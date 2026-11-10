extends Control
## Full-viewport sea and edge HUD. Receives only the host's filtered view, never hidden fleet state.
signal action_requested(action: Dictionary)
const ShellBurst: Script = preload("res://games/minigame/gp_battleship/shell_burst.gd")
const ShipDisplay: Script = preload("res://games/minigame/gp_battleship/ship_display.gd")
const DEFAULT_TEXT: Translation = preload("res://games/minigame/gp_battleship/i18n/zh_Hans.po")
@export var ship_display_scene: PackedScene
const ShotMarker: PackedScene = preload("res://games/minigame/gp_battleship/shot_marker.tscn")
const TargetMarker: PackedScene = preload("res://games/minigame/gp_battleship/vote_marker.tscn")
@onready var seas: Array[Node3D] = [$Models/BlueSea, $Models/RedSea]
var i18n: RefCounted
@onready var world: WorldEnvironment = %World
@onready var sun: DirectionalLight3D = %Sun
@onready var models: Node3D = %Models
@onready var camera: Camera3D = %Camera
@onready var _ships: Node3D = %Ships
@onready var _impacts: Node3D = %Impacts
@onready var _marks: Node3D = %Marks
@onready var _aim: MeshInstance3D = %Aim
@onready var _status: Label = %Status
@onready var _roster: Label = %Roster
@onready var _event: Label = %Event
@onready var _clock: Label = %Clock
@onready var _hint: Label = %Hint
@onready var _placement: HBoxContainer = %Placement
@onready var _ship_choice: OptionButton = %ShipChoice
@onready var _rotate: Button = %Rotate
@onready var _shuffle: Button = %Shuffle
@onready var _ready_button: Button = %ReadyButton
@onready var _switch: Button = %Switch
@onready var _rules: PanelContainer = %Rules
var _state: Dictionary = {}
var _shown_fleets: Array = []
var _shown_marks: Dictionary = {}
var _names: Dictionary = {}
var _vertical: bool = false
var _selected: int = 0
var input_enabled: bool = false
var _hover: int = -1
var _hover_team: int = -1
var _remaining: float = 0.0
## Formal entry supplies the shared clock; standalone previews use local delta.
var host_clock: Callable

func _ready() -> void:
	assert(ship_display_scene != null, "Missing ship display scene")
	_refresh_text()
	%ShowRules.pressed.connect(func() -> void: _rules.show())
	%CloseRules.pressed.connect(_rules.hide)
	_ship_choice.item_selected.connect(func(index: int) -> void: _selected = _ship_choice.get_item_id(index))
	_rotate.pressed.connect(func() -> void:
		_vertical = not _vertical
		_rotate.text = _text(&"placement.vertical" if _vertical else &"placement.horizontal"))
	_shuffle.pressed.connect(func() -> void: _send({"kind": "shuffle"}))
	_ready_button.pressed.connect(func() -> void: _send({"kind": "ready"}))
	_switch.pressed.connect(func() -> void: _send({"kind": "switch"}))
	_placement.hide()
	_clock.text = ""
	_status.text = ""
	_hint.text = ""

## The standalone view preview uses the same package Translation as formal play.
func _text(key: StringName, parameters: Dictionary = {}) -> String:
	return i18n.text(key, parameters) if i18n != null else String(DEFAULT_TEXT.get_message(key)).format(parameters)

func set_localization(localization: RefCounted) -> void:
	i18n = localization
	_refresh_text()

func _refresh_text() -> void:
	%ShowRules.text = _text(&"rules.open")
	%CloseRules.text = _text(&"rules.close")
	%RulesText.text = _text(&"rules.body")
	%BlueSeaLabel.text = _text(&"sea.blue")
	%RedSeaLabel.text = _text(&"sea.red")
	_rotate.text = _text(&"placement.vertical" if _vertical else &"placement.horizontal")
	_shuffle.text = _text(&"placement.shuffle")
	_switch.text = _text(&"placement.switch")
	_ready_button.text = _text(&"placement.ready")

func set_roster(players: Array[Dictionary]) -> void:
	for player: Dictionary in players:
		_names[player.player_id] = player.name if player.connected else _text(&"player.offline", {"name": player.name})

## Apply a filtered host view. Return the duration of a fresh impact so the final shot can be seen before results.
func show_state(value: Dictionary) -> float:
	var previous_shots: int = value.shots.size() if _state.is_empty() else _state.shots.size()
	_state = value
	_remaining = value.remaining
	var team: int = value.team
	var team_name: String = _text(&"team.spectator" if team < 0 else (&"team.blue" if team == 0 else &"team.red"))
	_status.text = _text(&"hud.solo_status" if value.solo else &"hud.status", {"team": team_name})
	var names: Array[String] = []
	for board: int in range(2):
		var team_names: Array[String] = []
		for id: String in value.teams[board]:
			team_names.append(_names[id])
		names.append(_text(&"hud.team_roster", {"team": _text(&"team.blue" if board == 0 else &"team.red"), "names": "、".join(team_names)}))
	_roster.text = "    |    ".join(names)
	var placement: bool = value.phase == "placement"
	_placement.visible = team >= 0 and (placement or value.solo)
	for control: Control in [_ship_choice, _rotate, _shuffle, _ready_button]:
		control.visible = placement
	_switch.visible = value.solo
	var offered: Array[int] = []
	for index: int in range(_ship_choice.item_count):
		offered.append(_ship_choice.get_item_id(index))
	if offered != value.owned_ships:
		_ship_choice.clear()
		var ship_keys: Array[StringName] = [&"ship.ford", &"ship.yamato", &"ship.enterprise", &"ship.belfast", &"ship.kidd"]
		for index: int in value.owned_ships:
			_ship_choice.add_item(_text(ship_keys[index]), index)
		if not value.owned_ships.is_empty():
			if _selected not in value.owned_ships:
				_selected = value.owned_ships[0]
			_ship_choice.select(_ship_choice.get_item_index(_selected))
	for button: BaseButton in [_ship_choice, _rotate, _shuffle, _ready_button]:
		button.disabled = team < 0 or value.placement_ready
	_ready_button.text = _text(&"placement.waiting" if value.placement_ready else &"placement.ready")
	if placement:
		_event.text = _text(&"hud.placement", {"blue": value.ready_counts[0], "red": value.ready_counts[1]})
	else:
		_event.text = _text(&"hud.salvo", {"round": value.turn_number, "blue": value.targeted[0],
			"blue_total": value.eligible[0], "red": value.targeted[1], "red_total": value.eligible[1]})
	if value.phase == "finished":
		_event.text = _text(&"result.draw") if value.winner < 0 else _text(&"result.winner", {"team": _text(&"team.blue" if value.winner == 0 else &"team.red")})
	elif not value.last_salvo.is_empty():
		var hits: int = 0
		var duds: int = 0
		for shell: Dictionary in value.last_salvo:
			if shell.hit:
				hits += 1
			if shell.dud:
				duds += 1
		_event.text += "    " + _text(&"hud.last_salvo", {"shells": value.last_salvo.size(), "hits": hits, "duds": duds})
	_hint.text = _text(&"hint.placement" if placement else &"hint.target")
	if not placement and team >= 0 and value.own_target >= 0:
		_hint.text = _text(&"hint.selected", {"cell": coordinate(value.own_target)})
	if not placement:
		var totals: Array[String] = []
		for id: String in value.scores:
			totals.append(_text(&"hud.player_score", {"name": _names[id], "score": value.scores[id]}))
		_roster.text += "\n" + " · ".join(totals)
	if placement and team >= 0:
		_status.text = _text(&"hud.assignment", {"status": _status.text, "count": value.owned_ships.size()})
		if value.placement_ready:
			_hint.text = _text(&"hint.waiting")
		else:
			_hint.text = _text(&"hint.owned")
	if team < 0:
		_hint.text = _text(&"hint.spectator")
	if value.fleets != _shown_fleets:
		_shown_fleets = value.fleets.duplicate(true)
		_rebuild_ships()
	for ship: ShipDisplay in _ships.get_children():
		ship.show_owner(placement)
	var marks: Dictionary = {"shots": value.shots, "targets": value.targets, "team": value.team}
	if marks != _shown_marks:
		_shown_marks = marks.duplicate(true)
		_rebuild_marks()

	var impact_time: float = 0.0
	for i: int in range(previous_shots, value.shots.size()):
		var shot: Dictionary = value.shots[i]
		if shot.hit:
			var burst: ShellBurst = ShellBurst.new()
			burst.position = _cell_position(1 - shot.by, shot.cell) + Vector3.UP * 0.20
			_impacts.add_child(burst)
			burst.play(shot.sunk >= 0, i * 100 + shot.cell)
			impact_time = ShellBurst.DURATION
	return impact_time

static func coordinate(cell: int) -> String:
	return String.chr(65 + cell % 10) + str(cell / 10 + 1)

func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _rebuild_ships() -> void:
	_clear(_ships)
	for board: int in range(2):
		for ship: Dictionary in _shown_fleets[board]:
			var holder: ShipDisplay = ship_display_scene.instantiate()
			_ships.add_child(holder)
			holder.global_position = seas[board].to_global(Vector3(ship.x - 4.5, 0, ship.y - 4.5))
			holder.position += Vector3(0, 0, (ship.length - 1) * 0.5) if ship.vertical else Vector3((ship.length - 1) * 0.5, 0, 0)
			var captain: String = _text(&"ship.mine") if board == _state.team and ship.index in _state.owned_ships else _names[ship.owner].left(6)
			holder.configure(ship, captain, _state.phase == "placement")

## End local presentation without disabling the controller's network processing.
func stop() -> void:
	input_enabled = false
	set_process(false)
	set_process_unhandled_input(false)
	_aim.hide()
	_rules.hide()
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
		marker.get_node("TargetOwner").text = _names[id].left(8)

func _process(delta: float) -> void:
	if _state.is_empty():
		return
	_remaining = maxf(0.0, float(_state.end_msec - int(host_clock.call())) / 1000.0) if host_clock.is_valid() else maxf(0.0, _remaining - delta)
	_clock.text = _text(&"hud.clock", {"time": ceili(_remaining)}) if _state.phase != "finished" else ""
	_aim.visible = false
	_hover = -1
	_hover_team = -1
	if not input_enabled or _rules.visible:
		return
	_pick_cell(get_global_mouse_position())

func _pick_cell(mouse: Vector2) -> void:
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

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or _rules.visible or _state.is_empty():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_pick_cell(event.position)
		if _hover < 0:
			return
		if _state.phase == "placement" and not _state.placement_ready and _hover_team == _state.team and _selected in _state.owned_ships:
			_send({"kind": "place", "index": _selected, "x": _hover % 10, "y": _hover / 10, "vertical": _vertical})
		elif _state.phase == "battle" and _state.team >= 0 and _hover_team == 1 - _state.team:
			_send({"kind": "target", "cell": _hover})
		get_viewport().set_input_as_handled()

func _send(action: Dictionary) -> void:
	if not input_enabled or _state.is_empty():
		return
	action["turn"] = _state.turn_number
	action["team"] = _state.team
	action_requested.emit(action)
