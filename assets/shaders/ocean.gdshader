shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec3 sea_color : source_color = vec3(0.25, 0.61, 0.66);
varying vec3 world;
void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(world.x * 0.7 + TIME * 0.45) * cos(world.z * 0.65 + TIME * 0.3) * 0.012;
}
void fragment() {
	float broad = sin(world.x*.25 + world.z*.15 + TIME*.035)*sin(world.z*.22 - world.x*.13);
	float wave = pow(max(0.0, sin(world.x*1.7 + world.z*1.4 + TIME*.55) * sin(world.z*.8 - TIME*.3)), 14.0);
	ALBEDO = sea_color + broad*.012 + wave*.008;
	ROUGHNESS = .76;
	SPECULAR = .25;

}
