extends Control
## PartyAPI owns transport and lifecycle; this host owns the game and sends private team views.
const Rules: Script = preload("res://games/minigame/godot_party_default_battleship_chess/battleship_rules.gd")
const BattleView: Script = preload("res://games/minigame/godot_party_default_battleship_chess/battle_view.gd")
const ACTION: StringName = &"battleship/action"
const VIEW: StringName = &"view"
var api: PartyAPI
var request: Dictionary
var model: RefCounted
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
var _vote_seconds: int
var _last_second: int = -1
var _revision: int = 0
var _received_revision: int = -1

func party_setup(value: PartyAPI, config: Dictionary) -> void:
	api = value
	request = config.duplicate(true)
	_vote_seconds = api.get_settings().vote_seconds
	api.net.message_received.connect(_message)
	api.players_changed.connect(_players_changed)

func _ready() -> void:
	add_to_group("party_minimal_hud")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if api == null:
		push_error("海战棋需要从派对大厅启动。")
		return
	view.i18n = api.i18n
	view.set_roster(api.get_players())
	view.action_requested.connect(_send_action)
	var gate_script: Script = api.load_asset({"package_id": api.protocol_id, "resource_key": "briefing_gate"}) as Script
	if gate_script == null:
		_fail("briefing_missing", "原版协议缺少规则准备页面")
		return
	_briefing = gate_script.new()
	var content: Dictionary = gate_script.read_content(get_script().resource_path.get_base_dir().path_join("manifest.json"), api)
	content["controls"] = [{"binding": "鼠标左键", "description": "摆放自己的舰船 / 点击敌方地块投票"},
		{"binding": "Esc", "description": "打开派对菜单"}]
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
			model.resolve_vote()
		_remaining = float(_vote_seconds)
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
		if sender.peer_id != 1 or not payload is Dictionary or not payload.get("state") is Dictionary:
			return
		if typeof(payload.get("revision")) != TYPE_INT or payload.revision <= _received_revision:
			return
		_received_revision = payload.revision
		snapshot = payload.state
		var impact_time: float = view.show_state(snapshot)
		if snapshot.phase == "finished" and not _settling:
			_open_settlement(payload.result, impact_time)

func _apply_action(player_id: String, action: Dictionary) -> void:
	var previous_phase: String = model.phase
	if not model.act(player_id, action):
		return
	if previous_phase == "placement" and model.phase == "battle":
		_remaining = float(_vote_seconds)
	elif model.phase == "battle" and model.all_voted():
		model.resolve_vote()
		_remaining = float(_vote_seconds)
	_publish()

func _players_changed() -> void:
	view.i18n = api.i18n
	view.set_roster(api.get_players())
	if not _playing or _settling or _stopped or not api.is_host():
		return
	model.update_connections(api.get_players())
	if model.phase == "battle" and model.all_voted():
		model.resolve_vote()
		_remaining = float(_vote_seconds)
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
	_result = result
	if impact_time > 0.0:
		await get_tree().create_timer(impact_time).timeout
		if _stopped or not api.is_open():
			return
	var gate_script: Script = api.load_asset({"package_id": api.protocol_id, "resource_key": "settlement_gate"}) as Script
	if gate_script == null:
		_fail("settlement_missing", "原版协议缺少结算页面")
		return
	_settlement = gate_script.new()
	_settlement.configure(api, {"title": "海战棋 · " + ("本局取消" if snapshot.winner < 0 else ("测试完成" if snapshot.solo else ("蓝队获胜" if snapshot.winner == 0 else "红队获胜"))),
		"rows": result.rankings}, request.request_id)
	_settlement.continued.connect(_submit_result)
	add_child(_settlement)

func _submit_result() -> void:
	if _stopped or _submitted or not api.is_host():
		return
	_submitted = true
	var error: Error = api.finish(_result)
	if error != OK:
		_fail("result_rejected", error_string(error))

func _fail(code: String, message: String) -> void:
	_stopped = true
	view.input_enabled = false
	push_error(code + ": " + message)
	api.fail(code, message)

func party_stop(_reason: StringName) -> void:
	_stopped = true
	_playing = false
	if is_instance_valid(view):
		view.input_enabled = false
	if is_instance_valid(_briefing):
		_briefing.stop()
	if is_instance_valid(_settlement):
		_settlement.stop()
	if api.net.message_received.is_connected(_message):
		api.net.message_received.disconnect(_message)
	if api.players_changed.is_connected(_players_changed):
		api.players_changed.disconnect(_players_changed)
