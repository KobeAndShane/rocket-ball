class_name BallTuning
extends Resource

@export_group("Body")
@export var mass: float = 30.0
@export var radius: float = 2.0
@export var linear_damping: float = 0.12
@export var angular_damping: float = 0.35
@export var bounce: float = 0.62
@export var friction: float = 0.05

@export_group("Limits")
@export var max_speed: float = 55.0
@export var max_angular_speed: float = 32.0

@export_group("Hits")
@export var hit_gain: float = 0.18
@export var pop_up_impulse: float = 3.6
@export var spin_transfer: float = 0.32
@export var min_hit_speed: float = 3.0
@export var hit_cooldown: float = 0.22

@export_group("Respawn")
@export var kickoff_height: float = 6.0
