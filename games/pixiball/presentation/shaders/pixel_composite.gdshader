shader_type canvas_item;
render_mode unshaded;

// Applied to the WorldView SubViewportContainer. TEXTURE is the fixed
// 640x360 world render target (4x MSAA inside the target, shared World3D),
// so the pixel grid is defined by the render resolution itself and is
// identical on any display or framebuffer scale. This pass only quantizes
// color and applies restrained ordered dithering keyed to the logical
// texel grid; the container's nearest filter performs the integer upscale.
// UI CanvasLayers draw after this container and stay native-resolution sharp.
uniform vec2 logical_size = vec2(640.0, 360.0);
uniform float color_steps : hint_range(16.0, 64.0, 1.0) = 48.0;
uniform float dither_strength : hint_range(0.0, 1.0, 0.01) = 0.35;

float bayer4(vec2 cell) {
	ivec2 q = ivec2(mod(cell, 4.0));
	int index = q.x + q.y * 4;
	float values[16] = float[16](
		0.0, 8.0, 2.0, 10.0,
		12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0,
		15.0, 7.0, 13.0, 5.0
	);
	return (values[index] / 16.0) - 0.5;
}

void fragment() {
	vec3 source = texture(TEXTURE, UV).rgb;
	// One dither cell per world texel, indexed on the logical grid so the
	// pattern can never alias against the display resolution, and rounded
	// (not truncated) quantization so mean brightness is preserved.
	float dither = bayer4(floor(UV * logical_size)) * dither_strength;
	vec3 quantized = floor(source * color_steps + 0.5 + dither) / color_steps;
	COLOR = vec4(clamp(quantized, 0.0, 1.0), 1.0);
}
