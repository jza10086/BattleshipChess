shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
// Original lightweight stylized water. Design references: docs/OCEAN_ART.md.
// This opaque material has no scene depth, reflection pass or fleet-position data.
uniform sampler2D current_fields : repeat_enable, filter_linear_mipmap;
uniform vec3 deep_color : source_color = vec3(0.12, 0.40, 0.47);
uniform vec3 sea_color : source_color = vec3(0.20, 0.55, 0.59);
uniform vec3 shoal_color : source_color = vec3(0.35, 0.67, 0.66);
uniform vec3 crest_color : source_color = vec3(0.65, 0.83, 0.77);
varying vec3 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Maximum displacement is 0.013, safely below the stable grid and shot planes.
	VERTEX.y += sin(dot(world.xz, vec2(0.55, 0.34)) + TIME * 0.48) * 0.008
		+ sin(dot(world.xz, vec2(-0.31, 0.73)) - TIME * 0.37) * 0.005;
}

void fragment() {
	vec2 p = world.xz;
	vec3 field_a = texture(current_fields, p * 0.032 + vec2(TIME * 0.0015, TIME * 0.0009)).rgb;
	vec3 field_b = texture(current_fields, p * 0.047 + vec2(-TIME * 0.0011, TIME * 0.0017) + vec2(0.39, 0.17)).rgb;
	float depth_tint = smoothstep(0.18, 0.82, field_a.r * 0.72 + field_b.r * 0.28);
	vec3 water = mix(deep_color, sea_color, smoothstep(0.0, 0.63, depth_tint));
	water = mix(water, shoal_color, smoothstep(0.42, 1.0, depth_tint) * 0.82);

	// Two crossing swells. Their analytic slopes carry light without moving the board.
	float phase_a = dot(p, vec2(0.80, 0.46)) + TIME * 0.65;
	float phase_b = dot(p, vec2(-0.42, 1.13)) - TIME * 0.48;
	vec2 slope = vec2(0.80, 0.46) * cos(phase_a) * 0.105
		+ vec2(-0.42, 1.13) * cos(phase_b) * 0.065;
	// Softly stepped current patches echo the low-poly hulls, not a noisy normal map.
	float facet = floor(field_b.g * 4.0) * 0.25;
	water *= 0.96 + facet * 0.08;
	NORMAL = normalize((VIEW_MATRIX * vec4(-slope.x, 1.0, -slope.y, 0.0)).xyz);

	// Broken mint crests: limited coverage and derivative smoothing at every resolution.
	float ripple = sin(dot(p, vec2(1.52, 0.88)) + TIME * 0.72 + field_b.g * 3.2);
	float aa = max(fwidth(ripple), 0.004);
	float crest = smoothstep(0.982 - aa, 0.999 + aa, ripple);
	crest *= smoothstep(0.60, 0.79, field_a.b) * smoothstep(0.28, 0.52, field_b.g);
	ALBEDO = mix(water, crest_color, crest * 0.48);
	ROUGHNESS = 0.72;
	SPECULAR = 0.24;
}
