class_name FastShiftMutator
extends MutatorBase

const INTERVAL := 15.0
const WARNING := 3.0


func _init() -> void:
	id = "fast_shift"
	display_name = "Fast Shift"
	description = "Gravity rotates every 15 seconds with a shorter warning."


func apply(rules: MatchRules, _world: Node) -> void:
	rules.gravity_interval = INTERVAL
	rules.gravity_warning = WARNING
