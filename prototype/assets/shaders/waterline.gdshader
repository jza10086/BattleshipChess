shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
// Local-only waterline. Instantiated by visible ship/buoy nodes, never hidden data.
uniform vec2 footprint = vec2(4.6, 0.85);
uniform vec2 patch_size = vec2(5.6, 1.85);
uniform float phase = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform vec3 foam_color : source_color = vec3(0.72, 0.88, 0.81);

void fragment() {
	vec2 p = (UV - 0.5) * patch_size;
	float half_straight = max(0.0, (footprint.x - footprint.y) * 0.5);
	vec2 q = vec2(max(abs(p.x) - half_straight, 0.0), p.y);
	float distance_to_hull = length(q) - footprint.y * 0.5;
	float aa = max(fwidth(distance_to_hull), 0.012);
	float flutter = sin(p.x * 5.3 + p.y * 4.1 + TIME * 1.2 + phase);
	float edge = 0.045 + flutter * 0.018;
	float contact = 1.0 - smoothstep(0.022, 0.052 + aa, abs(distance_to_hull - edge));
	float breakup = smoothstep(-0.72, -0.12, sin(p.x * 3.4 - p.y * 5.1 + TIME * 0.65 + phase));
	float cycle = fract(TIME * 0.23 + phase * 0.17);
	float ring_distance = 0.13 + cycle * 0.30;
	float ring = (1.0 - smoothstep(0.015, 0.037 + aa, abs(distance_to_hull - ring_distance))) * (1.0 - cycle);
	float outside = smoothstep(-0.04, 0.02, distance_to_hull);
	ALBEDO = foam_color;
	ALPHA = outside * (contact * 0.43 + ring * 0.24) * breakup * opacity;
}
