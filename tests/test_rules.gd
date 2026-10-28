extends SceneTree
## Deterministic production-rule tests. No production fixture mutation.
const Rules = preload("res://scripts/rules.gd")
const LENGTHS := [5, 4, 3, 3, 2]
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label)

func fleet(vertical := false) -> Array:
	var result: Array = []
	for i in range(5):
		result.append({"x": i * 2 if vertical else 0, "y": 0 if vertical else i * 2, "vertical": vertical, "length": LENGTHS[i]})
	return result

func shot_cells(ships: Array) -> Array:
	var result: Array = []
	for ship in ships:
		for cell in Rules.ship_cells(ship): result.append(cell)
	return result

func same_state(game, before: Dictionary, label: String) -> void:
	check(game.snapshot(0) == before, label)

func run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261028
	check(Rules.fleet_valid(fleet()), "horizontal fleet accepted")
	check(Rules.fleet_valid(fleet(true)), "vertical fleet accepted")
	var adjacent := fleet()
	for i in range(5): adjacent[i].y = i
	check(Rules.fleet_valid(adjacent), "touching ships allowed")
	for i in range(200):
		var generated: Array = Rules.auto_fleet(rng)
		check(Rules.fleet_valid(generated), "random fleet %d valid" % i)
		var unique := {}
		for cell in shot_cells(generated): unique[cell] = true
		check(unique.size() == 17, "random fleet %d has17 unique cells" % i)
	var invalid := fleet()
	invalid[0].x = 6
	check(not Rules.fleet_valid(invalid), "horizontal outofbounds rejected")
	invalid[0].x = 5
	check(Rules.fleet_valid(invalid), "horizontal ship fits exactly to right edge")
	invalid = fleet(true)
	invalid[0].y = 6
	check(not Rules.fleet_valid(invalid), "vertical outofbounds rejected")
	invalid[0].y = 5
	check(Rules.fleet_valid(invalid), "vertical ship fits exactly to lower edge")
	invalid = fleet()
	invalid[1].y = 0
	check(not Rules.fleet_valid(invalid), "overlap rejected")
	invalid = fleet()
	invalid[0].x = -1
	check(not Rules.fleet_valid(invalid), "negative coordinates rejected")
	invalid = fleet()
	invalid[0].length = 4
	check(not Rules.fleet_valid(invalid), "wrong ship length rejected")
	check(not Rules.fleet_valid([]), "empty fleet rejected")
	check(not Rules.fleet_valid([1, 2, 3, 4, 5]), "malformed ship items rejected")
	invalid = fleet()
	invalid[0].x = "0"
	check(not Rules.fleet_valid(invalid), "string coordinates rejected")
	invalid = fleet()
	invalid[0].vertical = "false"
	check(not Rules.fleet_valid(invalid), "nonboolean orientation rejected")
	invalid = fleet()
	invalid[0].x = 0.5
	check(not Rules.fleet_valid(invalid), "fractional coordinates rejected")
	var game = Rules.new()
	var initial: Dictionary = game.snapshot(0)
	check(initial.phase == "placement", "reset opens placement")
	check(initial.shots.is_empty(), "reset removes shots")
	check(not game.submit_fleet(-1, fleet()), "negative player rejected")
	check(not game.submit_fleet(2, fleet()), "third player rejected")
	check(not game.fire(0, 0, 0), "cannot fire before ready")
	check(not game.submit_fleet(0, []), "invalid fleet rejected by referee")
	var submitted := fleet()
	check(game.submit_fleet(0, submitted), "host submits valid fleet")
	submitted[0].x = 9
	check(game.snapshot(0).own_fleet[0].x == 0, "caller cannot mutate accepted fleet by reference")
	var locked: Dictionary = game.snapshot(0)
	check(locked.own_ready and not locked.other_ready, "only host ready")
	check(not game.submit_fleet(0, fleet(true)), "cannot reposition after ready")
	same_state(game, locked, "rejected readiness cannot mutate fleet")
	check(not game.fire(0, 0, 0), "cannot fire while waiting for opponent")
	check(game.submit_fleet(1, fleet()), "client submits valid fleet")
	check(game.snapshot(0).phase == "battle", "both ready starts battle")
	check(game.snapshot(0).turn == 0, "host opens first round")
	var before: Dictionary = game.snapshot(0)
	check(not game.fire(1, 9, 9), "outofturn rejected")
	same_state(game, before, "outofturn does not advance")
	check(not game.fire(0, -1, 0), "negative shot rejected")
	check(not game.fire(0, 10, 0), "outside shot rejected")
	check(not game.fire(2, 0, 0), "invalid shooter rejected")
	same_state(game, before, "invalid shots do not mutate")
	check(game.fire(0, 0, 0), "valid hit accepted")
	var hit: Dictionary = game.snapshot(0)
	check(hit.shots[-1].hit and hit.turn == 1, "hit switches turn")
	check(game.fire(1, 9, 9), "valid miss accepted")
	var miss: Dictionary = game.snapshot(0)
	check(not miss.shots[-1].hit and miss.turn == 0, "miss switches turn")
	before = game.snapshot(0)
	check(not game.fire(0, 0, 0), "duplicate own shot rejected")
	same_state(game, before, "duplicate does not advance turn")
	check(not game.submit_fleet(1, fleet(true)), "cannot place during battle")
	check(not before.has("enemy_fleet"), "live snapshot hides opponent fleet")
	var mutable_snapshot: Dictionary = game.snapshot(0)
	mutable_snapshot.own_fleet[0].x = 9
	mutable_snapshot.shots[0].x = 9
	check(game.snapshot(0).own_fleet[0].x == 0 and game.snapshot(0).shots[0].x == 0, "mutating snapshot cannot change referee")
	check(before.sunk_enemy.is_empty(), "unsunk enemy not disclosed")
	var targets: Array = shot_cells(fleet())
	var client_miss := 0
	for i in range(1, targets.size()):
		var cell: Vector2i = targets[i]
		check(game.fire(0, cell.x, cell.y), "host valid target %d" % i)
		var state: Dictionary = game.snapshot(0)
		if i == 4:
			check(state.shots[-1].sunk == 0, "fifth carrier hit reports sunk")
			check(state.sunk_enemy.size() == 1, "only sunk ship disclosed")
		if i < targets.size() - 1:
			check(state.phase == "battle" and state.winner == -1, "not prematurely victorious")
			check(not state.has("enemy_fleet"), "fleet stays secret until last hit")
			check(game.fire(1, 9 - client_miss / 9, client_miss % 9), "client alternating miss %d" % client_miss)
			client_miss += 1
	var finished: Dictionary = game.snapshot(0)
	check(finished.phase == "finished" and finished.winner == 0, "17 hits declares winner")
	check(finished.shots.size() == 33, "one shot per alternating turn")
	check(finished.sunk_enemy.size() == 5, "all five ships sunk")
	check(finished.has("enemy_fleet"), "completed game may reveal enemy fleet")
	check(not game.fire(1, 7, 7), "cannot shoot after victory")
	check(not game.rematch(2), "invalid rematch voter rejected")
	check(game.rematch(0), "first rematch vote accepted")
	check(game.snapshot(0).phase == "finished", "one rematch vote does not reset")
	check(game.rematch(1), "second rematch vote accepted")
	var next: Dictionary = game.snapshot(0)
	check(next.phase == "placement", "both votes return to placement")
	check(next.round == finished.round + 1, "round counter advances once")
	check(next.shots.is_empty() and next.own_fleet.is_empty(), "new round clears fleet and shots")
	check(not next.own_ready and not next.other_ready, "new round requires new readiness")
	check(not next.has("enemy_fleet"), "rematch hides opponent again")
	check(not game.fire(0, 0, 0), "new round cannot skip placement")
	check(game.submit_fleet(0, fleet(true)), "vertical placement after reset accepted")
	check(game.submit_fleet(1, fleet()), "new round second fleet accepted")
	check(game.snapshot(0).phase == "battle", "new round playable")
	game.reset()
	var reset_state: Dictionary = game.snapshot(0)
	check(reset_state.phase == "placement" and reset_state.own_fleet.is_empty() and reset_state.shots.is_empty(), "explicit room reset clears all match data")
	check(reset_state.winner == -1 and reset_state.sunk_enemy.is_empty() and reset_state.rematch_votes == [false, false], "reset clears winner, sunk ships, and votes")
	print("RULE_TEST_RESULT checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
