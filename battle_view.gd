extends Control
## Full-viewport sea and edge HUD. Receives only the host's filtered view, never hidden fleet state.
signal action_requested(action: Dictionary)
const YAMATO: int = 1
const YAMATO_WRECK: PackedScene = preload("res://games/minigame/godot_party_default_battleship_chess/assets/yamato/yamato_battleship_destroyed.glb")
const ShellBurst: Script = preload("res://games/minigame/godot_party_default_battleship_chess/shell_burst.gd")
const MODELS: Array[PackedScene] = [
	preload("res://games/minigame/godot_party_default_battleship_chess/assets/kenney-watercraft/ship-ocean-liner.glb"),
	preload("res://games/minigame/godot_party_default_battleship_chess/assets/yamato/yamato_battleship.glb"),
	preload("res://games/minigame/godot_party_default_battleship_chess/assets/kenney-watercraft/boat-tug-a.glb"),
	preload("res://games/minigame/godot_party_default_battleship_chess/assets/kenney-watercraft/boat-tug-b.glb"),
	preload("res://games/minigame/godot_party_default_battleship_chess/assets/kenney-watercraft/boat-speed-a.glb")]
const KENNEY_BOUNDS: Dictionary[int, Vector3] = {0: Vector3(4.76,8.934,21.28), 2: Vector3(1.785,2.237,3.47),
	3: Vector3(1.785,2.237,2.87), 4: Vector3(1.785,1.5,3.37)}
const FONT: Font = preload("res://games/minigame/godot_party_default_battleship_chess/assets/fonts/SeaInterface.otf")
const WATER: Shader = preload("res://games/minigame/godot_party_default_battleship_chess/assets/shaders/ocean.gdshader")
const WATERLINE: Shader = preload("res://games/minigame/godot_party_default_battleship_chess/assets/shaders/waterline.gdshader")
const FIELDS: Texture2D = preload("res://games/minigame/godot_party_default_battleship_chess/assets/textures/ocean_fields.png")
const CENTERS: Array[Vector3] = [Vector3(-6, 0, 0), Vector3(6, 0, 0)]
var world: WorldEnvironment
var sun: DirectionalLight3D
var models: Node3D
var camera: Camera3D
var _ships: Node3D
var _owner_labels: Node3D
var _marks: Node3D
var _aim: MeshInstance3D
var _status: Label
var _roster: Label
var _event: Label
var _clock: Label
var _hint: Label
var _placement: HBoxContainer
var _ship_choice: OptionButton
var _rotate: Button
var _shuffle: Button
var _ready_button: Button
var _switch: Button
var _rules: PanelContainer
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
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_world()
	_build_hud()

func _build_world() -> void:
	models = Node3D.new()
	add_child(models)
	world = WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("66aeb5")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("d2e4e2")
	world.environment.ambient_light_energy = 0.46
	models.add_child(world)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_color = Color("fff0d6")
	sun.light_energy = 0.72
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 55.0
	models.add_child(sun)
	var ocean: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(240, 240)
	ocean.mesh = plane
	ocean.position.y = -0.055
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = WATER
	material.set_shader_parameter("current_fields", FIELDS)
	ocean.material_override = material
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	models.add_child(ocean)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 55.0
	camera.current = true
	camera.position = Vector3(0, 12, 12)
	models.add_child(camera)
	camera.look_at(Vector3.ZERO)
	var grid: StandardMaterial3D = _material(Color(0.78, 0.96, 0.90, 0.32))
	for board: int in range(2):
		for index: int in range(11):
			_box(models, Vector3(0.022, 0.012, 10), CENTERS[board] + Vector3(index - 5, 0.02, 0), grid)
			_box(models, Vector3(10, 0.012, 0.022), CENTERS[board] + Vector3(0, 0.02, index - 5), grid)
		for index: int in range(10):
			_text3d(String.chr(65 + index), CENTERS[board] + Vector3(index - 4.5, 0.08, -5.45), models)
			_text3d(str(index + 1), CENTERS[board] + Vector3(-5.45, 0.08, index - 4.5), models)
		var title: Label3D = _text3d("蓝队海域" if board == 0 else "红队海域", CENTERS[board] + Vector3(0, 0.1, 5.7), models)
		title.font_size = 52
		title.modulate = Color("b7e6ff") if board == 0 else Color("ffb4a0")
	_ships = Node3D.new()
	models.add_child(_ships)
	_owner_labels = Node3D.new()
	models.add_child(_owner_labels)
	_marks = Node3D.new()
	models.add_child(_marks)
	_aim = _box(models, Vector3(0.94, 0.025, 0.94), Vector3.ZERO, _material(Color(1, 0.92, 0.5, 0.55)))
	_aim.hide()

func _material(color: Color) -> StandardMaterial3D:
	var value: StandardMaterial3D = StandardMaterial3D.new()
	value.albedo_color = color
	value.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	value.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return value

func _box(parent: Node3D, dimensions: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	node.mesh = mesh
	node.position = at
	node.material_override = material
	parent.add_child(node)
	return node

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

func _build_hud() -> void:
	var theme_value: Theme = Theme.new()
	theme_value.default_font = FONT
	theme_value.default_font_size = 24
	theme = theme_value
	var top: MarginContainer = MarginContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.add_theme_constant_override("margin_left", 32)
	top.add_theme_constant_override("margin_right", 32)
	top.add_theme_constant_override("margin_top", 22)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var columns: HBoxContainer = HBoxContainer.new()
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(columns)
	var lines: VBoxContainer = VBoxContainer.new()
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	columns.add_child(lines)
	_status = _label(lines, 30)
	_roster = _label(lines, 21)
	_roster.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_event = _label(lines, 23)
	_clock = _label(columns, 28)
	_clock.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_button(columns, "规则", func() -> void: _rules.visible = not _rules.visible)
	var bottom: MarginContainer = MarginContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.add_theme_constant_override("margin_left", 32)
	bottom.add_theme_constant_override("margin_right", 32)
	bottom.add_theme_constant_override("margin_bottom", 24)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)
	var actions: VBoxContainer = VBoxContainer.new()
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(actions)
	_placement = HBoxContainer.new()
	actions.add_child(_placement)
	_ship_choice = OptionButton.new()
	_ship_choice.item_selected.connect(func(index: int) -> void: _selected = _ship_choice.get_item_id(index))
	_placement.add_child(_ship_choice)
	_rotate = _button(_placement, "横向 / 纵向", func() -> void:
		_vertical = not _vertical
		_rotate.text = "纵向放置" if _vertical else "横向放置")
	_shuffle = _button(_placement, "随机摆放我的舰船", func() -> void: _send({"kind": "shuffle"}))
	_ready_button = _button(_placement, "我的布阵完成", func() -> void: _send({"kind": "ready"}))
	_switch = _button(_placement, "切换测试队伍", func() -> void: _send({"kind": "switch"}))
	_hint = _label(actions, 23)
	_rules = PanelContainer.new()
	_rules.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_rules.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_rules.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_rules)
	var rules_lines: VBoxContainer = VBoxContainer.new()
	_rules.add_child(rules_lines)
	var rules_text: Label = _label(rules_lines, 24)
	rules_text.text = "海战棋\n\n2–8 人随机分为蓝红两队，共用各队舰队。\n每队五艘舰船随机均分，每人只放置自己的舰船。\n选择舰船和朝向，点击己方格子布阵；全员确认或60秒后出航。\n轮到己方时点击敌方格子投票，每人一票，可在收齐前改投。\n收齐或超时后，按票数权重随机选一个目标；命中也轮换。\n无人投票则跳过。击沉全部敌舰获胜；整队离线判负。\n1 人测试由你交替操作两队，不添加机器人。\n\nEsc 打开派对菜单。"
	_button(rules_lines, "关闭", func() -> void: _rules.hide())
	_rules.hide()

func _label(parent: Node, font_size: int) -> Label:
	var label: Label = Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("fff4d9"))
	label.add_theme_color_override("font_outline_color", Color("173e48"))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

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
	_placement.visible = placement and team >= 0
	_switch.visible = value.solo
	var offered: Array[int] = []
	for index: int in range(_ship_choice.item_count):
		offered.append(_ship_choice.get_item_id(index))
	if offered != value.owned_ships:
		_ship_choice.clear()
		var ship_names: Array[String] = ["远洋轮 · 5格", "大和号战列舰 · 4格", "拖轮 · 3格", "工作艇 · 3格", "快艇 · 2格"]
		for index: int in value.owned_ships:
			_ship_choice.add_item(ship_names[index], index)
		if not value.owned_ships.is_empty():
			if _selected not in value.owned_ships:
				_selected = value.owned_ships[0]
			_ship_choice.select(_ship_choice.get_item_index(_selected))
	for button: BaseButton in [_ship_choice, _rotate, _shuffle, _ready_button]:
		button.disabled = team < 0 or value.placement_ready
	_ready_button.text = "已完成，等待队友" if value.placement_ready else "我的布阵完成"
	_event.text = ("布阵确认：蓝队 %d 人 · 红队 %d 人" % [value.ready_counts[0], value.ready_counts[1]]) if placement else ("蓝队" if value.turn == 0 else "红队") + "投票中 · %d / %d 人" % [value.voted, value.eligible]
	if value.phase == "finished":
		_event.text = "本局结束" if value.winner < 0 else ("蓝队" if value.winner == 0 else "红队") + "获胜"
	elif not value.last_event.is_empty():
		var event: Dictionary = value.last_event
		_event.text += "    上轮：" + ("无人投票，跳过" if event.cell < 0 else "%s %s" % [coordinate(event.cell), "击沉！" if event.sunk >= 0 else ("命中" if event.hit else "未命中")])
	_hint.text = "选择舰船和方向，点击己方格子放置 · Esc 菜单" if placement else "点击敌方格子投票 · 金色数字为票数 / 抽中概率 · Esc 菜单"
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
	var marks: Dictionary = {"shots": value.shots, "votes": value.votes, "turn": value.turn}
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
			holder.position = CENTERS[board] + Vector3(ship.x - 4.5, 0, ship.y - 4.5)
			holder.position += Vector3(0, 0, (ship.length - 1) * 0.5) if ship.vertical else Vector3((ship.length - 1) * 0.5, 0, 0)
			holder.rotation.y = -PI / 2.0 if ship.vertical else 0.0
			var owner_name: String = "我的" if board == _state.team and ship.index in _state.owned_ships else _names[ship.owner].left(6)
			var owner_label: Label3D = _text3d(owner_name, holder.position + Vector3(0, 1.4, 0), _owner_labels)
			owner_label.font_size = 20
			owner_label.width = 72.0
			owner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			var scene: PackedScene = MODELS[ship.index]
			if ship.index == YAMATO and ship.sunk:
				scene = YAMATO_WRECK
			var model: Node3D = scene.instantiate()
			holder.add_child(model)
			if ship.index == YAMATO:
				# Both exports share the same board-space origin, +X bow and waterline.
				model.position.y = -0.06 if ship.sunk else 0.0
			else:
				var bounds: Vector3 = KENNEY_BOUNDS[ship.index]
				model.scale = Vector3(0.92 / bounds.x, minf((ship.length - 0.18) / bounds.z, 0.53), (ship.length - 0.18) / bounds.z)
				model.rotation.y = PI / 2.0
				model.position.y = -0.52 if ship.sunk else -0.13
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
	return CENTERS[board] + Vector3(cell % 10 - 4.5, 0.07, cell / 10 - 4.5)

func _rebuild_marks() -> void:
	_clear(_marks)
	for shot: Dictionary in _state.shots:
		_box(_marks, Vector3(0.87, 0.028, 0.87), _cell_position(1 - shot.by, shot.cell),
			_material(Color(0.95, 0.2, 0.18, 0.75) if shot.hit else Color(0.15, 0.48, 0.95, 0.6)))
	var counts: Dictionary = {}
	for cell: int in _state.votes.values():
		counts[cell] = counts.get(cell, 0) + 1
	for cell: int in counts:
		var at: Vector3 = _cell_position(1 - _state.turn, cell)
		_box(_marks, Vector3(0.92, 0.03, 0.92), at, _material(Color(1.0, 0.81, 0.24, 0.7)))
		var label: Label3D = _text3d("%d票\n%d%%" % [counts[cell], roundi(100.0 * counts[cell] / _state.votes.size())], at + Vector3(0, 0.5, 0), _marks)
		label.font_size = 30

func _process(delta: float) -> void:
	if _state.is_empty():
		return
	_remaining = maxf(0.0, _remaining - delta)
	_clock.text = "%d 秒" % ceili(_remaining) if _state.phase != "finished" else ""
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
		var relative: Vector3 = intersection - CENTERS[board]
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
		elif _state.phase == "battle" and _state.team == _state.turn and _hover_team == 1 - _state.turn:
			_send({"kind": "vote", "cell": _hover})
		get_viewport().set_input_as_handled()

func _send(action: Dictionary) -> void:
	if not input_enabled or _state.is_empty():
		return
	action["turn"] = _state.turn_number
	action_requested.emit(action)
