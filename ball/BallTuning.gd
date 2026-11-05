class_name BallTuning
extends Resource
## Ball tuning (Task 02). Create BallTuning.tres from this resource.

@export_group("Body")
@export var radius: float = 2.4
@export var mass: float = 28.0
@export var linear_damp: float = 0.15
@export var angular_damp: float = 0.2
@export var max_speed: float = 70.0

@export_group("Material")
@export var bounce: float = 0.6
@export var friction: float = 0.15

@export_group("Hits")
@export var hit_transfer: float = 0.55
@export var max_hit_impulse: float = 260.0
@export var pop_bias: float = 0.45
@export var spin_transfer: float = 0.35
@export var hit_cooldown: float = 0.08
