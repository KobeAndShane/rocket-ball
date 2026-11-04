class_name MutatorBase
extends Resource
## Composable match modifier. Mutators are applied in list order at kickoff to a
## fresh copy of MatchRules, so one match never leaks state into the next.

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var enabled: bool = true


func apply(_rules: MatchRules, _world: Node) -> void:
	pass


func remove(_rules: MatchRules, _world: Node) -> void:
	pass


## Return true when this mutator cannot coexist with `other`.
func conflicts_with(other: MutatorBase) -> bool:
	return other != null and other.id == id
