class_name MatchController
extends Node3D
## Server-authoritative match loop: kickoff, goals, replay, overtime, postgame.
## Offline play uses the exact same flow; NetManager swaps authority later.

signal match_ready
signal local_car_spawned(car: Car)

enum State { LOBBY, COUNTDOWN, PLAYING, GOAL_PAUSE, REPLAY, OVERTIME, POSTGAME }

const CAR_SCENE := preload("res://car/Car.tscn")
const BALL_SCENE := preload("res://ball/Ball.tscn")
const ARENA_SCENE := preload("res://arena/Arena.tscn")
const CAMERA_SCENE := preload("res://camera/ChaseCamera.tscn")
const BOT_TIERS := preload("res://bots/BotTiers.tres")
const BASE_CAR_TUNING := preload("res://car/CarTuning.tres")
const BASE_BALL_TUNING := preload("res://ball/BallTuning.tres")

@export var rules: MatchRules
@export var auto_start: bool = true
@export var local_team: int = 1
@export var spawn_camera: bool = true
@export var spawn_hud: bool = true
@export var headless_mode: bool = false
@export var all_bots: bool = false

var arena: Arena
var ball: Ball
var cars: Array[Car] = []
var local_car: Car
var camera: ChaseCamera
var hud: CanvasLayer

var state: State = State.LOBBY
var score1: int = 0
var score2: int = 0
var time_left: float = 300.0
var overtime_time: float = 0.0
var countdown: float = 0.0
var in_overtime: bool = false
var paused: bool = false

var _after_countdown: State = State.PLAYING
var _countdown_last: int = -1
var _last_second: int = -1
var _goal_pause_timer: float = 0.0
var _replay_timer: float = 0.0
var _goal_active: bool = false
var _goal_decides: bool = false
var _timer_running: bool = true
var _stats: Dictionary = {}
var _last_boost: Dictionary = {}
var _last_hit: Dictionary = {}
var _last_hitters: Array[int] = []
var _last_hit_time: float = 0.0
var _match_time: float = 0.0
var _recorded: bool = false
var _match_seed: int = 0
var _pause_was_gravity_active: bool = false
var _base_rules: MatchRules


func _ready() -> void:
	if rules == null:
		rules = load("res://match/MatchRules.tres") as MatchRules
	_base_rules = rules.duplicate() as MatchRules
	headless_mode = headless_mode or DisplayServer.get_name() == "headless"
	_match_seed = int(Time.get_unix_time_from_system())
	_spawn_world()
	_connect_events()
	if auto_start:
		call_deferred("start_match")
	match_ready.emit()


func _exit_tree() -> void:
	_disconnect_events()
	GravityManager.stop()


func _connect_events() -> void:
	Events.goal_scored.connect(_on_goal_scored)
	Events.car_demolished.connect(_on_car_demolished)
	Events.ball_hit.connect(_on_ball_hit)
	Events.boost_changed.connect(_on_boost_changed)
	Events.car_respawned.connect(_on_car_respawned)


func _disconnect_events() -> void:
	if Events.goal_scored.is_connected(_on_goal_scored):
		Events.goal_scored.disconnect(_on_goal_scored)
	if Events.car_demolished.is_connected(_on_car_demolished):
		Events.car_demolished.disconnect(_on_car_demolished)
	if Events.ball_hit.is_connected(_on_ball_hit):
		Events.ball_hit.disconnect(_on_ball_hit)
	if Events.boost_changed.is_connected(_on_boost_changed):
		Events.boost_changed.disconnect(_on_boost_changed)
	if Events.car_respawned.is_connected(_on_car_respawned):
		Events.car_respawned.disconnect(_on_car_respawned)


func _spawn_world() -> void:
	arena = ARENA_SCENE.instantiate() as Arena
	arena.configure(rules)
	add_child(arena)
	var ball_tuning := BASE_BALL_TUNING.duplicate() as BallTuning
	ball_tuning.radius = BASE_BALL_TUNING.radius * rules.ball_radius_scale
	ball_tuning.mass = BASE_BALL_TUNING.mass * rules.ball_mass_scale
	ball = BALL_SCENE.instantiate() as Ball
	ball.tuning = ball_tuning
	add_child(ball)
	ball.reset_to_kickoff(arena.get_ball_spawn())
	_spawn_cars()
	if spawn_camera and not headless_mode:
		camera = CAMERA_SCENE.instantiate() as ChaseCamera
		add_child(camera)
		camera.setup(local_car, ball)
	if spawn_hud and not headless_mode and ResourceLoader.exists("res://ui/HUD.tscn"):
		var hud_scene := load("res://ui/HUD.tscn") as PackedScene
		if hud_scene != null:
			hud = hud_scene.instantiate() as CanvasLayer
			add_child(hud)
			if hud.has_method("setup"):
				hud.call("setup", self)
	_spawn_audio()


func _spawn_cars() -> void:
	var team_cars: Dictionary = {1: [] as Array[Car], 2: [] as Array[Car]}
	var next_id := 0
	var teams: Array[int] = [1]
	if not rules.free_play:
		teams.append(2)
	for team: int in teams:
		for i in rules.team_size:
			var car := CAR_SCENE.instantiate() as Car
			car.team = team
			car.car_id = next_id
			car.tuning = BASE_CAR_TUNING.duplicate() as CarTuning
			car.set_meta("spawn_index", i)
			car.auto_respawn = true
			if team == local_team and i == 0 and not all_bots:
				car.set_local_player(true)
				car.control_mode = Car.DriveMode.HUMAN
				car.display_name = str(Meta.profile.get("name", "Pilot"))
				local_car = car
			else:
				car.set_local_player(false)
				car.control_mode = Car.DriveMode.BOT
				car.display_name = "Bot %d" % (next_id + 1)
			add_child(car)
			cars.append(car)
			(team_cars[team] as Array[Car]).append(car)
			next_id += 1
	if rules.fill_with_bots:
		var tiers := BOT_TIERS as BotTiers
		var tier := tiers.get_tier(rules.bot_tier)
		for car: Car in cars:
			if car.control_mode != Car.DriveMode.BOT:
				continue
			var brain := BotBrain.new()
			brain.name = "BotBrain"
			car.add_child(brain)
			var allies: Array[Car] = []
			var opponents: Array[Car] = []
			for other: Car in cars:
				if other == car:
					continue
				if other.team == car.team:
					allies.append(other)
				else:
					opponents.append(other)
			brain.setup(car, ball, arena, tier, allies, opponents)
	if local_car != null:
		local_car_spawned.emit(local_car)


func _spawn_audio() -> void:
	if not ResourceLoader.exists("res://audio/MatchAudio.tscn"):
		return
	var audio_scene := load("res://audio/MatchAudio.tscn") as PackedScene
	if audio_scene != null:
		var audio := audio_scene.instantiate()
		add_child(audio)
		if audio.has_method("setup"):
			audio.call("setup", self)


func start_match() -> void:
	_apply_mutators()
	score1 = 0
	score2 = 0
	time_left = rules.match_duration
	overtime_time = 0.0
	in_overtime = false
	_recorded = false
	_match_time = 0.0
	_goal_active = false
	_goal_decides = false
	_stats.clear()
	_last_boost.clear()
	_last_hit.clear()
	_last_hitters.clear()
	if ball != null:
		ball.set_radius(BASE_BALL_TUNING.radius * rules.ball_radius_scale, BASE_BALL_TUNING.mass * rules.ball_mass_scale)
	for car: Car in cars:
		_stats[car.car_id] = {
			"name": car.display_name,
			"team": car.team,
			"car_id": car.car_id,
			"goals": 0,
			"saves": 0,
			"assists": 0,
			"shots": 0,
			"demolitions": 0,
			"boost_used": 0.0,
			"playtime": 0.0,
		}
		car.tuning.unstuck_time = rules.unstuck_time
	GravityManager.configure(rules, _match_seed)
	Events.score_changed.emit(score1, score2)
	_begin_kickoff(State.PLAYING)


## Rebuild the working rules from the authored preset each match, then stack the
## enabled mutators in order. Arena/ball/boost consumers read the result at
## kickoff, so mutators never corrupt the source resource.
func _apply_mutators() -> void:
	if _base_rules == null:
		return
	var working := _base_rules.duplicate() as MatchRules
	var built: Array[Resource] = []
	for entry: Resource in working.mutators:
		var mutator := entry as MutatorBase
		if mutator == null or not mutator.enabled:
			continue
		built.append(mutator)
	working.mutators = built
	for entry: Resource in working.mutators:
		(entry as MutatorBase).apply(working, self)
	rules = working
	if arena != null:
		arena.rules = rules
		if arena.theme != null:
			var themes := ["res://arena/ArenaTheme.tres", "res://arena/ArenaTheme_Ice.tres", "res://arena/ArenaTheme_Lava.tres"]
			var idx: int = clampi(rules.arena_theme_index, 0, themes.size() - 1)
			if ResourceLoader.exists(themes[idx]):
				arena.theme = load(themes[idx]) as ArenaTheme
				arena.apply_theme(arena.theme)


func mutator_names() -> Array[String]:
	var out: Array[String] = []
	for entry: Resource in rules.mutators:
		var mutator := entry as MutatorBase
		if mutator != null and mutator.enabled:
			out.append(mutator.display_name)
	return out


func _begin_kickoff(next_state: State) -> void:
	var previous := state
	state = State.COUNTDOWN
	_after_countdown = next_state
	countdown = maxf(rules.kickoff_countdown, 0.01)
	_countdown_last = -1
	_timer_running = false
	GravityManager.active = false
	GravityManager.reset_to_phase(0)
	for car: Car in cars:
		car.frozen = true
		car.demolition_enabled = rules.demolition_enabled
		car.friendly_fire = rules.friendly_fire
		car.reset_to_kickoff(arena.get_spawn_transform(car.team, int(car.get_meta("spawn_index", 0))))
		if car.boost_component != null:
			car.boost_component.enabled = not rules.no_boost
			car.boost_component.unlimited = rules.unlimited_boost
			if rules.no_boost:
				car.boost_component.set_amount(0.0)
			else:
				car.boost_component.reset()
	ball.freeze = true
	ball.reset_to_kickoff(arena.get_ball_spawn())
	for goal: Goal in arena.goals:
		goal.set_enabled(false)
	_goal_active = false
	if camera != null:
		camera.stop_replay()
	Events.countdown_changed.emit(int(ceil(countdown)))
	Events.match_state_changed.emit(state, previous)


func _start_play() -> void:
	var previous := state
	state = _after_countdown
	for car: Car in cars:
		car.frozen = false
	ball.freeze = false
	for goal: Goal in arena.goals:
		goal.set_enabled(true)
	GravityManager.active = true
	_timer_running = true
	_goal_active = false
	Events.countdown_changed.emit(0)
	Events.match_state_changed.emit(state, previous)


func _physics_process(delta: float) -> void:
	if paused:
		return
	match state:
		State.COUNTDOWN:
			countdown -= delta
			var whole: int = int(ceil(countdown))
			if whole != _countdown_last and whole > 0:
				_countdown_last = whole
				Events.countdown_changed.emit(whole)
			if countdown <= 0.0:
				_start_play()
		State.PLAYING:
			time_left -= delta
			_match_time += delta
			_emit_timer()
			if time_left <= 0.0:
				time_left = 0.0
				_on_regulation_end()
		State.OVERTIME:
			overtime_time += delta
			_match_time += delta
			_emit_timer()
		State.GOAL_PAUSE:
			_goal_pause_timer -= delta
			if _goal_pause_timer <= 0.0:
				_finish_goal_pause()
		State.REPLAY:
			_replay_timer -= delta
			if _replay_timer <= 0.0:
				_finish_replay()
		_:
			pass


func _emit_timer() -> void:
	var seconds: int = int(ceil(maxf(time_left, 0.0)))
	if in_overtime:
		seconds = int(floor(overtime_time))
	if seconds != _last_second:
		_last_second = seconds
		Events.timer_changed.emit(time_left if not in_overtime else overtime_time)


func _on_regulation_end() -> void:
	if score1 == score2 and rules.overtime_enabled:
		_start_overtime()
	else:
		_end_match()


func _start_overtime() -> void:
	if in_overtime:
		return
	in_overtime = true
	overtime_time = 0.0
	_last_second = -1
	Events.overtime_started.emit()
	Events.event_feed.emit("OVERTIME - next goal wins", Color(1.0, 0.85, 0.2))
	_begin_kickoff(State.OVERTIME)


func _on_goal_scored(team: int, scorer_id: int) -> void:
	if _goal_active:
		return
	if state != State.PLAYING and state != State.OVERTIME:
		return
	_goal_active = true
	if team == 1:
		score1 += 1
	else:
		score2 += 1
	Events.score_changed.emit(score1, score2)
	_credit_goal(team, scorer_id)
	Events.goal_explosion.emit(team, ball.global_position)
	Events.screen_shake.emit(0.7, 0.45)
	var scorer_name := _car_name(scorer_id)
	var feed_color := Color(0.25, 0.75, 1.0) if team == 1 else Color(1.0, 0.5, 0.2)
	Events.event_feed.emit("%s scores for %s!" % [scorer_name, "Blue" if team == 1 else "Orange"], feed_color)
	Events.notification.emit("GOAL!")
	_goal_decides = in_overtime or (rules.score_limit > 0 and maxi(score1, score2) >= rules.score_limit)
	for car: Car in cars:
		car.frozen = true
	ball.freeze = true
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	for goal: Goal in arena.goals:
		goal.set_enabled(false)
	GravityManager.active = false
	_timer_running = false
	var previous := state
	state = State.GOAL_PAUSE
	_goal_pause_timer = rules.goal_pause
	Events.match_state_changed.emit(state, previous)


func _credit_goal(team: int, scorer_id: int) -> void:
	if not _stats.has(scorer_id):
		return
	var scorer: Car = _car_by_id(scorer_id)
	if scorer == null or scorer.team != team:
		return
	var st: Dictionary = _stats[scorer_id]
	st["goals"] = int(st["goals"]) + 1
	# Assist: a different team-mate touched the ball within 6 s.
	var now := _match_time
	var idx := _last_hitters.find(scorer_id)
	if idx >= 0 and now - _last_hit_time < 6.0:
		for i in range(idx + 1, _last_hitters.size()):
			var assist_id: int = _last_hitters[i]
			var mate: Car = _car_by_id(assist_id)
			if mate != null and mate.team == team and mate != scorer:
				var ast: Dictionary = _stats[assist_id]
				ast["assists"] = int(ast["assists"]) + 1
				Events.event_feed.emit("%s assisted" % mate.display_name, Color(0.7, 0.9, 1.0))
				break
	_emit_stats()


func _finish_goal_pause() -> void:
	if _goal_decides or in_overtime:
		_end_match()
		return
	if rules.replay_enabled and camera != null:
		var previous := state
		state = State.REPLAY
		_replay_timer = rules.replay_duration
		camera.start_replay(ball.global_position, rules.replay_duration)
		Events.match_state_changed.emit(state, previous)
	else:
		_after_goal()


func _finish_replay() -> void:
	if camera != null:
		camera.stop_replay()
	_after_goal()


func _after_goal() -> void:
	if in_overtime:
		_end_match()
	elif time_left <= 0.0:
		if score1 == score2 and rules.overtime_enabled:
			_start_overtime()
		else:
			_end_match()
	else:
		_begin_kickoff(State.PLAYING)


func _on_ball_hit(strength: float, position: Vector3, hitter_id: int) -> void:
	if state != State.PLAYING and state != State.OVERTIME:
		return
	if strength < 2.0:
		return
	_last_hitters.push_front(hitter_id)
	if _last_hitters.size() > 3:
		_last_hitters.resize(3)
	_last_hit_time = _match_time
	var car: Car = _car_by_id(hitter_id)
	if car == null:
		return
	var st: Dictionary = _stats[hitter_id]
	var own_goal := _goal_defended_by(car.team)
	var opp_goal := _goal_defended_by(3 - car.team)
	if opp_goal != null and strength > 14.0:
		var to_goal: Vector3 = (opp_goal.global_position - position).normalized()
		var ball_vel: Vector3 = ball.linear_velocity.normalized() if ball.linear_velocity.length() > 0.5 else to_goal
		var dist: float = position.distance_to(opp_goal.global_position)
		if dist < 38.0 and ball_vel.dot(to_goal) > 0.55 and _cooldown_ok(hitter_id, "shot"):
			_goal_cooldown(hitter_id, "shot")
			st["shots"] = int(st["shots"]) + 1
	if own_goal != null and strength > 10.0:
		var own_dist: float = position.distance_to(own_goal.global_position)
		if own_dist < 18.0 and _cooldown_ok(hitter_id, "save"):
			_goal_cooldown(hitter_id, "save")
			st["saves"] = int(st["saves"]) + 1
			Events.event_feed.emit("%s saves!" % car.display_name, Color(0.4, 1.0, 0.55))
			_emit_stats()


func _cooldown_ok(car_id: int, kind: String) -> bool:
	var key := "%s_%d" % [kind, car_id]
	return _match_time - float(_last_hit.get(key, -999.0)) > 2.0


func _goal_cooldown(car_id: int, kind: String) -> void:
	_last_hit["%s_%d" % [kind, car_id]] = _match_time


func _on_car_demolished(victim_id: int, attacker_id: int) -> void:
	if attacker_id >= 0 and _stats.has(attacker_id):
		var st: Dictionary = _stats[attacker_id]
		st["demolitions"] = int(st["demolitions"]) + 1
	var victim := _car_by_id(victim_id)
	var attacker := _car_by_id(attacker_id)
	if victim != null:
		var text := "%s was demolished" % victim.display_name
		if attacker != null:
			text = "%s demolished %s" % [attacker.display_name, victim.display_name]
		Events.event_feed.emit(text, Color(1.0, 0.4, 0.25))
	Events.screen_shake.emit(0.5, 0.3)


func _on_car_respawned(car_id: int) -> void:
	if state != State.PLAYING and state != State.OVERTIME:
		return
	var car := _car_by_id(car_id)
	if car != null:
		Events.event_feed.emit("%s respawned" % car.display_name, Color(0.7, 0.7, 0.8))


func _on_boost_changed(car_id: int, amount: float) -> void:
	var prev: float = float(_last_boost.get(car_id, amount))
	if amount < prev and _stats.has(car_id):
		var st: Dictionary = _stats[car_id]
		st["boost_used"] = float(st["boost_used"]) + (prev - amount)
	_last_boost[car_id] = amount


func _end_match() -> void:
	if state == State.POSTGAME:
		return
	var previous := state
	state = State.POSTGAME
	GravityManager.active = false
	for car: Car in cars:
		car.frozen = true
		var st: Dictionary = _stats[car.car_id]
		st["playtime"] = _match_time
	ball.freeze = true
	for goal: Goal in arena.goals:
		goal.set_enabled(false)
	var winner: int = 0
	if score1 > score2:
		winner = 1
	elif score2 > score1:
		winner = 2
	var summary := _build_summary(winner)
	Events.match_ended.emit(score1, score2, winner)
	Events.timer_changed.emit(0.0)
	Events.stats_updated.emit(summary)
	Events.match_state_changed.emit(state, previous)
	if local_car != null and not _recorded:
		_recorded = true
		var local_stats: Dictionary = (_stats[local_car.car_id] as Dictionary).duplicate()
		var team_score: int = score1 if local_team == 1 else score2
		var other_score: int = score2 if local_team == 1 else score1
		local_stats["score_diff"] = team_score - other_score
		local_stats["mvp"] = 1 if int(summary.get("mvp_id", -1)) == local_car.car_id else 0
		Meta.record_match(winner == local_team, local_stats, float(Meta.profile["mmr"]), float(Meta.profile["mmr"]))


func _build_summary(winner: int) -> Dictionary:
	var list: Array = []
	var mvp_id := -1
	var mvp_points := -99999
	for car: Car in cars:
		var st: Dictionary = (_stats[car.car_id] as Dictionary).duplicate()
		var points: int = int(st["goals"]) * 100 + int(st["assists"]) * 55 + int(st["saves"]) * 45 + int(st["shots"]) * 15 + int(st["demolitions"]) * 35
		st["points"] = points
		st["name"] = car.display_name
		st["team"] = car.team
		if points > mvp_points:
			mvp_points = points
			mvp_id = car.car_id
		list.append(st)
	return {
		"score1": score1,
		"score2": score2,
		"winner": winner,
		"mvp_id": mvp_id,
		"overtime": in_overtime,
		"duration": _match_time,
		"players": list,
	}


func _emit_stats() -> void:
	Events.stats_updated.emit(_build_summary(0))


func _car_by_id(id: int) -> Car:
	for car: Car in cars:
		if car.car_id == id:
			return car
	return null


func _car_name(id: int) -> String:
	var car := _car_by_id(id)
	return car.display_name if car != null else "Unknown"


func _goal_defended_by(team: int) -> Goal:
	if arena == null:
		return null
	for goal: Goal in arena.goals:
		if goal.defending_team == team:
			return goal
	return null


func display_time() -> String:
	if in_overtime:
		var t: int = int(floor(overtime_time))
		return "OT %02d:%02d" % [int(t / 60), t % 60]
	var t2: int = int(ceil(maxf(time_left, 0.0)))
	return "%02d:%02d" % [int(t2 / 60), t2 % 60]


func get_state_name() -> String:
	return ["LOBBY", "COUNTDOWN", "PLAYING", "GOAL_PAUSE", "REPLAY", "OVERTIME", "POSTGAME"][state]


func toggle_pause() -> void:
	if state == State.POSTGAME:
		return
	paused = not paused
	if paused:
		_pause_was_gravity_active = GravityManager.active
		GravityManager.active = false
		for car: Car in cars:
			car.set_frozen(true)
		ball.freeze = true
	else:
		if state == State.PLAYING or state == State.OVERTIME:
			for car: Car in cars:
				car.set_frozen(false)
			ball.freeze = false
			GravityManager.active = _pause_was_gravity_active
	Events.request_pause.emit(paused)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and state != State.POSTGAME:
		toggle_pause()
		get_viewport().set_input_as_handled()


func rematch() -> void:
	paused = false
	for car: Car in cars:
		car.frozen = false
	ball.freeze = false
	start_match()


func return_to_menu() -> void:
	get_tree().change_scene_to_file("res://ui/Main.tscn")


func get_local_car() -> Car:
	return local_car
