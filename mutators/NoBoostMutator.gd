class_name NoBoostMutator
extends MutatorBase


func _init() -> void:
	id = "no_boost"
	display_name = "No Boost"
	description = "Boost pads and boost are disabled. Pure driving and aerials."


func apply(rules: MatchRules, _world: Node) -> void:
	rules.no_boost = true
	rules.unlimited_boost = false


func conflicts_with(other: MutatorBase) -> bool:
	return other != null and other.id == "unlimited_boost"
