"""Bounded, reproducible Blender companion builds for Godot projects."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path, PurePosixPath
from typing import Any, Mapping, Optional, Sequence

from .client import GodotAgentError

BLENDER_INVOCATION_SCHEMA_VERSION = 1
DEFAULT_BLENDER_TIMEOUT = 15 * 60.0
MANIFEST_SUFFIX = ".agent.json"
_LOG_TAIL_CHARACTERS = 4000
_MAX_PARAMETERS_BYTES = 64 * 1024


class BlenderBuildError(GodotAgentError):
    """A Blender asset build could not be completed or validated."""


def locate_blender(
    explicit: Optional[str | Path] = None,
    environ: Optional[Mapping[str, str]] = None,
) -> Path:
    """Locate Blender without installing or modifying the host.

    Discovery order is an explicit value, ``BLENDER``, ``PATH``, and standard
    macOS application locations. An explicitly selected but invalid executable
    is an error rather than a reason to silently fall through to another copy.
    """

    environment = os.environ if environ is None else environ
    if explicit is not None:
        return _resolve_executable(str(explicit), "--blender")

    configured = environment.get("BLENDER")
    if configured:
        return _resolve_executable(configured, "BLENDER")

    on_path = shutil.which("blender")
    if on_path:
        return _validate_executable(Path(on_path), "PATH")

    if sys.platform == "darwin":
        candidates = [
            Path("/Applications/Blender.app/Contents/MacOS/Blender"),
            Path.home() / "Applications/Blender.app/Contents/MacOS/Blender",
        ]
        candidates.extend(sorted(Path("/Applications").glob("Blender*.app/Contents/MacOS/Blender")))
        for candidate in candidates:
            if candidate.is_file() and os.access(str(candidate), os.X_OK):
                return candidate.resolve()

    raise BlenderBuildError(
        "Blender executable not found; pass --blender, set BLENDER, add blender "
        "to PATH, or place Blender.app in /Applications"
    )


def build_blender_asset(
    project: str | Path,
    script: str | Path,
    output: str,
    blend: Optional[str] = None,
    blender: Optional[str | Path] = None,
    *,
    environ: Optional[Mapping[str, str]] = None,
    timeout: float = DEFAULT_BLENDER_TIMEOUT,
    parameters: Optional[Mapping[str, Any]] = None,
    log: Optional[str] = None,
) -> dict[str, Any]:
    """Run one authored Python script in Blender and export a validated GLB.

    Outputs are produced under temporary names in their destination
    directories. Existing assets are replaced only after Blender succeeds and
    all requested files validate.
    """

    if timeout <= 0:
        raise ValueError("timeout must be greater than zero")

    project_root = _resolve_project(project)
    script_path = _resolve_script(project_root, script)
    output_path = _resolve_res_path(project_root, output, ".glb", "--output")
    blend_path = None if blend is None else _resolve_res_path(project_root, blend, ".blend", "--blend")
    log_path = None if log is None else _resolve_res_path(project_root, log, ".log", "log")
    normalized_parameters = _normalize_parameters(parameters)

    script_hash = _sha256(script_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if blend_path is not None:
        blend_path.parent.mkdir(parents=True, exist_ok=True)
    if log_path is not None:
        log_path.parent.mkdir(parents=True, exist_ok=True)

    staged_output_path = _new_staging_path(output_path)
    staged_output: Optional[Path] = staged_output_path
    staged_blend = None if blend_path is None else _new_staging_path(blend_path)
    bootstrap = Path(__file__).with_name("blender_bootstrap.py").resolve()
    if not bootstrap.is_file():
        raise BlenderBuildError("bundled Blender bootstrap is missing: {0}".format(bootstrap))

    completed: Optional[subprocess.CompletedProcess[str]] = None
    try:
        executable = locate_blender(blender, environ=environ)
        with tempfile.TemporaryDirectory(prefix="godot-agent-blender-") as temporary:
            receipt_path = Path(temporary) / "receipt.json"
            parameters_path = None
            if normalized_parameters is not None:
                parameters_path = Path(temporary) / "parameters.json"
                _write_json_atomic(parameters_path, normalized_parameters)
            command = _build_command(
                executable=executable,
                bootstrap=bootstrap,
                script=script_path,
                output=staged_output_path,
                blend=staged_blend,
                parameters=parameters_path,
                receipt=receipt_path,
            )
            try:
                completed = subprocess.run(
                    command,
                    cwd=str(project_root),
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    errors="replace",
                    timeout=timeout,
                    check=False,
                    shell=False,
                )
            except subprocess.TimeoutExpired as exc:
                raise BlenderBuildError("Blender build exceeded the {0:g} second timeout".format(timeout)) from exc
            except OSError as exc:
                raise BlenderBuildError("could not start Blender executable {0}: {1}".format(executable, exc)) from exc

            if completed.returncode != 0:
                log = _log_tail(completed.stderr or completed.stdout or "")
                detail = "Blender exited with status {0}".format(completed.returncode)
                if log:
                    detail += ":\n" + log
                raise BlenderBuildError(detail)

            blender_version = _read_receipt(receipt_path)
            _validate_glb(staged_output_path)
            if staged_blend is not None:
                _validate_blend(staged_blend)

        if _sha256(script_path) != script_hash:
            raise BlenderBuildError("authored Blender script changed during the build")

        if staged_blend is not None and blend_path is not None:
            os.replace(str(staged_blend), str(blend_path))
            staged_blend = None
        os.replace(str(staged_output_path), str(output_path))
        staged_output = None

        manifest_path = output_path.with_name(output_path.name + MANIFEST_SUFFIX)
        paths: dict[str, str] = {
            "manifest": _as_res_path(project_root, manifest_path),
            "output": _as_res_path(project_root, output_path),
            "script": _as_res_path(project_root, script_path),
        }
        hashes = {
            "output": _sha256(output_path),
            "script": script_hash,
        }
        if blend_path is not None:
            paths["blend"] = _as_res_path(project_root, blend_path)
            hashes["blend"] = _sha256(blend_path)
        if log_path is not None:
            _write_build_log(log_path, "succeeded", completed=completed)
            paths["log"] = _as_res_path(project_root, log_path)
            hashes["log"] = _sha256(log_path)

        manifest: dict[str, Any] = {
            "blender_version": blender_version,
            "invocation_schema_version": BLENDER_INVOCATION_SCHEMA_VERSION,
            "paths": paths,
            "sha256": hashes,
        }
        if normalized_parameters is not None:
            manifest["parameters"] = normalized_parameters
        _write_json_atomic(manifest_path, manifest)
        return manifest
    except BlenderBuildError as exc:
        if log_path is not None:
            try:
                _write_build_log(log_path, "failed", completed=completed, error=str(exc))
            except OSError:
                # The original build error is more useful than a secondary
                # failure while attempting to preserve its diagnostic log.
                pass
        raise
    finally:
        if staged_output is not None:
            staged_output.unlink(missing_ok=True)
        if staged_blend is not None:
            staged_blend.unlink(missing_ok=True)


def _resolve_project(project: str | Path) -> Path:
    root = Path(project).expanduser().resolve()
    if not root.is_dir():
        raise BlenderBuildError("project directory does not exist: {0}".format(root))
    return root


def _resolve_script(project: Path, value: str | Path) -> Path:
    raw = str(value)
    if raw.startswith("res://"):
        path = _resolve_res_path(project, raw, ".py", "SCRIPT")
    else:
        supplied = Path(raw).expanduser()
        path = (supplied if supplied.is_absolute() else project / supplied).resolve()
        _require_within_project(project, path, "SCRIPT")
        if path.suffix.lower() != ".py":
            raise BlenderBuildError("SCRIPT must be a Python .py file")
    if not path.is_file():
        raise BlenderBuildError("Blender script does not exist: {0}".format(path))
    return path


def _resolve_res_path(project: Path, raw: str, suffix: str, label: str) -> Path:
    if not isinstance(raw, str) or not raw.startswith("res://"):
        raise BlenderBuildError("{0} must be a res:// project path".format(label))
    relative = PurePosixPath(raw[len("res://") :])
    if not relative.parts or relative.is_absolute() or ".." in relative.parts:
        raise BlenderBuildError("{0} must stay within the project".format(label))
    path = project.joinpath(*relative.parts).resolve()
    _require_within_project(project, path, label)
    if path.suffix.lower() != suffix:
        raise BlenderBuildError("{0} must end in {1}".format(label, suffix))
    return path


def _require_within_project(project: Path, path: Path, label: str) -> None:
    try:
        path.relative_to(project)
    except ValueError as exc:
        raise BlenderBuildError("{0} must stay within the project".format(label)) from exc


def _as_res_path(project: Path, path: Path) -> str:
    try:
        relative = path.relative_to(project)
    except ValueError as exc:
        raise BlenderBuildError("manifest path escaped the project: {0}".format(path)) from exc
    return "res://" + relative.as_posix()


def _resolve_executable(raw: str, source: str) -> Path:
    expanded = Path(raw).expanduser()
    if expanded.suffix.lower() == ".app" and expanded.is_dir():
        expanded = expanded / "Contents/MacOS/Blender"
    if expanded.is_absolute() or expanded.parent != Path("."):
        return _validate_executable(expanded, source)
    found = shutil.which(raw)
    if found is None:
        raise BlenderBuildError("{0} does not name an executable: {1}".format(source, raw))
    return _validate_executable(Path(found), source)


def _validate_executable(path: Path, source: str) -> Path:
    resolved = path.resolve()
    if not resolved.is_file() or not os.access(str(resolved), os.X_OK):
        raise BlenderBuildError("{0} does not point to an executable file: {1}".format(source, path))
    return resolved


def _new_staging_path(target: Path) -> Path:
    descriptor, raw_path = tempfile.mkstemp(
        prefix=".{0}.agent-".format(target.stem),
        suffix=target.suffix,
        dir=str(target.parent),
    )
    os.close(descriptor)
    path = Path(raw_path)
    path.unlink()
    return path


def _build_command(
    *,
    executable: Path,
    bootstrap: Path,
    script: Path,
    output: Path,
    blend: Optional[Path],
    parameters: Optional[Path],
    receipt: Path,
) -> Sequence[str]:
    command = [
        str(executable),
        "--background",
        "--factory-startup",
        "--python-exit-code",
        "1",
        "--python",
        str(bootstrap),
        "--",
        "--schema-version",
        str(BLENDER_INVOCATION_SCHEMA_VERSION),
        "--script",
        str(script),
        "--output",
        str(output),
        "--receipt",
        str(receipt),
    ]
    if blend is not None:
        command.extend(["--blend", str(blend)])
    if parameters is not None:
        command.extend(["--parameters", str(parameters)])
    return command


def _read_receipt(path: Path) -> str:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise BlenderBuildError("Blender did not write a valid build receipt") from exc
    if not isinstance(value, dict):
        raise BlenderBuildError("Blender build receipt must be a JSON object")
    if value.get("invocation_schema_version") != BLENDER_INVOCATION_SCHEMA_VERSION:
        raise BlenderBuildError("Blender build receipt has the wrong invocation schema version")
    version = value.get("blender_version")
    if not isinstance(version, str) or not version.strip():
        raise BlenderBuildError("Blender build receipt is missing blender_version")
    return version.strip()


def _validate_glb(path: Path) -> None:
    try:
        size = path.stat().st_size
        with path.open("rb") as handle:
            header = handle.read(12)
            if len(header) != 12:
                raise BlenderBuildError("exported GLB is shorter than its header")
            magic, version, declared_size = struct.unpack("<4sII", header)
            if magic != b"glTF" or version != 2:
                raise BlenderBuildError("exported GLB is not a glTF 2.0 binary")
            if declared_size != size:
                raise BlenderBuildError("exported GLB length header does not match its file size")

            offset = 12
            chunk_index = 0
            while offset < size:
                chunk_header = handle.read(8)
                if len(chunk_header) != 8:
                    raise BlenderBuildError("exported GLB contains a truncated chunk header")
                chunk_length, chunk_type = struct.unpack("<I4s", chunk_header)
                if chunk_length % 4 != 0 or offset + 8 + chunk_length > size:
                    raise BlenderBuildError("exported GLB contains an invalid chunk length")
                if chunk_index == 0 and chunk_type != b"JSON":
                    raise BlenderBuildError("exported GLB does not start with a JSON chunk")
                handle.seek(chunk_length, os.SEEK_CUR)
                offset += 8 + chunk_length
                chunk_index += 1
            if chunk_index == 0:
                raise BlenderBuildError("exported GLB contains no chunks")
    except OSError as exc:
        raise BlenderBuildError("exported GLB is missing or unreadable: {0}".format(path)) from exc


def _validate_blend(path: Path) -> None:
    try:
        with path.open("rb") as handle:
            header = handle.read(17)
    except OSError as exc:
        raise BlenderBuildError("saved .blend is missing or unreadable: {0}".format(path)) from exc

    legacy_header = (
        len(header) >= 12
        and header.startswith(b"BLENDER")
        and header[7:8] in (b"_", b"-")
        and header[8:9] in (b"v", b"V")
        and header[9:12].isdigit()
    )
    extended_header = (
        len(header) >= 17
        and header.startswith(b"BLENDER17")
        and header[9:10] == b"-"
        and header[10:12] == b"01"
        and header[12:13] == b"v"
        and header[13:17].isdigit()
    )
    if not (legacy_header or extended_header):
        raise BlenderBuildError("saved .blend has an invalid Blender header")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _normalize_parameters(parameters: Optional[Mapping[str, Any]]) -> Optional[dict[str, Any]]:
    if parameters is None:
        return None
    if not isinstance(parameters, Mapping):
        raise BlenderBuildError("Blender recipe parameters must be a JSON object")
    try:
        encoded = json.dumps(
            dict(parameters),
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        ).encode("utf-8")
    except (TypeError, ValueError) as exc:
        raise BlenderBuildError("Blender recipe parameters must contain only finite JSON values") from exc
    if len(encoded) > _MAX_PARAMETERS_BYTES:
        raise BlenderBuildError("Blender recipe parameters exceed the 65536 byte limit")
    value = json.loads(encoded.decode("utf-8"))
    if not isinstance(value, dict):  # Defensive: the Mapping check should guarantee this.
        raise BlenderBuildError("Blender recipe parameters must be a JSON object")
    return value


def _write_build_log(
    path: Path,
    status: str,
    *,
    completed: Optional[subprocess.CompletedProcess[str]] = None,
    error: Optional[str] = None,
) -> None:
    value: dict[str, Any] = {
        "invocation_schema_version": BLENDER_INVOCATION_SCHEMA_VERSION,
        "returncode": None if completed is None else completed.returncode,
        "status": status,
        "stderr": "" if completed is None else _log_tail(completed.stderr or ""),
        "stdout": "" if completed is None else _log_tail(completed.stdout or ""),
    }
    if error is not None:
        value["error"] = error
    _write_json_atomic(path, value)


def _write_json_atomic(path: Path, value: Mapping[str, Any]) -> None:
    data = (
        json.dumps(
            value,
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
            allow_nan=False,
        )
        + "\n"
    )
    descriptor, temporary = tempfile.mkstemp(prefix=".{0}.".format(path.name), suffix=".tmp", dir=str(path.parent))
    temporary_path = Path(temporary)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(str(temporary_path), str(path))
    finally:
        temporary_path.unlink(missing_ok=True)


def _log_tail(value: str) -> str:
    cleaned = value.strip()
    if len(cleaned) <= _LOG_TAIL_CHARACTERS:
        return cleaned
    return "..." + cleaned[-_LOG_TAIL_CHARACTERS:]
