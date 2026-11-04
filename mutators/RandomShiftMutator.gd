class_name RandomShiftMutator
extends MutatorBase


func _init() -> void:
	id = "random_shift"
	display_name = "Random Shift"
	description = "The next gravity phase is chosen at random (seed-locked per match)."


func apply(rules: MatchRules, _world: Node) -> void:
	rules.random_gravity = true
