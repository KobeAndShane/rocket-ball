extends Node
## Networking entry point (Task 10 scaffolding). The core slice runs offline;
## gravity phase ownership already lives on the server/offline authority.

enum Mode { OFFLINE, HOST, CLIENT }

var mode: Mode = Mode.OFFLINE
var server_tick: int = 0
var peer_latency_ms: int = 0
var peer_loss_percent: float = 0.0


func _physics_process(_delta: float) -> void:
	if mode != Mode.OFFLINE:
		server_tick += 1


func is_server() -> bool:
	return mode != Mode.CLIENT


func start_host(port: int = 7777) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	return OK


func start_client(address: String, port: int = 7777) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	return OK


func stop() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	mode = Mode.OFFLINE
