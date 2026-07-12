"""Build Pixiball's deterministic, original, production ballplayer asset.

The recipe deliberately uses only Blender's bundled Python API.  Every visible
piece is weighted to the shared armature, even when a piece is rigid, so the
result remains easy to art-direct while exporting as a conventional skinned
glTF. Version 13 targets a lean professional-athlete silhouette with stable
foot mechanics: naturalistic adult proportions (a 7.5-heads figure with an
anatomically sized skull), a fully sculpted face with recessed eyeballs,
lids, nose, lips, and ears, muscle bellies and cloth response authored into
the deforming ring surfaces, physically based material response (subsurface
skin, fabric, leather, lacquered wood), and subdivision-level density in the
hundreds of thousands of triangles.  No third-party character, scan, or
texture data is used.
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Euler, Matrix, Vector
from mathutils.bvhtree import BVHTree

# Professionally sculpted CC0 head (Blender Studio "Human Base Meshes"
# bundle, animation-topology realistic head with layered eye parts),
# vendored beside the production .blend.  Landmarks below were measured from
# the vendored file; the fit maps its interpupillary line onto the rig's
# authored eye targets.
CC0_HEAD_BLEND = "cc0_head_base.blend"
CC0_HEAD_OBJECTS = {
    "head": "GEO-head_animation_realistic",
    "sclera_l": "GEO-head_animation_realistic.sclera.L",
    "sclera_r": "GEO-head_animation_realistic.sclera.R",
    "iris_l": "GEO-head_animation_realistic.iris.L",
    "iris_r": "GEO-head_animation_realistic.iris.R",
}
CC0_SRC_EYE_MID = Vector((1.4626, -0.1203, 0.7667))
CC0_SRC_INTERPUPIL = 0.0632
CC0_TARGET_EYE_MID = Vector((0.0, -0.072, 1.732))
CC0_TARGET_INTERPUPIL = 0.060
CC0_NECK_CUT_Z = 1.578
CC0_NECK_BLEND_TOP = 1.664

ASSET_VERSION = 13
DEG = math.pi / 180.0
RIG = None
MATERIALS = {}
CC0_PROBE = None
CC0_EYE_PARTS = []

# Realistic default wardrobe/character colors (classic road-gray uniform with
# navy and red trim).  TEAM_* values are the neutral defaults baked into the
# GLB; gameplay recolors those slots per team at runtime, and skin/hair are
# reseeded per player by the actor.
PALETTE = {
    "skin": "c28257",
    "skin_light": "d69c6e",
    "lip": "ad6b52",
    "hair": "2c1c12",
    "hair_light": "4a3320",
    "team_primary": "20395c",
    "team_secondary": "9e2f2a",
    "team_accent": "cfa14a",
    "cream": "e8e4d8",
    "cream_shadow": "c5c0b1",
    "belt": "241d18",
    "mitt": "7a4526",
    "mitt_dark": "4c2814",
    "bat": "b57a42",
    "tape": "2a231d",
    "cleat": "1d222d",
    "cleat_trim": "d8d4c8",
    "metal": "9aa1a8",
}


def srgb(hex_value):
    """Convert an sRGB hex string to Blender's linear-space color tuple."""

    text = hex_value.lstrip("#")
    channels = tuple(int(text[index : index + 2], 16) / 255.0 for index in (0, 2, 4))
    return tuple(
        channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4
        for channel in channels
    )


def reset_scene():
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.armatures, bpy.data.materials):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def material(
    name,
    color,
    roughness=0.72,
    metallic=0.0,
    specular_ior=0.32,
    coat_weight=0.0,
    coat_roughness=0.25,
    subsurface_weight=0.0,
):
    value = bpy.data.materials.new(name)
    value.diffuse_color = (*color, 1.0)
    value.use_nodes = True
    shader = value.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    specular = shader.inputs.get("Specular IOR Level")
    if specular is not None:
        specular.default_value = specular_ior
    coat = shader.inputs.get("Coat Weight")
    if coat is not None:
        coat.default_value = coat_weight
    coat_roughness_input = shader.inputs.get("Coat Roughness")
    if coat_roughness_input is not None:
        coat_roughness_input.default_value = coat_roughness
    subsurface = shader.inputs.get("Subsurface Weight")
    if subsurface is not None:
        subsurface.default_value = subsurface_weight
    value["pixiball_material"] = True
    if name.startswith("TEAM_"):
        value["team_color_slot"] = name.removeprefix("TEAM_").lower()
    MATERIALS[name] = value
    return value


def radial_profile(segments, phase, bumps, base=1.0):
    """Build a per-segment radius-multiplier list from angular bumps.

    ``bumps`` is a sequence of ``(center_deg, width_deg, amplitude)`` tuples
    in the chain ring-angle frame (the front of an upward chain sits at 270
    degrees).  Each bump adds a smooth raised-cosine lobe, so eye sockets,
    brow ridges, cheekbones, muscle bellies, and cloth folds can be sculpted
    directly into the deforming ring surfaces instead of bolted on as
    separate primitives.
    """

    values = []
    for segment in range(segments):
        angle = 360.0 * (float(segment) + float(phase)) / float(segments)
        value = float(base)
        for center, width, amplitude in bumps:
            delta = (angle - float(center) + 180.0) % 360.0 - 180.0
            if abs(delta) < float(width):
                value += float(amplitude) * 0.5 * (1.0 + math.cos(math.pi * delta / float(width)))
        values.append(value)
    return values


def build_materials():
    # Physically based wardrobe: sweat-sheened subsurface skin, wet layered
    # eyes, polyester double-knit cloth, oiled leather, lacquered maple, and
    # brushed steel.  The realism read comes from distinct micro-response per
    # family; the actor's runtime shader mirrors these families in-engine.
    material("MAT_Skin", srgb(PALETTE["skin"]), roughness=0.52, specular_ior=0.40, subsurface_weight=0.06)
    material("MAT_SkinLight", srgb(PALETTE["skin_light"]), roughness=0.55, specular_ior=0.38, subsurface_weight=0.09)
    material("MAT_Lip", srgb(PALETTE["lip"]), roughness=0.42, specular_ior=0.44, subsurface_weight=0.13)
    material("MAT_Nostril", (0.012, 0.006, 0.005), roughness=0.7, specular_ior=0.2)
    material("MAT_Hair", srgb(PALETTE["hair"]), roughness=0.46, specular_ior=0.42, coat_weight=0.12, coat_roughness=0.35)
    material("MAT_HairHighlight", srgb(PALETTE["hair_light"]), roughness=0.42, specular_ior=0.44, coat_weight=0.14, coat_roughness=0.32)
    # Layered wet eyes: bright sclera with a glossy film, a matte-fibrous
    # iris, and a near-black pupil.  The corneal glint comes from the low
    # sclera roughness under the key light.
    material("MAT_EyeWhite", (0.86, 0.85, 0.83), roughness=0.09, specular_ior=0.52, coat_weight=0.35, coat_roughness=0.06)
    material("MAT_Iris", srgb("5d3a1f"), roughness=0.30, specular_ior=0.40, coat_weight=0.30, coat_roughness=0.08)
    material("MAT_Pupil", (0.004, 0.004, 0.005), roughness=0.12, specular_ior=0.45, coat_weight=0.30, coat_roughness=0.06)
    material("TEAM_Primary", srgb(PALETTE["team_primary"]), roughness=0.74, specular_ior=0.26)
    material("TEAM_Secondary", srgb(PALETTE["team_secondary"]), roughness=0.74, specular_ior=0.26)
    material("TEAM_Accent", srgb(PALETTE["team_accent"]), roughness=0.68, specular_ior=0.3)
    material("MAT_Pants", srgb(PALETTE["cream"]), roughness=0.78, specular_ior=0.24)
    material("MAT_PantsShadow", srgb(PALETTE["cream_shadow"]), roughness=0.8, specular_ior=0.22)
    material("MAT_Belt", srgb(PALETTE["belt"]), roughness=0.38, specular_ior=0.4, coat_weight=0.18, coat_roughness=0.2)
    material("MAT_Leather", srgb(PALETTE["mitt_dark"]), roughness=0.5, specular_ior=0.38, coat_weight=0.12)
    material("MAT_LeatherLight", srgb(PALETTE["mitt"]), roughness=0.46, specular_ior=0.4, coat_weight=0.14)
    material("MAT_Bat", srgb(PALETTE["bat"]), roughness=0.24, specular_ior=0.46, coat_weight=0.35, coat_roughness=0.12)
    material("MAT_BatTape", srgb(PALETTE["tape"]), roughness=0.82, specular_ior=0.2)
    material("MAT_Cleat", srgb(PALETTE["cleat"]), roughness=0.3, specular_ior=0.44, coat_weight=0.25, coat_roughness=0.15)
    material("MAT_CleatEdge", srgb(PALETTE["cleat_trim"]), roughness=0.62, specular_ior=0.3)
    material("MAT_Rubber", (0.012, 0.017, 0.025), roughness=0.72, specular_ior=0.28)
    material("MAT_Metal", srgb(PALETTE["metal"]), roughness=0.22, metallic=0.85, specular_ior=0.45)


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
        # Realistic cervical proportions: a short exposed neck above the
        # collar and a naturalistic 0.28 m head-bone span, sized so the
        # figure reads about 7.7 heads tall against the fixed shoulder line.
        ("neck", (0.0, 0.0, 1.48), (0.0, 0.0, 1.56), "chest", True),
        ("head", (0.0, 0.0, 1.56), (0.0, 0.0, 1.84), "neck", True),
        ("clavicle.L", (0.0, 0.0, 1.43), (0.235, 0.0, 1.43), "chest", True),
        ("upper_arm.L", (0.235, 0.0, 1.43), (0.365, 0.0, 1.16), "clavicle.L", True),
        ("forearm.L", (0.365, 0.0, 1.16), (0.405, -0.005, 0.91), "upper_arm.L", True),
        ("hand.L", (0.405, -0.005, 0.91), (0.405, -0.045, 0.77), "forearm.L", True),
        ("clavicle.R", (0.0, 0.0, 1.43), (-0.235, 0.0, 1.43), "chest", True),
        ("upper_arm.R", (-0.235, 0.0, 1.43), (-0.365, 0.0, 1.16), "clavicle.R", True),
        ("forearm.R", (-0.365, 0.0, 1.16), (-0.405, -0.005, 0.91), "upper_arm.R", True),
        ("hand.R", (-0.405, -0.005, 0.91), (-0.405, -0.045, 0.77), "forearm.R", True),
        ("thigh.L", (0.14, 0.0, 1.01), (0.14, 0.006, 0.59), "hips", True),
        ("shin.L", (0.14, 0.006, 0.59), (0.14, 0.0, 0.17), "thigh.L", True),
        ("foot.L", (0.14, 0.0, 0.17), (0.14, -0.22, 0.075), "shin.L", True),
        ("toe.L", (0.14, -0.22, 0.075), (0.14, -0.34, 0.07), "foot.L", True),
        ("thigh.R", (-0.14, 0.0, 1.01), (-0.14, 0.006, 0.59), "hips", True),
        ("shin.R", (-0.14, 0.006, 0.59), (-0.14, 0.0, 0.17), "thigh.R", True),
        ("foot.R", (-0.14, 0.0, 0.17), (-0.14, -0.22, 0.075), "shin.R", True),
        ("toe.R", (-0.14, -0.22, 0.075), (-0.14, -0.34, 0.07), "foot.R", True),
        ("socket_head", (0.0, -0.11, 1.75), (0.0, -0.19, 1.75), "head", False),
        ("socket_chest", (0.0, -0.17, 1.35), (0.0, -0.25, 1.35), "chest", False),
        ("socket_glove", (0.405, -0.07, 0.82), (0.405, -0.17, 0.82), "hand.L", False),
        ("socket_catch", (0.405, -0.20, 0.84), (0.405, -0.29, 0.84), "hand.L", False),
        ("socket_bat", (-0.405, -0.07, 0.81), (-0.405, -0.17, 0.81), "hand.R", False),
        ("socket_ball", (-0.405, -0.13, 0.83), (-0.405, -0.22, 0.83), "hand.R", False),
        ("socket_bat_tip", (-0.365, -0.10, 1.53), (-0.365, -0.19, 1.53), "hand.R", False),
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
    # Quaternion tracks are essential for the large compound rotations in a
    # pitching delivery.  Baking independent IK solves back to XYZ Euler keys
    # produced branch flips between otherwise quiet frames (and visible arm
    # whips through the face).  glTF exports these quaternion curves natively.
    for pose_bone in rig.pose.bones:
        pose_bone.rotation_mode = "QUATERNION"
    RIG = rig
    return rig


def apply_subdivision(obj, levels):
    """Bake Catmull-Clark subdivision into the mesh before it is skinned.

    Applied ahead of the armature modifier so vertex-group weights authored
    on the control cage interpolate smoothly across the dense result.
    """

    if levels <= 0:
        return
    modifier = obj.modifiers.new("RealismSubdivision", "SUBSURF")
    modifier.levels = levels
    modifier.render_levels = levels
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def finish_mesh(obj, name, mat_name, bone_name, smooth=True, bevel=0.0, subdiv=0):
    obj.name = name
    obj.data.name = name + "_Mesh"
    # Deselect strays first: transform_apply acts on every selected object,
    # and selection bleed from earlier operators once smeared a stale
    # transform across appended meshes.
    bpy.ops.object.select_all(action="DESELECT")
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
    apply_subdivision(obj, subdiv)
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


def uv_part(name, location, scale, mat, bone, segments=16, rings=10, smooth=True, rotation=(0.0, 0.0, 0.0), subdiv=0):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments,
        ring_count=rings,
        radius=1.0,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.scale = scale
    return finish_mesh(obj, name, mat, bone, smooth=smooth, subdiv=subdiv)


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


def fit_cc0_point(point):
    """Map a coordinate from the vendored head's space into rig space."""

    scale = CC0_TARGET_INTERPUPIL / CC0_SRC_INTERPUPIL
    return CC0_TARGET_EYE_MID + (Vector(point) - CC0_SRC_EYE_MID) * scale


def append_cc0_head_objects():
    """Append the vendored CC0 head parts and fit them onto the rig.

    The fit is a uniform scale + translation registering the sculpt's
    interpupillary line onto the rig's authored eye targets.  The neck stump
    is cut just above the jersey collar so the recipe's own deforming neck
    tube carries the visible neck, and the sculpt's upper-neck rim tucks
    invisibly inside it.
    """

    source = Path(__file__).resolve().parent.parent / "models" / "ballplayer" / "source" / CC0_HEAD_BLEND
    with bpy.data.libraries.load(str(source), link=False) as (data_from, data_to):
        data_to.objects = [name for name in data_from.objects if name in CC0_HEAD_OBJECTS.values()]
    appended = {}
    for obj in data_to.objects:
        bpy.context.collection.objects.link(obj)
        appended[obj.name] = obj
    # matrix_world is only composed from loc/rot/scale after a depsgraph
    # update; reading it straight after linking returns identity.
    bpy.context.view_layer.update()
    # The bundle parents the eye parts to the head object.  Clear that
    # hierarchy (preserving world transforms) before fitting, or later
    # identity assignments resolve against a parent that no longer exists
    # once the head is joined into the body mesh.
    for obj in appended.values():
        world = obj.matrix_world.copy()
        obj.parent = None
        obj.matrix_world = world
    bpy.context.view_layer.update()
    for obj in appended.values():
        source_matrix = obj.matrix_world.copy()
        for vertex in obj.data.vertices:
            world = source_matrix @ vertex.co
            vertex.co = fit_cc0_point(world)
        obj.matrix_world = Matrix.Identity(4)
        obj.data.update()
        vertices = obj.data.vertices
        print(
            "CC0_FIT", obj.name,
            "x %.4f..%.4f" % (min(v.co.x for v in vertices), max(v.co.x for v in vertices)),
            "y %.4f..%.4f" % (min(v.co.y for v in vertices), max(v.co.y for v in vertices)),
            "z %.4f..%.4f" % (min(v.co.z for v in vertices), max(v.co.z for v in vertices)),
        )
    bpy.context.view_layer.update()

    head = appended[CC0_HEAD_OBJECTS["head"]]
    import bmesh

    mesh_data = head.data
    editor = bmesh.new()
    editor.from_mesh(mesh_data)
    doomed = [vertex for vertex in editor.verts if vertex.co.z < CC0_NECK_CUT_Z]
    bmesh.ops.delete(editor, geom=doomed, context="VERTS")
    editor.to_mesh(mesh_data)
    editor.free()
    mesh_data.update()

    # The sculpt's own neck (sternocleidomastoid, trapezius roots) is the
    # visible neck; the cut rim below hides under the undershirt mock-collar
    # that build_uniform wraps around it, exactly where a real jersey covers.
    # The residual trapezius flare just above the rim tucks radially into the
    # collar; the chin/jaw region (front of the y guard) stays untouched.
    axis_y = 0.006
    for vertex in mesh_data.vertices:
        if vertex.co.z >= 1.615 or vertex.co.y <= -0.052:
            continue
        blend = max(0.0, min(1.0, (vertex.co.z - CC0_NECK_CUT_Z) / (1.615 - CC0_NECK_CUT_Z)))
        radius_max = 0.052 + blend * 0.012
        offset_y = vertex.co.y - axis_y
        radius = math.hypot(vertex.co.x, offset_y)
        if radius > radius_max:
            shrink = radius_max / radius
            vertex.co.x *= shrink
            vertex.co.y = axis_y + offset_y * shrink
    mesh_data.update()

    # Rigid head weighting with a short blend into the neck across the
    # concealed overlap band.
    head_group = head.vertex_groups.new(name="head")
    neck_group = head.vertex_groups.new(name="neck")
    span = CC0_NECK_BLEND_TOP - CC0_NECK_CUT_Z
    for vertex in mesh_data.vertices:
        blend = min(1.0, max(0.0, (vertex.co.z - CC0_NECK_CUT_Z) / span))
        head_group.add([vertex.index], blend, "REPLACE")
        if blend < 1.0:
            neck_group.add([vertex.index], 1.0 - blend, "REPLACE")
    for polygon in mesh_data.polygons:
        polygon.use_smooth = True
    mesh_data.materials.append(MATERIALS["MAT_Skin"])
    apply_subdivision(head, 1)
    modifier = head.modifiers.new("BallplayerArmature", "ARMATURE")
    modifier.object = RIG
    modifier.use_deform_preserve_volume = True

    for key in ("sclera_l", "sclera_r", "iris_l", "iris_r"):
        obj = appended[CC0_HEAD_OBJECTS[key]]
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        obj.data.materials.append(MATERIALS["MAT_EyeWhite" if "sclera" in key else "MAT_Iris"])
        group = obj.vertex_groups.new(name="head")
        group.add(range(len(obj.data.vertices)), 1.0, "REPLACE")
        modifier = obj.modifiers.new("BallplayerArmature", "ARMATURE")
        modifier.object = RIG
        modifier.use_deform_preserve_volume = True
    return appended


def head_surface_probe(head_object):
    """Return a raycast helper over the fitted head surface.

    ``probe(origin, direction)`` returns the world-space hit location or
    ``None``; anchors for brows, hair shells, the cap, and sideburns are
    derived from real sculpt geometry instead of hardcoded offsets.
    """

    depsgraph = bpy.context.evaluated_depsgraph_get()
    tree = BVHTree.FromObject(head_object, depsgraph)

    def probe(origin, direction):
        location, _normal, _index, _distance = tree.ray_cast(Vector(origin), Vector(direction).normalized(), 2.0)
        return location

    return probe


def ellipsoid_plate(name, center, radii, mat, bone, azimuth, elevation, columns, rows, inflate=1.045, subdiv=0):
    """Create a curved shell patch hugging the front of an ellipsoid.

    The patch is parametrized by azimuth around Z (0 faces the character's
    -Y front) and elevation, sampled just outside the carrier surface so the
    texel art reads as painted-on.  UVs span the full patch: image column 0
    lands on the character's -X side, which a front-on camera sees on its
    left, so ASCII pixel rows render exactly as authored.
    """

    azimuth_max = float(azimuth)
    elevation_min, elevation_max = (float(value) for value in elevation)
    center_v = Vector(center)
    vertices = []
    for row in range(rows + 1):
        pitch = elevation_max + (elevation_min - elevation_max) * row / rows
        for column in range(columns + 1):
            yaw = -azimuth_max + 2.0 * azimuth_max * column / columns
            vertices.append(
                (
                    center_v.x + math.sin(yaw) * math.cos(pitch) * radii[0] * inflate,
                    center_v.y - math.cos(yaw) * math.cos(pitch) * radii[1] * inflate,
                    center_v.z + math.sin(pitch) * radii[2] * inflate,
                )
            )
    faces = []
    for row in range(rows):
        for column in range(columns):
            corner = row * (columns + 1) + column
            faces.append((corner, corner + 1, corner + columns + 2, corner + columns + 1))

    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for polygon in mesh.polygons:
        polygon.use_smooth = True
        for loop_index in polygon.loop_indices:
            vertex_index = mesh.loops[loop_index].vertex_index
            row, column = divmod(vertex_index, columns + 1)
            uv_layer.data[loop_index].uv = (column / columns, 1.0 - row / rows)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(MATERIALS[mat])
    apply_subdivision(obj, subdiv)
    group = obj.vertex_groups.new(name=bone)
    group.add(range(len(obj.data.vertices)), 1.0, "REPLACE")
    modifier = obj.modifiers.new("BallplayerArmature", "ARMATURE")
    modifier.object = RIG
    modifier.use_deform_preserve_volume = True
    obj["weighted_bone"] = bone
    return obj


def weighted_chain_part(name, rings, mat, segments=20, smooth=True, phase=0.0, face_materials=None, cap_materials=None, subdiv=0):
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
    if len(parts) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
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
    global CC0_PROBE
    parts = []
    # The head is the professionally sculpted CC0 base mesh, registered onto
    # the rig's eye targets and rigidly weighted to the head bone.  Anchors
    # for brows, hair, and the cap are raycast from its real surface by the
    # probe stashed here for the later builders.
    appended = append_cc0_head_objects()
    head = appended[CC0_HEAD_OBJECTS["head"]]
    head.name = "Body_HeadSculpt"
    CC0_PROBE = head_surface_probe(head)
    parts.append(head)
    CC0_EYE_PARTS.clear()
    for key in ("sclera_l", "sclera_r", "iris_l", "iris_r"):
        CC0_EYE_PARTS.append(appended[CC0_HEAD_OBJECTS[key]])
    # A trapezius shoulder saddle bridges the sculpt's neck roots into the
    # jersey yoke at the back; the sculpt itself carries all visible neck
    # anatomy above the undershirt collar.
    parts.append(
        weighted_chain_part(
            "Body_TrapsSaddle",
            [
                (
                    (0.0, 0.010, 1.446),
                    0.088,
                    0.078,
                    {"chest": 0.80, "neck": 0.20},
                    radial_profile(24, 0.5, ((90.0, 85.0, 0.62),)),
                ),
                (
                    (0.0, 0.008, 1.482),
                    0.078,
                    0.070,
                    {"chest": 0.45, "neck": 0.55},
                    radial_profile(24, 0.5, ((90.0, 75.0, 0.30),)),
                ),
                ((0.0, 0.005, 1.516), 0.070, 0.064, {"neck": 0.85, "chest": 0.15}),
                ((0.0, 0.003, 1.545), 0.064, 0.060, {"neck": 0.70, "head": 0.30}),
            ],
            "MAT_Skin",
            24,
            phase=0.5,
            subdiv=2,
        )
    )

    # Anatomical arm tubes: a deltoid cap, a bicep belly against the flatter
    # tricep plane behind it, a pinched elbow landmark, a brachioradialis and
    # extensor wedge flaring the upper forearm on the thumb side, and a
    # narrowing wrist that hands the surface off to the sculpted hand chains
    # below.  In the ring-angle frame the front of the arm is 270 degrees and
    # the lateral (outer) side is 0 degrees for the left arm / 180 for the
    # right, so lateral muscle groups are authored per side.
    arm_segments = 40
    # Wristbands: two deforming team-color rings authored as face bands on
    # the bare forearm, just above each hand -- standard on-field wear.
    def wristband_faces(band, segment):
        return "TEAM_Primary" if band in (12, 13) else None

    for side, sign in (("L", 1.0), ("R", -1.0)):
        upper_bone = "upper_arm." + side
        forearm_bone = "forearm." + side
        hand_bone = "hand." + side
        clavicle_bone = "clavicle." + side
        lateral = 0.0 if side == "L" else 180.0
        deltoid = ((lateral, 70.0, 0.06), (270.0, 40.0, 0.02))
        bicep = ((270.0, 55.0, 0.10), (90.0, 65.0, 0.050))
        elbow = ((90.0, 30.0, 0.05),)
        extensor = ((lateral, 55.0, 0.085), (270.0, 45.0, 0.045))
        flexor = ((270.0, 50.0, 0.045), (lateral, 45.0, 0.035))

        def arm_profile(bumps):
            return radial_profile(arm_segments, 0.5, bumps)

        parts.append(
            weighted_chain_part(
                "Body_ArmBlend_" + side,
                [
                    ((0.280 * sign, 0.000, 1.352), 0.086, 0.085, {clavicle_bone: 0.30, upper_bone: 0.70}, arm_profile(deltoid)),
                    ((0.305 * sign, 0.000, 1.308), 0.085, 0.083, {clavicle_bone: 0.12, upper_bone: 0.88}, arm_profile(deltoid)),
                    ((0.327 * sign, -0.001, 1.272), 0.080, 0.078, {upper_bone: 1.0}, arm_profile(bicep)),
                    ((0.345 * sign, -0.002, 1.240), 0.077, 0.075, {upper_bone: 1.0}, arm_profile(bicep)),
                    ((0.358 * sign, -0.003, 1.212), 0.073, 0.071, {upper_bone: 1.0}, arm_profile(bicep)),
                    ((0.369 * sign, -0.003, 1.188), 0.069, 0.067, {upper_bone: 0.80, forearm_bone: 0.20}, arm_profile(elbow)),
                    ((0.377 * sign, -0.004, 1.164), 0.065, 0.064, {upper_bone: 0.55, forearm_bone: 0.45}, arm_profile(elbow)),
                    ((0.382 * sign, -0.005, 1.142), 0.062, 0.061, {upper_bone: 0.30, forearm_bone: 0.70}, arm_profile(elbow)),
                    ((0.387 * sign, -0.006, 1.112), 0.064, 0.062, {upper_bone: 0.12, forearm_bone: 0.88}, arm_profile(extensor)),
                    ((0.393 * sign, -0.008, 1.072), 0.068, 0.066, {forearm_bone: 1.0}, arm_profile(extensor)),
                    ((0.397 * sign, -0.010, 1.030), 0.065, 0.063, {forearm_bone: 1.0}, arm_profile(flexor)),
                    ((0.401 * sign, -0.012, 0.988), 0.060, 0.058, {forearm_bone: 1.0}, arm_profile(flexor)),
                    ((0.405 * sign, -0.015, 0.952), 0.055, 0.051, {forearm_bone: 0.88, hand_bone: 0.12}),
                    ((0.407 * sign, -0.018, 0.926), 0.050, 0.045, {forearm_bone: 0.68, hand_bone: 0.32}),
                    ((0.409 * sign, -0.024, 0.898), 0.047, 0.041, {forearm_bone: 0.35, hand_bone: 0.65}),
                ],
                "MAT_Skin",
                arm_segments,
                phase=0.5,
                face_materials=wristband_faces,
                subdiv=2,
            )
        )

    # Sculpted hands built from existing bones only.  Both start with a narrow
    # wrist transition and a palm heel; a widened knuckle ridge carries a
    # four-bump radial profile and the finger mass carries a scalloped profile
    # so separation reads in silhouette without toast-rack finger boxes.  The
    # glove-side hand stays half-open for catches and celebrations while the
    # throwing hand curls into a compact fist whose volume wraps the resting
    # bat handle, with a thumb chain crossing the front of the grip.
    hand_segments = 30
    knuckle_profile = [
        1.0 + 0.075 * math.cos(4.0 * math.tau * (k + 0.5) / hand_segments) for k in range(hand_segments)
    ]
    finger_profile = [
        1.0 + 0.100 * math.cos(4.0 * math.tau * (k + 0.5) / hand_segments + math.pi) for k in range(hand_segments)
    ]
    fingertip_profile = [
        1.0 + 0.070 * math.cos(4.0 * math.tau * (k + 0.5) / hand_segments + math.pi) for k in range(hand_segments)
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
                ((0.408, -0.020, 0.915), 0.050, 0.042, {"forearm.L": 0.55, "hand.L": 0.45}),
                ((0.409, -0.026, 0.898), 0.054, 0.045, {"forearm.L": 0.30, "hand.L": 0.70}),
                ((0.410, -0.032, 0.882), 0.059, 0.048, {"forearm.L": 0.12, "hand.L": 0.88}),
                ((0.411, -0.036, 0.864), 0.064, 0.047, {"hand.L": 1.0}, thenar_profile),
                ((0.411, -0.041, 0.844), 0.070, 0.046, {"hand.L": 1.0}, thenar_profile),
                ((0.412, -0.048, 0.812), 0.080, 0.044, {"hand.L": 1.0}, thenar_profile),
                ((0.412, -0.058, 0.780), 0.084, 0.048, {"hand.L": 1.0}, knuckle_profile),
                ((0.412, -0.065, 0.764), 0.082, 0.044, {"hand.L": 1.0}, knuckle_profile),
                ((0.411, -0.072, 0.748), 0.078, 0.040, {"hand.L": 1.0}, finger_profile),
                ((0.410, -0.080, 0.732), 0.071, 0.036, {"hand.L": 1.0}, finger_profile),
                ((0.409, -0.086, 0.720), 0.064, 0.032, {"hand.L": 1.0}, finger_profile),
                ((0.408, -0.091, 0.708), 0.054, 0.028, {"hand.L": 1.0}, fingertip_profile),
                ((0.407, -0.094, 0.700), 0.044, 0.024, {"hand.L": 1.0}),
            ],
            "MAT_Skin",
            hand_segments,
            phase=0.5,
            face_materials=open_hand_faces,
            subdiv=2,
        )
    )
    parts.append(
        weighted_chain_part(
            "Body_Thumb_L",
            [
                ((0.437, -0.044, 0.834), 0.033, 0.030, {"hand.L": 1.0}),
                ((0.453, -0.060, 0.815), 0.029, 0.026, {"hand.L": 1.0}),
                ((0.465, -0.074, 0.800), 0.026, 0.023, {"hand.L": 1.0}),
                ((0.473, -0.085, 0.789), 0.022, 0.019, {"hand.L": 1.0}),
                ((0.478, -0.093, 0.781), 0.017, 0.015, {"hand.L": 1.0}),
            ],
            "MAT_Skin",
            12,
            subdiv=2,
        )
    )
    parts.append(
        weighted_chain_part(
            "Body_Hand_R",
            [
                ((-0.408, -0.020, 0.915), 0.050, 0.042, {"forearm.R": 0.55, "hand.R": 0.45}),
                ((-0.409, -0.027, 0.898), 0.052, 0.043, {"forearm.R": 0.30, "hand.R": 0.70}),
                ((-0.410, -0.034, 0.882), 0.056, 0.046, {"forearm.R": 0.12, "hand.R": 0.88}),
                ((-0.411, -0.038, 0.866), 0.059, 0.046, {"hand.R": 1.0}, thenar_profile),
                ((-0.411, -0.042, 0.850), 0.062, 0.046, {"hand.R": 1.0}, thenar_profile),
                ((-0.412, -0.058, 0.815), 0.070, 0.050, {"hand.R": 1.0}, thenar_profile),
                ((-0.411, -0.070, 0.782), 0.072, 0.053, {"hand.R": 1.0}, knuckle_profile),
                ((-0.409, -0.070, 0.766), 0.069, 0.051, {"hand.R": 1.0}, knuckle_profile),
                ((-0.407, -0.068, 0.752), 0.064, 0.048, {"hand.R": 1.0}, finger_profile),
                ((-0.405, -0.060, 0.740), 0.056, 0.042, {"hand.R": 1.0}, finger_profile),
                ((-0.403, -0.052, 0.732), 0.047, 0.035, {"hand.R": 1.0}),
            ],
            "MAT_Skin",
            hand_segments,
            phase=0.5,
            face_materials=fist_faces,
            subdiv=2,
        )
    )
    parts.append(
        weighted_chain_part(
            "Body_Thumb_R",
            [
                ((-0.455, -0.056, 0.822), 0.027, 0.025, {"hand.R": 1.0}),
                ((-0.449, -0.068, 0.812), 0.026, 0.024, {"hand.R": 1.0}),
                ((-0.441, -0.084, 0.800), 0.024, 0.022, {"hand.R": 1.0}),
                ((-0.433, -0.098, 0.788), 0.022, 0.020, {"hand.R": 1.0}),
                ((-0.422, -0.104, 0.781), 0.019, 0.017, {"hand.R": 1.0}),
                ((-0.411, -0.108, 0.775), 0.015, 0.013, {"hand.R": 1.0}),
            ],
            "MAT_Skin",
            12,
            subdiv=2,
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
        if band >= 15:
            # Raglan shoulder yoke: the same color as the sleeves so the
            # sleeve roots read as one continuous garment with the torso.
            return "TEAM_Secondary"
        if 7 <= band <= 14 and segment in (14, 15, 16, 30, 31, 0):
            return "TEAM_Secondary"  # jersey side panels
        if 2 <= band <= 14 and segment == 23:
            # Team-color placket piping down the white button front, like a
            # classic home uniform.
            return "TEAM_Primary"
        return None

    # Radial contract with the pants: every pelvis-chain radius stays at least
    # 8 mm inside these hem rings, and the shared pure-hips weighting across
    # the whole overlap zone means the two garments cannot separate or
    # interleave at the midriff in any pose.  The pinched ring at 1.104 is an
    # authored waist fold; the stepped rib rings above it carry the chest
    # planes, and the extra rings around the belt and hem keep those material
    # bands crisp under deformation.
    # Torso musculature reads through the fitted double-knit jersey: pectoral
    # plates flanking a sternal channel, lat flare toward the back corners, a
    # spinal groove, and a slight rectus plane above the belt.
    pec_profile = radial_profile(
        32, 0.5, ((252.0, 30.0, 0.035), (288.0, 30.0, 0.035), (90.0, 12.0, -0.020), (150.0, 25.0, 0.025), (30.0, 25.0, 0.025))
    )
    abs_profile = radial_profile(32, 0.5, ((270.0, 30.0, 0.018), (90.0, 12.0, -0.018)))
    parts.append(
        weighted_chain_part(
            "Uniform_TorsoBlend",
            [
                ((0.0, 0.012, 0.868), 0.220, 0.140, {"hips": 1.0}),
                ((0.0, 0.012, 0.918), 0.224, 0.142, {"hips": 1.0}),
                ((0.0, 0.011, 0.958), 0.226, 0.143, {"hips": 1.0}),
                ((0.0, 0.010, 1.000), 0.227, 0.143, {"hips": 1.0}),
                ((0.0, 0.010, 1.044), 0.228, 0.144, {"hips": 1.0}),
                ((0.0, 0.009, 1.080), 0.224, 0.141, {"hips": 0.85, "spine": 0.15}),
                ((0.0, 0.008, 1.104), 0.217, 0.138, {"hips": 0.68, "spine": 0.32}),
                ((0.0, 0.007, 1.136), 0.220, 0.138, {"hips": 0.45, "spine": 0.55}),
                ((0.0, 0.006, 1.176), 0.226, 0.138, {"hips": 0.24, "spine": 0.76}),
                ((0.0, 0.005, 1.216), 0.233, 0.139, {"spine": 0.90, "chest": 0.10}, abs_profile),
                ((0.0, 0.003, 1.258), 0.242, 0.141, {"spine": 0.74, "chest": 0.26}, abs_profile),
                ((0.0, 0.002, 1.296), 0.252, 0.145, {"spine": 0.45, "chest": 0.55}, abs_profile),
                ((0.0, 0.001, 1.336), 0.252, 0.142, {"spine": 0.26, "chest": 0.74}, pec_profile),
                ((0.0, -0.001, 1.378), 0.256, 0.143, {"chest": 1.0}, pec_profile),
                ((0.0, -0.001, 1.412), 0.258, 0.143, {"chest": 1.0}, pec_profile),
                ((0.0, -0.003, 1.466), 0.224, 0.134, {"chest": 1.0}),
                ((0.0, -0.004, 1.502), 0.132, 0.098, {"chest": 0.85, "neck": 0.15}),
                ((0.0, -0.004, 1.522), 0.068, 0.058, {"chest": 0.45, "neck": 0.55}),
            ],
            "MAT_Pants",
            32,
            phase=0.5,
            face_materials=torso_faces,
            cap_materials=("MAT_Pants", "MAT_Pants"),
            subdiv=2,
        )
    )
    # A trimmed crew collar closing snugly on the anatomical neck, over an
    # undershirt ring.  Chest identity is per-team equipment (mark and
    # number) so the base jersey stays role- and team-neutral.
    parts.append(torus_part("Uniform_Collar", (0.0, -0.004, 1.524), 0.0640, 0.0075, "TEAM_Primary", "chest"))
    # Undershirt mock-collar: wraps the sculpted neck's base (and conceals
    # the CC0 head's cut rim) exactly where a real compression shirt sits.
    parts.append(
        weighted_chain_part(
            "Uniform_Undershirt",
            [
                ((0.0, 0.004, 1.512), 0.070, 0.078, {"chest": 0.70, "neck": 0.30}),
                ((0.0, 0.008, 1.536), 0.067, 0.080, {"chest": 0.35, "neck": 0.65}),
                ((0.0, 0.010, 1.558), 0.062, 0.076, {"neck": 0.90, "chest": 0.10}),
                ((0.0, 0.012, 1.578), 0.057, 0.068, {"neck": 0.80, "head": 0.20}),
                ((0.0, 0.013, 1.592), 0.053, 0.063, {"neck": 0.55, "head": 0.45}),
            ],
            "TEAM_Secondary",
            24,
            phase=0.5,
            subdiv=2,
        )
    )

    def sleeve_faces(band, segment):
        return None  # plain raglan sleeves; real cuffs end without armbands

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
                    ((0.175 * sign, 0.000, 1.452), 0.088, 0.095, {"chest": 0.48, clavicle_bone: 0.42, upper_bone: 0.10}),
                    ((0.205 * sign, 0.000, 1.442), 0.090, 0.096, {"chest": 0.30, clavicle_bone: 0.48, upper_bone: 0.22}),
                    ((0.231 * sign, 0.000, 1.428), 0.092, 0.098, {"chest": 0.16, clavicle_bone: 0.50, upper_bone: 0.34}),
                    ((0.258 * sign, -0.001, 1.402), 0.094, 0.097, {clavicle_bone: 0.40, upper_bone: 0.60}),
                    ((0.281 * sign, -0.001, 1.372), 0.096, 0.099, {clavicle_bone: 0.28, upper_bone: 0.72}),
                    ((0.300 * sign, -0.001, 1.344), 0.094, 0.096, {clavicle_bone: 0.12, upper_bone: 0.88}),
                    ((0.315 * sign, -0.001, 1.315), 0.092, 0.094, {upper_bone: 1.0}),
                    ((0.327 * sign, -0.001, 1.288), 0.090, 0.092, {upper_bone: 1.0}),
                    ((0.337 * sign, -0.001, 1.258), 0.088, 0.090, {upper_bone: 0.95, forearm_bone: 0.05}),
                    ((0.347 * sign, -0.002, 1.215), 0.086, 0.088, {upper_bone: 0.86, forearm_bone: 0.14}),
                    ((0.352 * sign, -0.002, 1.192), 0.083, 0.085, {upper_bone: 0.80, forearm_bone: 0.20}),
                ],
                "TEAM_Secondary",
                28,
                phase=0.5,
                face_materials=sleeve_faces,
                subdiv=2,
            )
        )

    parts.append(
        weighted_chain_part(
            "Uniform_PelvisBlend",
            [
                ((0.0, 0.012, 1.112), 0.196, 0.123, {"hips": 1.0}),
                ((0.0, 0.012, 1.040), 0.201, 0.127, {"hips": 1.0}),
                ((0.0, 0.012, 1.000), 0.202, 0.128, {"hips": 1.0}),
                ((0.0, 0.012, 0.962), 0.202, 0.129, {"hips": 1.0}),
                ((0.0, 0.011, 0.928), 0.200, 0.127, {"hips": 0.94, "thigh.L": 0.03, "thigh.R": 0.03}),
                ((0.0, 0.010, 0.895), 0.197, 0.125, {"hips": 0.86, "thigh.L": 0.07, "thigh.R": 0.07}),
                ((0.0, 0.008, 0.845), 0.184, 0.119, {"hips": 0.60, "thigh.L": 0.20, "thigh.R": 0.20}),
                ((0.0, 0.006, 0.800), 0.160, 0.107, {"hips": 0.40, "thigh.L": 0.30, "thigh.R": 0.30}),
            ],
            "MAT_Pants",
            28,
            cap_materials=("MAT_Pants", "MAT_Pants"),
            subdiv=2,
        )
    )

    # Belt loops ride the waistband like real trousers.
    for loop_index, loop_angle in enumerate((-0.62, 0.62, -1.65, 1.65, math.pi)):
        parts.append(
            box_part(
                "Uniform_BeltLoop_%d" % loop_index,
                (0.230 * math.sin(loop_angle), 0.011 - 0.146 * math.cos(loop_angle), 0.938),
                (0.0075, 0.0045, 0.0210),
                "MAT_Pants",
                "hips",
                rotation=(0.0, 0.0, -loop_angle),
                bevel=0.002,
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
                return "TEAM_Primary"  # team-color stirrup sock into the cleat
            if 1 <= band <= 12 and segment == outer:
                return "TEAM_Secondary"  # outer-seam piping
            return None

        parts.append(
            weighted_chain_part(
                "Uniform_LegBlend_" + side,
                [
                    ((0.108 * sign, 0.010, 0.960), 0.104, 0.102, {"hips": 0.80, thigh: 0.20}),
                    ((0.126 * sign, 0.009, 0.905), 0.114, 0.112, {"hips": 0.60, thigh: 0.40}),
                    ((0.134 * sign, 0.008, 0.858), 0.120, 0.118, {"hips": 0.42, thigh: 0.58}),
                    ((0.140 * sign, 0.008, 0.778), 0.122, 0.120, {"hips": 0.10, thigh: 0.90}),
                    ((0.140 * sign, 0.007, 0.735), 0.119, 0.117, {thigh: 1.0}),
                    ((0.140 * sign, 0.006, 0.692), 0.115, 0.113, {thigh: 1.0}),
                    ((0.140 * sign, 0.005, 0.640), 0.109, 0.108, {thigh: 0.85, shin: 0.15}),
                    ((0.140 * sign, -0.008, 0.610), 0.106, 0.105, {thigh: 0.70, shin: 0.30}),
                    ((0.140 * sign, -0.004, 0.585), 0.103, 0.102, {thigh: 0.52, shin: 0.48}),
                    ((0.140 * sign, 0.004, 0.556), 0.099, 0.100, {thigh: 0.25, shin: 0.75}),
                    ((0.140 * sign, 0.010, 0.510), 0.096, 0.099, {shin: 1.0}),
                    ((0.140 * sign, 0.014, 0.462), 0.095, 0.099, {shin: 1.0}),
                    ((0.140 * sign, 0.010, 0.415), 0.091, 0.095, {shin: 1.0}),
                    ((0.140 * sign, 0.002, 0.352), 0.084, 0.088, {shin: 1.0}),
                    ((0.140 * sign, -0.003, 0.268), 0.077, 0.081, {shin: 1.0}),
                    ((0.140 * sign, -0.007, 0.214), 0.074, 0.078, {shin: 0.75, foot: 0.25}),
                    ((0.140 * sign, -0.018, 0.158), 0.072, 0.076, {shin: 0.30, foot: 0.70}),
                ],
                "MAT_Pants",
                28,
                phase=0.5,
                face_materials=leg_faces,
                subdiv=2,
            )
        )
    return join_parts(parts, "Uniform_Skinned", "uniform")


def build_hair():
    # Short athletic cut anchored to the sculpted skull by raycast: an
    # occipital shell, tapered nape layers, side coverage above the ears, and
    # sideburns, each buried a few millimetres into the measured surface so
    # the hairline follows the real head instead of hardcoded offsets.
    parts = []
    back_hit = CC0_PROBE((0.0, 0.40, 1.778), (0.0, -1.0, 0.0))
    nape_hit = CC0_PROBE((0.0, 0.40, 1.700), (0.0, -1.0, 0.0))
    if back_hit is None or nape_hit is None:
        raise RuntimeError("hair probes missed the sculpted head")
    parts.append(
        uv_part("Hair_Occiput", (0.0, back_hit.y - 0.060, 1.778), (0.0640, 0.0660, 0.0600), "MAT_Hair", "head", 28, 16, subdiv=2)
    )
    parts.append(
        uv_part("Hair_Nape", (0.0, nape_hit.y - 0.022, 1.700), (0.0480, 0.0280, 0.0380), "MAT_Hair", "head", 20, 12, subdiv=2)
    )
    for side, sign in (("L", 1.0), ("R", -1.0)):
        side_hit = CC0_PROBE((0.40 * sign, 0.020, 1.768), (-sign, 0.0, 0.0))
        if side_hit is None:
            raise RuntimeError("side hair probes missed the sculpted head")
        parts.append(
            uv_part(
                "Hair_Side_" + side,
                (side_hit.x - 0.0045 * sign, side_hit.y + 0.004, 1.7660),
                (0.0120, 0.0440, 0.0330),
                "MAT_Hair",
                "head",
                16,
                10,
                subdiv=2,
            )
        )
    for index, x in enumerate((-0.0330, -0.0165, 0.0, 0.0165, 0.0330)):
        parts.append(
            ico_part(
                "Hair_NapeLock_%02d" % index,
                (x, nape_hit.y - 0.006 - abs(x) * 0.30, 1.6900 + (index % 2) * 0.0055),
                (0.0125, 0.0100, 0.0185),
                "MAT_HairHighlight" if index == 2 else "MAT_Hair",
                "head",
                2,
                True,
                rotation=(-10.0 * DEG, 0.0, x * 2.2),
            )
        )
    return join_parts(parts, "Hair_Skinned", "hair")


def build_face():
    # The eyes are the CC0 sculpt's own layered parts (sclera shells plus
    # iris discs) fitted with the head, completed by small pupil spheres and
    # brow chains anchored by raycasting the actual sculpted brow ridge.
    # Everything else -- lids, nose, lips, ears -- is real sculpt geometry on
    # the head itself, so no procedural feature approximations remain.
    parts = list(CC0_EYE_PARTS)
    for part in parts:
        # The fitted vertex data is authoritative; neutralize any transform
        # an operator may have smeared onto these appended objects.
        part.matrix_world = Matrix.Identity(4)
        # The bundle intends a transparent cornea over a recessed iris; with
        # opaque materials the iris would hide inside the sclera, so bring
        # the discs proud of the sclera surface as a corneal bulge.
        if "iris" in part.name:
            for vertex in part.data.vertices:
                vertex.co.y -= 0.0042
    for side, sign in (("L", 1.0), ("R", -1.0)):
        iris_center = fit_cc0_point((1.4626 + 0.0325 * sign, -0.1331, 0.7667))
        parts.append(
            uv_part(
                "Face_Pupil_" + side,
                (iris_center.x, iris_center.y - 0.0060, iris_center.z),
                (0.0033, 0.0016, 0.0033),
                "MAT_Pupil",
                "head",
                14,
                8,
                subdiv=1,
            )
        )
        brow_rings = []
        for offset_x, offset_z, radius in (
            (0.012, 0.0245, 0.0028),
            (0.030, 0.0265, 0.0036),
            (0.045, 0.0250, 0.0030),
            (0.056, 0.0205, 0.0019),
        ):
            hit = CC0_PROBE(
                (offset_x * sign, -0.40, CC0_TARGET_EYE_MID.z + offset_z),
                (0.0, 1.0, 0.0),
            )
            if hit is None:
                raise RuntimeError("brow probe missed the sculpted head")
            brow_rings.append(((hit.x, hit.y - 0.0015, hit.z), radius, radius * 0.82, {"head": 1.0}))
        parts.append(
            weighted_chain_part(
                "Face_Brow_" + side,
                brow_rings,
                "MAT_Hair",
                10,
                subdiv=2,
            )
        )
    return join_parts(parts, "Face_Details_Skinned", "face_planes")


def build_cap():
    # Structured six-panel cap statically fitted to the measured CC0 skull
    # (band-zone side extent 0.074, sagittal extent -0.099..+0.087, apex at
    # z=1.840) with cloth clearance over the hair shells.
    parts = [
        weighted_chain_part(
            "Cap_Crown",
            [
                ((0.0, -0.0050, 1.7580), 0.0840, 0.1020, {"head": 1.0}),
                ((0.0, -0.0056, 1.7760), 0.0850, 0.1010, {"head": 1.0}),
                ((0.0, -0.0045, 1.8000), 0.0780, 0.0900, {"head": 1.0}),
                ((0.0, -0.0028, 1.8240), 0.0640, 0.0740, {"head": 1.0}),
                ((0.0, 0.0000, 1.8460), 0.0440, 0.0500, {"head": 1.0}),
                ((0.0, 0.0010, 1.8620), 0.0240, 0.0280, {"head": 1.0}),
            ],
            "TEAM_Primary",
            32,
            phase=0.5,
            subdiv=2,
        ),
        # Curved, tapering pro-cap brim; the rear ring is buried inside the
        # crown so the two never separate in profile.
        weighted_chain_part(
            "Cap_BrimCurve",
            [
                ((0.0, -0.0860, 1.7660), 0.0790, 0.0085, {"head": 1.0}),
                ((0.0, -0.1260, 1.7678), 0.0760, 0.0068, {"head": 1.0}),
                ((0.0, -0.1580, 1.7648), 0.0680, 0.0058, {"head": 1.0}),
                ((0.0, -0.1840, 1.7575), 0.0550, 0.0050, {"head": 1.0}),
                ((0.0, -0.2020, 1.7485), 0.0380, 0.0046, {"head": 1.0}),
            ],
            "TEAM_Secondary",
            28,
            subdiv=2,
        ),
    ]
    # Real caps drop lower at the back than the front: a rear skirt shell
    # covers the occiput between the horizontal crown bottom and the nape
    # hairline.
    back_skirt = ellipsoid_plate(
        "Cap_BackSkirt",
        (0.0, -0.004, 1.7640),
        (0.0840, 0.1000, 0.0520),
        "TEAM_Primary",
        "head",
        azimuth=1.30,
        elevation=(-0.85, 0.12),
        columns=20,
        rows=8,
        inflate=1.0,
        subdiv=1,
    )
    back_skirt.rotation_euler = (0.0, 0.0, math.pi)
    parts.append(back_skirt)
    # Small raised monogram at the crown front reads as embroidery.
    for name, offset_x, offset_z, scale in (
        ("Cap_MarkStem", -0.0040, 0.0040, (0.0018, 0.0026, 0.0080)),
        ("Cap_MarkTop", 0.0022, 0.0092, (0.0048, 0.0024, 0.0020)),
        ("Cap_MarkMid", 0.0022, 0.0018, (0.0040, 0.0024, 0.0018)),
        ("Cap_MarkBowl", 0.0058, 0.0055, (0.0018, 0.0024, 0.0036)),
    ):
        parts.append(
            box_part(
                name,
                (offset_x, -0.0975, 1.8020 + offset_z),
                scale,
                "TEAM_Accent",
                "head",
                rotation=(8.0 * DEG, 0.0, 0.0),
                bevel=0.001,
            )
        )
    parts.append(
        ico_part("Cap_Button", (0.0, 0.0015, 1.8710), (0.0080, 0.0080, 0.0050), "TEAM_Primary", "head", 2, True)
    )
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
                    "MAT_CleatEdge",
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
            "MAT_Leather",
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
            return "MAT_BatTape"  # one clean dark grip wrap, like the sheet
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
        box_part("Bat_Label", (-0.405, -0.121, 1.265), (0.018, 0.003, 0.042), "MAT_Belt", "hand.R", bevel=0.005),
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


def solve_foot_targets(targets):
    """Bake stable two-bone leg IK, then author the shoe orientation.

    The previous solve ended its three-bone chain at the foot tail. Position
    alone left the foot's roll unconstrained, so Blender could satisfy an
    otherwise good stride target with the support cleat balanced on its heel
    or outer edge.  We now solve thigh + shin to the derived ankle, then place
    the foot in an explicit armature-space orientation.  ``target`` remains
    the toe-base point so planted-foot telemetry and existing action data keep
    the same semantic contract.
    """

    helpers = []
    constraints = []
    affected = []
    foot_orientations = {}
    for side in ("L", "R"):
        specification = targets.get(side)
        if specification is None:
            continue
        sign = 1.0 if side == "L" else -1.0
        foot_name = "foot." + side
        shin_name = "shin." + side
        rest_foot = RIG.data.bones[foot_name]
        rotation = Euler(
            tuple(float(value) * DEG for value in specification.get("rotation", (0.0, 0.0, 0.0))),
            "XYZ",
        ).to_matrix()
        rest_vector = rest_foot.tail_local - rest_foot.head_local
        desired_vector = rotation @ rest_vector
        toe_target = Vector(tuple(float(value) for value in specification["target"]))
        ankle_target = toe_target - desired_vector

        target = bpy.data.objects.new("__IK_Foot_Target_" + side, None)
        target.location = ankle_target
        bpy.context.collection.objects.link(target)
        pole = bpy.data.objects.new("__IK_Foot_Pole_" + side, None)
        default_pole = (0.48 * sign, -0.58, 0.66)
        pole.location = tuple(float(value) for value in specification.get("pole", default_pole))
        bpy.context.collection.objects.link(pole)
        helpers.extend((target, pole))

        shin = RIG.pose.bones[shin_name]
        constraint = shin.constraints.new("IK")
        constraint.name = "__BAKE_FOOT_TARGET__"
        constraint.target = target
        constraint.pole_target = pole
        constraint.chain_count = 2
        constraint.iterations = 128
        constraint.use_tail = True
        constraint.pole_angle = float(specification.get("pole_angle", 0.0)) * DEG
        constraints.append((shin, constraint))
        affected.extend(("thigh." + side, shin_name))
        foot_orientations[side] = rotation

    bpy.context.view_layer.update()
    matrices = {name: RIG.pose.bones[name].matrix.copy() for name in affected}
    for shin, constraint in constraints:
        shin.constraints.remove(constraint)
    bpy.context.view_layer.update()

    for segment in ("thigh", "shin"):
        for side in ("L", "R"):
            name = segment + "." + side
            if name in matrices:
                RIG.pose.bones[name].matrix = matrices[name]
                bpy.context.view_layer.update()

    # Keep each sole orientation deterministic after the knee solve.  The
    # delta is expressed in armature space so pitch means the same thing on
    # both sides and no mirrored roll can sneak into a planted frame.
    for side, rotation in foot_orientations.items():
        foot_name = "foot." + side
        rest_matrix = RIG.data.bones[foot_name].matrix_local.copy()
        desired_matrix = (rotation @ rest_matrix.to_3x3()).to_4x4()
        desired_matrix.translation = RIG.pose.bones["shin." + side].tail
        RIG.pose.bones[foot_name].matrix = desired_matrix
        bpy.context.view_layer.update()
    for helper in helpers:
        bpy.data.objects.remove(helper, do_unlink=True)


def key_pose(frame, rotations, previous_quaternions=None):
    for pose_bone in RIG.pose.bones:
        pose_bone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pose_bone.location = (0.0, 0.0, 0.0)
    for name, degrees in rotations.items():
        if name == "_root_location":
            RIG.pose.bones["root"].location = tuple(float(value) for value in degrees)
            continue
        if name in ("_hand_targets", "_foot_targets"):
            continue
        pose_bone = RIG.pose.bones.get(name)
        if pose_bone is None:
            raise RuntimeError("animation references missing bone " + name)
        pose_bone.rotation_quaternion = Euler(
            tuple(float(value) * DEG for value in degrees), "XYZ"
        ).to_quaternion()
    if "_hand_targets" in rotations:
        solve_hand_targets(rotations["_hand_targets"])
    if "_foot_targets" in rotations:
        solve_foot_targets(rotations["_foot_targets"])
    for pose_bone in RIG.pose.bones:
        # q and -q encode the same orientation, but interpolating components
        # across opposite signs crosses the zero quaternion and creates a full
        # one-frame flip. Keep every authored key in the previous key's
        # hemisphere before Blender builds the curve.
        if previous_quaternions is not None:
            rotation = pose_bone.rotation_quaternion.copy()
            previous = previous_quaternions.get(pose_bone.name)
            if previous is not None and rotation.dot(previous) < 0.0:
                rotation.negate()
                pose_bone.rotation_quaternion = rotation
            previous_quaternions[pose_bone.name] = rotation.copy()
        pose_bone.keyframe_insert(data_path="rotation_quaternion", frame=frame, group=pose_bone.name)
        if pose_bone.name == "root":
            pose_bone.keyframe_insert(data_path="location", frame=frame, group=pose_bone.name)


def action_fcurves(action):
    """Return legacy or Blender 5 layered-action FCurves."""

    if hasattr(action, "fcurves"):
        return list(action.fcurves)
    curves = []
    for layer in action.layers:
        for strip in layer.strips:
            for channelbag in getattr(strip, "channelbags", ()):
                curves.extend(channelbag.fcurves)
    return curves


def create_action(name, frame_end, poses, loop=False, markers=None):
    action = bpy.data.actions.new(name=name)
    action.use_fake_user = True
    RIG.animation_data.action = action
    previous_quaternions = {}
    for frame, rotations in poses:
        key_pose(frame, rotations, previous_quaternions)
    for curve in action_fcurves(action):
        for keyframe in curve.keyframe_points:
            keyframe.interpolation = (
                "BEZIER"
                if name in ("idle", "pitch", "swing", "catch", "field_ready", "field_throw", "celebrate", "slide")
                else "LINEAR"
            )
            if keyframe.interpolation == "BEZIER":
                keyframe.handle_left_type = "AUTO_CLAMPED"
                keyframe.handle_right_type = "AUTO_CLAMPED"
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


def bake_action_frames(action, frame_start, frame_end):
    """Freeze evaluated quaternion motion to one deterministic key per frame.

    The authored poses remain sparse and readable above, while the exported
    clip behaves like a high-resolution rigged sprite: Blender, glTF, and Godot
    all receive the same sampled arc instead of independently interpolating IK
    solutions.  Sampling is completed before any new key is inserted so the
    source curves cannot feed back into later samples.
    """

    RIG.animation_data.action = action
    samples = []
    for frame in range(frame_start, frame_end + 1):
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        samples.append(
            (
                frame,
                {
                    pose_bone.name: (
                        pose_bone.rotation_quaternion.copy(),
                        pose_bone.location.copy(),
                    )
                    for pose_bone in RIG.pose.bones
                },
            )
        )
    for frame, transforms in samples:
        for bone_name, (rotation, location) in transforms.items():
            pose_bone = RIG.pose.bones[bone_name]
            pose_bone.rotation_quaternion = rotation
            pose_bone.location = location
            pose_bone.keyframe_insert(data_path="rotation_quaternion", frame=frame, group=bone_name)
            if bone_name == "root":
                pose_bone.keyframe_insert(data_path="location", frame=frame, group=bone_name)
    for curve in action_fcurves(action):
        for keyframe in curve.keyframe_points:
            keyframe.interpolation = "LINEAR"


def build_actions():
    RIG.animation_data_create()
    neutral = {}

    def hands(left, right, left_pole=(0.72, -0.18, 1.34), right_pole=(-0.72, -0.18, 1.42)):
        return {
            "L": {"target": left, "pole": left_pole},
            "R": {"target": right, "pole": right_pole},
        }

    def feet(
        left,
        right=(-0.14, -0.22, 0.075),
        left_pole=(0.48, -0.58, 0.66),
        right_pole=(-0.48, -0.30, 0.66),
        left_rotation=(0.0, 0.0, 0.0),
        right_rotation=(0.0, 0.0, 0.0),
    ):
        return {
            "L": {"target": left, "pole": left_pole, "rotation": left_rotation},
            "R": {"target": right, "pole": right_pole, "rotation": right_rotation},
        }

    def build_pitch_action():
        """Author a compact, camera-readable right-handed delivery.

        The pelvis opens before the shoulders, the head counter-rotates just
        enough to keep the eyes on the plate, and root motion returns almost
        completely before the clip hands back to idle.  Hand and foot targets
        use one continuous pole side so Blender cannot choose a different IK
        branch between adjacent keys.
        """

        pitch_action = create_action(
            "pitch",
            45,
            [
                (
                    1,
                    {
                        "hips": (0.0, -4.0, 0.0),
                        "spine": (2.0, -3.0, 0.0),
                        "chest": (2.0, -4.0, 0.0),
                        "head": (-1.0, 8.0, 0.0),
                        "_hand_targets": hands(
                            (0.05, -0.29, 1.34),
                            (-0.04, -0.28, 1.35),
                            right_pole=(-0.72, -0.15, 1.42),
                        ),
                        "_foot_targets": feet((0.14, -0.22, 0.075)),
                    },
                ),
                (
                    8,
                    {
                        "_root_location": (0.0, 0.012, 0.0),
                        "hips": (1.0, -8.0, 0.0),
                        "spine": (1.0, -5.0, -1.0),
                        "chest": (1.0, -8.0, -1.0),
                        "head": (0.0, 16.0, 1.0),
                        "_hand_targets": hands(
                            (0.05, -0.30, 1.31),
                            (-0.04, -0.29, 1.32),
                            right_pole=(-0.72, -0.14, 1.44),
                        ),
                        "_foot_targets": feet((0.14, -0.12, 0.30), left_rotation=(10.0, 0.0, 0.0)),
                    },
                ),
                (
                    16,
                    {
                        "_root_location": (0.0, 0.025, 0.005),
                        "hips": (2.0, -12.0, 0.0),
                        "spine": (2.0, -6.0, -1.0),
                        "chest": (2.0, -10.0, -1.0),
                        "head": (-3.0, 24.0, 1.0),
                        "_hand_targets": hands(
                            (0.04, -0.30, 1.31),
                            (-0.03, -0.29, 1.32),
                            right_pole=(-0.74, -0.12, 1.46),
                        ),
                        "_foot_targets": feet((0.14, -0.08, 0.68), left_rotation=(18.0, 0.0, 0.0)),
                    },
                ),
                (
                    19,
                    {
                        "_root_location": (0.0, 0.012, 0.025),
                        "hips": (2.0, -14.0, 0.0),
                        "spine": (3.0, -7.0, -1.0),
                        "chest": (3.0, -10.0, -1.0),
                        "head": (-5.0, 25.0, 1.0),
                        "_hand_targets": hands(
                            (0.25, -0.42, 1.28),
                            (-0.32, -0.02, 1.30),
                            right_pole=(-0.78, -0.05, 1.48),
                        ),
                        "_foot_targets": feet((0.14, -0.18, 0.58), left_rotation=(14.0, 0.0, 0.0)),
                    },
                ),
                (
                    22,
                    {
                        "_root_location": (0.0, -0.004, 0.075),
                        "hips": (4.0, -12.0, 0.0),
                        "spine": (4.0, -6.0, -1.0),
                        "chest": (4.0, -8.0, -1.0),
                        "head": (-7.0, 20.0, 1.0),
                        "_hand_targets": hands(
                            (0.36, -0.52, 1.25),
                            (-0.45, 0.10, 1.40),
                            right_pole=(-0.80, -0.02, 1.50),
                        ),
                        "_foot_targets": feet((0.15, -0.45, 0.28), left_rotation=(-6.0, 0.0, 0.0)),
                    },
                ),
                (
                    24,
                    {
                        "_root_location": (0.0, -0.035, 0.125),
                        "hips": (5.0, 4.0, 0.0),
                        "spine": (4.0, -8.0, -1.0),
                        "chest": (3.0, -10.0, -1.0),
                        "head": (-7.0, 12.0, 1.0),
                        "_hand_targets": hands(
                            (0.34, -0.60, 1.25),
                            (-0.50, 0.08, 1.54),
                            right_pole=(-0.79, -0.07, 1.54),
                        ),
                        "_foot_targets": feet((0.16, -0.64, 0.075), right_rotation=(2.0, 0.0, 0.0)),
                    },
                ),
                (
                    25,
                    {
                        "_root_location": (0.0, -0.045, 0.145),
                        "hips": (5.5, 8.0, 0.0),
                        "spine": (4.5, -5.0, -1.0),
                        "chest": (4.0, -8.0, -1.0),
                        "head": (-8.5, 6.0, 1.0),
                        "_hand_targets": hands(
                            (0.29, -0.58, 1.24),
                            (-0.48, 0.02, 1.63),
                            right_pole=(-0.78, -0.11, 1.57),
                        ),
                        "_foot_targets": feet((0.16, -0.64, 0.075), right_rotation=(4.0, 0.0, 0.0)),
                    },
                ),
                (
                    26,
                    {
                        "_root_location": (0.0, -0.052, 0.165),
                        "hips": (6.0, 12.0, 0.0),
                        "spine": (5.0, -2.0, -1.0),
                        "chest": (5.0, -5.0, -1.0),
                        "head": (-10.0, -2.0, 1.0),
                        "_hand_targets": hands(
                            (0.24, -0.56, 1.23),
                            (-0.44, -0.03, 1.72),
                            right_pole=(-0.76, -0.15, 1.60),
                        ),
                        "_foot_targets": feet((0.16, -0.64, 0.075), right_rotation=(7.0, 0.0, 0.0)),
                    },
                ),
                (
                    27,
                    {
                        "_root_location": (0.0, -0.058, 0.190),
                        "hips": (6.0, 15.0, 1.0),
                        "spine": (7.0, 2.0, 0.0),
                        "chest": (8.0, 4.0, 0.0),
                        "head": (-12.0, -14.0, 0.0),
                        "_hand_targets": hands(
                            (0.16, -0.24, 1.22),
                            (-0.32, -0.36, 1.68),
                            right_pole=(-0.70, -0.32, 1.59),
                        ),
                        "_foot_targets": feet((0.16, -0.64, 0.075), right_rotation=(10.0, 0.0, 0.0)),
                    },
                ),
                (
                    28,
                    {
                        "_root_location": (0.0, -0.062, 0.215),
                        "hips": (7.0, 18.0, 1.0),
                        "spine": (9.0, 8.0, 1.0),
                        "chest": (12.0, 12.0, 1.0),
                        "head": (-18.0, -28.0, -1.0),
                        "_hand_targets": hands(
                            (0.10, -0.18, 1.22),
                            (-0.08, -1.22, 1.56),
                            right_pole=(-0.62, -0.55, 1.55),
                        ),
                        "_foot_targets": feet((0.16, -0.64, 0.075), right_rotation=(14.0, 0.0, 0.0)),
                    },
                ),
                (
                    29,
                    {
                        "_root_location": (0.0, -0.065, 0.230),
                        "hips": (8.0, 20.0, 1.0),
                        "spine": (10.0, 10.0, 1.0),
                        "chest": (14.0, 14.0, 1.0),
                        "head": (-20.0, -32.0, -1.0),
                        "_hand_targets": hands(
                            (0.08, -0.17, 1.20),
                            (0.02, -1.36, 1.40),
                            right_pole=(-0.45, -0.72, 1.43),
                        ),
                        "_foot_targets": feet((0.16, -0.64, 0.075), right_rotation=(20.0, 0.0, 0.0)),
                    },
                ),
                (
                    34,
                    {
                        "_root_location": (0.0, -0.052, 0.205),
                        "hips": (12.0, 24.0, 1.0),
                        "spine": (14.0, 14.0, 1.0),
                        "chest": (18.0, 14.0, 1.0),
                        "head": (-28.0, -38.0, -2.0),
                        "_hand_targets": hands(
                            (0.06, -0.15, 1.15),
                            (0.30, -0.86, 0.92),
                            right_pole=(-0.05, -0.55, 1.15),
                        ),
                        "_foot_targets": feet(
                            (0.16, -0.64, 0.075),
                            (-0.12, -0.15, 0.50),
                            right_pole=(-0.45, -0.38, 0.72),
                            right_rotation=(20.0, 0.0, 0.0),
                        ),
                    },
                ),
                (
                    39,
                    {
                        "_root_location": (0.0, -0.025, 0.115),
                        "hips": (8.0, 20.0, 1.0),
                        "spine": (8.0, 10.0, 1.0),
                        "chest": (8.0, 8.0, 1.0),
                        "head": (-15.0, -27.0, -1.0),
                        "_hand_targets": hands(
                            (0.10, -0.26, 1.12),
                            (0.32, -0.55, 0.96),
                            right_pole=(0.02, -0.43, 1.10),
                        ),
                        "_foot_targets": feet(
                            (0.14, -0.64, 0.075),
                            (-0.12, -0.38, 0.18),
                            right_pole=(-0.45, -0.56, 0.58),
                            right_rotation=(12.0, 0.0, 0.0),
                        ),
                    },
                ),
                (
                    45,
                    {
                        "_root_location": (0.0, 0.0, 0.0),
                        "hips": (1.0, 4.0, 0.0),
                        "spine": (0.0, 2.0, 0.0),
                        "chest": (0.0, 1.0, 0.0),
                        "head": (0.0, -5.0, 0.0),
                        "_hand_targets": hands(
                            (0.40, -0.10, 0.82),
                            (-0.40, -0.10, 0.80),
                            left_pole=(0.70, -0.12, 1.15),
                            right_pole=(-0.66, -0.18, 1.10),
                        ),
                        "_foot_targets": feet(
                            (0.14, -0.54, 0.075),
                            (-0.13, -0.31, 0.075),
                            left_pole=(0.50, -0.55, 0.62),
                            right_pole=(-0.50, -0.34, 0.60),
                        ),
                    },
                ),
            ],
            markers={"ball_release": 28, "stride_plant": 24},
        )
        bake_action_frames(pitch_action, 1, 45)

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
        "__pitch_v8_diagnostic",
        45,
        [
            (
                1,
                {
                    "hips": (-2.0, -4.0, 0.0),
                    "spine": (2.0, -4.0, 0.0),
                    "chest": (3.0, -6.0, 0.0),
                    "head": (-2.0, 8.0, 0.0),
                    "_hand_targets": hands((0.14, -0.20, 1.35), (-0.14, -0.18, 1.33)),
                    "_foot_targets": feet((0.14, -0.22, 0.075)),
                },
            ),
            (
                4,
                {
                    "hips": (-3.0, -6.0, 0.0),
                    "spine": (3.0, -6.0, 0.0),
                    "chest": (4.0, -8.0, 0.0),
                    "head": (-3.0, 10.0, 0.0),
                    "_hand_targets": hands((0.14, -0.21, 1.37), (-0.14, -0.19, 1.35)),
                    "_foot_targets": feet((0.14, -0.22, 0.075)),
                },
            ),
            (
                7,
                {
                    "_root_location": (0.0, 0.0, 0.01),
                    "hips": (-5.0, -10.0, 0.0),
                    "spine": (2.0, -9.0, -1.0),
                    "chest": (3.0, -13.0, -1.0),
                    "head": (-2.0, 14.0, 1.0),
                    "_hand_targets": hands((0.13, -0.22, 1.40), (-0.13, -0.19, 1.38)),
                    "_foot_targets": feet((0.14, -0.22, 0.075)),
                },
            ),
            (
                10,
                {
                    "_root_location": (0.0, 0.0, 0.025),
                    "hips": (-7.0, -15.0, -1.0),
                    "spine": (-1.0, -14.0, -2.0),
                    "chest": (-3.0, -21.0, -2.0),
                    "head": (2.0, 20.0, 2.0),
                    "_hand_targets": hands((0.13, -0.23, 1.43), (-0.12, -0.20, 1.41)),
                    "_foot_targets": feet((0.14, -0.20, 0.15)),
                },
            ),
            (
                13,
                {
                    "_root_location": (0.0, 0.025, 0.045),
                    "hips": (-8.0, -20.0, -1.0),
                    "spine": (-4.0, -20.0, -2.0),
                    "chest": (-6.0, -28.0, -3.0),
                    "head": (4.0, 26.0, 3.0),
                    "_hand_targets": hands((0.12, -0.26, 1.48), (-0.12, -0.22, 1.46)),
                    "_foot_targets": feet((0.14, -0.15, 0.50)),
                },
            ),
            (
                16,
                {
                    "_root_location": (0.0, 0.045, 0.075),
                    "hips": (-7.0, -23.0, -1.0),
                    "spine": (-5.0, -23.0, -2.0),
                    "chest": (-7.0, -31.0, -3.0),
                    "head": (5.0, 29.0, 3.0),
                    "_hand_targets": hands((0.20, -0.33, 1.39), (-0.30, 0.02, 1.34)),
                    "_foot_targets": feet((0.14, -0.19, 0.68)),
                },
            ),
            (
                19,
                {
                    "_root_location": (0.0, 0.035, 0.15),
                    "hips": (-5.0, -22.0, -1.0),
                    "spine": (-5.0, -23.0, -2.0),
                    "chest": (-6.0, -30.0, -3.0),
                    "head": (4.0, 27.0, 3.0),
                    "_hand_targets": hands((0.34, -0.47, 1.32), (-0.47, 0.10, 1.46)),
                    "_foot_targets": feet((0.16, -0.35, 0.43)),
                },
            ),
            (
                22,
                {
                    "_root_location": (0.0, 0.015, 0.28),
                    "hips": (-2.0, -14.0, 0.0),
                    "spine": (-3.0, -21.0, -1.0),
                    "chest": (-4.0, -28.0, -2.0),
                    "head": (2.0, 24.0, 2.0),
                    "_hand_targets": hands(
                        (0.31, -0.54, 1.26),
                        (-0.45, 0.06, 1.71),
                        right_pole=(-0.78, -0.02, 1.58),
                    ),
                    "_foot_targets": feet((0.17, -0.66, 0.20)),
                },
            ),
            (
                24,
                {
                    "_root_location": (0.0, 0.0, 0.42),
                    "hips": (1.0, 8.0, 1.0),
                    "spine": (-1.0, -8.0, -1.0),
                    "chest": (-2.0, -16.0, -2.0),
                    "head": (0.0, 15.0, 2.0),
                    "_hand_targets": hands(
                        (0.23, -0.48, 1.20),
                        (-0.39, -0.02, 1.79),
                        right_pole=(-0.78, -0.14, 1.64),
                    ),
                    "_foot_targets": feet((0.16, -0.92, 0.075)),
                },
            ),
            (
                25,
                {
                    "_root_location": (0.0, -0.005, 0.49),
                    "hips": (3.0, 18.0, 1.0),
                    "spine": (1.0, 0.0, 0.0),
                    "chest": (1.0, -7.0, -1.0),
                    "head": (-1.0, 7.0, 1.0),
                    "_hand_targets": hands(
                        (0.19, -0.41, 1.18),
                        (-0.35, -0.10, 1.82),
                        right_pole=(-0.72, -0.23, 1.66),
                    ),
                    "_foot_targets": feet((0.16, -0.92, 0.075)),
                },
            ),
            (
                26,
                {
                    "_root_location": (0.0, -0.01, 0.55),
                    "hips": (0.0, 27.0, 2.0),
                    "spine": (1.0, 9.0, 0.0),
                    "chest": (2.0, 2.0, -1.0),
                    "head": (-3.0, 1.0, 1.0),
                    "_hand_targets": hands(
                        (0.15, -0.34, 1.17),
                        (-0.22, -0.14, 1.72),
                        right_pole=(-0.66, -0.34, 1.67),
                    ),
                    "_foot_targets": feet((0.16, -0.92, 0.075)),
                },
            ),
            (
                27,
                {
                    "_root_location": (0.0, -0.015, 0.62),
                    "hips": (-2.0, 37.0, 2.0),
                    "spine": (-2.0, 23.0, 1.0),
                    "chest": (-2.0, 19.0, 1.0),
                    "head": (-6.0, -14.0, 0.0),
                    "_hand_targets": hands(
                        (0.11, -0.26, 1.15),
                        (-0.14, -0.42, 1.69),
                        right_pole=(-0.57, -0.50, 1.64),
                    ),
                    "_foot_targets": feet((0.16, -0.92, 0.075)),
                },
            ),
            (
                28,
                {
                    "_root_location": (0.0, -0.02, 0.68),
                    "hips": (-5.0, 45.0, 3.0),
                    "spine": (-10.0, 38.0, 2.0),
                    "chest": (-14.0, 41.0, 3.0),
                    "head": (-10.0, -31.0, -2.0),
                    "_hand_targets": hands(
                        (0.08, -0.21, 1.13),
                        (-0.08, -1.31, 1.60),
                        right_pole=(-0.49, -0.66, 1.58),
                    ),
                    "_foot_targets": feet((0.16, -0.92, 0.075)),
                },
            ),
            (
                29,
                {
                    "_root_location": (0.0, -0.025, 0.74),
                    "hips": (-8.0, 49.0, 3.0),
                    "spine": (-18.0, 49.0, 3.0),
                    "chest": (-24.0, 56.0, 4.0),
                    "head": (-13.0, -43.0, -3.0),
                    "_hand_targets": hands(
                        (0.06, -0.18, 1.12),
                        (0.04, -1.48, 1.48),
                        right_pole=(-0.40, -0.75, 1.50),
                    ),
                    "_foot_targets": feet((0.16, -0.92, 0.075)),
                },
            ),
            (
                31,
                {
                    "_root_location": (0.0, -0.03, 0.82),
                    "hips": (-8.0, 51.0, 3.0),
                    "spine": (-18.0, 57.0, 4.0),
                    "chest": (-23.0, 64.0, 5.0),
                    "head": (-18.0, -50.0, -4.0),
                    "_hand_targets": hands(
                        (0.06, -0.17, 1.10),
                        (0.20, -1.35, 1.25),
                        right_pole=(-0.25, -0.75, 1.38),
                    ),
                    "_foot_targets": feet((0.16, -0.92, 0.075), (-0.14, -0.46, 0.18)),
                },
            ),
            (
                34,
                {
                    "_root_location": (0.0, -0.035, 0.88),
                    "hips": (-10.0, 50.0, 3.0),
                    "spine": (-22.0, 58.0, 4.0),
                    "chest": (-28.0, 66.0, 5.0),
                    "head": (-21.0, -52.0, -4.0),
                    "_hand_targets": hands(
                        (0.08, -0.18, 1.08),
                        (0.39, -1.05, 1.02),
                        right_pole=(0.05, -0.66, 1.24),
                    ),
                    "_foot_targets": feet((0.16, -0.92, 0.075), (-0.05, -0.70, 0.30)),
                },
            ),
            (
                38,
                {
                    "_root_location": (0.0, -0.025, 0.91),
                    "hips": (-8.0, 45.0, 2.0),
                    "spine": (-17.0, 48.0, 3.0),
                    "chest": (-21.0, 51.0, 4.0),
                    "head": (-16.0, -39.0, -3.0),
                    "_hand_targets": hands(
                        (0.10, -0.21, 1.05),
                        (0.46, -0.78, 0.93),
                        right_pole=(0.22, -0.48, 1.10),
                    ),
                    "_foot_targets": feet((0.16, -0.92, 0.075), (0.10, -0.88, 0.19)),
                },
            ),
            (
                45,
                {
                    "_root_location": (0.0, -0.01, 0.91),
                    "hips": (-4.0, 34.0, 1.0),
                    "spine": (-8.0, 34.0, 2.0),
                    "chest": (-10.0, 35.0, 2.0),
                    "head": (-10.0, -26.0, -2.0),
                    "_hand_targets": hands(
                        (0.12, -0.24, 1.02),
                        (0.33, -0.47, 1.02),
                        right_pole=(0.18, -0.36, 1.08),
                    ),
                    "_foot_targets": feet((0.16, -0.92, 0.075), (0.15, -0.86, 0.075)),
                },
            ),
        ],
        markers={"ball_release": 28, "stride_plant": 24},
    )
    # Keep the previous v8 target set in source history for comparison while
    # ensuring it never reaches the authored asset or exported action list.
    bpy.data.actions.remove(bpy.data.actions["__pitch_v8_diagnostic"])
    build_pitch_action()
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
                    "_hand_targets": hands((-0.21, -0.19, 1.37), (-0.29, -0.16, 1.40)),
                    "_foot_targets": feet((0.16, -0.28, 0.075), (-0.18, -0.18, 0.075)),
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
                    "_hand_targets": hands((-0.23, -0.14, 1.40), (-0.32, -0.11, 1.43)),
                    "_foot_targets": feet((0.16, -0.28, 0.075), (-0.18, -0.18, 0.075)),
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
                    "_hand_targets": hands((-0.08, -0.34, 1.30), (-0.15, -0.34, 1.32)),
                    "_foot_targets": feet((0.18, -0.36, 0.075), (-0.18, -0.18, 0.075)),
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
                    "_hand_targets": hands((0.10, -0.46, 1.22), (0.03, -0.48, 1.23)),
                    "_foot_targets": feet((0.20, -0.48, 0.075), (-0.18, -0.18, 0.075), right_rotation=(8.0, 0.0, 0.0)),
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
                    "_hand_targets": hands((0.30, -0.18, 1.43), (0.24, -0.21, 1.46)),
                    "_foot_targets": feet((0.22, -0.50, 0.075), (-0.16, -0.16, 0.075), right_rotation=(18.0, 0.0, 0.0)),
                },
            ),
            (
                29,
                {
                    "hips": (0.0, 20.0, 0.0),
                    "spine": (5.0, 24.0, 2.0),
                    "chest": (8.0, 32.0, 3.0),
                    "head": (-4.0, -20.0, -2.0),
                    "_hand_targets": hands((0.15, -0.19, 1.25), (0.08, -0.20, 1.27)),
                    "_foot_targets": feet((0.18, -0.38, 0.075), (-0.16, -0.18, 0.075), right_rotation=(6.0, 0.0, 0.0)),
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
        pose_bone.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pose_bone.location = (0.0, 0.0, 0.0)


def finish_scene(meshes):
    scene = bpy.context.scene
    # Godot Agent validates the raw BLENDER header. Blender 5 defaults to Zstd
    # compression, so keep authored build outputs portable and inspectable.
    bpy.context.preferences.filepaths.use_file_compression = False
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.fps = 30
    scene.frame_start = 1
    scene.frame_end = 61
    scene["agent_recipe"] = Path(__file__).name
    scene["agent_recipe_version"] = ASSET_VERSION
    scene["asset_name"] = "Pixiball Ballplayer"
    scene["asset_style"] = "realistic procedurally sculpted baseball athlete"
    scene["license"] = "original project asset"
    scene["nominal_height_m"] = 1.89
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
