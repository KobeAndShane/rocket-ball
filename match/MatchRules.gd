class_name MatchRules
extends Resource
## Per-match configuration. Every mode, private lobby and mutator reads this.

@export_group("Match")
@export var mode_name: String = "Standard"
@export var team_size: int = 3
@export var match_duration: float = 300.0
@export var score_limit: int = 0
@export var overtime_enabled: bool = true
@export var kickoff_countdown: float = 3.0
@export var goal_pause: float = 3.0
@export var replay_enabled: bool = true
@export var replay_duration: float = 3.5
@export var fill_with_bots: bool = true
@export var bot_tier: int = 1
@export var friendly_fire: bool = false
@export var demolition_enabled: bool = true

@export_group("Gravity")
@export var gravity_interval: float = 30.0
@export var gravity_transition: float = 2.0
@export var gravity_warning: float = 5.0
@export var random_gravity: bool = false
@export var gravity_strength: float = 20.0
@export var enabled_phases: Array[bool] = [true, true, true, true]
@export var shift_refill_pulse: float = 15.0

@export_group("Ball")
@export var ball_radius_scale: float = 1.0
@export var ball_mass_scale: float = 1.0

@export_group("Boost")
@export var boost_pads_enabled: bool = true
@export var no_boost: bool = false
@export var unlimited_boost: bool = false
@export var boost_pad_amount_small: float = 12.0
@export var boost_pad_amount_large: float = 100.0
@export var small_pad_respawn: float = 4.0
@export var large_pad_respawn: float = 10.0

@export_group("Mutators")
@export var mutators: Array[Resource] = []
