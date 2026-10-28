extends Node3D
## Presentation only. Requests still pass through the unchanged ENet referee.
const NetworkModel = preload("res://scripts/network.gd")
const Rules = preload("res://scripts/rules.gd")
const Vessel = preload("res://scripts/ship_visual.gd")
const FONT = preload("res://assets/fonts/SeaInterface.otf")
const BUOY = preload("res://assets/kenney-watercraft/buoy.glb")
const LENGTHS := [5,4,3,3,2]
const NAMES := ["远洋轮", "货轮", "拖轮", "工作艇", "快艇"]
const CREAM := Color("f1e8cd")
const INK := Color("254c55")
const AQUA := Color("9fe0cc")
const CORAL := Color("de7850")
var net = NetworkModel.new()
var draft: Array = []
var selected := -1
var vertical := false
var rng := RandomNumberGenerator.new()
var viewport_size := Vector2(1280,720)
var own_center := Vector3(-6.1,0,0)
var enemy_center := Vector3(6.1,0,0)
var stacked := false
var camera: Camera3D
var own_board: Node3D
var enemy_board: Node3D
var own_fleet_node: Node3D
var enemy_fleet_node: Node3D
var shot_node: Node3D
var effects_node: Node3D
var effects: Array = []
var known_sunk: Dictionary = {}
var hover_node: Node3D
var own_grid_material: StandardMaterial3D
var enemy_grid_material: StandardMaterial3D
var hover_material: StandardMaterial3D
var hover_cell := Vector2i(-1,-1)
var hovered_enemy := false
var pointer_position := Vector2.ZERO
var dragging := false
var drag_start := Vector2.ZERO
var drag_offset := Vector2i.ZERO
var candidate_cell := Vector2i(-1,-1)
var last_round := -1
var last_shots := 0
var menu_open := false
var connecting := false
var muted := false
var ui: Control
var entry: Control
var pause_menu: Control
var end_overlay: Control
var address_field: LineEdit
var port_field: SpinBox
var host_button: Button
var join_button: Button
var status_label: Label
var ready_button: Button
var rematch_button: Button
var auto_button: Button
var title: Label
var end_title: Label
var sound_button: Button
var voice: AudioStreamPlayer
var sound_hit: AudioStreamWAV
var sound_miss: AudioStreamWAV
var sound_place: AudioStreamWAV
var shot_pending := false
var shot_pending_at := 0
var hovered_ship := -1
var hover_signature := ""

func _ready() -> void:
	DisplayServer.window_set_title("海战棋")
	rng.randomize()
	_default_draft()
	net.name = "Network"
	add_child(net)
	net.changed.connect(_state_changed)
	net.notice.connect(_notice)
	net.disconnected.connect(_disconnected)
	_build_world()
	_build_ui()
	_build_audio()
	_layout()
	_rebuild_fleets()
	_sync_ui()

func _default_draft() -> void:
	draft = [{"x":1,"y":0,"vertical":false},{"x":5,"y":3,"vertical":true},{"x":1,"y":4,"vertical":false},{"x":1,"y":7,"vertical":false},{"x":7,"y":8,"vertical":false}]
	for i in range(5):
		draft[i]["length"] = LENGTHS[i]
		draft[i]["index"] = i
	selected = -1
	vertical = false
	dragging = false

func _build_world() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("66aeb5")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("d2e4e2")
	settings.ambient_light_energy = .46
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-35,0)
	sun.light_color = Color("fff0d6")
	sun.light_energy = .72
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 55
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.shadow_blur = 1.5
	sun.shadow_bias = .035
	add_child(sun)
	var ocean := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(240,240)
	plane.subdivide_width = 40
	plane.subdivide_depth = 40
	ocean.mesh = plane
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ocean_material := ShaderMaterial.new()
	ocean_material.shader = preload("res://assets/shaders/ocean.gdshader")
	ocean_material.set_shader_parameter("sea_color",Color("3c8791"))
	ocean.material_override = ocean_material
	ocean.position.y = -.055
	add_child(ocean)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = .1
	camera.far = 180
	camera.current = true
	add_child(camera)
	own_grid_material = _transparent_material(Color(.78,.96,.90,.25))
	enemy_grid_material = _transparent_material(Color(.78,.96,.90,.18))
	own_board = _board(own_grid_material)
	enemy_board = _board(enemy_grid_material)
	own_fleet_node = Node3D.new()
	enemy_fleet_node = Node3D.new()
	shot_node = Node3D.new()
	effects_node = Node3D.new()
	hover_node = Node3D.new()
	for node in [own_fleet_node,enemy_fleet_node,shot_node,effects_node,hover_node]: add_child(node)
	hover_material = _transparent_material(Color(.97,.89,.63,.60))

func _transparent_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	return mat

func _box(parent: Node3D, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	node.mesh = box
	node.position = pos
	node.material_override = material
	parent.add_child(node)
	return node

func _board(mat: StandardMaterial3D) -> Node3D:
	var board := Node3D.new()
	add_child(board)
	for i in range(11):
		_box(board, Vector3(.021,.008,10),Vector3(i-5,.014,0),mat).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_box(board, Vector3(10,.008,.021),Vector3(0,.014,i-5),mat).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for x in [-5.25,5.25]:
		for z in [-5.25,5.25]:
			var buoy: Node3D = BUOY.instantiate()
			board.add_child(buoy)
			buoy.scale = Vector3.ONE*.23
			buoy.position = Vector3(x,0,z)
	return board

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	ui = Control.new()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(ui)
	var theme := Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 16
	for kind in ["normal","hover","pressed","disabled","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = {"normal":Color("eee5cc"),"hover":Color("fff5db"),"pressed":Color("d6cfb7"),"disabled":Color("a1bbb4"),"focus":Color(0,0,0,0)}[kind]
		style.set_corner_radius_all(7)
		style.content_margin_left = 18
		style.content_margin_right = 18
		style.border_color = INK
		style.set_border_width_all(2 if kind == "focus" else 0)
		theme.set_stylebox(kind,"Button",style)
		theme.set_color("font_color","Button",INK)
		theme.set_color("font_hover_color","Button",INK)
		theme.set_color("font_pressed_color","Button",INK)
		theme.set_color("font_disabled_color","Button",Color("66837f"))
	var field := StyleBoxFlat.new()
	field.bg_color = Color(.95,.94,.86,.90)
	field.set_corner_radius_all(6)
	field.content_margin_left = 12
	theme.set_stylebox("normal","LineEdit",field)
	theme.set_color("font_color","LineEdit",INK)
	ui.theme = theme
	entry = Control.new()
	entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(entry)
	title = _label(entry,"海 战 棋",40)
	address_field = LineEdit.new()
	address_field.text = "127.0.0.1"
	address_field.placeholder_text = "房主 IP"
	entry.add_child(address_field)
	port_field = SpinBox.new()
	port_field.min_value = 1024
	port_field.max_value = 65535
	port_field.value = 17777
	entry.add_child(port_field)
	host_button = _button(entry,"创建",_host)
	join_button = _button(entry,"加入",_join)
	status_label = _label(entry,"",13)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ready_button = _button(ui,"出 航",_ready_fleet)
	pause_menu = Control.new()
	pause_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(pause_menu)
	var shade := ColorRect.new()
	shade.color = Color(.09,.22,.25,.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_menu.add_child(shade)
	_button(pause_menu,"继续",_toggle_menu)
	auto_button = _button(pause_menu,"重新布阵",_auto_place)
	sound_button = _button(pause_menu,"声音 · 开",_toggle_sound)
	_button(pause_menu,"离开",_leave)
	end_overlay = Control.new()
	end_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(end_overlay)
	end_title = _label(end_overlay,"",28)
	rematch_button = _button(end_overlay,"再来一局",func(): net.vote_rematch())

func _label(parent: Control, value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",INK)
	parent.add_child(label)
	return label

func _button(parent: Control, value: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = value
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func _layout() -> void:
	viewport_size = get_viewport().get_visible_rect().size
	var w := viewport_size.x
	var h := viewport_size.y
	stacked = w < h*1.10
	own_center = Vector3(0,0,6.2) if stacked else Vector3(-6.2,0,0)
	enemy_center = Vector3(0,0,-6.2) if stacked else Vector3(6.2,0,0)
	own_board.position = own_center
	enemy_board.position = enemy_center
	own_fleet_node.position = own_center
	enemy_fleet_node.position = enemy_center
	camera.position = Vector3(3,31,26) if not stacked else Vector3(2,30,24)
	camera.look_at(Vector3(0,.3,0))
	# Fit the true camera-space bounds, including the tallest model, at every aspect.
	var half_width := 0.0
	var half_height := 0.0
	for center in [own_center,enemy_center]:
		for x in [-5.9,5.9]:
			for z in [-5.9,5.9]:
				for y in [0.0,2.1]:
					var p: Vector3 = camera.global_transform.affine_inverse() * (center+Vector3(x,y,z))
					half_width = maxf(half_width,absf(p.x))
					half_height = maxf(half_height,absf(p.y))
	camera.size = maxf(half_height*2.0, half_width*2.0/(w/h))*1.06
	ui.size = viewport_size
	entry.size = viewport_size
	pause_menu.size = viewport_size
	end_overlay.size = viewport_size
	var ew := minf(330,w-40)
	var center_x := w*.75 if not stacked else w*.5
	var ey := h*.34 if not stacked else h*.13
	var ex := center_x-ew*.5
	title.position = Vector2(ex,ey-85)
	title.size = Vector2(ew,60)
	address_field.position = Vector2(ex,ey)
	address_field.size = Vector2(ew*.64-5,42)
	port_field.position = Vector2(ex+ew*.64+5,ey)
	port_field.size = Vector2(ew*.36-5,42)
	host_button.position = Vector2(ex,ey+54)
	host_button.size = Vector2(ew*.5-5,44)
	join_button.position = Vector2(ex+ew*.5+5,ey+54)
	join_button.size = Vector2(ew*.5-5,44)
	status_label.position = Vector2(ex-15,ey+110)
	status_label.size = Vector2(ew+30,55)
	ready_button.position = Vector2(w*.5-57,h-61)
	ready_button.size = Vector2(114,40)
	var buttons: Array = []
	for child in pause_menu.get_children():
		if child is Button: buttons.append(child)
	for i in range(buttons.size()):
		buttons[i].position = Vector2(w*.5-90,h*.5-108+i*55)
		buttons[i].size = Vector2(180,43)
	end_title.position = Vector2(w*.5-130,28)
	end_title.size = Vector2(260,50)
	rematch_button.position = Vector2(w*.5-65,h-65)
	rematch_button.size = Vector2(130,42)
	_rebuild_shots()

func _process(delta: float) -> void:
	for effect in effects:
		effect.age += delta
		effect.node.scale = Vector3.ONE*(1.0+effect.age*2.0)
		effect.material.albedo_color.a = maxf(0,.55*(1.0-effect.age))
		if effect.age>=1.0: effect.node.queue_free()
	effects = effects.filter(func(effect): return effect.age<1.0)
	for flame in shot_node.get_children():
		if flame.has_meta("flame"):
			flame.scale.y = 1.0+sin(Time.get_ticks_msec()*.006+flame.position.x)*.08
	if get_viewport().get_visible_rect().size != viewport_size: _layout()
	if shot_pending and Time.get_ticks_msec()-shot_pending_at > 2500: shot_pending = false
	_update_hover(delta)
	var active := _can_fire()
	var target := Color(.85,1.0,.91,.40) if active else Color(.67,.87,.84,.24)
	enemy_grid_material.albedo_color = enemy_grid_material.albedo_color.lerp(target,1.0-exp(-delta*4))
	own_grid_material.albedo_color = Color(.80,.97,.91,.29 if _can_edit() else .23)

func _phase() -> String: return str(net.state.get("phase","placement"))
func _player() -> int: return int(net.state.get("player",0))
func _can_edit() -> bool: return net.connected and _phase()=="placement" and not net.state.get("own_ready",false) and not menu_open
func _can_fire() -> bool: return net.connected and _phase()=="battle" and int(net.state.get("turn",-1))==_player() and not shot_pending and not menu_open

func _state_changed(state: Dictionary) -> void:
	if state.is_empty():
		_sync_ui()
		return
	connecting = false
	shot_pending = false
	status_label.text = ""
	var round_id := int(state.get("round",0))
	if round_id != last_round:
		_default_draft()
		last_round = round_id
		last_shots = 0
		known_sunk.clear()
		effects.clear()
		_clear(effects_node)
	if state.get("own_ready",false):
		draft = state.get("own_fleet",[]).duplicate(true)
		selected = -1
		dragging = false
	var shots: Array = state.get("shots",[])
	if shots.size()>last_shots:
		_play(sound_hit if shots.back().hit else sound_miss)
		for i in range(last_shots,shots.size()):
			var shot: Dictionary = shots[i]
			var center := enemy_center if int(shot.by)==_player() else own_center
			var ring := _ring(effects_node,center+Vector3(shot.x-4.5,.07,shot.y-4.5),.23,Color(.94,.96,.85,.55))
			effects.append({"node":ring,"material":ring.material_override,"age":0.0})
	last_shots = shots.size()
	_rebuild_fleets()
	_rebuild_shots()
	_sync_ui()

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _rebuild_fleets() -> void:
	if own_fleet_node == null: return
	_clear(own_fleet_node)
	_clear(enemy_fleet_node)
	for i in range(draft.size()):
		if int(draft[i].x)>=0: _add_ship(own_fleet_node,draft[i],i,false)
	if net.connected:
		var enemy: Array = net.state.get("enemy_fleet",[]) if _phase()=="finished" else net.state.get("sunk_enemy",[])
		for ship in enemy:
			_add_ship(enemy_fleet_node,ship,int(ship.get("index",LENGTHS.find(int(ship.get("length",2))))),true)

func _add_ship(parent: Node3D, ship: Dictionary, index: int, enemy: bool) -> void:
	if index<0 or index>4: return
	var node = Vessel.new()
	parent.add_child(node)
	node.setup(index,enemy)
	node.position = _ship_position(ship)
	node.rotation.y = -PI/2 if ship.vertical else 0.0
	node.set_meta("ship_index",index)
	if net.connected:
		var hit_count := 0
		for shot in net.state.get("shots",[]):
			if (int(shot.by)==_player()) == enemy and shot.hit and Vector2i(shot.x,shot.y) in Rules.ship_cells(ship): hit_count += 1
		node.sunk = hit_count>=LENGTHS[index]
		var key := str(enemy)+str(index)
		if node.sunk:
			if known_sunk.has(key): node.base_y = -.47
			known_sunk[key] = true

func _ship_position(ship: Dictionary) -> Vector3:
	var length: int = int(ship.get("length",LENGTHS[int(ship.get("index",0))]))
	return Vector3(float(ship.x)-4.5+(0 if ship.vertical else (length-1)*.5),0,float(ship.y)-4.5+((length-1)*.5 if ship.vertical else 0))

func _rebuild_shots() -> void:
	if shot_node == null: return
	_clear(shot_node)
	for shot in net.state.get("shots",[]):
		var center := enemy_center if int(shot.by)==_player() else own_center
		var pos := center+Vector3(shot.x-4.5,.055,shot.y-4.5)
		if shot.hit:
			var elevation := _hit_elevation(shot)
			# A small geometric ember stays readable over the ship; no particle shower or text.
			var flame := MeshInstance3D.new()
			var mesh := PrismMesh.new()
			mesh.size = Vector3(.24,.55,.24)
			flame.mesh = mesh
			flame.material_override = Vessel.material(CORAL)
			flame.position = pos+Vector3(0,elevation,0)
			flame.set_meta("flame",true)
			shot_node.add_child(flame)
			var ember := _box(shot_node,Vector3(.19,.13,.19),pos+Vector3(0,elevation-.24,0),Vessel.material(Color("f5c56f")))
			ember.rotation.y = PI*.25
		else:
			_ring(shot_node,pos,.18,Color(.86,.96,.89,.80))

func _hit_elevation(shot: Dictionary) -> float:
	# Tall glTF decks must never occlude the only visible hit feedback.
	var enemy: bool = int(shot.by)==_player()
	var visible_fleet: Array = draft
	if enemy:
		visible_fleet = net.state.get("enemy_fleet",[]) if _phase()=="finished" else net.state.get("sunk_enemy",[])
	for ship in visible_fleet:
		if Vector2i(shot.x,shot.y) not in Rules.ship_cells(ship): continue
		var index: int = int(ship.get("index",0))
		var bounds: Vector3 = Vessel.BOUNDS[index]
		var top := bounds.y*minf((LENGTHS[index]-.18)/bounds.z,.53)-.13
		if known_sunk.has(str(enemy)+str(index)): top -= .47
		return maxf(.63,top+.28)
	return .63

func _ring(parent: Node3D, pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius-.018
	mesh.outer_radius = radius+.018
	mesh.rings = 20
	mesh.ring_segments = 6
	node.mesh = mesh
	node.material_override = _transparent_material(color)
	node.position = pos
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func _sync_ui() -> void:
	if entry==null: return
	entry.visible = not net.connected
	enemy_board.visible = net.connected
	pause_menu.visible = menu_open and net.connected
	ready_button.visible = _can_edit() and Rules.fleet_valid(draft) and not dragging and selected<0
	end_overlay.visible = net.connected and _phase()=="finished" and not menu_open
	end_title.text = "胜 利" if int(net.state.get("winner",-1))==_player() else "下 次 再 会"
	var votes: Array = net.state.get("rematch_votes",[false,false])
	rematch_button.visible = not votes[_player()]
	auto_button.visible = _can_edit() or (menu_open and _phase()=="placement" and not net.state.get("own_ready",false))
	host_button.text = "取消" if connecting else "创建"
	join_button.disabled = connecting

func _board_pick(screen: Vector2) -> Dictionary:
	# Ray-plane intersection is independent of pixel scale and frame rate.
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var hit = Plane(Vector3.UP,0).intersects_ray(origin,direction)
	if hit == null: return {}
	for enemy in [false,true]:
		var center := enemy_center if enemy else own_center
		var local: Vector3 = hit-center
		var p := Vector2i(floori(local.x+5),floori(local.z+5))
		if p.x>=0 and p.x<10 and p.y>=0 and p.y<10: return {"enemy":enemy,"cell":p,"world":hit}
	return {}

func cell_screen(x: int, y: int, enemy := false) -> Vector2:
	return camera.unproject_position((enemy_center if enemy else own_center)+Vector3(x-4.5,0,y-4.5))

func _ship_at(p: Vector2i) -> int:
	for i in range(draft.size()):
		if draft[i].x>=0 and p in Rules.ship_cells(draft[i]): return i
	return -1

func _shot_at(p: Vector2i) -> bool:
	for shot in net.state.get("shots",[]):
		if shot.by==_player() and shot.x==p.x and shot.y==p.y: return true
	return false

func _ship_pick(screen: Vector2) -> int:
	var origin := camera.project_ray_origin(screen)
	var ray := PhysicsRayQueryParameters3D.create(origin, origin+camera.project_ray_normal(screen)*160,1)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		var vessel: Node = hit.collider.get_parent()
		if vessel.get_parent()==own_fleet_node: return int(vessel.get_meta("ship_index",-1))
	return -1

func _restore_preview() -> void:
	for vessel in own_fleet_node.get_children():
		var index: int = vessel.get_meta("ship_index",0)
		vessel.position = _ship_position(draft[index])
		vessel.rotation.y = -PI/2 if draft[index].vertical else 0.0

func _update_hover(delta: float) -> void:
	var pick := _board_pick(pointer_position)
	if selected>=0 and not pick.is_empty() and not pick.enemy and _can_edit():
		candidate_cell = pick.cell-drag_offset
		for vessel in own_fleet_node.get_children():
			if int(vessel.get_meta("ship_index",-1))==selected:
				vessel.position = vessel.position.lerp(_ship_position(_candidate(candidate_cell))+Vector3(0,.25,0),1.0-exp(-delta*20))
				vessel.rotation.y = lerp_angle(vessel.rotation.y,-PI/2 if vertical else 0.0,1.0-exp(-delta*20))
	var model_pick := _ship_pick(pointer_position) if _can_edit() and selected<0 else -1
	var signature := str(pick.get("cell",Vector2i(-1,-1)))+str(pick.get("enemy",false))+str(selected)+str(vertical)+str(menu_open)+str(_can_fire())+str(model_pick)+str(net.connected)
	if signature==hover_signature: return
	hover_signature = signature
	_clear(hover_node)
	if menu_open or not net.connected:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		return
	var cursor := Input.CURSOR_ARROW
	if not pick.is_empty():
		var p: Vector2i = pick.cell
		if not pick.enemy and _can_edit():
			hovered_ship = model_pick if model_pick>=0 else _ship_at(p)
			if selected>=0:
				candidate_cell = p-drag_offset
				var ship := _candidate(candidate_cell)
				var good := _placement_valid(ship,selected)
				var color := Color(.97,.88,.56,.46) if good else Color(.91,.40,.28,.50)
				for cell in Rules.ship_cells(ship):
					if cell.x>=0 and cell.x<10 and cell.y>=0 and cell.y<10:
						_box(hover_node,Vector3(.95,.015,.95),own_center+Vector3(cell.x-4.5,.04,cell.y-4.5),_transparent_material(color)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				cursor = Input.CURSOR_DRAG if good else Input.CURSOR_FORBIDDEN
			elif hovered_ship>=0:
				cursor = Input.CURSOR_POINTING_HAND
				for cell in Rules.ship_cells(draft[hovered_ship]):
					_ring(hover_node,own_center+Vector3(cell.x-4.5,.05,cell.y-4.5),.35,Color(1,.93,.74,.55))
		elif pick.enemy and _can_fire() and not _shot_at(p):
			cursor = Input.CURSOR_CROSS
			_ring(hover_node,enemy_center+Vector3(p.x-4.5,.05,p.y-4.5),.36,Color(1,.94,.71,.90))
	Input.set_default_cursor_shape(cursor)

func _candidate(pos: Vector2i) -> Dictionary:
	return {"x":pos.x,"y":pos.y,"vertical":vertical,"length":LENGTHS[selected],"index":selected}
func _placement_valid(ship: Dictionary, index: int) -> bool:
	for p in Rules.ship_cells(ship):
		if p.x<0 or p.x>=10 or p.y<0 or p.y>=10: return false
		for i in range(5):
			if i!=index and draft[i].x>=0 and p in Rules.ship_cells(draft[i]): return false
	return true
func _select_ship(index: int) -> void:
	if not _can_edit(): return
	_restore_preview()
	selected = index
	vertical = bool(draft[index].vertical)
	drag_offset = Vector2i.ZERO
	_sync_ui()
func _place_at(pos: Vector2i) -> void:
	if selected<0 or not _can_edit(): return
	var ship := _candidate(pos)
	if not _placement_valid(ship,selected): return
	draft[selected] = ship
	selected = -1
	drag_offset = Vector2i.ZERO
	_play(sound_place)
	_rebuild_fleets()
	_sync_ui()
func _rotate() -> void:
	if _can_edit() and selected>=0:
		vertical = not vertical
		drag_offset = Vector2i.ZERO
		_play(sound_place)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		pointer_position = event.position
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_F11:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif event.keycode==KEY_ESCAPE:
			if connecting and not net.connected: _leave()
			elif selected>=0:
				_restore_preview()
				selected = -1
				dragging = false
				_sync_ui()
			elif net.connected: _toggle_menu()
		elif event.keycode==KEY_R: _rotate()
		elif event.keycode>=KEY_1 and event.keycode<=KEY_5: _select_ship(event.keycode-KEY_1)
	if menu_open or not net.connected: return
	if event is InputEventMouseButton:
		pointer_position = event.position
		if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
			_rotate()
			return
		if event.button_index!=MOUSE_BUTTON_LEFT: return
		var pick := _board_pick(event.position)
		if not event.pressed:
			if dragging:
				dragging = false
				if event.position.distance_to(drag_start)>8 and not pick.is_empty() and not pick.enemy:
					_place_at(pick.cell-drag_offset)
				_sync_ui()
			return
		var hit_ship := _ship_pick(event.position) if _can_edit() else -1
		if hit_ship>=0 and selected<0:
			_select_ship(hit_ship)
			drag_offset = Vector2i.ZERO
			if not pick.is_empty() and not pick.enemy and pick.cell in Rules.ship_cells(draft[hit_ship]):
				drag_offset = pick.cell-Vector2i(draft[hit_ship].x,draft[hit_ship].y)
			drag_start = event.position
			dragging = true
			_sync_ui()
			return
		if pick.is_empty(): return
		if not pick.enemy and _can_edit():
			var index := _ship_at(pick.cell)
			if selected>=0:
				_place_at(pick.cell)
			elif index>=0:
				_select_ship(index)
				drag_offset = pick.cell-Vector2i(draft[index].x,draft[index].y)
				drag_start = event.position
				dragging = true
				_sync_ui()
		elif pick.enemy and _can_fire() and not _shot_at(pick.cell):
			shot_pending = true
			shot_pending_at = Time.get_ticks_msec()
			net.shoot(pick.cell.x,pick.cell.y)

func _host() -> void:
	if connecting:
		_leave()
		return
	if net.host(int(port_field.value))!=OK: status_label.text = "端口不可用"
	_sync_ui()
func _join() -> void:
	if address_field.text.strip_edges().is_empty():
		status_label.text = "请输入房主 IP"
		return
	connecting = true
	status_label.text = "连接中…"
	if net.join(address_field.text.strip_edges(),int(port_field.value))!=OK:
		connecting = false
		status_label.text = "无法连接"
	_sync_ui()
func _notice(message: String) -> void:
	if not net.connected and status_label!=null: status_label.text = message
func _disconnected(message: String) -> void:
	connecting = false
	menu_open = false
	last_round = -1
	last_shots = 0
	known_sunk.clear()
	effects.clear()
	_clear(effects_node)
	_default_draft()
	status_label.text = message
	_rebuild_fleets()
	_rebuild_shots()
	_sync_ui()
func _leave() -> void:
	net.leave()
	_disconnected("")
func _toggle_menu() -> void:
	menu_open = not menu_open
	_sync_ui()
func _auto_place() -> void:
	if _phase()!="placement" or net.state.get("own_ready",false): return
	draft = Rules.auto_fleet(rng)
	selected = -1
	menu_open = false
	_rebuild_fleets()
	_sync_ui()
func _ready_fleet() -> void:
	if _can_edit() and Rules.fleet_valid(draft):
		selected = -1
		net.ready_fleet(draft)

func _build_audio() -> void:
	voice = AudioStreamPlayer.new()
	voice.volume_db = -21
	add_child(voice)
	sound_place = _tone(330,.10,false)
	sound_miss = _tone(180,.30,true)
	sound_hit = _tone(75,.38,true)
func _tone(hz: float, duration: float, noise: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(int(duration*22050)*2)
	var random := RandomNumberGenerator.new()
	random.seed = 912
	for i in range(data.size()/2):
		var t := float(i)/22050
		var envelope := pow(1-t/duration,2)*minf(t*160,1)
		var sample := sin(TAU*hz*t*(1-t*.4))
		if noise: sample = sample*.45+random.randf_range(-.45,.45)
		data.encode_s16(i*2,int(sample*envelope*14000))
	stream.data = data
	return stream
func _play(sound: AudioStreamWAV) -> void:
	if not muted and voice!=null and sound!=null:
		voice.stream = sound
		voice.play()
func _toggle_sound() -> void:
	muted = not muted
	sound_button.text = "声音 · 关" if muted else "声音 · 开"
