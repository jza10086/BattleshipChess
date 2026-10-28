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
	var board: Rect2 = scene.enemy_rect if enemy else scene.own_rect
	await click(board.position + (Vector2(x,y)+Vector2.ONE*.5)*scene.cell)
func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Requires existing desktop display")
		quit(1)
		return
	output = OS.get_environment("BATTLE_CAPTURE_DIR")
	if output.is_empty():
		quit(1)
		return
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
	await board_click(1,1)
	check(scene.draft[0].x == 1, "click places carrier")
	await key(KEY_R)
	check(scene.vertical, "R rotates next ship")
	await board_click(7,2)
	await board_click(2,5)
	await click(scene.own_rect.position + Vector2(15,15), MOUSE_BUTTON_RIGHT)
	check(scene.vertical, "right button rotates")
	await board_click(0,6)
	await board_click(6,8)
	check(Rules.fleet_valid(scene.draft), "five ships valid through mouse and keys")
	# Pick and reposition an existing ship, then restore it through the same input path.
	await board_click(6,8)
	check(scene.selected == 4, "placed ship is selectable")
	await board_click(5,8)
	check(scene.draft[4].x == 5, "placed ship can be repositioned")
	await board_click(5,8)
	await board_click(6,8)
	await frames(20)
	await capture("battleship-placement")
	for dimensions in [Vector2i(720,960),Vector2i(640,480)]:
		root.size = dimensions
		await frames(12)
		check(scene.ready_button.position.y + scene.ready_button.size.y < root.size.y - 20, "placement actions fit " + str(dimensions))
		for i in range(4):
			check(scene.fleet_buttons[i].position.x + scene.fleet_buttons[i].size.x <= scene.fleet_buttons[i+1].position.x, "ship selector has no overlap " + str(i))
		await capture("battleship-placement-%dx%d" % [dimensions.x,dimensions.y])
	root.size = Vector2i(1280,720)
	await frames(10)
	await click(scene.ready_button.position + scene.ready_button.size/2)
	check(await until(func(): return scene.net.state.get("phase", "") == "battle"), "both ready starts battle")
	check(not scene.auto_button.visible and not scene.fleet_buttons[0].visible, "placement controls hidden in battle")
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
	check(scene.net.state.sunk_enemy.size() == 1, "sunk enemy ship publicly revealed")
	var before: int = scene.net.state.shots.size()
	await board_click(0,0,true)
	check(scene.net.state.shots.size() == before, "duplicate click cannot advance turn")
	for dimensions in [Vector2i(960,960),Vector2i(720,960),Vector2i(640,480)]:
		root.size = dimensions
		await frames(15)
		check(scene.enemy_rect.end.x <= root.size.x and scene.enemy_rect.end.y < root.size.y - 35, "boards fit " + str(dimensions))
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
	check(scene.draft[0].x == -1 and scene.net.state.shots.is_empty(), "new-round UI clears own placements and shots")
	scene.net.leave()
	check(await until(func(): return not OS.is_process_running(peer_pid)), "host exit ends separate client")
	# Repeat and cancel joining through the real entry controls.
	scene.port_field.value = 19778
	await click(scene.join_button.position + scene.join_button.size/2)
	check(scene.connecting and scene.host_button.text == "取消连接", "pending join exposes cancellation")
	await click(scene.host_button.position + scene.host_button.size/2)
	check(not scene.connecting and not scene.net.connected, "cancel pending join restores entry")
	await click(scene.join_button.position + scene.join_button.size/2)
	await key(KEY_ESCAPE)
	check(not scene.connecting and not scene.net.connected, "Escape cancels repeat join")
	print("NATIVE_UI_RESULT ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
