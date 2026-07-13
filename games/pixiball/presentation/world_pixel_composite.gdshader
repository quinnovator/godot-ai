shader_type canvas_item;
render_mode unshaded;

// World-only dense-pixel finish. This pass runs after the direct 640x360
// design-grid scene but before the native HUD. It never resamples through a
// low-resolution viewport: all taps land on the existing 4x4 native grid.
uniform sampler2D screen_texture : hint_screen_texture, filter_nearest, repeat_disable;
uniform float poster_steps : hint_range(8.0, 32.0, 1.0) = 32.0;
uniform float rim_strength : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float glow_strength : hint_range(0.0, 1.0, 0.01) = 0.16;
uniform float atmosphere_strength : hint_range(0.0, 1.0, 0.01) = 0.10;

float luminance(vec3 color) {
	return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

float hash21(vec2 value) {
	return fract(sin(dot(value, vec2(127.1, 311.7))) * 43758.5453123);
}

float bayer4(vec2 cell) {
	vec2 p = mod(cell, 4.0);
	float row0 = p.x < 1.0 ? 0.0 : (p.x < 2.0 ? 8.0 : (p.x < 3.0 ? 2.0 : 10.0));
	float row1 = p.x < 1.0 ? 12.0 : (p.x < 2.0 ? 4.0 : (p.x < 3.0 ? 14.0 : 6.0));
	float row2 = p.x < 1.0 ? 3.0 : (p.x < 2.0 ? 11.0 : (p.x < 3.0 ? 1.0 : 9.0));
	float row3 = p.x < 1.0 ? 15.0 : (p.x < 2.0 ? 7.0 : (p.x < 3.0 ? 13.0 : 5.0));
	float value = p.y < 1.0 ? row0 : (p.y < 2.0 ? row1 : (p.y < 3.0 ? row2 : row3));
	return (value + 0.5) / 16.0;
}

void fragment() {
	vec2 dense_pixel = SCREEN_PIXEL_SIZE * 4.0;
	vec2 dense_cell = floor(SCREEN_UV / dense_pixel);
	vec2 snapped_uv = (dense_cell + vec2(0.5)) * dense_pixel;
	vec3 source = textureLod(screen_texture, snapped_uv, 0.0).rgb;

	float center_luma = luminance(source);
	float left_luma = luminance(textureLod(screen_texture, snapped_uv - vec2(dense_pixel.x, 0.0), 0.0).rgb);
	float right_luma = luminance(textureLod(screen_texture, snapped_uv + vec2(dense_pixel.x, 0.0), 0.0).rgb);
	float up_luma = luminance(textureLod(screen_texture, snapped_uv - vec2(0.0, dense_pixel.y), 0.0).rgb);
	float down_luma = luminance(textureLod(screen_texture, snapped_uv + vec2(0.0, dense_pixel.y), 0.0).rgb);
	float edge = clamp(max(max(abs(left_luma - center_luma), abs(right_luma - center_luma)), max(abs(up_luma - center_luma), abs(down_luma - center_luma))) * 2.4, 0.0, 1.0);

	// Directional rim: cool light catches upper-left silhouette edges while a
	// small warm bounce catches bright material edges. Both remain hard steps.
	float cool_rim = max(0.0, max(left_luma, up_luma) - center_luma) * edge;
	float warm_rim = max(0.0, center_luma - min(right_luma, down_luma)) * edge;
	vec3 color = source;
	color += vec3(0.18, 0.72, 0.74) * cool_rim * rim_strength;
	color += vec3(1.0, 0.63, 0.28) * warm_rim * rim_strength * 0.42;

	// Two discrete neighbour rings give lamps, ball highlights, and chalk a
	// stepped emissive fringe instead of a soft blur.
	float near_peak = max(max(left_luma, right_luma), max(up_luma, down_luma));
	float far_peak = 0.0;
	far_peak = max(far_peak, luminance(textureLod(screen_texture, snapped_uv + vec2(dense_pixel.x * 2.0, 0.0), 0.0).rgb));
	far_peak = max(far_peak, luminance(textureLod(screen_texture, snapped_uv - vec2(dense_pixel.x * 2.0, 0.0), 0.0).rgb));
	far_peak = max(far_peak, luminance(textureLod(screen_texture, snapped_uv + vec2(0.0, dense_pixel.y * 2.0), 0.0).rgb));
	far_peak = max(far_peak, luminance(textureLod(screen_texture, snapped_uv - vec2(0.0, dense_pixel.y * 2.0), 0.0).rgb));
	float dark_receiver = smoothstep(0.62, 0.18, center_luma);
	float stepped_glow = smoothstep(0.76, 0.96, near_peak) * 0.75 + smoothstep(0.84, 0.99, far_peak) * 0.25;
	color += vec3(1.0, 0.72, 0.34) * stepped_glow * dark_receiver * glow_strength;

	// Posterization is dithered per dense design cell, preserving hard native
	// pixels while creating intermediate material values without gradients.
	float threshold = bayer4(dense_cell) - 0.5;
	color = floor(clamp(color, vec3(0.0), vec3(1.0)) * poster_steps + 0.5 + threshold * 0.18) / poster_steps;

	// Sparse atmospheric motes animate at 6 fps. They only appear away from
	// the outer frame and on middle/dark values, so gameplay silhouettes win.
	float tick = floor(TIME * 6.0);
	float mote_seed = hash21(dense_cell + vec2(tick * 0.37, -tick * 0.19));
	float middle_field = step(0.07, SCREEN_UV.y) * step(SCREEN_UV.y, 0.86) * step(center_luma, 0.48);
	float mote = step(0.9992, mote_seed) * middle_field;
	color += mix(vec3(0.20, 0.66, 0.69), vec3(1.0, 0.71, 0.35), step(0.9997, mote_seed)) * mote * atmosphere_strength;

	// Four hard vignette terraces, dithered on their seams.
	vec2 centered = abs(SCREEN_UV * 2.0 - 1.0);
	float frame = max(centered.x, centered.y);
	float vignette = floor(clamp((frame - 0.72) * 10.0 + threshold * 0.28, 0.0, 3.0)) / 3.0;
	color *= 1.0 - vignette * atmosphere_strength * 0.36;
	COLOR = vec4(clamp(color, vec3(0.0), vec3(1.0)), 1.0);
}
