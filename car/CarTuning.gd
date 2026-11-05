class_name CarTuning
extends Resource
## All car numbers live here (Task 01). Never hardcode tuning in Car.gd.

@export_group("Body")
@export var mass: float = 22.0
@export var body_size: Vector3 = Vector3(1.9, 0.8, 3.0)
@export var track_width: float = 1.6
@export var wheelbase: float = 2.1
@export var wheel_anchor_height: float = -0.3

@export_group("Driving")
@export var max_ground_speed: float = 32.0
@export var max_reverse_speed: float = 12.0
@export var engine_accel: float = 42.0
@export var brake_accel: float = 55.0
@export var coast_drag: float = 5.0
@export var turn_rate: float = 2.7
@export var turn_rate_fast: float = 1.45
@export var angular_response: float = 16.0
@export var align_rate: float = 9.0
@export var grip: float = 0.95
@export var handbrake_grip: float = 0.28
@export var stick_force: float = 6.0
@export var supersonic_speed: float = 24.0

@export_group("Suspension")
@export var suspension_rest: float = 0.5
@export var suspension_ray_length: float = 0.95
@export var spring_strength: float = 1500.0
@export var spring_damping: float = 90.0
@export var min_wheels_grounded: int = 2
@export var coyote_time: float = 0.1

@export_group("Air")
@export var jump_impulse: float = 11.0
@export var double_jump_impulse: float = 9.5
@export var double_jump_window: float = 1.5
@export var dodge_impulse: float = 15.0
@export var dodge_up_bias: float = 2.5
@export var dodge_duration: float = 0.45
## Max air rotation rates in rad/s (names kept for saved .tres compatibility).
@export var air_pitch_torque: float = 5.0
@export var air_yaw_torque: float = 4.5
@export var air_roll_torque: float = 5.5
## How quickly air rotation reaches the target rate (1/s). Higher = snappier.
@export var air_damping: float = 10.0

@export_group("Boost")
@export var boost_accel: float = 30.0
@export var boost_consumption: float = 33.0
@export var boost_capacity: float = 100.0
