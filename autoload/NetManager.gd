extends Node
## Network session owner. Offline play uses the same code paths with a fake peer.
## Task 10 expands prediction/reconciliation; this file owns the session lifecycle.

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal server_started
signal joined_server
signal connection_failed

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 6

var is_offline: bool = true
var is_server: bool = true
var local_peer_id: int = 1
var server_tick: int = 0
var players: Dictionary = {} # peer_id -> {name, team, car_id, ready}
var peer: ENetMultiplayerPeer = null
var simulated_latency_ms: int = 0
var simulated_loss: float = 0.0
var _tick_accum: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _physics_process(delta: float) -> void:
	if is_server and not is_offline:
		_tick_accum += delta
		var tick_rate: float = 60.0
		if _tick_accum >= 1.0 / tick_rate:
			_tick_accum -= 1.0 / tick_rate
			server_tick += 1


func host(port: int = DEFAULT_PORT, max_players: int = MAX_PLAYERS) -> Error:
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_server(port, max_players)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = enet
	peer = enet
	is_offline = false
	is_server = true
	local_peer_id = 1
	players = {1: {"name": Settings.get_setting("net/player_name"), "team": 1, "car_id": 0, "ready": true}}
	Events.network_status_changed.emit("Hosting on port %d" % port)
	server_started.emit()
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = enet
	peer = enet
	is_offline = false
	is_server = false
	Events.network_status_changed.emit("Connecting to %s:%d" % [address, port])
	return OK


func start_offline() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_offline = true
	is_server = true
	local_peer_id = 1
	players = {1: {"name": Settings.get_setting("net/player_name"), "team": 1, "car_id": 0, "ready": true}}
	Events.network_status_changed.emit("Offline")


func leave() -> void:
	if peer != null:
		peer.close()
	peer = null
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_offline = true
	is_server = true
	local_peer_id = 1
	players.clear()
	server_tick = 0
	Events.network_status_changed.emit("Offline")


func _on_peer_connected(id: int) -> void:
	peer_connected.emit(id)
	if is_server:
		Events.player_joined.emit(id, "Pilot %d" % id)


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	peer_disconnected.emit(id)
	Events.player_left.emit(id)


func _on_connected_to_server() -> void:
	local_peer_id = multiplayer.get_unique_id()
	joined_server.emit()
	Events.network_status_changed.emit("Connected as peer %d" % local_peer_id)


func _on_connection_failed() -> void:
	Events.network_status_changed.emit("Connection failed")
	connection_failed.emit()


func _on_server_disconnected() -> void:
	leave()


func set_simulated_network(latency_ms: int, loss: float) -> void:
	simulated_latency_ms = clampi(latency_ms, 0, 1000)
	simulated_loss = clampf(loss, 0.0, 1.0)


func should_drop_packet() -> bool:
	return simulated_loss > 0.0 and _rng.randf() < simulated_loss


func latency_seconds() -> float:
	return float(simulated_latency_ms) / 1000.0
