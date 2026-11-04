class_name BotTier
extends Resource
## One difficulty preset. Higher tiers react faster and aim better.

@export var display_name: String = "Rookie"
@export var update_hz: float = 30.0
@export var reaction_delay: float = 0.1
@export var aim_error: float = 0.12
@export var boost_use: float = 0.7
@export var prediction_time: float = 0.7
@export var aerial_skill: float = 0.5
@export var aggression: float = 0.6
@export var speed_scale: float = 1.0
@export var defend_bias: float = 0.5
