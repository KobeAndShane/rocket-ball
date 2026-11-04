extends Node
## Local player profile, progression, cosmetics, challenges and Glicko-2 ranking.
## Save format is versioned JSON; the backend mirror uses the same shape.

const SAVE_PATH := "user://profile.json"
const SAVE_VERSION := 5
const RANK_TIERS := ["Bronze", "Silver", "Gold", "Platinum", "Diamond", "Champion", "Grand Champion"]
const TIER_SIZE := 300
const PLACEMENT_MATCHES := 10
const SEASON_LENGTH_SECONDS := 90.0 * 24.0 * 60.0 * 60.0
const LEAVER_COOLDOWNS: Array[float] = [300.0, 900.0, 3600.0]
const ABANDON_PENALTY := 25.0
const SMURF_RISK_THRESHOLD := 0.6
const SEASON_PASS_LEVELS := 30
const SEASON_PASS_XP_PER_LEVEL := 5000
const PREMIUM_PASS_COST := 1200

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
		"inventory": ["body_stock", "wheel_stock", "boost_standard", "decal_none", "explosion_standard", "antenna_none", "trail_none"],
		"loadout": _default_loadout(),
		"loadout_presets": [],
		"active_preset": 0,
		"season_rewards_claimed": [],
		"mvp_count": 0,
		"win_streak": 0,
		"best_win_streak": 0,
		"challenge_progress": {},
		"challenges_date": "",
		"challenges_week": "",
		"challenges_claimed": {"daily": [], "weekly": []},
		"training_progress": {},
		"training_packs_completed": [],
	}
	var preset_default := {
		"name": "Default",
		"loadout": profile["loadout"].duplicate(true),
	}
	profile["loadout_presets"] = [preset_default]


func _default_loadout() -> Dictionary:
	return CosmeticLibrary.default_loadout()


func _build_catalog() -> void:
	catalog.clear()
	for item: CosmeticItem in CosmeticLibrary.all():
		catalog.append({
			"id": item.id,
			"type": item.slot,
			"name": item.display_name,
			"rarity": item.rarity,
			"price": item.price,
			"owned": item.default_owned,
			"unlock_level": item.unlock_level,
			"season_only": item.season_only,
			"description": item.description,
			"primary_color": item.primary_color,
			"accent_color": item.accent_color,
		})


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
	profile["loadout"] = CosmeticLibrary.sanitize_loadout(profile.get("loadout", {}))
	if (profile.get("loadout_presets", []) as Array).is_empty():
		profile["loadout_presets"] = [{"name": "Default", "loadout": profile["loadout"].duplicate(true)}]
	if (profile.get("challenges_claimed", {}) as Dictionary).is_empty():
		profile["challenges_claimed"] = {"daily": [], "weekly": []}


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
	if version < 4:
		# Task 12: presets, career streaks and independent challenge tracks.
		var sanitized: Dictionary = CosmeticLibrary.sanitize_loadout(data.get("loadout", {}))
		data["loadout"] = sanitized
		if not data.has("loadout_presets") or (data.get("loadout_presets", []) as Array).is_empty():
			data["loadout_presets"] = [{"name": "Default", "loadout": sanitized.duplicate(true)}]
		data["active_preset"] = int(data.get("active_preset", 0))
		data["mvp_count"] = int(data.get("mvp_count", 0))
		data["win_streak"] = int(data.get("win_streak", 0))
		data["best_win_streak"] = int(data.get("best_win_streak", 0))
		data["challenges_week"] = str(data.get("challenges_week", ""))
		if not data.has("challenges_claimed"):
			data["challenges_claimed"] = {"daily": [], "weekly": []}
		if not data.has("season_rewards_claimed"):
			data["season_rewards_claimed"] = []
	if version < 5:
		# Task 13: training completion and best times.
		if not data.has("training_progress"):
			data["training_progress"] = {}
		if not data.has("training_packs_completed"):
			data["training_packs_completed"] = []
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
		Events.level_up.emit(int(profile["level"]))
		profile["credits"] = int(profile["credits"]) + 100
		needed = xp_for_level(int(profile["level"]))
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
	if won:
		profile["win_streak"] = int(profile.get("win_streak", 0)) + 1
		profile["best_win_streak"] = maxi(int(profile.get("best_win_streak", 0)), int(profile["win_streak"]))
	else:
		profile["win_streak"] = 0
	if int(stats.get("mvp", 0)) > 0:
		profile["mvp_count"] = int(profile.get("mvp_count", 0)) + 1
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
	profile["season_rewards_claimed"] = []
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
	if bool(item.get("season_only", false)):
		return false
	if int(profile.get("level", 1)) < int(item.get("unlock_level", 1)):
		return false
	var price: int = int(item["price"])
	if int(profile["credits"]) < price:
		return false
	profile["credits"] = int(profile["credits"]) - price
	profile["inventory"].append(id)
	save_profile()
	Events.cosmetics_changed.emit()
	return true


## Explains why a store button is disabled, for menu copy and tests.
func purchase_block_reason(id: String) -> String:
	var item := cosmetic(id)
	if item.is_empty():
		return "Unknown item"
	if owns(id):
		return "Owned"
	if bool(item.get("season_only", false)):
		return "Season pass reward"
	if int(profile.get("level", 1)) < int(item.get("unlock_level", 1)):
		return "Reach level %d" % int(item.get("unlock_level", 1))
	if int(profile["credits"]) < int(item["price"]):
		return "Not enough credits"
	return ""


func equip(id: String) -> bool:
	var item := cosmetic(id)
	if item.is_empty() or not owns(id):
		return false
	profile["loadout"][item["type"]] = id
	save_profile()
	Events.cosmetics_changed.emit()
	return true


## Switch a slot back to its default cosmetic (the "unequip" action).
func unequip(slot: String) -> bool:
	var default_id := default_item_for(slot)
	if default_id == "":
		return false
	profile["loadout"][slot] = default_id
	save_profile()
	Events.cosmetics_changed.emit()
	return true


func default_item_for(slot: String) -> String:
	for item: Dictionary in catalog:
		if str(item["type"]) == slot and bool(item["owned"]):
			return str(item["id"])
	return str(CosmeticLibrary.default_loadout().get(slot, ""))


## Apply a complete loadout, ignoring items the player does not own.
func set_loadout(loadout: Dictionary) -> bool:
	var clean: Dictionary = CosmeticLibrary.default_loadout()
	var changed: bool = false
	for slot: String in CosmeticLibrary.SLOTS:
		var id: String = str(loadout.get(slot, ""))
		if id == "" or not owns(id):
			continue
		var item := cosmetic(id)
		if item.is_empty() or str(item["type"]) != slot:
			continue
		clean[slot] = id
		changed = true
	profile["loadout"] = clean
	save_profile()
	Events.cosmetics_changed.emit()
	return changed


func equipped(type: String) -> String:
	return str(profile["loadout"].get(type, default_item_for(type)))


# --- Loadout presets ---------------------------------------------------------

func save_loadout_preset(name: String) -> int:
	var preset_name: String = name.strip_edges().left(28)
	if preset_name == "":
		preset_name = "Preset %d" % ((profile.get("loadout_presets", []) as Array).size() + 1)
	var presets: Array = profile.get("loadout_presets", [])
	var entry := {"name": preset_name, "loadout": profile["loadout"].duplicate(true)}
	var found: int = -1
	for i in presets.size():
		if str((presets[i] as Dictionary).get("name", "")) == preset_name:
			found = i
			break
	if found >= 0:
		presets[found] = entry
	else:
		presets.append(entry)
		found = presets.size() - 1
	while presets.size() > 10:
		presets.pop_front()
		found = maxi(0, found - 1)
	profile["loadout_presets"] = presets
	profile["active_preset"] = found
	save_profile()
	Events.cosmetics_changed.emit()
	return found


func apply_loadout_preset(index: int) -> bool:
	var presets: Array = profile.get("loadout_presets", [])
	if index < 0 or index >= presets.size():
		return false
	var source: Dictionary = presets[index]
	var applied: bool = set_loadout(source.get("loadout", {}))
	profile["active_preset"] = index
	save_profile()
	return applied


func delete_loadout_preset(index: int) -> bool:
	var presets: Array = profile.get("loadout_presets", [])
	if presets.size() <= 1 or index < 0 or index >= presets.size():
		return false
	presets.remove_at(index)
	profile["loadout_presets"] = presets
	profile["active_preset"] = clampi(int(profile.get("active_preset", 0)), 0, presets.size() - 1)
	save_profile()
	Events.cosmetics_changed.emit()
	return true


func loadout_preset_names() -> Array[String]:
	var out: Array[String] = []
	for preset: Dictionary in profile.get("loadout_presets", []):
		out.append(str(preset.get("name", "Preset")))
	return out


func grant_cosmetic(id: String) -> bool:
	if cosmetic(id).is_empty():
		return false
	if owns(id):
		add_credits(100)
		return false
	profile["inventory"].append(id)
	save_profile()
	return true


func _ensure_challenges() -> void:
	var today := Time.get_date_string_from_system()
	var week := _week_key()
	var dirty: bool = false
	if str(profile.get("challenges_date", "")) != today:
		profile["challenges_date"] = today
		_reset_challenge_track("daily")
		daily_challenges.clear()
		dirty = true
	if str(profile.get("challenges_week", "")) != week:
		profile["challenges_week"] = week
		_reset_challenge_track("weekly")
		weekly_challenges.clear()
		dirty = true
	var pool := [
		{"id": "matches", "text": "Play %d matches", "target": 3, "reward": 200},
		{"id": "wins", "text": "Win %d matches", "target": 2, "reward": 300},
		{"id": "goals", "text": "Score %d goals", "target": 5, "reward": 250},
		{"id": "saves", "text": "Make %d saves", "target": 3, "reward": 250},
	]
	if daily_challenges.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(today + str(profile["name"]))
		var remaining: Array = pool.duplicate(true)
		for i in 3:
			if remaining.is_empty():
				break
			var pick: int = rng.randi_range(0, remaining.size() - 1)
			var entry: Dictionary = (remaining[pick] as Dictionary).duplicate(true)
			remaining.remove_at(pick)
			entry["text"] = str(entry["text"]) % int(entry["target"])
			entry["kind"] = "daily"
			entry["claimed"] = false
			daily_challenges.append(entry)
		dirty = true
	if weekly_challenges.is_empty():
		for entry_base: Dictionary in pool:
			var entry: Dictionary = entry_base.duplicate(true)
			entry["target"] = int(entry["target"]) * 5
			entry["reward"] = int(entry["reward"]) * 3
			entry["text"] = str(entry["text"]) % int(entry["target"])
			entry["kind"] = "weekly"
			entry["claimed"] = false
			weekly_challenges.append(entry)
		dirty = true
	if dirty:
		save_profile()


func _week_key(now: float = -1.0) -> String:
	var ts: float = now if now >= 0.0 else Time.get_unix_time_from_system()
	# Unix epoch was a Thursday; offset by four days so buckets start Monday.
	var bucket: int = int(floor((ts + 4.0 * 86400.0) / 604800.0))
	var year: int = int(Time.get_datetime_dict_from_unix_time(int(ts)).get("year", 0))
	return "%d-W%d" % [year, bucket]


func _reset_challenge_track(kind: String) -> void:
	var progress: Dictionary = profile.get("challenge_progress", {})
	var prefix: String = kind + ":"
	for key: String in progress.keys():
		if key.begins_with(prefix):
			progress.erase(key)
	var claimed: Dictionary = profile.get("challenges_claimed", {})
	claimed[kind] = []
	profile["challenges_claimed"] = claimed


func _add_challenge_progress(id: String, amount: int) -> void:
	if amount == 0:
		return
	var progress: Dictionary = profile["challenge_progress"]
	for kind: String in ["daily", "weekly"]:
		var key: String = "%s:%s" % [kind, id]
		progress[key] = int(progress.get(key, 0)) + amount


func challenge_state(entry: Dictionary) -> Dictionary:
	var id: String = str(entry["id"])
	var kind: String = str(entry.get("kind", "daily"))
	var progress: int = int(profile["challenge_progress"].get("%s:%s" % [kind, id], 0))
	var claimed_list: Array = profile.get("challenges_claimed", {}).get(kind, [])
	return {
		"progress": mini(progress, int(entry["target"])),
		"target": int(entry["target"]),
		"done": progress >= int(entry["target"]),
		"claimed": claimed_list.has(id),
	}


func claim_challenge(entry: Dictionary) -> bool:
	var state := challenge_state(entry)
	if not state["done"] or bool(state["claimed"]):
		return false
	add_credits(int(entry["reward"]))
	var claimed: Dictionary = profile.get("challenges_claimed", {})
	var kind: String = str(entry.get("kind", "daily"))
	var list: Array = claimed.get(kind, [])
	list.append(str(entry["id"]))
	claimed[kind] = list
	profile["challenges_claimed"] = claimed
	entry["claimed"] = true
	save_profile()
	return true


# --- Season pass -------------------------------------------------------------

func season_pass_level() -> int:
	var xp: int = int(profile.get("season_xp", 0))
	return clampi(1 + int(xp / SEASON_PASS_XP_PER_LEVEL), 1, SEASON_PASS_LEVELS)


func season_pass_progress() -> Dictionary:
	var xp: int = int(profile.get("season_xp", 0))
	var level: int = season_pass_level()
	var into: int = xp - (level - 1) * SEASON_PASS_XP_PER_LEVEL
	if level >= SEASON_PASS_LEVELS:
		into = SEASON_PASS_XP_PER_LEVEL
	into = clampi(into, 0, SEASON_PASS_XP_PER_LEVEL)
	return {
		"level": level,
		"xp": xp,
		"into": into,
		"needed": SEASON_PASS_XP_PER_LEVEL,
		"ratio": float(into) / float(SEASON_PASS_XP_PER_LEVEL),
		"maxed": level >= SEASON_PASS_LEVELS,
		"premium": bool(profile.get("premium_pass", false)),
	}


func season_reward(level: int, premium: bool) -> Dictionary:
	var free_cosmetics := {
		3: "decal_stripes",
		7: "wheel_neon",
		10: "body_interceptor",
		15: "boost_ion",
		20: "decal_hex",
		25: "body_aurora",
		30: "trail_aurora",
	}
	var premium_cosmetics := {
		2: "antenna_flag",
		6: "wheel_neon",
		12: "wheel_gravity",
		18: "trail_comet",
		24: "boost_supernova",
		28: "explosion_blackhole",
	}
	var table: Dictionary = premium_cosmetics if premium else free_cosmetics
	var cosmetic_id: String = str(table.get(level, ""))
	var credits: int = 0 if cosmetic_id != "" else ((200 + level * 40) if premium else (100 + level * 20))
	return {
		"level": level,
		"premium": premium,
		"credits": credits,
		"cosmetic": cosmetic_id,
		"label": season_reward_label(cosmetic_id, credits),
	}


func season_reward_label(cosmetic_id: String, credits: int) -> String:
	if cosmetic_id != "":
		var item := cosmetic(cosmetic_id)
		if not item.is_empty():
			return "%s  (%s)" % [str(item["name"]), str(item["rarity"])]
		return cosmetic_id
	return "%d credits" % credits


func season_reward_claimed(level: int, premium: bool) -> bool:
	var key: String = "%s:%d" % ["premium" if premium else "free", level]
	return (profile.get("season_rewards_claimed", []) as Array).has(key)


func claim_season_reward(level: int, premium: bool) -> bool:
	if level < 1 or level > SEASON_PASS_LEVELS:
		return false
	if level > season_pass_level():
		return false
	if premium and not bool(profile.get("premium_pass", false)):
		return false
	if season_reward_claimed(level, premium):
		return false
	var reward := season_reward(level, premium)
	var key: String = "%s:%d" % ["premium" if premium else "free", level]
	var claimed: Array = profile.get("season_rewards_claimed", [])
	claimed.append(key)
	profile["season_rewards_claimed"] = claimed
	var cosmetic_id: String = str(reward.get("cosmetic", ""))
	if cosmetic_id != "":
		grant_cosmetic(cosmetic_id)
	else:
		add_credits(int(reward.get("credits", 0)))
	save_profile()
	Events.cosmetics_changed.emit()
	return true


func purchase_premium_pass() -> bool:
	if bool(profile.get("premium_pass", false)):
		return false
	if int(profile.get("credits", 0)) < PREMIUM_PASS_COST:
		return false
	profile["credits"] = int(profile["credits"]) - PREMIUM_PASS_COST
	profile["premium_pass"] = true
	save_profile()
	Events.cosmetics_changed.emit()
	return true


# --- Career summary ----------------------------------------------------------

func career_summary() -> Dictionary:
	var matches: int = int(profile.get("matches", 0))
	var wins: int = int(profile.get("wins", 0))
	var level: int = int(profile.get("level", 1))
	var needed: int = xp_for_level(level)
	return {
		"name": str(profile.get("name", "Pilot")),
		"level": level,
		"xp": int(profile.get("xp", 0)),
		"xp_needed": needed,
		"xp_ratio": clampf(float(profile.get("xp", 0)) / float(maxi(needed, 1)), 0.0, 1.0),
		"total_xp": int(profile.get("total_xp", 0)),
		"matches": matches,
		"wins": wins,
		"losses": int(profile.get("losses", 0)),
		"win_rate": (float(wins) / float(matches)) if matches > 0 else 0.0,
		"goals": int(profile.get("goals", 0)),
		"saves": int(profile.get("saves", 0)),
		"assists": int(profile.get("assists", 0)),
		"shots": int(profile.get("shots", 0)),
		"demolitions": int(profile.get("demolitions", 0)),
		"mvp_count": int(profile.get("mvp_count", 0)),
		"boost_used": float(profile.get("boost_used", 0.0)),
		"playtime": float(profile.get("playtime", 0.0)),
		"playtime_text": format_playtime(float(profile.get("playtime", 0.0))),
		"win_streak": int(profile.get("win_streak", 0)),
		"best_win_streak": int(profile.get("best_win_streak", 0)),
		"rank": rank_name(),
		"mmr": float(profile.get("mmr", 1000.0)),
		"rd": float(profile.get("rd", 350.0)),
		"peak_mmr": float(profile.get("peak_mmr", 1000.0)),
		"ranked_matches": int(profile.get("ranked_matches", 0)),
		"casual_matches": int(profile.get("casual_matches", 0)),
		"season": int(profile.get("season", 1)),
		"season_level": season_pass_level(),
		"season_xp": int(profile.get("season_xp", 0)),
		"credits": int(profile.get("credits", 0)),
		"training_drills": int((profile.get("training_progress", {}) as Dictionary).size()),
	}


# --- Training ---------------------------------------------------------------

func record_training(pack_id: String, drill_id: String, seconds: float, success: bool) -> void:
	if pack_id == "" or drill_id == "":
		return
	if not profile.has("training_progress") or not (profile["training_progress"] is Dictionary):
		profile["training_progress"] = {}
	var progress: Dictionary = profile["training_progress"]
	var key := "%s/%s" % [pack_id, drill_id]
	var entry: Dictionary = progress.get(key, {})
	var was_complete: bool = bool(entry.get("completed", false))
	entry["attempts"] = int(entry.get("attempts", 0)) + 1
	entry["last_attempt"] = seconds
	if success:
		entry["completed"] = true
		var best: float = float(entry.get("best_time", 999999.0))
		entry["best_time"] = minf(best, seconds)
		entry["completed_at"] = Time.get_unix_time_from_system()
		if not was_complete:
			profile["credits"] = int(profile.get("credits", 0)) + 10
	progress[key] = entry
	save_profile()


func training_drill_completed(pack_id: String, drill_id: String) -> bool:
	var progress: Dictionary = profile.get("training_progress", {})
	return bool((progress.get("%s/%s" % [pack_id, drill_id], {}) as Dictionary).get("completed", false))


func training_pack_completed(pack_id: String) -> bool:
	var list: Array = profile.get("training_packs_completed", [])
	return list.has(pack_id)


func mark_training_pack_completed(pack_id: String) -> void:
	if pack_id == "":
		return
	var list: Array = profile.get("training_packs_completed", [])
	if not list.has(pack_id):
		list.append(pack_id)
		profile["training_packs_completed"] = list
		profile["credits"] = int(profile.get("credits", 0)) + 50
		Events.notification.emit("Training pack complete: %s" % pack_id)
		save_profile()


func training_summary() -> Dictionary:
	var progress: Dictionary = profile.get("training_progress", {})
	var completed := 0
	for key: Variant in progress.keys():
		if bool((progress[key] as Dictionary).get("completed", false)):
			completed += 1
	return {
		"drills_completed": completed,
		"total_attempts": progress.size(),
		"packs_completed": (profile.get("training_packs_completed", []) as Array).size(),
	}


static func format_playtime(seconds: float) -> String:
	var total: int = maxi(0, int(seconds))
	var hours: int = total / 3600
	var minutes: int = (total % 3600) / 60
	if hours > 0:
		return "%dh %02dm" % [hours, minutes]
	return "%dm" % minutes


func _on_goal_scored(_team: int, _scorer: int) -> void:
	pass


func _on_car_demolished(_victim: int, _attacker: int) -> void:
	pass


func reset_profile() -> void:
	_default_profile()
	profile["season_started"] = Time.get_unix_time_from_system()
	save_profile()
