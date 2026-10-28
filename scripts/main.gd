extends Node2D
## Presentation only. Fleet submission and all fire requests go through the referee.
const NetworkModel = preload("res://scripts/network.gd")
const Rules = preload("res://scripts/rules.gd")
const FONT = preload("res://assets/fonts/SeaInterface.otf")
const INK := Color("092431")
const CREAM := Color("ede7d1")
const MUTED := Color("90b1b6")
const AQUA := Color("80d4c7")
const GOLD := Color("edc584")
const CORAL := Color("ec9578")
const LENGTHS := [5, 4, 3, 3, 2]
const NAMES := ["航母", "战列舰", "巡洋舰", "潜艇", "驱逐舰"]
var net = NetworkModel.new()
var draft: Array = []
var selected := 0
var vertical := false
var rng := RandomNumberGenerator.new()
var viewport_size := Vector2(1280, 720)
var own_rect := Rect2()
var enemy_rect := Rect2()
var cell := 42.0
var scale_ui := 1.0
var stacked := false
var time := 0.0
var effects: Array = []
var last_shots := 0
var last_round := -1
var toast := ""
var toast_time := 0.0
var menu_open := false
var connecting := false
var muted := false
var entry: Control
var in_game: Control
var pause_menu: Control
var address_field: LineEdit
var port_field: SpinBox
var host_button: Button
var join_button: Button
var status_label: Label
var auto_button: Button
var ready_button: Button
var rotate_button: Button
var rematch_button: Button
var leave_button: Button
var fleet_buttons: Array[Button] = []
var entry_nodes: Array[Control] = []
var ui: Control
var voice: AudioStreamPlayer
var sound_hit: AudioStreamWAV
var sound_miss: AudioStreamWAV
var sound_place: AudioStreamWAV

func _ready() -> void:
	rng.randomize()
	_empty_draft()
	net.name = "Network"
	add_child(net)
	net.changed.connect(_state_changed)
	net.notice.connect(_notice)
	net.disconnected.connect(_disconnected)
	_build_ui()
	_build_audio()
	_layout()

func _empty_draft() -> void:
	draft = []
	for i in range(5):
		draft.append({"x": -1, "y": -1, "vertical": false, "length": LENGTHS[i], "index": i})
	selected = 0
	vertical = false

func _build_ui() -> void:
	ui = Control.new()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	var theme := Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 16
	for kind in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = {"normal": Color("153c48"), "hover": Color("245664"), "pressed": Color("2d6570"), "disabled": Color("122e39"), "focus": Color(0,0,0,0)}[kind]
		style.set_corner_radius_all(6)
		style.content_margin_left = 14
		style.content_margin_right = 14
		style.border_color = AQUA if kind == "focus" else Color("42616a")
		style.set_border_width_all(2 if kind == "focus" else 1)
		theme.set_stylebox(kind, "Button", style)
	theme.set_color("font_color", "Button", CREAM)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", Color("65848d"))
	var field_style := StyleBoxFlat.new()
	field_style.bg_color = Color("0b2935")
	field_style.border_color = Color("4d737b")
	field_style.set_border_width_all(1)
	field_style.set_corner_radius_all(5)
	field_style.content_margin_left = 12
	theme.set_stylebox("normal", "LineEdit", field_style)
	theme.set_color("font_color", "LineEdit", CREAM)
	ui.theme = theme
	entry = Control.new()
	entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(entry)
	address_field = LineEdit.new()
	address_field.text = "127.0.0.1"
	address_field.placeholder_text = "房主 IP 地址"
	entry.add_child(address_field)
	port_field = SpinBox.new()
	port_field.min_value = 1024
	port_field.max_value = 65535
	port_field.value = 17777
	port_field.step = 1
	entry.add_child(port_field)
	host_button = _button(entry, "创建海域", _host)
	join_button = _button(entry, "加入海域", _join)
	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", CORAL)
	entry.add_child(status_label)
	in_game = Control.new()
	in_game.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(in_game)
	auto_button = _button(in_game, "随机布阵", _auto_place)
	rotate_button = _button(in_game, "旋转 · R", _rotate)
	ready_button = _button(in_game, "舰队就绪", _ready_fleet)
	rematch_button = _button(in_game, "再战一局", func(): net.vote_rematch())
	leave_button = _button(in_game, "菜单", _toggle_menu)
	for i in range(5):
		var b := _button(in_game, NAMES[i], _select_ship.bind(i))
		for kind in ["normal", "hover", "pressed", "disabled", "focus"]:
			var style: StyleBoxFlat = theme.get_stylebox(kind, "Button").duplicate()
			style.content_margin_left = 4
			style.content_margin_right = 4
			b.add_theme_stylebox_override(kind, style)
		fleet_buttons.append(b)
	pause_menu = Control.new()
	pause_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(pause_menu)
	_button(pause_menu, "继续航行", _toggle_menu)
	_button(pause_menu, "声音：开", _toggle_sound)
	_button(pause_menu, "离开海域", _leave)
	_sync_ui()

func _button(parent: Control, label: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func _layout() -> void:
	viewport_size = get_viewport_rect().size
	var w := viewport_size.x
	var h := viewport_size.y
	scale_ui = clampf(minf(w / 1280.0, h / 720.0), 0.65, 1.3)
	stacked = w < h * 1.12
	var s := scale_ui
	var board_size: float
	if stacked:
		board_size = floorf(minf(w - 100 * s, (h - 410 * s) / 2))
		own_rect = Rect2(Vector2((w - board_size) / 2, 166 * s), Vector2.ONE * board_size)
		enemy_rect = Rect2(Vector2((w - board_size) / 2, own_rect.end.y + 110 * s), Vector2.ONE * board_size)
	else:
		board_size = floorf(minf((w - 194 * s) / 2, h - 282 * s))
		var gap := clampf(w * 0.085, 70 * s, 150 * s)
		var start_x := (w - board_size * 2 - gap) / 2
		var start_y := 164 * s + maxf(0, (h - 720 * s) * 0.25)
		own_rect = Rect2(Vector2(start_x, start_y), Vector2.ONE * board_size)
		enemy_rect = Rect2(Vector2(start_x + board_size + gap, start_y), Vector2.ONE * board_size)
	cell = board_size / 10.0
	ui.size = viewport_size
	entry.size = viewport_size
	in_game.size = viewport_size
	pause_menu.size = viewport_size
	var ew := minf(480 * s, w - 48)
	var ex := (w - ew) / 2
	var ey := h * 0.53
	address_field.position = Vector2(ex, ey)
	address_field.size = Vector2(ew * .68 - 6 * s, 46 * s)
	port_field.position = Vector2(ex + ew * .68 + 6 * s, ey)
	port_field.size = Vector2(ew * .32 - 6 * s, 46 * s)
	host_button.position = Vector2(ex, ey + 65 * s)
	host_button.size = Vector2(ew / 2 - 7 * s, 50 * s)
	join_button.position = Vector2(ex + ew / 2 + 7 * s, ey + 65 * s)
	join_button.size = Vector2(ew / 2 - 7 * s, 50 * s)
	status_label.position = Vector2(0, ey + 126 * s)
	status_label.size = Vector2(w, 32 * s)
	leave_button.position = Vector2(w - 105 * s, 30 * s)
	leave_button.size = Vector2(72 * s, 34 * s)
	var by := enemy_rect.end.y + 38 * s
	var action_w := (enemy_rect.size.x - 16 * s) / 3
	for i in range(3):
		var b: Button = [auto_button, rotate_button, ready_button][i]
		b.position = Vector2(enemy_rect.position.x + i * (action_w + 8 * s), by)
		b.size = Vector2(action_w, 42 * s)
	rematch_button.position = Vector2(enemy_rect.get_center().x - 90 * s, by)
	rematch_button.size = Vector2(180 * s, 42 * s)
	var fy := own_rect.end.y + 35 * s
	if stacked:
		fy = own_rect.end.y + 8 * s
	var fw := (own_rect.size.x - 16 * s) / 5
	for i in range(5):
		fleet_buttons[i].position = Vector2(own_rect.position.x + i * (fw + 4 * s), fy)
		fleet_buttons[i].add_theme_font_size_override("font_size", maxi(11, int(13 * s)))
		fleet_buttons[i].text = NAMES[i] + ("" if fw < 70 else " · ") + str(LENGTHS[i])
		fleet_buttons[i].size = Vector2(fw, 42 * s if not stacked else 30 * s)
	for i in range(pause_menu.get_child_count()):
		var b: Button = pause_menu.get_child(i)
		b.position = Vector2(w / 2 - 110 * s, h / 2 - 30 * s + i * 60 * s)
		b.size = Vector2(220 * s, 45 * s)
	for node in [host_button, join_button, auto_button, rotate_button, ready_button, rematch_button, leave_button, address_field, port_field, status_label]:
		node.add_theme_font_size_override("font_size", maxi(12, int(16 * s)))

func _sync_ui() -> void:
	if entry == null:
		return
	entry.visible = not net.connected
	in_game.visible = net.connected
	pause_menu.visible = menu_open and net.connected
	var editing := _can_edit()
	for b in fleet_buttons:
		b.visible = editing and not menu_open
	auto_button.visible = editing and not menu_open
	rotate_button.visible = editing and not menu_open
	ready_button.visible = _phase() == "placement" and net.connected and not menu_open
	ready_button.disabled = not editing or not Rules.fleet_valid(draft)
	ready_button.text = "已就绪" if net.state.get("own_ready", false) else "舰队就绪"
	rematch_button.visible = _phase() == "finished" and not menu_open
	var votes: Array = net.state.get("rematch_votes", [false, false])
	var voted: bool = votes[_player()]
	rematch_button.disabled = voted
	rematch_button.text = "等待对方再战" if voted else "再战一局"
	leave_button.visible = not menu_open
	host_button.disabled = false
	host_button.text = "取消连接" if connecting else "创建海域"
	join_button.disabled = connecting
	for i in range(5):
		fleet_buttons[i].text = NAMES[i] + ("" if (own_rect.size.x - 16 * scale_ui) / 5 < 70 else " · ") + str(LENGTHS[i])
		fleet_buttons[i].modulate = AQUA if i == selected else (CREAM if draft[i].x >= 0 else MUTED)

func _process(delta: float) -> void:
	time += delta
	toast_time = maxf(0, toast_time - delta)
	for e in effects:
		e.age += delta
	effects = effects.filter(func(e): return e.age < 1.3)
	if get_viewport_rect().size != viewport_size:
		_layout()
	queue_redraw()

func _phase() -> String:
	return str(net.state.get("phase", "placement"))

func _player() -> int:
	return int(net.state.get("player", 0))

func _can_edit() -> bool:
	return net.connected and _phase() == "placement" and not net.state.get("own_ready", false)

func _state_changed(state: Dictionary) -> void:
	if state.is_empty():
		_sync_ui()
		return
	connecting = false
	status_label.text = ""
	var round_id := int(state.get("round", 0))
	if round_id != last_round:
		_empty_draft()
		last_round = round_id
		last_shots = 0
		effects.clear()
	if state.get("own_ready", false):
		draft = state.get("own_fleet", []).duplicate(true)
	var shots: Array = state.get("shots", [])
	if shots.size() > last_shots:
		for i in range(last_shots, shots.size()):
			var shot: Dictionary = shots[i]
			effects.append({"enemy": shot.by == _player(), "x": shot.x, "y": shot.y, "hit": shot.hit, "age": 0.0})
		var latest: Dictionary = shots.back()
		_play(sound_hit if latest.hit else sound_miss)
		var result: String = "击沉 " + NAMES[int(latest.sunk)] if int(latest.sunk) >= 0 else ("命中" if latest.hit else "未命中")
		_notice(("你" if latest.by == _player() else "对方") + " · " + _coordinate(latest.x, latest.y) + " · " + result)
	last_shots = shots.size()
	_sync_ui()

func _host() -> void:
	if connecting:
		_leave()
		return
	var result: int = net.host(int(port_field.value))
	if result != OK:
		status_label.text = "无法创建海域，请更换端口后重试"
	else:
		_sync_ui()

func _join() -> void:
	if address_field.text.strip_edges().is_empty():
		status_label.text = "请输入房主的 IP 地址"
		return
	connecting = true
	status_label.text = "正在寻找海域…"
	var result: int = net.join(address_field.text.strip_edges(), int(port_field.value))
	if result != OK:
		connecting = false
		status_label.text = "连接未能建立，请检查 IP 与端口"
	_sync_ui()

func _disconnected(message: String) -> void:
	connecting = false
	menu_open = false
	last_round = -1
	last_shots = 0
	_empty_draft()
	status_label.text = message
	_sync_ui()

func _notice(message: String) -> void:
	toast = message
	toast_time = 4.0
	if not net.connected and status_label != null:
		status_label.text = message

func _leave() -> void:
	net.leave()
	menu_open = false
	connecting = false
	last_round = -1
	last_shots = 0
	_empty_draft()
	status_label.text = ""
	_sync_ui()

func _toggle_menu() -> void:
	menu_open = not menu_open
	_sync_ui()

func _auto_place() -> void:
	if not _can_edit():
		return
	draft = Rules.auto_fleet(rng)
	selected = -1
	_play(sound_place)
	_sync_ui()

func _select_ship(index: int) -> void:
	if _can_edit():
		selected = index
		vertical = bool(draft[index].vertical)
		_sync_ui()

func _rotate() -> void:
	if _can_edit() and selected >= 0:
		vertical = not vertical
		_play(sound_place)

func _ready_fleet() -> void:
	if _can_edit() and Rules.fleet_valid(draft):
		net.ready_fleet(draft)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif event.keycode == KEY_ESCAPE:
			if connecting and not net.connected:
				_leave()
			elif net.connected:
				_toggle_menu()
		elif event.keycode == KEY_R and not menu_open:
			_rotate()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_5 and not menu_open:
			_select_ship(event.keycode - KEY_1)
	if menu_open or not net.connected:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_rotate()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var pos: Vector2 = event.position
			if _can_edit() and own_rect.has_point(pos):
				_place_at(_grid_cell(pos, own_rect))
			elif _phase() == "battle" and enemy_rect.has_point(pos):
				if int(net.state.get("turn", -1)) != _player():
					_notice("稍候，正在等待对方落子")
				else:
					var p := _grid_cell(pos, enemy_rect)
					net.shoot(p.x, p.y)

func _grid_cell(pos: Vector2, board: Rect2) -> Vector2i:
	return Vector2i(floori((pos.x - board.position.x) / cell), floori((pos.y - board.position.y) / cell))

func _candidate(pos: Vector2i) -> Dictionary:
	return {"x": pos.x, "y": pos.y, "vertical": vertical, "length": LENGTHS[selected], "index": selected}

func _placement_valid(ship: Dictionary, index: int) -> bool:
	for p in Rules.ship_cells(ship):
		if p.x < 0 or p.x >= 10 or p.y < 0 or p.y >= 10:
			return false
		for i in range(5):
			if i != index and draft[i].x >= 0 and p in Rules.ship_cells(draft[i]):
				return false
	return true

func _place_at(pos: Vector2i) -> void:
	# Click a placed vessel to pick it up without destroying its saved position.
	for i in range(5):
		if draft[i].x >= 0 and pos in Rules.ship_cells(draft[i]):
			if selected != i:
				_select_ship(i)
				return
	if selected < 0:
		return
	var ship := _candidate(pos)
	if not _placement_valid(ship, selected):
		_notice("此处无法停泊：舰船不能重叠或越界")
		return
	draft[selected] = ship
	selected = -1
	for i in range(5):
		if draft[i].x < 0:
			selected = i
			vertical = bool(draft[i].vertical)
			break
	_play(sound_place)
	_sync_ui()

func _coordinate(x: int, y: int) -> String:
	return String.chr(65 + x) + str(y + 1)

func _build_audio() -> void:
	voice = AudioStreamPlayer.new()
	voice.volume_db = -16
	add_child(voice)
	sound_place = _tone(330, .10, false)
	sound_miss = _tone(180, .30, true)
	sound_hit = _tone(75, .38, true)

func _tone(hz: float, duration: float, noise: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(int(duration * 22050) * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 912
	for i in range(data.size() / 2):
		var t := float(i) / 22050
		var envelope := pow(1.0 - t / duration, 2.0) * minf(t * 160, 1.0)
		var sample := sin(TAU * hz * t * (1.0 - t * .4))
		if noise:
			sample = sample * .45 + random.randf_range(-.45, .45)
		data.encode_s16(i * 2, int(sample * envelope * 14000))
	stream.data = data
	return stream

func _play(sound: AudioStreamWAV) -> void:
	if not muted and voice != null and sound != null:
		voice.stream = sound
		voice.play()

func _toggle_sound() -> void:
	muted = not muted
	pause_menu.get_child(1).text = "声音：关" if muted else "声音：开"

func _draw() -> void:
	_draw_ocean()
	if not net.connected:
		_draw_entry()
		return
	var s := scale_ui
	_text("海战棋", Vector2(38 * s, 58 * s), 29 * s, CREAM)
	_text("静 海 交 锋", Vector2(39 * s, 82 * s), 10 * s, MUTED)
	var phase_text := "部署舰队"
	var detail := "将五艘舰船藏入你的海域"
	var accent := AQUA
	if _phase() == "placement":
		if net.state.get("own_ready", false):
			phase_text = "舰队已就绪"
			detail = "等待对方部署完毕" if net.opponent_present else "等待另一位舰长加入"
		elif not net.opponent_present:
			detail = "你可以先布阵 · 等待另一位舰长加入"
	elif _phase() == "battle":
		var mine: bool = int(net.state.get("turn", -1)) == _player()
		phase_text = "轮到你了" if mine else "对方的回合"
		detail = "选择目标海域的一格，发起探测" if mine else "屏息等待，留意你的海域"
		accent = GOLD if mine else MUTED
	else:
		var won: bool = int(net.state.get("winner", -1)) == _player()
		phase_text = "海域由你掌握" if won else "舰队沉入静海"
		detail = "敌方舰队已全部击沉" if won else "胜负已定，再赴一场海上较量吧"
		accent = GOLD if won else CORAL
	_center_text(phase_text, Vector2(viewport_size.x / 2, 48 * s), 22 * s, accent)
	_center_text(detail, Vector2(viewport_size.x / 2, 77 * s), 12 * s, MUTED)
	var header_y := 98 * s
	draw_line(Vector2(38 * s, header_y), Vector2(viewport_size.x - 38 * s, header_y), Color(0.55,.77,.78,.14), 1.0)
	_draw_board(own_rect, false)
	_draw_board(enemy_rect, true)
	_draw_fleet()
	_draw_shots()
	_draw_hover()
	_draw_effects()
	if _phase() == "placement":
		if net.state.get("own_ready", false):
			_center_text("舰队已锁定 · 祝你好运，舰长", Vector2(own_rect.get_center().x, own_rect.end.y + (28 if stacked else 62) * s), 13 * s, AQUA)
		var ready_caption := "对方已就绪" if net.state.get("other_ready", false) else "敌舰隐于迷雾"
		_center_text(ready_caption, enemy_rect.get_center() + Vector2(0, -6 * s), 22 * s, Color(.64,.79,.79,.62))
		_center_text("双方就绪后，交替发起探测", enemy_rect.get_center() + Vector2(0, 25 * s), 12 * s, Color(.55,.71,.73,.7))
		_draw_compass(enemy_rect.get_center() + Vector2(0, -78 * s), 26 * s, Color(.50,.72,.74,.25))
	var bottom := viewport_size.y - 24 * s
	var tip := "单击停泊 / 移动舰船    R 或右键旋转    1–5 选择舰船"
	if _phase() == "battle":
		tip = "命中不连击 · 每次有效探测后交换回合"
	elif _phase() == "finished":
		tip = "双方同意再战后，重新部署舰队"
	if toast_time > 0:
		tip = toast
	_center_text(tip, Vector2(viewport_size.x / 2, bottom), 13 * s, CREAM if toast_time > 0 else MUTED)
	if menu_open:
		draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(.025,.08,.11,.94))
		_center_text("暂离片刻", Vector2(viewport_size.x / 2, viewport_size.y / 2 - 92 * s), 30 * s, CREAM)
		_center_text("联机对局仍在继续", Vector2(viewport_size.x / 2, viewport_size.y / 2 - 59 * s), 13 * s, MUTED)

func _draw_ocean() -> void:
	var w := viewport_size.x
	var h := viewport_size.y
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color("082531"))
	# Broad, translucent moving currents, drawn edge to edge rather than boxed art.
	for band in range(11):
		var points := PackedVector2Array()
		var y := float(band) * h / 8 - h * .12
		for x in range(-60, int(w) + 100, 35):
			points.append(Vector2(x, y + sin(float(x) / 310 + float(band) * .9 + time * .085) * 28 + float(x) * .045))
		draw_polyline(points, Color(.16,.39,.43,.12), 19 + float(band % 3) * 12, true)
	for i in range(64):
		var x := fmod(float(i * 197 + 47) + time * (2.0 + i % 3), w + 70) - 35
		var y := fmod(float(i * 131 + 19), h)
		var alpha := .06 + .025 * sin(time * .6 + i)
		draw_line(Vector2(x, y), Vector2(x + 12 + (i % 4) * 7, y - 2), Color(.66,.85,.81,alpha), 1, true)
	# Quiet depth contours at the margins.
	for i in range(5):
		draw_arc(Vector2(-w * .06, h * 1.08), h * (.32 + i * .033), -1.5, -.05, 60, Color(.33,.56,.58,.10), 1, true)
		draw_arc(Vector2(w * 1.06, -h * .12), h * (.39 + i * .04), 1.2, 2.9, 60, Color(.33,.56,.58,.08), 1, true)
	if not net.connected:
		_draw_compass(Vector2(w * .88, h * .80), 85 * scale_ui, Color(.40,.67,.70,.12))

func _draw_entry() -> void:
	var w := viewport_size.x
	var h := viewport_size.y
	var s := scale_ui
	var title_y := h * .28
	_center_text("B A T T L E S H I P", Vector2(w / 2, title_y - 55 * s), 13 * s, AQUA)
	_center_text("海 战 棋", Vector2(w / 2, title_y + 8 * s), 56 * s, CREAM)
	_center_text("静海之上，每一步都是交锋。", Vector2(w / 2, title_y + 57 * s), 17 * s, MUTED)
	var y := h * .53 - 16 * s
	_text("房主 IP", Vector2(w / 2 - minf(240 * s, (w - 48) / 2), y), 12 * s, MUTED)
	_text("UDP 端口", Vector2(w / 2 + 92 * s, y), 12 * s, MUTED)
	_center_text("两位舰长 · 五艘舰船 · 一片未知的海", Vector2(w / 2, h * .53 + 188 * s), 13 * s, MUTED)
	_center_text("同一局域网 / 直连 IP     F11 全屏", Vector2(w / 2, h - 36 * s), 12 * s, Color("668f99"))
	# Small original naval silhouette, with wake lines.
	var p := Vector2(w / 2, title_y - 100 * s)
	_draw_ship(Rect2(p - Vector2(45, 10) * s, Vector2(90,20) * s), 2, false, AQUA, .75)

func _draw_board(board: Rect2, enemy: bool) -> void:
	var s := scale_ui
	var title := "目标海域" if enemy else "我的海域"
	_text(title, board.position + Vector2(0, -40 * s), 20 * s, CREAM)
	var subtitle := "探测未知" if enemy else "守护舰队"
	if _phase() != "placement":
		var hits := 0
		var sunk_count := 0
		for shot in net.state.get("shots", []):
			if (int(shot.by) == _player()) == enemy:
				if shot.hit:
					hits += 1
				if int(shot.sunk) >= 0:
					sunk_count += 1
		subtitle = "%d / 5 击沉" % sunk_count if enemy else "%d / 17 舰体" % (17 - hits)
	_right_text(subtitle, board.position + Vector2(board.size.x, -40 * s), 12 * s, MUTED)
	draw_rect(board, Color(.055,.20,.25,.54) if not enemy else Color(.04,.145,.195,.68))
	# Subtle large-cell checker makes the coordinates easy to track.
	for y in range(10):
		for x in range(10):
			if (x + y) % 2 == 0:
				draw_rect(Rect2(board.position + Vector2(x, y) * cell, Vector2.ONE * cell), Color(.50,.73,.72,.025))
	for i in range(11):
		var line_color := Color(.42,.67,.69,.19)
		draw_line(board.position + Vector2(i * cell, 0), board.position + Vector2(i * cell, board.size.y), line_color, 1, true)
		draw_line(board.position + Vector2(0, i * cell), board.position + Vector2(board.size.x, i * cell), line_color, 1, true)
	for i in range(10):
		_center_text(String.chr(65 + i), board.position + Vector2((i + .5) * cell, -12 * s), 11 * s, MUTED)
		_right_text(str(i + 1), board.position + Vector2(-12 * s, (i + .5) * cell + 4 * s), 11 * s, MUTED)
	# Four open framing corners, not a software panel border.
	for corner in [Vector2(0,0), Vector2(1,0), Vector2(0,1), Vector2(1,1)]:
		var p: Vector2 = board.position + corner * board.size
		var dx: float = 1.0 if corner.x == 0 else -1.0
		var dy: float = 1.0 if corner.y == 0 else -1.0
		draw_line(p, p + Vector2(14 * s * dx, 0), Color("5d9298"), 2, true)
		draw_line(p, p + Vector2(0, 14 * s * dy), Color("5d9298"), 2, true)

func _draw_fleet() -> void:
	for i in range(draft.size()):
		var ship: Dictionary = draft[i]
		if int(ship.x) < 0:
			continue
		var ship_rect := _ship_rect(ship, own_rect)
		_draw_ship(ship_rect, i, bool(ship.vertical), CREAM, .9)
		if _can_edit() and selected == i:
			draw_rect(ship_rect.grow(2), Color(.5,.85,.78,.65), false, 1.5)
	var enemy_fleet: Array = net.state.get("enemy_fleet", []) if _phase() == "finished" else net.state.get("sunk_enemy", [])
	for ship in enemy_fleet:
		_draw_ship(_ship_rect(ship, enemy_rect), int(ship.get("index",0)), bool(ship.vertical), CORAL, .55)

func _ship_rect(ship: Dictionary, board: Rect2) -> Rect2:
	var length := int(ship.get("length", LENGTHS[int(ship.get("index",0))]))
	var size := Vector2(1, length) if bool(ship.vertical) else Vector2(length, 1)
	return Rect2(board.position + Vector2(ship.x, ship.y) * cell, size * cell)

func _draw_ship(area: Rect2, kind: int, is_vertical: bool, color: Color, opacity: float) -> void:
	var long_side: float = area.size.y if is_vertical else area.size.x
	var short_side: float = area.size.x if is_vertical else area.size.y
	var margin := short_side * .15
	var length := long_side - margin * 2
	var beam := short_side * .62
	var origin := area.get_center()
	var rotation := PI / 2 if is_vertical else 0.0
	draw_set_transform(origin + Vector2(2, 4), rotation)
	var hull := PackedVector2Array([Vector2(-length / 2, -beam * .28), Vector2(-length / 2 + beam * .24, -beam / 2), Vector2(length / 2 - beam * .66, -beam / 2), Vector2(length / 2, 0), Vector2(length / 2 - beam * .66, beam / 2), Vector2(-length / 2 + beam * .24, beam / 2), Vector2(-length / 2, beam * .28)])
	draw_colored_polygon(hull, Color(0,.055,.08,opacity * .55))
	draw_set_transform(origin, rotation)
	draw_colored_polygon(hull, Color(color, opacity))
	var edge := hull.duplicate()
	edge.append(hull[0])
	draw_polyline(edge, Color(color.lightened(.25), opacity), 1, true)
	var deck_color := Color("5b8085") if color != CORAL else Color("875d53")
	deck_color.a = opacity
	if kind == 0:
		draw_rect(Rect2(Vector2(-length * .40, -beam * .30), Vector2(length * .69, beam * .60)), deck_color)
		draw_line(Vector2(-length * .36, 0), Vector2(length * .29, 0), Color(color,opacity), 1, true)
		for dx in [-.20, .04, .26]:
			var x: float = dx * length
			draw_line(Vector2(x - 3, -3), Vector2(x + 3, 3), Color(color, opacity), 1, true)
			draw_line(Vector2(x - 3, 3), Vector2(x + 3, -3), Color(color, opacity), 1, true)
		draw_rect(Rect2(Vector2(-length * .15, -beam * .46), Vector2(length * .25, beam * .18)), Color("294956"))
	elif kind == 3:
		draw_style_box(_rounded_box(deck_color, int(beam * .25)), Rect2(Vector2(-length * .25, -beam * .22), Vector2(length * .45, beam * .44)))
		draw_line(Vector2(0, -beam * .2), Vector2(0, -beam * .45), Color("203e49"), 2)
	else:
		draw_rect(Rect2(Vector2(-length * .20, -beam * .28), Vector2(length * .38, beam * .56)), deck_color)
		draw_rect(Rect2(Vector2(-length * .07, -beam * .17), Vector2(length * .15, beam * .34)), Color("294956"))
		for dx in [-.34, .32]:
			var center := Vector2(dx * length, 0)
			draw_circle(center, beam * .18, deck_color)
			draw_line(center, center + Vector2(beam * .28, 0), Color("254650"), 2, true)
	draw_set_transform(Vector2.ZERO)

func _rounded_box(color: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	return box

func _draw_shots() -> void:
	var shots: Array = net.state.get("shots", [])
	for i in range(shots.size()):
		var shot: Dictionary = shots[i]
		var board := enemy_rect if int(shot.by) == _player() else own_rect
		var pos := board.position + (Vector2(shot.x, shot.y) + Vector2(.5,.5)) * cell
		if shot.hit:
			draw_rect(Rect2(pos - Vector2.ONE * cell * .45, Vector2.ONE * cell * .9), Color(.8,.32,.2,.15))
			draw_circle(pos, cell * .20, Color("3b4545"))
			draw_circle(pos, cell * .10, CORAL)
			var d := cell * .15
			draw_line(pos - Vector2(d,d), pos + Vector2(d,d), CORAL, 2, true)
			draw_line(pos - Vector2(d,-d), pos + Vector2(d,-d), CORAL, 2, true)
		else:
			draw_arc(pos, cell * .13, 0, TAU, 20, Color(.69,.83,.82,.73), 1.5, true)
			draw_circle(pos, cell * .035, Color(.74,.85,.83,.85))
		if i == shots.size() - 1:
			draw_arc(pos, cell * (.33 + sin(time * 2) * .025), 0, TAU, 32, Color(GOLD,.55), 1.2, true)

func _draw_hover() -> void:
	if menu_open:
		return
	var mouse := get_global_mouse_position()
	if _can_edit() and selected >= 0 and own_rect.has_point(mouse):
		var candidate := _candidate(_grid_cell(mouse, own_rect))
		var valid := _placement_valid(candidate, selected)
		var col := AQUA if valid else CORAL
		for pos in Rules.ship_cells(candidate):
			if pos.x >= 0 and pos.x < 10 and pos.y >= 0 and pos.y < 10:
				draw_rect(Rect2(own_rect.position + Vector2(pos) * cell + Vector2.ONE * 2, Vector2.ONE * (cell - 4)), Color(col, .22))
		if valid:
			_draw_ship(_ship_rect(candidate, own_rect), selected, vertical, col, .55)
	elif _phase() == "battle" and int(net.state.get("turn", -1)) == _player() and enemy_rect.has_point(mouse):
		var p := _grid_cell(mouse, enemy_rect)
		for shot in net.state.get("shots", []):
			if int(shot.by) == _player() and int(shot.x) == p.x and int(shot.y) == p.y:
				return
		var center := enemy_rect.position + (Vector2(p) + Vector2.ONE * .5) * cell
		draw_rect(Rect2(center - Vector2.ONE * cell * .5, Vector2.ONE * cell), Color(GOLD,.12))
		draw_arc(center, cell * .30, 0, TAU, 32, GOLD, 1.4, true)
		for dir in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
			draw_line(center + dir * cell * .18, center + dir * cell * .39, GOLD, 1, true)

func _draw_effects() -> void:
	for e in effects:
		var board: Rect2 = enemy_rect if e.enemy else own_rect
		var center := board.position + (Vector2(e.x,e.y) + Vector2.ONE * .5) * cell
		var age: float = e.age
		var color := CORAL if e.hit else AQUA
		color.a = maxf(0, 1.0 - age / 1.3) * .75
		draw_arc(center, cell * (.15 + age * .65), 0, TAU, 40, color, 2, true)
		color.a *= .45
		draw_arc(center, cell * (.05 + age * .45), 0, TAU, 40, color, 1, true)

func _draw_compass(center: Vector2, radius: float, color: Color) -> void:
	draw_arc(center, radius, 0, TAU, 64, color, 1, true)
	draw_arc(center, radius * .78, 0, TAU, 64, color, 1, true)
	for dir in [Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT]:
		draw_line(center + dir * radius * .45, center + dir * radius * 1.15, color, 1, true)
	draw_colored_polygon(PackedVector2Array([center + Vector2(0,-radius*.7), center + Vector2(radius*.15,0), center + Vector2(0,radius*.7), center - Vector2(radius*.15,0)]), color)

func _text(value: String, pos: Vector2, font_size: float, color: Color) -> void:
	draw_string(FONT, pos, value, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(10, int(font_size)), color)

func _center_text(value: String, pos: Vector2, font_size: float, color: Color) -> void:
	var size := maxi(10, int(font_size))
	var width := FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(FONT, pos - Vector2(width / 2, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _right_text(value: String, pos: Vector2, font_size: float, color: Color) -> void:
	var size := maxi(10, int(font_size))
	var width := FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(FONT, pos - Vector2(width, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
