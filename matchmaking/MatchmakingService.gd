extends Node
## Server-authoritative matchmaking facade.
##
## The matcher itself is transport agnostic (Matchmaker). In a production build
## it would run behind an HTTP/WebSocket backend; locally the host fills spare
## seats with a synthetic population so the complete queue -> match flow can be
## exercised offline and in automated tests.

signal queue_changed
signal queue_progress(elapsed: float, queue_size: int)
signal match_found(match_info: Dictionary)
signal queue_cancelled

const TICK_INTERVAL := 0.5
const SYNTHETIC_POPULATION := 240
const SYNTHETIC_SPREAD := 180.0
const TARGET_WAIT := 30.0

var matcher: Matchmaker = Matchmaker.new()
var in_queue: bool = false
var remote_pending: bool = false
var mode: String = ""
var region: String = "auto"
var party_rule: String = "avg"
var max_ping: int = 120
var team_size: int = 3
var elapsed: float = 0.0
var local_entry_id: int = 0
var local_team_index: int = 0
var last_match: Dictionary = {}
var synthetic_count: int = 0

var _tick_accum: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	_rng.randomize()
	Events.settings_changed.connect(_on_settings_changed)
	NetManager.match_started.connect(_on_match_started)
	_apply_settings()


func _on_settings_changed(key: String, _value: Variant) -> void:
	if key == "*" or key.begins_with("net/") or key.begins_with("game/"):
		_apply_settings()


func refresh_settings() -> void:
	_apply_settings()


func _apply_settings() -> void:
	region = str(Settings.get_setting("net/region"))
	var rule: String = str(Settings.get_setting("net/mmr_rule"))
	party_rule = rule if rule == "max" else "avg"
	max_ping = clampi(Settings.get_int("net/max_ping"), 20, 300)
	team_size = clampi(Settings.get_int("game/team_size"), 1, 3)


func _on_match_started(_rules_data: Dictionary) -> void:
	# A match start supersedes any local queue state (host or listened client).
	if in_queue:
		_reset_queue()
		queue_changed.emit()


func queue_ranked() -> bool:
	return queue("ranked")


func queue_casual() -> bool:
	return queue("casual")


## `party_mmrs` is the local party's list of ratings. Empty means solo. In a
## hosted session connected peers are queued alongside the local player.
func queue(mode_name: String, party_mmrs: Array[float] = []) -> bool:
	if in_queue:
		return false
	if mode_name != "ranked" and mode_name != "casual":
		return false
	if not Meta.can_queue():
		Events.notification.emit("Queue locked for %d more seconds" % int(ceil(Meta.leaver_cooldown_remaining())))
		return false
	_apply_settings()
	mode = mode_name
	elapsed = 0.0
	_tick_accum = 0.0
	remote_pending = false
	if not NetManager.is_server and not NetManager.is_offline:
		# Clients ask the host to run the search; host match-start arrives over
		# the normal reliable match event channel.
		if multiplayer.has_multiplayer_peer():
			_rpc_request_queue.rpc_id(1, mode_name)
		remote_pending = true
		in_queue = true
		set_process(true)
		queue_changed.emit()
		return true
	matcher.clear()
	synthetic_count = 0
	var mmr: float = float(Meta.profile.get("mmr", 1000.0))
	var rd: float = float(Meta.profile.get("rd", 350.0))
	var local_party: Array[float] = party_mmrs
	if local_party.is_empty():
		local_party = [mmr]
	local_entry_id = matcher.enqueue({
		"mmr": mmr,
		"rd": rd,
		"party_size": local_party.size(),
		"party_mmrs": local_party,
		"region": region,
		"ping": 0,
		"joined": 0.0,
		"kind": "local",
	})
	var humans: int = 1
	if not NetManager.is_offline and NetManager.is_server:
		for peer_id: int in NetManager.players.keys():
			if peer_id == NetManager.local_peer_id:
				continue
			matcher.enqueue({
				"mmr": mmr + _rng.randf_range(-120.0, 120.0),
				"rd": 200.0,
				"party_size": 1,
				"party_mmrs": [],
				"region": region,
				"ping": 25,
				"joined": 0.0,
				"kind": "peer",
				"peer_id": peer_id,
			})
			humans += 1
	var required: int = team_size * 2
	if matcher.size() < required:
		_spawn_synthetic(required - matcher.size() + SYNTHETIC_POPULATION, mmr)
	in_queue = true
	set_process(true)
	Events.network_status_changed.emit("Searching %s %dv%d" % [mode_name, team_size, team_size])
	queue_changed.emit()
	return true


## Host-side entry point when a client requests matchmaking.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_queue(mode_name: String) -> void:
	if not NetManager.is_server or in_queue:
		return
	if not multiplayer.has_multiplayer_peer():
		return
	queue(mode_name)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_cancel_queue() -> void:
	if not NetManager.is_server:
		return
	cancel()


func cancel(silent: bool = false) -> void:
	if not in_queue:
		return
	if remote_pending and multiplayer.has_multiplayer_peer():
		_rpc_cancel_queue.rpc_id(1)
	_reset_queue()
	set_process(false)
	Events.network_status_changed.emit("Matchmaking cancelled")
	if not silent:
		queue_cancelled.emit()
	queue_changed.emit()


func _reset_queue() -> void:
	in_queue = false
	remote_pending = false
	elapsed = 0.0
	_tick_accum = 0.0
	matcher.clear()
	synthetic_count = 0
	local_entry_id = 0


func _process(delta: float) -> void:
	if not in_queue:
		set_process(false)
		return
	elapsed += delta
	if remote_pending:
		queue_progress.emit(elapsed, 0)
		return
	_tick_accum += delta
	if _tick_accum < TICK_INTERVAL:
		return
	_tick_accum = 0.0
	_form_matches()
	if in_queue:
		queue_progress.emit(elapsed, matcher.size())


## Runs one search step immediately. Used by tests and the debug overlay.
func tick_now() -> void:
	if not in_queue or remote_pending:
		return
	_tick_accum = 0.0
	_form_matches()
	if in_queue:
		queue_progress.emit(elapsed, matcher.size())


func _form_matches() -> void:
	var batch: Array[Dictionary] = matcher.tick(elapsed, team_size, region, max_ping, party_rule, mode)
	for info: Dictionary in batch:
		var players: Array = info.get("players", [])
		if not players.has(local_entry_id):
			continue
		for team_idx in 2:
			var team: Array = info.get("teams", [[], []])[team_idx]
			if team.has(local_entry_id):
				local_team_index = team_idx
				break
		info["local_team"] = local_team_index
		info["local_entry"] = local_entry_id
		info["ranked"] = mode == "ranked"
		info["team_size"] = team_size
		info["target_wait"] = TARGET_WAIT
		info["party_rule"] = party_rule
		last_match = info.duplicate(true)
		_reset_queue()
		set_process(false)
		Events.network_status_changed.emit("Match found")
		match_found.emit(info)
		return


## Queue filler players around the local rating so a solo player always finds a
## nearby lobby quickly. Region and ping are varied to exercise filtering.
func _spawn_synthetic(count: int, centre_mmr: float) -> void:
	var regions: Array[String] = ["eu", "na", "asia", "sa", "oce"]
	var target_region: String = region if region != "" and region != "auto" else regions[_rng.randi_range(0, regions.size() - 1)]
	for i in count:
		var pmmr: float = clampf(centre_mmr + _rng.randfn(0.0, SYNTHETIC_SPREAD), 0.0, Glicko2.MAX_RATING)
		var party_size: int = 1
		var roll: float = _rng.randf()
		if roll > 0.95:
			party_size = 3
		elif roll > 0.86:
			party_size = 2
		var party: Array[float] = []
		var spread: float = _rng.randf_range(20.0, 70.0)
		for j in party_size:
			party.append(clampf(pmmr + _rng.randfn(0.0, spread), 0.0, Glicko2.MAX_RATING))
		matcher.enqueue({
			"mmr": pmmr,
			"rd": _rng.randf_range(70.0, 350.0),
			"party_size": party_size,
			"party_mmrs": party,
			"region": target_region,
			"ping": _rng.randi_range(12, 95),
			"joined": 0.0,
			"kind": "synthetic",
		})
		synthetic_count += 1


func queue_size() -> int:
	return matcher.size()


func estimated_wait() -> float:
	# Window growth is 20 MMR/s; a wider local spread means a faster match.
	var spread: float = 0.0
	if not last_match.is_empty():
		spread = float(last_match.get("spread", 0.0))
	return maxf(2.0, TARGET_WAIT - elapsed + spread * 0.02)


func status_text() -> String:
	if not in_queue:
		return "Idle"
	if remote_pending:
		return "Waiting for host...  %ds" % int(elapsed)
	return "%s  %dv%d   %ds   queue %d   region %s   +/-%d" % [
		mode.capitalize(),
		team_size,
		team_size,
		int(elapsed),
		matcher.size(),
		region.to_upper(),
		int(Matchmaker.BASE_WINDOW_RANKED + Matchmaker.WINDOW_GROWTH * elapsed),
	]
