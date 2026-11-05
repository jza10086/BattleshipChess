extends Control
## Full-viewport sea and edge HUD. Receives only the host's filtered view, never hidden fleet state.
signal action_requested(action: Dictionary)
const ShellBurst: Script = preload("res://games/minigame/godot_party_default_battleship_chess/shell_burst.gd")
const MODELS: Array[PackedScene] = [
	preload("res://games/minigame/godot_party_default_battleship_chess/assets/fleet/uss_gerald_r_ford_cvn78.glb"),
	preload("res://games/minigame/godot_party_default_battleship_chess/assets/yamato/yamato_battleship.glb"),
	preload("res://games/minigame/godot_party_default_battleship_chess/assets/fleet/enterprise_cv6.glb"),
	preload("res://games/minigame/godot_party_default_battleship_chess/assets/fleet/hms_belfast.glb"),
	preload("res://games/minigame/godot_party_default_battleship_chess/assets/fleet/uss_kidd_dd661.glb")]
const WRECKS: Array[PackedScene] = [
	preload("res://games/minigame/godot_party_default_battleship_chess/assets/fleet/uss_gerald_r_ford_cvn78_destroyed.glb"),
	preload("res://games/minigame/godot_party_default_battleship_chess/assets/yamato/yamato_battleship_destroyed.glb"),
	preload("res://games/minigame/godot_party_default_battleship_chess/assets/fleet/enterprise_cv6_destroyed.glb"),
	preload("res://games/minigame/godot_party_default_battleship_chess/assets/fleet/hms_belfast_destroyed.glb"),
	preload("res://games/minigame/godot_party_default_battleship_chess/assets/fleet/uss_kidd_dd661_destroyed.glb")]
const FONT: Font = preload("res://games/minigame/godot_party_default_battleship_chess/assets/fonts/SeaInterface.otf")
const ShotMarker: PackedScene = preload("res://games/minigame/godot_party_default_battleship_chess/shot_marker.tscn")
const TargetMarker: PackedScene = preload("res://games/minigame/godot_party_default_battleship_chess/vote_marker.tscn")
const WATERLINE: Shader = preload("res://games/minigame/godot_party_default_battleship_chess/assets/shaders/waterline.gdshader")
const FIELDS: Texture2D = preload("res://games/minigame/godot_party_default_battleship_chess/assets/textures/ocean_fields.png")
@onready var seas: Array[Node3D] = [$Models/BlueSea, $Models/RedSea]
var i18n: RefCounted
@onready var world: WorldEnvironment = %World
@onready var sun: DirectionalLight3D = %Sun
@onready var models: Node3D = %Models
@onready var camera: Camera3D = %Camera
@onready var _ships: Node3D = %Ships
@onready var _owner_labels: Node3D = %OwnerLabels
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

func _ready() -> void:
	%ShowRules.pressed.connect(func() -> void: _rules.show())
	%CloseRules.pressed.connect(_rules.hide)
	_ship_choice.item_selected.connect(func(index: int) -> void: _selected = _ship_choice.get_item_id(index))
	_rotate.pressed.connect(func() -> void:
		_vertical = not _vertical
		_rotate.text = "纵向放置" if _vertical else "横向放置")
	_shuffle.pressed.connect(func() -> void: _send({"kind": "shuffle"}))
	_ready_button.pressed.connect(func() -> void: _send({"kind": "ready"}))
	_switch.pressed.connect(func() -> void: _send({"kind": "switch"}))
	_placement.hide()
	_clock.text = ""
	_status.text = ""
	_hint.text = ""

func _text3d(text: String, at: Vector3, parent: Node3D) -> Label3D:
	var label: Label3D = Label3D.new()
	label.text = text
	label.font = FONT
	label.font_size = 38
	label.pixel_size = 0.012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = at
	label.no_depth_test = true
	parent.add_child(label)
	return label

func set_roster(players: Array[Dictionary]) -> void:
	for player: Dictionary in players:
		_names[player.player_id] = player.name + ("" if player.connected else "（离线）")

## Apply a filtered host view. Return the duration of a fresh impact so the final shot can be seen before results.
func show_state(value: Dictionary) -> float:
	var previous_shots: int = value.shots.size() if _state.is_empty() else _state.shots.size()
	_state = value
	_remaining = value.remaining
	var team: int = value.team
	var team_name: String = "观战" if team < 0 else ("蓝队" if team == 0 else "红队")
	_status.text = "海战棋 · " + ("单人测试 · 当前操作" if value.solo else "") + team_name
	var names: Array[String] = []
	for board: int in range(2):
		var team_names: Array[String] = []
		for id: String in value.teams[board]:
			team_names.append(_names[id])
		names.append(("蓝队 " if board == 0 else "红队 ") + "、".join(team_names))
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
		var ship_names: Array[String] = ["福特号航母 · 5格", "大和号战列舰 · 4格", "企业号航母 · 4格", "贝尔法斯特号巡洋舰 · 3格", "基德号驱逐舰 · 2格"]
		for index: int in value.owned_ships:
			_ship_choice.add_item(ship_names[index], index)
		if not value.owned_ships.is_empty():
			if _selected not in value.owned_ships:
				_selected = value.owned_ships[0]
			_ship_choice.select(_ship_choice.get_item_index(_selected))
	for button: BaseButton in [_ship_choice, _rotate, _shuffle, _ready_button]:
		button.disabled = team < 0 or value.placement_ready
	_ready_button.text = "已完成，等待队友" if value.placement_ready else "我的布阵完成"
	_event.text = ("布阵确认：蓝队 %d 人 · 红队 %d 人" % [value.ready_counts[0], value.ready_counts[1]]) if placement else "共同回合 %d · 蓝队已选 %d/%d · 红队已选 %d/%d" % [value.turn_number, value.targeted[0], value.eligible[0], value.targeted[1], value.eligible[1]]
	if value.phase == "finished":
		_event.text = "双方平局" if value.winner < 0 else ("蓝队" if value.winner == 0 else "红队") + "获胜"
	elif not value.last_salvo.is_empty():
		var hits: int = 0
		var duds: int = 0
		for shell: Dictionary in value.last_salvo:
			if shell.hit:
				hits += 1
			if shell.dud:
				duds += 1
		_event.text += "    上轮 %d 发 · 命中 %d · 哑弹 %d" % [value.last_salvo.size(), hits, duds]
	_hint.text = "选择舰船和方向，点击己方格子放置 · Esc 菜单" if placement else "点击敌方空闲格抢选目标 · 同队先到先得，可改选空闲格 · 命中 +1，胜队 +100 · Esc 菜单"
	if not placement and team >= 0 and value.own_target >= 0:
		_hint.text = "已选 %s · 等待双方选齐或超时发射 · 可改选空闲格 · Esc 菜单" % coordinate(value.own_target)
	if not placement:
		var totals: Array[String] = []
		for id: String in value.scores:
			totals.append("%s %d分" % [_names[id], value.scores[id]])
		_roster.text += "\n" + " · ".join(totals)
	if placement and team >= 0:
		_status.text += " · 负责 %d 艘舰船" % value.owned_ships.size()
		if value.placement_ready:
			_hint.text = "你的布阵已完成，等待其余玩家确认 · Esc 菜单"
		else:
			_hint.text = "仅能摆放自己的舰船；舰船上方显示负责人 · Esc 菜单"
	if team < 0:
		_hint.text = "观战：仅显示公开命中与已沉舰船 · Esc 菜单"
	if value.fleets != _shown_fleets:
		_shown_fleets = value.fleets.duplicate(true)
		_rebuild_ships()
	_owner_labels.visible = placement
	var marks: Dictionary = {"shots": value.shots, "targets": value.targets, "team": value.team}
	if marks != _shown_marks:
		_shown_marks = marks.duplicate(true)
		_rebuild_marks()

	var impact_time: float = 0.0
	for i: int in range(previous_shots, value.shots.size()):
		var shot: Dictionary = value.shots[i]
		if shot.hit:
			var burst: Node3D = ShellBurst.new()
			burst.position = _cell_position(1 - shot.by, shot.cell) + Vector3.UP * 0.20
			models.add_child(burst)
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
	_clear(_owner_labels)
	for board: int in range(2):
		for ship: Dictionary in _shown_fleets[board]:
			var holder: Node3D = Node3D.new()
			_ships.add_child(holder)
			holder.global_position = seas[board].to_global(Vector3(ship.x - 4.5, 0, ship.y - 4.5))
			holder.position += Vector3(0, 0, (ship.length - 1) * 0.5) if ship.vertical else Vector3((ship.length - 1) * 0.5, 0, 0)
			holder.rotation.y = -PI / 2.0 if ship.vertical else 0.0
			var owner_name: String = "我的" if board == _state.team and ship.index in _state.owned_ships else _names[ship.owner].left(6)
			var owner_label: Label3D = _text3d(owner_name, holder.position + Vector3(0, 1.4, 0), _owner_labels)
			owner_label.font_size = 20
			owner_label.width = 72.0
			owner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var scene: PackedScene = WRECKS[ship.index] if ship.sunk else MODELS[ship.index]
			var model: Node3D = scene.instantiate()
			holder.add_child(model)
			model.position.y = -0.06 if ship.sunk else 0.0
			var ring: MeshInstance3D = MeshInstance3D.new()
			var patch: PlaneMesh = PlaneMesh.new()
			var footprint: Vector2 = Vector2(ship.length - 0.22, 0.8)
			patch.size = footprint + Vector2.ONE
			ring.mesh = patch
			var material: ShaderMaterial = ShaderMaterial.new()
			material.shader = WATERLINE
			material.set_shader_parameter("footprint", footprint)
			material.set_shader_parameter("patch_size", patch.size)
			material.set_shader_parameter("phase", float(ship.index))
			material.set_shader_parameter("opacity", 0.32 if ship.sunk else 1.0)
			ring.material_override = material
			ring.position.y = -0.018
			holder.add_child(ring)

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
	_remaining = maxf(0.0, _remaining - delta)
	_clock.text = i18n.text(&"hud.clock", {"time": ceili(_remaining)}) if _state.phase != "finished" else ""
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
