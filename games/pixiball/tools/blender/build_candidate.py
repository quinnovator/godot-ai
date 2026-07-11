"""Build one parameterized Pixiball player or equipment candidate.

The batch runner supplies a JSON file through
``GODOT_AGENT_BLENDER_PARAMETERS``.  Keeping the recipe and parameters
separate lets several modeling agents explore candidates concurrently while
the resulting source, logs, and provenance stay deterministic and reviewable.
"""

from __future__ import annotations

import json
import math
import os
import re

import bpy
from mathutils import Vector

PARAMETERS_ENV = "GODOT_AGENT_BLENDER_PARAMETERS"
STYLE = "high_resolution_pixel_volume"
ID_PATTERN = re.compile(r"^[a-z0-9][a-z0-9-]{0,47}$")


def read_parameters():
    path = os.environ.get(PARAMETERS_ENV)
    if not path:
        raise RuntimeError(PARAMETERS_ENV + " was not provided")
    with open(path, encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise RuntimeError("candidate parameters must be a JSON object")

    expected = {
        "asset_type",
        "candidate_id",
        "equipment_kind",
        "palette",
        "proportions",
        "role",
        "stance",
        "style",
    }
    unknown = sorted(set(value) - expected)
    if unknown:
        raise RuntimeError("unknown candidate parameters: " + ", ".join(unknown))
    candidate_id = value.get("candidate_id")
    if not isinstance(candidate_id, str) or ID_PATTERN.fullmatch(candidate_id) is None:
        raise RuntimeError("candidate_id must be a lowercase slug")
    if value.get("style", STYLE) != STYLE:
        raise RuntimeError("unsupported candidate style")
    asset_type = value.get("asset_type")
    if asset_type not in ("player", "equipment"):
        raise RuntimeError("asset_type must be player or equipment")
    return value


def reset_scene():
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for blocks in (bpy.data.meshes, bpy.data.curves, bpy.data.materials):
        for block in list(blocks):
            if block.users == 0:
                blocks.remove(block)


def rgb(value, fallback):
    if value is None:
        value = fallback
    if not isinstance(value, str) or not re.fullmatch(r"#[0-9a-fA-F]{6}", value):
        raise RuntimeError("palette colors must use #RRGGBB")
    return tuple(int(value[index : index + 2], 16) / 255.0 for index in (1, 3, 5))


def make_material(name, color, roughness=0.78, metallic=0.0):
    material = bpy.data.materials.new(name)
    material.diffuse_color = (*color, 1.0)
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    material["pixiball_palette_slot"] = name.removeprefix("MAT_").lower()
    return material


def build_materials(parameters):
    palette = parameters.get("palette", {})
    if not isinstance(palette, dict):
        raise RuntimeError("palette must be an object")
    return {
        "primary": make_material("MAT_Primary", rgb(palette.get("primary"), "#123F66")),
        "secondary": make_material("MAT_Secondary", rgb(palette.get("secondary"), "#E05247")),
        "accent": make_material("MAT_Accent", rgb(palette.get("accent"), "#F2B544"), 0.66),
        "cloth": make_material("MAT_Cloth", rgb(palette.get("cloth"), "#D9D6C8")),
        "skin": make_material("MAT_Skin", rgb(palette.get("skin"), "#B96E48"), 0.84),
        "dark": make_material("MAT_Dark", rgb(palette.get("dark"), "#18202B"), 0.70),
        "leather": make_material("MAT_Leather", rgb(palette.get("leather"), "#7A351D"), 0.88),
        "wood": make_material("MAT_Wood", rgb(palette.get("wood"), "#C58A3D"), 0.72),
        "metal": make_material("MAT_Metal", rgb(palette.get("metal"), "#8292A0"), 0.35, 0.6),
    }


def finish_object(obj, root, material, semantic, bevel=0.0):
    obj.parent = root
    obj.data.materials.append(material)
    obj["semantic_role"] = semantic
    obj["pixel_volume_candidate"] = True
    if bevel > 0.0:
        bpy.context.view_layer.objects.active = obj
        modifier = obj.modifiers.new("PixelEdge", "BEVEL")
        modifier.width = bevel
        modifier.segments = 1
        modifier.limit_method = "ANGLE"
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


def box(name, root, location, scale, material, semantic, rotation=(0.0, 0.0, 0.0), bevel=0.015):
    bpy.ops.mesh.primitive_cube_add(size=2.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_object(obj, root, material, semantic, bevel)


def sphere(name, root, location, scale, material, semantic):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_object(obj, root, material, semantic)


def cylinder(name, root, start, end, radius, material, semantic, vertices=12):
    start_value = Vector(start)
    end_value = Vector(end)
    direction = end_value - start_value
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=direction.length,
        location=(start_value + end_value) * 0.5,
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(direction.normalized())
    return finish_object(obj, root, material, semantic, 0.008)


def bounded_number(value, fallback, minimum, maximum, label):
    if value is None:
        return fallback
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise RuntimeError(label + " must be numeric")
    result = float(value)
    if not math.isfinite(result) or not minimum <= result <= maximum:
        raise RuntimeError(label + " is outside its supported range")
    return result


def build_player(root, parameters, materials):
    proportions = parameters.get("proportions", {})
    if not isinstance(proportions, dict):
        raise RuntimeError("proportions must be an object")
    unknown = sorted(set(proportions) - {"height", "shoulder_width", "stockiness"})
    if unknown:
        raise RuntimeError("unknown proportions: " + ", ".join(unknown))
    height = bounded_number(proportions.get("height"), 1.0, 0.85, 1.18, "height")
    shoulders = bounded_number(proportions.get("shoulder_width"), 1.0, 0.8, 1.25, "shoulder_width")
    stockiness = bounded_number(proportions.get("stockiness"), 1.0, 0.78, 1.3, "stockiness")
    stance = parameters.get("stance", "ready")
    if stance not in ("ready", "pitcher_power", "catcher_low"):
        raise RuntimeError("unsupported player stance")

    z_scale = height
    crouch = 0.17 if stance == "catcher_low" else 0.0
    torso_z = (1.18 - crouch) * z_scale
    box("Jersey_Torso", root, (0, 0, torso_z), (0.28 * shoulders * stockiness, 0.18, 0.31), materials["primary"], "torso")
    box("Belt", root, (0, -0.005, (0.88 - crouch) * z_scale), (0.27 * stockiness, 0.19, 0.045), materials["dark"], "belt", bevel=0.008)
    box("Pants", root, (0, 0, (0.73 - crouch) * z_scale), (0.25 * stockiness, 0.18, 0.14), materials["cloth"], "hips")
    sphere("Head", root, (0, -0.012, (1.68 - crouch) * z_scale), (0.23, 0.20, 0.25), materials["skin"], "head")
    box("Cap_Crown", root, (0, 0.015, (1.90 - crouch) * z_scale), (0.24, 0.20, 0.08), materials["primary"], "cap")
    box("Cap_Brim", root, (0, -0.20, (1.86 - crouch) * z_scale), (0.20, 0.13, 0.025), materials["secondary"], "cap_brim")
    for side in (-1, 1):
        suffix = "L" if side > 0 else "R"
        eye_x = 0.085 * side
        box("Eye_" + suffix, root, (eye_x, -0.198, (1.70 - crouch) * z_scale), (0.035, 0.014, 0.043), materials["dark"], "face_pixel", bevel=0.004)
        shoulder = (0.29 * shoulders * side, 0, (1.40 - crouch) * z_scale)
        if stance == "pitcher_power" and side < 0:
            hand = (0.48 * side, -0.08, 1.62 * z_scale)
        elif stance == "catcher_low":
            hand = (0.38 * side, -0.20, 0.88 * z_scale)
        else:
            hand = (0.39 * side, -0.06, 1.03 * z_scale)
        elbow = tuple((Vector(shoulder) + Vector(hand)) * 0.5 + Vector((0, 0.015, 0.05)))
        cylinder("UpperArm_" + suffix, root, shoulder, elbow, 0.085 * stockiness, materials["primary"], "upper_arm")
        cylinder("Forearm_" + suffix, root, elbow, hand, 0.072 * stockiness, materials["skin"], "forearm")
        sphere("Hand_" + suffix, root, hand, (0.085, 0.075, 0.09), materials["skin"], "hand")

        hip = (0.14 * side, 0, (0.70 - crouch) * z_scale)
        knee = (0.17 * side, 0.025, (0.39 - crouch * 0.45) * z_scale)
        ankle = (0.16 * side, -0.015, 0.11 * z_scale)
        cylinder("Thigh_" + suffix, root, hip, knee, 0.105 * stockiness, materials["cloth"], "thigh")
        cylinder("Shin_" + suffix, root, knee, ankle, 0.085 * stockiness, materials["cloth"], "shin")
        box("Cleat_" + suffix, root, (0.16 * side, -0.09, 0.075 * z_scale), (0.11, 0.18, 0.065), materials["dark"], "cleat", bevel=0.01)

    box("Jersey_PixelMark", root, (0, -0.187, torso_z + 0.03), (0.075, 0.012, 0.10), materials["accent"], "uniform_mark", bevel=0.004)
    root["player_role"] = str(parameters.get("role", "utility"))
    root["stance"] = stance


def build_equipment(root, parameters, materials):
    kind = parameters.get("equipment_kind")
    if kind == "bat":
        cylinder("Bat_Barrel", root, (0, 0, 0.20), (0, 0, 1.16), 0.085, materials["wood"], "bat_barrel", 16)
        cylinder("Bat_Handle", root, (0, 0, 0.02), (0, 0, 0.40), 0.038, materials["dark"], "bat_handle", 12)
        cylinder("Bat_Knob", root, (0, 0, -0.015), (0, 0, 0.045), 0.060, materials["accent"], "bat_knob", 12)
        box("Bat_PixelBrand", root, (0, -0.086, 0.80), (0.028, 0.008, 0.12), materials["accent"], "equipment_mark", bevel=0.002)
    elif kind == "mitt":
        sphere("Mitt_Palm", root, (0, 0, 0.26), (0.34, 0.12, 0.31), materials["leather"], "mitt_palm")
        for index, x_value in enumerate((-0.24, -0.12, 0.0, 0.12, 0.24)):
            length = 0.62 + 0.07 * (2 - abs(index - 2))
            cylinder("Mitt_Finger_{0}".format(index + 1), root, (x_value, 0, 0.42), (x_value * 1.08, 0, length), 0.075, materials["leather"], "mitt_finger", 10)
        box("Mitt_Web", root, (0.0, -0.075, 0.49), (0.14, 0.025, 0.17), materials["dark"], "mitt_web", bevel=0.005)
        for x_value in (-0.08, 0.0, 0.08):
            cylinder("Mitt_Lace_{0:+.2f}".format(x_value), root, (x_value, -0.14, 0.31), (x_value, -0.14, 0.60), 0.012, materials["accent"], "mitt_lace", 8)
    else:
        raise RuntimeError("equipment_kind must be bat or mitt")
    root["equipment_kind"] = kind


def main():
    parameters = read_parameters()
    reset_scene()
    materials = build_materials(parameters)
    candidate_id = parameters["candidate_id"]
    root = bpy.data.objects.new("PIXIBALL_CANDIDATE_" + candidate_id, None)
    bpy.context.collection.objects.link(root)
    root["asset_contract_version"] = 1
    root["asset_type"] = parameters["asset_type"]
    root["candidate_id"] = candidate_id
    root["style"] = STYLE
    root["forward_axis"] = "-Y"

    if parameters["asset_type"] == "player":
        build_player(root, parameters, materials)
    else:
        build_equipment(root, parameters, materials)
    bpy.context.scene["pixiball_candidate_id"] = candidate_id


if __name__ == "__main__":
    main()
