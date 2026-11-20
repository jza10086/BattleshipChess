extends Control
## Full-viewport sea and edge HUD. Receives only the host's filtered view, never hidden fleet state.
signal action_requested(action: Dictionary)
const ShellBurst: Script = preload("res://games/minigame/GP_battleship/shell_burst.gd")
const Rules: Script = preload("res://games/minigame/GP_battleship/battleship_rules.gd")
const ShipDisplay: Script = preload("res://games/minigame/GP_battleship/ship_display.gd")
@export var ship_display_scene: PackedScene
const ShotMarker: PackedScene = preload("res://games/minigame/GP_battleship/shot_marker.tscn")
const TargetMarker: PackedScene = preload("res://games/minigame/GP_battleship/vote_marker.tscn")
@onready var seas: Array[Node3D] = [$Models/BlueSea, $Models/RedSea]
@onready var world: WorldEnvironment = %World
@onready var sun: DirectionalLight3D = %Sun
@onready var models: Node3D = %Models
@onready var camera: Camera3D = %Camera
@onready var _ships: Node3D = %Ships
@onready var _impacts: Node3D = %Impacts
@onready var _marks: Node3D = %Marks
@onready var _aim: MeshInstance3D = %Aim
@onready var _clock: Label = $GameHUD/Status/RoundClock
var _state: Dictionary = {}
var _shown_fleets: Array = []
var _shown_marks: Dictionary = {}
const FALL_SECONDS: float = 0.55
const SALVO_SECONDS: float = FALL_SECONDS + ShellBurst.DURATION + 0.1
var _salvo_turn: int = -1
var _landing: Tween
var _footprint: MeshInstance3D = MeshInstance3D.new()
var _vertical: bool = false
var _selected: int = 0
var _carrying: bool = false
var _preview_team: int = -2
var _grip: int = 0
var _ghost: Node3D
var _ghost_index: int = -1
var _ghost_material: StandardMaterial3D = StandardMaterial3D.new()
var _sources: Dictionary[int, ShipDisplay] = {}
var _hidden_source: ShipDisplay
var _preview_action: Dictionary = {}
var input_enabled: bool = false
var _hover: int = -1
var _hover_team: int = -1
var _remaining: float = 0.0
## Formal entry supplies the shared clock; standalone previews use local delta.
var host_clock: Callable

func _ready() -> void:
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_footprint.mesh = BoxMesh.new()
	_footprint.material_override = _ghost_material
	_footprint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	models.add_child(_footprint)
	_footprint.hide()

func show_state(value: Dictionary) -> void:
	if _preview_team != value.team or value.phase != "placement":
		_cancel_move()
	_preview_team = value.team
	_state = value
	_remaining = value.remaining
	if value.phase == "impact" and _salvo_turn != value.turn_number:
		_salvo_turn = value.turn_number
		var elapsed: float = 0.0
		if host_clock.is_valid():
			elapsed = clampf(SALVO_SECONDS - (value.end_msec - int(host_clock.call())) / 1000.0, 0.0, SALVO_SECONDS)
		if elapsed < FALL_SECONDS:
			for shot: Dictionary in value.last_salvo:
				_drop_shell(shot, elapsed)
			_landing = _impacts.create_tween()
			_landing.tween_callback(_show_board).set_delay(FALL_SECONDS - elapsed)
		else:
			_show_board()
			for shot: Dictionary in value.last_salvo:
				_land_shell(shot, elapsed - FALL_SECONDS)
	elif value.phase != "impact":
		_show_board()

func _show_board() -> void:
	var value: Dictionary = _state
	if value.fleets != _shown_fleets:
		_shown_fleets = value.fleets.duplicate(true)
		_rebuild_ships()
	var marks: Dictionary = {"shots": value.shots, "targets": value.targets, "team": value.team}
	if marks != _shown_marks:
		_shown_marks = marks.duplicate(true)
		_rebuild_marks()

func _drop_shell(shot: Dictionary, elapsed: float) -> void:
	var shell: MeshInstance3D = MeshInstance3D.new()
	var ball: SphereMesh = SphereMesh.new()
	ball.radius = 0.14
	ball.height = 0.34
	shell.mesh = ball
	var steel: StandardMaterial3D = StandardMaterial3D.new()
	steel.albedo_color = Color(0.16, 0.18, 0.21)
	shell.material_override = steel
	_impacts.add_child(shell)
	var target: Vector3 = _cell_position(1 - shot.by, shot.cell)
	shell.global_position = target + Vector3.UP * 8.0
	var fall: Tween = shell.create_tween()
	fall.tween_property(shell, "global_position", target, FALL_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_callback(func() -> void:
		shell.queue_free()
		_land_shell(shot, 0.0))
	fall.custom_step(elapsed)

func _land_shell(shot: Dictionary, age: float) -> void:
	var target: Vector3 = _cell_position(1 - shot.by, shot.cell)
	if shot.hit and age < ShellBurst.DURATION:
		var burst: ShellBurst = ShellBurst.new()
		_impacts.add_child(burst)
		burst.global_position = target + Vector3.UP * 0.20
		burst.play(shot.sunk >= 0, shot.cell)
		burst.advance(age)
	elif not shot.hit and age < 0.85:
		_splash(target, age)

func _splash(target: Vector3, age: float) -> void:
	var ripple: MeshInstance3D = MeshInstance3D.new()
	var ring: TorusMesh = TorusMesh.new()
	ring.inner_radius = 0.42
	ring.outer_radius = 0.5
	ripple.mesh = ring
	var foam: StandardMaterial3D = StandardMaterial3D.new()
	foam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	foam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	foam.albedo_color = Color(0.78, 0.96, 1, 0.85)
	ripple.material_override = foam
	_impacts.add_child(ripple)
	ripple.global_position = target
	ripple.scale = Vector3(0.18, 0.25, 0.18)
	var wave: Tween = ripple.create_tween().set_parallel()
	wave.tween_property(ripple, "scale", Vector3(2, 0.12, 2), 0.85)
	wave.tween_property(foam, "albedo_color:a", 0.0, 0.85)
	wave.chain().tween_callback(ripple.queue_free)
	wave.custom_step(age)

func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _rebuild_ships() -> void:
	_hide_preview()
	_sources.clear()
	_clear(_ships)
	for board: int in range(2):
		for ship: Dictionary in _shown_fleets[board]:
			var holder: ShipDisplay = ship_display_scene.instantiate()
			_ships.add_child(holder)
			if board == _state.team:
				_sources[ship.index] = holder
			holder.global_position = seas[board].to_global(Vector3(ship.x - 4.5, 0, ship.y - 4.5))
			holder.position += Vector3(0, 0, (ship.length - 1) * 0.5) if ship.vertical else Vector3((ship.length - 1) * 0.5, 0, 0)
			holder.configure(ship, "", false)

## End local presentation without disabling the controller's network processing.
func stop() -> void:
	if _landing != null:
		_landing.kill()
	_cancel_move()
	input_enabled = false
	set_process(false)
	set_process_unhandled_input(false)
	_aim.hide()
	%GameHUD.hide()
	_clear(_impacts)

func _cell_position(board: int, cell: int) -> Vector3:
	return seas[board].to_global(Vector3(cell % 10 - 4.5, 0.07, cell / 10 - 4.5))

func _rebuild_marks() -> void:
	_clear(_marks)
	for shot: Dictionary in _state.shots:
		var marker: MeshInstance3D = ShotMarker.instantiate()
		_marks.add_child(marker)
		marker.global_position = _cell_position(1 - shot.by, shot.cell)
		if shot.hit:
			marker.material_override.albedo_color = Color(0.95, 0.2, 0.18, 0.75)
	for id: String in _state.targets:
		var cell: int = _state.targets[id]
		var marker: MeshInstance3D = TargetMarker.instantiate()
		_marks.add_child(marker)
		marker.global_position = _cell_position(1 - _state.team, cell)
		marker.get_node("TargetOwner").hide()

func _process(delta: float) -> void:
	if _state.is_empty():
		return
	_remaining = maxf(0.0, float(_state.end_msec - int(host_clock.call())) / 1000.0) if host_clock.is_valid() else maxf(0.0, _remaining - delta)
	_clock.visible = _state.phase in ["placement", "battle", "countdown"]
	_clock.text = str(ceili(_remaining))
	_aim.visible = false
	_hover = -1
	_hover_team = -1
	if not input_enabled or _state.phase not in ["placement", "battle"]:
		_hide_preview()
		return
	_pick_cell(get_global_mouse_position())

func _pick_cell(mouse: Vector2) -> void:
	_hide_preview()
	_aim.hide()
	_hover = -1
	_hover_team = -1
	var intersection: Variant = Plane(Vector3.UP, 0.0).intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	if intersection == null:
		return
	for board: int in range(2):
		var relative: Vector3 = seas[board].to_local(intersection)
		var x: int = floori(relative.x + 5.0)
		var y: int = floori(relative.z + 5.0)
		if x >= 0 and x < 10 and y >= 0 and y < 10:
			_hover = y * 10 + x
			_hover_team = board
			_aim.position = _cell_position(board, _hover) + Vector3(0, 0.04, 0)
			_aim.visible = true
			if _state.phase == "placement":
				_preview_move()
			return

func _hide_preview() -> void:
	_footprint.hide()
	_preview_action.clear()
	if is_instance_valid(_hidden_source):
		_hidden_source.show()
		_hidden_source = null
	if _ghost != null:
		_ghost.hide()

func _cancel_move() -> void:
	_hide_preview()
	_carrying = false
	_grip = 0

func _owned_ship_at_cursor() -> int:
	var cell: Vector2i = Vector2i(_hover % 10, _hover / 10)
	for ship: Dictionary in _state.fleets[_state.team]:
		if cell in Rules.cells(ship):
			return ship.index
	return -1

func _preview_move() -> void:
	if _hover_team != _state.team:
		_aim.hide()
		return
	if not _carrying:
		return
	var source: ShipDisplay = _sources[_selected]
	var length: int = Rules.LENGTHS[_selected]
	var axis: Vector2i = Vector2i.DOWN if _vertical else Vector2i.RIGHT
	var origin: Vector2i = Vector2i(_hover % 10, _hover / 10) - axis * _grip
	var candidate: Array = _state.fleets[_state.team].duplicate()
	for i: int in candidate.size():
		if candidate[i].index == _selected:
			candidate[i] = {"x": origin.x, "y": origin.y, "vertical": _vertical, "length": length}
			break
	var legal: bool = Rules.valid_fleet(candidate)
	if legal:
		_preview_action = {"kind": "place", "index": _selected, "x": origin.x, "y": origin.y, "vertical": _vertical}
	if _ghost_index != _selected:
		if _ghost != null:
			_ghost.queue_free()
		_ghost = source.intact_models[_selected].instantiate()
		models.add_child(_ghost)
		_ghost_index = _selected
	_ghost_material.albedo_color = Color(0.3, 1.0, 0.7, 0.68) if legal else Color(1.0, 0.2, 0.18, 0.75)
	var center: Vector2 = Vector2(origin) + Vector2(axis) * (length - 1) * 0.5
	_ghost.global_position = seas[_hover_team].to_global(Vector3(center.x - 4.5, 1.05, center.y - 4.5))
	_ghost.rotation.y = -PI / 2.0 if _vertical else 0.0
	_footprint.global_position = _ghost.global_position - Vector3.UP * 0.96
	_footprint.scale = Vector3(length - 0.04, 0.025, 0.96)
	_footprint.rotation.y = _ghost.rotation.y
	_footprint.show()
	_ghost.show()
	source.hide()
	_hidden_source = source
	_aim.hide()

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or _state.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo and _state.phase == "placement":
		if event.physical_keycode == KEY_R and _carrying:
			_vertical = not _vertical
			_pick_cell(get_global_mouse_position())
		elif event.physical_keycode == KEY_SPACE and _state.solo:
			_cancel_move()
			_send({"kind": "switch"})
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and _carrying:
		_cancel_move()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_pick_cell(event.position)
		if _hover < 0:
			return
		if _state.phase == "placement" and _hover_team == _state.team:
			var picked: int = _owned_ship_at_cursor()
			if not _carrying and picked >= 0:
				_selected = picked
				var ship: Dictionary = _state.fleets[_state.team].filter(func(item: Dictionary) -> bool: return item.index == picked).front()
				_vertical = ship.vertical
				_grip = _hover / 10 - ship.y if _vertical else _hover % 10 - ship.x
				_carrying = true
				_preview_move()
			elif not _preview_action.is_empty():
				_send(_preview_action.duplicate())
				_cancel_move()
		elif _state.phase == "battle" and _state.team >= 0 and _hover_team == 1 - _state.team:
			_send({"kind": "target", "cell": _hover})
		get_viewport().set_input_as_handled()

func _send(action: Dictionary) -> void:
	if not input_enabled or _state.is_empty():
		return
	action["turn"] = _state.turn_number
	action["team"] = _state.team
	action_requested.emit(action)
