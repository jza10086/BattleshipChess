extends RefCounted
## Host-owned fleets and votes. Views reveal only allied ships and publicly sunk enemies.
const SIZE: int = 10
const LENGTHS: Array[int] = [5, 4, 3, 3, 2]
var teams: Array = [[], []]
var connected: Dictionary = {}
var fleets: Array = [[], []]
var locked: Array[bool] = [false, false]
var shots: Array[Dictionary] = []
var votes: Dictionary = {}
var phase: String = "placement"
var turn: int = 0
var turn_number: int = 0
var winner: int = -1
var solo: bool = false
var solo_team: int = 0
var last_event: Dictionary = {}
var random: RandomNumberGenerator = RandomNumberGenerator.new()

func start(players: Array[Dictionary], public_seed: int) -> void:
	var ids: Array[String] = []
	for player: Dictionary in players:
		ids.append(player.player_id)
		connected[player.player_id] = player.connected
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
	turn = team_random.randi_range(0, 1)
	# Public round seeds must not let clients reconstruct hidden ship positions or draws.
	random.randomize()
	fleets = [random_fleet(), random_fleet()]

func team_of(player_id: String) -> int:
	for team: int in range(2):
		if player_id in teams[team]:
			return team
	return -1

func controlled_team(player_id: String) -> int:
	if solo and team_of(player_id) == 0:
		return solo_team if phase == "placement" else turn
	return team_of(player_id)

func members(team: int) -> Array[String]:
	var result: Array[String] = []
	for id: String in teams[0 if solo else team]:
		if connected[id]:
			result.append(id)
	return result

func captain(team: int) -> String:
	var active: Array[String] = members(team)
	return "" if active.is_empty() else active[0]

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
		var candidates: Array[Dictionary] = []
		for vertical: bool in [false, true]:
			for y: int in range(SIZE - (LENGTHS[index] - 1 if vertical else 0)):
				for x: int in range(SIZE - (0 if vertical else LENGTHS[index] - 1)):
					var ship: Dictionary = {"x": x, "y": y, "vertical": vertical, "length": LENGTHS[index], "index": index}
					var candidate: Array = result.duplicate()
					candidate.append(ship)
					if valid_fleet(candidate):
						candidates.append(ship)
		result.append(candidates[random.randi_range(0, candidates.size() - 1)])
	return result

## The controller supplies the authenticated player ID; payload is an untrusted network boundary.
func act(player_id: String, action: Dictionary) -> bool:
	var team: int = controlled_team(player_id)
	if team < 0 or not connected[player_id] or typeof(action.get("turn")) != TYPE_INT or action.turn != turn_number:
		return false
	var kind: Variant = action.get("kind")
	if phase == "placement":
		if player_id != captain(team):
			return false
		if kind == "switch" and solo:
			solo_team = 1 - solo_team
			return true
		if locked[team]:
			return false
		if kind == "shuffle":
			fleets[team] = random_fleet()
			return true
		if kind == "ready":
			locked[team] = true
			if solo and not locked[1 - team]:
				solo_team = 1 - team
			if locked[0] and locked[1]:
				begin_battle()
			return true
		if kind == "place":
			for key: String in ["index", "x", "y"]:
				if typeof(action.get(key)) != TYPE_INT:
					return false
			if typeof(action.get("vertical")) != TYPE_BOOL or action.index < 0 or action.index >= LENGTHS.size() or action.x < 0 or action.x >= SIZE or action.y < 0 or action.y >= SIZE:
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
	if phase != "battle" or team != turn or kind != "vote":
		return false
	if typeof(action.get("cell")) != TYPE_INT or action.cell < 0 or action.cell >= SIZE * SIZE:
		return false
	if was_fired(turn, action.cell):
		return false
	votes[player_id] = action.cell
	return true

func begin_battle() -> void:
	locked = [true, true]
	phase = "battle"
	turn_number += 1
	votes.clear()

func was_fired(by: int, cell: int) -> bool:
	for shot: Dictionary in shots:
		if shot.by == by and shot.cell == cell:
			return true
	return false

func all_voted() -> bool:
	var active: Array[String] = members(turn)
	if active.is_empty():
		return false
	for id: String in active:
		if not votes.has(id):
			return false
	return true

## One uniform ticket per voter gives each target exactly votes(target) / total_votes probability.
func resolve_vote() -> void:
	var tickets: Array = votes.values()
	if tickets.is_empty():
		last_event = {"by": turn, "cell": -1, "hit": false, "sunk": -1}
	else:
		var cell: int = tickets[random.randi_range(0, tickets.size() - 1)]
		var enemy: int = 1 - turn
		var hit: bool = false
		var sunk: int = -1
		for ship: Dictionary in fleets[enemy]:
			if Vector2i(cell % SIZE, cell / SIZE) in cells(ship):
				hit = true
		var shot: Dictionary = {"by": turn, "cell": cell, "hit": hit, "sunk": -1}
		shots.append(shot)
		var remaining: int = 0
		for ship: Dictionary in fleets[enemy]:
			if is_sunk(enemy, ship):
				if Vector2i(cell % SIZE, cell / SIZE) in cells(ship):
					sunk = ship.index
			else:
				remaining += 1
		shot.sunk = sunk
		last_event = shot.duplicate()
		if remaining == 0:
			winner = turn
			phase = "finished"
	votes.clear()
	turn = 1 - turn
	turn_number += 1

func is_sunk(team: int, ship: Dictionary) -> bool:
	for cell: Vector2i in cells(ship):
		if not was_fired(1 - team, cell.y * SIZE + cell.x):
			return false
	return true

func update_connections(players: Array[Dictionary]) -> void:
	for player: Dictionary in players:
		connected[player.player_id] = player.connected
		if not player.connected:
			votes.erase(player.player_id)
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
		votes.clear()

func view(player_id: String) -> Dictionary:
	var team: int = controlled_team(player_id)
	var visible: Array = [[], []]
	for board: int in range(2):
		for ship: Dictionary in fleets[board]:
			if board == team or phase == "finished" or is_sunk(board, ship):
				var shown: Dictionary = ship.duplicate()
				shown["sunk"] = is_sunk(board, ship)
				visible[board].append(shown)
	var shown_votes: Dictionary = votes.duplicate() if team == turn else {}
	return {"phase": phase, "team": team, "teams": teams.duplicate(true), "solo": solo,
		"captain": team >= 0 and captain(team) == player_id, "locked": locked.duplicate(),
		"fleets": visible, "turn": turn, "turn_number": turn_number, "winner": winner,
		"shots": shots.duplicate(true), "votes": shown_votes, "last_event": last_event.duplicate(),
		"eligible": members(turn).size(), "voted": votes.size()}

func result(request_id: String, players: Array[Dictionary]) -> Dictionary:
	var rows: Array[Dictionary] = []
	for player: Dictionary in players:
		var rank: int = 0
		var status: String = "withdrawn"
		if player.connected:
			status = "unranked" if winner < 0 else "completed"
			rank = 0 if winner < 0 else (1 if solo or team_of(player.player_id) == winner else 2)
		rows.append({"player_id": player.player_id, "rank": rank, "status": status,
			"metrics": {"team": "单人测试" if solo else ("蓝队" if team_of(player.player_id) == 0 else "红队")}})
	return {"request_id": request_id, "reason": "cancelled" if winner < 0 else "completed",
		"rankings": rows, "columns": [{"key": "team", "title": "队伍", "format": "text"}],
		"game_data": {"winner": winner, "turns": turn_number, "solo_test": solo}}
