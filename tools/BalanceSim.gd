extends Node
## Headless balance simulator. Runs many bot matches on the real match scene
## and writes per-match CSV plus a JSON summary.
##
## Usage:
##   godot --headless --fixed-fps 120 --path . res://tools/BalanceSim.tscn -- \
##     --sim-matches=1000 --orientation=0 --seconds=20 --label=floor
##
## The match is reused between samples: scores, timers, cars, ball, pads and
## gravity are reset by MatchController.start_match(), so no scene churn is
## included in the simulation time.

const MATCH_SCENE := preload("res://match/Match.tscn")
const RULES := preload("res://match/MatchRules.tres")
const ORIENTATION_NAMES := ["floor", "wall_a", "ceiling", "wall_b"]

var requested_matches: int = 10
var orientation: int = 0
var orientation_all: bool = false
var match_seconds: float = 20.0
var shift_interval: float = 30.0
var transition: float = 2.0
var ball_speed_scale: float = 1.0
var boost_scale: float = 1.0
var bot_tier: int = -1
var base_seed: int = 1000
var label: String = "default"
var debug_log: bool = false
## Overtime produces a decisive winner instead of recording a draw. Fairness
## sampling enables it so win rates are measured on real outcomes.
var overtime_enabled: bool = true
var telemetry_path: String = ""
var telemetry_hz: float = 1.0
var csv_path: String = "user://balance_matches.csv"
var goal_csv_path: String = "user://balance_goals.csv"
var summary_path: String = "user://balance_summary.json"

var match_ref: MatchController
var _match_index: int = 0
var _current_orientation: int = 0
var _current_seed: int = 0
var _active: bool = false
var _results: Array[Dictionary] = []
var _goal_rows: Array[Dictionary] = []
var _telemetry_rows: Array[Dictionary] = []
var _telemetry_accum: float = 0.0
var _match_goals: int = 0
var _match_shift_goals: int = 0
var _match_demos: int = 0
var _match_stucks: int = 0
var _match_righted: int = 0
var _match_ball_resets: int = 0
var _ball_z_min: float = 0.0
var _ball_z_max: float = 0.0
var _ball_speed_max: float = 0.0
var _shift_ago: float = 999.0
var _wall_start_us: int = 0
var _sim_seconds: float = 0.0


func _ready() -> void:
	_parse_args()
	call_deferred("_run")


func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for arg: String in args:
		if arg.begins_with("--sim-matches="):
			requested_matches = maxi(int(arg.get_slice("=", 1)), 1)
		elif arg.begins_with("--orientation="):
			var value := arg.get_slice("=", 1)
			if value == "all":
				orientation_all = true
			else:
				orientation = clampi(int(value), 0, 3)
		elif arg.begins_with("--seconds="):
			match_seconds = maxf(float(arg.get_slice("=", 1)), 2.0)
		elif arg.begins_with("--shift-interval="):
			shift_interval = maxf(float(arg.get_slice("=", 1)), 5.0)
		elif arg.begins_with("--transition="):
			transition = maxf(float(arg.get_slice("=", 1)), 0.0)
		elif arg.begins_with("--ball-speed="):
			ball_speed_scale = maxf(float(arg.get_slice("=", 1)), 0.2)
		elif arg.begins_with("--boost="):
			boost_scale = maxf(float(arg.get_slice("=", 1)), 0.2)
		elif arg.begins_with("--bot-tier="):
			bot_tier = clampi(int(arg.get_slice("=", 1)), 0, 2)
		elif arg.begins_with("--seed="):
			base_seed = int(arg.get_slice("=", 1))
		elif arg.begins_with("--label="):
			label = arg.get_slice("=", 1)
		elif arg == "--debug":
			debug_log = true
		elif arg == "--no-overtime":
			overtime_enabled = false
		elif arg.begins_with("--telemetry-csv="):
			telemetry_path = arg.get_slice("=", 1)
		elif arg.begins_with("--telemetry-hz="):
			telemetry_hz = maxf(float(arg.get_slice("=", 1)), 0.1)
		elif arg.begins_with("--csv="):
			csv_path = arg.get_slice("=", 1)
		elif arg.begins_with("--goal-csv="):
			goal_csv_path = arg.get_slice("=", 1)
		elif arg.begins_with("--summary="):
			summary_path = arg.get_slice("=", 1)


func _run() -> void:
	await get_tree().process_frame
	Engine.max_fps = 0
	var rules := RULES.duplicate() as MatchRules
	rules.team_size = 3
	rules.match_duration = match_seconds
	rules.kickoff_countdown = 0.05
	rules.goal_pause = 0.05
	rules.replay_enabled = false
	rules.replay_duration = 0.0
	rules.overtime_enabled = overtime_enabled
	rules.score_limit = 0
	rules.fill_with_bots = true
	rules.ranked = false
	rules.mode_id = "balance_sim"
	rules.mode_name = "Balance Sim"
	if bot_tier >= 0:
		rules.bot_tier = bot_tier
	rules.gravity_interval = shift_interval
	rules.gravity_transition = transition
	rules.gravity_warning = minf(5.0, maxf(shift_interval * 0.2, 0.2))
	match_ref = MATCH_SCENE.instantiate() as MatchController
	match_ref.rules = rules
	match_ref.auto_start = false
	match_ref.headless_mode = true
	match_ref.spawn_camera = false
	match_ref.spawn_hud = false
	match_ref.all_bots = true
	match_ref.start_phase_index = orientation
	match_ref.match_seed_override = base_seed
	add_child(match_ref)
	await get_tree().process_frame
	# Presentation is not part of a balance sample; drop audio/VFX once.
	var audio := match_ref.get_node_or_null("MatchAudio")
	if audio != null:
		audio.queue_free()
	var vfx := match_ref.get_node_or_null("VFX")
	if vfx != null:
		vfx.queue_free()
	_apply_tuning()
	Events.match_ended.connect(_on_match_ended, CONNECT_DEFERRED)
	Events.goal_scored.connect(_on_goal_scored)
	Events.car_demolished.connect(_on_car_demolished)
	Events.car_unstuck.connect(_on_car_unstuck)
	Events.car_righted.connect(_on_car_righted)
	Events.ball_unstuck.connect(_on_ball_unstuck)
	Events.gravity_shift_started.connect(_on_gravity_shift_started)
	_wall_start_us = Time.get_ticks_usec()
	_start_next_match()


func _apply_tuning() -> void:
	if match_ref.ball != null and match_ref.ball.tuning != null:
		var bt := match_ref.ball.tuning
		bt.max_speed *= ball_speed_scale
		bt.hit_gain *= lerpf(1.0, ball_speed_scale, 0.5)
		bt.pop_up_impulse *= lerpf(1.0, ball_speed_scale, 0.5)
	for car: Car in match_ref.cars:
		if car.tuning == null:
			continue
		car.tuning.boost_force *= boost_scale
		car.tuning.boost_refill_on_shift *= boost_scale
		car.tuning.boost_max_speed = car.tuning.max_speed + (car.tuning.boost_max_speed - car.tuning.max_speed) * boost_scale
		car.tuning.unstuck_time = RULES.unstuck_time


func _start_next_match() -> void:
	if _match_index >= requested_matches:
		_finish()
		return
	_current_orientation = _match_index % 4 if orientation_all else orientation
	_current_seed = base_seed + _match_index * 7919
	_match_goals = 0
	_match_shift_goals = 0
	_match_demos = 0
	_match_stucks = 0
	_match_righted = 0
	_match_ball_resets = 0
	_ball_z_min = 0.0
	_ball_z_max = 0.0
	_ball_speed_max = 0.0
	_shift_ago = 999.0
	_telemetry_accum = 0.0
	match_ref.start_phase_index = _current_orientation
	match_ref.match_seed_override = _current_seed
	match_ref.start_match()
	_active = true


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_sim_seconds += delta
	_shift_ago += delta
	if debug_log and Engine.get_physics_frames() % 120 == 0:
		_debug_print()
	if match_ref != null and match_ref.ball != null:
		var bz: float = match_ref.ball.global_position.z
		_ball_z_min = minf(_ball_z_min, bz)
		_ball_z_max = maxf(_ball_z_max, bz)
		_ball_speed_max = maxf(_ball_speed_max, match_ref.ball.linear_velocity.length())
		if not telemetry_path.is_empty() and (match_ref.state == MatchController.State.PLAYING \
				or match_ref.state == MatchController.State.OVERTIME):
			_telemetry_accum += delta
			if _telemetry_accum >= 1.0 / telemetry_hz:
				_telemetry_accum = 0.0
				_record_telemetry()


func _record_telemetry() -> void:
	var bpos: Vector3 = match_ref.ball.global_position
	var bvel: Vector3 = match_ref.ball.linear_velocity
	_telemetry_rows.append({
		"match": _match_index,
		"orientation": _current_orientation,
		"t": match_ref._match_time,
		"phase": GravityManager.phase_index,
		"shift_ago": _shift_ago,
		"state": int(match_ref.state),
		"bx": bpos.x,
		"by": bpos.y,
		"bz": bpos.z,
		"bspeed": bvel.length(),
		"score1": match_ref.score1,
		"score2": match_ref.score2,
	})


func _debug_print() -> void:
	var parts: Array[String] = []
	for car: Car in match_ref.cars:
		parts.append("car%d t%d %s spd=%.2f thr=%.2f frz=%s st=%d wheels=%d upY=%.2f pos=(%.1f,%.1f,%.1f)" % [
			car.car_id, car.team, car.display_name, car.get_speed(), car.input.throttle,
			str(car.frozen), int(car.state), car.wheels_on_ground, car.global_transform.basis.y.dot(GravityManager.up),
			car.global_position.x, car.global_position.y, car.global_position.z,
		])
	print("DBG t=%.1f state=%d score=%d-%d ball=(%.1f,%.1f,%.1f) v=%.1f | %s" % [
		_sim_seconds, int(match_ref.state), match_ref.score1, match_ref.score2,
		match_ref.ball.global_position.x, match_ref.ball.global_position.y, match_ref.ball.global_position.z,
		match_ref.ball.linear_velocity.length(), " | ".join(parts),
	])


func _on_gravity_shift_started(_from: Vector3, _to: Vector3, _duration: float) -> void:
	_shift_ago = 0.0


func _on_goal_scored(team: int, scorer_id: int) -> void:
	if not _active:
		return
	_match_goals += 1
	var shift_goal := _shift_ago <= 5.0
	if shift_goal:
		_match_shift_goals += 1
	var pos := match_ref.ball.global_position if match_ref.ball != null else Vector3.ZERO
	_goal_rows.append({
		"orientation": _current_orientation,
		"match": _match_index,
		"team": team,
		"scorer": scorer_id,
		"phase": GravityManager.phase_index,
		"shift_goal": 1 if shift_goal else 0,
		"x": pos.x,
		"y": pos.y,
		"z": pos.z,
	})


func _on_car_demolished(_victim_id: int, _attacker_id: int) -> void:
	if _active:
		_match_demos += 1


func _on_car_unstuck(_car_id: int) -> void:
	if _active:
		_match_stucks += 1


func _on_car_righted(_car_id: int) -> void:
	if _active:
		_match_righted += 1


func _on_ball_unstuck(_position: Vector3) -> void:
	if _active:
		_match_ball_resets += 1


func _on_match_ended(score1: int, score2: int, winner: int) -> void:
	if not _active:
		return
	_active = false
	_results.append({
		"orientation": _current_orientation,
		"match": _match_index,
		"seed": _current_seed,
		"score1": score1,
		"score2": score2,
		"winner": winner,
		"overtime": 1 if match_ref.in_overtime else 0,
		"goals": _match_goals,
		"shift_goals": _match_shift_goals,
		"demos": _match_demos,
		"stucks": _match_stucks,
		"righted": _match_righted,
		"ball_resets": _match_ball_resets,
		"ball_z_min": _ball_z_min,
		"ball_z_max": _ball_z_max,
		"ball_speed_max": _ball_speed_max,
		"shift_interval": shift_interval,
		"transition": transition,
		"ball_speed_scale": ball_speed_scale,
		"boost_scale": boost_scale,
	})
	_match_index += 1
	if _match_index % 25 == 0:
		var elapsed := float(Time.get_ticks_usec() - _wall_start_us) / 1000000.0
		print("BALANCE PROGRESS  %d/%d  sim=%.0fs wall=%.1fs" % [_match_index, requested_matches, _sim_seconds, elapsed])
	_start_next_match()


func _finish() -> void:
	var elapsed := float(Time.get_ticks_usec() - _wall_start_us) / 1000000.0
	_write_csv()
	_write_goal_csv()
	_write_telemetry()
	var summary := _build_summary(elapsed)
	_write_summary(summary)
	print("BALANCE_JSON_BEGIN")
	print(JSON.stringify(summary, "  "))
	print("BALANCE_JSON_END")
	print("BALANCE PASS  %s  orientation=%s  matches=%d  team1=%.1f%%  team2=%.1f%%  draws=%.1f%%  wall=%.1fs" % [
		label,
		"all" if orientation_all else ORIENTATION_NAMES[_current_orientation],
		int(summary["matches"]),
		float(summary["team1_win_pct"]),
		float(summary["team2_win_pct"]),
		float(summary["draw_pct"]),
		elapsed,
	])
	get_tree().quit(0)


func _build_summary(elapsed: float) -> Dictionary:
	var rows: Array = []
	for o in 4:
		var matches := 0
		var t1 := 0
		var t2 := 0
		var draws := 0
		var goals := 0
		var shift_goals := 0
		var demos := 0
		var stucks := 0
		var righted := 0
		var ball_resets := 0
		var overtime := 0
		for r: Dictionary in _results:
			if int(r["orientation"]) != o:
				continue
			matches += 1
			var w: int = int(r["winner"])
			if w == 1:
				t1 += 1
			elif w == 2:
				t2 += 1
			else:
				draws += 1
			goals += int(r["goals"])
			shift_goals += int(r["shift_goals"])
			demos += int(r["demos"])
			stucks += int(r["stucks"])
			righted += int(r.get("righted", 0))
			ball_resets += int(r["ball_resets"])
			overtime += int(r.get("overtime", 0))
		if matches == 0:
			continue
		var decisive: int = t1 + t2
		var ci := _wilson_interval(t1, decisive)
		var win_pct: float = float(t1) * 100.0 / float(maxi(decisive, 1))
		rows.append({
			"orientation": o,
			"name": ORIENTATION_NAMES[o],
			"matches": matches,
			"team1_wins": t1,
			"team2_wins": t2,
			"draws": draws,
			"decisive": decisive,
			"team1_win_pct": win_pct,
			"team2_win_pct": float(t2) * 100.0 / float(maxi(decisive, 1)),
			"team1_win_ci_low_pct": ci.x,
			"team1_win_ci_high_pct": ci.y,
			"within_48_52": win_pct >= 48.0 and win_pct <= 52.0,
			"team1_share_pct": (float(t1) + float(draws) * 0.5) * 100.0 / float(matches),
			"team2_share_pct": (float(t2) + float(draws) * 0.5) * 100.0 / float(matches),
			"draw_pct": float(draws) * 100.0 / float(matches),
			"overtime_matches": overtime,
			"goals_per_match": float(goals) / float(matches),
			"shift_goals_per_match": float(shift_goals) / float(matches),
			"demos_per_match": float(demos) / float(matches),
			"stucks_per_match": float(stucks) / float(matches),
			"righted_per_match": float(righted) / float(matches),
			"ball_resets_per_match": float(ball_resets) / float(matches),
		})
	var total_t1 := 0
	var total_t2 := 0
	var total_draws := 0
	var total_goals := 0
	var total_shift_goals := 0
	var total_demos := 0
	var total_stucks := 0
	var total_righted := 0
	var total_ball_resets := 0
	var total_overtime := 0
	for r: Dictionary in _results:
		var w: int = int(r["winner"])
		if w == 1:
			total_t1 += 1
		elif w == 2:
			total_t2 += 1
		else:
			total_draws += 1
		total_goals += int(r["goals"])
		total_shift_goals += int(r["shift_goals"])
		total_demos += int(r["demos"])
		total_stucks += int(r["stucks"])
		total_righted += int(r.get("righted", 0))
		total_ball_resets += int(r["ball_resets"])
		total_overtime += int(r.get("overtime", 0))
	var total_decisive: int = total_t1 + total_t2
	var match_count: int = maxi(_results.size(), 1)
	var total_ci := _wilson_interval(total_t1, total_decisive)
	var total_win_pct: float = float(total_t1) * 100.0 / float(maxi(total_decisive, 1))
	return {
		"label": label,
		"matches": _results.size(),
		"orientation_mode": "all" if orientation_all else ORIENTATION_NAMES[orientation],
		"seconds": match_seconds,
		"shift_interval": shift_interval,
		"transition": transition,
		"ball_speed_scale": ball_speed_scale,
		"boost_scale": boost_scale,
		"overtime_enabled": overtime_enabled,
		"seed": base_seed,
		"wall_seconds": elapsed,
		"simulated_seconds": _sim_seconds,
		"speedup": _sim_seconds / maxf(elapsed, 0.001),
		"team1_wins": total_t1,
		"team2_wins": total_t2,
		"draws": total_draws,
		"decisive": total_decisive,
		"team1_win_pct": total_win_pct,
		"team2_win_pct": float(total_t2) * 100.0 / float(maxi(total_decisive, 1)),
		"team1_win_ci_low_pct": total_ci.x,
		"team1_win_ci_high_pct": total_ci.y,
		"within_48_52": total_win_pct >= 48.0 and total_win_pct <= 52.0,
		"team1_share_pct": (float(total_t1) + float(total_draws) * 0.5) * 100.0 / float(match_count),
		"team2_share_pct": (float(total_t2) + float(total_draws) * 0.5) * 100.0 / float(match_count),
		"draw_pct": float(total_draws) * 100.0 / float(match_count),
		"overtime_matches": total_overtime,
		"goals_per_match": float(total_goals) / float(match_count),
		"shift_goals_per_match": float(total_shift_goals) / float(match_count),
		"demos_per_match": float(total_demos) / float(match_count),
		"stucks_per_match": float(total_stucks) / float(match_count),
		"righted_per_match": float(total_righted) / float(match_count),
		"ball_resets_per_match": float(total_ball_resets) / float(match_count),
		"telemetry_samples": _telemetry_rows.size(),
		"orientations": rows,
		"goals": _goal_rows.size(),
	}


func _write_csv() -> void:
	var file := FileAccess.open(csv_path, FileAccess.WRITE)
	if file == null:
		push_warning("BalanceSim: cannot write %s" % csv_path)
		return
	file.store_line("orientation,match,seed,score1,score2,winner,overtime,goals,shift_goals,demos,stucks,righted,ball_resets,ball_z_min,ball_z_max,ball_speed_max,shift_interval,transition,ball_speed_scale,boost_scale")
	for r: Dictionary in _results:
		file.store_line("%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f" % [
			int(r["orientation"]), int(r["match"]), int(r["seed"]),
			int(r["score1"]), int(r["score2"]), int(r["winner"]),
			int(r.get("overtime", 0)),
			int(r["goals"]), int(r["shift_goals"]), int(r["demos"]),
			int(r["stucks"]), int(r.get("righted", 0)), int(r["ball_resets"]),
			float(r["ball_z_min"]), float(r["ball_z_max"]), float(r["ball_speed_max"]),
			float(r["shift_interval"]), float(r["transition"]),
			float(r["ball_speed_scale"]), float(r["boost_scale"]),
		])
	file.close()


func _write_goal_csv() -> void:
	var file := FileAccess.open(goal_csv_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_line("orientation,match,team,scorer,phase,shift_goal,x,y,z")
	for r: Dictionary in _goal_rows:
		file.store_line("%d,%d,%d,%d,%d,%d,%.2f,%.2f,%.2f" % [
			int(r["orientation"]), int(r["match"]), int(r["team"]),
			int(r["scorer"]), int(r["phase"]), int(r["shift_goal"]),
			float(r["x"]), float(r["y"]), float(r["z"]),
		])
	file.close()


func _write_telemetry() -> void:
	if telemetry_path.is_empty() or _telemetry_rows.is_empty():
		return
	var file := FileAccess.open(telemetry_path, FileAccess.WRITE)
	if file == null:
		push_warning("BalanceSim: cannot write %s" % telemetry_path)
		return
	file.store_line("match,orientation,t,phase,shift_ago,state,bx,by,bz,bspeed,score1,score2")
	for r: Dictionary in _telemetry_rows:
		file.store_line("%d,%d,%.2f,%d,%.2f,%d,%.2f,%.2f,%.2f,%.2f,%d,%d" % [
			int(r["match"]), int(r["orientation"]), float(r["t"]), int(r["phase"]),
			float(r["shift_ago"]), int(r["state"]), float(r["bx"]), float(r["by"]),
			float(r["bz"]), float(r["bspeed"]), int(r["score1"]), int(r["score2"]),
		])
	file.close()


func _wilson_interval(wins: int, total: int) -> Vector2:
	if total <= 0:
		return Vector2(0.0, 100.0)
	var n := float(total)
	var p := float(wins) / n
	var z := 1.96
	var denom := 1.0 + z * z / n
	var centre := (p + z * z / (2.0 * n)) / denom
	var margin := z * sqrt((p * (1.0 - p) + z * z / (4.0 * n)) / n) / denom
	return Vector2(
		clampf((centre - margin) * 100.0, 0.0, 100.0),
		clampf((centre + margin) * 100.0, 0.0, 100.0)
	)


func _write_summary(summary: Dictionary) -> void:
	var file := FileAccess.open(summary_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(summary, "  "))
	file.close()
