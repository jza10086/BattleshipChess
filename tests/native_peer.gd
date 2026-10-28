extends SceneTree
## Automated second human's intentions for native QA, never used by normal play.
const Network = preload("res://scripts/network.gd")
var net
var last_count := -1
var started := 0
var turn_index := 0
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	started = Time.get_ticks_msec()
	var main := Node.new()
	main.name = "Main"
	root.add_child(main)
	net = Network.new()
	net.name = "Network"
	main.add_child(net)
	net.disconnected.connect(func(_m): quit())
	var port := int(OS.get_environment("BATTLE_NATIVE_PORT"))
	if port == 0: port = 19777
	if net.join("127.0.0.1", port) != OK:
		quit(1)
	process_frame.connect(step)
func fleet() -> Array:
	return [{"x":1,"y":1,"vertical":true},{"x":4,"y":1,"vertical":false},{"x":3,"y":5,"vertical":false},{"x":8,"y":4,"vertical":true},{"x":5,"y":8,"vertical":false}]
func step() -> void:
	if Time.get_ticks_msec() - started > 180000:
		quit(1)
	if not net.connected or net.state.is_empty(): return
	var state: Dictionary = net.state
	if state.phase == "placement" and not state.own_ready:
		net.ready_fleet(fleet())
	elif state.phase == "battle" and state.turn == 1 and state.shots.size() != last_count:
		last_count = state.shots.size()
		var targets := [Vector2i(1,1),Vector2i(2,1),Vector2i(4,4),Vector2i(3,1),Vector2i(9,9),Vector2i(6,6),Vector2i(4,1)]
		for y in range(10):
			for x in range(10):
				var candidate := Vector2i(x,y)
				if candidate not in targets and y != 1 and y != 5 and x != 0 and x != 7 and y != 8:
					targets.append(candidate)
		var p: Vector2i = targets[turn_index]
		turn_index += 1
		net.shoot(p.x,p.y)

	elif state.phase == "finished" and not state.rematch_votes[1]:
		net.vote_rematch()
