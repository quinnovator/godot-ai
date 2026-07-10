"""Deterministically author a semantic low-poly beacon in Blender."""

import bpy


def material(name, color, metallic=0.0, roughness=0.65, emission=None):
    value = bpy.data.materials.new(name)
    value.diffuse_color = (*color, 1.0)
    value.use_nodes = True
    shader = value.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    if emission is not None:
        emission_input = shader.inputs.get("Emission Color") or shader.inputs.get("Emission")
        emission_input.default_value = (*emission, 1.0)
        shader.inputs["Emission Strength"].default_value = 4.0
    return value


def cube(name, location, scale, surface, bevel=0.04):
    bpy.ops.mesh.primitive_cube_add(location=location)
    value = bpy.context.object
    value.name = name
    value.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    value.data.materials.append(surface)
    if bevel > 0.0:
        modifier = value.modifiers.new("EdgeSoftening", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        bpy.context.view_layer.objects.active = value
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return value


bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)

scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene["agent_recipe"] = "build_beacon.py"
scene["agent_recipe_version"] = 1

dark = material("Beacon_Dark", (0.035, 0.055, 0.085), metallic=0.65, roughness=0.3)
trim = material("Beacon_Trim", (0.18, 0.34, 0.52), metallic=0.4, roughness=0.38)
light = material(
    "Beacon_Emitter",
    (0.08, 0.5, 0.8),
    roughness=0.2,
    emission=(0.05, 0.8, 1.0),
)

root = bpy.data.objects.new("Beacon_Root", None)
bpy.context.collection.objects.link(root)
root.empty_display_type = "PLAIN_AXES"
root["semantic_role"] = "interactable_beacon"

parts = [
    cube("Base", (0.0, 0.0, 0.2), (0.8, 0.8, 0.2), dark, 0.08),
    cube("LowerTrim", (0.0, 0.0, 0.48), (0.64, 0.64, 0.08), trim),
    cube("Core", (0.0, 0.0, 1.02), (0.46, 0.46, 0.46), dark, 0.06),
    cube("UpperTrim", (0.0, 0.0, 1.56), (0.58, 0.58, 0.08), trim),
    cube("Emitter", (0.0, 0.0, 1.9), (0.34, 0.34, 0.26), light, 0.1),
]

for index, offset in enumerate((-0.42, 0.0, 0.42)):
    parts.append(cube("Signal_%02d" % index, (offset, -0.59, 1.02), (0.13, 0.06, 0.22), light, 0.025))

for part in parts:
    part.parent = root
    part["semantic_role"] = "beacon_part"

socket = bpy.data.objects.new("Socket_Top", None)
bpy.context.collection.objects.link(socket)
socket.parent = root
socket.location = (0.0, 0.0, 2.2)
socket.empty_display_type = "PLAIN_AXES"
socket.empty_display_size = 0.2
socket["semantic_role"] = "attachment_socket"

bpy.context.view_layer.objects.active = root
root.select_set(True)
