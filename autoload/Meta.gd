extends Node
## Local player profile, progression, cosmetics, challenges and Glicko-2 ranking.
## Save format is versioned JSON; the backend mirror uses the same shape.

const SAVE_PATH := "user://profile.json"
const SAVE_VERSION := 3
const RANK_TIERS := ["Bronze", "Silver", "Gold", "Platinum", "Diamond", "Champion", "Grand Champion"]
const TIER_SIZE := 300
const PLACEMENT_MATCHES := 10
const SEASON_LENGTH_SECONDS := 90.0 * 24.0 * 60.0 * 60.0
const LEAVER_COOLDOWNS: Array[float] = [300.0, 900.0, 3600.0]
const ABANDON_PENALTY := 25.0
const SMURF_RISK_THRESHOLD := 0.6

var profile: Dictionary = {}
var daily_challenges: Array[Dictionary] = []
var weekly_challenges: Array[Dictionary] = []
var catalog: Array[Dictionary] = []


func _ready() -> void:
	_build_catalog()
	_default_profile()
	load_profile()
	if float(profile.get("season_started", 0.0)) <= 0.0:
		profile["season_started"] = Time.get_unix_time_from_system()
	check_season_rollover()
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
		"rd": 350.0,
		"volatility": 0.06,
		"placement_matches": 0,
		"ranked_matches": 0,
		"ranked_wins": 0,
		"casual_matches": 0,
		"casual_wins": 0,
		"last_mmr_delta": 0.0,
		"smurf_risk": 0.0,
		"leaver_count": 0,
		"abandon_count": 0,
		"leaver_cooldown_until": 0.0,
		"season": 1,
		"season_started": 0.0,
		"season_xp": 0,
		"season_matches": 0,
		"season_wins": 0,
		"season_peak_mmr": 1000.0,
		"season_history": [],
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
	if version < 3:
		# Elo-era saves become Glicko-2 ratings. Established players keep a
		# tighter RD than players who have not finished placements.
		var placements: int = int(data.get("placement_matches", 0))
		data["rd"] = 200.0 if placements >= PLACEMENT_MATCHES else 350.0
		data["volatility"] = 0.06
		data["ranked_matches"] = placements
		data["ranked_wins"] = int(data.get("wins", 0))
		data["casual_matches"] = 0
		data["casual_wins"] = 0
		data["last_mmr_delta"] = 0.0
		data["smurf_risk"] = 0.0
		data["leaver_count"] = 0
		data["abandon_count"] = 0
		data["leaver_cooldown_until"] = 0.0
		data["season_started"] = Time.get_unix_time_from_system()
		data["season_matches"] = 0
		data["season_wins"] = 0
		data["season_peak_mmr"] = float(data.get("peak_mmr", data.get("mmr", 1000.0)))
		data["season_history"] = []
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
## `opponent_mmr < 0` records an unrated match (free play, private or casual).
func record_match(won: bool, stats: Dictionary, opponent_mmr: float = -1.0, opponent_rd: float = 200.0, ranked: bool = true) -> Dictionary:
	profile["matches"] = int(profile["matches"]) + 1
	if won:
		profile["wins"] = int(profile["wins"]) + 1
	else:
		profile["losses"] = int(profile["losses"]) + 1
	if ranked:
		profile["ranked_matches"] = int(profile.get("ranked_matches", 0)) + 1
		if won:
			profile["ranked_wins"] = int(profile.get("ranked_wins", 0)) + 1
	else:
		profile["casual_matches"] = int(profile.get("casual_matches", 0)) + 1
		if won:
			profile["casual_wins"] = int(profile.get("casual_wins", 0)) + 1
	for key: String in ["goals", "saves", "assists", "shots", "demolitions"]:
		profile[key] = int(profile[key]) + int(stats.get(key, 0))
	profile["boost_used"] = float(profile["boost_used"]) + float(stats.get("boost_used", 0.0))
	profile["playtime"] = float(profile["playtime"]) + float(stats.get("playtime", 0.0))
	var mmr_result := {
		"delta": 0.0,
		"mmr": float(profile["mmr"]),
		"rd": float(profile.get("rd", 200.0)),
		"placed": int(profile["placement_matches"]) >= PLACEMENT_MATCHES,
		"rank": rank_name(),
	}
	if ranked and opponent_mmr >= 0.0:
		mmr_result = apply_rated_result(won, opponent_mmr, opponent_rd, float(stats.get("score_diff", 0)))
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


## Glicko-2 rated result. Placements use the naturally high starting RD rather
## than a special K-factor, so uncertainty shrinks match by match.
func apply_rated_result(won: bool, opponent_mmr: float, opponent_rd: float = 200.0, score_diff: float = 0.0) -> Dictionary:
	var old_rating: float = float(profile["mmr"])
	var glicko := Glicko2.new(
		old_rating,
		float(profile.get("rd", 350.0)),
		float(profile.get("volatility", 0.06)),
	)
	var score: float = 1.0 if won else 0.0
	var result: Dictionary = glicko.update(opponent_mmr, opponent_rd, score)
	var margin: float = clampf(1.0 + absf(score_diff) * 0.02, 1.0, 1.25)
	var delta: float = float(result["delta"]) * margin
	if won:
		delta *= smurf_multiplier()
	var new_rating: float = clampf(old_rating + delta, Glicko2.MIN_RATING, Glicko2.MAX_RATING)
	delta = new_rating - old_rating
	profile["mmr"] = new_rating
	profile["rd"] = glicko.rd
	profile["volatility"] = glicko.volatility
	profile["last_mmr_delta"] = delta
	profile["peak_mmr"] = maxf(float(profile["peak_mmr"]), new_rating)
	profile["season_peak_mmr"] = maxf(float(profile.get("season_peak_mmr", new_rating)), new_rating)
	profile["season_matches"] = int(profile.get("season_matches", 0)) + 1
	if won:
		profile["season_wins"] = int(profile.get("season_wins", 0)) + 1
	_update_smurf_risk(won, score_diff)
	var placements_before: int = int(profile["placement_matches"])
	if placements_before < PLACEMENT_MATCHES:
		profile["placement_matches"] = placements_before + 1
		if placements_before + 1 == PLACEMENT_MATCHES:
			Events.notification.emit("Placements complete - %s" % rank_for_mmr(new_rating))
	Events.notification.emit("MMR %+d   RD %d" % [int(round(delta)), int(round(glicko.rd))])
	save_profile()
	return {
		"delta": delta,
		"mmr": new_rating,
		"rd": glicko.rd,
		"volatility": glicko.volatility,
		"placed": int(profile["placement_matches"]) >= PLACEMENT_MATCHES,
		"placement_matches": int(profile["placement_matches"]),
		"rank": rank_name(),
		"smurf_risk": float(profile.get("smurf_risk", 0.0)),
	}


## New accounts that win by large margins climb faster so they leave the
## beginner pool quickly instead of farming it.
func _update_smurf_risk(won: bool, score_diff: float) -> void:
	var ranked_matches: int = int(profile.get("ranked_matches", 0))
	var risk: float = float(profile.get("smurf_risk", 0.0))
	if ranked_matches > 20:
		risk = maxf(0.0, risk - 0.05)
	elif won:
		risk += 0.06
		if absf(score_diff) >= 3.0:
			risk += 0.05
		if int(profile.get("placement_matches", 0)) < PLACEMENT_MATCHES:
			risk += 0.03
	else:
		risk = maxf(0.0, risk - 0.04)
	profile["smurf_risk"] = clampf(risk, 0.0, 1.0)


func smurf_multiplier() -> float:
	return 1.0 + float(profile.get("smurf_risk", 0.0)) * 0.5


func is_flagged_smurf() -> bool:
	return float(profile.get("smurf_risk", 0.0)) >= SMURF_RISK_THRESHOLD


func placement_remaining() -> int:
	return maxi(0, PLACEMENT_MATCHES - int(profile.get("placement_matches", 0)))


func rank_name() -> String:
	if int(profile.get("placement_matches", 0)) < PLACEMENT_MATCHES:
		return "Unranked"
	return rank_for_mmr(float(profile["mmr"]))


static func rank_for_mmr(mmr: float) -> String:
	if mmr < 0.0:
		return "Unranked"
	var tier_idx: int = tier_index_for_mmr(mmr)
	var division: int = division_for_mmr(mmr)
	if tier_idx == RANK_TIERS.size() - 1:
		return RANK_TIERS[tier_idx]
	return "%s %d" % [RANK_TIERS[tier_idx], division]


static func tier_index_for_mmr(mmr: float) -> int:
	if mmr < 0.0:
		return -1
	return clampi(int(mmr / TIER_SIZE), 0, RANK_TIERS.size() - 1)


static func division_for_mmr(mmr: float) -> int:
	if mmr < 0.0:
		return 0
	var tier_idx: int = tier_index_for_mmr(mmr)
	var within: float = mmr - tier_idx * TIER_SIZE
	return clampi(1 + int(within / (TIER_SIZE / 3.0)), 1, 3)


func rank_progress() -> Dictionary:
	var mmr: float = float(profile["mmr"])
	var tier_idx: int = tier_index_for_mmr(mmr)
	var within: float = mmr - tier_idx * TIER_SIZE
	var next_label: String = rank_for_mmr(mmr)
	if tier_idx < RANK_TIERS.size() - 1 and division_for_mmr(mmr) < 3:
		next_label = "%s %d" % [RANK_TIERS[tier_idx], division_for_mmr(mmr) + 1]
	elif tier_idx < RANK_TIERS.size() - 1:
		next_label = "%s 1" % RANK_TIERS[tier_idx + 1]
	else:
		next_label = "Grand Champion"
	return {
		"tier_index": tier_idx,
		"tier": RANK_TIERS[tier_idx],
		"division": division_for_mmr(mmr),
		"mmr_into_tier": within,
		"tier_size": TIER_SIZE,
		"next": next_label,
		"unranked": int(profile.get("placement_matches", 0)) < PLACEMENT_MATCHES,
	}


# --- Seasons / leaver / queue gating -----------------------------------------

func season_ends_at() -> float:
	return float(profile.get("season_started", 0.0)) + SEASON_LENGTH_SECONDS


func season_time_left(now: float = -1.0) -> float:
	var ts: float = now if now >= 0.0 else Time.get_unix_time_from_system()
	return maxf(0.0, season_ends_at() - ts)


## Starts the next season with a soft MMR reset (halfway back to 1000),
## fresh placements and expanded uncertainty.
func start_new_season(now: float = -1.0) -> Dictionary:
	var ts: float = now if now >= 0.0 else Time.get_unix_time_from_system()
	var old_mmr: float = float(profile["mmr"])
	var new_mmr: float = 1000.0 + (old_mmr - 1000.0) * 0.5
	var history: Array = profile.get("season_history", [])
	history.append({
		"season": int(profile.get("season", 1)),
		"mmr": old_mmr,
		"peak_mmr": float(profile.get("season_peak_mmr", old_mmr)),
		"matches": int(profile.get("season_matches", 0)),
		"wins": int(profile.get("season_wins", 0)),
		"ended": ts,
	})
	while history.size() > 10:
		history.pop_front()
	profile["season_history"] = history
	profile["season"] = int(profile.get("season", 1)) + 1
	profile["season_started"] = ts
	profile["season_matches"] = 0
	profile["season_wins"] = 0
	profile["season_xp"] = 0
	profile["season_peak_mmr"] = new_mmr
	profile["placement_matches"] = 0
	profile["mmr"] = new_mmr
	profile["rd"] = clampf(float(profile.get("rd", 200.0)) * 1.8, 150.0, 350.0)
	profile["smurf_risk"] = 0.0
	save_profile()
	Events.notification.emit("Season %d started - soft reset to %.0f MMR" % [int(profile["season"]), new_mmr])
	return {
		"season": int(profile["season"]),
		"old_mmr": old_mmr,
		"new_mmr": new_mmr,
		"rd": float(profile["rd"]),
	}


## Rolls over automatically when the 90-day season window expires.
func check_season_rollover(now: float = -1.0) -> bool:
	var ts: float = now if now >= 0.0 else Time.get_unix_time_from_system()
	if float(profile.get("season_started", ts)) <= 0.0:
		profile["season_started"] = ts
		return false
	if ts < season_ends_at():
		return false
	start_new_season(ts)
	return true


## Abandoning a ranked match applies a rating penalty, raises uncertainty and
## escalates the queue cooldown (5 min / 15 min / 60 min).
func register_abandon(now: float = -1.0) -> float:
	var ts: float = now if now >= 0.0 else Time.get_unix_time_from_system()
	var count: int = int(profile.get("abandon_count", 0)) + 1
	profile["abandon_count"] = count
	profile["leaver_count"] = int(profile.get("leaver_count", 0)) + 1
	var cooldown: float = LEAVER_COOLDOWNS[clampi(count - 1, 0, LEAVER_COOLDOWNS.size() - 1)]
	profile["leaver_cooldown_until"] = ts + cooldown
	profile["mmr"] = maxf(0.0, float(profile["mmr"]) - ABANDON_PENALTY)
	profile["rd"] = clampf(float(profile.get("rd", 200.0)) + 30.0, Glicko2.MIN_RD, Glicko2.MAX_RD)
	profile["last_mmr_delta"] = -ABANDON_PENALTY
	save_profile()
	Events.notification.emit("Match abandoned - queue locked for %d min" % int(cooldown / 60.0))
	return cooldown


func leaver_cooldown_remaining(now: float = -1.0) -> float:
	var ts: float = now if now >= 0.0 else Time.get_unix_time_from_system()
	return maxf(0.0, float(profile.get("leaver_cooldown_until", 0.0)) - ts)


func can_queue(now: float = -1.0) -> bool:
	return leaver_cooldown_remaining(now) <= 0.0


## Called on reconnect after a grace-period disconnect; the next abandon
## escalates while a clean match completion forgives one strike.
func forgive_abandon() -> void:
	profile["abandon_count"] = maxi(0, int(profile.get("abandon_count", 0)) - 1)
	profile["leaver_cooldown_until"] = 0.0
	save_profile()


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
	profile["season_started"] = Time.get_unix_time_from_system()
	save_profile()
