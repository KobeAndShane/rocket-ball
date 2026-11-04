class_name Car
extends RigidBody3D
## Arcade car body. All forces are applied in _integrate_forces at 120 Hz.
## Gravity comes only from GravityManager and is applied manually.

signal state_changed(new_state: int)
signal demolished(attacker_id: int)
signal respawned
signal supersonic_changed(active: bool)

enum State { GROUNDED, AIRBORNE, DODGING, DEMOLISHED }
enum DriveMode { HUMAN, BOT, NETWORK }

const ARENA_LAYER := 1
const CAR_LAYER := 1 << 1
const BALL_LAYER := 1 << 2
const GOAL_LAYER := 1 << 4
const CAR_MASK := ARENA_LAYER | CAR_LAYER | BALL_LAYER | GOAL_LAYER

@export var tuning: CarTuning
@export var team: int = 1
@export var car_id: int = 0
@export var display_name: String = "Pilot"
@export var control_mode: DriveMode = DriveMode.HUMAN
@export var friendly_fire: bool = false
@export var auto_respawn: bool = true
@export var demolition_enabled: bool = true
@export var frozen: bool = false

var state: State = State.AIRBORNE
var input := CarInput.new()
var wheels_on_ground: int = 0
var ground_normal: Vector3 = Vector3.UP
var ground_forward: Vector3 = Vector3.FORWARD
var is_supersonic: bool = false
var speed: float = 0.0
var forward_speed: float = 0.0
var boost_component: BoostComponent
var spawn_transform: Transform3D = Transform3D.IDENTITY

var _air_time: float = 0.0
var _jumps_used: int = 0
var _dodge_timer: float = 0.0
var _respawn_timer: float = 0.0
var _demolish_attacker: int = -1
var _demolish_cooldown: float = 0.0
var _jump_ignore: float = 0.0
var _last_state: State = State.AIRBORNE
var _body_meshes: Array[MeshInstance3D] = []
var _team_material: StandardMaterial3D
var _wheel_nodes: Array[Node3D] = []
var _name_tag: Label3D
var _is_local_visual: bool = false
var _external_pending: bool = false
var _network_tick: int = 0
var _state_packets: Array[Dictionary] = []


func _ready() -> void:
	if tuning == null:
		tuning = load("res://car/CarTuning.tres") as CarTuning
	mass = tuning.mass
	gravity_scale = 0.0
	can_sleep = false
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = tuning.center_of_mass_offset
	collision_layer = CAR_LAYER
	collision_mask = CAR_MASK
	_resize_collider()
	boost_component = get_node_or_null("BoostComponent") as BoostComponent
	if boost_component != null:
		boost_component.set_tuning(tuning)
		boost_component.changed.connect(_on_boost_changed)
		boost_component.depleted.connect(_on_boost_depleted)
	body_entered.connect(_on_body_entered)
	_build_visuals()
	spawn_transform = global_transform
	Events.gravity_shift_finished.connect(_on_gravity_shift_finished)
	_last_state = state


func _exit_tree() -> void:
	if Events.gravity_shift_finished.is_connected(_on_gravity_shift_finished):
		Events.gravity_shift_finished.disconnect(_on_gravity_shift_finished)


func _resize_collider() -> void:
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		return
	if shape_node.shape is BoxShape3D:
		(shape_node.shape as BoxShape3D).size = tuning.collider_size


func _build_visuals() -> void:
	var body := get_node_or_null("BodyMesh") as MeshInstance3D
	var cabin := get_node_or_null("CabinMesh") as MeshInstance3D
	if body != null:
		_body_meshes.append(body)
	if cabin != null:
		_body_meshes.append(cabin)
	_team_material = StandardMaterial3D.new()
	_team_material.albedo_color = team_color()
	_team_material.metallic = 0.45
	_team_material.roughness = 0.35
	_team_material.emission_enabled = true
	_team_material.emission = team_color() * 0.22
	for m in _body_meshes:
		m.material_override = _team_material
	# Wheels are visual-only; physics uses rays.
	var wheel_mesh := CylinderMesh.new()
	wheel_mesh.top_radius = tuning.wheel_radius
	wheel_mesh.bottom_radius = tuning.wheel_radius
	wheel_mesh.height = 0.16
	wheel_mesh.radial_segments = 12
	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.05, 0.05, 0.06)
	wheel_mat.roughness = 0.9
	for off: Vector3 in tuning.wheel_offsets:
		var wheel := MeshInstance3D.new()
		wheel.mesh = wheel_mesh
		wheel.material_override = wheel_mat
		wheel.position = off
		wheel.rotation_degrees = Vector3(0, 0, 90)
		add_child(wheel)
		_wheel_nodes.append(wheel)
	_name_tag = Label3D.new()
	_name_tag.text = display_name
	_name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_tag.font_size = 42
	_name_tag.pixel_size = 0.0045
	_name_tag.position = Vector3(0.0, 1.35, 0.0)
	_name_tag.modulate = team_color()
	_name_tag.outline_size = 8
	_name_tag.no_depth_test = true
	_name_tag.render_priority = 10
	add_child(_name_tag)


func team_color() -> Color:
	if team == 1:
		return Settings.get_color("a11y/team1_color") if Settings.get_bool("a11y/team_color_override") else Color(0.18, 0.64, 1.0)
	if team == 2:
		return Settings.get_color("a11y/team2_color") if Settings.get_bool("a11y/team_color_override") else Color(1.0, 0.42, 0.16)
	return Color(0.75, 0.75, 0.8)


func set_team(new_team: int) -> void:
	team = new_team
	if _team_material != null:
		_team_material.albedo_color = team_color()
		_team_material.emission = team_color() * 0.22
	if _name_tag != null:
		_name_tag.modulate = team_color()


func set_display_name(new_name: String) -> void:
	display_name = new_name
	if _name_tag != null:
		_name_tag.text = new_name


func set_frozen(value: bool) -> void:
	frozen = value
	if frozen:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		input = CarInput.new()


func set_local_player(value: bool) -> void:
	_is_local_visual = value
	control_mode = DriveMode.HUMAN if value else control_mode


func is_local_player_visual() -> bool:
	return _is_local_visual


func _physics_process(delta: float) -> void:
	speed = linear_velocity.length()
	if state != State.DEMOLISHED:
		var sup: bool = speed >= tuning.supersonic_speed
		if sup != is_supersonic:
			is_supersonic = sup
			supersonic_changed.emit(sup)
	if state == State.DEMOLISHED:
		_respawn_timer -= delta
		if auto_respawn and _respawn_timer <= 0.0:
			respawn(spawn_transform)
		return
	if frozen:
		return
	if control_mode == DriveMode.HUMAN and _is_local_visual:
		_gather_human_input()
	_demolish_cooldown = maxf(0.0, _demolish_cooldown - delta)
	if _external_pending:
		_external_pending = false


func _gather_human_input() -> void:
	if not input_enabled():
		input.throttle = 0.0
		input.steer = 0.0
		return
	input.throttle = Settings.axis_from_actions("brake", "throttle")
	input.steer = Settings.axis_from_actions("steer_left", "steer_right")
	input.jump_pressed = Input.is_action_just_pressed("jump")
	input.jump_held = Input.is_action_pressed("jump")
	input.boost = Input.is_action_pressed("boost")
	input.handbrake = Input.is_action_pressed("handbrake")
	input.air_roll = Input.is_action_pressed("air_roll")
	input.pitch = -input.throttle
	input.yaw = input.steer
	input.roll = 0.0
	if input.air_roll:
		input.roll = input.steer
		input.yaw = 0.0
	if Settings.get_bool("controls/invert_pitch"):
		input.pitch = -input.pitch


func input_enabled() -> bool:
	return state != State.DEMOLISHED and not frozen


## Used by bots and network clients. The edge flag is consumed by the next tick.
func apply_input(new_input: CarInput) -> void:
	input.copy_from(new_input)
	_external_pending = true


func _integrate_forces(ps: PhysicsDirectBodyState3D) -> void:
	var dt: float = ps.step
	var up: Vector3 = GravityManager.up
	if state == State.DEMOLISHED or frozen:
		ps.linear_velocity = Vector3.ZERO
		ps.angular_velocity = Vector3.ZERO
		input.clear_edges()
		return
	_jump_ignore = maxf(0.0, _jump_ignore - dt)
	# --- Gravity (single source of truth) -------------------------------------
	ps.linear_velocity += GravityManager.gravity_dir * GravityManager.gravity_strength * dt

	# --- Wheel rays ------------------------------------------------------------
	var space := ps.get_space_state()
	var ray_len: float = tuning.suspension_rest_length + tuning.wheel_radius
	var ray_down: Vector3 = -ps.transform.basis.y.normalized()
	var hits: int = 0
	var normal_sum := Vector3.ZERO
	var contact_acc := Vector3.ZERO
	var contact_points: Array[Vector3] = []
	for off: Vector3 in tuning.wheel_offsets:
		var mount_world: Vector3 = ps.transform * off
		var to: Vector3 = mount_world + ray_down * ray_len
		var query := PhysicsRayQueryParameters3D.create(mount_world, to, ARENA_LAYER, [get_rid()])
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var normal: Vector3 = hit["normal"]
		var point: Vector3 = hit["position"]
		var distance: float = mount_world.distance_to(point)
		var compression: float = ray_len - distance
		if compression < -0.02:
			continue
		hits += 1
		normal_sum += normal
		contact_acc += point
		contact_points.append(point)
		var point_vel: Vector3 = ps.linear_velocity + ps.angular_velocity.cross(point - ps.transform.origin)
		var along: float = point_vel.dot(normal)
		var spring_force: float = tuning.suspension_stiffness * maxf(0.0, compression) - tuning.suspension_damping * along
		spring_force = clampf(spring_force, 0.0, tuning.suspension_stiffness * (tuning.suspension_rest_length + tuning.suspension_travel))
		if spring_force > 0.0:
			ps.apply_force(normal * spring_force, point - ps.transform.origin)
	wheels_on_ground = hits
	if hits > 0:
		ground_normal = normal_sum.normalized()
	else:
		ground_normal = up

	var grounded: bool = hits > 0 and _jump_ignore <= 0.0
	var was_grounded: bool = state == State.GROUNDED
	if grounded and not was_grounded and state != State.DODGING:
		_land()
	elif not grounded and was_grounded:
		_take_off()

	# --- Local axes on the contact plane --------------------------------------
	var car_forward: Vector3 = -ps.transform.basis.z
	ground_forward = car_forward - ground_normal * car_forward.dot(ground_normal)
	if ground_forward.length_squared() < 0.001:
		ground_forward = -ps.transform.basis.z
	ground_forward = ground_forward.normalized()
	var side: Vector3 = ground_normal.cross(ground_forward).normalized()
	forward_speed = ps.linear_velocity.dot(ground_forward)

	# --- Ground drive ---------------------------------------------------------
	if grounded:
		var throttle: float = input.throttle
		if absf(throttle) > 0.01:
			var force: float = 0.0
			if throttle > 0.0:
				force = tuning.brake_force if forward_speed < -0.8 else tuning.drive_force
				force *= throttle
			else:
				force = tuning.brake_force if forward_speed > 0.8 else tuning.reverse_force
				force *= throttle
			var speed_factor: float = clampf(1.0 - absf(forward_speed) / maxf(tuning.max_speed, 1.0), 0.12, 1.0)
			ps.apply_central_force(ground_forward * force * speed_factor)
		# Lateral grip, reduced by handbrake.
		var lateral: float = ps.linear_velocity.dot(side)
		var grip: float = tuning.handbrake_grip if input.handbrake else tuning.lateral_grip
		ps.linear_velocity -= side * lateral * clampf(grip * dt, 0.0, 1.0)
		# Rolling resistance.
		var resistance: float = tuning.rolling_resistance if absf(throttle) < 0.05 else tuning.rolling_resistance * 0.15
		ps.linear_velocity -= ground_forward * forward_speed * clampf(resistance * dt, 0.0, 1.0)
		# Speed-sensitive steering around the surface normal.
		var speed_t: float = clampf(absf(forward_speed) / tuning.high_speed_steer_speed, 0.0, 1.0)
		var desired_turn: float = lerpf(tuning.turn_rate_low, tuning.turn_rate_high, speed_t) * input.steer
		if forward_speed < -0.5:
			desired_turn = -desired_turn
		var current_turn: float = ps.angular_velocity.dot(ground_normal)
		var new_turn: float = lerpf(current_turn, desired_turn, clampf(tuning.steer_response * dt, 0.0, 1.0))
		ps.angular_velocity += ground_normal * (new_turn - current_turn)
		# Align chassis up with the surface normal.
		_align_to_normal(ps, ground_normal, dt)
		# Stick to walls/ceiling: extra force into the surface when 3+ wheels touch.
		if hits >= 3:
			ps.apply_central_force(-ground_normal * tuning.stick_force)
	elif state != State.DODGING:
		_air_control(ps, up, dt)

	# --- Jump / double jump / dodge ------------------------------------------
	if input.jump_pressed:
		_handle_jump(ps, grounded)
	# --- Boost ---------------------------------------------------------------
	if input.boost and boost_component != null and boost_component.consume(dt):
		var boost_dir: Vector3 = -ps.transform.basis.z.normalized()
		if grounded and boost_dir.dot(ground_normal) < -0.3:
			boost_dir = ground_forward
		ps.apply_central_force(boost_dir * tuning.boost_force)

	# --- Damping / clamps ----------------------------------------------------
	if state == State.DODGING:
		_dodge_timer -= dt
		ps.angular_velocity -= ps.angular_velocity * clampf(0.8 * dt, 0.0, 1.0)
		if _dodge_timer <= 0.0:
			_set_state(State.AIRBORNE if not grounded else State.GROUNDED)
	if not grounded:
		ps.angular_velocity -= ps.angular_velocity * clampf(tuning.air_angular_damping * dt, 0.0, 1.0)
	var max_ang: float = tuning.max_angular_speed
	if ps.angular_velocity.length() > max_ang:
		ps.angular_velocity = ps.angular_velocity.normalized() * max_ang
	var cap: float = tuning.boost_max_speed if input.boost else tuning.max_speed
	if ps.linear_velocity.length() > cap:
		ps.linear_velocity = ps.linear_velocity.normalized() * cap

	# --- State bookkeeping ---------------------------------------------------
	if not grounded and state == State.GROUNDED:
		_set_state(State.AIRBORNE)
	if grounded and state == State.AIRBORNE and _dodge_timer <= 0.0:
		_set_state(State.GROUNDED)
	if state != State.GROUNDED and state != State.DEMOLISHED:
		_air_time += dt
	if state == State.GROUNDED:
		_air_time = 0.0
		_jumps_used = 0
	input.clear_edges()


func _align_to_normal(ps: PhysicsDirectBodyState3D, normal: Vector3, _dt: float) -> void:
	var current_up: Vector3 = ps.transform.basis.y.normalized()
	var axis: Vector3 = current_up.cross(normal)
	var angle: float = current_up.angle_to(normal)
	if axis.length_squared() > 0.0001 and angle > 0.001:
		var torque: Vector3 = axis.normalized() * angle * tuning.alignment_torque
		# Damp only the angular velocity that fights alignment.
		var av_plane: Vector3 = ps.angular_velocity - normal * ps.angular_velocity.dot(normal)
		torque -= av_plane * tuning.alignment_damping
		ps.apply_torque(torque)


func _air_control(ps: PhysicsDirectBodyState3D, _up: Vector3, _dt: float) -> void:
	var basis: Basis = ps.transform.basis
	var pitch_axis: Vector3 = basis.x.normalized()
	var yaw_axis: Vector3 = -basis.y.normalized()
	var roll_axis: Vector3 = -basis.z.normalized()
	var pitch: float = clampf(input.pitch, -1.0, 1.0)
	var yaw: float = clampf(input.yaw, -1.0, 1.0)
	var roll: float = clampf(input.roll, -1.0, 1.0)
	if input.air_roll:
		if absf(roll) < 0.01:
			roll = clampf(input.steer, -1.0, 1.0)
		yaw *= 0.25
	ps.apply_torque(pitch_axis * pitch * tuning.air_pitch_torque)
	ps.apply_torque(yaw_axis * yaw * tuning.air_yaw_torque)
	ps.apply_torque(roll_axis * roll * tuning.air_roll_torque)
	# Neutral stick: slowly bring the wheels under the car so it can land on a
	# wall or ceiling after the gravity direction changes. Player input always
	# wins, and the torque is deliberately gentle.
	var neutral: bool = absf(pitch) < 0.05 and absf(yaw) < 0.05 and absf(roll) < 0.05
	if neutral and tuning.air_auto_level > 0.0:
		var car_up: Vector3 = basis.y.normalized()
		var want_up: Vector3 = GravityManager.up
		var axis: Vector3 = car_up.cross(want_up)
		var angle: float = car_up.angle_to(want_up)
		if axis.length_squared() > 0.0001 and angle > 0.01:
			var torque: Vector3 = axis.normalized() * angle * tuning.air_auto_level
			var av_plane: Vector3 = ps.angular_velocity - want_up * ps.angular_velocity.dot(want_up)
			torque -= av_plane * tuning.air_auto_level_damping
			ps.apply_torque(torque)


func _handle_jump(ps: PhysicsDirectBodyState3D, grounded: bool) -> void:
	if state == State.DEMOLISHED or state == State.DODGING:
		return
	if grounded and state == State.GROUNDED:
		var jump_dir: Vector3 = ground_normal if ground_normal.dot(GravityManager.up) > 0.2 else GravityManager.up
		ps.linear_velocity += jump_dir * tuning.jump_velocity
		_jumps_used = 1
		_jump_ignore = 0.1
		_air_time = 0.0
		_set_state(State.AIRBORNE)
		return
	if _jumps_used >= 2:
		return
	if _air_time > tuning.double_jump_window:
		return
	_jumps_used = 2
	var flat := Vector2(input.steer, input.throttle)
	if flat.length() > 0.22:
		var dir: Vector3 = CarInput.dodge_world_direction(flat, ps.transform.basis, GravityManager.up)
		ps.linear_velocity += dir * tuning.dodge_velocity + GravityManager.up * tuning.dodge_lift
		var spin_axis: Vector3 = dir.cross(GravityManager.up).normalized()
		ps.angular_velocity = spin_axis * tuning.dodge_spin
		_dodge_timer = tuning.dodge_lock_time
		_set_state(State.DODGING)
	else:
		ps.linear_velocity += GravityManager.up * tuning.double_jump_velocity
		_set_state(State.AIRBORNE)


func _land() -> void:
	_jumps_used = 0
	_air_time = 0.0
	_dodge_timer = 0.0
	_set_state(State.GROUNDED)


func _take_off() -> void:
	_jumps_used = 0
	_air_time = 0.0
	_set_state(State.AIRBORNE)


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	_last_state = new_state
	state_changed.emit(new_state)
	Events.car_state_changed.emit(car_id, new_state)


func _on_boost_changed(amount: float, _max_amount: float) -> void:
	Events.boost_changed.emit(car_id, amount)


func _on_boost_depleted() -> void:
	pass


func _on_gravity_shift_finished(_phase: int) -> void:
	if boost_component != null and tuning.boost_refill_on_shift > 0.0:
		boost_component.add(tuning.boost_refill_on_shift)
		Events.boost_pulse.emit(car_id, tuning.boost_refill_on_shift)


func _on_body_entered(body: Node) -> void:
	if state == State.DEMOLISHED:
		return
	if body is Car:
		var other := body as Car
		if not demolition_enabled or not other.demolition_enabled:
			return
		if team != 0 and other.team == team and not friendly_fire:
			return
		if _demolish_cooldown > 0.0 or other._demolish_cooldown > 0.0:
			return
		if get_speed() >= tuning.demolish_speed and other.state != Car.State.DEMOLISHED:
			other.demolish(car_id)
			_demolish_cooldown = 0.5


func demolish(attacker_id: int) -> void:
	if state == State.DEMOLISHED:
		return
	_demolish_attacker = attacker_id
	_set_state(State.DEMOLISHED)
	_respawn_timer = tuning.demolish_respawn_time
	visible = false
	collision_layer = 0
	collision_mask = 0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	Events.car_demolished.emit(car_id, attacker_id)
	demolished.emit(attacker_id)


func respawn(new_transform: Transform3D) -> void:
	spawn_transform = new_transform
	global_transform = new_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	visible = true
	collision_layer = CAR_LAYER
	collision_mask = CAR_MASK
	_jumps_used = 0
	_air_time = 0.0
	_dodge_timer = 0.0
	_demolish_cooldown = 0.5
	if boost_component != null:
		boost_component.reset()
	_set_state(State.AIRBORNE)
	respawned.emit()
	Events.car_respawned.emit(car_id)


func reset_to_kickoff(new_transform: Transform3D) -> void:
	respawn(new_transform)


func get_speed() -> float:
	return linear_velocity.length()


func get_local_up() -> Vector3:
	return global_transform.basis.y.normalized()


func get_forward() -> Vector3:
	return -global_transform.basis.z.normalized()


func is_grounded() -> bool:
	return state == State.GROUNDED


## Network: compact state for snapshots (position, orientation, velocity).
func get_snapshot_state() -> Dictionary:
	return {
		"p": global_position,
		"q": global_transform.basis.get_rotation_quaternion(),
		"v": linear_velocity,
		"w": angular_velocity,
		"b": boost_component.amount if boost_component != null else 0.0,
		"s": state,
		"t": Engine.get_physics_frames(),
	}


func set_snapshot_state(snap: Dictionary) -> void:
	if state == State.DEMOLISHED:
		return
	global_position = snap.get("p", global_position)
	var q: Quaternion = snap.get("q", Quaternion.IDENTITY)
	global_transform = Transform3D(Basis(q), global_position)
	linear_velocity = snap.get("v", Vector3.ZERO)
	angular_velocity = snap.get("w", Vector3.ZERO)
	if boost_component != null:
		boost_component.set_amount(float(snap.get("b", 0.0)))
