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
    ("pitch_balance", "pitch", 14, (3.25, 4.25, 2.05), 1.03),
    ("pitch_release", "pitch", 24, (3.25, 4.25, 2.05), 1.03),
    ("pitch_follow_through", "pitch", 31, (3.25, 4.25, 2.05), 1.03),
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


def main() -> None:
    args = arguments()
    output_dir = Path(args.output_dir).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = args.size
    scene.render.resolution_y = args.size
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.world.color = (0.018, 0.024, 0.038)

    _, camera = add_studio()
    rig = bpy.data.objects.get("Ballplayer_Rig")
    if rig is None:
        raise RuntimeError("Ballplayer_Rig is missing")
    actions = {action.name: action for action in bpy.data.actions}
    rig.animation_data_create()

    receipt = {"blend": bpy.data.filepath, "renders": []}
    for name, action_name, frame, location, target_z in REVIEW_POSES:
        rig.animation_data.action = actions.get(action_name) if action_name else None
        bat = bpy.data.objects.get("Bat_Skinned")
        glove = bpy.data.objects.get("Glove_Skinned")
        if bat is not None:
            bat.hide_render = action_name != "swing" and action_name is not None
        if glove is not None:
            glove.hide_render = action_name == "swing"
        scene.frame_set(frame)
        camera.location = location
        look_at(camera, (0.0, 0.0, target_z))
        path = output_dir / (name + ".png")
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        receipt["renders"].append(
            {"name": name, "action": action_name, "frame": frame, "target_z": target_z, "path": str(path)}
        )

    (output_dir / "qa_receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
