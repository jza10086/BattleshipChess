extends Node3D
## One visible ship from an already-filtered team view. Appearance belongs to this scene.
@export var intact_models: Array[PackedScene] = []
@export var wreck_models: Array[PackedScene] = []
@export var wreck_depth: float = -0.06
@onready var _hull: Node3D = %Hull
@onready var _owner_label: Label3D = %OwnerLabel
@onready var _waterline: MeshInstance3D = %Waterline

func _ready() -> void:
	assert(intact_models.size() == 5 and wreck_models.size() == 5, "Ship display requires all five intact/wreck pairs")
	for index: int in range(5):
		assert(intact_models[index] != null and wreck_models[index] != null, "Missing ship model")

## Called once after insertion. The caller supplies only the ship visible to this viewer.
func configure(ship: Dictionary, captain: String, placement: bool) -> void:
	rotation.y = -PI / 2.0 if ship.vertical else 0.0
	_owner_label.text = captain
	show_owner(placement)
	var scene: PackedScene = wreck_models[ship.index] if ship.sunk else intact_models[ship.index]
	var model: Node3D = scene.instantiate()
	_hull.add_child(model)
	_hull.position.y = wreck_depth if ship.sunk else 0.0
	var footprint: Vector2 = Vector2(ship.length - 0.22, 0.8)
	var patch: PlaneMesh = _waterline.mesh
	patch.size = footprint + Vector2.ONE
	var material: ShaderMaterial = _waterline.material_override
	material.set_shader_parameter("footprint", footprint)
	material.set_shader_parameter("patch_size", patch.size)
	material.set_shader_parameter("phase", float(ship.index))
	material.set_shader_parameter("opacity", 0.32 if ship.sunk else 1.0)

func show_owner(placement: bool) -> void:
	_owner_label.visible = placement
