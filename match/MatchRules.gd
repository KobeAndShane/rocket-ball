class_name MatchRules
extends Resource
## Match-level rules and gravity phase configuration (Tasks 04/05).

@export var match_time: float = 300.0
@export var overtime_enabled: bool = true
@export var goal_pause_time: float = 2.5
@export var countdown_time: float = 3.0

@export_group("Gravity")
@export var shift_interval: float = 30.0
@export var shift_warning: float = 5.0
@export var shift_transition: float = 2.0
@export var gravity_strength: float = 9.8
@export var random_shifts: bool = false
@export var seed_value: int = 12345
@export var boost_refill_on_shift: float = 8.0
@export var phases: Array[Vector3] = [
	Vector3(0.0, -1.0, 0.0),
	Vector3(0.0, 0.0, -1.0),
	Vector3(0.0, 1.0, 0.0),
	Vector3(0.0, 0.0, 1.0),
]
