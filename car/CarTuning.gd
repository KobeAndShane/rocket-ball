class_name CarTuning
extends Resource
## All car numbers live here. No gameplay magic numbers in Car.gd.

@export_group("Body")
@export var mass: float = 180.0
@export var collider_size: Vector3 = Vector3(1.9, 0.68, 3.4)
@export var center_of_mass_offset: Vector3 = Vector3(0.0, -0.18, 0.0)

@export_group("Drive")
@export var drive_force: float = 3600.0
@export var reverse_force: float = 2400.0
@export var brake_force: float = 6200.0
@export var max_speed: float = 34.0
@export var boost_max_speed: float = 48.0
@export var rolling_resistance: float = 0.55
@export var lateral_grip: float = 9.0
@export var handbrake_grip: float = 1.6
@export var turn_rate_low: float = 2.75
@export var turn_rate_high: float = 1.25
@export var steer_response: float = 11.0
@export var high_speed_steer_speed: float = 26.0

@export_group("Suspension")
@export var wheel_offsets: Array[Vector3] = [
	Vector3(-0.82, -0.30, -1.12),
	Vector3(0.82, -0.30, -1.12),
	Vector3(-0.82, -0.30, 1.12),
	Vector3(0.82, -0.30, 1.12),
]
@export var wheel_radius: float = 0.20
@export var suspension_rest_length: float = 0.34
@export var suspension_travel: float = 0.16
@export var suspension_stiffness: float = 46000.0
@export var suspension_damping: float = 5200.0
@export var stick_force: float = 1800.0
@export var alignment_torque: float = 900.0
@export var alignment_damping: float = 420.0

@export_group("Jump / dodge")
@export var jump_velocity: float = 7.3
@export var double_jump_velocity: float = 6.6
@export var double_jump_window: float = 1.45
@export var dodge_velocity: float = 10.5
@export var dodge_lift: float = 3.2
@export var dodge_spin: float = 11.0
@export var dodge_lock_time: float = 0.55

@export_group("Air control")
@export var air_pitch_torque: float = 1250.0
@export var air_yaw_torque: float = 950.0
@export var air_roll_torque: float = 780.0
@export var air_angular_damping: float = 1.1
@export var max_angular_speed: float = 9.0
## Gentle auto-level toward local gravity while the stick is neutral, so a car
## that is thrown off a surface lands on its wheels after a gravity shift.
@export var air_auto_level: float = 240.0
@export var air_auto_level_damping: float = 55.0

@export_group("Boost")
@export var boost_max: float = 100.0
@export var boost_consumption: float = 33.3
@export var boost_force: float = 5200.0
@export var boost_refill_on_shift: float = 15.0
@export var supersonic_speed: float = 24.0

@export_group("Demolition")
@export var demolish_speed: float = 22.0
@export var demolish_respawn_time: float = 3.0

@export_group("Network")
@export var prediction_max_error: float = 0.35
@export var prediction_smooth_rate: float = 12.0
