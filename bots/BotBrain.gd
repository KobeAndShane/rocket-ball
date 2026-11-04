class_name BotBrain
extends Node
## Bots produce the same CarInput a human does; they never bypass physics.
## Decisions run at 8-40 Hz depending on tier; driving input is applied every tick.

const BOT_TIERS := preload("res://bots/BotTiers.tres")

enum Mode { KICKOFF, CHASE, DEFEND, GRAB_BOOST, ROTATE_BACK, AERIAL }

@export var tier: BotTier

var car: Car
var ball: Ball
var arena: Arena
var allies: Array[Car] = []
var opponents: Array[Car] = []

var mode: Mode = Mode.CHASE
var _input := CarInput.new()
var _target := Vector3.ZERO
var _decision_timer: float = 0.0
var _jump_cooldown: float = 0.0
var _want_jump: bool = false
var _rng := RandomNumberGenerator.new()
var _last_ball_pos := Vector3.ZERO


func setup(car_ref: Car, ball_ref: Ball, arena_ref: Arena, tier_ref: BotTier, allies_ref: Array[Car], opponents_ref: Array[Car]) -> void:
	car = car_ref
	ball = ball_ref
	arena = arena_ref
	tier = tier_ref if tier_ref != null else BOT_TIERS.get_tier(1)
	allies = allies_ref
	opponents = opponents_ref
	_rng.seed = 9187 + car.car_id * 7919
	_last_ball_pos = ball.global_position if ball != null else Vector3.ZERO
	_decision_timer = _rng.randf_range(0.0, 0.1)
	car.control_mode = Car.DriveMode.BOT


func _physics_process(delta: float) -> void:
	if car == null or ball == null or arena == null:
		return
	if car.frozen or car.state == Car.State.DEMOLISHED:
		return
	_jump_cooldown = maxf(0.0, _jump_cooldown - delta)
	_decision_timer -= delta
	if _decision_timer <= 0.0:
		_decision_timer = 1.0 / maxf(tier.update_hz, 1.0)
		_decide()
	_drive(delta)
	car.apply_input(_input)


func _decide() -> void:
	var predicted := _predict_ball()
	var ball_delta: Vector3 = predicted - car.global_position
	var up: Vector3 = GravityManager.up
	var height: float = ball_delta.dot(up)
	var flat_dist: float = (ball_delta - up * height).length()
	var own_goal := _own_goal()
	var closest := _is_closest_to_ball(predicted)
	_want_jump = false
	var target := predicted
	var new_mode := Mode.CHASE

	if car.boost_component != null and car.boost_component.amount < 18.0 and not closest:
		var pad := _nearest_pad()
		if pad != null:
			target = pad.global_position
			new_mode = Mode.GRAB_BOOST

	if not closest and new_mode != Mode.GRAB_BOOST:
		if own_goal != null:
			var to_ball: Vector3 = (ball.global_position - own_goal.global_position).normalized()
			target = own_goal.global_position + to_ball * (9.0 + tier.defend_bias * 5.0)
			new_mode = Mode.DEFEND
		else:
			new_mode = Mode.ROTATE_BACK
	elif closest and own_goal != null:
		var dist_own_goal: float = car.global_position.distance_to(own_goal.global_position)
		if dist_own_goal < 16.0 and ball_delta.dot(own_goal.global_position - car.global_position) > 0.0:
			new_mode = Mode.DEFEND
			target = predicted

	# Aerial attempt when the ball is above the drivable plane and close.
	if height > 3.2 and flat_dist < 13.0 and tier.aerial_skill > 0.15:
		if car.is_grounded() and _jump_cooldown <= 0.0 and _rng.randf() < tier.aerial_skill:
			_want_jump = true
			_jump_cooldown = 0.22
			new_mode = Mode.AERIAL
		elif not car.is_grounded() and _jump_cooldown <= 0.0 and flat_dist < 7.0:
			_want_jump = true
			_jump_cooldown = 0.5
			new_mode = Mode.AERIAL

	# Aim error is deterministic per bot and grows with distance.
	var error_dir: Vector3 = (predicted - car.global_position)
	error_dir -= up * error_dir.dot(up)
	if error_dir.length_squared() > 0.1:
		var right: Vector3 = error_dir.normalized().cross(up).normalized()
		target += right * _rng.randf_range(-1.0, 1.0) * tier.aim_error * minf(error_dir.length(), 30.0)
	target = _clamp_inside(target)
	_target = target
	mode = new_mode


func _predict_ball() -> Vector3:
	var t: float = clampf(car.global_position.distance_to(ball.global_position) / 38.0, 0.08, tier.prediction_time)
	var g: Vector3 = GravityManager.gravity_dir * GravityManager.gravity_strength
	var p: Vector3 = ball.global_position + ball.linear_velocity * t + 0.5 * g * t * t
	return _clamp_inside(p)


func _clamp_inside(p: Vector3) -> Vector3:
	var h := Arena.HALF_EXTENTS - Vector3(2.0, 2.0, 2.0)
	return Vector3(clampf(p.x, -h.x, h.x), clampf(p.y, -h.y, h.y), clampf(p.z, -h.z, h.z))


func _own_goal() -> Goal:
	if arena == null:
		return null
	for goal: Goal in arena.goals:
		if goal.defending_team == car.team:
			return goal
	return null


func _nearest_pad() -> BoostPad:
	if arena == null:
		return null
	var best: BoostPad = null
	var best_dist: float = 1e20
	for pad: BoostPad in arena.pads:
		if not pad.active:
			continue
		var d: float = pad.global_position.distance_squared_to(car.global_position)
		if d < best_dist:
			best_dist = d
			best = pad
	if best_dist > 40.0 * 40.0:
		return null
	return best


func _is_closest_to_ball(predicted: Vector3) -> bool:
	var my_dist: float = car.global_position.distance_squared_to(predicted)
	for other: Car in allies:
		if other == car or other.state == Car.State.DEMOLISHED:
			continue
		if other.global_position.distance_squared_to(predicted) < my_dist:
			return false
	return true


func _drive(delta: float) -> void:
	var up: Vector3 = GravityManager.up
	var grounded: bool = car.is_grounded()
	var ref_up: Vector3 = car.ground_normal if grounded else up
	var delta_vec: Vector3 = _target - car.global_position
	var flat: Vector3 = delta_vec - ref_up * delta_vec.dot(ref_up)
	var dist: float = flat.length()
	var local := Vector3.ZERO
	if dist > 0.05:
		local = car.global_transform.basis.inverse() * (flat / dist)
	var forward: Vector3 = -car.global_transform.basis.z
	var facing: float = forward.dot(flat.normalized()) if dist > 0.05 else 1.0
	_input.jump_pressed = _want_jump
	_want_jump = false
	_input.jump_held = false
	_input.handbrake = false
	_input.air_roll = false
	_input.boost = false
	_input.pitch = 0.0
	_input.yaw = 0.0
	_input.roll = 0.0
	if grounded:
		_input.throttle = clampf(facing * 1.6 + 0.25, 0.0, 1.0) * tier.speed_scale
		_input.steer = clampf(local.x * 2.8, -1.0, 1.0)
		if absf(facing) < 0.35 and car.speed > 12.0:
			_input.handbrake = true
			_input.throttle *= 0.55
		if mode == Mode.CHASE and dist > 8.0 and car.boost_component != null and car.boost_component.amount > 8.0 and facing > 0.72:
			if _rng.randf() < tier.boost_use:
				_input.boost = true
		# Small hop when a pad or the ball requires a jump.
		if dist < 5.0 and _jump_cooldown <= 0.0 and _rng.randf() < tier.aggression * 0.4:
			_input.jump_pressed = true
			_jump_cooldown = 0.4
	else:
		_input.steer = clampf(local.x * 2.0, -1.0, 1.0)
		_input.yaw = _input.steer
		var height_err: float = delta_vec.dot(up)
		_input.pitch = clampf(height_err * 0.18, -1.0, 1.0)
		if height_err > 0.0 and car.boost_component != null and car.boost_component.amount > 5.0:
			_input.boost = true
		_input.throttle = 0.0
	_input.tick = Engine.get_physics_frames()


func set_enabled(value: bool) -> void:
	process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
