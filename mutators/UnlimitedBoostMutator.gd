class_name UnlimitedBoostMutator
extends MutatorBase


func _init() -> void:
	id = "unlimited_boost"
	display_name = "Unlimited Boost"
	description = "Everyone has infinite boost. Supersonic all the time."


func apply(rules: MatchRules, _world: Node) -> void:
	rules.unlimited_boost = true
	rules.no_boost = false


func conflicts_with(other: MutatorBase) -> bool:
	return other != null and other.id == "no_boost"
