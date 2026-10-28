class_name BattleNetwork
extends Node

## The host alone owns the referee. Clients submit intentions, never identities or results.
## Each recipient gets a separately built, private snapshot (no generic full-state RPC).
signal changed(state: Dictionary)
signal notice(message: String)
signal disconnected(message: String)

const Rules = preload("res://scripts/rules.gd")
const PROTOCOL := 1
const DEFAULT_PORT := 17777
const CONNECT_TIMEOUT_MS := 9000

var state: Dictionary = {}
var connected := false
var is_host := false
var opponent_present := false
var referee: BattleRules
var enet: ENetMultiplayerPeer
var port := DEFAULT_PORT
var _guest_id := 0
var _connecting := false
var _started_at := 0
var _pending: Dictionary = {}
var _rejecting: Dictionary = {}
var _limits: Dictionary = {}
var _generation := 0

func _init() -> void:
	name = "BattleNetwork"

func _ready() -> void:
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(_connected_to_server)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_disconnected)
	multiplayer.server_relay = false
	multiplayer.allow_object_decoding = false

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _connecting and now - _started_at > CONNECT_TIMEOUT_MS:
		_end_connection("连接超时，请检查房主 IP、端口与 UDP 网络。")
	if is_host and connected:
		for id in _pending.keys():
			if now - int(_pending[id]) > CONNECT_TIMEOUT_MS:
				_reject(int(id), "连接验证超时，请重新加入。")

static func _valid_port(value: int) -> bool:
	return value >= 1024 and value <= 65535

func host(room_port: int = DEFAULT_PORT) -> Error:
	if not _valid_port(room_port):
		notice.emit("端口请填写 1024 至 65535。")
		return ERR_INVALID_PARAMETER
	leave()
	var peer := ENetMultiplayerPeer.new()
	# Transport-only capacity allows an explicit room-full rejection. Only one guest is admitted.
	var err := peer.create_server(room_port, 4, 1)
	if err != OK:
		notice.emit("无法创建房间，请检查端口是否已被占用。")
		return err
	enet = peer
	multiplayer.multiplayer_peer = enet
	port = room_port
	is_host = true
	connected = true
	referee = Rules.new()
	_publish()
	return OK

func join(address: String, room_port: int = DEFAULT_PORT) -> Error:
	var clean := address.strip_edges()
	if not _valid_port(room_port) or clean.is_empty() or clean.length() > 253 or " " in clean or "\n" in clean:
		notice.emit("请填写房主 IP 和有效端口。")
		return ERR_INVALID_PARAMETER
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(clean, room_port, 1)
	if err != OK:
		notice.emit("无法连接，请检查房主 IP 与端口。")
		return err
	enet = peer
	multiplayer.multiplayer_peer = enet
	port = room_port
	_connecting = true
	_started_at = Time.get_ticks_msec()
	notice.emit("正在连接房主…")
	return OK

func leave() -> void:
	_generation += 1
	connected = false
	opponent_present = false
	is_host = false
	_connecting = false
	_guest_id = 0
	_pending.clear()
	_rejecting.clear()
	_limits.clear()
	if enet != null:
		enet.close()
	enet = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	referee = null
	state = {}
	changed.emit(state)

func ready_fleet(fleet: Array) -> void:
	if not connected:
		return
	if is_host:
		if referee.submit_fleet(0, fleet):
			_publish()
		else:
			notice.emit("舰队布局无效，或你已准备就绪。")
	else:
		_request.rpc_id(1, ["ready", fleet])

func shoot(x: int, y: int) -> void:
	if not connected:
		return
	if is_host:
		if opponent_present and referee.fire(0, x, y):
			_publish()
	else:
		_request.rpc_id(1, ["fire", x, y])

func vote_rematch() -> void:
	if not connected or not opponent_present:
		return
	if is_host:
		if referee.rematch(0):
			_publish()
	else:
		_request.rpc_id(1, ["rematch"])

func _publish() -> void:
	if not is_host or referee == null:
		return
	state = referee.snapshot(0)
	state["opponent_present"] = opponent_present
	changed.emit(state)
	if _guest_id != 0 and opponent_present:
		var private_state: Dictionary = referee.snapshot(1)
		private_state["opponent_present"] = true
		_receive_state.rpc_id(_guest_id, private_state)

func _peer_connected(id: int) -> void:
	if not is_host:
		return
	_pending[id] = Time.get_ticks_msec()
	var remote := enet.get_peer(id)
	if remote != null:
		remote.set_timeout(8, 3000, 8000)
	if _guest_id != 0 or referee.phase != "placement":
		_reject(id, "房间已满：海战棋需要两位舰长。")

func _peer_disconnected(id: int) -> void:
	if not is_host:
		return
	_pending.erase(id)
	_rejecting.erase(id)
	_limits.erase(id)
	if id != _guest_id:
		return
	_guest_id = 0
	opponent_present = false
	# A departure cancels the match; a new guest can never inherit a prior player's fleet.
	referee.reset()
	_publish()
	notice.emit("对方已离开，本局结束。等待新的舰长加入。")

func _connected_to_server() -> void:
	if not _connecting or is_host:
		return
	var remote := enet.get_peer(1)
	if remote != null:
		remote.set_timeout(8, 3000, 8000)
	_hello.rpc_id(1, PROTOCOL)

func _connection_failed() -> void:
	if _connecting:
		_end_connection("连接失败，请检查房主 IP、UDP 端口和网络。")

func _server_disconnected() -> void:
	if connected or _connecting:
		_end_connection("房主已离开或连接中断，本局结束。")

func _end_connection(message: String) -> void:
	leave()
	notice.emit(message)
	disconnected.emit(message)

func _reject(id: int, message: String) -> void:
	if _rejecting.has(id) or enet == null:
		return
	_rejecting[id] = true
	_rejected.rpc_id(id, message)
	var generation := _generation
	await get_tree().create_timer(0.25).timeout
	if generation == _generation and enet != null and is_host:
		if multiplayer.get_peers().has(id):
			enet.disconnect_peer(id)
		_pending.erase(id)
		_rejecting.erase(id)

func _allow(id: int) -> bool:
	var now := Time.get_ticks_msec()
	var bucket: Dictionary = _limits.get(id, {"tokens": 24.0, "time": now})
	bucket.tokens = minf(24.0, float(bucket.tokens) + float(now - int(bucket.time)) * 0.012)
	bucket.time = now
	if float(bucket.tokens) < 1.0:
		_limits[id] = bucket
		return false
	bucket.tokens -= 1.0
	_limits[id] = bucket
	return true

@rpc("any_peer", "call_remote", "reliable")
func _hello(protocol: Variant) -> void:
	if not is_host or not connected:
		return
	var id := multiplayer.get_remote_sender_id()
	if not _pending.has(id) or _rejecting.has(id):
		return
	if typeof(protocol) != TYPE_INT or protocol != PROTOCOL:
		_reject(id, "游戏版本不同，请使用相同版本。")
		return
	if _guest_id != 0 or referee.phase != "placement":
		_reject(id, "房间已满：海战棋需要两位舰长。")
		return
	_guest_id = id
	_pending.erase(id)
	opponent_present = true
	_welcome.rpc_id(id, PROTOCOL)
	_publish()
	notice.emit("另一位舰长已加入，准备好后即可开战。")

@rpc("any_peer", "call_remote", "reliable")
func _request(payload: Variant) -> void:
	if not is_host or not connected or not opponent_present:
		return
	var id := multiplayer.get_remote_sender_id()
	if id != _guest_id or not _allow(id):
		return
	if typeof(payload) != TYPE_ARRAY or payload.is_empty() or payload.size() > 3 or typeof(payload[0]) != TYPE_STRING:
		return
	var changed_rules := false
	match payload[0]:
		"ready":
			if payload.size() == 2 and typeof(payload[1]) == TYPE_ARRAY:
				changed_rules = referee.submit_fleet(1, payload[1])
		"fire":
			if payload.size() == 3 and typeof(payload[1]) == TYPE_INT and typeof(payload[2]) == TYPE_INT:
				changed_rules = referee.fire(1, payload[1], payload[2])
		"rematch":
			if payload.size() == 1:
				changed_rules = referee.rematch(1)
	if changed_rules:
		_publish()

@rpc("authority", "call_remote", "reliable")
func _welcome(protocol: int) -> void:
	if is_host or not _connecting or multiplayer.get_remote_sender_id() != 1:
		return
	if protocol != PROTOCOL:
		_end_connection("游戏版本不同，请使用相同版本。")
		return
	_connecting = false
	connected = true
	opponent_present = true
	notice.emit("已加入海域，请部署你的舰队。")

@rpc("authority", "call_remote", "reliable")
func _receive_state(private_state: Dictionary) -> void:
	if is_host or not connected or multiplayer.get_remote_sender_id() != 1:
		return
	state = private_state
	opponent_present = bool(state.get("opponent_present", false))
	changed.emit(state)

@rpc("authority", "call_remote", "reliable")
func _rejected(message: String) -> void:
	if not is_host and (connected or _connecting) and multiplayer.get_remote_sender_id() == 1:
		_end_connection(message)
