shader_type spatial;
// A translucent stencil on the grid, including where a known hull covers a hit.
// Only public shot cells get this plane; it never reads or outlines hidden ships.
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled;
uniform vec4 mark_color : source_color = vec4(0.9, 0.29, 0.29, 1.0);
uniform bool hit = false;

void fragment() {
	vec2 p = UV - vec2(0.5);
	float edge = max(abs(p.x), abs(p.y));
	float aa = max(fwidth(edge), 0.002);
	float cell = 1.0 - smoothstep(0.47 - aa, 0.47 + aa, edge);
	float border = smoothstep(0.435 - aa, 0.435 + aa, edge) * cell;
	float symbol;
	if (hit) {
		float diagonal = abs(abs(p.x) - abs(p.y));
		symbol = (1.0 - smoothstep(0.026 - aa, 0.026 + aa, diagonal))
			* (1.0 - smoothstep(0.17 - aa, 0.17 + aa, edge));
	} else {
		float ring = abs(length(p) - 0.15);
		symbol = 1.0 - smoothstep(0.022 - aa, 0.022 + aa, ring);
	}
	ALBEDO = mark_color.rgb;
	ALPHA = max(cell * 0.23, max(border * 0.85, symbol * 0.95));
}
