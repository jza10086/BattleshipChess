class_name ShipVisual
extends Node3D
## Real CC0 glTF models by Kenney; local +X follows board columns.
const Waterline = preload("res://scripts/waterline.gd")
const MODELS := [preload("res://assets/kenney-watercraft/ship-ocean-liner.glb"), preload("res://assets/kenney-watercraft/ship-cargo-a.glb"), preload("res://assets/kenney-watercraft/boat-tug-a.glb"), preload("res://assets/kenney-watercraft/boat-tug-b.glb"), preload("res://assets/kenney-watercraft/boat-speed-a.glb")]
const LENGTHS := [5,4,3,3,2]
const BOUNDS := [Vector3(4.76,8.934,21.28),Vector3(3.917,3.38,10.549),Vector3(1.785,2.237,3.47),Vector3(1.785,2.237,2.87),Vector3(1.785,1.5,3.37)]
var kind := 0
var sunk := false
var base_y := 0.0
var body: Node3D
var seed_phase := 0.0
var waterline: MeshInstance3D
var waterline_sunk := false
static var materials: Dictionary = {}
static func material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if materials.has(key): return materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = .86
	materials[key] = m
	return m
func setup(index: int, _enemy := false) -> void:
	kind = index
	seed_phase = index*1.8
	waterline = Waterline.create(Vector2(LENGTHS[index]-.22,.80), seed_phase)
	add_child(waterline)
	waterline.position.y = -.018
	body = Node3D.new()
	add_child(body)
	var model: Node3D = MODELS[index].instantiate()
	body.add_child(model)
	var bounds: Vector3 = BOUNDS[index]
	model.scale = Vector3(.92/bounds.x, minf((LENGTHS[index]-.18)/bounds.z,.53), (LENGTHS[index]-.18)/bounds.z)
	model.rotation.y = PI/2
	model.position.y = -.13
	var collision := StaticBody3D.new()
	collision.collision_layer = 1
	collision.collision_mask = 0
	add_child(collision)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(LENGTHS[index]-.10, 1.8 if index==0 else 1.1, .95)
	shape.shape = box
	shape.position.y = box.size.y*.5-.12
	collision.add_child(shape)
func _process(delta: float) -> void:
	if body == null: return
	# A lifted placement preview must not lift its waterline off the sea.
	waterline.global_position.y = -.018
	if waterline_sunk != sunk:
		waterline_sunk = sunk
		waterline.material_override.set_shader_parameter("opacity", .32 if sunk else 1.0)
	var t := Time.get_ticks_msec()*.001
	base_y = move_toward(base_y,-.47 if sunk else 0.0,delta*.23)
	body.position.y = base_y + sin(t*1.15+seed_phase)*.018
	body.rotation.x = sin(t*.9+seed_phase)*.008
	body.rotation.z = sin(t*.7+seed_phase)*.006 + (-.055 if sunk else 0.0)
