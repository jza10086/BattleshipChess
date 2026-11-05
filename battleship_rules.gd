extends RefCounted
## Host-owned fleets, simultaneous salvos and personal hit scores. Views reveal only allied ships and publicly sunk enemies.
const SIZE: int = 10
const LENGTHS: Array[int] = [5, 4, 4, 3, 2]
var teams: Array = [[], []]
var connected: Dictionary = {}
var fleets: Array = [[], []]
var locked: Array[bool] = [false, false]
var ship_owners: Array = [[], []]
var placement_ready: Array = [{}, {}]
var shots: Array[Dictionary] = []
var targets: Array = [{}, {}]
var scores: Dictionary[String, int] = {}
var phase: String = "placement"
var turn_number: int = 0
var winner: int = -1
var solo: bool = false
var solo_team: int = 0
var last_salvo: Array[Dictionary] = []
var random: RandomNumberGenerator = RandomNumberGenerator.new()

func start(players: Array[Dictionary], public_seed: int) -> void:
	var ids: Array[String] = []
	for player: Dictionary in players:
		ids.append(player.player_id)
		connected[player.player_id] = player.connected
		scores[player.player_id] = 0
	solo = ids.size() == 1
	var team_random: RandomNumberGenerator = RandomNumberGenerator.new()
	team_random.seed = public_seed
	for index: int in range(ids.size() - 1, 0, -1):
		var other: int = team_random.randi_range(0, index)
		var value: String = ids[index]
		ids[index] = ids[other]
		ids[other] = value
	for index: int in range(ids.size()):
		teams[index % 2].append(ids[index])
	# Public round seeds must not let clients reconstruct hidden ship positions or dud selection.
	random.randomize()
	fleets = [random_fleet(), random_fleet()]
	for team: int in range(2):
		_assign_ships(team)

func team_of(player_id: String) -> int:
	for team: int in range(2):
		if player_id in teams[team]:
			return team
	return -1

func controlled_team(player_id: String) -> int:
	if solo and team_of(player_id) == 0:
		return solo_team
	return team_of(player_id)

func members(team: int) -> Array[String]:
	var result: Array[String] = []
	for id: String in teams[0 if solo else team]:
		if connected[id]:
			result.append(id)
	return result

## Shuffle both seats and ship indices so extra ships and ship types are random.
func _assign_ships(team: int) -> void:
	var players: Array = teams[0 if solo else team].duplicate()
	var indices: Array = range(LENGTHS.size())
	for values: Array in [players, indices]:
		for index: int in range(values.size() - 1, 0, -1):
			var other: int = random.randi_range(0, index)
			var value: Variant = values[index]
			values[index] = values[other]
			values[other] = value
	ship_owners[team].resize(LENGTHS.size())
	for index: int in range(indices.size()):
		ship_owners[team][indices[index]] = players[index % players.size()]

func owned_ships(team: int, player_id: String) -> Array[int]:
	var result: Array[int] = []
	for index: int in range(LENGTHS.size()):
		if ship_owners[team][index] == player_id:
			result.append(index)
	return result

func ready_count(team: int) -> int:
	var count: int = 0
	for id: String in members(team):
		if placement_ready[team].has(id):
			count += 1
	return count

func _update_placement_locks() -> void:
	for team: int in range(2):
		locked[team] = ready_count(team) == members(team).size()
	if locked[0] and locked[1]:
		begin_battle()

## Keep every other player's layout; only reassign ships whose owner disconnected.
func _redistribute_ships(team: int) -> void:
	var active: Array[String] = members(team)
	for index: int in range(LENGTHS.size()):
		if connected[ship_owners[team][index]]:
			continue
		var candidates: Array[String] = []
		var least: int = LENGTHS.size()
		for id: String in active:
			var count: int = owned_ships(team, id).size()
			if count < least:
				candidates.clear()
				least = count
			if count == least:
				candidates.append(id)
		var recipient: String = candidates[random.randi_range(0, candidates.size() - 1)]
		ship_owners[team][index] = recipient
		placement_ready[team].erase(recipient)

static func cells(ship: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset: int in range(ship.length):
		result.append(Vector2i(ship.x, ship.y) + (Vector2i(0, offset) if ship.vertical else Vector2i(offset, 0)))
	return result

static func valid_fleet(fleet: Array) -> bool:
	var occupied: Dictionary = {}
	for ship: Dictionary in fleet:
		for cell: Vector2i in cells(ship):
			if cell.x < 0 or cell.x >= SIZE or cell.y < 0 or cell.y >= SIZE or occupied.has(cell):
				return false
			occupied[cell] = true
	return true

func random_fleet() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in range(LENGTHS.size()):
		result.append(_random_ship(index, result))
	return result

func _random_ship(index: int, occupied: Array) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for vertical: bool in [false, true]:
		for y: int in range(SIZE - (LENGTHS[index] - 1 if vertical else 0)):
			for x: int in range(SIZE - (0 if vertical else LENGTHS[index] - 1)):
				var ship: Dictionary = {"x": x, "y": y, "vertical": vertical, "length": LENGTHS[index], "index": index}
				var candidate: Array = occupied.duplicate()
				candidate.append(ship)
				if valid_fleet(candidate):
					candidates.append(ship)
	return candidates[random.randi_range(0, candidates.size() - 1)]

func _shuffle_owned(team: int, player_id: String) -> void:
	for index: int in owned_ships(team, player_id):
		var occupied: Array = fleets[team].duplicate()
		occupied.remove_at(index)
		fleets[team][index] = _random_ship(index, occupied)

## The controller supplies the authenticated player ID; payload is an untrusted network boundary.
func act(player_id: String, action: Dictionary) -> bool:
	var team: int = controlled_team(player_id)
	if team < 0 or not connected[player_id] or typeof(action.get("turn")) != TYPE_INT or action.turn != turn_number:
		return false
	var kind: Variant = action.get("kind")
	if kind == "switch" and solo and phase in ["placement", "battle"]:
		solo_team = 1 - solo_team
		return true
	if phase == "placement":
		if placement_ready[team].has(player_id):
			return false
		if kind == "shuffle":
			_shuffle_owned(team, player_id)
			return true
		if kind == "ready":
			placement_ready[team][player_id] = true
			_update_placement_locks()
			if solo and phase == "placement" and not locked[1 - team]:
				solo_team = 1 - team
			return true
		if kind == "place":
			for key: String in ["index", "x", "y"]:
				if typeof(action.get(key)) != TYPE_INT:
					return false
			if typeof(action.get("vertical")) != TYPE_BOOL or action.index < 0 or action.index >= LENGTHS.size() or action.x < 0 or action.x >= SIZE or action.y < 0 or action.y >= SIZE:
				return false
			if ship_owners[team][action.index] != player_id:
				return false
			var next: Array = fleets[team].duplicate(true)
			next[action.index].x = action.x
			next[action.index].y = action.y
			next[action.index].vertical = action.vertical
			if not valid_fleet(next):
				return false
			fleets[team] = next
			return true
		return false
	if phase != "battle" or kind != "target" or typeof(action.get("team")) != TYPE_INT or action.team != team:
		return false
	if typeof(action.get("cell")) != TYPE_INT or action.cell < 0 or action.cell >= SIZE * SIZE:
		return false
	if was_fired(team, action.cell):
		return false
	# Host arrival order gives a cell to its first claimant. A failed change preserves the old target.
	for id: String in targets[team]:
		if id != player_id and targets[team][id] == action.cell:
			return false
	targets[team][player_id] = action.cell
	if solo and targets[1 - team].is_empty():
		solo_team = 1 - team
	return true

func begin_battle() -> void:
	locked = [true, true]
	phase = "battle"
	turn_number += 1
	targets = [{}, {}]
	solo_team = 0

func was_fired(by: int, cell: int) -> bool:
	for shot: Dictionary in shots:
		if shot.by == by and shot.cell == cell:
			return true
	return false

func all_targeted() -> bool:
	for team: int in range(2):
		var active: Array[String] = members(team)
		if active.is_empty():
			return false
		for id: String in active:
			if not targets[team].has(id):
				return false
	return true

## Resolve every selected shell before deciding victory. Duds never enter fired-cell history.
func resolve_salvo() -> void:
	if phase != "battle":
		return
	last_salvo.clear()
	for team: int in range(2):
		var active: Array[String] = members(team)
		var excess: int = maxi(0, active.size() - members(1 - team).size())
		var duds: Array[String] = []
		# Usually one extra player; withdrawals can create a larger imbalance.
		for index: int in range(excess):
			var picked: int = random.randi_range(0, active.size() - 1)
			duds.append(active[picked])
			active.remove_at(picked)
		for id: String in targets[team]:
			var cell: int = targets[team][id]
			var shot: Dictionary = {"by": team, "player_id": id, "cell": cell, "hit": false, "sunk": -1, "dud": id in duds}
			if not shot.dud:
				for ship: Dictionary in fleets[1 - team]:
					if Vector2i(cell % SIZE, cell / SIZE) in cells(ship):
						shot.hit = true
				shots.append(shot)
				if shot.hit:
					scores[id] += 1
			last_salvo.append(shot)
	# Attach sunk state only after all of both teams' shells have landed.
	for shot: Dictionary in last_salvo:
		if shot.hit:
			for ship: Dictionary in fleets[1 - shot.by]:
				if Vector2i(shot.cell % SIZE, shot.cell / SIZE) in cells(ship) and is_sunk(1 - shot.by, ship):
					shot.sunk = ship.index
	var destroyed: Array[bool] = [true, true]
	for team: int in range(2):
		for ship: Dictionary in fleets[team]:
			if not is_sunk(team, ship):
				destroyed[team] = false
	if destroyed[0] or destroyed[1]:
		phase = "finished"
		winner = -1 if destroyed[0] and destroyed[1] else (1 if destroyed[0] else 0)
	targets = [{}, {}]
	turn_number += 1
	solo_team = 0

func is_sunk(team: int, ship: Dictionary) -> bool:
	for cell: Vector2i in cells(ship):
		if not was_fired(1 - team, cell.y * SIZE + cell.x):
			return false
	return true

func update_connections(players: Array[Dictionary]) -> void:
	for player: Dictionary in players:
		connected[player.player_id] = player.connected
		if not player.connected:
			targets[0].erase(player.player_id)
			targets[1].erase(player.player_id)
	if phase == "finished":
		return
	if solo:
		if members(0).is_empty():
			phase = "finished"
		return
	var empty_a: bool = members(0).is_empty()
	var empty_b: bool = members(1).is_empty()
	if empty_a or empty_b:
		winner = -1 if empty_a and empty_b else (1 if empty_a else 0)
		phase = "finished"
		targets = [{}, {}]
	elif phase == "placement":
		for team: int in range(2):
			_redistribute_ships(team)
		_update_placement_locks()

func view(player_id: String) -> Dictionary:
	var team: int = controlled_team(player_id)
	var visible: Array = [[], []]
	for board: int in range(2):
		for ship: Dictionary in fleets[board]:
			if board == team or phase == "finished" or is_sunk(board, ship):
				var shown: Dictionary = ship.duplicate()
				shown["sunk"] = is_sunk(board, ship)
				shown["owner"] = ship_owners[board][ship.index]
				visible[board].append(shown)
	return {"phase": phase, "team": team, "teams": teams.duplicate(true), "solo": solo,
		"owned_ships": owned_ships(team, player_id) if team >= 0 else [],
		"placement_ready": team >= 0 and placement_ready[team].has(player_id),
		"ready_counts": [ready_count(0), ready_count(1)], "locked": locked.duplicate(),
		"fleets": visible, "turn_number": turn_number, "winner": winner,
		"shots": shots.duplicate(true), "targets": targets[team].duplicate() if team >= 0 else {},
		"last_salvo": last_salvo.duplicate(true), "scores": scores.duplicate(),
		"own_target": targets[team].get(player_id, -1) if team >= 0 else -1,
		"eligible": [members(0).size(), members(1).size()],
		"targeted": [targets[0].size(), targets[1].size()]}

func result(request_id: String, players: Array[Dictionary]) -> Dictionary:
	var rows: Array[Dictionary] = []
	for player: Dictionary in players:
		var bonus: int = 100 if winner >= 0 and (solo or team_of(player.player_id) == winner) and player.connected else 0
		rows.append({"player_id": player.player_id, "rank": 0,
			"status": "completed" if player.connected else "withdrawn",
			"metrics": {"score": scores[player.player_id] + bonus, "hits": scores[player.player_id], "bonus": bonus,
				"team": "单人测试" if solo else ("蓝队" if team_of(player.player_id) == 0 else "红队")}})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.status != b.status:
			return a.status == "completed"
		return a.metrics.score > b.metrics.score)
	for row: Dictionary in rows:
		if row.status == "completed":
			row.rank = 1
			for other: Dictionary in rows:
				if other.status == "completed" and other.metrics.score > row.metrics.score:
					row.rank += 1
	return {"request_id": request_id, "reason": "completed",
		"rankings": rows, "columns": [{"key": "score", "title": "总分", "format": "integer"},
			{"key": "hits", "title": "命中", "format": "integer"},
			{"key": "bonus", "title": "胜利加分", "format": "integer"},
			{"key": "team", "title": "队伍", "format": "text"}],
		"game_data": {"winner": winner, "draw": winner < 0, "turns": turn_number, "solo_test": solo}}
