shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// Deterministic pixel-art turf for the Pixiball field. Every pattern term is
// keyed to world XZ position so the result is stable under camera motion and
// contains no time-dependent noise. Straight mowing lanes run across the field
// and cross a fainter perpendicular hatch; a sparse hash grain adds small
// deliberate pixel clusters. All detail terms fade with distance from the
// plate before they can shimmer at subpixel scale, leaving only the broad
// atmospheric far tint.

uniform vec3 color_a : source_color = vec3(0.42, 0.55, 0.27);
uniform vec3 color_b : source_color = vec3(0.35, 0.46, 0.22);
uniform vec3 color_far : source_color = vec3(0.27, 0.38, 0.24);
// Optional mood turf texture blended over the procedural checker so tones
// match the shipped reference. Defaults white + mix 0 => procedural-only.
uniform sampler2D grass_tex : source_color, filter_nearest_mipmap, hint_default_white;
uniform float grass_tex_mix = 0.0;
uniform float grass_tex_scale = 0.22;
uniform vec2 fan_origin = vec2(0.0, 18.0);
uniform float lane_width = 3.4;
uniform float hatch_width = 6.4;
uniform float grain_scale = 3.0;
uniform float grain_strength = 0.05;
uniform float detail_start = 20.0;
uniform float detail_end = 58.0;
uniform float far_start = 26.0;
uniform float far_end = 78.0;

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 rel = world_xz - fan_origin;
	float dist = length(rel);
	float detail_fade = 1.0 - smoothstep(detail_start, detail_end, dist);
	// Straight mowing lanes across the field, crossed with a faint hatch.
	float lane = mod(floor(rel.y / lane_width), 2.0);
	float hatch = mod(floor(rel.x / hatch_width), 2.0);
	float tone = clamp(lane * 0.7 + hatch * 0.3, 0.0, 1.0);
	// Lanes relax toward the mid tone with distance so far turf stays calm.
	tone = mix(0.5, tone, mix(0.3, 1.0, detail_fade));
	vec3 base = mix(color_a, color_b, tone);
	// Sparse clustered grain: most cells stay clean, marked cells shift one
	// step lighter or darker, and the whole term fades out before aliasing.
	vec2 cell = floor(world_xz * grain_scale);
	float mark = step(0.66, hash2(cell + vec2(17.0, 9.0)));
	float g = floor(hash2(cell) * 3.0) - 1.0;
	base *= 1.0 + g * grain_strength * mark * detail_fade;
	// Tint toward the shipped mood turf texture, fading with distance so the
	// far field stays in the atmospheric color rather than a tiled sample.
	vec3 turf = texture(grass_tex, world_xz * grass_tex_scale).rgb;
	float turf_luma = max(dot(turf, vec3(0.2126, 0.7152, 0.0722)), 0.08);
	vec3 turf_tint = turf / turf_luma;
	base = mix(base, base * mix(vec3(1.0), turf_tint, 0.42), grass_tex_mix * detail_fade);
	// Atmospheric settle toward the outfield keeps the focal lane brightest.
	base = mix(base, color_far, smoothstep(far_start, far_end, dist) * 0.45);
	ALBEDO = base;
	ROUGHNESS = 1.0;
}
