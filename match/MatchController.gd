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
var _replay_recorder: ReplayRecorder

# Networking
var _online: bool = false
var _net_client: bool = false
var _prediction: PredictionController
var _net_overlay: NetDebugOverlay
var _snapshot_accum: float = 0.0
var _snapshot_queue: Array[Dictionary] = []
var _last_net_phase: int = -1
var _last_net_score := Vector2i(-1, -1)
var _last_net_countdown: int = -1


func _ready() -> void:
	if rules == null:
		rules = load("res://match/MatchRules.tres") as MatchRules
	_base_rules = rules.duplicate() as MatchRules
	headless_mode = headless_mode or DisplayServer.get_name() == "headless"
	_match_seed = int(Time.get_unix_time_from_system())
	_online = not NetManager.is_offline
	_net_client = _online and not NetManager.is_server
	if _online:
		local_team = NetManager.team_for_local()
		NetManager.snapshot_received.connect(_on_net_snapshot)
		NetManager.match_event.connect(_on_net_match_event)
		NetManager.peer_connected.connect(_on_net_peer_connected)
		NetManager.peer_takeover.connect(_on_net_peer_takeover)
	_spawn_world()
	_connect_events()
	if _online:
		_setup_network()
	if auto_start:
		call_deferred("start_match")
	match_ready.emit()


func _exit_tree() -> void:
	# Leaving a live ranked match counts as an abandon. Completed matches are in
	# POSTGAME and are never penalised, including the normal scene teardown.
	if rules != null and rules.ranked and local_car != null and not _recorded:
		if state == State.PLAYING or state == State.OVERTIME:
			Meta.register_abandon()
	_disconnect_events()
	if _online:
		if NetManager.snapshot_received.is_connected(_on_net_snapshot):
			NetManager.snapshot_received.disconnect(_on_net_snapshot)
		if NetManager.match_event.is_connected(_on_net_match_event):
			NetManager.match_event.disconnect(_on_net_match_event)
		if NetManager.peer_connected.is_connected(_on_net_peer_connected):
			NetManager.peer_connected.disconnect(_on_net_peer_connected)
		if NetManager.peer_takeover.is_connected(_on_net_peer_takeover):
			NetManager.peer_takeover.disconnect(_on_net_peer_takeover)
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
	if _net_client:
		ball.set_network_ghost(true)
		for goal: Goal in arena.goals:
			goal.set_enabled(false)
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
	_spawn_replay_recorder()


func _spawn_replay_recorder() -> void:
	if _net_client or headless_mode or all_bots:
		return
	_replay_recorder = ReplayRecorder.new()
	_replay_recorder.name = "ReplayRecorder"
	add_child(_replay_recorder)
	_replay_recorder.setup(self)


func _spawn_cars() -> void:
	if _online:
		_spawn_network_cars()
		return
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
			if car == local_car:
				car.apply_cosmetics(Meta.profile.get("loadout", {}))
			else:
				car.apply_cosmetics(_bot_loadout(car.car_id))
			(team_cars[team] as Array[Car]).append(car)
			next_id += 1
	if rules.fill_with_bots:
		for car: Car in cars:
			if car.control_mode == Car.DriveMode.BOT:
				_attach_bot(car)
	if local_car != null:
		local_car_spawned.emit(local_car)


## Online spawn: car ids and teams are assigned by the authoritative lobby, so
## server and clients construct exactly the same roster.
func _spawn_network_cars() -> void:
	NetManager.unregister_all()
	var total: int = rules.team_size * (1 if rules.free_play else 2)
	var local_id: int = -1
	if not all_bots:
		local_id = NetManager.local_car_id()
	for id in total:
		var car := CAR_SCENE.instantiate() as Car
		car.car_id = id
		car.team = 1 if (rules.free_play or id < rules.team_size) else 2
		car.tuning = BASE_CAR_TUNING.duplicate() as CarTuning
		car.set_meta("spawn_index", id % maxi(rules.team_size, 1))
		car.auto_respawn = true
		add_child(car)
		cars.append(car)
		NetManager.register_car(car)
		if NetManager.peer_for_car(car.car_id) > 0:
			car.apply_cosmetics(NetManager.loadout_for_car(car.car_id))
		else:
			car.apply_cosmetics(_bot_loadout(car.car_id))
	for car: Car in cars:
		var owner_peer: int = NetManager.peer_for_car(car.car_id)
		if _net_client:
			if car.car_id == local_id:
				car.set_local_player(true)
				car.control_mode = Car.DriveMode.HUMAN
				car.display_name = str(Meta.profile.get("name", "Pilot"))
				local_car = car
			else:
				car.set_local_player(false)
				car.control_mode = Car.DriveMode.NETWORK
				_make_remote_ghost(car)
				if owner_peer > 0 and NetManager.players.has(owner_peer):
					car.display_name = str(NetManager.players[owner_peer].get("name", "Pilot"))
		else:
			if car.car_id == local_id and not all_bots:
				car.set_local_player(true)
				car.control_mode = Car.DriveMode.HUMAN
				car.display_name = str(Meta.profile.get("name", "Pilot"))
				local_car = car
			elif owner_peer > 1:
				car.set_local_player(false)
				car.control_mode = Car.DriveMode.NETWORK
				car.display_name = str(NetManager.players[owner_peer].get("name", "Pilot"))
			else:
				car.set_local_player(false)
				car.control_mode = Car.DriveMode.BOT if rules.fill_with_bots else Car.DriveMode.NETWORK
				car.display_name = "Bot %d" % (car.car_id + 1)
				if car.control_mode == Car.DriveMode.BOT:
					_attach_bot(car)
				else:
					car.frozen = true
	if local_car != null:
		local_car_spawned.emit(local_car)


## Deterministic cosmetic variation for bots. Season-exclusive items are never
## handed to bots so they keep their reward value.
func _bot_loadout(car_id: int) -> Dictionary:
	var out: Dictionary = CosmeticLibrary.default_loadout()
	var choices := {
		"body": ["body_stock", "body_interceptor", "body_orbiter"],
		"wheel": ["wheel_stock", "wheel_neon", "wheel_gravity"],
		"boost": ["boost_standard", "boost_ion", "boost_supernova"],
		"decal": ["decal_none", "decal_stripes", "decal_hex"],
		"antenna": ["antenna_none", "antenna_flag"],
		"trail": ["trail_none", "trail_comet"],
		"explosion": ["explosion_standard", "explosion_blackhole"],
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("bot_%d" % car_id)
	for slot: String in CosmeticLibrary.SLOTS:
		var list: Array = choices.get(slot, [])
		if not list.is_empty():
			out[slot] = str(list[rng.randi_range(0, list.size() - 1)])
	return out


func _attach_bot(car: Car) -> void:
	var tiers := BOT_TIERS as BotTiers
	var tier := tiers.get_tier(rules.bot_tier)
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


## Remote cars are visual proxies on the client. Interpolated snapshots own
## their transforms, so their local physics and collisions are disabled.
func _make_remote_ghost(car: Car) -> void:
	car.control_mode = Car.DriveMode.NETWORK
	car.demolition_enabled = false
	car.collision_layer = 0
	car.collision_mask = 0
	car.frozen = true


func _spawn_audio() -> void:
	if not ResourceLoader.exists("res://audio/MatchAudio.tscn"):
		return
	var audio_scene := load("res://audio/MatchAudio.tscn") as PackedScene
	if audio_scene != null:
		var audio := audio_scene.instantiate()
		add_child(audio)
		if audio.has_method("setup"):
			audio.call("setup", self)


func _setup_network() -> void:
	if _net_client and local_car != null:
		local_car.demolition_enabled = false
		_prediction = PredictionController.new()
		_prediction.name = "PredictionController"
		add_child(_prediction)
		_prediction.setup(local_car, NetManager)
	if not headless_mode:
		_net_overlay = NetDebugOverlay.new()
		_net_overlay.name = "NetDebugOverlay"
		add_child(_net_overlay)
		_net_overlay.setup(NetManager, _prediction)


func _freeze_for_state(car: Car, value: bool) -> void:
	# Clients only simulate their own car; remote cars are snapshot-driven.
	if _net_client and car != local_car:
		car.frozen = true
		return
	car.set_frozen(value)


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
		if _net_client and car != local_car:
			_make_remote_ghost(car)
		if _net_client and car == local_car:
			car.demolition_enabled = false
		if car.boost_component != null:
			car.boost_component.enabled = not rules.no_boost
			car.boost_component.unlimited = rules.unlimited_boost
			if rules.no_boost:
				car.boost_component.set_amount(0.0)
			else:
				car.boost_component.reset()
	ball.freeze = true
	ball.reset_to_kickoff(arena.get_ball_spawn())
	if _net_client:
		ball.set_network_ghost(true)
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
		_freeze_for_state(car, false)
	ball.freeze = false
	if _net_client:
		ball.set_network_ghost(true)
	for goal: Goal in arena.goals:
		goal.set_enabled(not _net_client)
	GravityManager.active = true
	_timer_running = true
	_goal_active = false
	if _replay_recorder != null:
		_replay_recorder.start()
	Events.countdown_changed.emit(0)
	Events.match_state_changed.emit(state, previous)


func _physics_process(delta: float) -> void:
	if paused:
		return
	if _net_client:
		_client_physics(delta)
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
	if _online and NetManager.is_server:
		_server_snapshot_tick(delta)


func _server_snapshot_tick(delta: float) -> void:
	_snapshot_accum += delta
	var step: float = 1.0 / NetManager.SNAPSHOT_RATE
	while _snapshot_accum >= step:
		_snapshot_accum -= step
		var meta := {
			"state": int(state),
			"score1": score1,
			"score2": score2,
			"time_left": time_left,
			"countdown": countdown,
			"overtime": overtime_time,
		}
		NetManager.broadcast_snapshot(cars, ball, GravityManager.phase_index, meta)


## Client mirror: timers and transforms come from snapshots. The local car is
## still simulated locally for responsiveness and reconciled by prediction.
func _client_physics(delta: float) -> void:
	if state == State.PLAYING:
		time_left = maxf(time_left - delta, 0.0)
	elif state == State.OVERTIME:
		overtime_time += delta
	_emit_timer()
	_interpolate_network()


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
	if _net_client:
		return
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
	if _online and NetManager.is_server:
		NetManager.broadcast_event("goal", {
			"team": team,
			"scorer": scorer_id,
			"pos": ball.global_position,
		})
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
	if _replay_recorder != null:
		_replay_recorder.finish_and_save()
	if local_car != null and not _recorded:
		_recorded = true
		var local_stats: Dictionary = (_stats[local_car.car_id] as Dictionary).duplicate()
		var team_score: int = score1 if local_team == 1 else score2
		var other_score: int = score2 if local_team == 1 else score1
		local_stats["score_diff"] = team_score - other_score
		local_stats["mvp"] = 1 if int(summary.get("mvp_id", -1)) == local_car.car_id else 0
		var opponent: float = rules.opponent_mmr if rules.ranked else -1.0
		Meta.record_match(winner == local_team, local_stats, opponent, rules.opponent_rd, rules.ranked)
	if _online and NetManager.is_server:
		NetManager.broadcast_event("postgame", summary)


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


# --- Networking --------------------------------------------------------------

func _on_net_snapshot(snapshot: Dictionary) -> void:
	if not _net_client:
		return
	var arrival: float = Time.get_ticks_msec() / 1000.0
	snapshot["_arrival"] = arrival
	_snapshot_queue.append(snapshot)
	while _snapshot_queue.size() > 48:
		_snapshot_queue.pop_front()
	while _snapshot_queue.size() > 4 and arrival - float(_snapshot_queue[0]["_arrival"]) > 1.0:
		_snapshot_queue.pop_front()
	if _prediction != null and local_car != null:
		var car_states: Array = snapshot.get("cars", [])
		for state: Dictionary in car_states:
			if int(state.get("id", -1)) != local_car.car_id:
				continue
			if int(state.get("s", 0)) == Car.State.DEMOLISHED:
				if local_car.state != Car.State.DEMOLISHED:
					local_car.demolish(-1)
			else:
				if local_car.state == Car.State.DEMOLISHED:
					local_car.respawn(Transform3D(Basis(state.get("q", Quaternion.IDENTITY)), state.get("p", local_car.global_position)))
					local_car.demolition_enabled = false
				_prediction.apply_snapshot(state, int(snapshot.get("tick", 0)))
			break
	_apply_net_meta(snapshot)


func _apply_net_meta(snapshot: Dictionary) -> void:
	var meta: Dictionary = snapshot.get("m", {})
	if meta.is_empty():
		return
	var new_state: int = int(meta.get("state", state))
	if new_state != int(state):
		_enter_client_state(new_state)
	if new_state == State.COUNTDOWN:
		countdown = float(meta.get("countdown", 0.0))
		var whole: int = int(ceil(countdown))
		if whole != _last_net_countdown:
			_last_net_countdown = whole
			Events.countdown_changed.emit(maxi(whole, 0))
	var s1: int = int(meta.get("score1", score1))
	var s2: int = int(meta.get("score2", score2))
	if s1 != score1 or s2 != score2:
		score1 = s1
		score2 = s2
		Events.score_changed.emit(score1, score2)
	time_left = float(meta.get("time_left", time_left))
	overtime_time = float(meta.get("overtime", overtime_time))
	in_overtime = int(state) == State.OVERTIME
	var phase: int = int(snapshot.get("phase", GravityManager.phase_index))
	if phase != _last_net_phase:
		_last_net_phase = phase
		GravityManager.reset_to_phase(phase)
	GravityManager.active = int(state) == State.PLAYING or int(state) == State.OVERTIME


func _enter_client_state(new_state: int) -> void:
	var previous := state
	state = new_state
	var playing: bool = state == State.PLAYING or state == State.OVERTIME
	for car: Car in cars:
		if car == local_car:
			car.set_frozen(not playing)
		else:
			car.frozen = true
	ball.freeze = true
	if state == State.COUNTDOWN:
		GravityManager.reset_to_phase(GravityManager.phase_index)
	GravityManager.active = playing
	Events.match_state_changed.emit(state, previous)
	if state == State.POSTGAME:
		Events.timer_changed.emit(0.0)


## Two-snapshot interpolation keeps remote motion smooth without ever letting
## a client invent authoritative movement. Render time trails arrival by 100 ms.
func _interpolate_network() -> void:
	if _snapshot_queue.is_empty():
		return
	var render_time: float = Time.get_ticks_msec() / 1000.0 - 0.1
	var a: Dictionary = _snapshot_queue[0]
	var b: Dictionary = _snapshot_queue[0]
	if _snapshot_queue.size() > 1:
		for i in range(_snapshot_queue.size() - 1):
			if float(_snapshot_queue[i]["_arrival"]) <= render_time:
				a = _snapshot_queue[i]
				b = _snapshot_queue[i + 1]
	var span: float = maxf(float(b["_arrival"]) - float(a["_arrival"]), 0.0001)
	var alpha: float = clampf((render_time - float(a["_arrival"])) / span, 0.0, 1.0)
	var cars_a: Array = a.get("cars", [])
	var cars_b: Array = b.get("cars", [])
	for car_state: Dictionary in cars_a:
		var id: int = int(car_state.get("id", -1))
		if local_car != null and id == local_car.car_id:
			continue
		var car := _car_by_id(id)
		if car == null:
			continue
		var state_b: Dictionary = _find_car_state(cars_b, id)
		if state_b.is_empty():
			state_b = car_state
		var blended := _blend_car_state(car_state, state_b, alpha)
		if int(blended.get("s", 0)) == Car.State.DEMOLISHED:
			if car.state != Car.State.DEMOLISHED:
				car.demolish(-1)
			continue
		if car.state == Car.State.DEMOLISHED:
			car.respawn(Transform3D(Basis(blended.get("q", Quaternion.IDENTITY)), blended.get("p", car.global_position)))
			_make_remote_ghost(car)
		car.set_snapshot_state(blended)
	var ball_a: Dictionary = a.get("ball", {})
	if not ball_a.is_empty():
		var ball_b: Dictionary = b.get("ball", ball_a)
		if ball_b.is_empty():
			ball_b = ball_a
		ball.set_snapshot_state(_blend_ball_state(ball_a, ball_b, alpha))


func _find_car_state(list: Array, car_id: int) -> Dictionary:
	for state: Dictionary in list:
		if int(state.get("id", -1)) == car_id:
			return state
	return {}


func _blend_car_state(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	return {
		"p": (a.get("p", Vector3.ZERO) as Vector3).lerp(b.get("p", a.get("p", Vector3.ZERO)), t),
		"q": (a.get("q", Quaternion.IDENTITY) as Quaternion).slerp(b.get("q", a.get("q", Quaternion.IDENTITY)), t),
		"v": (a.get("v", Vector3.ZERO) as Vector3).lerp(b.get("v", a.get("v", Vector3.ZERO)), t),
		"b": lerpf(float(a.get("b", 0.0)), float(b.get("b", a.get("b", 0.0))), t),
		"s": int(a.get("s", 0)) if t < 0.5 else int(b.get("s", a.get("s", 0))),
	}


func _blend_ball_state(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	return {
		"p": (a.get("p", Vector3.ZERO) as Vector3).lerp(b.get("p", a.get("p", Vector3.ZERO)), t),
		"q": (a.get("q", Quaternion.IDENTITY) as Quaternion).slerp(b.get("q", a.get("q", Quaternion.IDENTITY)), t),
		"v": (a.get("v", Vector3.ZERO) as Vector3).lerp(b.get("v", a.get("v", Vector3.ZERO)), t),
		"w": (a.get("w", Vector3.ZERO) as Vector3).lerp(b.get("w", a.get("w", Vector3.ZERO)), t),
	}


func _on_net_match_event(kind: String, payload: Dictionary) -> void:
	if not _net_client:
		return
	match kind:
		"goal":
			var team: int = int(payload.get("team", 1))
			var pos: Vector3 = payload.get("pos", ball.global_position)
			var scorer_id: int = int(payload.get("scorer", -1))
			Events.goal_explosion.emit(team, pos)
			Events.screen_shake.emit(0.7, 0.45)
			Events.event_feed.emit("%s scores for %s!" % [_car_name(scorer_id), "Blue" if team == 1 else "Orange"], Color(0.25, 0.75, 1.0) if team == 1 else Color(1.0, 0.5, 0.2))
			Events.notification.emit("GOAL!")
		"feed":
			var color: Color = payload.get("color", Color.WHITE)
			Events.event_feed.emit(str(payload.get("text", "")), color)
		"postgame":
			_apply_network_postgame(payload)


func _apply_network_postgame(summary: Dictionary) -> void:
	score1 = int(summary.get("score1", score1))
	score2 = int(summary.get("score2", score2))
	var winner: int = int(summary.get("winner", 0))
	Events.match_ended.emit(score1, score2, winner)
	Events.stats_updated.emit(summary)
	if local_car == null or _recorded:
		return
	_recorded = true
	var local_stats: Dictionary = {}
	var players_list: Array = summary.get("players", [])
	for entry: Dictionary in players_list:
		if int(entry.get("car_id", -1)) == local_car.car_id:
			local_stats = entry.duplicate()
			break
	var team_score: int = score1 if local_team == 1 else score2
	var other_score: int = score2 if local_team == 1 else score1
	local_stats["score_diff"] = team_score - other_score
	local_stats["mvp"] = 1 if int(summary.get("mvp_id", -1)) == local_car.car_id else 0
	var opponent: float = rules.opponent_mmr if rules.ranked else -1.0
	Meta.record_match(winner == local_team, local_stats, opponent, rules.opponent_rd, rules.ranked)


func _on_net_peer_connected(peer_id: int) -> void:
	if _online and NetManager.is_server:
		if not NetManager.current_match_rules.is_empty():
			NetManager.send_match_start_to(peer_id, NetManager.current_match_rules)
		_takeover_car(peer_id, true)


func _on_net_peer_takeover(peer_id: int) -> void:
	if _online and NetManager.is_server:
		_takeover_car(peer_id, false)


## Mid-match join converts the assigned bot into a human-controlled car;
## reconnect expiry hands it back to the bot brain.
func _takeover_car(peer_id: int, human: bool) -> void:
	var entry: Dictionary = NetManager.players.get(peer_id, {})
	if entry.is_empty():
		return
	var car := _car_by_id(int(entry.get("car_id", -1)))
	if car == null:
		return
	var brain := car.get_node_or_null("BotBrain")
	if brain != null:
		brain.queue_free()
	car.display_name = str(entry.get("name", car.display_name))
	car.apply_cosmetics(NetManager.loadout_for_car(car.car_id))
	var playing: bool = state == State.PLAYING or state == State.OVERTIME
	if human:
		car.set_local_player(false)
		car.control_mode = Car.DriveMode.NETWORK
		car.frozen = not playing
	else:
		NetManager.report_disconnect(peer_id)
		if rules.fill_with_bots:
			car.control_mode = Car.DriveMode.BOT
			_attach_bot(car)
			car.frozen = not playing
		else:
			car.control_mode = Car.DriveMode.NETWORK
			car.frozen = true
