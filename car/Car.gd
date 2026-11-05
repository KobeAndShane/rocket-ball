extends RigidBody3D
class_name Car
## Arcade car on a RigidBody3D (Task 01). Gravity is applied manually in
## _integrate_forces; every surface direction comes from GravityManager.

enum State { GROUNDED, AIRBORNE, DODGING, DEMOLISHED }

signal state_changed(new_state: int)
signal supersonic_changed(value: bool)

@export var tuning: CarTuning
@export var team: int = 0

var player_id: int = 0
var boost: BoostComponent
var state: int = State.AIRBORNE
var controls_enabled: bool = false
var is_supersonic: bool = false
var speed: float = 0.0

# Input frame. Bots and the network write exactly the same fields.
var in_throttle: float = 0.0
var in_brake: float = 0.0
var in_steer: float = 0.0
var in_pitch: float = 0.0
var in_roll: float = 0.0
var in_boost: bool = false
var in_handbrake: bool = false

var _wheel_offsets: Array[Vector3] = []
var _grounded: bool = false
var _ground_normal: Vector3 = Vector3.UP
var _jumps_used: int = 0
var _air_time: float = 0.0
var _coyote: float = 0.0
var _dodge_timer: float = 0.0
var _dodge_dir: Vector3 = Vector3.ZERO
var _jump_queued: bool = false
var _space_state: PhysicsDirectSpaceState3D
var _events_connected: bool = false


func _ready() -> void:
	if tuning == null:
		tuning = load("res://car/CarTuning.tres") as CarTuning
	gravity_scale = 0.0
	mass = tuning.mass
	can_sleep = false
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 6
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	add_to_group("cars")
	_build_body()
	_build_wheels()
	boost = BoostComponent.new()
	boost.name = "BoostComponent"
	boost.setup(tuning)
	add_child(boost)


func _build_body() -> void:
	var shape := BoxShape3D.new()
	shape.size = tuning.body_size
	var collider := CollisionShape3D.new()
	collider.name = "Hull"
	collider.shape = shape
	add_child(collider)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "HullMesh"
	var box := BoxMesh.new()
	box.size = tuning.body_size
	mesh_instance.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.45, 1.0) if team == 0 else Color(1.0, 0.42, 0.1)
	mat.metallic = 0.45
	mat.roughness = 0.3
	mesh_instance.material_override = mat
	add_child(mesh_instance)

	# Nose marker makes the car's forward direction readable (forward is -Z).
	var nose := MeshInstance3D.new()
	nose.name = "Nose"
	var nose_box := BoxMesh.new()
	nose_box.size = Vector3(0.55, 0.22, 1.2)
	nose.mesh = nose_box
	nose.position = Vector3(0.0, 0.12, -tuning.body_size.z * 0.5 - 0.4)
	var nose_mat := StandardMaterial3D.new()
	nose_mat.albedo_color = Color(1.0, 1.0, 1.0)
	nose_mat.emission_enabled = true
	nose_mat.emission = Color(0.7, 0.9, 1.0)
	nose_mat.emission_energy_multiplier = 1.5
	nose.material_override = nose_mat
	add_child(nose)


func _build_wheels() -> void:
	var half_track := tuning.track_width * 0.5
	var half_base := tuning.wheelbase * 0.5
	_wheel_offsets = [
		Vector3(-half_track, tuning.wheel_anchor_height, -half_base),
		Vector3(half_track, tuning.wheel_anchor_height, -half_base),
		Vector3(-half_track, tuning.wheel_anchor_height, half_base),
		Vector3(half_track, tuning.wheel_anchor_height, half_base),
	]


func _physics_process(_delta: float) -> void:
	if state == State.DEMOLISHED:
		return
	if controls_enabled:
		_read_player_input()
	else:
		_zero_input()

	if Input.is_action_just_pressed("jump") and controls_enabled:
		_jump_queued = true


func _read_player_input() -> void:
	in_throttle = Input.get_action_strength("throttle")
	in_brake = Input.get_action_strength("brake")
	in_steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	in_pitch = Input.get_action_strength("pitch_up") - Input.get_action_strength("pitch_down")
	in_roll = Input.get_action_strength("air_roll")
	in_boost = Input.is_action_pressed("boost")
	in_handbrake = Input.is_action_pressed("handbrake")


func _zero_input() -> void:
	in_throttle = 0.0
	in_brake = 0.0
	in_steer = 0.0
	in_pitch = 0.0
	in_roll = 0.0
	in_boost = false
	in_handbrake = false


func _integrate_forces(body_state: PhysicsDirectBodyState3D) -> void:
	if state == State.DEMOLISHED:
		return
	var delta: float = body_state.step
	if delta <= 0.0:
		return
	_space_state = get_world_3d().direct_space_state

	var up_dir: Vector3 = GravityManager.up
	body_state.apply_central_force(
		GravityManager.gravity_dir * GravityManager.gravity_strength * mass
	)

	_air_time += delta
	if _coyote > 0.0:
		_coyote -= delta

	if _jump_queued:
		_jump_queued = false
		_perform_jump(body_state, up_dir)

	_probe_suspension(body_state, up_dir)

	if _grounded:
		_apply_ground_forces(body_state, delta)
		if _dodge_timer <= 0.0 and state != State.DODGING:
			_set_state(State.GROUNDED)
		_jumps_used = 0
		_coyote = tuning.coyote_time
	else:
		_apply_air_forces(body_state, delta)
		if _dodge_timer <= 0.0 and state != State.DODGING:
			_set_state(State.AIRBORNE)

	if _dodge_timer > 0.0:
		_dodge_timer -= delta
		if _dodge_timer <= 0.0 and state == State.DODGING:
			_set_state(State.AIRBORNE)

	_apply_boost(body_state, up_dir)
	_update_speed_readout(body_state)


func _probe_suspension(body_state: PhysicsDirectBodyState3D, up_dir: Vector3) -> void:
	var touch_count: int = 0
	var normal_sum := Vector3.ZERO
	for offset: Vector3 in _wheel_offsets:
		var origin: Vector3 = body_state.transform * offset
		var to: Vector3 = origin - up_dir * tuning.suspension_ray_length
		var query := PhysicsRayQueryParameters3D.create(origin, to, 1)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var hit: Dictionary = _space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		var dist: float = origin.distance_to(hit.position as Vector3)
		if dist > tuning.suspension_rest + 0.06:
			continue
		var n: Vector3 = (hit.normal as Vector3).normalized()
		var compression: float = tuning.suspension_rest - dist
		var vn: float = body_state.linear_velocity.dot(n)
		var spring_force: float = tuning.spring_strength * maxf(compression, 0.0)
		var damp_force: float = tuning.spring_damping * vn
		var force: float = maxf(0.0, spring_force - damp_force)
		body_state.apply_force(n * force, (hit.position as Vector3) - body_state.transform.origin)
		touch_count += 1
		normal_sum += n

	_grounded = touch_count >= tuning.min_wheels_grounded
	if _grounded:
		_ground_normal = normal_sum.normalized()
		# Downforce keeps the wheels pressed onto wall/ceiling surfaces.
		body_state.apply_central_force(-_ground_normal * tuning.stick_force * mass)
	else:
		_ground_normal = up_dir


func _apply_ground_forces(body_state: PhysicsDirectBodyState3D, delta: float) -> void:
	var n: Vector3 = _ground_normal
	var vel: Vector3 = body_state.linear_velocity
	var tangent_vel: Vector3 = vel - n * vel.dot(n)
	var forward: Vector3 = _project_to_plane(-body_state.transform.basis.z, n)
	if forward.length_squared() < 0.01:
		forward = _project_to_plane(Vector3.FORWARD, n)
	if forward.length_squared() < 0.01:
		forward = _project_to_plane(Vector3.RIGHT, n)
	var right: Vector3 = forward.cross(n)
	if right.length_squared() < 0.01:
		right = _project_to_plane(body_state.transform.basis.x, n)
	right = right.normalized()
	var fwd_speed: float = tangent_vel.dot(forward)

	# Longitudinal control.
	if in_throttle > 0.01 and fwd_speed < tuning.max_ground_speed:
		body_state.apply_central_force(forward * tuning.engine_accel * in_throttle * mass)
	elif in_brake > 0.01:
		if fwd_speed > 1.0:
			body_state.apply_central_force(-forward * tuning.brake_accel * in_brake * mass)
		elif fwd_speed > -tuning.max_reverse_speed:
			body_state.apply_central_force(-forward * tuning.engine_accel * 0.7 * in_brake * mass)
	else:
		var drag: Vector3 = tangent_vel.normalized() * tuning.coast_drag * mass
		body_state.apply_central_force(-drag)

	# Cap overspeed.
	if fwd_speed > tuning.max_ground_speed:
		body_state.apply_central_force(
			-forward * (fwd_speed - tuning.max_ground_speed) * mass * 2.0
		)

	# Lateral grip / drift.
	var lateral: float = tangent_vel.dot(right)
	var grip_mult: float = tuning.handbrake_grip if in_handbrake else tuning.grip
	var lateral_accel: float = clampf(lateral * grip_mult * 10.0, -45.0, 45.0)
	if not in_handbrake:
		body_state.apply_central_force(-right * lateral_accel * mass)
	else:
		body_state.apply_central_force(-right * lateral_accel * 0.25 * mass)

	# Yaw: direct angular steering with speed-sensitive rate (feels arcade).
	var speed_ratio: float = clampf(tangent_vel.length() / tuning.max_ground_speed, 0.0, 1.0)
	var turn: float = tuning.turn_rate + (tuning.turn_rate_fast - tuning.turn_rate) * speed_ratio
	var reverse_sign: float = -1.0 if fwd_speed < -0.5 else 1.0
	var yaw_av: Vector3 = n * (-in_steer * turn * reverse_sign)
	var car_up: Vector3 = body_state.transform.basis.y.normalized()
	var align_err: Vector3 = car_up.cross(n)
	var align_av: Vector3 = align_err * tuning.align_rate
	if align_av.length() > 6.0:
		align_av = align_av.normalized() * 6.0
	var target_av: Vector3 = yaw_av + align_av
	body_state.angular_velocity = body_state.angular_velocity.lerp(
		target_av, 1.0 - exp(-tuning.angular_response * delta)
	)


func _apply_air_forces(body_state: PhysicsDirectBodyState3D, delta: float) -> void:
	# Let a dodge's momentum play out without air control fighting it.
	if state == State.DODGING:
		return
	var basis: Basis = body_state.transform.basis.orthonormalized()
	var pitch_axis: Vector3 = basis.x    # +rotation = nose up
	var yaw_axis: Vector3 = -basis.y     # +rotation = nose right
	var roll_axis: Vector3 = -basis.z    # +rotation = roll right

	# W / throttle pitches the nose down in the air, S / brake pitches it up.
	var pitch_input: float = clampf(in_pitch - in_throttle + in_brake, -1.0, 1.0)
	# Holding air roll turns steering into roll instead of yaw.
	var yaw_input: float = in_steer
	var roll_input: float = 0.0
	if in_roll > 0.5:
		roll_input = in_steer
		yaw_input = 0.0

	# Drive angular velocity toward a target rate: snappy response, and the
	# car stops rotating when the stick is released.
	var target_av: Vector3 = (
		pitch_axis * pitch_input * tuning.air_pitch_torque
		+ yaw_axis * yaw_input * tuning.air_yaw_torque
		+ roll_axis * roll_input * tuning.air_roll_torque
	)
	body_state.angular_velocity = body_state.angular_velocity.lerp(
		target_av, 1.0 - exp(-tuning.air_damping * delta)
	)


func _apply_boost(body_state: PhysicsDirectBodyState3D, _up_dir: Vector3) -> void:
	if not in_boost or boost == null:
		return
	if not boost.consume(body_state.step):
		return
	var forward: Vector3 = -body_state.transform.basis.z
	body_state.apply_central_force(forward * tuning.boost_accel * mass)


func _perform_jump(body_state: PhysicsDirectBodyState3D, up_dir: Vector3) -> void:
	if _grounded or _coyote > 0.0:
		body_state.apply_central_impulse(up_dir * tuning.jump_impulse * mass)
		_jumps_used = 1
		_air_time = 0.0
		_coyote = 0.0
		_grounded = false
		_set_state(State.AIRBORNE)
		return

	if _jumps_used == 1 and _air_time <= tuning.double_jump_window:
		var dir_local := dodge_direction(in_steer, in_throttle - in_brake)
		if dir_local == Vector3.ZERO:
			body_state.apply_central_impulse(up_dir * tuning.double_jump_impulse * mass)
			_jumps_used = 2
		else:
			var world_dir: Vector3 = (body_state.transform.basis * dir_local).normalized()
			world_dir = (world_dir - up_dir * world_dir.dot(up_dir)).normalized()
			body_state.apply_central_impulse(
				(world_dir * tuning.dodge_impulse + up_dir * tuning.dodge_up_bias) * mass
			)
			_dodge_dir = world_dir
			_dodge_timer = tuning.dodge_duration
			_jumps_used = 2
			_set_state(State.DODGING)


## Pure 8-way mapping from steering / throttle inputs to a car-local direction.
## Returns Vector3.ZERO when no direction is held (that means double jump).
static func dodge_direction(steer: float, pitch: float) -> Vector3:
	var x: float = 0.0
	var z: float = 0.0
	if absf(steer) > 0.25:
		x = signf(steer)
	if absf(pitch) > 0.25:
		z = -signf(pitch)
	var dir := Vector3(x, 0.0, z)
	if dir.length_squared() < 0.001:
		return Vector3.ZERO
	return dir.normalized()


func _update_speed_readout(body_state: PhysicsDirectBodyState3D) -> void:
	speed = body_state.linear_velocity.length()
	var supersonic: bool = speed >= tuning.supersonic_speed
	if supersonic != is_supersonic:
		is_supersonic = supersonic
		supersonic_changed.emit(is_supersonic)


func _set_state(new_state: int) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(state)
	Events.car_state_changed.emit(self, state)


func reset_to_transform(xform: Transform3D) -> void:
	global_transform = xform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	speed = 0.0
	is_supersonic = false
	_grounded = false
	_jumps_used = 0
	_air_time = 0.0
	_coyote = 0.0
	_dodge_timer = 0.0
	_dodge_dir = Vector3.ZERO
	_jump_queued = false
	_set_state(State.AIRBORNE)


func set_controls_enabled(value: bool) -> void:
	controls_enabled = value
	if not value:
		_zero_input()


func _project_to_plane(vec: Vector3, n: Vector3) -> Vector3:
	var out := vec - n * vec.dot(n)
	if out.length_squared() > 0.0001:
		out = out.normalized()
	return out
