extends "res://tests/native_capture.gd"
## Focused ocean + marker + privacy regression, using a real separate ENet peer.
## Optional motion: --fixed-fps 20 and OCEAN_CAPTURE_MOTION=1 capture 120 native frames.
func waterline_count(node: Node) -> int:
	var result := 1 if str(node.name).begins_with("Waterline") else 0
	for child in node.get_children(): result += waterline_count(child)
	return result
func check_water() -> void:
	var ocean: MeshInstance3D = scene.get_node("Ocean")
	var shader: Shader = ocean.material_override.shader
	var ocean_names: Array = []
	for uniform in shader.get_shader_uniform_list(): ocean_names.append(str(uniform.name))
	check(ocean_names.size() == 5 and ocean_names.all(func(n): return n in ["current_fields","deep_color","sea_color","shoal_color","crest_color"]), "ocean uniform allowlist contains no fleet or position data")
	check(not "ALPHA" in shader.code and not "hint_depth_texture" in shader.code and not "hint_screen_texture" in shader.code, "opaque water has no screen/depth dependency")
	check(ocean.position.y + .013 < -.018 and -.018 < .010 and .018 < .025, "waves stay below waterline, fixed grid and shot planes")
	check(waterline_count(scene.own_fleet_node) == scene.own_fleet_node.get_child_count(), "one local waterline per visible own ship")
	check(waterline_count(scene.enemy_fleet_node) == scene.enemy_fleet_node.get_child_count(), "no waterline exists for uninstantiated enemy ships")
	check(waterline_count(scene.own_board) == 4 and waterline_count(scene.enemy_board) == 4, "only four visible corner buoy ripples per board")
	for fleet in [scene.own_fleet_node,scene.enemy_fleet_node]:
		for ship in fleet.get_children():
			var waterline: MeshInstance3D = ship.get_node("Waterline")
			check(is_equal_approx(waterline.global_position.y,-.018), "local waterline remains at sea height")
			var names: Array = []
			for uniform in waterline.material_override.shader.get_shader_uniform_list(): names.append(str(uniform.name))
			check(names.size() == 5 and names.all(func(n): return n in ["footprint","patch_size","phase","opacity","foam_color"]), "waterline uniform allowlist only describes its visible parent")
func record_motion() -> void:
	DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
	var first: Image
	var last: Image
	for i in range(120):
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		if i == 0: first = frame
		if i == 119: last = frame
		if frame.save_png(output.path_join("frames/frame-%03d.png" % i)) != OK:
			check(false,"motion frame save")
			return
	# The upper band is open water; exclude hull animation and all shot cells.
	var difference := 0.0
	for y in range(15,90,5):
		for x in range(20,1260,5):
			var a := first.get_pixel(x,y)
			var b := last.get_pixel(x,y)
			difference += absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)
	check(difference > 10.0, "open water pixels animate across 120 actual rendered frames")
	print("OCEAN_MOTION frames=120 fixed_step_fps=20 open_water_difference=",difference)

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
	await frames(8)
	scene.port_field.value = 19777
	await click(scene.host_button.position + scene.host_button.size/2)
	check(scene.net.connected and scene.net.is_host, "real native host")
	OS.set_environment("BATTLE_NATIVE_PORT", "19777")
	peer_pid = OS.create_process(OS.get_executable_path(), ["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/native_peer.gd"])
	check(await until(func(): return scene.net.opponent_present), "separate ENet peer admitted")
	await key(KEY_1)
	await board_click(1,1)
	check(Rules.fleet_valid(scene.draft) and scene.draft[0].y == 1, "own liner positioned by native grid input")
	await key(KEY_1)
	await frames(5)
	var lifted = scene.own_fleet_node.get_child(0)
	check(lifted.position.y > .05 and is_equal_approx(lifted.waterline.global_position.y,-.018), "lifted placement preview keeps contact effect on the sea")
	await key(KEY_ESCAPE)
	check(scene.selected == -1 and scene.draft[0].y == 1, "canceling preview preserves its saved cell")
	await capture("ocean-placement")
	await click(scene.ready_button.position + scene.ready_button.size/2)
	check(await until(func(): return scene.net.state.get("phase", "") == "battle"), "both ready starts battle")
	check(scene.enemy_fleet_node.get_child_count() == 0, "unknown enemy ships not instantiated")
	check_water()
	for p in [Vector2i(0,0),Vector2i(5,8),Vector2i(6,8),Vector2i(1,1),Vector2i(1,2),Vector2i(9,3),Vector2i(4,1)]:
		check(await until(func(): return scene.net.state.turn == 0), "our turn arrives")
		var count: int = scene.net.state.shots.size()
		await board_click(p.x,p.y,true)
		check(await until(func(): return scene.net.state.shots.size() > count), "grid shot accepted")
		await frames(3)
	await until(func(): return scene.net.state.turn == 0)
	await frames(15)
	check_shot_markers()
	check(scene.enemy_fleet_node.get_child_count() == 1 and scene.net.state.sunk_enemy.size() == 1, "only public sunk enemy vessel instantiated")
	var before: int = scene.net.state.shots.size()
	await board_click(0,0,true)
	check(scene.net.state.shots.size() == before, "duplicate remains rejected")
	var samples: Array[float] = []
	for i in range(32):
		await process_frame
		samples.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
	samples.sort()
	print("OCEAN_BENCH frames=32 median_ms=", samples[16], " min_ms=", samples[0], " max_ms=", samples[31], " fps=",Engine.get_frames_per_second()," calls=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," primitives=",Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	check_water()
	await capture("ocean-battle")
	if OS.get_environment("OCEAN_CAPTURE_MOTION") == "1": await record_motion()
	root.size = Vector2i(720,960)
	await frames(8)
	check_shot_markers()
	check_boards_fit(root.size)
	check_water()
	await capture("ocean-portrait")
	root.size = Vector2i(1280,720)
	await frames(4)
	scene._leave()
	await frames(3)
	check(waterline_count(scene.enemy_fleet_node) == 0 and not scene.enemy_board.visible, "leaving clears revealed hull waterlines and hides enemy buoy ripples")
	check(await until(func(): return not OS.is_process_running(peer_pid)), "host cleanup closes peer")
	print("OCEAN_CAPTURE_RESULT ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
