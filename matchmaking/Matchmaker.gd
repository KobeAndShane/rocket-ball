class_name Matchmaker
extends RefCounted
## Queue matcher with region/ping filtering, expanding MMR windows and party
## support. The same code runs against a backend population or the local
## simulated queue, which keeps the algorithm testable without a service.

const BASE_WINDOW_RANKED := 70.0
const BASE_WINDOW_CASUAL := 350.0
const WINDOW_GROWTH := 20.0
const MAX_WINDOW := 900.0

var entries: Array[Dictionary] = []
var next_id: int = 1


func enqueue(entry: Dictionary) -> int:
	var copy: Dictionary = entry.duplicate(true)
	var id: int = int(copy.get("id", next_id))
	if id < next_id:
		id = next_id
	next_id = maxi(next_id, id + 1)
	copy["id"] = id
	copy["joined"] = float(copy.get("joined", 0.0))
	copy["mmr"] = float(copy.get("mmr", 1000.0))
	copy["rd"] = float(copy.get("rd", 200.0))
	copy["party_size"] = maxi(1, int(copy.get("party_size", 1)))
	copy["region"] = str(copy.get("region", "auto"))
	copy["ping"] = int(copy.get("ping", 40))
	var party_mmrs: Variant = copy.get("party_mmrs", null)
	if not (party_mmrs is Array) or (party_mmrs as Array).is_empty():
		copy["party_mmrs"] = [float(copy["mmr"])]
	elif not copy.has("mmr"):
		copy["mmr"] = effective_mmr(copy, "avg")
	entries.append(copy)
	return id


func remove(id: int) -> bool:
	for i in range(entries.size() - 1, -1, -1):
		if int(entries[i]["id"]) == id:
			entries.remove_at(i)
			return true
	return false


func clear() -> void:
	entries.clear()
	next_id = 1


func size() -> int:
	return entries.size()


func effective_mmr(entry: Dictionary, party_rule: String) -> float:
	var party_size: int = int(entry.get("party_size", 1))
	if party_size <= 1:
		return float(entry.get("mmr", 1000.0))
	var mmrs: Array = entry.get("party_mmrs", [])
	if mmrs.is_empty():
		return float(entry.get("mmr", 1000.0))
	if party_rule == "max":
		var highest: float = -INF
		for value: Variant in mmrs:
			highest = maxf(highest, float(value))
		return highest
	var total: float = 0.0
	for value: Variant in mmrs:
		total += float(value)
	return total / float(mmrs.size())


func search_window(entry: Dictionary, now: float, mode: String) -> float:
	var base: float = BASE_WINDOW_CASUAL if mode == "casual" else BASE_WINDOW_RANKED
	var waited: float = maxf(now - float(entry.get("joined", now)), 0.0)
	return minf(base + WINDOW_GROWTH * waited, MAX_WINDOW)


## Returns zero or more matches. Matched entries are removed from the queue.
func tick(now: float, team_size: int = 3, region: String = "", max_ping: int = 120, party_rule: String = "avg", mode: String = "ranked") -> Array[Dictionary]:
	var formed: Array[Dictionary] = []
	if team_size <= 0 or entries.size() < team_size * 2:
		return formed
	var view: Array[Dictionary] = []
	for entry: Dictionary in entries:
		view.append({"entry": entry, "eff": effective_mmr(entry, party_rule)})
	view.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["eff"]) < float(b["eff"]))
	var used: Dictionary = {}
	for i in view.size():
		var anchor: Dictionary = view[i]["entry"]
		var anchor_id: int = int(anchor["id"])
		if used.has(anchor_id):
			continue
		if not _compatible(anchor, region, max_ping):
			continue
		var anchor_eff: float = float(view[i]["eff"])
		var window: float = search_window(anchor, now, mode)
		var needed: int = team_size * 2 - int(anchor["party_size"])
		if needed < 0:
			continue
		var group: Array[Dictionary] = [anchor]
		var attempt: Dictionary = {anchor_id: true}
		var left: int = i - 1
		var right: int = i + 1
		while needed > 0 and (left >= 0 or right < view.size()):
			var go_left: bool = false
			if left >= 0 and right < view.size():
				var dl: float = absf(float(view[left]["eff"]) - anchor_eff)
				var dr: float = absf(float(view[right]["eff"]) - anchor_eff)
				go_left = dl <= dr
			elif left >= 0:
				go_left = true
			elif right >= view.size():
				break
			var picked: Dictionary = view[left]["entry"] if go_left else view[right]["entry"]
			if go_left:
				left -= 1
			else:
				right += 1
			var distance: float = absf(effective_mmr(picked, party_rule) - anchor_eff)
			if distance > window:
				# The nearest unused candidate on either side is outside the
				# window, so no further candidate can match either.
				break
			var picked_id: int = int(picked["id"])
			if used.has(picked_id) or attempt.has(picked_id):
				continue
			if not _compatible(picked, region, max_ping):
				continue
			var picked_size: int = int(picked["party_size"])
			if picked_size > needed:
				continue
			group.append(picked)
			attempt[picked_id] = true
			needed -= picked_size
		if needed != 0:
			continue
		var match_info := _build_match(group, team_size, party_rule, now, mode)
		if match_info.is_empty():
			continue
		formed.append(match_info)
		for id: Variant in attempt.keys():
			used[int(id)] = true
	if not used.is_empty():
		var keep: Array[Dictionary] = []
		for entry: Dictionary in entries:
			if not used.has(int(entry["id"])):
				keep.append(entry)
		entries = keep
	return formed


func _compatible(entry: Dictionary, region: String, max_ping: int) -> bool:
	if int(entry.get("ping", 0)) > max_ping:
		return false
	if region != "" and region != "auto" and str(entry.get("region", "auto")) != region:
		return false
	return true


func _build_match(group: Array[Dictionary], team_size: int, party_rule: String, now: float, mode: String) -> Dictionary:
	if group.size() < 2:
		return {}
	var players: Array[Dictionary] = group.duplicate()
	players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return effective_mmr(a, party_rule) > effective_mmr(b, party_rule)
	)
	var capacities: Array[int] = [team_size, team_size]
	var sums: Array[float] = [0.0, 0.0]
	var teams: Array[Array] = [[], []]
	var oldest: float = now
	for entry: Dictionary in players:
		var party_size: int = int(entry["party_size"])
		var team: int = -1
		if capacities[0] >= party_size and capacities[1] >= party_size:
			if capacities[0] != capacities[1]:
				team = 0 if capacities[0] > capacities[1] else 1
			else:
				team = 0 if sums[0] <= sums[1] else 1
		elif capacities[0] >= party_size:
			team = 0
		elif capacities[1] >= party_size:
			team = 1
		if team < 0:
			return {}
		capacities[team] -= party_size
		sums[team] += effective_mmr(entry, party_rule) * float(party_size)
		teams[team].append(int(entry["id"]))
		oldest = minf(oldest, float(entry.get("joined", now)))
	if capacities[0] != 0 or capacities[1] != 0:
		return {}
	var avg1: float = sums[0] / float(team_size)
	var avg2: float = sums[1] / float(team_size)
	var ids: Array[int] = []
	for entry: Dictionary in players:
		ids.append(int(entry["id"]))
	return {
		"players": ids,
		"size": team_size * 2,
		"teams": teams,
		"team_mmr": [avg1, avg2],
		"spread": absf(avg1 - avg2),
		"wait": maxf(now - oldest, 0.0),
		"region": str(players[0].get("region", "auto")),
		"mode": mode,
	}


# --- Offline population simulation ------------------------------------------

## Generates a synthetic population, drains it and reports queue health. Used by
## tests and the balance dashboard to prove 1000 players match quickly.
static func simulate_population(population: int, team_size: int = 3, seconds: float = 30.0, tick_interval: float = 0.5, seed_value: int = 7) -> Dictionary:
	var matcher := Matchmaker.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var regions: Array[String] = ["eu", "na", "asia"]
	for i in population:
		var party_size: int = 1
		var roll: float = rng.randf()
		if roll > 0.94:
			party_size = 3
		elif roll > 0.82:
			party_size = 2
		var base_mmr: float = clampf(rng.randfn(1000.0, 240.0), 0.0, 4000.0)
		var party_mmrs: Array[float] = []
		for j in party_size:
			party_mmrs.append(clampf(base_mmr + rng.randfn(0.0, 35.0), 0.0, 4000.0))
		matcher.enqueue({
			"mmr": base_mmr,
			"rd": rng.randf_range(60.0, 350.0),
			"party_size": party_size,
			"party_mmrs": party_mmrs,
			"region": regions[rng.randi_range(0, regions.size() - 1)],
			"ping": rng.randi_range(12, 110),
			"joined": 0.0,
		})
	var formed: Array[Dictionary] = []
	var now: float = 0.0
	while now < seconds and matcher.size() >= team_size * 2:
		now += tick_interval
		var batch := matcher.tick(now, team_size, "", 120, "avg", "ranked")
		formed.append_array(batch)
	var max_wait: float = 0.0
	var spread_sum: float = 0.0
	for match_info: Dictionary in formed:
		max_wait = maxf(max_wait, float(match_info["wait"]))
		spread_sum += float(match_info["spread"])
	return {
		"matches": formed,
		"formed": formed.size(),
		"unmatched": matcher.size(),
		"max_wait": max_wait,
		"avg_spread": spread_sum / maxf(float(formed.size()), 1.0),
		"duration": now,
	}
