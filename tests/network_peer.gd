extends SceneTree
## Real ENet process integration. Only player intentions are automated; no fixture mutation.
const Network = preload("res://scripts/network.gd")
const Rules = preload("res://scripts/rules.gd")
const LENGTHS := [5, 4, 3, 3, 2]
var net
var role := "client"
var scenario := "match"
var address := "127.0.0.1"
var room_port := 18777
var out_dir := "/tmp/battleship-network"
var checks := 0
var failures := 0
var started := 0
var phase := 0
var phase_at := 0
var last_send_at := 0
var last_sent_count := -1
var snapshots := 0
var finished := false
var disconnect_message := ""
var seen_battle := false
var seen_finish := false
var saw_sunk := false
var initial_round := 0
var last_snapshot_key := ""
var seen_keys := {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair.size() != 2: continue
		match pair[0]:
			"role": role = pair[1]
			"scenario": scenario = pair[1]
			"address": address = pair[1]
			"port": room_port = int(pair[1])
			"out": out_dir = pair[1]
	call_deferred("setup")

func setup() -> void:
	started = Time.get_ticks_msec()
	net = Network.new()
	root.add_child(net)
	net.changed.connect(on_snapshot)
	net.disconnected.connect(func(message: String): disconnect_message = message)
	process_frame.connect(step)
	var err: int = net.host(room_port) if role == "host" else net.join(address, room_port)
	check(err == OK, "transport started")
	if err != OK: finish()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", description)
	else: print("PASS: ", description)

func fleet(kind := -1) -> Array:
	var vertical: bool = role != "host" if kind == -1 else bool(kind)
	var result: Array = []
	for i in range(5):
		result.append({"x": i * 2 if vertical else 0, "y": 0 if vertical else i * 2, "vertical": vertical, "length": LENGTHS[i]})
	return result

func targets() -> Array:
	var result: Array = []
	for ship in fleet(1): result.append_array(Rules.ship_cells(ship))
	return result

func marker(name: String, content := "done") -> void:
	var file := FileAccess.open(out_dir.path_join(name), FileAccess.WRITE)
	if file: file.store_string(content)

func has_marker(name: String) -> bool:
	return FileAccess.file_exists(out_dir.path_join(name))

func stage() -> String:
	var file := FileAccess.open(out_dir.path_join("stage.txt"), FileAccess.READ)
	return file.get_as_text() if file else ""

func set_stage(value: String) -> void:
	marker("stage.txt", value)
	print("STAGE ", value)

func finish() -> void:
	if finished: return
	finished = true
	print("NETWORK_PEER_RESULT role=%s scenario=%s checks=%d failures=%d snapshots=%d" % [role, scenario, checks, failures, snapshots])
	marker(role + ".done", "pass" if failures == 0 else "fail")
	quit(1 if failures else 0)

func on_snapshot(state: Dictionary) -> void:
	if state.is_empty(): return
	snapshots += 1
	var key := "%d:%s:%d:%s:%s" % [state.round, state.phase, state.shots.size(), state.own_ready, state.other_ready]
	if not seen_keys.has(key):
		seen_keys[key] = true
		# Inspect the actual state handed to this process by production networking.
		var allowed := ["phase", "player", "own_fleet", "own_ready", "other_ready", "turn", "winner", "round", "shots", "sunk_enemy", "rematch_votes", "opponent_present"]
		if state.phase == "finished": allowed.append("enemy_fleet")
		for field in state:
			check(field in allowed, "snapshot key permitted: " + str(field))
		check(state.player == (0 if role == "host" else 1), "private state assigned to correct player")
		if state.own_ready:
			check(state.own_fleet.size() == 5, "private ready fleet has exactly five ships")
			for i in range(state.own_fleet.size()):
				var expected: Dictionary = fleet()[i]
				var received: Dictionary = state.own_fleet[i]
				check(received.x == expected.x and received.y == expected.y and received.vertical == expected.vertical and received.length == expected.length, "own fleet is recipient's distinct layout")
		if state.phase != "finished":
			check(not state.has("enemy_fleet"), "unhit enemy fleet absent before gameover")
		for ship in state.sunk_enemy:
			for cell in Rules.ship_cells(ship):
				var public_hit := false
				for shot in state.shots:
					if shot.by == state.player and shot.hit and shot.x == cell.x and shot.y == cell.y: public_hit = true
				check(public_hit, "disclosed sunk cell was already hit")
		if state.phase == "battle": seen_battle = true
		if state.phase == "finished": seen_finish = true
		if not state.sunk_enemy.is_empty(): saw_sunk = true
		if initial_round == 0: initial_round = state.round
		# Canonical public state is compared across peers by the Python runner.
		var public := {"round": state.round, "phase": state.phase, "turn": state.turn, "winner": state.winner, "shots": state.shots}
		print("PUBLIC_SNAPSHOT ", JSON.stringify(public))

func step() -> void:
	if finished: return
	var now := Time.get_ticks_msec()
	if now - started > 26000:
		check(false, "bounded integration timed out at phase%d stage%s" % [phase, stage()])
		finish()
		return
	if role.begins_with("reject"):
		if not disconnect_message.is_empty():
			check(not net.connected and net.state.is_empty(), "rejected peer receives no private state")
			check(snapshots == 0, "rejected peer never received any snapshot")
			check("房间已满" in disconnect_message, "explicit room-full rejection")
			finish()
		return
	if scenario == "disconnect":
		disconnect_step(now)
	elif role == "host": host_step(now)
	else: client_step(now)

func host_step(now: int) -> void:
	if phase == 0 and net.opponent_present:
		check(net.state.phase == "placement", "two-peer handshake enters placement")
		set_stage("full_lobby")
		phase = 1
	elif phase == 1 and has_marker("reject_full.done"):
		net.ready_fleet(fleet())
		check(net.state.own_ready and not net.state.other_ready, "host ready alone does not start")
		set_stage("place")
		phase = 2
	elif phase == 2 and net.state.get("phase") == "battle":
		check(net.state.turn == 0, "host opens round1")
		set_stage("late_join")
		phase = 3
	elif phase == 3 and has_marker("reject_late.done"):
		set_stage("hostile_initial")
		phase = 4
	elif phase == 4 and has_marker("hostile_initial.done"):
		check(net.state.shots.is_empty() and net.state.turn == 0, "hostile outofturn and malformed requests cannot advance")
		check(not net.referee.fleets[0][0].vertical and net.referee.fleets[1][0].vertical, "distinct locked fleets remain assigned to correct players")
		set_stage("play")
		phase = 5
	elif phase == 5:
		if net.state.phase == "finished":
			check(net.state.winner == 0 and net.state.shots.size() == 33, "host wins by17 alternating hits")
			check(net.state.sunk_enemy.size() == 5, "all five ships sunk")
			check(seen_battle and saw_sunk, "battle and sinking observed")
			set_stage("finished")
			phase = 6
			phase_at = now
		elif net.state.turn == 0 and now - last_send_at >= 180:
			var count: int = net.state.shots.size()
			if count != last_sent_count:
				last_sent_count = count
				last_send_at = now
				var target: Vector2i = targets()[count / 2]
				net.shoot(target.x, target.y)
	elif phase == 6 and has_marker("client_saw_finish"):
		net.vote_rematch()
		check(net.state.phase == "finished" and net.state.rematch_votes[0], "single rematch vote keeps finished state")
		set_stage("rematch")
		phase = 7
	elif phase == 7 and net.state.phase == "placement":
		check(net.state.round == initial_round + 1, "both votes increment round")
		check(net.state.shots.is_empty() and net.state.own_fleet.is_empty(), "rematch clears authoritative state")
		check(not net.state.own_ready and not net.state.other_ready, "rematch requires both fresh layouts")
		check(net.state.turn == 1, "opening player alternates on rematch")
		set_stage("new_round")
		phase = 8
	elif phase == 8 and has_marker("client_saw_rematch"):
		net.leave()
		check(not net.connected and net.state.is_empty(), "host leave clears local connection")
		phase_at = now
		phase = 9
	elif phase == 9 and has_marker("client.done"):
		finish()

func client_step(now: int) -> void:
	if phase == 0 and stage() == "place" and not net.state.is_empty():
		check(net.connected and net.state.player == 1, "client admitted with own logical identity")
		net._request.rpc_id(1, ["ready", [1, 2, 3, 4, 5]])
		net._request.rpc_id(1, ["ready", "not an array"])
		phase_at = now
		phase = 1
	elif phase == 1 and now - phase_at > 250:
		check(not net.state.own_ready and net.state.phase == "placement", "malformed ready cannot start battle")
		net.ready_fleet(fleet())
		phase = 2
	elif phase == 2 and stage() == "hostile_initial":
		net._request.rpc_id(1, ["fire", 9, 9]) # Valid coordinate, wrong turn.
		net._request.rpc_id(1, ["fire", "0", 0])
		net._request.rpc_id(1, ["fire", 0.5, 0])
		net._request.rpc_id(1, ["fire", -1, 99])
		net._request.rpc_id(1, ["ready", []])
		net._request.rpc_id(1, {"fire": [0, 0]})
		net._request.rpc_id(1, ["fire", 0, 0, 0])
		net._request.rpc_id(1, "bad")
		phase_at = now
		phase = 3
	elif phase == 3 and now - phase_at > 350:
		check(net.state.shots.is_empty() and net.state.turn == 0, "client sees no mutation from hostile packets")
		marker("hostile_initial.done")
		phase = 4
	elif phase == 4 and stage() == "play":
		if net.state.phase == "battle" and net.state.turn == 1 and now - last_send_at >= 180:
			var count: int = net.state.shots.size()
			if count != last_sent_count:
				last_sent_count = count
				last_send_at = now
				if count == 3:
					# Invalid current-turn shots and a duplicate precede a valid miss in reliable order.
					net._request.rpc_id(1, ["fire", -1, 0])
					net._request.rpc_id(1, ["fire", 10, 0])
					net._request.rpc_id(1, ["fire", 9, 9])
				var index: int = count / 2
				net.shoot(9 - index % 10, 9 - index / 10)
	if phase == 4 and net.state.get("phase") == "finished":
		check(net.state.winner == 0 and net.state.shots.size() == 33, "client agrees exact final winner and shotcount")
		check(net.state.has("enemy_fleet"), "finished match reveals enemy fleet only now")
		check(seen_battle and seen_finish, "client observed real replicated battle")
		marker("client_saw_finish")
		phase = 5
	elif phase == 5 and stage() == "rematch" and net.state.rematch_votes[0]:
		check(net.state.rematch_votes[0], "host rematch vote replicated")
		net.vote_rematch()
		phase = 6
	elif phase == 6 and net.state.get("phase") == "placement":
		check(net.state.round == initial_round + 1 and net.state.shots.is_empty(), "client receives clean new round")
		check(net.state.own_fleet.is_empty() and not net.state.has("enemy_fleet"), "new round restores privacy")
		marker("client_saw_rematch")
		phase = 7
	elif phase == 7 and not disconnect_message.is_empty():
		check(not net.connected and net.state.is_empty(), "host disconnect cleans client state")
		check("房主" in disconnect_message, "host departure presented clearly")
		finish()

func disconnect_step(now: int) -> void:
	if role == "host":
		if phase == 0 and net.opponent_present:
			net.ready_fleet(fleet())
			set_stage("leave_guest")
			phase = 1
		elif phase == 1 and not net.opponent_present and has_marker("guest_left"):
			check(net.connected and net.is_host, "host stays available after guest departure")
			check(net.state.phase == "placement" and net.state.shots.is_empty(), "guest departure cancels current round")
			check(not net.state.own_ready and net.state.own_fleet.is_empty(), "new guest cannot inherit old fleet")
			finish()
	elif phase == 0 and stage() == "leave_guest" and net.connected:
		net.ready_fleet(fleet())
		phase_at = now
		phase = 1
	elif phase == 1 and net.state.get("phase") == "battle":
		check(net.state.own_ready and net.state.other_ready, "guest leaves from real active battle")
		net.leave()
		check(not net.connected and net.state.is_empty(), "guest explicit leave clears local state")
		marker("guest_left")
		finish()
