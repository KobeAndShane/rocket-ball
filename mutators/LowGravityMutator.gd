class_name LowGravityMutator
extends MutatorBase

const SCALE := 0.55


func _init() -> void:
	id = "low_gravity"
	display_name = "Low Gravity"
	description = "Gravity is 45% weaker. Floaty aerials and long hang time."


func apply(rules: MatchRules, _world: Node) -> void:
	rules.gravity_strength *= SCALE
