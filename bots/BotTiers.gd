class_name BotTiers
extends Resource

@export var tiers: Array[Resource] = []


func get_tier(index: int) -> BotTier:
	if tiers.is_empty():
		return BotTier.new()
	return tiers[clampi(index, 0, tiers.size() - 1)] as BotTier
