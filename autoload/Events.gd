extends Node
## Global signal bus. Systems emit here; consumers connect here.
## Keep this file free of gameplay logic so it stays a stable contract.

# --- Match -------------------------------------------------------------------
signal match_state_changed(state: int, previous_state: int)
signal countdown_changed(value: int)
signal timer_changed(seconds_left: float)
signal score_changed(team1: int, team2: int)
signal goal_scored(team: int, scorer_id: int)
signal goal_cleared
signal match_ended(team1_score: int, team2_score: int, winner: int)
signal stats_updated(stats: Dictionary)
signal overtime_started

# --- Gravity -----------------------------------------------------------------
signal gravity_shift_warning(seconds_left: float, next_dir: Vector3)
signal gravity_shift_started(from_dir: Vector3, to_dir: Vector3, duration: float)
signal gravity_shift_finished(phase_index: int)
signal gravity_changed(direction: Vector3)

# --- Cars / ball -------------------------------------------------------------
signal boost_changed(car_id: int, amount: float)
signal boost_pulse(car_id: int, amount: float)
signal car_state_changed(car_id: int, state: int)
signal car_demolished(victim_id: int, attacker_id: int)
signal car_respawned(car_id: int)
signal ball_hit(strength: float, position: Vector3, hitter_id: int)
signal shot_taken(car_id: int)
signal save_made(car_id: int)
signal ball_reset
signal pad_collected(pad_id: int, car_id: int)
signal pad_respawned(pad_id: int)

# --- UI / meta ---------------------------------------------------------------
signal notification(text: String)
signal event_feed(text: String, color: Color)
signal settings_changed(key: String, value: Variant)
signal bindings_changed
signal profile_changed
signal cosmetics_changed
signal level_up(level: int)
signal show_subtitle(text: String, duration: float)
signal screen_shake(strength: float, duration: float)
signal goal_explosion(team: int, position: Vector3)

# --- Network -----------------------------------------------------------------
signal network_status_changed(text: String)
signal player_joined(peer_id: int, display_name: String)
signal player_left(peer_id: int)
signal lobby_changed
signal replay_saved(path: String)
signal announce(text: String)

# --- Input / debug -----------------------------------------------------------
signal request_pause(paused: bool)
signal debug_toggle_overlay

# Recovery events (counted by tools/BalanceSim).
signal car_unstuck(car_id: int)
signal car_righted(car_id: int)
signal ball_unstuck(position: Vector3)

var _muted_peers: Dictionary = {}


func emit_notification(text: String) -> void:
	notification.emit(text)


func emit_feed(text: String, color: Color = Color.WHITE) -> void:
	event_feed.emit(text, color)


func mute_peer(peer_id: int, muted: bool) -> void:
	if muted:
		_muted_peers[peer_id] = true
	else:
		_muted_peers.erase(peer_id)


func is_peer_muted(peer_id: int) -> bool:
	return _muted_peers.has(peer_id)
