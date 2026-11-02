class_name BattleRules
extends RefCounted

## Pure authoritative rules. Network IDs never enter this model.
## Ship index fixes its length; touching ships are allowed.
const SIZE := 10
const LENGTHS := [5, 4, 3, 3, 2]
const TOTAL_CELLS := 17

var phase := "placement"
var fleets: Array = [[], []]
var ready: Array = [false, false]
var turn := 0
var winner := -1
var shots: Array = []
var rematch_votes: Array = [false, false]
var round := 0
var _fired: Array = [{}, {}]
var _sunk: Array = [[], []]

func _init() -> void:
	reset()

static func _valid_player(player: int) -> bool:
	return player == 0 or player == 1

static func ship_cells(ship: Dictionary) -> Array:
	var result: Array = []
	if not ship.has("x") or not ship.has("y") or not ship.has("vertical"):
		return result
	var length: int = int(ship.get("length", 0))
	if length < 2 or length > 5:
		return result
	for offset in range(length):
		result.append(Vector2i(int(ship.x) + (0 if ship.vertical else offset), int(ship.y) + (offset if ship.vertical else 0)))
	return result

static func fleet_valid(fleet: Array) -> bool:
	if fleet.size() != LENGTHS.size():
		return false
	var occupied: Dictionary = {}
	for index in range(LENGTHS.size()):
		if typeof(fleet[index]) != TYPE_DICTIONARY:
			return false
		var ship: Dictionary = fleet[index]
		if typeof(ship.get("x")) != TYPE_INT or typeof(ship.get("y")) != TYPE_INT or typeof(ship.get("vertical")) != TYPE_BOOL:
			return false
		if ship.has("length") and (typeof(ship.length) != TYPE_INT or ship.length != LENGTHS[index]):
			return false
		if int(ship.x) < 0 or int(ship.x) >= SIZE or int(ship.y) < 0 or int(ship.y) >= SIZE:
			return false
		var normalized := {"x": int(ship.x), "y": int(ship.y), "vertical": bool(ship.vertical), "length": int(LENGTHS[index])}
		for cell in ship_cells(normalized):
			if cell.x >= SIZE or cell.y >= SIZE:
				return false
			var key: int = cell.y * SIZE + cell.x
			if occupied.has(key):
				return false
			occupied[key] = true
	return occupied.size() == TOTAL_CELLS

static func auto_fleet(rng: RandomNumberGenerator) -> Array:
	# Enumerate valid placements for each ship; bounded retries then a guaranteed fallback.
	for attempt in range(64):
		var result: Array = []
		var occupied: Dictionary = {}
		for index in range(LENGTHS.size()):
			var length: int = LENGTHS[index]
			var candidates: Array = []
			for vertical in [false, true]:
				for y in range(SIZE - (length - 1 if vertical else 0)):
					for x in range(SIZE - (0 if vertical else length - 1)):
						var candidate := {"x": x, "y": y, "vertical": vertical, "length": length, "index": index}
						var valid := true
						for cell in ship_cells(candidate):
							if occupied.has(cell.y * SIZE + cell.x):
								valid = false
								break
						if valid:
							candidates.append(candidate)
			if candidates.is_empty():
				break
			var chosen: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
			result.append(chosen)
			for cell in ship_cells(chosen):
				occupied[cell.y * SIZE + cell.x] = true
		if result.size() == LENGTHS.size():
			return result
	var fallback: Array = []
	for index in range(LENGTHS.size()):
		fallback.append({"x": 0, "y": index, "vertical": false, "length": int(LENGTHS[index]), "index": index})
	return fallback

func reset() -> void:
	round += 1
	phase = "placement"
	fleets = [[], []]
	ready = [false, false]
	turn = (round - 1) % 2
	winner = -1
	shots = []
	rematch_votes = [false, false]
	_fired = [{}, {}]
	_sunk = [[], []]

func submit_fleet(player: int, fleet: Array) -> bool:
	if not _valid_player(player) or phase != "placement" or ready[player] or not fleet_valid(fleet):
		return false
	var normalized: Array = []
	for index in range(LENGTHS.size()):
		var ship: Dictionary = fleet[index]
		normalized.append({"x": int(ship.x), "y": int(ship.y), "vertical": bool(ship.vertical), "length": int(LENGTHS[index]), "index": index})
	fleets[player] = normalized
	ready[player] = true
	if ready[0] and ready[1]:
		phase = "battle"
	return true

func fire(player: int, x: int, y: int) -> bool:
	if not _valid_player(player) or phase != "battle" or player != turn:
		return false
	if x < 0 or x >= SIZE or y < 0 or y >= SIZE:
		return false
	var key := y * SIZE + x
	if _fired[player].has(key):
		return false
	var enemy := 1 - player
	var hit_index := -1
	for index in range(LENGTHS.size()):
		if Vector2i(x, y) in ship_cells(fleets[enemy][index]):
			hit_index = index
			break
	_fired[player][key] = hit_index >= 0
	var sunk_index := -1
	if hit_index >= 0:
		var sunk := true
		for cell in ship_cells(fleets[enemy][hit_index]):
			if not _fired[player].has(cell.y * SIZE + cell.x):
				sunk = false
				break
		if sunk:
			sunk_index = hit_index
			_sunk[player].append(hit_index)
	shots.append({"by": player, "x": x, "y": y, "hit": hit_index >= 0, "sunk": sunk_index})
	# A hit does not grant an extra turn. Even the final shot is one complete turn.
	turn = enemy
	if _sunk[player].size() == LENGTHS.size():
		winner = player
		phase = "finished"
	return true

func rematch(player: int) -> bool:
	if not _valid_player(player) or phase != "finished" or rematch_votes[player]:
		return false
	rematch_votes[player] = true
	if rematch_votes[0] and rematch_votes[1]:
		reset()
	return true

func snapshot(player: int) -> Dictionary:
	if not _valid_player(player):
		return {}
	var enemy := 1 - player
	var sunk_enemy: Array = []
	for index in _sunk[player]:
		sunk_enemy.append(fleets[enemy][index].duplicate(true))
	var result := {
		"phase": phase, "player": player, "own_fleet": fleets[player].duplicate(true),
		"own_ready": bool(ready[player]), "other_ready": bool(ready[enemy]),
		"turn": turn, "winner": winner, "round": round,
		"shots": shots.duplicate(true), "sunk_enemy": sunk_enemy,
		"rematch_votes": rematch_votes.duplicate()
	}
	# This is the only intentional full enemy-fleet disclosure: the match is over.
	if phase == "finished":
		result["enemy_fleet"] = fleets[enemy].duplicate(true)
	return result
