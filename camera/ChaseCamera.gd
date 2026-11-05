extends Camera3D
class_name ChaseCamera
## Chase / ball camera (Task 06). Reads interpolated physics transforms and
## smooths "up" from GravityManager so gravity shifts never snap or roll-flip.

@export var target: Car
@export var ball: Ball
@export var distance: float = 9.0
@export var height: float = 3.6
@export var stiffness: float = 6.0
@export var ball_cam: bool = false

var _smooth_up: Vector3 = Vector3.UP
var _smooth_pos: Vector3 = Vector3.ZERO
var _look_target: Vector3 = Vector3.ZERO
var _initialised: bool = false
var _ball_cam_requested: bool = false


func setup(p_target: Car, p_ball: Ball) -> void:
	target = p_target
	ball = p_ball
	distance = float(Settings.get_setting("camera/distance", 9.0))
	height = float(Settings.get_setting("camera/height", 3.6))
	stiffness = float(Settings.get_setting("camera/stiffness", 6.0))
	fov = float(Settings.get_setting("camera/fov", 80.0))
	ball_cam = bool(Settings.get_setting("camera/ball_cam", false))
	current = true


func _process(delta: float) -> void:
	if target == null:
		return
	if Input.is_action_just_pressed("ball_cam"):
		ball_cam = not ball_cam
		Settings.set_setting("camera/ball_cam", ball_cam)

	var reduced_motion: bool = bool(Settings.get_setting("accessibility/reduced_motion", false))
	var up_target: Vector3 = GravityManager.up
	var up_weight: float = 1.0 - exp(-(2.0 if reduced_motion else 7.0) * delta)
	_smooth_up = _smooth_up.slerp(up_target, clampf(up_weight, 0.0, 1.0)).normalized()
	if _smooth_up.length_squared() < 0.01:
		_smooth_up = up_target

	var car_xform: Transform3D = target.get_global_transform_interpolated()
	var car_pos: Vector3 = car_xform.origin
	var car_fwd: Vector3 = -car_xform.basis.z
	car_fwd -= _smooth_up * car_fwd.dot(_smooth_up)
	if car_fwd.length_squared() < 0.01:
		car_fwd = _smooth_up.cross(Vector3.RIGHT)
	car_fwd = car_fwd.normalized()

	var look_behind: bool = Input.is_action_pressed("look_behind")
	var backwards: float = -1.0 if look_behind else 1.0
	var wanted_distance: float = distance
	var wanted_height: float = height
	var desired: Vector3 = car_pos + _smooth_up * wanted_height - car_fwd * wanted_distance * backwards

	# Spring-arm collision against the arena.
	var ray_from: Vector3 = car_pos + _smooth_up * 1.0
	var query := PhysicsRayQueryParameters3D.create(ray_from, desired, 1)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		desired = (hit.position as Vector3) + (ray_from - desired).normalized() * 0.4

	if not _initialised:
		_smooth_pos = desired
		_look_target = car_pos + _smooth_up * 1.4
		_initialised = true

	var pos_weight: float = 1.0 - exp(-stiffness * delta)
	_smooth_pos = _smooth_pos.lerp(desired, clampf(pos_weight, 0.0, 1.0))

	var look_point: Vector3
	if ball_cam and ball != null:
		look_point = ball.get_global_transform_interpolated().origin
	else:
		look_point = car_pos + _smooth_up * 1.4 + car_fwd * 5.0
	var look_weight: float = 1.0 - exp(-(5.0 if reduced_motion else 10.0) * delta)
	_look_target = _look_target.lerp(look_point, clampf(look_weight, 0.0, 1.0))

	global_position = _smooth_pos
	if global_position.distance_squared_to(_look_target) > 0.001:
		look_at(_look_target, _smooth_up)
