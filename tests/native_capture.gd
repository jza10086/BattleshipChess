extends SceneTree
## Genuine native Godot + separate ENet peer. Automated intentions, no referee mutations.
const Rules = preload("res://scripts/rules.gd")
var scene
var peer_pid := -1
var failed := false
var output := ""
func _initialize() -> void:
	call_deferred("run")
func frames(count: int) -> void:
	for i in range(count): await process_frame
func check(ok: bool, label: String) -> void:
	print("NATIVE ", "PASS " if ok else "FAIL ", label)
	failed = failed or not ok
func until(predicate: Callable, duration := 10.0) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < duration * 1000:
		if predicate.call(): return true
		await process_frame
	return false
func capture(name: String) -> void:
	if name == "battleship-battle":
		print("NATIVE_RENDER_METRICS fps=", Engine.get_frames_per_second(), " process_ms=", Performance.get_monitor(Performance.TIME_PROCESS)*1000, " draw_calls=", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " primitives=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, "capture " + name)
func click(pos: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	Input.parse_input_event(motion)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = pos
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await frames(2)
func key(code: int) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await frames(2)
func board_click(x: int,y: int, enemy := false) -> void:
	await click(scene.cell_screen(x,y,enemy))
func drag_cell(from: Vector2i, to: Vector2i) -> void:
	var start: Vector2 = scene.cell_screen(from.x,from.y)
	var end: Vector2 = scene.cell_screen(to.x,to.y)
	var press := InputEventMouseButton.new()
	press.position = start
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await frames(3)
	var motion := InputEventMouseMotion.new()
	motion.position = end
	motion.relative = end-start
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await frames(5)
	var release := InputEventMouseButton.new()
	release.position = end
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await frames(5)
func check_boards_fit(dimensions: Vector2i) -> void:
	for enemy in [false,true]:
		for p in [Vector2i(0,0),Vector2i(9,0),Vector2i(0,9),Vector2i(9,9)]:
			var screen: Vector2 = scene.cell_screen(p.x,p.y,enemy)
			check(Rect2(Vector2.ZERO,Vector2(dimensions)).has_point(screen), "3D board corner fits " + str(dimensions))
			var pick: Dictionary = scene._board_pick(screen)
			check(not pick.is_empty() and pick.cell == p and pick.enemy == enemy, "3D projection ray-pick round trip")
func check_shot_markers() -> void:
	var shots: Array = scene.net.state.shots
	check(scene.shot_node.get_child_count() == shots.size(), "one flat marker per public shot")
	var planar := true
	var positioned := true
	var colors := true
	var own_hits := 0
	var enemy_hits := 0
	var misses := 0
	for i in range(mini(shots.size(),scene.shot_node.get_child_count())):
		var shot: Dictionary = shots[i]
		var mark: MeshInstance3D = scene.shot_node.get_child(i)
		var center: Vector3 = scene.enemy_center if shot.by == scene._player() else scene.own_center
		planar = planar and mark.mesh is PlaneMesh and mark.get_child_count() == 0 and mark.rotation.is_zero_approx() and mark.scale.is_equal_approx(Vector3.ONE)
		positioned = positioned and mark.position.is_equal_approx(center+Vector3(shot.x-4.5,.025,shot.y-4.5))
		colors = colors and mark.material_override.get_shader_parameter("mark_color") == (scene.SHOT_HIT if shot.hit else scene.SHOT_MISS) and mark.material_override.get_shader_parameter("hit") == shot.hit
		if not shot.hit: misses += 1
		elif shot.by == scene._player(): enemy_hits += 1
		else: own_hits += 1
	check(planar, "shot geometry is only horizontal planes, no arrows or vertical markers")
	check(positioned, "all shot markers stay centered on their grid cells at y=0.025")
	check(colors, "all misses blue and all own, enemy and sunk hits red")
	check(own_hits > 0 and enemy_hits > 0 and misses > 0, "capture covers own hits, enemy hits and misses")
	check("depth_test_disabled" in scene.SHOT_CELL_SHADER.code, "planar shot overlays remain readable through own hulls")
func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Requires existing desktop display")
		quit(1)
		return
	output = OS.get_environment("BATTLE_CAPTURE_DIR")
	if output.is_empty():
		quit(1)
		return
	get_tree_watchdog()
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,720)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await frames(10)
	await capture("battleship-entry")
	scene.port_field.value = 19777
	await click(scene.host_button.position + scene.host_button.size/2)
	check(scene.net.connected and scene.net.is_host, "create room button opens real host")
	OS.set_environment("BATTLE_NATIVE_PORT", "19777")
	peer_pid = OS.create_process(OS.get_executable_path(), ["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/native_peer.gd"])
	check(peer_pid > 0, "separate ENet client process")
	check(await until(func(): return scene.net.opponent_present), "client admitted")
	check(scene is Node3D and scene.camera is Camera3D, "actual Node3D camera scene")
	check(Rules.fleet_valid(scene.draft), "default fleet starts valid")
	check(scene.enemy_fleet_node.get_child_count() == 0, "no hidden enemy vessel meshes in scene")
	await key(KEY_1)
	check(scene.selected == 0, "keyboard selects first ship")
	check(not scene.ready_button.visible, "ready hidden while vessel preview selected")
	await board_click(1,1)
	check(scene.draft[0].y == 1, "projected-grid click relocates first vessel")
	await key(KEY_2)
	await key(KEY_R)
	check(not scene.vertical, "R rotates selected vessel")
	await click(scene.cell_screen(7,2), MOUSE_BUTTON_RIGHT)
	check(scene.vertical, "right button rotates selected vessel back")
	await board_click(7,2)
	await key(KEY_3)
	await board_click(2,5)
	await key(KEY_4)
	await click(scene.cell_screen(0,6), MOUSE_BUTTON_RIGHT)
	await board_click(0,6)
	await key(KEY_5)
	await board_click(6,8)
	check(Rules.fleet_valid(scene.draft), "five ships valid through projected clicks and keys")
	await drag_cell(Vector2i(6,8),Vector2i(5,8))
	check(scene.draft[4].x == 5, "direct drag moves placed vessel")
	await drag_cell(Vector2i(5,8),Vector2i(6,8))
	check(scene.draft[4].x == 6, "repeat drag repositions vessel")
	await key(KEY_5)
	await board_click(7,8)
	check(scene.draft[4].x == 7 and scene.selected == -1, "second click places across previous own footprint")
	await key(KEY_5)
	await board_click(6,8)
	check(scene.draft[4].x == 6, "click repositions vessel back")
	# Escape cancels a lifted preview without changing the authoritative draft.
	var before_cancel: Array = scene.draft.duplicate(true)
	await key(KEY_1)
	await key(KEY_R)
	await board_click(9,9)
	check(scene.draft == before_cancel and scene.selected == 0 and not scene.ready_button.visible, "invalid preview cannot replace draft or submit readiness")
	await key(KEY_ESCAPE)
	check(scene.selected == -1 and scene.draft == before_cancel, "Escape cancels lifted/rotated preview")
	check(scene.ready_button.visible, "Escape restores ready action for saved valid fleet")
	await frames(20)
	await capture("battleship-placement")
	for dimensions in [Vector2i(720,960),Vector2i(640,480)]:
		root.size = dimensions
		await frames(12)
		check(scene.ready_button.position.y + scene.ready_button.size.y < root.size.y - 20, "placement actions fit " + str(dimensions))
		check_boards_fit(dimensions)
		await capture("battleship-placement-%dx%d" % [dimensions.x,dimensions.y])
	root.size = Vector2i(1280,720)
	await frames(10)
	await click(scene.ready_button.position + scene.ready_button.size/2)
	check(await until(func(): return scene.net.state.get("phase", "") == "battle"), "both ready starts battle")
	check(not scene.ready_button.visible and not scene.auto_button.visible, "placement controls hidden in battle")
	check(scene.enemy_fleet_node.get_child_count() == 0, "enemy mesh remains hidden at battle start")
	var targets := [Vector2i(0,0),Vector2i(5,8),Vector2i(6,8),Vector2i(1,1),Vector2i(1,2),Vector2i(9,3),Vector2i(4,1)]
	for p in targets:
		check(await until(func(): return scene.net.state.turn == 0), "our turn arrives")
		var count: int = scene.net.state.shots.size()
		await board_click(p.x,p.y,true)
		check(await until(func(): return scene.net.state.shots.size() > count), "grid shot accepted")
		await frames(5)
	await until(func(): return scene.net.state.turn == 0)
	await frames(45)
	await capture("battleship-battle")
	check_shot_markers()
	check(scene.net.state.sunk_enemy.size() == 1, "sunk enemy ship publicly revealed")
	check(scene.enemy_fleet_node.get_child_count() == 1, "only sunk enemy vessel is instantiated")
	var before: int = scene.net.state.shots.size()
	await board_click(0,0,true)
	check(scene.net.state.shots.size() == before, "duplicate click cannot advance turn")
	for dimensions in [Vector2i(960,960),Vector2i(720,960),Vector2i(640,480)]:
		root.size = dimensions
		await frames(15)
		check_boards_fit(dimensions)
		await capture("battleship-battle-%dx%d" % [dimensions.x,dimensions.y])
	root.size = Vector2i(1280,720)
	await frames(10)
	await key(KEY_ESCAPE)
	check(scene.menu_open, "Escape opens minimal menu")
	await key(KEY_ESCAPE)
	check(not scene.menu_open, "Escape closes menu")
	await key(KEY_F11)
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "F11 full-screen")
	await key(KEY_F11)
	check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "F11 returns windowed")
	# Finish the same actual match using known test scenario targets, not referee edits.
	var target_fleet := [{"x":1,"y":1,"vertical":true,"length":5},{"x":4,"y":1,"vertical":false,"length":4},{"x":3,"y":5,"vertical":false,"length":3},{"x":8,"y":4,"vertical":true,"length":3},{"x":5,"y":8,"vertical":false,"length":2}]
	for ship in target_fleet:
		for p in Rules.ship_cells(ship):
			var already := false
			for shot in scene.net.state.shots:
				if shot.by == 0 and shot.x == p.x and shot.y == p.y: already = true
			if already: continue
			check(await until(func(): return scene.net.state.turn == 0), "victory sequence turn")
			await board_click(p.x,p.y,true)
	check(scene.net.state.phase == "finished" and scene.net.state.winner == 0, "native victory UI")
	await frames(12)
	await capture("battleship-victory")
	await click(scene.rematch_button.position + scene.rematch_button.size/2)
	check(await until(func(): return scene.net.state.phase == "placement"), "both rematch votes return to deployment")
	check(Rules.fleet_valid(scene.draft) and scene.net.state.shots.is_empty() and not scene.net.state.own_ready, "new-round UI resets editable fleet and clears shots")
	check(scene.enemy_fleet_node.get_child_count() == 0, "rematch removes revealed enemy vessel meshes")
	scene.net.leave()
	check(await until(func(): return not OS.is_process_running(peer_pid)), "host exit ends separate client")
	# Repeat and cancel joining through the real entry controls.
	scene.port_field.value = 19778
	await click(scene.join_button.position + scene.join_button.size/2)
	check(scene.connecting and scene.host_button.text == "取消", "pending join exposes cancellation")
	await click(scene.host_button.position + scene.host_button.size/2)
	check(not scene.connecting and not scene.net.connected, "cancel pending join restores entry")
	await click(scene.join_button.position + scene.join_button.size/2)
	await key(KEY_ESCAPE)
	check(not scene.connecting and not scene.net.connected, "Escape cancels repeat join")
	print("NATIVE_UI_RESULT ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)

func get_tree_watchdog() -> void:
	await create_timer(180).timeout
	if peer_pid > 0 and OS.is_process_running(peer_pid): OS.kill(peer_pid)
	push_error("NATIVE_UI_RESULT FAIL: 180-second deadline exceeded")
	quit(1)
