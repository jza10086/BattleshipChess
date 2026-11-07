extends Control
## PartyAPI owns transport and lifecycle; this host owns the game and sends private team views.
const Rules: Script = preload("res://games/minigame/godot_party_default_battleship_chess/battleship_rules.gd")
const BattleView: Script = preload("res://games/minigame/godot_party_default_battleship_chess/battle_view.gd")
const ACTION: StringName = &"battleship/action"
const VIEW: StringName = &"view"
var api: PartyAPI
var request: Dictionary
var model: Rules
@onready var view: BattleView = %BattleView
var snapshot: Dictionary = {}
var _briefing: Control
var _settlement: Control
var _result: Dictionary = {}
var _playing: bool = false
var _stopped: bool = false
var _settling: bool = false
var _submitted: bool = false
var _remaining: float = 60.0
var _target_seconds: int
var _last_second: int = -1
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
	view.set_roster(api.get_players())
	view.action_requested.connect(_send_action)
	var gate_script: Script = api.load_asset({"package_id": api.protocol_id, "resource_key": "briefing_gate"}) as Script
	if gate_script == null:
		_fail("briefing_missing", "原版协议缺少规则准备页面")
		return
	_briefing = gate_script.new()
	var content: Dictionary = gate_script.read_content(get_script().resource_path.get_base_dir().path_join("manifest.json"), api)
	content["controls"] = [{"binding": api.i18n.text(&"controls.mouse"), "description": api.i18n.text(&"controls.primary")},
		{"binding": "Esc", "description": api.i18n.text(&"controls.menu")}]
	_briefing.configure(api, content)
	_briefing.play_requested.connect(_begin_play)
	add_child(_briefing)
	var error: Error = api.mark_ready()
	if error != OK:
		_fail("ready_failed", error_string(error))

func godot_party_graphics_targets() -> Dictionary:
	return {"world": view.world, "sun": view.sun, "materials_root": view.models}

func party_start() -> void:
	_briefing.transport_started()

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
	elif ceili(_remaining) != _last_second:
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
		snapshot = payload.state
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
	_revision += 1
	_last_second = ceili(_remaining)
	var recipients: Array[Dictionary] = api.get_players()
	recipients.append_array(api.get_spectators())
	var result: Dictionary = model.result(request.request_id, api.get_players()) if model.phase == "finished" else {}
	for player: Dictionary in recipients:
		if not player.connected:
			continue
		var state: Dictionary = model.view(player.player_id)
		state["remaining"] = _remaining
		var error: Error = api.net.send_to_player(player.player_id, VIEW,
			{"revision": _revision, "state": state, "result": result})
		if error != OK:
			_fail("view_send_failed", error_string(error))
			return

func _open_settlement(result: Dictionary, impact_time: float) -> void:
	_settling = true
	view.input_enabled = false
	_result = result.duplicate(true)
	if impact_time > 0.0:
		await get_tree().create_timer(impact_time).timeout
		if _stopped or not api.is_open():
			return
	var gate_script: Script = api.load_asset({"package_id": api.protocol_id, "resource_key": "settlement_gate"}) as Script
	if gate_script == null:
		_fail("settlement_missing", "原版协议缺少结算页面")
		return
	_settlement = gate_script.new()
	_settlement.configure(api, _result_presentation(result), request.request_id)
	_settlement.continued.connect(_submit_result)
	add_child(_settlement)

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
	if is_instance_valid(_briefing):
		_briefing.stop()
	if is_instance_valid(_settlement):
		_settlement.stop()
	if api.net.message_received.is_connected(_message):
		api.net.message_received.disconnect(_message)
	if api.players_changed.is_connected(_players_changed):
		api.players_changed.disconnect(_players_changed)
