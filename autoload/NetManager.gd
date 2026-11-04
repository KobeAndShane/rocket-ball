extends Node
## Network session owner and server-authoritative transport.
##
## Offline play uses the same code paths with an OfflineMultiplayerPeer. Clients
## send tick-stamped inputs (with two redundant previous inputs) at physics rate;
## the server simulates and broadcasts quantised snapshots at 60 Hz.

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal server_started
signal joined_server
signal connection_failed
signal snapshot_received(snapshot: Dictionary)
signal lobby_changed
signal match_started(rules_data: Dictionary)
signal match_event(kind: String, payload: Dictionary)
signal peer_takeover(peer_id: int)

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 6
const TICK_RATE := 120.0
const SNAPSHOT_RATE := 60.0
const INPUT_RATE_LIMIT := 160.0
const RECONNECT_GRACE := 10.0

var is_offline: bool = true
var is_server: bool = true
var dedicated_server: bool = false
var local_peer_id: int = 1
var server_tick: int = 0
var team_size: int = 3
var players: Dictionary = {} # peer_id -> {name, team, car_id, ready, party}
var cars: Dictionary = {} # car_id -> Car
var party: Array[int] = []
var current_match_rules: Dictionary = {}
var peer: ENetMultiplayerPeer = null
var simulated_latency_ms: int = 0
var simulated_loss: float = 0.0

var _local_tick: int = 0
var _tick_offset: float = 0.0
var _tick_accum: float = 0.0
var _rng := RandomNumberGenerator.new()
var _buffers: Dictionary = {} # car_id -> InputBuffer
var _input_counts: Dictionary = {} # peer_id -> [window_start_ms, count]
var _pending_out: Array[Dictionary] = []
var _disconnect_timers: Dictionary = {} # peer_id -> seconds
var _bytes_in: int = 0
var _bytes_out: int = 0


func _ready() -> void:
	_rng.randomize()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	Events.settings_changed.connect(_on_settings_changed)
	Events.cosmetics_changed.connect(_on_cosmetics_changed)
	_on_settings_changed("", null)
	_parse_cmdline()


func _on_settings_changed(key: String, _value: Variant) -> void:
	if key == "net/test_latency" or key == "*":
		simulated_latency_ms = Settings.get_int("net/test_latency")
	if key == "net/test_loss" or key == "*":
		simulated_loss = clampf(Settings.get_float("net/test_loss") / 100.0, 0.0, 1.0)
	if key.begins_with("net/"):
		simulated_latency_ms = clampi(Settings.get_int("net/test_latency"), 0, 1000)
		simulated_loss = clampf(Settings.get_float("net/test_loss") / 100.0, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	_local_tick += 1
	if is_server:
		server_tick = _local_tick
	elif not is_offline:
		var estimate: int = _local_tick + int(round(_tick_offset))
		server_tick = maxi(server_tick, estimate)
	else:
		server_tick = _local_tick
	if is_server and not is_offline:
		_tick_accum += delta
		var step: float = 1.0 / TICK_RATE
		while _tick_accum >= step:
			_tick_accum -= step
	_flush_out()
	for peer_id: int in _disconnect_timers.keys():
		_disconnect_timers[peer_id] = float(_disconnect_timers[peer_id]) - delta
		if float(_disconnect_timers[peer_id]) <= 0.0:
			_disconnect_timers.erase(peer_id)
			Events.announce.emit("Player %d disconnected; bot takeover" % peer_id)
			peer_takeover.emit(peer_id)


func _parse_cmdline() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	var port: int = DEFAULT_PORT
	for arg: String in args:
		if arg == "--server" or arg == "--dedicated-server":
			dedicated_server = true
		elif arg.begins_with("--port="):
			port = int(arg.get_slice("=", 1))
	if dedicated_server:
		team_size = 3
		host(port)
		Events.network_status_changed.emit("Dedicated server on port %d" % port)


# --- Session lifecycle -------------------------------------------------------

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
	_reset_clock()
	players = {1: _player_entry(0, 1, true, Meta.profile.get("loadout", {}))}
	cars.clear()
	_buffers.clear()
	party = [1]
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
	_reset_clock()
	Events.network_status_changed.emit("Connecting to %s:%d" % [address, port])
	return OK


func start_offline() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_offline = true
	is_server = true
	local_peer_id = 1
	_reset_clock()
	players = {1: _player_entry(0, 1, true, Meta.profile.get("loadout", {}))}
	cars.clear()
	_buffers.clear()
	party = [1]
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
	cars.clear()
	_buffers.clear()
	party.clear()
	_reset_clock()
	Events.network_status_changed.emit("Offline")


func _reset_clock() -> void:
	server_tick = 0
	_local_tick = 0
	_tick_offset = 0.0
	_tick_accum = 0.0


func _player_entry(car_id: int, team: int, ready: bool, loadout: Dictionary = {}) -> Dictionary:
	var clean: Dictionary = CosmeticLibrary.sanitize_loadout(loadout)
	return {
		"name": str(Settings.get_setting("net/player_name")),
		"team": team,
		"car_id": car_id,
		"ready": ready,
		"party": "",
		"loadout": clean,
	}


# --- Lobby / party -----------------------------------------------------------

func set_ready(peer_id: int, ready: bool) -> void:
	if not players.has(peer_id):
		return
	players[peer_id]["ready"] = ready
	Events.lobby_changed.emit()
	lobby_changed.emit()
	if is_server:
		rpc("_rpc_lobby", players)
	_ready_check()


func is_lobby_ready() -> bool:
	if players.size() < 2:
		return false
	for id: int in players.keys():
		if not bool(players[id].get("ready", false)):
			return false
	return true


func _ready_check() -> void:
	if is_server and is_lobby_ready():
		Events.network_status_changed.emit("Lobby ready")


## Keep the lobby roster's cosmetic loadouts in sync. Clients notify the host,
## which rebroadcasts the roster so every peer renders the same cars.
func _on_cosmetics_changed() -> void:
	if is_offline:
		return
	var loadout: Dictionary = CosmeticLibrary.sanitize_loadout(Meta.profile.get("loadout", {}))
	if players.has(local_peer_id):
		players[local_peer_id]["loadout"] = loadout
	if is_server:
		rpc("_rpc_lobby", players)
	else:
		rpc_id(1, "_rpc_set_loadout", loadout)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_loadout(loadout: Dictionary) -> void:
	if not is_server:
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not players.has(sender):
		return
	players[sender]["loadout"] = CosmeticLibrary.sanitize_loadout(loadout)
	Events.lobby_changed.emit()
	lobby_changed.emit()
	rpc("_rpc_lobby", players)


func local_loadout() -> Dictionary:
	return CosmeticLibrary.sanitize_loadout(Meta.profile.get("loadout", {}))


## Resolve the loadout a car should render with, preferring the lobby roster so
## remote clients see each other's equipped cosmetics.
func loadout_for_car(car_id: int) -> Dictionary:
	var peer_id: int = peer_for_car(car_id)
	if peer_id > 0 and players.has(peer_id):
		return CosmeticLibrary.sanitize_loadout(players[peer_id].get("loadout", {}))
	if car_id == local_car_id() or is_offline:
		return local_loadout()
	return CosmeticLibrary.default_loadout()


func invite(peer_id: int) -> bool:
	if is_server and players.has(peer_id):
		if not party.has(peer_id):
			party.append(peer_id)
		players[peer_id]["party"] = local_peer_id
		Events.notification.emit("Invited peer %d" % peer_id)
		return true
	return false


func invite_all() -> int:
	if not is_server:
		return 0
	var count: int = 0
	for peer_id: int in players.keys():
		if peer_id == local_peer_id:
			continue
		if invite(peer_id):
			count += 1
	return count


func party_mmr() -> float:
	# Party matchmaking uses average MMR; local profile is the only real one.
	if party.size() <= 1:
		return float(Meta.profile.get("mmr", 1000.0))
	return float(Meta.profile.get("mmr", 1000.0))


func report_disconnect(_peer_id: int) -> void:
	Meta.profile["leaver_count"] = int(Meta.profile.get("leaver_count", 0)) + 1
	Meta.save_profile()


# --- Registration / state ----------------------------------------------------

func register_car(car: Car) -> void:
	if car == null:
		return
	cars[car.car_id] = car
	if not _buffers.has(car.car_id):
		_buffers[car.car_id] = InputBuffer.new()


func unregister_all() -> void:
	cars.clear()
	_buffers.clear()


func get_car(car_id: int) -> Car:
	return cars.get(car_id) as Car


func local_car_id() -> int:
	if players.has(local_peer_id):
		return int(players[local_peer_id]["car_id"])
	return 0


# --- Inputs (client -> server) ----------------------------------------------

func send_inputs(car_id: int, inputs: Array[CarInput]) -> void:
	if is_offline:
		return
	if is_server:
		_apply_inputs(car_id, inputs)
		return
	var data := InputBuffer.pack(inputs)
	_bytes_out += data.size()
	_dispatch("_rpc_inputs", [car_id, data])


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_inputs(car_id: int, data: PackedByteArray) -> void:
	if not is_server:
		return
	_bytes_in += data.size()
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 0 and players.has(sender):
		var expected: int = int(players[sender]["car_id"])
		if expected != car_id:
			return
	if not _allow_input(sender):
		return
	var inputs := InputBuffer.unpack(data)
	_apply_inputs(car_id, inputs)


func _apply_inputs(car_id: int, inputs: Array[CarInput]) -> void:
	var car := get_car(car_id)
	if car == null:
		return
	var buffer: InputBuffer = _buffers.get(car_id, null)
	if buffer == null:
		buffer = InputBuffer.new()
		_buffers[car_id] = buffer
	for input: CarInput in inputs:
		_sanitise_input(car, input)
		buffer.push(input)
	for input: CarInput in buffer.consume_new():
		car.apply_input(input)
	_validate_car(car)


## Server-side sanity clamps. Never trust a client's reported velocity.
func _validate_car(car: Car) -> void:
	if car == null or car.tuning == null:
		return
	var cap: float = car.tuning.boost_max_speed * 1.2
	if car.linear_velocity.length() > cap:
		car.linear_velocity = car.linear_velocity.normalized() * cap
	if car.angular_velocity.length() > car.tuning.max_angular_speed * 1.2:
		car.angular_velocity = car.angular_velocity.normalized() * car.tuning.max_angular_speed * 1.2


func _sanitise_input(car: Car, input: CarInput) -> void:
	input.throttle = clampf(input.throttle, -1.0, 1.0)
	input.steer = clampf(input.steer, -1.0, 1.0)
	input.pitch = clampf(input.pitch, -1.0, 1.0)
	input.yaw = clampf(input.yaw, -1.0, 1.0)
	input.roll = clampf(input.roll, -1.0, 1.0)
	if input.boost and (car.boost_component == null or car.boost_component.amount <= 0.0):
		input.boost = false
	if car.state == Car.State.DEMOLISHED:
		input.clear_edges()


func _allow_input(peer_id: int) -> bool:
	if simulated_loss > 0.0 and _rng.randf() < simulated_loss:
		return false
	var now: int = Time.get_ticks_msec()
	if not _input_counts.has(peer_id):
		_input_counts[peer_id] = [now, 0]
	var entry: Array = _input_counts[peer_id]
	if now - int(entry[0]) >= 1000:
		entry[0] = now
		entry[1] = 0
	entry[1] = int(entry[1]) + 1
	return int(entry[1]) <= int(INPUT_RATE_LIMIT)


# --- Snapshots (server -> clients) ------------------------------------------

func broadcast_snapshot(car_list: Array, ball: Ball, phase: int, meta: Dictionary = {}) -> void:
	if not is_server or is_offline:
		return
	if should_drop_packet():
		return
	var data := SnapshotCodec.encode(server_tick, phase, car_list, ball, meta)
	_bytes_out += data.size()
	_dispatch("_rpc_snapshot", [data])


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_snapshot(data: PackedByteArray) -> void:
	if is_server:
		return
	if simulated_loss > 0.0 and _rng.randf() < simulated_loss:
		return
	_bytes_in += data.size()
	var snapshot := SnapshotCodec.decode(data)
	if snapshot.is_empty():
		return
	_update_clock_from_snapshot(int(snapshot["tick"]))
	snapshot_received.emit(snapshot)


## Keep the local estimate of the server clock monotonic while absorbing the
## snapshot's authoritative tick. The one-way delay is subtracted per frame by
## predicting the server's current tick, not the tick at send time.
func _update_clock_from_snapshot(remote_tick: int) -> void:
	var one_way_ms: float = float(simulated_latency_ms) if simulated_latency_ms > 0 else float(get_ping_ms()) * 0.5
	var travel_ticks: int = int(round(one_way_ms / 1000.0 * TICK_RATE))
	var estimate: float = float(remote_tick + travel_ticks - _local_tick)
	_tick_offset = lerpf(_tick_offset, estimate, 0.35)
	server_tick = maxi(server_tick, _local_tick + int(round(_tick_offset)))


# --- Match events (server -> clients) ---------------------------------------

func broadcast_match_start(rules_data: Dictionary) -> void:
	current_match_rules = rules_data.duplicate(true)
	if not is_server or is_offline:
		return
	rpc("_rpc_match_start", rules_data)


func send_match_start_to(peer_id: int, rules_data: Dictionary) -> void:
	if not is_server or is_offline:
		return
	rpc_id(peer_id, "_rpc_match_start", rules_data)


@rpc("authority", "call_remote", "reliable")
func _rpc_match_start(rules_data: Dictionary) -> void:
	match_started.emit(rules_data)


func broadcast_event(kind: String, payload: Dictionary = {}) -> void:
	if not is_server or is_offline:
		return
	_dispatch("_rpc_match_event", [kind, payload])


@rpc("authority", "call_remote", "reliable")
func _rpc_match_event(kind: String, payload: Dictionary) -> void:
	match_event.emit(kind, payload)


func _dispatch(method: String, args: Array) -> void:
	if simulated_latency_ms > 0:
		_pending_out.append({
			"due": Time.get_ticks_msec() + simulated_latency_ms,
			"method": method,
			"args": args,
		})
		return
	_emit_rpc(method, args)


func _flush_out() -> void:
	if _pending_out.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var remaining: Array[Dictionary] = []
	for packet: Dictionary in _pending_out:
		if int(packet["due"]) <= now:
			_emit_rpc(str(packet["method"]), packet["args"] as Array)
		else:
			remaining.append(packet)
	_pending_out = remaining


func _emit_rpc(method: String, args: Array) -> void:
	match method:
		"_rpc_inputs":
			rpc("_rpc_inputs", int(args[0]), args[1] as PackedByteArray)
		"_rpc_snapshot":
			rpc("_rpc_snapshot", args[0] as PackedByteArray)
		"_rpc_lobby":
			rpc("_rpc_lobby", args[0] as Dictionary)
		"_rpc_match_event":
			rpc("_rpc_match_event", str(args[0]), args[1] as Dictionary)


@rpc("authority", "call_remote", "reliable")
func _rpc_lobby(lobby: Dictionary) -> void:
	players = lobby
	Events.lobby_changed.emit()
	lobby_changed.emit()


# --- Diagnostics -------------------------------------------------------------

func set_simulated_network(latency_ms: int, loss: float) -> void:
	simulated_latency_ms = clampi(latency_ms, 0, 1000)
	simulated_loss = clampf(loss, 0.0, 1.0)


func should_drop_packet() -> bool:
	return simulated_loss > 0.0 and _rng.randf() < simulated_loss


func latency_seconds() -> float:
	return float(simulated_latency_ms) / 1000.0


func get_ping_ms() -> int:
	if simulated_latency_ms > 0:
		return simulated_latency_ms
	if is_offline:
		return 0
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		var ids: PackedInt32Array = multiplayer.get_peers()
		if not ids.is_empty():
			var packet_peer := enet.get_peer(ids[0])
			if packet_peer != null:
				return int(packet_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
	return 0


func get_packet_loss() -> float:
	if simulated_loss > 0.0:
		return simulated_loss
	if is_offline:
		return 0.0
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		var ids: PackedInt32Array = multiplayer.get_peers()
		if not ids.is_empty():
			var packet_peer := enet.get_peer(ids[0])
			if packet_peer != null:
				return packet_peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS)
	return 0.0


func bandwidth_bytes() -> Vector2i:
	return Vector2i(_bytes_in, _bytes_out)


# --- Peer events -------------------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if is_server:
		if players.size() >= MAX_PLAYERS:
			return
		var next_car: int = 0
		while _car_id_in_use(next_car):
			next_car += 1
		var team: int = 1 if next_car < maxi(team_size, 1) else 2
		players[id] = _player_entry(next_car, team, false)
		players[id]["name"] = "Pilot %d" % id
		rpc("_rpc_lobby", players)
		Events.lobby_changed.emit()
		lobby_changed.emit()
		Events.player_joined.emit(id, str(players[id]["name"]))
	peer_connected.emit(id)


func _car_id_in_use(car_id: int) -> bool:
	for peer_id: int in players.keys():
		if int(players[peer_id].get("car_id", -1)) == car_id:
			return true
	return false


func peer_for_car(car_id: int) -> int:
	for peer_id: int in players.keys():
		if int(players[peer_id].get("car_id", -1)) == car_id:
			return peer_id
	return 0


func team_for_local() -> int:
	if players.has(local_peer_id):
		return int(players[local_peer_id].get("team", 1))
	return 1


func _on_peer_disconnected(id: int) -> void:
	if is_server and players.has(id):
		_disconnect_timers[id] = RECONNECT_GRACE
		players[id]["ready"] = false
	cars.erase(int(players.get(id, {}).get("car_id", -1)))
	peer_disconnected.emit(id)
	Events.player_left.emit(id)


func _on_connected_to_server() -> void:
	local_peer_id = multiplayer.get_unique_id()
	joined_server.emit()
	rpc_id(1, "_rpc_set_loadout", local_loadout())
	Events.network_status_changed.emit("Connected as peer %d" % local_peer_id)


func _on_connection_failed() -> void:
	Events.network_status_changed.emit("Connection failed")
	connection_failed.emit()


func _on_server_disconnected() -> void:
	leave()
