extends Node
class_name MatchController
## Match state machine (Task 05): LOBBY > COUNTDOWN > PLAYING > GOAL_PAUSE >
## OVERTIME > POSTGAME. Server/offline owns score, timer and gravity phase.

enum State { LOBBY, COUNTDOWN, PLAYING, GOAL_PAUSE, REPLAY, OVERTIME, POSTGAME }

var rules: MatchRules
var arena: Arena
var ball: Ball
var cars: Array[Car] = []

var state: int = State.LOBBY
var overtime: bool = false
var time_left: float = 300.0
var countdown_left: float = 0.0
var pause_left: float = 0.0
var blue_score: int = 0
var orange_score: int = 0

var _last_timer_second: int = -999
var _last_countdown: int = -999
var _pending_end: bool = false


func setup(
	p_arena: Arena, p_ball: Ball, p_cars: Array[Car], p_rules: MatchRules
) -> void:
	arena = p_arena
	ball = p_ball
	cars = p_cars
	rules = p_rules
	Events.goal_scored.connect(_on_goal_scored)


func start_match() -> void:
	blue_score = 0
	orange_score = 0
	overtime = false
	_pending_end = false
	time_left = rules.match_time
	Events.score_changed.emit(blue_score, orange_score)
	_emit_timer(true)
	_begin_kickoff()


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("debug_gravity"):
		GravityManager.debug_shift()
	if Input.is_action_just_pressed("reset_car"):
		_reset_player_car()

	match state:
		State.COUNTDOWN:
			_tick_countdown(delta)
		State.PLAYING:
			_tick_play(delta)
		State.OVERTIME:
			# Golden goal: no clock, first goal ends the match.
			pass
		State.GOAL_PAUSE:
			_tick_goal_pause(delta)
		_:
			pass


func _tick_countdown(delta: float) -> void:
	countdown_left -= delta
	var whole: int = int(ceil(maxf(countdown_left, 0.0)))
	if whole != _last_countdown:
		_last_countdown = whole
		if whole > 0:
			Events.ui_prompt.emit(str(whole), 0.9)
	if countdown_left <= 0.0:
		_start_play()


func _start_play() -> void:
	state = State.OVERTIME if overtime else State.PLAYING
	Events.match_state_changed.emit(state)
	Events.ui_prompt.emit("GO!", 0.8)
	for car: Car in cars:
		car.set_controls_enabled(true)
	GravityManager.reset_phase(0)
	GravityManager.start()
	if overtime:
		Events.overtime_started.emit()


func _tick_play(delta: float) -> void:
	time_left = maxf(time_left - delta, 0.0)
	_emit_timer()
	if time_left <= 0.0:
		if blue_score == orange_score and rules.overtime_enabled:
			_begin_overtime()
		else:
			_end_match()


func _emit_timer(force: bool = false) -> void:
	var whole: int = int(ceil(time_left))
	if force or whole != _last_timer_second:
		_last_timer_second = whole
		Events.timer_changed.emit(whole)


func _begin_kickoff() -> void:
	state = State.COUNTDOWN
	countdown_left = rules.countdown_time
	_last_countdown = -999
	_pending_end = false
	Events.match_state_changed.emit(state)
	GravityManager.stop()
	if ball != null:
		ball.reset_to_kickoff(Vector3(0.0, 0.0, 0.0))
	var slot_by_team: Dictionary = {0: 0, 1: 0}
	for car: Car in cars:
		var slot: int = int(slot_by_team.get(car.team, 0))
		slot_by_team[car.team] = slot + 1
		car.set_controls_enabled(false)
		if arena != null:
			car.reset_to_transform(arena.get_spawn_transform(car.team, slot))
	# Emit after the ball and cars are back at kickoff positions.
	Events.kickoff_started.emit()


func _on_goal_scored(scoring_team: int) -> void:
	if state != State.PLAYING and state != State.OVERTIME:
		return
	if scoring_team == 0:
		blue_score += 1
	else:
		orange_score += 1
	Events.score_changed.emit(blue_score, orange_score)
	var team_name: String = "BLUE" if scoring_team == 0 else "ORANGE"
	Events.ui_prompt.emit("%s SCORES!" % team_name, 1.8)
	Events.event_feed.emit("%s goal  (%d - %d)" % [team_name, blue_score, orange_score])
	GravityManager.stop()
	for car: Car in cars:
		car.set_controls_enabled(false)
	if state == State.OVERTIME:
		_pending_end = true
	elif time_left <= 0.0 and blue_score != orange_score:
		_pending_end = true
	state = State.GOAL_PAUSE
	pause_left = rules.goal_pause_time
	Events.match_state_changed.emit(state)


func _tick_goal_pause(delta: float) -> void:
	pause_left -= delta
	if pause_left > 0.0:
		return
	if _pending_end:
		_end_match()
	elif time_left <= 0.0:
		if blue_score == orange_score and rules.overtime_enabled:
			_begin_overtime()
		else:
			_end_match()
	else:
		_begin_kickoff()


func _begin_overtime() -> void:
	overtime = true
	time_left = 0.0
	_emit_timer(true)
	Events.overtime_started.emit()
	Events.ui_prompt.emit("OVERTIME - GOLDEN GOAL", 2.5)
	_begin_kickoff()


func _end_match() -> void:
	state = State.POSTGAME
	GravityManager.stop()
	for car: Car in cars:
		car.set_controls_enabled(false)
	Events.match_state_changed.emit(state)
	var result: String = "DRAW"
	if blue_score > orange_score:
		result = "BLUE WINS"
	elif orange_score > blue_score:
		result = "ORANGE WINS"
	Events.ui_prompt.emit("%s  %d - %d" % [result, blue_score, orange_score], 6.0)
	Events.event_feed.emit("%s  %d - %d" % [result, blue_score, orange_score])
	Events.match_ended.emit(blue_score, orange_score)


func _reset_player_car() -> void:
	if arena == null or cars.is_empty():
		return
	var car: Car = cars[0]
	car.reset_to_transform(arena.get_spawn_transform(car.team, 0))
	if state == State.PLAYING or state == State.OVERTIME:
		car.set_controls_enabled(true)
