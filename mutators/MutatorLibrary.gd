class_name MutatorLibrary
extends RefCounted
## Catalog and factory for built-in mutators. UI and network both use the ids.

const ORDER := [
	"low_gravity",
	"big_ball",
	"fast_shift",
	"random_shift",
	"no_boost",
	"unlimited_boost",
]


static func make(id: String) -> MutatorBase:
	match id:
		"low_gravity":
			return LowGravityMutator.new()
		"big_ball":
			return BigBallMutator.new()
		"fast_shift":
			return FastShiftMutator.new()
		"random_shift":
			return RandomShiftMutator.new()
		"no_boost":
			return NoBoostMutator.new()
		"unlimited_boost":
			return UnlimitedBoostMutator.new()
	return null


static func catalog() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in ORDER:
		var m := make(id)
		if m != null:
			out.append({"id": m.id, "name": m.display_name, "description": m.description})
	return out


static func build(ids: Array) -> Array[Resource]:
	var out: Array[Resource] = []
	for raw: Variant in ids:
		var m := make(str(raw))
		if m != null:
			out.append(m)
	return out


## Remove conflicting entries, keeping the later selection.
static func validate(list: Array[Resource]) -> Array[Resource]:
	var out: Array[Resource] = []
	for entry: Resource in list:
		var mutator := entry as MutatorBase
		if mutator == null:
			continue
		var drop := false
		for existing: Resource in out:
			if (existing as MutatorBase).conflicts_with(mutator) or mutator.conflicts_with(existing as MutatorBase):
				drop = true
				break
		if not drop:
			out.append(mutator)
	return out
