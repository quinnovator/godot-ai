"""Parallel, failure-isolated Blender asset batches from reviewable JSON."""

from __future__ import annotations

import json
import math
import os
import re
from concurrent.futures import Future, ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Optional

from .blender import (
    DEFAULT_BLENDER_TIMEOUT,
    MANIFEST_SUFFIX,
    BlenderBuildError,
    _as_res_path,
    _normalize_parameters,
    _require_within_project,
    _resolve_project,
    _resolve_res_path,
    _resolve_script,
    _write_build_log,
    _write_json_atomic,
    build_blender_asset,
    locate_blender,
)

BLENDER_BATCH_SCHEMA_VERSION = 1
DEFAULT_BLENDER_BATCH_WORKERS = 4
MAX_BLENDER_BATCH_WORKERS = 32
MAX_BLENDER_BATCH_JOBS = 256

_ID_PATTERN = re.compile(r"^[a-z0-9][a-z0-9._-]{0,63}$")
_TOP_LEVEL_KEYS = {"schema_version", "name", "max_workers", "result", "defaults", "jobs"}
_DEFAULT_KEYS = {"timeout_seconds"}
_JOB_KEYS = {"id", "script", "output", "blend", "log", "parameters", "timeout_seconds"}


@dataclass(frozen=True)
class BlenderBatchJob:
    """A fully resolved job whose artifacts cannot conflict with another job."""

    job_id: str
    script: str
    output: str
    manifest: str
    blend: Optional[str]
    log: str
    parameters: Optional[dict[str, Any]]
    timeout: float

    def paths(self) -> dict[str, str]:
        value = {
            "log": self.log,
            "manifest": self.manifest,
            "output": self.output,
            "script": self.script,
        }
        if self.blend is not None:
            value["blend"] = self.blend
        return value

    def plan_record(self) -> dict[str, Any]:
        value: dict[str, Any] = {
            "id": self.job_id,
            "parameters": {} if self.parameters is None else self.parameters,
            "paths": self.paths(),
            "status": "planned",
            "timeout_seconds": self.timeout,
        }
        return value


@dataclass(frozen=True)
class BlenderBatchPlan:
    project: Path
    source_path: Path
    source: str
    name: str
    result_path: Path
    result: str
    max_workers: int
    jobs: tuple[BlenderBatchJob, ...]


def load_blender_batch(
    project: str | Path,
    manifest: str | Path,
    *,
    max_workers: Optional[int] = None,
) -> BlenderBatchPlan:
    """Load and completely validate a batch without launching Blender or writing files."""

    project_root = _resolve_project(project)
    source_path = _resolve_batch_source(project_root, manifest)
    try:
        value = json.loads(source_path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise BlenderBuildError("cannot read Blender batch manifest {0}: {1}".format(source_path, exc)) from exc
    except json.JSONDecodeError as exc:
        raise BlenderBuildError("Blender batch manifest is not valid JSON: {0}".format(exc)) from exc
    if not isinstance(value, dict):
        raise BlenderBuildError("Blender batch manifest must be a JSON object")
    _reject_unknown_keys(value, _TOP_LEVEL_KEYS, "batch manifest")
    if value.get("schema_version") != BLENDER_BATCH_SCHEMA_VERSION:
        raise BlenderBuildError(
            "Blender batch schema_version must be {0}".format(BLENDER_BATCH_SCHEMA_VERSION)
        )

    raw_name = value.get("name", source_path.stem)
    if not isinstance(raw_name, str) or not raw_name.strip() or len(raw_name.strip()) > 128:
        raise BlenderBuildError("Blender batch name must be a non-empty string of at most 128 characters")
    name = raw_name.strip()

    defaults = value.get("defaults", {})
    if not isinstance(defaults, dict):
        raise BlenderBuildError("Blender batch defaults must be a JSON object")
    _reject_unknown_keys(defaults, _DEFAULT_KEYS, "batch defaults")
    default_timeout = _positive_timeout(defaults.get("timeout_seconds", DEFAULT_BLENDER_TIMEOUT), "defaults.timeout_seconds")

    configured_workers = value.get("max_workers", DEFAULT_BLENDER_BATCH_WORKERS)
    requested_workers = configured_workers if max_workers is None else max_workers
    workers = _worker_count(requested_workers)

    raw_jobs = value.get("jobs")
    if not isinstance(raw_jobs, list) or not raw_jobs:
        raise BlenderBuildError("Blender batch jobs must be a non-empty JSON array")
    if len(raw_jobs) > MAX_BLENDER_BATCH_JOBS:
        raise BlenderBuildError("Blender batch exceeds the {0} job limit".format(MAX_BLENDER_BATCH_JOBS))

    raw_result = value.get("result")
    if raw_result is None:
        result_path = source_path.with_name(source_path.name + ".agent.result.json").resolve()
        _require_within_project(project_root, result_path, "batch result")
    else:
        result_path = _resolve_res_path(project_root, raw_result, ".json", "batch result")

    job_ids: set[str] = set()
    jobs: list[BlenderBatchJob] = []
    claimed_outputs: dict[str, str] = {}
    input_paths: dict[str, str] = {_path_key(source_path): "batch manifest"}
    _claim_output(claimed_outputs, result_path, "batch result")

    for index, raw_job in enumerate(raw_jobs):
        label = "jobs[{0}]".format(index)
        if not isinstance(raw_job, dict):
            raise BlenderBuildError("{0} must be a JSON object".format(label))
        _reject_unknown_keys(raw_job, _JOB_KEYS, label)

        job_id = raw_job.get("id")
        if not isinstance(job_id, str) or _ID_PATTERN.fullmatch(job_id) is None:
            raise BlenderBuildError(
                "{0}.id must match {1}".format(label, _ID_PATTERN.pattern)
            )
        if job_id in job_ids:
            raise BlenderBuildError("duplicate Blender batch job id: {0}".format(job_id))
        job_ids.add(job_id)

        script_value = raw_job.get("script")
        if not isinstance(script_value, str):
            raise BlenderBuildError("{0}.script must be a string".format(label))
        script_path = _resolve_script(project_root, script_value)
        input_paths[_path_key(script_path)] = "script for job {0}".format(job_id)

        output_value = raw_job.get("output")
        if not isinstance(output_value, str):
            raise BlenderBuildError("{0}.output must be a res:// path string".format(label))
        output_path = _resolve_res_path(project_root, output_value, ".glb", "{0}.output".format(label))
        output_manifest_path = output_path.with_name(output_path.name + MANIFEST_SUFFIX)

        blend_value = raw_job.get("blend")
        if blend_value is not None and not isinstance(blend_value, str):
            raise BlenderBuildError("{0}.blend must be a res:// path string".format(label))
        blend_path = (
            None
            if blend_value is None
            else _resolve_res_path(project_root, blend_value, ".blend", "{0}.blend".format(label))
        )

        log_value = raw_job.get("log")
        if log_value is None:
            log_path = output_path.with_name(output_path.name + ".agent.log")
        elif isinstance(log_value, str):
            log_path = _resolve_res_path(project_root, log_value, ".log", "{0}.log".format(label))
        else:
            raise BlenderBuildError("{0}.log must be a res:// path string".format(label))

        parameters_value = raw_job.get("parameters")
        if parameters_value is not None and not isinstance(parameters_value, Mapping):
            raise BlenderBuildError("{0}.parameters must be a JSON object".format(label))
        parameters = _normalize_parameters(parameters_value)
        timeout = _positive_timeout(raw_job.get("timeout_seconds", default_timeout), "{0}.timeout_seconds".format(label))

        _claim_output(claimed_outputs, output_path, "output for job {0}".format(job_id))
        _claim_output(claimed_outputs, output_manifest_path, "manifest for job {0}".format(job_id))
        _claim_output(claimed_outputs, log_path, "log for job {0}".format(job_id))
        if blend_path is not None:
            _claim_output(claimed_outputs, blend_path, "blend for job {0}".format(job_id))

        jobs.append(
            BlenderBatchJob(
                job_id=job_id,
                script=_as_res_path(project_root, script_path),
                output=_as_res_path(project_root, output_path),
                manifest=_as_res_path(project_root, output_manifest_path),
                blend=None if blend_path is None else _as_res_path(project_root, blend_path),
                log=_as_res_path(project_root, log_path),
                parameters=parameters,
                timeout=timeout,
            )
        )

    for key, output_label in claimed_outputs.items():
        input_label = input_paths.get(key)
        if input_label is not None:
            raise BlenderBuildError(
                "conflicting Blender batch path: {0} also overwrites {1}".format(output_label, input_label)
            )

    return BlenderBatchPlan(
        project=project_root,
        source_path=source_path,
        source=_as_res_path(project_root, source_path),
        name=name,
        result_path=result_path,
        result=_as_res_path(project_root, result_path),
        max_workers=min(workers, len(jobs)),
        jobs=tuple(jobs),
    )


def build_blender_batch(
    project: str | Path,
    manifest: str | Path,
    blender: Optional[str | Path] = None,
    *,
    max_workers: Optional[int] = None,
    dry_run: bool = False,
    environ: Optional[Mapping[str, str]] = None,
) -> dict[str, Any]:
    """Validate and execute independent jobs concurrently.

    Job failures are represented in the returned and persisted batch result;
    successful jobs remain installed and are never rolled back because a peer
    failed. Result ordering always matches the source manifest, not thread
    completion order.
    """

    plan = load_blender_batch(project, manifest, max_workers=max_workers)
    if dry_run:
        return _batch_result(plan, [job.plan_record() for job in plan.jobs], dry_run=True)

    try:
        executable = locate_blender(blender, environ=environ)
    except BlenderBuildError as exc:
        failure_records = [_failed_before_launch(plan, job, str(exc)) for job in plan.jobs]
        result = _batch_result(plan, failure_records, dry_run=False)
        _persist_batch_result(plan, result)
        return result

    records: list[Optional[dict[str, Any]]] = [None] * len(plan.jobs)
    with ThreadPoolExecutor(max_workers=plan.max_workers, thread_name_prefix="godot-blender") as executor:
        futures: dict[Future[dict[str, Any]], int] = {}
        for index, job in enumerate(plan.jobs):
            future = executor.submit(_run_job, plan, job, executable, environ)
            futures[future] = index
        for future in as_completed(futures):
            index = futures[future]
            job = plan.jobs[index]
            try:
                records[index] = future.result()
            except Exception as exc:  # Keep peer artifacts even on an unexpected worker failure.
                records[index] = _failed_unexpectedly(plan, job, exc)

    stable_records = [record for record in records if record is not None]
    result = _batch_result(plan, stable_records, dry_run=False)
    _persist_batch_result(plan, result)
    return result


def _run_job(
    plan: BlenderBatchPlan,
    job: BlenderBatchJob,
    executable: Path,
    environ: Optional[Mapping[str, str]],
) -> dict[str, Any]:
    try:
        asset_manifest = build_blender_asset(
            project=plan.project,
            script=job.script,
            output=job.output,
            blend=job.blend,
            blender=executable,
            environ=environ,
            timeout=job.timeout,
            parameters=job.parameters,
            log=job.log,
        )
    except (BlenderBuildError, ValueError) as exc:
        return {
            "error": str(exc),
            "id": job.job_id,
            "parameters": {} if job.parameters is None else job.parameters,
            "paths": job.paths(),
            "status": "failed",
            "timeout_seconds": job.timeout,
        }
    return {
        "asset_manifest": asset_manifest,
        "id": job.job_id,
        "parameters": {} if job.parameters is None else job.parameters,
        "paths": job.paths(),
        "status": "succeeded",
        "timeout_seconds": job.timeout,
    }


def _failed_before_launch(plan: BlenderBatchPlan, job: BlenderBatchJob, error: str) -> dict[str, Any]:
    log_path = _resolve_res_path(plan.project, job.log, ".log", "job log")
    log_path.parent.mkdir(parents=True, exist_ok=True)
    _write_build_log(log_path, "failed", error=error)
    return {
        "error": error,
        "id": job.job_id,
        "parameters": {} if job.parameters is None else job.parameters,
        "paths": job.paths(),
        "status": "failed",
        "timeout_seconds": job.timeout,
    }


def _failed_unexpectedly(plan: BlenderBatchPlan, job: BlenderBatchJob, exc: Exception) -> dict[str, Any]:
    error = "unexpected batch worker failure: {0}".format(exc)
    log_path = _resolve_res_path(plan.project, job.log, ".log", "job log")
    log_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        _write_build_log(log_path, "failed", error=error)
    except OSError:
        pass
    return {
        "error": error,
        "id": job.job_id,
        "parameters": {} if job.parameters is None else job.parameters,
        "paths": job.paths(),
        "status": "failed",
        "timeout_seconds": job.timeout,
    }


def _batch_result(
    plan: BlenderBatchPlan,
    records: list[dict[str, Any]],
    *,
    dry_run: bool,
) -> dict[str, Any]:
    succeeded = sum(record["status"] == "succeeded" for record in records)
    failed = sum(record["status"] == "failed" for record in records)
    planned = sum(record["status"] == "planned" for record in records)
    return {
        "batch_schema_version": BLENDER_BATCH_SCHEMA_VERSION,
        "dry_run": dry_run,
        "jobs": records,
        "manifest": plan.source,
        "max_workers": plan.max_workers,
        "name": plan.name,
        "ok": failed == 0,
        "result": plan.result,
        "status": "planned" if dry_run else ("succeeded" if failed == 0 else "partial_failure"),
        "summary": {
            "failed": failed,
            "planned": planned,
            "succeeded": succeeded,
            "total": len(records),
        },
    }


def _persist_batch_result(plan: BlenderBatchPlan, result: Mapping[str, Any]) -> None:
    plan.result_path.parent.mkdir(parents=True, exist_ok=True)
    _write_json_atomic(plan.result_path, result)


def _resolve_batch_source(project: Path, manifest: str | Path) -> Path:
    raw = str(manifest)
    if raw.startswith("res://"):
        path = _resolve_res_path(project, raw, ".json", "BATCH")
    else:
        supplied = Path(raw).expanduser()
        path = (supplied if supplied.is_absolute() else project / supplied).resolve()
        _require_within_project(project, path, "BATCH")
        if path.suffix.lower() != ".json":
            raise BlenderBuildError("BATCH must be a JSON file")
    if not path.is_file():
        raise BlenderBuildError("Blender batch manifest does not exist: {0}".format(path))
    return path


def _claim_output(claims: dict[str, str], path: Path, label: str) -> None:
    key = _path_key(path)
    previous = claims.get(key)
    if previous is not None:
        raise BlenderBuildError(
            "conflicting Blender batch outputs: {0} and {1} resolve to {2}".format(previous, label, path)
        )
    claims[key] = label


def _path_key(path: Path) -> str:
    # Case-fold conservatively so a manifest is also safe on the default
    # case-insensitive macOS and Windows filesystems when authored on Linux.
    return os.path.normpath(str(path.resolve())).casefold()


def _reject_unknown_keys(value: Mapping[str, Any], allowed: set[str], label: str) -> None:
    unknown = sorted(str(key) for key in value if key not in allowed)
    if unknown:
        raise BlenderBuildError("{0} has unknown fields: {1}".format(label, ", ".join(unknown)))


def _positive_timeout(value: Any, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise BlenderBuildError("{0} must be a positive finite number".format(label))
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise BlenderBuildError("{0} must be a positive finite number".format(label))
    return number


def _worker_count(value: Any) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise BlenderBuildError("max_workers must be an integer")
    if value < 1 or value > MAX_BLENDER_BATCH_WORKERS:
        raise BlenderBuildError(
            "max_workers must be between 1 and {0}".format(MAX_BLENDER_BATCH_WORKERS)
        )
    return int(value)
