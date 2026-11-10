extends Node3D
## Local one-shot impact. Its parent places the origin at the publicly resolved shot.
const STAR: Texture2D = preload("res://games/minigame/gp_battleship/assets/impact/star_05.png")
const DURATION: float = 0.95
static var _puff: ArrayMesh
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func play(sinking: bool, cell_seed: int) -> void:
	_rng.seed = cell_seed
	scale = Vector3.ONE * (1.55 if sinking else 0.88)
	if _puff == null:
		_puff = _faceted_puff()
	var flash: Sprite3D = Sprite3D.new()
	flash.texture = STAR
	flash.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flash.pixel_size = 2.0 / STAR.get_width()
	flash.modulate = Color(1.0, 0.92, 0.49)
	flash.position.y = 0.32
	add_child(flash)
	var pulse: Tween = create_tween().set_parallel(true)
	pulse.tween_property(flash, "scale", Vector3.ONE * 1.45, 0.12).from(Vector3.ONE * 0.28)
	pulse.tween_property(flash, "modulate:a", 0.0, 0.17)
	for i: int in range(8):
		var angle: float = i * TAU / 8.0 + _rng.randf_range(-0.15, 0.15)
		var outward: Vector3 = Vector3(cos(angle), 0, sin(angle))
		_particle(outward * 0.08, outward * _rng.randf_range(0.26, 0.66) + Vector3.UP * _rng.randf_range(0.3, 0.95),
			0.0, 0.44, _rng.randf_range(0.24, 0.47), Color("#ff9236") if i % 2 else Color("#ffdb6b"), 0.0)
		if i % 2 == 0:
			_particle(outward * 0.13 + Vector3.UP * 0.21, outward * 0.45 + Vector3.UP * _rng.randf_range(0.75, 1.30),
				0.10, 0.80, 0.38, Color("#535866") if i % 4 else Color("#79777a"), 0.0)
		_particle(Vector3.UP * 0.18, outward * _rng.randf_range(0.65, 1.22) + Vector3.UP * _rng.randf_range(1.3, 2.0),
			0.03, 0.65, _rng.randf_range(0.07, 0.12), Color("#e99a48"), 1.65)
	create_tween().tween_callback(queue_free).set_delay(DURATION)

func _particle(origin: Vector3, travel: Vector3, delay: float, lifetime: float, radius: float, color: Color, drop: float) -> void:
	var chunk: MeshInstance3D = MeshInstance3D.new()
	chunk.mesh = _puff
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	chunk.material_override = material
	chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk.rotation = Vector3(_rng.randf() * PI, _rng.randf() * TAU, _rng.randf() * PI)
	chunk.hide()
	add_child(chunk)
	var tween: Tween = create_tween()
	tween.tween_callback(chunk.show).set_delay(delay)
	tween.tween_method(func(t: float) -> void:
		chunk.position = origin + travel * t - Vector3.UP * drop * t * t
		chunk.scale = Vector3.ONE * radius * maxf(0.005, minf(1.0, t * 6.0) * (1.0 - t * t))
	, 0.0, 1.0, lifetime)
	tween.tween_callback(chunk.hide)

static func _faceted_puff() -> ArrayMesh:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 6
	sphere.rings = 2
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertices: PackedVector3Array = sphere.get_faces()
	for i: int in range(0, vertices.size(), 3):
		var normal: Vector3 = (vertices[i + 2] - vertices[i]).cross(vertices[i + 1] - vertices[i]).normalized()
		for j: int in range(3):
			surface.set_normal(normal)
			surface.add_vertex(vertices[i + j])
	return surface.commit()
