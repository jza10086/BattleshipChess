extends Control

## Content-owned gameplay rules, independent of package compatibility.
static func party_definition() -> Dictionary:
	return {"player_counts": [1, 2, 3, 4, 5, 6, 7, 8]}

## PartyAPI owns transport and lifecycle; this host owns the game and sends private team views.
const Rules: Script = preload("res://games/minigame/gp_battleship/battleship_rules.gd")
const BattleView: Script = preload("res://games/minigame/gp_battleship/battle_view.gd")
const ACTION: StringName = &"battleship/action"
const VIEW: StringName = &"view"
var api: PartyAPI
var request: Dictionary
var model: Rules
@onready var view: BattleView = %BattleView
var snapshot: Dictionary = {}
@export var briefing: Control
@export var settlement: Control
var _result: Dictionary = {}
var _playing: bool = false
var _stopped: bool = false
var _settling: bool = false
var _submitted: bool = false
var _remaining: float = 60.0
var _target_seconds: int
var _phase_key: String = ""
var _end_msec: int = 0
var _published_views: Dictionary = {}
var _revision: int = 0
var _received_revision: int = -1

func party_setup(value: PartyAPI, config: Dictionary) -> void:
	api = value
	request = config.duplicate(true)
	_target_seconds = api.get_settings().target_seconds
	api.net.message_received.connect(_message)
	api.players_changed.connect(_players_changed)

func _ready() -> void:
	add_to_group("party_minimal_hud")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if api == null:
		push_error("海战棋需要从派对大厅启动。")
		return
	view.set_localization(api.i18n)
	view.host_clock = api.net.host_time_msec
	view.set_roster(api.get_players())
	view.action_requested.connect(_send_action)
	var content: Dictionary = briefing.read_content(get_script().resource_path.get_base_dir().path_join("manifest.json"), api)
	content["controls"] = [{"binding": api.i18n.text(&"controls.mouse"), "description": api.i18n.text(&"controls.primary")},
		{"binding": "Esc", "description": api.i18n.text(&"controls.menu")}]
	briefing.configure(api, content)
	briefing.play_requested.connect(_begin_play)
	var error: Error = api.mark_ready()
	if error != OK:
		_fail("ready_failed", error_string(error))

func godot_party_graphics_targets() -> Dictionary:
	return {"world": view.world, "sun": view.sun, "materials_root": view.models}

func party_start() -> void:
	briefing.transport_started()

func _begin_play() -> void:
	if _stopped:
		return
	_playing = true
	if api.is_host():
		model = Rules.new()
		model.start(api.get_players(), api.get_seed())
		model.update_connections(api.get_players())
		_publish()

func _process(delta: float) -> void:
	if api == null or _stopped:
		return
	view.input_enabled = _playing and not _settling and not api.input.input_blocked
	if not _playing or _settling or not api.is_host():
		return
	_remaining = maxf(0.0, _remaining - delta)
	if _remaining == 0.0:
		if model.phase == "placement":
			model.begin_battle()
		elif model.phase == "battle":
			model.resolve_salvo()
		_remaining = float(_target_seconds)
		_publish()

func _send_action(action: Dictionary) -> void:
	if not _playing or _stopped or _settling or api.input.input_blocked:
		return
	var error: Error = api.net.send_to_host(ACTION, action)
	if error != OK:
		_fail("action_send_failed", error_string(error))

func _message(sender: Dictionary, topic: StringName, payload: Variant) -> void:
	if _stopped:
		return
	if topic == ACTION:
		if not api.is_host() or not _playing or _settling or not payload is Dictionary:
			return
		for player: Dictionary in api.get_players():
			if player.connected and player.peer_id == sender.peer_id and player.player_id in sender.player_ids:
				_apply_action(player.player_id, payload)
				return
	elif topic == VIEW:
		if _settling or sender.peer_id != 1 or not payload is Dictionary or not payload.get("state") is Dictionary:
			return
		if typeof(payload.get("revision")) != TYPE_INT or payload.revision <= _received_revision:
			return
		if payload.state.get("phase") == "finished":
			if not payload.get("result") is Dictionary:
				_fail("invalid_result", "Missing battleship result dictionary")
				return
			var contract: Script = api.load_asset({"package_id": api.protocol_id, "resource_key": "contract"}) as Script
			if contract == null:
				_fail("contract_missing", "Default protocol result contract is missing")
				return
			var checked: Dictionary = contract.new().validate_result(payload.result, request, api.get_players())
			if not checked.ok:
				_fail(checked.code, checked.message)
				return
			if not _valid_scorecard(payload.result):
				_fail("invalid_scorecard", "Missing battleship score columns or metrics")
				return
		_received_revision = payload.revision
		if snapshot.is_empty():
			snapshot = {"shots": [], "fleets": [[], []]}
		var change: Dictionary = payload.state.duplicate(true)
		if change.has("shots_added"):
			if not change.shots_added is Array:
				return
			snapshot.shots.append_array(change.shots_added)
			change.erase("shots_added")
		if change.has("fleet_changes"):
			if not change.fleet_changes is Array:
				return
			for entry: Variant in change.fleet_changes:
				if not entry is Dictionary or entry.get("team") not in [0, 1] or not entry.get("ship") is Dictionary or not entry.ship.get("index") is int:
					return
				var replaced: bool = false
				for index: int in snapshot.fleets[entry.team].size():
					if snapshot.fleets[entry.team][index].index == entry.ship.index:
						snapshot.fleets[entry.team][index] = entry.ship
						replaced = true
						break
				if not replaced:
					snapshot.fleets[entry.team].append(entry.ship)
			change.erase("fleet_changes")
		snapshot.merge(change, true)
		snapshot["remaining"] = maxf(0.0, float(snapshot.end_msec - api.net.host_time_msec()) / 1000.0)
		var impact_time: float = view.show_state(snapshot)
		if snapshot.phase == "finished" and not _settling:
			_open_settlement(payload.result, impact_time)

## The protocol allows optional metrics/columns; this game's final scorecard requires its four columns.
## Called only at the receive boundary, after protocol validation has checked nested value types.
func _valid_scorecard(result: Dictionary) -> bool:
	if not result.has("columns") or result.columns.size() != 4:
		return false
	var keys: Array[String] = ["score", "hits", "bonus", "team"]
	for index: int in range(keys.size()):
		var column: Dictionary = result.columns[index]
		if column.key != keys[index] or column.format != ("text" if column.key == "team" else "integer"):
			return false
	for row: Dictionary in result.rankings:
		if not row.has("metrics") or not row.metrics.has_all(keys):
			return false
	return true

func _apply_action(player_id: String, action: Dictionary) -> void:
	var previous_phase: String = model.phase
	if not model.act(player_id, action):
		_publish()
		return
	if previous_phase == "placement" and model.phase == "battle":
		_remaining = float(_target_seconds)
	elif model.phase == "battle" and model.all_targeted():
		model.resolve_salvo()
		_remaining = float(_target_seconds)
	_publish()

func _players_changed() -> void:
	view.i18n = api.i18n
	view.set_roster(api.get_players())
	if not _playing or _settling or _stopped or not api.is_host():
		return
	var previous_phase: String = model.phase
	model.update_connections(api.get_players())
	if previous_phase == "placement" and model.phase == "battle":
		_remaining = float(_target_seconds)
	if model.phase == "battle" and model.all_targeted():
		model.resolve_salvo()
		_remaining = float(_target_seconds)
	_publish()

## Never broadcast the full model: the host may itself be an unselected spectator.
func _publish() -> void:
	var phase_key: String = "%s/%d" % [model.phase, model.turn_number]
	if phase_key != _phase_key:
		_phase_key = phase_key
		_end_msec = api.net.host_time_msec() + roundi(_remaining * 1000.0)
	_revision += 1
	var recipients: Array[Dictionary] = api.get_players()
	recipients.append_array(api.get_spectators())
	var result: Dictionary = model.result(request.request_id, api.get_players()) if model.phase == "finished" else {}
	for player: Dictionary in recipients:
		if not player.connected:
			continue
		var current: Dictionary = model.view(player.player_id)
		current["end_msec"] = _end_msec
		var previous: Dictionary = _published_views.get(player.player_id, {})
		var change: Dictionary = {}
		for key: String in current:
			if key in ["shots", "fleets"]:
				continue
			if not previous.has(key) or previous[key] != current[key]:
				change[key] = current[key]
		var shot_count: int = previous.get("shots", []).size()
		if current.shots.size() > shot_count:
			change["shots_added"] = current.shots.slice(shot_count)
		var ships: Array = []
		for team: int in range(2):
			for ship: Dictionary in current.fleets[team]:
				var old: Dictionary = {}
				if previous.has("fleets"):
					for candidate: Dictionary in previous.fleets[team]:
						if candidate.index == ship.index:
							old = candidate
							break
				if ship != old:
					ships.append({"team": team, "ship": ship})
		if not ships.is_empty():
			change["fleet_changes"] = ships
		if change.is_empty():
			continue
		var message: Dictionary = {"revision": _revision, "state": change}
		if change.get("phase") == "finished":
			message["result"] = result
		var error: Error = api.net.send_to_player(player.player_id, VIEW, message)
		if error != OK:
			_fail("view_send_failed", error_string(error))
			return
		_published_views[player.player_id] = current.duplicate(true)

func _open_settlement(result: Dictionary, impact_time: float) -> void:
	_settling = true
	view.input_enabled = false
	_result = result.duplicate(true)
	if impact_time > 0.0:
		await get_tree().create_timer(impact_time).timeout
		if _stopped or not api.is_open():
			return
	settlement.configure(api, _result_presentation(result), request.request_id)
	settlement.continued.connect(_submit_result)

## Translate a presentation copy; the authoritative result and its wire format remain unchanged.
func _result_presentation(result: Dictionary) -> Dictionary:
	var outcome: String = api.i18n.text(&"result.draw")
	if snapshot.winner >= 0:
		outcome = api.i18n.text(&"result.test_complete") if snapshot.solo else api.i18n.text(&"result.winner",
			{"team": api.i18n.text(&"team.blue" if snapshot.winner == 0 else &"team.red")})
	var columns: Array = result.columns.duplicate(true)
	for column: Dictionary in columns:
		column.title = api.i18n.text(StringName("result.column." + column.key))
	var rows: Array = result.rankings.duplicate(true)
	for row: Dictionary in rows:
		var team_key: StringName = &"team.solo" if snapshot.solo else (&"team.blue" if row.player_id in snapshot.teams[0] else &"team.red")
		row.metrics.team = api.i18n.text(team_key)
	return {"title": api.i18n.text(&"result.title", {"outcome": outcome}), "rows": rows, "columns": columns}

func _submit_result() -> void:
	if _stopped or _submitted or not api.is_host():
		return
	_submitted = true
	var error: Error = api.finish(_result)
	if error != OK:
		_fail("result_rejected", error_string(error))

func _fail(code: String, message: String) -> void:
	party_stop(&"failed")
	push_error(code + ": " + message)
	api.fail(code, message)

func party_stop(_reason: StringName) -> void:
	_stopped = true
	_playing = false
	set_process(false)
	if is_instance_valid(view):
		view.stop()
		if view.action_requested.is_connected(_send_action):
			view.action_requested.disconnect(_send_action)
	if is_instance_valid(briefing):
		briefing.stop()
	if is_instance_valid(settlement):
		settlement.stop()
	if api.net.message_received.is_connected(_message):
		api.net.message_received.disconnect(_message)
	if api.players_changed.is_connected(_players_changed):
		api.players_changed.disconnect(_players_changed)
