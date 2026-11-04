class_name BigBallMutator
extends MutatorBase

const RADIUS_SCALE := 1.55
const MASS_SCALE := 1.35


func _init() -> void:
	id = "big_ball"
	display_name = "Big Ball"
	description = "A larger, heavier ball. Different bounce reads and goal coverage."


func apply(rules: MatchRules, _world: Node) -> void:
	rules.ball_radius_scale *= RADIUS_SCALE
	rules.ball_mass_scale *= MASS_SCALE
