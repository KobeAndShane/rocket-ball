class_name BotBrain
extends Node
## Bots produce the same CarInput a human does; they never bypass physics.
## Decisions run at 8-40 Hz depending on tier; driving input is applied every tick.

const BOT_TIERS := preload("res://bots/BotTiers.tres")

enum Mode { KICKOFF, CHASE, DEFEND, GRAB_BOOST, ROTATE_BACK, AERIAL }
enum Role { STRIKER, SUPPORT, GOALIE }

@export var tier: BotTier

var car: Car
var ball: Ball
var arena: Arena
var allies: Array[Car] = []
var opponents: Array[Car] = []

var mode: Mode = Mode.CHASE
var role: Role = Role.STRIKER
var _input := CarInput.new()
var _target := Vector3.ZERO
var _decision_timer: float = 0.0
var _jump_cooldown: float = 0.0
var _want_jump: bool = false
var _rng := RandomNumberGenerator.new()
var _last_ball_pos := Vector3.ZERO
var _ball_history: Array[Vector3] = []


func setup(car_ref: Car, ball_ref: Ball, arena_ref: Arena, tier_ref: BotTier, allies_ref: Array[Car], opponents_ref: Array[Car]) -> void:
	car = car_ref
	ball = ball_ref
	arena = arena_ref
	tier = tier_ref if tier_ref != null else BOT_TIERS.get_tier(1)
	allies = allies_ref
	opponents = opponents_ref
	# Seed by spawn slot, not car id, so the two teams get equivalent bot
	# personalities. Car ids are assigned team-by-team, which would otherwise
	# give one side a fixed RNG advantage in balance sampling.
	var slot: int = int(car.get_meta("spawn_index", car.car_id))
	_rng.seed = 9187 + slot * 7919
	_last_ball_pos = ball.global_position if ball != null else Vector3.ZERO
	_decision_timer = _rng.randf_range(0.0, 0.1)
	_ball_history.clear()
	car.control_mode = Car.DriveMode.BOT


func _physics_process(delta: float) -> void:
	if car == null or ball == null or arena == null:
		return
	_ball_history.append(ball.global_position)
	while _ball_history.size() > 180:
		_ball_history.pop_front()
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
	var perceived := _delayed_ball_position()
	var predicted := _predict_ball_from(perceived)
	var ball_delta: Vector3 = predicted - car.global_position
	var up: Vector3 = GravityManager.up
	var height: float = ball_delta.dot(up)
	var flat_dist: float = (ball_delta - up * height).length()
	var own_goal := _own_goal()
	var opp_goal := _opponent_goal()
	var closest := _is_closest_to_ball(predicted)
	_update_role(predicted)
	_want_jump = false
	var target := predicted
	var new_mode := Mode.CHASE

	if role == Role.GOALIE and own_goal != null:
		var to_ball: Vector3 = (ball.global_position - own_goal.global_position).normalized()
		target = own_goal.global_position + to_ball * (8.0 + tier.defend_bias * 5.0)
		new_mode = Mode.DEFEND
	elif role == Role.SUPPORT and own_goal != null:
		# Second attacker: stay offset from the primary striker but still drive
		# through the ball toward the opponent goal instead of parking midway.
		var lateral: Vector3 = up.cross(ball.global_position - car.global_position).normalized()
		target = predicted + lateral * 4.0
		new_mode = Mode.CHASE
	elif not closest and new_mode != Mode.GRAB_BOOST:
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

	if car.boost_component != null and car.boost_component.amount < 18.0 and not closest and role != Role.GOALIE:
		var pad := _nearest_pad()
		if pad != null:
			target = pad.global_position
			new_mode = Mode.GRAB_BOOST

	# Striker approach: get behind the ball relative to the opponent goal, then
	# drive through it. Chasing the ball directly makes bots bump it sideways
	# and never score, which also makes bot-based balance sampling useless.
	if new_mode == Mode.CHASE and opp_goal != null:
		var to_goal: Vector3 = opp_goal.global_position - predicted
		to_goal -= up * to_goal.dot(up)
		if to_goal.length_squared() > 0.01:
			to_goal = to_goal.normalized()
			var behind_offset: float = 2.2 + clampf(car.get_speed() * 0.12, 0.0, 3.5)
			var goal_side: float = (car.global_position - predicted).dot(to_goal)
			if goal_side > -1.5:
				target = predicted - to_goal * behind_offset
			else:
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


func _delayed_ball_position() -> Vector3:
	var delay: float = maxf(tier.reaction_delay, 0.0)
	if delay <= 0.001 or _ball_history.is_empty():
		return ball.global_position
	var ticks: int = int(round(delay * 120.0))
	var idx: int = clampi(_ball_history.size() - 1 - ticks, 0, _ball_history.size() - 1)
	return _ball_history[idx]


func _update_role(predicted: Vector3) -> void:
	var team: Array[Car] = [car]
	for ally: Car in allies:
		if ally != car and ally.state != Car.State.DEMOLISHED:
			team.append(ally)
	var own_goal := _own_goal()
	if own_goal == null or team.size() == 1:
		role = Role.STRIKER
		return
	var striker: Car = team[0]
	var goalie: Car = team[0]
	var best_ball: float = 1e20
	var best_goal: float = 1e20
	for member: Car in team:
		var d_ball: float = member.global_position.distance_squared_to(predicted)
		if d_ball < best_ball:
			best_ball = d_ball
			striker = member
		var d_goal: float = member.global_position.distance_squared_to(own_goal.global_position)
		if d_goal < best_goal:
			best_goal = d_goal
			goalie = member
	if car == striker:
		role = Role.STRIKER
	elif car == goalie:
		role = Role.GOALIE
	else:
		role = Role.SUPPORT


func role_name() -> String:
	return ["STRIKER", "SUPPORT", "GOALIE"][role]


func _predict_ball() -> Vector3:
	return _predict_ball_from(_delayed_ball_position())


func _predict_ball_from(origin: Vector3) -> Vector3:
	var t: float = clampf(car.global_position.distance_to(origin) / 38.0, 0.08, tier.prediction_time)
	var g: Vector3 = GravityManager.gravity_dir * GravityManager.gravity_strength
	var p: Vector3 = origin + ball.linear_velocity * t
	# If a shift lands inside the prediction window, integrate in two segments
	# with the blended gravity. This is what makes wall/ceiling reads work.
	var time_to_shift: float = GravityManager.time_until_shift()
	if GravityManager.active and not GravityManager.transitioning and time_to_shift < t:
		var first: float = maxf(time_to_shift, 0.0)
		p = origin + ball.linear_velocity * first + 0.5 * g * first * first
		var v2: Vector3 = ball.linear_velocity + g * first
		var remaining: float = t - first
		var new_g: Vector3 = GravityManager.next_direction() * GravityManager.gravity_strength
		var blend: float = clampf(remaining / maxf(GravityManager.transition_duration, 0.01), 0.0, 1.0)
		var average_g: Vector3 = g.lerp(new_g, blend)
		p += v2 * remaining + 0.5 * average_g * remaining * remaining
	else:
		p += 0.5 * g * t * t
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


func _opponent_goal() -> Goal:
	if arena == null:
		return null
	for goal: Goal in arena.goals:
		if goal.defending_team != car.team:
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
