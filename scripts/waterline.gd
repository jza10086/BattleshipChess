extends RefCounted
## An inexpensive local quad, owned by its visible hull or board buoy.
## No fleet arrays, screen/depth textures or world-position uniforms are used.
const SHADER = preload("res://assets/shaders/waterline.gdshader")
static func create(footprint: Vector2, phase: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "Waterline"
	var patch_size := footprint + Vector2.ONE
	var plane := PlaneMesh.new()
	plane.size = patch_size
	node.mesh = plane
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("footprint",footprint)
	material.set_shader_parameter("patch_size",patch_size)
	material.set_shader_parameter("phase",phase)
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node
