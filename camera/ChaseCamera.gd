class_name ChaseCamera
extends Camera3D
## Visual-only chase camera. Physics transforms are read interpolated; the
## camera never writes to physics bodies.

const ARENA_LAYER := 1
const WORLD_HORIZON := Vector3(0.0, 1.0, 0.0)

@export var target: Car
@export var ball: Ball
@export var distance: float = 7.2
@export var height: float = 2.4
@export var angle_deg: float = -12.0
@export var stiffness: float = 8.0
@export var up_rate: float = 6.0

var ball_cam_enabled: bool = true
var free_camera: bool = false
var spectator_target: Node3D = null

var _smooth_up: Vector3 = Vector3.UP
var _smooth_look: Vector3 = Vector3.ZERO
var _smooth_pos: Vector3 = Vector3.ZERO
var _has_snapshot: bool = false
var _shake: float = 0.0
var _shake_time: float = 0.0
var _replay_active: bool = false
var _replay_time: float = 0.0
var _replay_duration: float = 0.0
var _replay_focus: Vector3 = Vector3.ZERO
var _ball_cam_blend: float = 0.55
var _reduced_motion: bool = false
var _fixed_horizon: bool = false
var _shake_scale: float = 1.0
var _fov_setting: float = 100.0
var _look_behind: bool = false
var _free_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	current = true
	near = 0.08
	far = 420.0
	_apply_settings()
	_smooth_up = GravityManager.up
	Events.settings_changed.connect(_on_settings_changed)
	Events.screen_shake.connect(_on_screen_shake)
	Events.gravity_shift_started.connect(_on_shift_started)


func _exit_tree() -> void:
	if Events.settings_changed.is_connected(_on_settings_changed):
		Events.settings_changed.disconnect(_on_settings_changed)
	if Events.screen_shake.is_connected(_on_screen_shake):
		Events.screen_shake.disconnect(_on_screen_shake)


func setup(car: Car, ball_ref: Ball) -> void:
	target = car
	ball = ball_ref
	_has_snapshot = false


func _apply_settings() -> void:
	_ball_cam_blend = Settings.get_float("camera/ball_cam_blend")
	_reduced_motion = Settings.get_bool("a11y/reduced_motion")
	_fixed_horizon = Settings.get_bool("a11y/fixed_horizon")
	_shake_scale = Settings.get_float("a11y/screen_shake")
	_fov_setting = Settings.get_float("camera/fov")
	distance = Settings.get_float("camera/distance")
	height = Settings.get_float("camera/height")
	angle_deg = Settings.get_float("camera/angle")
	stiffness = Settings.get_float("camera/stiffness")
	ball_cam_enabled = Settings.get_bool("camera/ball_cam")


func _on_settings_changed(key: String, _value: Variant) -> void:
	if key.begins_with("camera/") or key.begins_with("a11y/"):
		_apply_settings()


func _on_screen_shake(strength: float, duration: float) -> void:
	_shake = maxf(_shake, strength)
	_shake_time = maxf(_shake_time, duration)


func _on_shift_started(_from: Vector3, _to: Vector3, _duration: float) -> void:
	if _reduced_motion:
		return


func _process(delta: float) -> void:
	if _replay_active:
		_update_replay(delta)
		return
	if free_camera:
		_update_free(delta)
		return
	if target == null or not is_instance_valid(target):
		return
	if target.control_mode == Car.DriveMode.HUMAN and target.is_local_player_visual():
		_handle_input()
	var raw_up: Vector3 = WORLD_HORIZON if _fixed_horizon else GravityManager.up
	var rate: float = up_rate * (0.28 if _reduced_motion else 1.0)
	_smooth_up = _slerp_safe(_smooth_up, raw_up, 1.0 - exp(-rate * delta))
	var tf: Transform3D = target.get_global_transform_interpolated()
	var car_pos: Vector3 = tf.origin
	var forward: Vector3 = -tf.basis.z
	forward = forward - _smooth_up * forward.dot(_smooth_up)
	if forward.length_squared() < 0.001:
		forward = -_smooth_up.cross(tf.basis.x).normalized()
	forward = forward.normalized()
	if _look_behind:
		forward = -forward
	var desired: Vector3 = car_pos + _smooth_up * height - forward * distance
	desired = _avoid_geometry(car_pos + _smooth_up * 0.9, desired)
	var damp: float = stiffness * (0.45 if _reduced_motion else 1.0)
	var pos_k: float = 1.0 - exp(-damp * delta)
	if not _has_snapshot:
		_smooth_pos = desired
		_has_snapshot = true
	else:
		_smooth_pos = _smooth_pos.lerp(desired, pos_k)
	var car_look: Vector3 = car_pos + forward * 5.0 + _smooth_up * 0.65
	var look_target: Vector3 = car_look
	if ball_cam_enabled and ball != null and is_instance_valid(ball):
		var ball_blend: float = _ball_cam_blend
		if _reduced_motion:
			ball_blend *= 0.7
		look_target = car_look.lerp(ball.global_position, ball_blend)
	_smooth_look = _smooth_look.lerp(look_target, 1.0 - exp(-(stiffness + 4.0) * delta)) if _has_snapshot and _smooth_look != Vector3.ZERO else look_target
	var up_vec: Vector3 = _smooth_up
	var dir: Vector3 = (_smooth_look - _smooth_pos)
	if dir.length_squared() < 0.01:
		dir = forward
	if absf(dir.normalized().dot(up_vec)) > 0.995:
		up_vec = forward.cross(up_vec).normalized()
	var basis := Transform3D.IDENTITY.looking_at(_smooth_look, up_vec).basis
	var final_pos: Vector3 = _smooth_pos
	fov = lerpf(fov, _fov_setting, 1.0 - exp(-8.0 * delta))
	if _shake > 0.001:
		_shake_time -= delta
		_shake = maxf(0.0, _shake - delta * 2.2)
		_shake_time = maxf(0.0, _shake_time - delta)
		var amp: float = _shake * _shake_scale * (0.15 if _reduced_motion else 0.4)
		var t: float = Time.get_ticks_msec() * 0.001
		final_pos += basis.x * sin(t * 73.0) * amp
		final_pos += basis.y * cos(t * 61.0) * amp * 0.7
	global_transform = Transform3D(basis, final_pos)


func _handle_input() -> void:
	if Input.is_action_just_pressed("ball_cam"):
		ball_cam_enabled = not ball_cam_enabled
		Settings.set_setting("camera/ball_cam", ball_cam_enabled)
	_look_behind = Input.is_action_pressed("look_behind")


func _avoid_geometry(from: Vector3, to: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	if space == null:
		return to
	var query := PhysicsRayQueryParameters3D.create(from, to, ARENA_LAYER)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return to
	var normal: Vector3 = hit["normal"]
	return (hit["position"] as Vector3) + normal * 0.35


func _slerp_safe(from: Vector3, to: Vector3, t: float) -> Vector3:
	var a := from.normalized()
	var b := to.normalized()
	if a.length_squared() < 0.1:
		return b
	if a.dot(b) < -0.9995:
		return a.rotated(Vector3(0.0, 0.0, 1.0), PI * clampf(t, 0.0, 1.0)).normalized()
	var out := a.slerp(b, clampf(t, 0.0, 1.0))
	return out.normalized() if out.length_squared() > 0.1 else b


func start_replay(focus: Vector3, duration: float) -> void:
	_replay_active = true
	_replay_time = 0.0
	_replay_duration = maxf(duration, 0.5)
	_replay_focus = focus


func stop_replay() -> void:
	_replay_active = false
	_has_snapshot = false


func _update_replay(delta: float) -> void:
	_replay_time += delta
	var t: float = _replay_time * 0.55
	var up: Vector3 = GravityManager.up
	var right := Vector3(1.0, 0.0, 0.0)
	if absf(up.dot(right)) > 0.9:
		right = Vector3(0.0, 0.0, 1.0)
	var fwd := up.cross(right).normalized()
	var radius: float = 17.0 - minf(_replay_time * 1.2, 5.0)
	var pos: Vector3 = _replay_focus + right * cos(t) * radius + fwd * sin(t) * radius + up * 8.0
	var look := _replay_focus
	var basis := Transform3D.IDENTITY.looking_at(look, up).basis
	global_transform = Transform3D(basis, pos)
	if _replay_time >= _replay_duration:
		_replay_active = false


func set_free_camera(enabled: bool) -> void:
	free_camera = enabled
	_has_snapshot = false


func _update_free(delta: float) -> void:
	var up: Vector3 = GravityManager.up
	var input2 := Input.get_vector("steer_left", "steer_right", "brake", "throttle")
	var forward: Vector3 = -global_transform.basis.z
	var right: Vector3 = global_transform.basis.x
	var move: Vector3 = right * input2.x + forward * input2.y
	if Input.is_action_pressed("jump"):
		move += up
	if Input.is_action_pressed("handbrake"):
		move -= up
	_free_velocity = _free_velocity.lerp(move * 24.0, 1.0 - exp(-6.0 * delta))
	global_position += _free_velocity * delta
	if Input.is_action_pressed("look_behind"):
		global_rotate(up, 1.8 * delta)


func set_spectator(node: Node3D) -> void:
	spectator_target = node
	if node is Car:
		target = node as Car
		_has_snapshot = false
