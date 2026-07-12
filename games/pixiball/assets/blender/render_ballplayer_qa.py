"""Render deterministic visual-QA turntable and action contact frames.

Usage:
  Blender --background ballplayer.blend --python render_ballplayer_qa.py -- \
    --output-dir /tmp/pixiball-ballplayer-qa

The script never changes or saves the opened production file.  It creates a
neutral studio setup and writes one PNG per review pose plus a JSON receipt.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector

REVIEW_POSES = (
    ("rest_front", None, 1, (0.0, 4.8, 1.70), 1.03),
    ("rest_three_quarter", None, 1, (3.25, 4.25, 2.05), 1.03),
    ("field_ready_set", "field_ready", 8, (3.25, 4.25, 2.05), 1.03),
    ("pitch_balance", "pitch", 16, (3.25, 4.25, 2.05), 1.03),
    ("pitch_hand_break", "pitch", 19, (3.25, 4.25, 2.05), 1.03),
    ("pitch_stride", "pitch", 22, (3.25, 4.25, 2.05), 1.03),
    ("pitch_plant", "pitch", 24, (3.25, 4.25, 2.05), 1.03),
    ("pitch_late_cock", "pitch", 26, (3.25, 4.25, 2.05), 1.03),
    ("pitch_release", "pitch", 28, (3.25, 4.25, 2.05), 1.03),
    ("pitch_extension", "pitch", 29, (3.25, 4.25, 2.05), 1.03),
    ("pitch_follow_through", "pitch", 34, (3.25, 4.25, 2.05), 1.03),
    ("pitch_finish", "pitch", 45, (3.25, 4.25, 2.05), 1.03),
    ("field_throw_transfer", "field_throw", 11, (-3.25, 4.25, 2.05), 1.03),
    ("field_throw_cock", "field_throw", 16, (-3.25, 4.25, 2.05), 1.03),
    ("field_throw_release", "field_throw", 18, (-3.25, 4.25, 2.05), 1.03),
    ("field_throw_follow_through", "field_throw", 24, (-3.25, 4.25, 2.05), 1.03),
    ("swing_load", "swing", 1, (3.25, 4.25, 2.05), 1.03),
    ("swing_contact", "swing", 19, (3.25, 4.25, 2.05), 1.03),
    ("swing_finish", "swing", 25, (3.25, 4.25, 2.05), 1.03),
    ("catch_contact", "catch", 14, (3.25, 4.25, 2.05), 1.03),
    ("run_stride", "run", 1, (3.25, 4.25, 2.05), 1.03),
    ("celebrate_peak", "celebrate", 24, (3.25, 4.25, 2.05), 1.12),
    ("celebrate_fist_pump", "celebrate", 32, (3.25, 4.25, 2.05), 1.03),
    ("slide_entry", "slide", 16, (2.7, 3.8, 1.45), 0.66),
    ("slide_contact", "slide", 22, (2.7, 3.8, 1.45), 0.58),
)


def arguments() -> argparse.Namespace:
    raw = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--size", type=int, default=512)
    parser.add_argument("--telemetry-only", action="store_true")
    return parser.parse_args(raw)


def look_at(obj: bpy.types.Object, point: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(point) - obj.location).to_track_quat("-Z", "Y").to_euler()


def material(name: str, color: tuple[float, float, float], roughness: float) -> bpy.types.Material:
    value = bpy.data.materials.new(name)
    value.diffuse_color = (*color, 1.0)
    value.use_nodes = True
    shader = value.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Roughness"].default_value = roughness
    return value


def add_studio() -> tuple[bpy.types.Object, bpy.types.Object]:
    collection = bpy.data.collections.new("__QA_STUDIO__")
    bpy.context.scene.collection.children.link(collection)

    floor_mesh = bpy.data.meshes.new("__QA_FLOOR_MESH__")
    floor = bpy.data.objects.new("__QA_FLOOR__", floor_mesh)
    collection.objects.link(floor)
    vertices = [(-3.0, -3.0, 0.0), (3.0, -3.0, 0.0), (3.0, 3.0, 0.0), (-3.0, 3.0, 0.0)]
    floor_mesh.from_pydata(vertices, [], [(0, 1, 2, 3)])
    floor_mesh.materials.append(material("__QA_FLOOR_MAT__", (0.055, 0.070, 0.090), 0.74))

    camera_data = bpy.data.cameras.new("__QA_CAMERA_DATA__")
    camera_data.lens = 66.0
    camera = bpy.data.objects.new("__QA_CAMERA__", camera_data)
    collection.objects.link(camera)
    bpy.context.scene.camera = camera

    def area(name: str, location: tuple[float, float, float], energy: float, color, size: float):
        light_data = bpy.data.lights.new(name + "_DATA", "AREA")
        light_data.energy = energy
        light_data.color = color
        light_data.shape = "DISK"
        light_data.size = size
        light = bpy.data.objects.new(name, light_data)
        light.location = location
        look_at(light, (0.0, 0.0, 1.05))
        collection.objects.link(light)

    area("__QA_KEY__", (3.8, 3.4, 5.5), 1050.0, (1.0, 0.78, 0.60), 4.0)
    area("__QA_FILL__", (-4.0, 2.2, 3.0), 720.0, (0.52, 0.72, 1.0), 3.2)
    area("__QA_RIM__", (0.0, -4.0, 4.2), 900.0, (0.40, 0.62, 1.0), 2.8)
    return floor, camera


def pose_point(rig: bpy.types.Object, bone_name: str) -> Vector:
    return rig.matrix_world @ rig.pose.bones[bone_name].head


def reset_pose(rig: bpy.types.Object) -> None:
    """Restore the authored rest pose after an action is detached.

    Blender intentionally keeps the last evaluated property values when an
    action slot is cleared.  Telemetry ends on the pitching finish, so the old
    rest renders accidentally showed that finish pose unless every bone was
    reset explicitly.
    """

    for pose_bone in rig.pose.bones:
        pose_bone.location = (0.0, 0.0, 0.0)
        pose_bone.scale = (1.0, 1.0, 1.0)
        if pose_bone.rotation_mode == "QUATERNION":
            pose_bone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        else:
            pose_bone.rotation_euler = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()


def pitch_telemetry(scene: bpy.types.Scene, rig: bpy.types.Object, action: bpy.types.Action) -> dict:
    """Sample the complete delivery and enforce the core motion contract."""

    frame_start = int(round(action.frame_range[0]))
    frame_end = int(round(action.frame_range[1]))
    release_frame = int(action.get("marker_ball_release", 0))
    plant_frame = int(action.get("marker_stride_plant", 0))
    if release_frame <= frame_start or plant_frame <= frame_start:
        raise RuntimeError("pitch action is missing release or stride-plant metadata")

    rig.animation_data.action = action
    samples = []
    previous_hand = None
    previous_root = None
    fps = float(scene.render.fps) / max(1.0, float(scene.render.fps_base))
    for frame in range(frame_start, frame_end + 1):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        hand = pose_point(rig, "socket_ball")
        root = pose_point(rig, "root")
        lead_toe = pose_point(rig, "toe.L")
        speed = 0.0 if previous_hand is None else (hand - previous_hand).length * fps
        forward_speed = 0.0 if previous_hand is None else (hand.y - previous_hand.y) * fps
        root_forward_speed = 0.0 if previous_root is None else (root.y - previous_root.y) * fps
        samples.append(
            {
                "frame": frame,
                "hand_m": [round(value, 6) for value in hand],
                "hand_speed_mps": round(speed, 6),
                "hand_forward_mps": round(forward_speed, 6),
                "root_m": [round(value, 6) for value in root],
                "root_forward_mps": round(root_forward_speed, 6),
                "lead_toe_m": [round(value, 6) for value in lead_toe],
            }
        )
        previous_hand = hand.copy()
        previous_root = root.copy()

    by_frame = {sample["frame"]: sample for sample in samples}
    release = by_frame[release_frame]
    plant = by_frame[plant_frame]
    peak_forward = max(samples, key=lambda sample: sample["hand_forward_mps"])
    peak_speed = max(samples, key=lambda sample: sample["hand_speed_mps"])
    plant_toe = Vector(plant["lead_toe_m"])
    plant_drift = max(
        (Vector(by_frame[frame]["lead_toe_m"]) - plant_toe).length
        for frame in range(plant_frame, release_frame + 1)
    )
    start_root_y = float(samples[0]["root_m"][1])
    end_root_y = float(samples[-1]["root_m"][1])
    root_excursion = max(abs(float(sample["root_m"][1]) - start_root_y) for sample in samples)
    root_recovery = abs(end_root_y - start_root_y)
    max_root_step = max(
        abs(float(by_frame[frame]["root_m"][1]) - float(by_frame[frame - 1]["root_m"][1]))
        for frame in range(frame_start + 1, frame_end + 1)
    )
    early_peak = max(by_frame[frame]["hand_speed_mps"] for frame in range(frame_start + 1, 17))
    # The frame immediately before release is an intentional sampled smear/
    # acceleration beat.  Bound the gather through late cock, then let the
    # existing peak-frame assertion govern the final two-frame whip.
    gather_peak = max(by_frame[frame]["hand_speed_mps"] for frame in range(17, release_frame - 1))
    post_release_peak = max(
        by_frame[frame]["hand_speed_mps"] for frame in range(release_frame + 1, frame_end + 1)
    )

    assertions = [
        {
            "name": "release_is_peak_forward_frame",
            "passed": abs(int(peak_forward["frame"]) - release_frame) <= 1,
            "actual": int(peak_forward["frame"]),
            "expected": release_frame,
        },
        {
            "name": "release_has_throwing_hand_speed",
            "passed": float(release["hand_speed_mps"]) >= 12.0,
            "actual": float(release["hand_speed_mps"]),
            "minimum": 12.0,
        },
        {
            "name": "delivery_has_controlled_drive",
            "passed": 0.15 <= root_excursion <= 0.35,
            "actual": round(root_excursion, 6),
            "minimum": 0.15,
            "maximum": 0.35,
        },
        {
            "name": "lead_foot_stays_planted",
            "passed": plant_drift <= 0.02,
            "actual": round(plant_drift, 6),
            "maximum": 0.02,
        },
        {
            "name": "delivery_recovers_in_place",
            "passed": root_recovery <= 0.05,
            "actual": round(root_recovery, 6),
            "maximum": 0.05,
        },
        {
            "name": "root_motion_is_continuous",
            "passed": max_root_step <= 0.055,
            "actual": round(max_root_step, 6),
            "maximum": 0.055,
        },
        {
            "name": "early_delivery_is_stable",
            "passed": early_peak <= 1.0,
            "actual": round(early_peak, 6),
            "maximum": 1.0,
        },
        {
            "name": "gather_acceleration_is_bounded",
            "passed": gather_peak <= float(release["hand_speed_mps"]) * 0.55,
            "actual": round(gather_peak, 6),
            "maximum": round(float(release["hand_speed_mps"]) * 0.55, 6),
        },
        {
            "name": "follow_through_decelerates",
            "passed": post_release_peak <= float(release["hand_speed_mps"]) * 0.70,
            "actual": round(post_release_peak, 6),
            "maximum": round(float(release["hand_speed_mps"]) * 0.70, 6),
        },
    ]
    return {
        "frame_start": frame_start,
        "frame_end": frame_end,
        "plant_frame": plant_frame,
        "release_frame": release_frame,
        "peak_forward_frame": int(peak_forward["frame"]),
        "peak_speed_frame": int(peak_speed["frame"]),
        "release_speed_mps": float(release["hand_speed_mps"]),
        "release_forward_mps": float(release["hand_forward_mps"]),
        "root_excursion_m": round(root_excursion, 6),
        "root_recovery_m": round(root_recovery, 6),
        "max_root_step_m": round(max_root_step, 6),
        "early_peak_speed_mps": round(early_peak, 6),
        "gather_peak_speed_mps": round(gather_peak, 6),
        "plant_drift_m": round(plant_drift, 6),
        "assertions": assertions,
        "samples": samples,
    }


def main() -> None:
    args = arguments()
    output_dir = Path(args.output_dir).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = args.size
    scene.render.resolution_y = args.size
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.world.color = (0.018, 0.024, 0.038)

    rig = bpy.data.objects.get("Ballplayer_Rig")
    if rig is None:
        raise RuntimeError("Ballplayer_Rig is missing")
    actions = {action.name: action for action in bpy.data.actions}
    rig.animation_data_create()

    receipt = {"blend": bpy.data.filepath, "renders": []}
    receipt["pitch_telemetry"] = pitch_telemetry(scene, rig, actions["pitch"])
    if not args.telemetry_only:
        _, camera = add_studio()
        for name, action_name, frame, location, target_z in REVIEW_POSES:
            rig.animation_data.action = actions.get(action_name) if action_name else None
            bat = bpy.data.objects.get("Bat_Skinned")
            glove = bpy.data.objects.get("Glove_Skinned")
            if bat is not None:
                bat.hide_render = action_name != "swing" and action_name is not None
            if glove is not None:
                glove.hide_render = action_name == "swing"
            scene.frame_set(frame)
            if action_name is None:
                reset_pose(rig)
            camera.location = location
            look_at(camera, (0.0, 0.0, target_z))
            path = output_dir / (name + ".png")
            scene.render.filepath = str(path)
            bpy.ops.render.render(write_still=True)
            receipt["renders"].append(
                {"name": name, "action": action_name, "frame": frame, "target_z": target_z, "path": str(path)}
            )

    (output_dir / "qa_receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    failures = [item for item in receipt["pitch_telemetry"]["assertions"] if not item["passed"]]
    summary = receipt["pitch_telemetry"]
    print(
        "PIXIBALL_PITCH_QA release=%d peak=%d speed=%.3f root_excursion=%.3f recovery=%.3f plant_drift=%.6f"
        % (
            summary["release_frame"],
            summary["peak_forward_frame"],
            summary["release_speed_mps"],
            summary["root_excursion_m"],
            summary["root_recovery_m"],
            summary["plant_drift_m"],
        )
    )
    if failures:
        raise RuntimeError("pitch telemetry failed: " + ", ".join(item["name"] for item in failures))


if __name__ == "__main__":
    main()
