extends Node
## Local player profile, progression, cosmetics, challenges and Elo ranking.
## Save format is versioned JSON; backend sync (Task 11) mirrors this shape.

const SAVE_PATH := "user://profile.json"
const SAVE_VERSION := 2
const RANK_TIERS := ["Bronze", "Silver", "Gold", "Platinum", "Diamond", "Champion", "Grand Champion"]
const TIER_SIZE := 300

var profile: Dictionary = {}
var daily_challenges: Array[Dictionary] = []
var weekly_challenges: Array[Dictionary] = []
var catalog: Array[Dictionary] = []


func _ready() -> void:
	_build_catalog()
	_default_profile()
	load_profile()
	_ensure_challenges()
	Events.goal_scored.connect(_on_goal_scored)
	Events.car_demolished.connect(_on_car_demolished)


func _default_profile() -> void:
	profile = {
		"version": SAVE_VERSION,
		"name": str(Settings.get_setting("net/player_name")),
		"level": 1,
		"xp": 0,
		"total_xp": 0,
		"matches": 0,
		"wins": 0,
		"losses": 0,
		"goals": 0,
		"saves": 0,
		"assists": 0,
		"shots": 0,
		"demolitions": 0,
		"boost_used": 0.0,
		"playtime": 0.0,
		"mmr": 1000.0,
		"peak_mmr": 1000.0,
		"placement_matches": 0,
		"season": 1,
		"season_xp": 0,
		"premium_pass": false,
		"credits": 500,
		"inventory": ["body_stock", "wheel_stock", "boost_standard", "decal_none", "explosion_standard", "antenna_none"],
		"loadout": {
			"body": "body_stock",
			"wheel": "wheel_stock",
			"boost": "boost_standard",
			"decal": "decal_none",
			"explosion": "explosion_standard",
			"antenna": "antenna_none",
			"trail": "trail_none",
		},
		"season_rewards_claimed": [],
		"challenge_progress": {},
		"challenges_date": "",
	}


func _build_catalog() -> void:
	catalog = [
		_cosmetic("body_stock", "body", "Stock Body", "common", 0, true),
		_cosmetic("body_interceptor", "body", "Interceptor", "rare", 800, false),
		_cosmetic("body_orbiter", "body", "Orbiter", "epic", 1500, false),
		_cosmetic("wheel_stock", "wheel", "Stock Wheels", "common", 0, true),
		_cosmetic("wheel_neon", "wheel", "Neon Spokes", "rare", 500, false),
		_cosmetic("wheel_gravity", "wheel", "Gravity Rings", "epic", 1200, false),
		_cosmetic("boost_standard", "boost", "Standard Boost", "common", 0, true),
		_cosmetic("boost_ion", "boost", "Ion Trail", "rare", 600, false),
		_cosmetic("boost_supernova", "boost", "Supernova", "legendary", 2000, false),
		_cosmetic("decal_none", "decal", "No Decal", "common", 0, true),
		_cosmetic("decal_stripes", "decal", "Twin Stripes", "uncommon", 250, false),
		_cosmetic("decal_hex", "decal", "Hex Shift", "epic", 1100, false),
		_cosmetic("explosion_standard", "explosion", "Standard Burst", "common", 0, true),
		_cosmetic("explosion_blackhole", "explosion", "Singularity", "legendary", 2500, false),
		_cosmetic("antenna_none", "antenna", "No Antenna", "common", 0, true),
		_cosmetic("antenna_flag", "antenna", "Gravity Flag", "rare", 350, false),
		_cosmetic("trail_none", "trail", "No Trail", "common", 0, true),
		_cosmetic("trail_comet", "trail", "Comet", "epic", 1400, false),
	]


func _cosmetic(id: String, type: String, display: String, rarity: String, price: int, owned: bool) -> Dictionary:
	return {"id": id, "type": type, "name": display, "rarity": rarity, "price": price, "owned": owned}


func load_profile() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return
	var data: Dictionary = parsed
	_migrate(data)
	for key: Variant in data.keys():
		if profile.has(key):
			profile[key] = data[key]
	profile["version"] = SAVE_VERSION
	# Merge catalog ownership flags.
	for item: Dictionary in catalog:
		if item["owned"] and not profile["inventory"].has(item["id"]):
			profile["inventory"].append(item["id"])


func _migrate(data: Dictionary) -> void:
	var version: int = int(data.get("version", 1))
	if version < 2:
		data["season"] = 1
		data["season_xp"] = 0
		data["premium_pass"] = false
		data["season_rewards_claimed"] = []
		data["challenge_progress"] = {}
		data["challenges_date"] = ""
	data["version"] = SAVE_VERSION


func save_profile() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not save profile")
		return
	file.store_string(JSON.stringify(profile, "\t"))
	file.close()
	Events.profile_changed.emit()


func set_player_name(new_name: String) -> void:
	profile["name"] = new_name.strip_edges().left(24)
	Settings.set_setting("net/player_name", profile["name"])
	save_profile()


func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	profile["xp"] = int(profile["xp"]) + amount
	profile["total_xp"] = int(profile["total_xp"]) + amount
	profile["season_xp"] = int(profile["season_xp"]) + amount
	var needed := xp_for_level(int(profile["level"]))
	while int(profile["xp"]) >= needed:
		profile["xp"] = int(profile["xp"]) - needed
		profile["level"] = int(profile["level"]) + 1
		Events.notification.emit("Level up! Level %d" % profile["level"])
		profile["credits"] = int(profile["credits"]) + 100
		needed = xp_for_level(int(profile["level"]))
	if int(profile["season_xp"]) >= season_level_xp(int(profile["season_xp"])):
		pass
	save_profile()


func xp_for_level(level: int) -> int:
	return 1000 + (level - 1) * 250


func season_level_xp(season_xp: int) -> int:
	return 2500 + int(season_xp / 2500) * 500


func add_credits(amount: int) -> void:
	profile["credits"] = maxi(0, int(profile["credits"]) + amount)
	save_profile()


## Record a finished match. `stats` follows the StatsCollector dictionary shape.
func record_match(won: bool, stats: Dictionary, team_mmr: float = -1.0, opponent_mmr: float = -1.0) -> Dictionary:
	profile["matches"] = int(profile["matches"]) + 1
	if won:
		profile["wins"] = int(profile["wins"]) + 1
	else:
		profile["losses"] = int(profile["losses"]) + 1
	for key: String in ["goals", "saves", "assists", "shots", "demolitions"]:
		profile[key] = int(profile[key]) + int(stats.get(key, 0))
	profile["boost_used"] = float(profile["boost_used"]) + float(stats.get("boost_used", 0.0))
	profile["playtime"] = float(profile["playtime"]) + float(stats.get("playtime", 0.0))
	var mmr_result := {"delta": 0.0, "mmr": float(profile["mmr"]), "placed": int(profile["placement_matches"]) >= 10}
	if team_mmr >= 0.0 and opponent_mmr >= 0.0:
		mmr_result = apply_rated_result(won, team_mmr, opponent_mmr, float(stats.get("score_diff", 0)))
	var xp_gain: int = 400 + int(stats.get("goals", 0)) * 120 + int(stats.get("saves", 0)) * 60 + int(stats.get("assists", 0)) * 40
	if won:
		xp_gain += 250
	xp_gain += int(stats.get("mvp", 0)) * 150
	add_xp(xp_gain)
	_add_challenge_progress("matches", 1)
	_add_challenge_progress("wins", 1 if won else 0)
	_add_challenge_progress("goals", int(stats.get("goals", 0)))
	_add_challenge_progress("saves", int(stats.get("saves", 0)))
	save_profile()
	return {"xp": xp_gain, "mmr": mmr_result}


func apply_rated_result(won: bool, team_mmr: float, opponent_mmr: float, score_diff: float = 0.0) -> Dictionary:
	var placements: int = int(profile["placement_matches"])
	var k: float = 40.0
	if placements >= 10:
		k = 24.0 if int(profile["matches"]) < 30 else 16.0
	else:
		k = 48.0
	var expected: float = 1.0 / (1.0 + pow(10.0, (opponent_mmr - team_mmr) / 400.0))
	var actual: float = 1.0 if won else 0.0
	var margin: float = clampf(1.0 + absf(score_diff) * 0.06, 1.0, 1.5)
	var delta: float = k * (actual - expected) * margin
	profile["mmr"] = maxf(0.0, float(profile["mmr"]) + delta)
	profile["peak_mmr"] = maxf(float(profile["peak_mmr"]), float(profile["mmr"]))
	if placements < 10:
		profile["placement_matches"] = placements + 1
	Events.notification.emit("MMR %+d" % int(round(delta)))
	save_profile()
	return {
		"delta": delta,
		"mmr": float(profile["mmr"]),
		"placed": int(profile["placement_matches"]) >= 10,
		"rank": rank_name(),
	}


func rank_name() -> String:
	return rank_for_mmr(float(profile["mmr"]))


static func rank_for_mmr(mmr: float) -> String:
	if mmr < 0.0:
		return "Unranked"
	var tier_idx: int = clampi(int(mmr / TIER_SIZE), 0, RANK_TIERS.size() - 1)
	var within: float = mmr - tier_idx * TIER_SIZE
	var division: int = clampi(1 + int(within / (TIER_SIZE / 3.0)), 1, 3)
	if tier_idx == RANK_TIERS.size() - 1:
		return RANK_TIERS[tier_idx]
	return "%s %d" % [RANK_TIERS[tier_idx], division]


func owned_cosmetics() -> Array:
	var out: Array = []
	for item: Dictionary in catalog:
		if profile["inventory"].has(item["id"]):
			var copy: Dictionary = item.duplicate()
			copy["owned"] = true
			out.append(copy)
	return out


func cosmetic(id: String) -> Dictionary:
	for item: Dictionary in catalog:
		if item["id"] == id:
			return item
	return {}


func owns(id: String) -> bool:
	return profile["inventory"].has(id)


func purchase(id: String) -> bool:
	var item := cosmetic(id)
	if item.is_empty() or owns(id):
		return false
	var price: int = int(item["price"])
	if int(profile["credits"]) < price:
		return false
	profile["credits"] = int(profile["credits"]) - price
	profile["inventory"].append(id)
	save_profile()
	Events.cosmetics_changed.emit()
	return true


func equip(id: String) -> bool:
	var item := cosmetic(id)
	if item.is_empty() or not owns(id):
		return false
	profile["loadout"][item["type"]] = id
	save_profile()
	Events.cosmetics_changed.emit()
	return true


func equipped(type: String) -> String:
	return str(profile["loadout"].get(type, ""))


func _ensure_challenges() -> void:
	var today := Time.get_date_string_from_system()
	if str(profile.get("challenges_date", "")) == today and not daily_challenges.is_empty():
		return
	profile["challenges_date"] = today
	profile["challenge_progress"] = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(today + str(profile["name"]))
	var pool := [
		{"id": "matches", "text": "Play %d matches", "target": 3, "reward": 200},
		{"id": "wins", "text": "Win %d matches", "target": 2, "reward": 300},
		{"id": "goals", "text": "Score %d goals", "target": 5, "reward": 250},
		{"id": "saves", "text": "Make %d saves", "target": 3, "reward": 250},
	]
	daily_challenges.clear()
	for i in 3:
		var entry: Dictionary = pool[rng.randi_range(0, pool.size() - 1)].duplicate(true)
		entry["text"] = str(entry["text"]) % int(entry["target"])
		entry["kind"] = "daily"
		entry["claimed"] = false
		daily_challenges.append(entry)
	weekly_challenges.clear()
	for entry_base: Dictionary in pool:
		var entry: Dictionary = entry_base.duplicate(true)
		entry["target"] = int(entry["target"]) * 5
		entry["reward"] = int(entry["reward"]) * 3
		entry["text"] = str(entry["text"]) % int(entry["target"])
		entry["kind"] = "weekly"
		entry["claimed"] = false
		weekly_challenges.append(entry)
	save_profile()


func _add_challenge_progress(id: String, amount: int) -> void:
	if amount == 0:
		return
	var progress: Dictionary = profile["challenge_progress"]
	progress[id] = int(progress.get(id, 0)) + amount


func challenge_state(entry: Dictionary) -> Dictionary:
	var id: String = str(entry["id"])
	var progress: int = int(profile["challenge_progress"].get(id, 0))
	return {"progress": mini(progress, int(entry["target"])), "target": int(entry["target"]), "done": progress >= int(entry["target"])}


func claim_challenge(entry: Dictionary) -> bool:
	var state := challenge_state(entry)
	if not state["done"]:
		return false
	add_credits(int(entry["reward"]))
	entry["claimed"] = true
	save_profile()
	return true


func _on_goal_scored(_team: int, _scorer: int) -> void:
	pass


func _on_car_demolished(_victim: int, _attacker: int) -> void:
	pass


func reset_profile() -> void:
	_default_profile()
	save_profile()
