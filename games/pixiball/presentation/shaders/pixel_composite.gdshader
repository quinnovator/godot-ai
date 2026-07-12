shader_type canvas_item;
render_mode unshaded;

// Applied to the native-resolution WorldView SubViewportContainer. Geometry
// keeps 4x MSAA while this finish quantizes luminance, rather than crushing
// each RGB channel independently. The result retains colorful material detail
// and uses the pixel treatment as a restrained accent. UI draws afterward.
uniform vec2 logical_size = vec2(1280.0, 720.0);
uniform float color_steps : hint_range(16.0, 64.0, 1.0) = 48.0;
uniform float dither_strength : hint_range(0.0, 1.0, 0.01) = 0.08;

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
	// One stable dither cell per native world texel. Quantizing luminance keeps
	// team colors and skin tones intact instead of building noisy RGB ramps.
	float dither = bayer4(floor(UV * logical_size)) * dither_strength;
	float luma = dot(source, vec3(0.2126, 0.7152, 0.0722));
	float quantized_luma = floor(luma * color_steps + 0.5 + dither) / color_steps;
	vec3 quantized = source + vec3(quantized_luma - luma);
	COLOR = vec4(clamp(quantized, 0.0, 1.0), 1.0);
}
