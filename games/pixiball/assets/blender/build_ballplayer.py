"""Build Pixiball's deterministic, original, production ballplayer asset.

The recipe deliberately uses only Blender's bundled Python API.  Every visible
piece is weighted to the shared armature, even when a piece is rigid, so the
result remains easy to art-direct while exporting as a conventional skinned
glTF.  Rounded low-poly forms and small planar accents create a high-resolution
pixel-art silhouette without copying any third-party character or texture.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector

ASSET_VERSION = 7
DEG = math.pi / 180.0
RIG = None
MATERIALS = {}


def reset_scene():
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.armatures, bpy.data.materials):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def material(name, color, roughness=0.72, metallic=0.0, emission=None):
    value = bpy.data.materials.new(name)
    value.diffuse_color = (*color, 1.0)
    value.use_nodes = True
    shader = value.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    specular = shader.inputs.get("Specular IOR Level")
    if specular is not None:
        specular.default_value = 0.32
    if emission is not None:
        emission_color = shader.inputs.get("Emission Color") or shader.inputs.get("Emission")
        if emission_color is not None:
            emission_color.default_value = (*emission, 1.0)
        strength = shader.inputs.get("Emission Strength")
        if strength is not None:
            strength.default_value = 0.18
    value["pixiball_material"] = True
    if name.startswith("TEAM_"):
        value["team_color_slot"] = name.removeprefix("TEAM_").lower()
    MATERIALS[name] = value
    return value


def build_materials():
    material("MAT_Skin", (0.67, 0.345, 0.175), roughness=0.82)
    material("MAT_SkinLight", (0.91, 0.58, 0.36), roughness=0.80)
    material("MAT_Hair", (0.055, 0.026, 0.018), roughness=0.90)
    material("MAT_HairHighlight", (0.17, 0.072, 0.035), roughness=0.88)
    material("MAT_EyeWhite", (0.91, 0.91, 0.82), roughness=0.72)
    material("MAT_Iris", (0.045, 0.16, 0.17), roughness=0.55)
    material("MAT_Pupil", (0.006, 0.009, 0.012), roughness=0.38)
    material("MAT_Mouth", (0.23, 0.035, 0.04), roughness=0.78)
    material("TEAM_Primary", (0.035, 0.18, 0.31), roughness=0.72)
    material("TEAM_Secondary", (0.72, 0.045, 0.065), roughness=0.72)
    material("TEAM_Accent", (0.95, 0.58, 0.08), roughness=0.64)
    material("MAT_Pants", (0.78, 0.79, 0.75), roughness=0.78)
    material("MAT_PantsShadow", (0.48, 0.51, 0.51), roughness=0.82)
    material("MAT_Belt", (0.055, 0.045, 0.04), roughness=0.72)
    material("MAT_Leather", (0.23, 0.075, 0.026), roughness=0.88)
    material("MAT_LeatherLight", (0.53, 0.20, 0.065), roughness=0.84)
    material("MAT_Bat", (0.52, 0.27, 0.075), roughness=0.63)
    material("MAT_BatTape", (0.055, 0.06, 0.065), roughness=0.78)
    material("MAT_Cleat", (0.025, 0.032, 0.042), roughness=0.62)
    material("MAT_CleatEdge", (0.18, 0.20, 0.22), roughness=0.58)
    material("MAT_Sock", (0.90, 0.88, 0.79), roughness=0.82)
    material("MAT_Rubber", (0.012, 0.017, 0.025), roughness=0.76)
    material("MAT_Metal", (0.46, 0.52, 0.55), roughness=0.33, metallic=0.68)


def create_rig():
    global RIG
    armature = bpy.data.armatures.new("BallplayerHumanoid")
    armature.display_type = "STICK"
    rig = bpy.data.objects.new("Ballplayer_Rig", armature)
    bpy.context.collection.objects.link(rig)
    rig.show_in_front = True
    rig["semantic_role"] = "ballplayer_humanoid_rig"
    rig["asset_contract_version"] = ASSET_VERSION
    rig["forward_axis"] = "-Y"

    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    definitions = [
        ("root", (0.0, 0.0, 0.02), (0.0, 0.0, 0.18), None, False),
        ("hips", (0.0, 0.0, 0.84), (0.0, 0.0, 1.05), "root", True),
        ("spine", (0.0, 0.0, 1.05), (0.0, 0.0, 1.28), "hips", True),
        ("chest", (0.0, 0.0, 1.28), (0.0, 0.0, 1.48), "spine", True),
        ("neck", (0.0, 0.0, 1.48), (0.0, 0.0, 1.58), "chest", True),
        ("head", (0.0, 0.0, 1.58), (0.0, 0.0, 1.86), "neck", True),
        ("clavicle.L", (0.0, 0.0, 1.43), (0.255, 0.0, 1.43), "chest", True),
        ("upper_arm.L", (0.255, 0.0, 1.43), (0.39, 0.0, 1.16), "clavicle.L", True),
        ("forearm.L", (0.39, 0.0, 1.16), (0.43, -0.005, 0.91), "upper_arm.L", True),
        ("hand.L", (0.43, -0.005, 0.91), (0.43, -0.045, 0.77), "forearm.L", True),
        ("clavicle.R", (0.0, 0.0, 1.43), (-0.255, 0.0, 1.43), "chest", True),
        ("upper_arm.R", (-0.255, 0.0, 1.43), (-0.39, 0.0, 1.16), "clavicle.R", True),
        ("forearm.R", (-0.39, 0.0, 1.16), (-0.43, -0.005, 0.91), "upper_arm.R", True),
        ("hand.R", (-0.43, -0.005, 0.91), (-0.43, -0.045, 0.77), "forearm.R", True),
        ("thigh.L", (0.14, 0.0, 1.01), (0.14, 0.006, 0.59), "hips", True),
        ("shin.L", (0.14, 0.006, 0.59), (0.14, 0.0, 0.17), "thigh.L", True),
        ("foot.L", (0.14, 0.0, 0.17), (0.14, -0.22, 0.075), "shin.L", True),
        ("toe.L", (0.14, -0.22, 0.075), (0.14, -0.34, 0.07), "foot.L", True),
        ("thigh.R", (-0.14, 0.0, 1.01), (-0.14, 0.006, 0.59), "hips", True),
        ("shin.R", (-0.14, 0.006, 0.59), (-0.14, 0.0, 0.17), "thigh.R", True),
        ("foot.R", (-0.14, 0.0, 0.17), (-0.14, -0.22, 0.075), "shin.R", True),
        ("toe.R", (-0.14, -0.22, 0.075), (-0.14, -0.34, 0.07), "foot.R", True),
        ("socket_head", (0.0, -0.19, 1.79), (0.0, -0.27, 1.79), "head", False),
        ("socket_chest", (0.0, -0.17, 1.35), (0.0, -0.25, 1.35), "chest", False),
        ("socket_glove", (0.43, -0.07, 0.82), (0.43, -0.17, 0.82), "hand.L", False),
        ("socket_catch", (0.43, -0.20, 0.84), (0.43, -0.29, 0.84), "hand.L", False),
        ("socket_bat", (-0.43, -0.07, 0.81), (-0.43, -0.17, 0.81), "hand.R", False),
        ("socket_ball", (-0.43, -0.13, 0.83), (-0.43, -0.22, 0.83), "hand.R", False),
        ("socket_bat_tip", (-0.39, -0.10, 1.53), (-0.39, -0.19, 1.53), "hand.R", False),
        ("socket_foot.L", (0.14, -0.24, 0.04), (0.14, -0.32, 0.04), "foot.L", False),
        ("socket_foot.R", (-0.14, -0.24, 0.04), (-0.14, -0.32, 0.04), "foot.R", False),
    ]

    edit_bones = {}
    for name, head, tail, parent_name, deform in definitions:
        bone = armature.edit_bones.new(name)
        bone.head = head
        bone.tail = tail
        bone.use_deform = deform
        if parent_name is not None:
            bone.parent = edit_bones[parent_name]
        edit_bones[name] = bone

    bpy.ops.object.mode_set(mode="OBJECT")
    for bone in armature.bones:
        bone["semantic_bone"] = True
        if bone.name.startswith("socket_"):
            bone["semantic_role"] = "attachment_socket"
    for pose_bone in rig.pose.bones:
        pose_bone.rotation_mode = "XYZ"
    RIG = rig
    return rig


def finish_mesh(obj, name, mat_name, bone_name, smooth=True, bevel=0.0):
    obj.name = name
    obj.data.name = name + "_Mesh"
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if bevel > 0.0:
        modifier = obj.modifiers.new("PixelEdgeSoftening", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        modifier.limit_method = "ANGLE"
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    if smooth:
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    obj.data.materials.append(MATERIALS[mat_name])
    group = obj.vertex_groups.new(name=bone_name)
    group.add(range(len(obj.data.vertices)), 1.0, "REPLACE")
    modifier = obj.modifiers.new("BallplayerArmature", "ARMATURE")
    modifier.object = RIG
    modifier.use_deform_preserve_volume = True
    obj["weighted_bone"] = bone_name
    return obj


def uv_part(name, location, scale, mat, bone, segments=16, rings=10, smooth=True, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments,
        ring_count=rings,
        radius=1.0,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.scale = scale
    return finish_mesh(obj, name, mat, bone, smooth=smooth)


def ico_part(name, location, scale, mat, bone, subdivisions=2, smooth=False, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_ico_sphere_add(
        subdivisions=subdivisions, radius=1.0, location=location, rotation=rotation
    )
    obj = bpy.context.object
    obj.scale = scale
    return finish_mesh(obj, name, mat, bone, smooth=smooth)


def box_part(name, location, scale, mat, bone, rotation=(0.0, 0.0, 0.0), bevel=0.0):
    bpy.ops.mesh.primitive_cube_add(size=2.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.scale = scale
    return finish_mesh(obj, name, mat, bone, smooth=False, bevel=bevel)


def cylinder_part(name, start, end, radius, mat, bone, vertices=12, smooth=False):
    start_v = Vector(start)
    end_v = Vector(end)
    direction = end_v - start_v
    midpoint = (start_v + end_v) * 0.5
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=direction.length,
        location=midpoint,
    )
    obj = bpy.context.object
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0.0, 0.0, 1.0)).rotation_difference(direction.normalized())
    return finish_mesh(obj, name, mat, bone, smooth=smooth)


def torus_part(name, location, major_radius, minor_radius, mat, bone, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_torus_add(
        align="WORLD",
        major_segments=24,
        minor_segments=8,
        location=location,
        rotation=rotation,
        major_radius=major_radius,
        minor_radius=minor_radius,
    )
    return finish_mesh(bpy.context.object, name, mat, bone, smooth=True)


def weighted_chain_part(name, rings, mat, segments=20, smooth=True, phase=0.0, face_materials=None, cap_materials=None):
    """Create a continuous, multi-weight tube through an articulated chain.

    ``rings`` contains ``(center, side_radius, depth_radius, weights)`` tuples,
    optionally extended with a fifth per-segment radial profile (a sequence or
    callable of multipliers) that sculpts knuckle bumps, finger scallops, and
    cloth folds directly into the deforming surface.  Each weight map is
    written directly to the ring's vertices.  Adjacent rings deliberately
    overlap influence at shoulders, elbows, knees, wrists and ankles,
    eliminating the separated toy-joint look of rigid primitives while
    retaining compact, deterministic topology.

    ``phase`` rotates every ring by a fraction of one segment so a single face
    column can center exactly on the front or side of the tube.  Side faces are
    created in ``band * segments + segment`` order; ``face_materials`` maps a
    ``(band, segment)`` pair to an override material name (or ``None`` for the
    base material), turning stripes, plackets, belts, and cuffs into deforming
    surface bands instead of separate rigid primitives.  ``cap_materials`` is
    an optional ``(start, end)`` pair overriding the two closing n-gons so an
    exposed hem or sole cap never flashes the base color.
    """

    vertices = []
    faces = []
    vertex_weights = []
    centers = [Vector(ring[0]) for ring in rings]
    forward_reference = Vector((0.0, 1.0, 0.0))
    for ring_index, ring in enumerate(rings):
        center_raw, side_radius, depth_radius, weights = ring[:4]
        profile = ring[4] if len(ring) > 4 else None
        center = Vector(center_raw)
        if ring_index == 0:
            tangent = centers[1] - center
        elif ring_index == len(rings) - 1:
            tangent = center - centers[ring_index - 1]
        else:
            tangent = centers[ring_index + 1] - centers[ring_index - 1]
        tangent.normalize()
        side = tangent.cross(forward_reference)
        if side.length_squared < 1.0e-8:
            side = Vector((1.0, 0.0, 0.0))
        else:
            side.normalize()
        depth = side.cross(tangent).normalized()
        for segment in range(segments):
            angle = math.tau * (float(segment) + float(phase)) / float(segments)
            scale = 1.0
            if profile is not None:
                scale = float(profile(segment)) if callable(profile) else float(profile[segment])
            point = (
                center
                + side * (math.cos(angle) * side_radius * scale)
                + depth * (math.sin(angle) * depth_radius * scale)
            )
            vertices.append(tuple(point))
            vertex_weights.append(dict(weights))

    for ring_index in range(len(rings) - 1):
        first = ring_index * segments
        following = (ring_index + 1) * segments
        for segment in range(segments):
            next_segment = (segment + 1) % segments
            faces.append((first + segment, first + next_segment, following + next_segment, following + segment))
    faces.append(tuple(reversed(range(segments))))
    end_start = (len(rings) - 1) * segments
    faces.append(tuple(end_start + segment for segment in range(segments)))

    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(MATERIALS[mat])
    if face_materials is not None or cap_materials is not None:
        slots = {mat: 0}

        def assign(polygon, override):
            if override is None or override == mat:
                return
            if override not in slots:
                slots[override] = len(mesh.materials)
                mesh.materials.append(MATERIALS[override])
            polygon.material_index = slots[override]

        band_faces = (len(rings) - 1) * segments
        for face_index, polygon in enumerate(mesh.polygons):
            if face_index < band_faces:
                if face_materials is not None:
                    band, segment = divmod(face_index, segments)
                    assign(polygon, face_materials(band, segment))
            elif cap_materials is not None:
                assign(polygon, cap_materials[face_index - band_faces])
    if smooth:
        for polygon in mesh.polygons:
            polygon.use_smooth = True

    groups = {}
    for weights in vertex_weights:
        for bone_name in weights:
            if bone_name not in groups:
                groups[bone_name] = obj.vertex_groups.new(name=bone_name)
    for vertex_index, weights in enumerate(vertex_weights):
        total = sum(max(0.0, float(weight)) for weight in weights.values())
        if total <= 0.0:
            raise RuntimeError("weighted chain ring has no positive influence")
        for bone_name, weight in weights.items():
            normalized = max(0.0, float(weight)) / total
            if normalized > 0.0:
                groups[bone_name].add([vertex_index], normalized, "REPLACE")
    modifier = obj.modifiers.new("BallplayerArmature", "ARMATURE")
    modifier.object = RIG
    modifier.use_deform_preserve_volume = True
    obj["multi_weighted"] = True
    obj["influence_bones"] = ",".join(sorted(groups))
    return obj


def join_parts(parts, name, category):
    if not parts:
        raise RuntimeError("cannot join empty mesh category " + category)
    bpy.ops.object.select_all(action="DESELECT")
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    obj.data.name = name + "_Mesh"
    obj["semantic_role"] = category
    obj["skinned"] = True
    obj["asset_contract_version"] = ASSET_VERSION
    # Joining preserves the active armature modifier and all per-part groups.
    modifiers = [modifier for modifier in obj.modifiers if modifier.type == "ARMATURE"]
    if not modifiers:
        modifier = obj.modifiers.new("BallplayerArmature", "ARMATURE")
        modifier.object = RIG
        modifier.use_deform_preserve_volume = True
    elif modifiers[0].object is None:
        modifiers[0].object = RIG
    # Blender 4.x replaced auto-smooth with data-level sharp edges.  Authored
    # per-polygon smooth flags stay in charge of the pixel-faceted parts; the
    # angle pass only adds hard seams where smooth surfaces meet at extreme
    # angles (tube end caps, brims), which the glTF exporter bakes as split
    # normals deterministically.
    if hasattr(obj.data, "set_sharp_from_angle"):
        obj.data.set_sharp_from_angle(angle=62.0 * DEG)
    return obj


def build_body():
    parts = []
    # One coherent warm skin tone across cranium, jaw and ears keeps the face
    # readable at gameplay scale; graphic contrast now comes from the face
    # planes, hair, and cap rather than mottled skin patches.  The result is
    # authored, deterministic, and intentionally not a real-player likeness.
    parts.append(uv_part("Body_Head", (0.0, 0.002, 1.724), (0.155, 0.134, 0.186), "MAT_Skin", "head", 40, 24))
    parts.append(ico_part("Body_Jaw", (0.0, -0.054, 1.646), (0.133, 0.106, 0.118), "MAT_Skin", "head", 3, True))
    # Same-material cheek and brow-ridge masses push the face silhouette
    # outward so the head reads as authored form instead of a bare sphere,
    # without adding any value noise at gameplay scale.  A chin cap under the
    # jaw sharpens the profile line from the mouth to the neck.
    parts.append(uv_part("Body_Cheek_L", (0.082, -0.112, 1.688), (0.046, 0.038, 0.044), "MAT_Skin", "head", 16, 11))
    parts.append(uv_part("Body_Cheek_R", (-0.082, -0.112, 1.688), (0.046, 0.038, 0.044), "MAT_Skin", "head", 16, 11))
    parts.append(uv_part("Body_BrowRidge", (0.0, -0.118, 1.792), (0.118, 0.044, 0.030), "MAT_Skin", "head", 18, 9))
    parts.append(uv_part("Body_Chin", (0.0, -0.098, 1.606), (0.058, 0.052, 0.042), "MAT_Skin", "head", 16, 10))
    parts.append(uv_part("Body_Ear_L", (0.153, -0.002, 1.718), (0.028, 0.022, 0.054), "MAT_Skin", "head", 16, 11))
    parts.append(uv_part("Body_Ear_R", (-0.153, 0.001, 1.713), (0.028, 0.022, 0.053), "MAT_Skin", "head", 16, 11))
    parts.append(uv_part("Body_EarLobe_L", (0.150, -0.014, 1.694), (0.014, 0.014, 0.020), "MAT_Skin", "head", 10, 7))
    parts.append(uv_part("Body_EarLobe_R", (-0.150, -0.011, 1.690), (0.014, 0.014, 0.020), "MAT_Skin", "head", 10, 7))
    parts.append(
        ico_part("Body_NoseTip", (0.0, -0.154, 1.700), (0.035, 0.030, 0.035), "MAT_SkinLight", "head", 2, True)
    )
    parts.append(
        weighted_chain_part(
            "Body_NoseBridge",
            [
                ((0.0, -0.126, 1.752), 0.020, 0.014, {"head": 1.0}),
                ((0.0, -0.140, 1.728), 0.024, 0.016, {"head": 1.0}),
                ((0.0, -0.150, 1.708), 0.027, 0.018, {"head": 1.0}),
            ],
            "MAT_Skin",
            10,
        )
    )
    parts.append(
        weighted_chain_part(
            "Body_NeckBlend",
            [
                ((0.0, 0.0, 1.462), 0.098, 0.090, {"chest": 0.45, "neck": 0.55}),
                ((0.0, 0.0, 1.502), 0.088, 0.081, {"chest": 0.18, "neck": 0.82}),
                ((0.0, 0.002, 1.540), 0.083, 0.077, {"neck": 1.0}),
                ((0.0, 0.002, 1.575), 0.084, 0.078, {"neck": 0.62, "head": 0.38}),
                ((0.0, 0.0, 1.612), 0.088, 0.082, {"neck": 0.28, "head": 0.72}),
            ],
            "MAT_Skin",
            24,
        )
    )

    # Anatomical arm tubes: deltoid mass, a bicep peak against a flatter
    # tricep plane, a pinched elbow landmark, a flared then tapering forearm,
    # and a narrowing wrist that hands the surface off to the sculpted hand
    # chains below.  The bicep/tricep asymmetry is authored with a gentle
    # single-lobe radial profile so the upper arm reads as muscle, not pipe.
    arm_segments = 28
    bicep_profile = [
        1.0 + 0.050 * math.cos(math.tau * (k + 0.5) / arm_segments + math.pi * 0.5) for k in range(arm_segments)
    ]
    forearm_profile = [
        1.0 + 0.035 * math.cos(math.tau * (k + 0.5) / arm_segments - math.pi * 0.5) for k in range(arm_segments)
    ]
    for side, sign in (("L", 1.0), ("R", -1.0)):
        upper_bone = "upper_arm." + side
        forearm_bone = "forearm." + side
        hand_bone = "hand." + side
        clavicle_bone = "clavicle." + side
        parts.append(
            weighted_chain_part(
                "Body_ArmBlend_" + side,
                [
                    ((0.305 * sign, 0.000, 1.352), 0.106, 0.104, {clavicle_bone: 0.30, upper_bone: 0.70}),
                    ((0.330 * sign, 0.000, 1.308), 0.104, 0.102, {clavicle_bone: 0.12, upper_bone: 0.88}),
                    ((0.352 * sign, -0.001, 1.272), 0.098, 0.096, {upper_bone: 1.0}, bicep_profile),
                    ((0.370 * sign, -0.002, 1.240), 0.094, 0.092, {upper_bone: 1.0}, bicep_profile),
                    ((0.383 * sign, -0.003, 1.212), 0.089, 0.087, {upper_bone: 1.0}, bicep_profile),
                    ((0.394 * sign, -0.003, 1.188), 0.084, 0.082, {upper_bone: 0.80, forearm_bone: 0.20}),
                    ((0.402 * sign, -0.004, 1.164), 0.079, 0.078, {upper_bone: 0.55, forearm_bone: 0.45}),
                    ((0.407 * sign, -0.005, 1.142), 0.074, 0.073, {upper_bone: 0.30, forearm_bone: 0.70}),
                    ((0.412 * sign, -0.006, 1.112), 0.076, 0.074, {upper_bone: 0.12, forearm_bone: 0.88}),
                    ((0.418 * sign, -0.008, 1.072), 0.083, 0.081, {forearm_bone: 1.0}, forearm_profile),
                    ((0.422 * sign, -0.010, 1.030), 0.080, 0.078, {forearm_bone: 1.0}, forearm_profile),
                    ((0.426 * sign, -0.012, 0.988), 0.074, 0.072, {forearm_bone: 1.0}, forearm_profile),
                    ((0.430 * sign, -0.015, 0.952), 0.067, 0.063, {forearm_bone: 0.88, hand_bone: 0.12}),
                    ((0.432 * sign, -0.018, 0.926), 0.061, 0.055, {forearm_bone: 0.68, hand_bone: 0.32}),
                    ((0.434 * sign, -0.024, 0.898), 0.055, 0.047, {forearm_bone: 0.35, hand_bone: 0.65}),
                ],
                "MAT_Skin",
                arm_segments,
                phase=0.5,
            )
        )

    # Sculpted hands built from existing bones only.  Both start with a narrow
    # wrist transition and a palm heel; a widened knuckle ridge carries a
    # four-bump radial profile and the finger mass carries a scalloped profile
    # so separation reads in silhouette without toast-rack finger boxes.  The
    # glove-side hand stays half-open for catches and celebrations while the
    # throwing hand curls into a compact fist whose volume wraps the resting
    # bat handle, with a thumb chain crossing the front of the grip.
    hand_segments = 22
    knuckle_profile = [
        1.0 + 0.065 * math.cos(4.0 * math.tau * (k + 0.5) / hand_segments) for k in range(hand_segments)
    ]
    finger_profile = [
        1.0 + 0.085 * math.cos(4.0 * math.tau * (k + 0.5) / hand_segments + math.pi) for k in range(hand_segments)
    ]
    fingertip_profile = [
        1.0 + 0.060 * math.cos(4.0 * math.tau * (k + 0.5) / hand_segments + math.pi) for k in range(hand_segments)
    ]
    # A single-lobe bias toward the thumb side widens the palm over the thenar
    # mass, and the knuckle ridge above the fingers separates index from
    # pinky in silhouette without toast-rack finger boxes.
    thenar_profile = [
        1.0 + 0.070 * math.cos(math.tau * (k + 0.5) / hand_segments) for k in range(hand_segments)
    ]

    def open_hand_faces(band, segment):
        return "MAT_SkinLight" if band >= 7 else None

    def fist_faces(band, segment):
        return "MAT_SkinLight" if band >= 5 else None

    parts.append(
        weighted_chain_part(
            "Body_Hand_L",
            [
                ((0.433, -0.020, 0.915), 0.050, 0.042, {"forearm.L": 0.55, "hand.L": 0.45}),
                ((0.434, -0.026, 0.898), 0.054, 0.045, {"forearm.L": 0.30, "hand.L": 0.70}),
                ((0.435, -0.032, 0.882), 0.059, 0.048, {"forearm.L": 0.12, "hand.L": 0.88}),
                ((0.436, -0.036, 0.864), 0.064, 0.047, {"hand.L": 1.0}, thenar_profile),
                ((0.436, -0.041, 0.844), 0.070, 0.046, {"hand.L": 1.0}, thenar_profile),
                ((0.437, -0.048, 0.812), 0.080, 0.044, {"hand.L": 1.0}, thenar_profile),
                ((0.437, -0.058, 0.780), 0.084, 0.048, {"hand.L": 1.0}, knuckle_profile),
                ((0.437, -0.065, 0.764), 0.082, 0.044, {"hand.L": 1.0}, knuckle_profile),
                ((0.436, -0.072, 0.748), 0.078, 0.040, {"hand.L": 1.0}, finger_profile),
                ((0.435, -0.080, 0.732), 0.071, 0.036, {"hand.L": 1.0}, finger_profile),
                ((0.434, -0.086, 0.720), 0.064, 0.032, {"hand.L": 1.0}, finger_profile),
                ((0.433, -0.091, 0.708), 0.054, 0.028, {"hand.L": 1.0}, fingertip_profile),
                ((0.432, -0.094, 0.700), 0.044, 0.024, {"hand.L": 1.0}),
            ],
            "MAT_Skin",
            hand_segments,
            phase=0.5,
            face_materials=open_hand_faces,
        )
    )
    parts.append(
        weighted_chain_part(
            "Body_Thumb_L",
            [
                ((0.462, -0.044, 0.834), 0.033, 0.030, {"hand.L": 1.0}),
                ((0.478, -0.060, 0.815), 0.029, 0.026, {"hand.L": 1.0}),
                ((0.490, -0.074, 0.800), 0.026, 0.023, {"hand.L": 1.0}),
                ((0.498, -0.085, 0.789), 0.022, 0.019, {"hand.L": 1.0}),
                ((0.503, -0.093, 0.781), 0.017, 0.015, {"hand.L": 1.0}),
            ],
            "MAT_Skin",
            12,
        )
    )
    parts.append(
        weighted_chain_part(
            "Body_Hand_R",
            [
                ((-0.433, -0.020, 0.915), 0.050, 0.042, {"forearm.R": 0.55, "hand.R": 0.45}),
                ((-0.434, -0.027, 0.898), 0.055, 0.046, {"forearm.R": 0.30, "hand.R": 0.70}),
                ((-0.435, -0.034, 0.882), 0.060, 0.050, {"forearm.R": 0.12, "hand.R": 0.88}),
                ((-0.436, -0.038, 0.866), 0.065, 0.050, {"hand.R": 1.0}, thenar_profile),
                ((-0.436, -0.042, 0.850), 0.070, 0.050, {"hand.R": 1.0}, thenar_profile),
                ((-0.437, -0.058, 0.815), 0.082, 0.058, {"hand.R": 1.0}, thenar_profile),
                ((-0.436, -0.070, 0.782), 0.084, 0.062, {"hand.R": 1.0}, knuckle_profile),
                ((-0.434, -0.070, 0.766), 0.080, 0.060, {"hand.R": 1.0}, knuckle_profile),
                ((-0.432, -0.068, 0.752), 0.074, 0.056, {"hand.R": 1.0}, finger_profile),
                ((-0.430, -0.060, 0.740), 0.064, 0.048, {"hand.R": 1.0}, finger_profile),
                ((-0.428, -0.052, 0.732), 0.054, 0.040, {"hand.R": 1.0}),
            ],
            "MAT_Skin",
            hand_segments,
            phase=0.5,
            face_materials=fist_faces,
        )
    )
    parts.append(
        weighted_chain_part(
            "Body_Thumb_R",
            [
                ((-0.484, -0.056, 0.822), 0.033, 0.030, {"hand.R": 1.0}),
                ((-0.478, -0.068, 0.812), 0.031, 0.028, {"hand.R": 1.0}),
                ((-0.469, -0.084, 0.800), 0.029, 0.026, {"hand.R": 1.0}),
                ((-0.460, -0.098, 0.788), 0.026, 0.023, {"hand.R": 1.0}),
                ((-0.448, -0.104, 0.781), 0.022, 0.020, {"hand.R": 1.0}),
                ((-0.436, -0.108, 0.775), 0.017, 0.015, {"hand.R": 1.0}),
            ],
            "MAT_Skin",
            12,
        )
    )
    return join_parts(parts, "Body_Skinned", "body_skin")


def build_uniform():
    # Every uniform accent is painted onto deforming chain faces instead of
    # floating rigid slabs.  Column bookkeeping for phase=0.5 chains: a face
    # column ``s`` of an N-segment ring is centered on angle (s + 1) / N of a
    # full turn.  Upward chains (torso, 32 segments) place +X at 180 deg ->
    # column 15 and -Y (front) at 270 deg -> column 23; downward chains (legs,
    # 28 segments) mirror X, so +X is column 27 and -X is column 13 while the
    # front sits at column 20.
    parts = []

    def torso_faces(band, segment):
        if band == 0:
            return "MAT_Pants"  # tucked waist overlap band, reads as pants
        if band == 1:
            return "MAT_Metal" if segment == 23 else "MAT_Belt"
        if band == 15:
            # Raglan shoulder yoke: the same red as the sleeves so the sleeve
            # roots read as one continuous garment with the torso.
            return "TEAM_Accent" if segment == 23 else "TEAM_Secondary"
        if 7 <= band <= 14 and segment in (14, 15, 16, 30, 31, 0):
            return "TEAM_Secondary"  # jersey side panels
        if 2 <= band <= 14 and segment == 23:
            return "TEAM_Accent"  # button placket / central graphic stripe
        return None

    # Radial contract with the pants: every pelvis-chain radius stays at least
    # 8 mm inside these hem rings, and the shared pure-hips weighting across
    # the whole overlap zone means the two garments cannot separate or
    # interleave at the midriff in any pose.  The pinched ring at 1.104 is an
    # authored waist fold; the stepped rib rings above it carry the chest
    # planes, and the extra rings around the belt and hem keep those material
    # bands crisp under deformation.
    parts.append(
        weighted_chain_part(
            "Uniform_TorsoBlend",
            [
                ((0.0, 0.012, 0.868), 0.236, 0.152, {"hips": 1.0}),
                ((0.0, 0.012, 0.918), 0.240, 0.154, {"hips": 1.0}),
                ((0.0, 0.011, 0.958), 0.242, 0.155, {"hips": 1.0}),
                ((0.0, 0.010, 1.000), 0.243, 0.155, {"hips": 1.0}),
                ((0.0, 0.010, 1.044), 0.244, 0.156, {"hips": 1.0}),
                ((0.0, 0.009, 1.080), 0.240, 0.153, {"hips": 0.85, "spine": 0.15}),
                ((0.0, 0.008, 1.104), 0.232, 0.150, {"hips": 0.68, "spine": 0.32}),
                ((0.0, 0.007, 1.136), 0.236, 0.150, {"hips": 0.45, "spine": 0.55}),
                ((0.0, 0.006, 1.176), 0.242, 0.150, {"hips": 0.24, "spine": 0.76}),
                ((0.0, 0.005, 1.216), 0.250, 0.151, {"spine": 0.90, "chest": 0.10}),
                ((0.0, 0.003, 1.258), 0.261, 0.154, {"spine": 0.74, "chest": 0.26}),
                ((0.0, 0.002, 1.296), 0.273, 0.158, {"spine": 0.45, "chest": 0.55}),
                ((0.0, 0.001, 1.336), 0.286, 0.162, {"spine": 0.26, "chest": 0.74}),
                ((0.0, -0.001, 1.378), 0.294, 0.164, {"chest": 1.0}),
                ((0.0, -0.001, 1.412), 0.297, 0.165, {"chest": 1.0}),
                ((0.0, -0.003, 1.466), 0.270, 0.154, {"chest": 1.0}),
                ((0.0, -0.005, 1.508), 0.174, 0.128, {"chest": 0.80, "neck": 0.20}),
            ],
            "TEAM_Primary",
            32,
            phase=0.5,
            face_materials=torso_faces,
            cap_materials=("MAT_Pants", "TEAM_Primary"),
        )
    )
    parts.append(torus_part("Uniform_Collar", (0.0, -0.004, 1.505), 0.104, 0.014, "TEAM_Accent", "chest"))
    parts.append(torus_part("Uniform_Undershirt", (0.0, -0.002, 1.496), 0.079, 0.017, "TEAM_Secondary", "chest"))
    # Layered V-neck: two angled accent bars descending from the collar.
    for side, sign in (("L", 1.0), ("R", -1.0)):
        parts.append(
            box_part(
                "Uniform_VNeck_" + side,
                (0.034 * sign, -0.163, 1.460),
                (0.011, 0.008, 0.046),
                "TEAM_Accent",
                "chest",
                rotation=(0.0, 0.0, 24.0 * sign * DEG),
                bevel=0.005,
            )
        )
    # An abstract embroidered H reads crisply at field distance and remains a
    # team-colorable original mark rather than a borrowed real-world logo.
    parts.append(
        box_part(
            "Uniform_MarkLeft",
            (0.062, -0.172, 1.362),
            (0.013, 0.008, 0.052),
            "TEAM_Accent",
            "chest",
            rotation=(0.0, 0.0, -7.0 * DEG),
            bevel=0.005,
        )
    )
    parts.append(
        box_part(
            "Uniform_MarkRight",
            (0.114, -0.172, 1.362),
            (0.013, 0.008, 0.052),
            "TEAM_Accent",
            "chest",
            rotation=(0.0, 0.0, -7.0 * DEG),
            bevel=0.005,
        )
    )
    parts.append(
        box_part(
            "Uniform_MarkBridge",
            (0.088, -0.175, 1.362),
            (0.030, 0.007, 0.011),
            "TEAM_Secondary",
            "chest",
            rotation=(0.0, 0.0, -7.0 * DEG),
            bevel=0.004,
        )
    )

    def sleeve_faces(band, segment):
        return "TEAM_Accent" if band == 8 else None  # deforming cuff piping

    # Raglan sleeves grow out of the torso instead of capping it: the root
    # ring sits deep inside the chest tube and is chest-dominated, so raising
    # the arm fans the sleeve smoothly out of the red shoulder yoke instead of
    # hinging a detached epaulette wedge.  A pinched ring under the arm and a
    # slight flare at the hem author broad cloth-fold planes into the sleeve.
    for side, sign in (("L", 1.0), ("R", -1.0)):
        upper_bone = "upper_arm." + side
        forearm_bone = "forearm." + side
        clavicle_bone = "clavicle." + side
        parts.append(
            weighted_chain_part(
                "Uniform_SleeveBlend_" + side,
                [
                    ((0.200 * sign, 0.000, 1.452), 0.124, 0.138, {"chest": 0.48, clavicle_bone: 0.42, upper_bone: 0.10}),
                    ((0.230 * sign, 0.000, 1.442), 0.129, 0.139, {"chest": 0.30, clavicle_bone: 0.48, upper_bone: 0.22}),
                    ((0.256 * sign, 0.000, 1.428), 0.132, 0.140, {"chest": 0.16, clavicle_bone: 0.50, upper_bone: 0.34}),
                    ((0.283 * sign, -0.001, 1.402), 0.130, 0.136, {clavicle_bone: 0.40, upper_bone: 0.60}),
                    ((0.306 * sign, -0.001, 1.372), 0.126, 0.130, {clavicle_bone: 0.28, upper_bone: 0.72}),
                    ((0.325 * sign, -0.001, 1.344), 0.121, 0.126, {clavicle_bone: 0.12, upper_bone: 0.88}),
                    ((0.340 * sign, -0.001, 1.315), 0.115, 0.121, {upper_bone: 1.0}),
                    ((0.352 * sign, -0.001, 1.288), 0.110, 0.115, {upper_bone: 1.0}),
                    ((0.362 * sign, -0.001, 1.258), 0.106, 0.111, {upper_bone: 0.95, forearm_bone: 0.05}),
                    ((0.372 * sign, -0.002, 1.215), 0.103, 0.108, {upper_bone: 0.86, forearm_bone: 0.14}),
                    ((0.377 * sign, -0.002, 1.192), 0.099, 0.104, {upper_bone: 0.80, forearm_bone: 0.20}),
                ],
                "TEAM_Secondary",
                28,
                phase=0.5,
                face_materials=sleeve_faces,
            )
        )

    parts.append(
        weighted_chain_part(
            "Uniform_PelvisBlend",
            [
                ((0.0, 0.012, 1.112), 0.216, 0.136, {"hips": 1.0}),
                ((0.0, 0.012, 1.040), 0.222, 0.142, {"hips": 1.0}),
                ((0.0, 0.012, 1.000), 0.224, 0.143, {"hips": 1.0}),
                ((0.0, 0.012, 0.962), 0.224, 0.144, {"hips": 1.0}),
                ((0.0, 0.011, 0.928), 0.222, 0.142, {"hips": 0.94, "thigh.L": 0.03, "thigh.R": 0.03}),
                ((0.0, 0.010, 0.895), 0.218, 0.140, {"hips": 0.86, "thigh.L": 0.07, "thigh.R": 0.07}),
                ((0.0, 0.008, 0.845), 0.200, 0.130, {"hips": 0.60, "thigh.L": 0.20, "thigh.R": 0.20}),
                ((0.0, 0.006, 0.800), 0.172, 0.116, {"hips": 0.40, "thigh.L": 0.30, "thigh.R": 0.30}),
            ],
            "MAT_Pants",
            28,
            cap_materials=("MAT_Pants", "MAT_Pants"),
        )
    )

    # Each pant leg is closed against the pelvis by construction: the top ring
    # tucks deep inside the pelvis tube with hips-dominated weighting, so deep
    # thigh flexion stretches the tube from an anchored ring instead of
    # opening a crotch or hip gap.  Ring offsets and radii author a knee cap,
    # knee crease, calf bulge, and ankle taper into the silhouette.
    for side, sign in (("L", 1.0), ("R", -1.0)):
        thigh = "thigh." + side
        shin = "shin." + side
        foot = "foot." + side
        outer_column = 27 if sign > 0.0 else 13

        def leg_faces(band, segment, outer=outer_column):
            if band == 13:
                return "TEAM_Accent"  # sock stripe ring
            if band >= 14:
                return "MAT_Sock"  # sock top into the cleat
            if band == 8 and segment in (19, 20, 21):
                return "MAT_PantsShadow"  # knee crease shading
            if 1 <= band <= 12 and segment == outer:
                return "TEAM_Secondary"  # outer-seam piping
            return None

        parts.append(
            weighted_chain_part(
                "Uniform_LegBlend_" + side,
                [
                    ((0.108 * sign, 0.010, 0.960), 0.112, 0.110, {"hips": 0.80, thigh: 0.20}),
                    ((0.126 * sign, 0.009, 0.905), 0.126, 0.124, {"hips": 0.60, thigh: 0.40}),
                    ((0.134 * sign, 0.008, 0.858), 0.134, 0.132, {"hips": 0.42, thigh: 0.58}),
                    ((0.140 * sign, 0.008, 0.778), 0.138, 0.134, {"hips": 0.10, thigh: 0.90}),
                    ((0.140 * sign, 0.007, 0.735), 0.134, 0.131, {thigh: 1.0}),
                    ((0.140 * sign, 0.006, 0.692), 0.128, 0.126, {thigh: 1.0}),
                    ((0.140 * sign, 0.005, 0.640), 0.121, 0.119, {thigh: 0.85, shin: 0.15}),
                    ((0.140 * sign, -0.008, 0.610), 0.117, 0.116, {thigh: 0.70, shin: 0.30}),
                    ((0.140 * sign, -0.004, 0.585), 0.113, 0.112, {thigh: 0.52, shin: 0.48}),
                    ((0.140 * sign, 0.004, 0.556), 0.109, 0.109, {thigh: 0.25, shin: 0.75}),
                    ((0.140 * sign, 0.010, 0.510), 0.105, 0.108, {shin: 1.0}),
                    ((0.140 * sign, 0.014, 0.462), 0.103, 0.108, {shin: 1.0}),
                    ((0.140 * sign, 0.010, 0.415), 0.098, 0.103, {shin: 1.0}),
                    ((0.140 * sign, 0.002, 0.352), 0.089, 0.093, {shin: 1.0}),
                    ((0.140 * sign, -0.003, 0.268), 0.081, 0.085, {shin: 1.0}),
                    ((0.140 * sign, -0.007, 0.214), 0.078, 0.082, {shin: 0.75, foot: 0.25}),
                    ((0.140 * sign, -0.018, 0.158), 0.076, 0.080, {shin: 0.30, foot: 0.70}),
                ],
                "MAT_Pants",
                28,
                phase=0.5,
                face_materials=leg_faces,
            )
        )
    return join_parts(parts, "Uniform_Skinned", "uniform")


def build_hair():
    parts = [
        uv_part("Hair_Crown", (0.0, 0.020, 1.836), (0.151, 0.137, 0.092), "MAT_Hair", "head", 28, 16),
        uv_part("Hair_Back", (0.0, 0.106, 1.748), (0.143, 0.056, 0.137), "MAT_Hair", "head", 24, 14),
        # Two large swept clumps give the crown an authored parting instead of
        # a helmet dome; both stay under the cap line in every review pose.
        uv_part(
            "Hair_SweepClump_L",
            (0.066, -0.052, 1.842),
            (0.078, 0.088, 0.048),
            "MAT_Hair",
            "head",
            14,
            9,
            rotation=(0.0, 10.0 * DEG, -14.0 * DEG),
        ),
        uv_part(
            "Hair_SweepClump_R",
            (-0.070, -0.044, 1.836),
            (0.070, 0.082, 0.044),
            "MAT_HairHighlight",
            "head",
            14,
            9,
            rotation=(0.0, -10.0 * DEG, 14.0 * DEG),
        ),
    ]
    for index, x in enumerate((-0.115, -0.076, -0.038, 0.002, 0.042, 0.079, 0.115)):
        parts.append(
            ico_part(
                "Hair_Fringe_%02d" % index,
                (x, -0.124, 1.820 - abs(x) * 0.14 + (0.005 if index % 2 else 0.0)),
                (0.033, 0.024, 0.058 - abs(x) * 0.05),
                "MAT_HairHighlight" if index in (1, 4) else "MAT_Hair",
                "head",
                2,
                False,
                rotation=(6.0 * DEG, 0.0, x * 1.2),
            )
        )
    for side, sign in (("L", 1.0), ("R", -1.0)):
        parts.append(
            box_part(
                "Hair_Side_" + side,
                (0.132 * sign, -0.016, 1.755),
                (0.023, 0.103, 0.071),
                "MAT_Hair",
                "head",
                rotation=(0.0, 0.0, -7.0 * sign * DEG),
                bevel=0.011,
            )
        )
        parts.append(
            ico_part(
                "Hair_SideTuft_" + side,
                (0.128 * sign, -0.088, 1.742),
                (0.021, 0.028, 0.049),
                "MAT_Hair",
                "head",
                2,
                False,
                rotation=(0.0, -12.0 * sign * DEG, 0.0),
            )
        )
        parts.append(
            ico_part(
                "Hair_Sideburn_" + side,
                (0.139 * sign, -0.071, 1.682),
                (0.015, 0.018, 0.047),
                "MAT_HairHighlight",
                "head",
                2,
                False,
            )
        )
    for index, x in enumerate((-0.102, -0.055, -0.008, 0.040, 0.086)):
        parts.append(
            ico_part(
                "Hair_BackLock_%02d" % index,
                (x, 0.146, 1.708 + (index % 2) * 0.022),
                (0.036, 0.026, 0.066 - abs(x) * 0.06),
                "MAT_Hair" if index != 2 else "MAT_HairHighlight",
                "head",
                2,
                False,
                rotation=(-8.0 * DEG, 0.0, x * 0.9),
            )
        )
    return join_parts(parts, "Hair_Skinned", "hair")


def build_face():
    # A graphic four-value face: coherent warm skin (body mesh), big friendly
    # eyes with bold brows, and one simple mouth plane.  No stubble, teeth,
    # lids, or cheek patches -- those read as mottled noise at gameplay scale
    # and poked through the profile silhouette.
    parts = []
    for side, sign in (("L", 1.0), ("R", -1.0)):
        x = 0.062 * sign
        parts.append(
            box_part(
                "FacePlane_EyeWhite_" + side,
                (x, -0.136, 1.748),
                (0.046, 0.008, 0.028),
                "MAT_EyeWhite",
                "head",
                bevel=0.012,
            )
        )
        parts.append(
            box_part(
                "FacePlane_Iris_" + side,
                (x - 0.006 * sign, -0.146, 1.745),
                (0.020, 0.006, 0.019),
                "MAT_Iris",
                "head",
                bevel=0.008,
            )
        )
        parts.append(
            box_part(
                "FacePlane_Pupil_" + side,
                (x - 0.008 * sign, -0.152, 1.744),
                (0.010, 0.005, 0.011),
                "MAT_Pupil",
                "head",
                bevel=0.004,
            )
        )
        parts.append(
            box_part(
                "FacePlane_EyeGlint_" + side,
                (x - 0.013 * sign, -0.156, 1.752),
                (0.0045, 0.003, 0.005),
                "MAT_EyeWhite",
                "head",
                bevel=0.002,
            )
        )
        parts.append(
            box_part(
                "FacePlane_Brow_" + side,
                (x, -0.148, 1.795),
                (0.052, 0.008, 0.012),
                "MAT_Hair",
                "head",
                rotation=(0.0, 0.0, 8.0 * sign * DEG),
                bevel=0.005,
            )
        )
    parts.append(
        box_part("FacePlane_Mouth", (0.0, -0.158, 1.650), (0.040, 0.008, 0.010), "MAT_Mouth", "head", bevel=0.006)
    )
    return join_parts(parts, "Face_Details_Skinned", "face_planes")


def build_cap():
    # The crown drops over the hairline and the brim is a continuous curved
    # chain whose rear ring is buried inside the crown volume, so the two can
    # never read as separated shells in slide or profile views.  The chain
    # tapers and dips toward the tip for a premium curved-bill silhouette.
    # Seam cylinders and vent dots were subpixel clutter at gameplay scale;
    # the front panel and a bolder accent mark carry the identity instead.
    parts = [
        uv_part(
            "Cap_Crown",
            (0.0, 0.004, 1.866),
            (0.174, 0.160, 0.118),
            "TEAM_Primary",
            "head",
            32,
            18,
        ),
        torus_part("Cap_Band", (0.0, 0.006, 1.826), 0.164, 0.017, "TEAM_Secondary", "head"),
        # Two vertical seam hoops trace the dome like real cap panels; their
        # lower halves are buried inside the crown and head so only the seam
        # arcs over the dome read at review scale.
        torus_part(
            "Cap_SeamFront",
            (0.0, 0.004, 1.850),
            0.138,
            0.008,
            "TEAM_Secondary",
            "head",
            rotation=(0.0, 90.0 * DEG, 0.0),
        ),
        torus_part(
            "Cap_SeamSide",
            (0.0, 0.004, 1.838),
            0.150,
            0.008,
            "TEAM_Secondary",
            "head",
            rotation=(90.0 * DEG, 0.0, 0.0),
        ),
        weighted_chain_part(
            "Cap_BrimCurve",
            [
                ((0.0, 0.020, 1.842), 0.168, 0.021, {"head": 1.0}),
                ((0.0, -0.030, 1.849), 0.166, 0.020, {"head": 1.0}),
                ((0.0, -0.075, 1.852), 0.162, 0.019, {"head": 1.0}),
                ((0.0, -0.124, 1.852), 0.155, 0.018, {"head": 1.0}),
                ((0.0, -0.170, 1.850), 0.146, 0.017, {"head": 1.0}),
                ((0.0, -0.212, 1.845), 0.133, 0.016, {"head": 1.0}),
                ((0.0, -0.250, 1.838), 0.118, 0.015, {"head": 1.0}),
                ((0.0, -0.286, 1.830), 0.098, 0.013, {"head": 1.0}),
                ((0.0, -0.318, 1.820), 0.072, 0.012, {"head": 1.0}),
            ],
            "TEAM_Secondary",
            18,
        ),
        box_part(
            "Cap_FrontPanel",
            (0.0, -0.148, 1.884),
            (0.112, 0.016, 0.068),
            "TEAM_Primary",
            "head",
            rotation=(8.0 * DEG, 0.0, 0.0),
            bevel=0.016,
        ),
        box_part(
            "Cap_MarkStem",
            (-0.020, -0.168, 1.888),
            (0.012, 0.007, 0.042),
            "TEAM_Accent",
            "head",
            rotation=(8.0 * DEG, 0.0, 0.0),
            bevel=0.004,
        ),
        box_part(
            "Cap_MarkTop",
            (0.012, -0.170, 1.916),
            (0.030, 0.007, 0.011),
            "TEAM_Accent",
            "head",
            rotation=(8.0 * DEG, 0.0, 0.0),
            bevel=0.004,
        ),
        box_part(
            "Cap_MarkMid",
            (0.008, -0.170, 1.884),
            (0.024, 0.007, 0.010),
            "TEAM_Accent",
            "head",
            rotation=(8.0 * DEG, 0.0, 0.0),
            bevel=0.004,
        ),
        ico_part("Cap_Button", (0.0, 0.004, 1.976), (0.018, 0.018, 0.014), "TEAM_Secondary", "head", 2, False),
    ]
    return join_parts(parts, "Cap_Skinned", "cap")


def build_cleats():
    # Each shoe is one continuous cross-section chain from the ankle collar
    # over the instep to a rounded, tapered toe, so the sock cone disappears
    # into the collar and the toe box is a sculpted form rather than a slab.
    # Toe rings hand off to the toe bone for toe-off flex.  A flattened
    # separated sole plate, a heel counter, three bold lace bands, a tongue,
    # and chunky studs finish the read without subpixel hardware.
    parts = []
    for side, sign in (("L", 1.0), ("R", -1.0)):
        foot = "foot." + side
        toe = "toe." + side

        def shoe_faces(band, segment):
            return "MAT_CleatEdge" if band >= 10 else None  # toe cap value break

        parts.append(
            weighted_chain_part(
                "Cleat_Shoe_" + side,
                [
                    ((0.140 * sign, 0.030, 0.165), 0.080, 0.056, {foot: 0.85, "shin." + side: 0.15}),
                    ((0.140 * sign, 0.014, 0.152), 0.084, 0.060, {foot: 0.94, "shin." + side: 0.06}),
                    ((0.140 * sign, -0.010, 0.140), 0.088, 0.064, {foot: 1.0}),
                    ((0.140 * sign, -0.042, 0.128), 0.091, 0.066, {foot: 1.0}),
                    ((0.140 * sign, -0.075, 0.116), 0.094, 0.068, {foot: 1.0}),
                    ((0.140 * sign, -0.112, 0.105), 0.096, 0.066, {foot: 0.94, toe: 0.06}),
                    ((0.140 * sign, -0.150, 0.095), 0.098, 0.064, {foot: 0.85, toe: 0.15}),
                    ((0.140 * sign, -0.188, 0.086), 0.097, 0.059, {foot: 0.65, toe: 0.35}),
                    ((0.140 * sign, -0.225, 0.078), 0.094, 0.054, {foot: 0.45, toe: 0.55}),
                    ((0.140 * sign, -0.258, 0.070), 0.088, 0.048, {foot: 0.20, toe: 0.80}),
                    ((0.140 * sign, -0.285, 0.064), 0.079, 0.042, {toe: 1.0}),
                    ((0.140 * sign, -0.306, 0.060), 0.069, 0.036, {toe: 1.0}),
                    ((0.140 * sign, -0.322, 0.056), 0.055, 0.029, {toe: 1.0}),
                ],
                "MAT_Cleat",
                20,
                face_materials=shoe_faces,
                cap_materials=("MAT_Cleat", "MAT_CleatEdge"),
            )
        )
        # The sole is a flattened chain that follows the last, so it tapers
        # with the toe and rounds the heel instead of reading as one slab.
        parts.append(
            weighted_chain_part(
                "Cleat_SolePlate_" + side,
                [
                    ((0.140 * sign, 0.070, 0.038), 0.070, 0.019, {foot: 1.0}),
                    ((0.140 * sign, 0.020, 0.032), 0.092, 0.022, {foot: 1.0}),
                    ((0.140 * sign, -0.060, 0.030), 0.098, 0.022, {foot: 1.0}),
                    ((0.140 * sign, -0.140, 0.028), 0.100, 0.022, {foot: 0.75, toe: 0.25}),
                    ((0.140 * sign, -0.220, 0.026), 0.096, 0.021, {foot: 0.35, toe: 0.65}),
                    ((0.140 * sign, -0.290, 0.026), 0.082, 0.019, {toe: 1.0}),
                    ((0.140 * sign, -0.330, 0.028), 0.058, 0.016, {toe: 1.0}),
                ],
                "MAT_Rubber",
                14,
                smooth=False,
                cap_materials=("MAT_Rubber", "MAT_Rubber"),
            )
        )
        parts.append(
            box_part(
                "Cleat_HeelCounter_" + side,
                (0.140 * sign, 0.048, 0.070),
                (0.084, 0.048, 0.048),
                "MAT_Rubber",
                foot,
                rotation=(-4.0 * DEG, 0.0, 0.0),
                bevel=0.018,
            )
        )
        parts.append(
            box_part(
                "Cleat_Tongue_" + side,
                (0.140 * sign, -0.022, 0.202),
                (0.048, 0.056, 0.016),
                "MAT_CleatEdge",
                foot,
                rotation=(-24.0 * DEG, 0.0, 0.0),
                bevel=0.011,
            )
        )
        # Quarter accent panel plus a swept side stripe give each shoe an
        # authored profile read instead of a black rectangle.
        parts.append(
            box_part(
                "Cleat_QuarterPanel_" + side,
                ((0.140 + 0.086) * sign, -0.028, 0.108),
                (0.010, 0.062, 0.040),
                "MAT_CleatEdge",
                foot,
                rotation=(-10.0 * DEG, 0.0, 0.0),
                bevel=0.008,
            )
        )
        parts.append(
            box_part(
                "Cleat_Stripe_" + side,
                ((0.140 + 0.092) * sign, -0.132, 0.090),
                (0.009, 0.090, 0.020),
                "TEAM_Accent",
                foot,
                rotation=(-6.0 * DEG, 0.0, 0.0),
                bevel=0.006,
            )
        )
        for lace_index, (y, z, tilt) in enumerate(
            ((-0.036, 0.202, -16.0), (-0.078, 0.188, -18.0), (-0.118, 0.174, -20.0), (-0.156, 0.160, -22.0))
        ):
            parts.append(
                box_part(
                    "Cleat_Lace_%s_%d" % (side, lace_index),
                    (0.140 * sign, y, z),
                    (0.056, 0.014, 0.011),
                    "MAT_Sock",
                    foot,
                    rotation=(tilt * DEG, 0.0, 0.0),
                    bevel=0.007,
                )
            )
            # Eyelet value clusters cap each lace band; one bold dot per side
            # survives 128 px where individual metal rings would vanish.
            for eyelet_sign in (1.0, -1.0):
                parts.append(
                    box_part(
                        "Cleat_Eyelet_%s_%d_%s" % (side, lace_index, "a" if eyelet_sign > 0 else "b"),
                        ((0.140 + eyelet_sign * 0.052) * sign, y - 0.004, z - 0.004),
                        (0.009, 0.011, 0.010),
                        "MAT_CleatEdge",
                        foot,
                        rotation=(tilt * DEG, 0.0, 0.0),
                        bevel=0.003,
                    )
                )
        for stud_index, (x, y) in enumerate(((0.105, -0.055), (0.178, -0.055), (0.105, -0.195), (0.178, -0.195), (0.140, -0.290))):
            parts.append(
                cylinder_part(
                    "Cleat_Stud_%s_%d" % (side, stud_index),
                    (x * sign, y, 0.030),
                    (x * sign, y, 0.004),
                    0.019,
                    "MAT_Metal",
                    foot,
                    8,
                    False,
                )
            )
    return join_parts(parts, "Cleats_Skinned", "cleats")


def build_glove():
    # A committed baseball mitt: a deep heel-and-body shell, a clearly darker
    # recessed pocket plate, three bold finger lobes fanned along the top
    # edge, one thick thumb lobe, and a single open web bridge between thumb
    # and index built from a post and a top bar.  Everything is a broad mass
    # that resolves at 128 px; per-finger laces and stitch runs stay banned.
    parts = [
        uv_part("Glove_Shell", (0.468, -0.098, 0.842), (0.128, 0.082, 0.150), "MAT_LeatherLight", "hand.L", 26, 16),
        uv_part("Glove_HeelPad", (0.452, -0.112, 0.772), (0.096, 0.056, 0.062), "MAT_LeatherLight", "hand.L", 16, 10),
        uv_part("Glove_Pocket", (0.470, -0.156, 0.865), (0.092, 0.028, 0.110), "MAT_Leather", "hand.L", 20, 12),
        uv_part(
            "Glove_FingerLobe_A",
            (0.402, -0.098, 0.950),
            (0.036, 0.054, 0.082),
            "MAT_LeatherLight",
            "hand.L",
            14,
            9,
            rotation=(0.0, 14.0 * DEG, 0.0),
        ),
        uv_part(
            "Glove_FingerLobe_B",
            (0.444, -0.104, 0.970),
            (0.038, 0.056, 0.092),
            "MAT_LeatherLight",
            "hand.L",
            14,
            9,
            rotation=(0.0, 5.0 * DEG, 0.0),
        ),
        uv_part(
            "Glove_FingerLobe_C",
            (0.486, -0.103, 0.968),
            (0.038, 0.056, 0.090),
            "MAT_LeatherLight",
            "hand.L",
            14,
            9,
            rotation=(0.0, -5.0 * DEG, 0.0),
        ),
        uv_part(
            "Glove_FingerLobe_D",
            (0.524, -0.098, 0.950),
            (0.036, 0.052, 0.080),
            "MAT_LeatherLight",
            "hand.L",
            14,
            9,
            rotation=(0.0, -14.0 * DEG, 0.0),
        ),
        uv_part(
            "Glove_Thumb",
            (0.556, -0.086, 0.824),
            (0.052, 0.060, 0.112),
            "MAT_LeatherLight",
            "hand.L",
            16,
            10,
            rotation=(0.0, -26.0 * DEG, 0.0),
        ),
        box_part(
            "Glove_WebPost",
            (0.550, -0.108, 0.916),
            (0.017, 0.032, 0.054),
            "MAT_Leather",
            "hand.L",
            rotation=(0.0, 0.0, -18.0 * DEG),
            bevel=0.010,
        ),
        box_part(
            "Glove_WebBar",
            (0.534, -0.110, 0.962),
            (0.048, 0.028, 0.017),
            "MAT_Leather",
            "hand.L",
            rotation=(0.0, 0.0, -15.0 * DEG),
            bevel=0.010,
        ),
        # One clustered cross-lace treatment inside the open web: two bold
        # diagonal straps instead of stitch runs, sized to read at 512 and
        # merge into a single dark X at 128.
        box_part(
            "Glove_WebLace_A",
            (0.540, -0.112, 0.940),
            (0.036, 0.014, 0.009),
            "MAT_Leather",
            "hand.L",
            rotation=(0.0, 0.0, 38.0 * DEG),
            bevel=0.004,
        ),
        box_part(
            "Glove_WebLace_B",
            (0.540, -0.112, 0.940),
            (0.036, 0.014, 0.009),
            "MAT_Leather",
            "hand.L",
            rotation=(0.0, 0.0, -55.0 * DEG),
            bevel=0.004,
        ),
        # A short clustered lace ridge along the thumb-side pocket edge.
        box_part(
            "Glove_EdgeLace",
            (0.548, -0.140, 0.892),
            (0.030, 0.012, 0.012),
            "MAT_Leather",
            "hand.L",
            rotation=(0.0, 0.0, -30.0 * DEG),
            bevel=0.004,
        ),
        uv_part("Glove_CuffPad", (0.448, -0.072, 0.744), (0.084, 0.064, 0.032), "MAT_Leather", "hand.L", 16, 10),
        torus_part(
            "Glove_WristRoll",
            (0.445, -0.070, 0.764),
            0.072,
            0.018,
            "TEAM_Secondary",
            "hand.L",
            rotation=(0.0, 90.0 * DEG, 0.0),
        ),
    ]
    return join_parts(parts, "Glove_Skinned", "glove")


def build_bat():
    # The rest pose carries the bat vertically behind the right shoulder.  The
    # whole prop is rigidly weighted to the hand, and socket_bat_tip provides a
    # stable gameplay endpoint even if this silhouette is later replaced.
    def bat_faces(band, segment):
        if band <= 4:
            return "TEAM_Accent" if band % 2 == 1 else "MAT_BatTape"  # grip wrap bands
        return None

    parts = [
        weighted_chain_part(
            "Bat_TaperedBody",
            [
                ((-0.405, -0.075, 0.752), 0.0230, 0.0230, {"hand.R": 1.0}),
                ((-0.405, -0.075, 0.790), 0.0235, 0.0235, {"hand.R": 1.0}),
                ((-0.405, -0.075, 0.828), 0.0240, 0.0240, {"hand.R": 1.0}),
                ((-0.405, -0.075, 0.866), 0.0245, 0.0245, {"hand.R": 1.0}),
                ((-0.405, -0.075, 0.904), 0.0250, 0.0250, {"hand.R": 1.0}),
                ((-0.405, -0.075, 0.940), 0.0255, 0.0255, {"hand.R": 1.0}),
                ((-0.405, -0.075, 1.010), 0.0272, 0.0272, {"hand.R": 1.0}),
                ((-0.405, -0.075, 1.080), 0.0300, 0.0300, {"hand.R": 1.0}),
                ((-0.405, -0.075, 1.160), 0.0342, 0.0342, {"hand.R": 1.0}),
                ((-0.405, -0.075, 1.240), 0.0392, 0.0392, {"hand.R": 1.0}),
                ((-0.405, -0.075, 1.310), 0.0430, 0.0430, {"hand.R": 1.0}),
                ((-0.405, -0.075, 1.390), 0.0446, 0.0446, {"hand.R": 1.0}),
                ((-0.405, -0.075, 1.460), 0.0452, 0.0452, {"hand.R": 1.0}),
                ((-0.405, -0.075, 1.515), 0.0450, 0.0450, {"hand.R": 1.0}),
            ],
            "MAT_Bat",
            24,
            face_materials=bat_faces,
            cap_materials=("MAT_BatTape", "MAT_Bat"),
        )
    ]
    parts.extend([
        cylinder_part(
            "Bat_Knob", (-0.405, -0.075, 0.730), (-0.405, -0.075, 0.770), 0.034, "MAT_BatTape", "hand.R", 16, True
        ),
        uv_part("Bat_EndCap", (-0.405, -0.075, 1.525), (0.046, 0.046, 0.024), "TEAM_Accent", "hand.R", 16, 8),
        box_part("Bat_Label", (-0.405, -0.121, 1.265), (0.021, 0.004, 0.051), "TEAM_Secondary", "hand.R", bevel=0.006),
    ])
    return join_parts(parts, "Bat_Skinned", "bat")


def solve_hand_targets(targets):
    """Solve one or both three-bone arms to authored grip/release targets.

    Targets are evaluated with Blender's native IK, then immediately baked back
    to ordinary pose transforms.  The exported glTF therefore contains no IK
    constraints or helper objects, only deterministic skeletal keyframes.
    """

    helpers = []
    constraints = []
    affected = []
    for side in ("L", "R"):
        specification = targets.get(side)
        if specification is None:
            continue
        target = bpy.data.objects.new("__IK_Target_" + side, None)
        target.location = tuple(float(value) for value in specification["target"])
        bpy.context.collection.objects.link(target)
        pole = bpy.data.objects.new("__IK_Pole_" + side, None)
        default_pole = (0.78 if side == "L" else -0.78, -0.08, 1.26)
        pole.location = tuple(float(value) for value in specification.get("pole", default_pole))
        bpy.context.collection.objects.link(pole)
        helpers.extend((target, pole))

        hand = RIG.pose.bones["hand." + side]
        constraint = hand.constraints.new("IK")
        constraint.name = "__BAKE_HAND_TARGET__"
        constraint.target = target
        constraint.pole_target = pole
        constraint.chain_count = 3
        constraint.iterations = 96
        constraint.use_tail = True
        constraint.pole_angle = float(specification.get("pole_angle", 0.0)) * DEG
        constraints.append((hand, constraint))
        affected.extend(("upper_arm." + side, "forearm." + side, "hand." + side))

    bpy.context.view_layer.update()
    matrices = {name: RIG.pose.bones[name].matrix.copy() for name in affected}
    for hand, constraint in constraints:
        hand.constraints.remove(constraint)
    bpy.context.view_layer.update()

    # Assign parent-to-child so each saved armature-space matrix is preserved
    # when Blender derives the local basis from its already-restored parent.
    for segment in ("upper_arm", "forearm", "hand"):
        for side in ("L", "R"):
            name = segment + "." + side
            if name in matrices:
                RIG.pose.bones[name].matrix = matrices[name]
                bpy.context.view_layer.update()
    for helper in helpers:
        bpy.data.objects.remove(helper, do_unlink=True)


def key_pose(frame, rotations):
    for pose_bone in RIG.pose.bones:
        pose_bone.rotation_euler = (0.0, 0.0, 0.0)
        pose_bone.location = (0.0, 0.0, 0.0)
    for name, degrees in rotations.items():
        if name == "_root_location":
            RIG.pose.bones["root"].location = tuple(float(value) for value in degrees)
            continue
        if name == "_hand_targets":
            continue
        pose_bone = RIG.pose.bones.get(name)
        if pose_bone is None:
            raise RuntimeError("animation references missing bone " + name)
        pose_bone.rotation_euler = tuple(float(value) * DEG for value in degrees)
    if "_hand_targets" in rotations:
        solve_hand_targets(rotations["_hand_targets"])
    for pose_bone in RIG.pose.bones:
        pose_bone.keyframe_insert(data_path="rotation_euler", frame=frame, group=pose_bone.name)
        if pose_bone.name == "root":
            pose_bone.keyframe_insert(data_path="location", frame=frame, group=pose_bone.name)


def create_action(name, frame_end, poses, loop=False, markers=None):
    action = bpy.data.actions.new(name=name)
    action.use_fake_user = True
    RIG.animation_data.action = action
    for frame, rotations in poses:
        key_pose(frame, rotations)
    for curve in action.fcurves:
        for keyframe in curve.keyframe_points:
            keyframe.interpolation = (
                "BEZIER"
                if name in ("idle", "pitch", "swing", "catch", "field_ready", "field_throw", "celebrate", "slide")
                else "LINEAR"
            )
        if loop:
            modifier = curve.modifiers.new(type="CYCLES")
            modifier.mode_before = "REPEAT"
            modifier.mode_after = "REPEAT"
    action["pixiball_action"] = True
    action["loop"] = loop
    action["frame_start"] = 1
    action["frame_end"] = frame_end
    if markers:
        for marker_name, frame in markers.items():
            marker = action.pose_markers.new(marker_name)
            marker.frame = frame
            action["marker_" + marker_name] = frame
    return action


def build_actions():
    RIG.animation_data_create()
    neutral = {}
    field_ready = {
        "hips": (-12.0, 0.0, 0.0),
        "spine": (14.0, 0.0, 0.0),
        "chest": (10.0, 0.0, -3.0),
        "head": (-8.0, 0.0, 3.0),
        "upper_arm.L": (-52.0, -8.0, 16.0),
        "forearm.L": (-45.0, 0.0, 0.0),
        "upper_arm.R": (-34.0, 6.0, -14.0),
        "forearm.R": (-62.0, 0.0, 0.0),
        "thigh.L": (-30.0, 0.0, -3.0),
        "shin.L": (58.0, 0.0, 0.0),
        "foot.L": (-8.0, 0.0, 0.0),
        "thigh.R": (-30.0, 0.0, 3.0),
        "shin.R": (58.0, 0.0, 0.0),
        "foot.R": (-8.0, 0.0, 0.0),
    }
    create_action(
        "idle",
        61,
        [
            (1, neutral),
            (
                16,
                {
                    "chest": (1.5, 0.0, 0.8),
                    "head": (-0.8, 1.5, -0.5),
                    "upper_arm.L": (2.0, 0.0, -1.0),
                    "upper_arm.R": (-1.0, 0.0, 1.0),
                },
            ),
            (31, {"chest": (-0.6, 0.0, -0.4), "head": (0.5, -1.0, 0.3)}),
            (
                46,
                {
                    "chest": (1.0, 0.0, -0.7),
                    "head": (-0.5, 0.5, 0.4),
                    "upper_arm.L": (-1.0, 0.0, 1.0),
                    "upper_arm.R": (2.0, 0.0, -1.0),
                },
            ),
            (61, neutral),
        ],
        loop=True,
    )
    create_action(
        "run",
        25,
        [
            (
                1,
                {
                    "chest": (5.0, 0.0, -4.0),
                    "upper_arm.L": (-38.0, 0.0, -3.0),
                    "forearm.L": (-18.0, 0.0, 0.0),
                    "upper_arm.R": (42.0, 0.0, 3.0),
                    "forearm.R": (-35.0, 0.0, 0.0),
                    "thigh.L": (42.0, 0.0, 0.0),
                    "shin.L": (-28.0, 0.0, 0.0),
                    "foot.L": (-18.0, 0.0, 0.0),
                    "thigh.R": (-32.0, 0.0, 0.0),
                    "shin.R": (48.0, 0.0, 0.0),
                    "foot.R": (10.0, 0.0, 0.0),
                },
            ),
            (
                7,
                {
                    "chest": (7.0, 0.0, 0.0),
                    "upper_arm.L": (0.0, 0.0, 0.0),
                    "upper_arm.R": (0.0, 0.0, 0.0),
                    "thigh.L": (5.0, 0.0, 0.0),
                    "shin.L": (28.0, 0.0, 0.0),
                    "foot.L": (6.0, 0.0, 0.0),
                    "thigh.R": (5.0, 0.0, 0.0),
                    "shin.R": (28.0, 0.0, 0.0),
                    "foot.R": (-6.0, 0.0, 0.0),
                },
            ),
            (
                13,
                {
                    "chest": (5.0, 0.0, 4.0),
                    "upper_arm.L": (42.0, 0.0, -3.0),
                    "forearm.L": (-35.0, 0.0, 0.0),
                    "upper_arm.R": (-38.0, 0.0, 3.0),
                    "forearm.R": (-18.0, 0.0, 0.0),
                    "thigh.L": (-32.0, 0.0, 0.0),
                    "shin.L": (48.0, 0.0, 0.0),
                    "foot.L": (10.0, 0.0, 0.0),
                    "thigh.R": (42.0, 0.0, 0.0),
                    "shin.R": (-28.0, 0.0, 0.0),
                    "foot.R": (-18.0, 0.0, 0.0),
                },
            ),
            (
                19,
                {
                    "chest": (7.0, 0.0, 0.0),
                    "upper_arm.L": (0.0, 0.0, 0.0),
                    "upper_arm.R": (0.0, 0.0, 0.0),
                    "thigh.L": (5.0, 0.0, 0.0),
                    "shin.L": (28.0, 0.0, 0.0),
                    "foot.L": (-6.0, 0.0, 0.0),
                    "thigh.R": (5.0, 0.0, 0.0),
                    "shin.R": (28.0, 0.0, 0.0),
                    "foot.R": (6.0, 0.0, 0.0),
                },
            ),
            (
                25,
                {
                    "chest": (5.0, 0.0, -4.0),
                    "upper_arm.L": (-38.0, 0.0, -3.0),
                    "forearm.L": (-18.0, 0.0, 0.0),
                    "upper_arm.R": (42.0, 0.0, 3.0),
                    "forearm.R": (-35.0, 0.0, 0.0),
                    "thigh.L": (42.0, 0.0, 0.0),
                    "shin.L": (-28.0, 0.0, 0.0),
                    "foot.L": (-18.0, 0.0, 0.0),
                    "thigh.R": (-32.0, 0.0, 0.0),
                    "shin.R": (48.0, 0.0, 0.0),
                    "foot.R": (10.0, 0.0, 0.0),
                },
            ),
        ],
        loop=True,
    )
    create_action(
        "pitch",
        37,
        [
            (1, neutral),
            (
                7,
                {
                    "hips": (0.0, -10.0, 0.0),
                    "spine": (-4.0, -9.0, -2.0),
                    "chest": (-5.0, -12.0, -3.0),
                    "head": (3.0, 8.0, 2.0),
                    "upper_arm.L": (-42.0, -8.0, 22.0),
                    "forearm.L": (-52.0, 0.0, 0.0),
                    "upper_arm.R": (-35.0, 15.0, -45.0),
                    "forearm.R": (78.0, 0.0, 0.0),
                    "thigh.L": (-55.0, 3.0, 0.0),
                    "shin.L": (82.0, 0.0, 0.0),
                },
            ),
            (
                14,
                {
                    "hips": (0.0, -22.0, 0.0),
                    "spine": (-7.0, -18.0, -3.0),
                    "chest": (-8.0, -28.0, -4.0),
                    "head": (6.0, 20.0, 3.0),
                    "upper_arm.L": (-65.0, -10.0, 35.0),
                    "forearm.L": (-76.0, 0.0, 0.0),
                    "upper_arm.R": (-78.0, 12.0, -58.0),
                    "forearm.R": (108.0, 3.0, -8.0),
                    "hand.R": (-28.0, 0.0, 0.0),
                    "thigh.L": (-78.0, 0.0, 2.0),
                    "shin.L": (112.0, 0.0, 0.0),
                    "foot.L": (-22.0, 0.0, 0.0),
                    "thigh.R": (8.0, 0.0, 0.0),
                    "shin.R": (-10.0, 0.0, 0.0),
                },
            ),
            (
                21,
                {
                    "hips": (0.0, 14.0, 0.0),
                    "spine": (8.0, 16.0, 2.0),
                    "chest": (12.0, 24.0, 4.0),
                    "head": (-7.0, -18.0, -3.0),
                    "upper_arm.L": (25.0, 20.0, -42.0),
                    "forearm.L": (-40.0, 0.0, 0.0),
                    "upper_arm.R": (72.0, -20.0, 46.0),
                    "forearm.R": (-32.0, 8.0, 10.0),
                    "hand.R": (25.0, 0.0, 0.0),
                    "thigh.L": (24.0, 0.0, 0.0),
                    "shin.L": (-18.0, 0.0, 0.0),
                    "thigh.R": (-28.0, 0.0, 0.0),
                    "shin.R": (22.0, 0.0, 0.0),
                },
            ),
            (
                24,
                {
                    "hips": (0.0, 28.0, 0.0),
                    "spine": (18.0, 26.0, 2.0),
                    "chest": (24.0, 35.0, 5.0),
                    "head": (-12.0, -26.0, -4.0),
                    "upper_arm.L": (48.0, 18.0, -52.0),
                    "forearm.L": (-25.0, 0.0, 0.0),
                    "upper_arm.R": (98.0, -18.0, 54.0),
                    "forearm.R": (-12.0, 12.0, 8.0),
                    "hand.R": (42.0, 0.0, 0.0),
                    "thigh.L": (35.0, 0.0, 0.0),
                    "shin.L": (-24.0, 0.0, 0.0),
                    "thigh.R": (-35.0, 0.0, 0.0),
                    "shin.R": (35.0, 0.0, 0.0),
                },
            ),
            (
                31,
                {
                    "hips": (0.0, 38.0, 0.0),
                    "spine": (28.0, 34.0, 3.0),
                    "chest": (34.0, 46.0, 6.0),
                    "head": (-18.0, -34.0, -5.0),
                    "upper_arm.L": (26.0, 12.0, -30.0),
                    "forearm.L": (-55.0, 0.0, 0.0),
                    "upper_arm.R": (62.0, -12.0, 30.0),
                    "forearm.R": (35.0, 6.0, 0.0),
                    "thigh.L": (48.0, 0.0, 0.0),
                    "shin.L": (-12.0, 0.0, 0.0),
                    "thigh.R": (-20.0, 0.0, 0.0),
                    "shin.R": (50.0, 0.0, 0.0),
                },
            ),
            (
                37,
                {
                    "hips": (0.0, 8.0, 0.0),
                    "spine": (8.0, 7.0, 1.0),
                    "chest": (10.0, 8.0, 1.0),
                    "upper_arm.R": (18.0, 0.0, 8.0),
                    "forearm.R": (25.0, 0.0, 0.0),
                    "thigh.L": (12.0, 0.0, 0.0),
                    "shin.R": (15.0, 0.0, 0.0),
                },
            ),
        ],
        markers={"ball_release": 24},
    )
    create_action(
        "swing",
        29,
        [
            (
                1,
                {
                    "hips": (0.0, -12.0, 0.0),
                    "chest": (0.0, -24.0, -2.0),
                    "head": (0.0, 20.0, 1.0),
                    "_hand_targets": {"L": {"target": (-0.14, -0.20, 1.40)}, "R": {"target": (-0.22, -0.18, 1.43)}},
                },
            ),
            (
                8,
                {
                    "hips": (0.0, -30.0, 0.0),
                    "spine": (0.0, -24.0, -2.0),
                    "chest": (0.0, -48.0, -4.0),
                    "head": (0.0, 40.0, 3.0),
                    "thigh.L": (-12.0, 0.0, 0.0),
                    "thigh.R": (8.0, 0.0, 0.0),
                    "_hand_targets": {"L": {"target": (-0.18, -0.15, 1.42)}, "R": {"target": (-0.26, -0.13, 1.45)}},
                },
            ),
            (
                14,
                {
                    "hips": (0.0, -5.0, 0.0),
                    "spine": (2.0, 8.0, 1.0),
                    "chest": (5.0, 18.0, 2.0),
                    "head": (-1.0, -10.0, -1.0),
                    "thigh.L": (10.0, 0.0, 0.0),
                    "thigh.R": (-8.0, 0.0, 0.0),
                    "_hand_targets": {"L": {"target": (-0.08, -0.34, 1.30)}, "R": {"target": (-0.15, -0.34, 1.32)}},
                },
            ),
            (
                19,
                {
                    "_root_location": (0.0, -0.04, 0.0),
                    "hips": (0.0, 32.0, 0.0),
                    "spine": (7.0, 42.0, 3.0),
                    "chest": (10.0, 62.0, 5.0),
                    "head": (-4.0, -48.0, -4.0),
                    "thigh.L": (20.0, 0.0, 0.0),
                    "thigh.R": (-22.0, 0.0, 0.0),
                    "_hand_targets": {"L": {"target": (0.10, -0.46, 1.22)}, "R": {"target": (0.03, -0.48, 1.23)}},
                },
            ),
            (
                25,
                {
                    "_root_location": (0.0, -0.06, 0.0),
                    "hips": (0.0, 58.0, 0.0),
                    "spine": (12.0, 64.0, 4.0),
                    "chest": (16.0, 96.0, 7.0),
                    "head": (-8.0, -76.0, -6.0),
                    "thigh.L": (18.0, 0.0, 0.0),
                    "thigh.R": (-18.0, 0.0, 0.0),
                    "_hand_targets": {"L": {"target": (0.30, -0.18, 1.43)}, "R": {"target": (0.24, -0.21, 1.46)}},
                },
            ),
            (
                29,
                {
                    "hips": (0.0, 20.0, 0.0),
                    "spine": (5.0, 24.0, 2.0),
                    "chest": (8.0, 32.0, 3.0),
                    "head": (-4.0, -20.0, -2.0),
                    "_hand_targets": {"L": {"target": (0.15, -0.19, 1.25)}, "R": {"target": (0.08, -0.20, 1.27)}},
                },
            ),
        ],
        markers={"bat_contact": 19},
    )
    create_action(
        "catch",
        25,
        [
            (1, neutral),
            (
                7,
                {
                    "hips": (-8.0, 0.0, 0.0),
                    "spine": (12.0, 0.0, 0.0),
                    "chest": (12.0, 0.0, -4.0),
                    "upper_arm.L": (-70.0, -12.0, 18.0),
                    "forearm.L": (-55.0, 0.0, 0.0),
                    "upper_arm.R": (-25.0, 8.0, -18.0),
                    "forearm.R": (-48.0, 0.0, 0.0),
                    "thigh.L": (-25.0, 0.0, 0.0),
                    "shin.L": (42.0, 0.0, 0.0),
                    "thigh.R": (-25.0, 0.0, 0.0),
                    "shin.R": (42.0, 0.0, 0.0),
                },
            ),
            (
                14,
                {
                    "hips": (-16.0, 0.0, 0.0),
                    "spine": (20.0, 0.0, 0.0),
                    "chest": (18.0, 0.0, -8.0),
                    "head": (-8.0, 0.0, 6.0),
                    "upper_arm.L": (-102.0, -16.0, 28.0),
                    "forearm.L": (-35.0, 0.0, 0.0),
                    "hand.L": (-18.0, 0.0, 0.0),
                    "upper_arm.R": (-48.0, 10.0, -28.0),
                    "forearm.R": (-60.0, 0.0, 0.0),
                    "thigh.L": (-38.0, 0.0, 0.0),
                    "shin.L": (64.0, 0.0, 0.0),
                    "thigh.R": (-38.0, 0.0, 0.0),
                    "shin.R": (64.0, 0.0, 0.0),
                },
            ),
            (
                17,
                {
                    "hips": (-12.0, 0.0, 0.0),
                    "spine": (16.0, 0.0, 0.0),
                    "chest": (14.0, 0.0, -6.0),
                    "head": (-5.0, 0.0, 5.0),
                    "upper_arm.L": (-88.0, -12.0, 22.0),
                    "forearm.L": (-62.0, 0.0, 0.0),
                    "upper_arm.R": (-58.0, 8.0, -22.0),
                    "forearm.R": (-74.0, 0.0, 0.0),
                    "thigh.L": (-30.0, 0.0, 0.0),
                    "shin.L": (52.0, 0.0, 0.0),
                    "thigh.R": (-30.0, 0.0, 0.0),
                    "shin.R": (52.0, 0.0, 0.0),
                },
            ),
            (
                25,
                {
                    "hips": (-3.0, 0.0, 0.0),
                    "spine": (5.0, 0.0, 0.0),
                    "upper_arm.L": (-25.0, 0.0, 8.0),
                    "forearm.L": (-30.0, 0.0, 0.0),
                    "upper_arm.R": (-18.0, 0.0, -6.0),
                    "forearm.R": (-22.0, 0.0, 0.0),
                    "thigh.L": (-8.0, 0.0, 0.0),
                    "shin.L": (12.0, 0.0, 0.0),
                    "thigh.R": (-8.0, 0.0, 0.0),
                    "shin.R": (12.0, 0.0, 0.0),
                },
            ),
        ],
        markers={"glove_contact": 14},
    )
    create_action(
        "field_ready",
        31,
        [
            (1, field_ready),
            (
                8,
                {
                    **field_ready,
                    "hips": (-14.0, -3.0, -2.0),
                    "spine": (16.0, -4.0, 1.0),
                    "head": (-9.0, 5.0, 2.0),
                    "upper_arm.L": (-58.0, -10.0, 19.0),
                    "thigh.L": (-33.0, 0.0, -4.0),
                    "shin.L": (62.0, 0.0, 0.0),
                },
            ),
            (
                16,
                {
                    **field_ready,
                    "hips": (-11.0, 4.0, 2.0),
                    "spine": (13.0, 5.0, -1.0),
                    "head": (-7.0, -6.0, 4.0),
                    "upper_arm.R": (-39.0, 8.0, -17.0),
                    "thigh.R": (-34.0, 0.0, 4.0),
                    "shin.R": (63.0, 0.0, 0.0),
                },
            ),
            (
                24,
                {
                    **field_ready,
                    "hips": (-13.0, 2.0, 1.0),
                    "chest": (12.0, 2.0, -4.0),
                    "head": (-9.0, -3.0, 2.0),
                    "upper_arm.L": (-55.0, -9.0, 18.0),
                    "forearm.R": (-66.0, 0.0, 0.0),
                },
            ),
            (31, field_ready),
        ],
        loop=True,
    )
    create_action(
        "field_throw",
        31,
        [
            (1, field_ready),
            (
                6,
                {
                    "hips": (-14.0, -8.0, 0.0),
                    "spine": (15.0, -10.0, -1.0),
                    "chest": (12.0, -14.0, -3.0),
                    "head": (-8.0, 11.0, 3.0),
                    "upper_arm.L": (-72.0, -8.0, 24.0),
                    "forearm.L": (-74.0, 0.0, 0.0),
                    "upper_arm.R": (-62.0, 10.0, -25.0),
                    "forearm.R": (-80.0, 0.0, 0.0),
                    "thigh.L": (-34.0, 0.0, -3.0),
                    "shin.L": (62.0, 0.0, 0.0),
                    "thigh.R": (-28.0, 0.0, 3.0),
                    "shin.R": (54.0, 0.0, 0.0),
                },
            ),
            (
                11,
                {
                    "hips": (-4.0, -27.0, 0.0),
                    "spine": (5.0, -27.0, -2.0),
                    "chest": (8.0, -38.0, -4.0),
                    "head": (-4.0, 28.0, 3.0),
                    "upper_arm.L": (-48.0, -8.0, 34.0),
                    "forearm.L": (-52.0, 0.0, 0.0),
                    "upper_arm.R": (-80.0, 15.0, -63.0),
                    "forearm.R": (110.0, 3.0, -8.0),
                    "hand.R": (-26.0, 0.0, 0.0),
                    "thigh.L": (-20.0, 0.0, -2.0),
                    "shin.L": (35.0, 0.0, 0.0),
                    "thigh.R": (12.0, 0.0, 2.0),
                    "shin.R": (-5.0, 0.0, 0.0),
                },
            ),
            (
                16,
                {
                    "_root_location": (0.0, -0.05, 0.0),
                    "hips": (3.0, 12.0, 0.0),
                    "spine": (8.0, 16.0, 1.0),
                    "chest": (12.0, 22.0, 3.0),
                    "head": (-6.0, -17.0, -2.0),
                    "upper_arm.L": (22.0, 15.0, -40.0),
                    "forearm.L": (-42.0, 0.0, 0.0),
                    "upper_arm.R": (68.0, -18.0, 48.0),
                    "forearm.R": (-30.0, 8.0, 8.0),
                    "hand.R": (22.0, 0.0, 0.0),
                    "thigh.L": (18.0, 0.0, -2.0),
                    "shin.L": (-12.0, 0.0, 0.0),
                    "thigh.R": (-24.0, 0.0, 2.0),
                    "shin.R": (24.0, 0.0, 0.0),
                },
            ),
            (
                18,
                {
                    "_root_location": (0.0, -0.09, 0.0),
                    "hips": (8.0, 28.0, 0.0),
                    "spine": (14.0, 32.0, 2.0),
                    "chest": (18.0, 42.0, 5.0),
                    "head": (-10.0, -32.0, -4.0),
                    "upper_arm.L": (35.0, 12.0, -45.0),
                    "forearm.L": (-30.0, 0.0, 0.0),
                    "upper_arm.R": (105.0, -16.0, 58.0),
                    "forearm.R": (-8.0, 12.0, 8.0),
                    "hand.R": (38.0, 0.0, 0.0),
                    "thigh.L": (28.0, 0.0, -2.0),
                    "shin.L": (-18.0, 0.0, 0.0),
                    "thigh.R": (-28.0, 0.0, 2.0),
                    "shin.R": (28.0, 0.0, 0.0),
                },
            ),
            (
                24,
                {
                    "_root_location": (0.0, -0.12, 0.0),
                    "hips": (18.0, 46.0, 0.0),
                    "spine": (26.0, 54.0, 3.0),
                    "chest": (30.0, 68.0, 6.0),
                    "head": (-15.0, -48.0, -5.0),
                    "upper_arm.L": (18.0, 8.0, -25.0),
                    "forearm.L": (-48.0, 0.0, 0.0),
                    "upper_arm.R": (72.0, -8.0, 25.0),
                    "forearm.R": (38.0, 5.0, 0.0),
                    "thigh.L": (36.0, 0.0, -2.0),
                    "shin.L": (-10.0, 0.0, 0.0),
                    "thigh.R": (-16.0, 0.0, 2.0),
                    "shin.R": (42.0, 0.0, 0.0),
                },
            ),
            (
                31,
                {
                    **field_ready,
                    "hips": (-8.0, 6.0, 0.0),
                    "spine": (12.0, 8.0, 0.0),
                    "chest": (9.0, 9.0, -2.0),
                },
            ),
        ],
        markers={"ball_release": 18},
    )
    create_action(
        "celebrate",
        49,
        [
            (1, neutral),
            (
                8,
                {
                    "hips": (-18.0, 0.0, 0.0),
                    "spine": (18.0, 0.0, 0.0),
                    "chest": (12.0, 0.0, -3.0),
                    "head": (-8.0, 0.0, 4.0),
                    "upper_arm.L": (-48.0, -8.0, 20.0),
                    "forearm.L": (-62.0, 0.0, 0.0),
                    "upper_arm.R": (-48.0, 8.0, -20.0),
                    "forearm.R": (-62.0, 0.0, 0.0),
                    "thigh.L": (-36.0, 0.0, -3.0),
                    "shin.L": (68.0, 0.0, 0.0),
                    "thigh.R": (-36.0, 0.0, 3.0),
                    "shin.R": (68.0, 0.0, 0.0),
                },
            ),
            (
                16,
                {
                    "_root_location": (0.0, 0.0, 0.06),
                    "hips": (8.0, 0.0, 0.0),
                    "spine": (-8.0, 0.0, 0.0),
                    "chest": (-14.0, 0.0, 0.0),
                    "head": (8.0, 0.0, 0.0),
                    "upper_arm.L": (-118.0, -8.0, 24.0),
                    "forearm.L": (-28.0, 0.0, 0.0),
                    "upper_arm.R": (-118.0, 8.0, -24.0),
                    "forearm.R": (-28.0, 0.0, 0.0),
                    "thigh.L": (14.0, 0.0, -2.0),
                    "shin.L": (-20.0, 0.0, 0.0),
                    "thigh.R": (14.0, 0.0, 2.0),
                    "shin.R": (-20.0, 0.0, 0.0),
                },
            ),
            (
                24,
                {
                    "_root_location": (0.0, 0.0, 0.14),
                    "hips": (12.0, 0.0, 0.0),
                    "spine": (-12.0, 0.0, 0.0),
                    "chest": (-20.0, 0.0, 0.0),
                    "head": (12.0, 0.0, 0.0),
                    "upper_arm.L": (-158.0, -10.0, 28.0),
                    "forearm.L": (-18.0, 0.0, 0.0),
                    "hand.L": (-16.0, 0.0, 0.0),
                    "upper_arm.R": (-158.0, 10.0, -28.0),
                    "forearm.R": (-18.0, 0.0, 0.0),
                    "hand.R": (-16.0, 0.0, 0.0),
                    "thigh.L": (25.0, 0.0, -3.0),
                    "shin.L": (-28.0, 0.0, 0.0),
                    "thigh.R": (25.0, 0.0, 3.0),
                    "shin.R": (-28.0, 0.0, 0.0),
                },
            ),
            (
                32,
                {
                    "_root_location": (0.0, 0.0, 0.02),
                    "hips": (-12.0, 18.0, 0.0),
                    "spine": (12.0, 22.0, 1.0),
                    "chest": (8.0, 28.0, 2.0),
                    "head": (-7.0, -20.0, -2.0),
                    "upper_arm.L": (-68.0, -8.0, 20.0),
                    "forearm.L": (-74.0, 0.0, 0.0),
                    "upper_arm.R": (-142.0, 8.0, -18.0),
                    "forearm.R": (-48.0, 0.0, 0.0),
                    "hand.R": (-34.0, 0.0, 0.0),
                    "thigh.L": (-28.0, 0.0, -3.0),
                    "shin.L": (54.0, 0.0, 0.0),
                    "thigh.R": (-24.0, 0.0, 3.0),
                    "shin.R": (48.0, 0.0, 0.0),
                },
            ),
            (
                40,
                {
                    "hips": (-4.0, -14.0, 0.0),
                    "spine": (5.0, -16.0, -1.0),
                    "chest": (2.0, -22.0, -2.0),
                    "head": (-3.0, 18.0, 2.0),
                    "upper_arm.L": (-112.0, -6.0, 52.0),
                    "forearm.L": (-28.0, 0.0, 0.0),
                    "upper_arm.R": (-112.0, 6.0, -52.0),
                    "forearm.R": (-28.0, 0.0, 0.0),
                    "thigh.L": (-10.0, 0.0, -2.0),
                    "shin.L": (18.0, 0.0, 0.0),
                    "thigh.R": (-10.0, 0.0, 2.0),
                    "shin.R": (18.0, 0.0, 0.0),
                },
            ),
            (49, neutral),
        ],
        markers={"celebration_peak": 24},
    )
    create_action(
        "slide",
        39,
        [
            (
                1,
                {
                    "hips": (5.0, 0.0, -3.0),
                    "spine": (8.0, 0.0, 2.0),
                    "chest": (7.0, 0.0, 2.0),
                    "upper_arm.L": (-38.0, 0.0, -4.0),
                    "upper_arm.R": (42.0, 0.0, 4.0),
                    "thigh.L": (42.0, 0.0, -2.0),
                    "shin.L": (-24.0, 0.0, 0.0),
                    "thigh.R": (-30.0, 0.0, 2.0),
                    "shin.R": (46.0, 0.0, 0.0),
                },
            ),
            (
                8,
                {
                    "_root_location": (0.0, 0.08, 0.08),
                    "root": (-10.0, 0.0, 0.0),
                    "hips": (-22.0, 0.0, 0.0),
                    "spine": (18.0, 0.0, 0.0),
                    "chest": (14.0, 0.0, 0.0),
                    "head": (-9.0, 0.0, 0.0),
                    "upper_arm.L": (34.0, 0.0, -30.0),
                    "forearm.L": (-22.0, 0.0, 0.0),
                    "upper_arm.R": (28.0, 0.0, 30.0),
                    "forearm.R": (-26.0, 0.0, 0.0),
                    "thigh.L": (22.0, 0.0, -3.0),
                    "shin.L": (-8.0, 0.0, 0.0),
                    "thigh.R": (-20.0, 0.0, 4.0),
                    "shin.R": (42.0, 0.0, 0.0),
                },
            ),
            (
                16,
                {
                    "_root_location": (0.0, 0.18, 0.16),
                    "root": (-42.0, 0.0, 0.0),
                    "hips": (8.0, 0.0, 0.0),
                    "spine": (-8.0, 0.0, -3.0),
                    "chest": (-12.0, 0.0, -4.0),
                    "head": (8.0, 0.0, 4.0),
                    "upper_arm.L": (58.0, -5.0, -42.0),
                    "forearm.L": (18.0, 0.0, 0.0),
                    "upper_arm.R": (52.0, 5.0, 42.0),
                    "forearm.R": (22.0, 0.0, 0.0),
                    "thigh.L": (15.0, 0.0, -4.0),
                    "shin.L": (-10.0, 0.0, 0.0),
                    "foot.L": (5.0, 0.0, 0.0),
                    "thigh.R": (-18.0, 0.0, 5.0),
                    "shin.R": (40.0, 0.0, 0.0),
                    "foot.R": (-8.0, 0.0, 0.0),
                },
            ),
            (
                22,
                {
                    "_root_location": (0.0, 0.25, 0.24),
                    "root": (-70.0, 0.0, 0.0),
                    "hips": (12.0, 0.0, 0.0),
                    "spine": (-10.0, 0.0, -4.0),
                    "chest": (-16.0, 0.0, -5.0),
                    "head": (12.0, 0.0, 5.0),
                    "upper_arm.L": (64.0, -6.0, -50.0),
                    "forearm.L": (26.0, 0.0, 0.0),
                    "upper_arm.R": (58.0, 6.0, 50.0),
                    "forearm.R": (30.0, 0.0, 0.0),
                    "thigh.L": (10.0, 0.0, -4.0),
                    "shin.L": (-10.0, 0.0, 0.0),
                    "foot.L": (5.0, 0.0, 0.0),
                    "thigh.R": (-15.0, 0.0, 5.0),
                    "shin.R": (35.0, 0.0, 0.0),
                    "foot.R": (-8.0, 0.0, 0.0),
                },
            ),
            (
                30,
                {
                    "_root_location": (0.0, 0.22, 0.32),
                    "root": (-55.0, 0.0, 0.0),
                    "hips": (8.0, 8.0, 0.0),
                    "spine": (-4.0, 10.0, -2.0),
                    "chest": (-8.0, 12.0, -3.0),
                    "head": (8.0, -9.0, 3.0),
                    "upper_arm.L": (50.0, -4.0, -38.0),
                    "forearm.L": (38.0, 0.0, 0.0),
                    "upper_arm.R": (46.0, 4.0, 38.0),
                    "forearm.R": (42.0, 0.0, 0.0),
                    "thigh.L": (12.0, 0.0, -3.0),
                    "shin.L": (-8.0, 0.0, 0.0),
                    "thigh.R": (-18.0, 0.0, 4.0),
                    "shin.R": (45.0, 0.0, 0.0),
                },
            ),
            (
                39,
                {
                    "_root_location": (0.0, 0.16, 0.38),
                    "root": (-32.0, 0.0, 0.0),
                    "hips": (-4.0, 14.0, 0.0),
                    "spine": (10.0, 16.0, 0.0),
                    "chest": (8.0, 18.0, -2.0),
                    "head": (-6.0, -12.0, 2.0),
                    "upper_arm.L": (22.0, 0.0, -20.0),
                    "forearm.L": (52.0, 0.0, 0.0),
                    "upper_arm.R": (18.0, 0.0, 20.0),
                    "forearm.R": (55.0, 0.0, 0.0),
                    "thigh.L": (8.0, 0.0, -3.0),
                    "shin.L": (0.0, 0.0, 0.0),
                    "thigh.R": (-22.0, 0.0, 3.0),
                    "shin.R": (55.0, 0.0, 0.0),
                },
            ),
        ],
        markers={"base_contact": 22},
    )
    RIG.animation_data.action = None
    for pose_bone in RIG.pose.bones:
        pose_bone.rotation_euler = (0.0, 0.0, 0.0)
        pose_bone.location = (0.0, 0.0, 0.0)


def finish_scene(meshes):
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = 30
    scene.frame_start = 1
    scene.frame_end = 61
    scene["agent_recipe"] = Path(__file__).name
    scene["agent_recipe_version"] = ASSET_VERSION
    scene["asset_name"] = "Pixiball Ballplayer"
    scene["asset_style"] = "premium hybrid pixel-art baseball athlete"
    scene["license"] = "original project asset"
    scene["nominal_height_m"] = 1.98
    scene["actions"] = "idle,run,pitch,swing,catch,field_ready,field_throw,celebrate,slide"
    scene["team_materials"] = "TEAM_Primary,TEAM_Secondary,TEAM_Accent"
    scene["attachment_sockets"] = (
        "socket_head,socket_chest,socket_glove,socket_catch,socket_bat,socket_ball,socket_bat_tip,socket_foot.L,socket_foot.R"
    )

    # Blender's +Y becomes Godot's -Z.  Rotate and apply the authored -Y-facing
    # construction once so the exported asset has the engine's canonical
    # forward direction while every production object keeps identity rotation.
    bpy.ops.object.select_all(action="DESELECT")
    for obj in [RIG] + meshes:
        obj.rotation_euler.z = math.pi
        obj.select_set(True)
    bpy.context.view_layer.objects.active = RIG
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)

    root = bpy.data.objects.new("Ballplayer_AssetRoot", None)
    bpy.context.collection.objects.link(root)
    root.empty_display_type = "PLAIN_AXES"
    root["semantic_role"] = "ballplayer_asset_root"
    root["asset_contract_version"] = ASSET_VERSION
    root["source_recipe"] = Path(__file__).name
    RIG.parent = root
    for mesh in meshes:
        mesh.parent = root

    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    bpy.context.view_layer.objects.active = root
    scene.frame_set(1)


def main():
    reset_scene()
    build_materials()
    create_rig()
    meshes = [
        build_body(),
        build_uniform(),
        build_hair(),
        build_face(),
        build_cap(),
        build_cleats(),
        build_glove(),
        build_bat(),
    ]
    build_actions()
    finish_scene(meshes)


if __name__ == "__main__":
    main()
