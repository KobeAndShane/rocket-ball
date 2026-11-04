class_name CosmeticLibrary
extends RefCounted
## Canonical cosmetic catalog and loadout hygiene.
##
## Authored resources live in res://cosmetics/items/*.tres. If the folder has
## not been generated yet (or a build strips it), the same definitions are
## constructed in code so the game and tests still boot.

const SLOTS: Array[String] = ["body", "wheel", "boost", "trail", "decal", "explosion", "antenna"]
const ITEM_DIR := "res://cosmetics/items"

static var _loaded: bool = false
static var _all: Array[CosmeticItem] = []
static var _cache: Dictionary = {}


## Load every authored item once. Falls back to generated defaults.
static func all() -> Array[CosmeticItem]:
	if _loaded:
		return _all
	_loaded = true
	_all.clear()
	_cache.clear()
	var paths: Array[String] = _paths()
	for path: String in paths:
		var loaded: Resource = ResourceLoader.load(path)
		if loaded is CosmeticItem:
			_all.append(loaded as CosmeticItem)
	if _all.is_empty():
		_all = build_defaults()
	for item: CosmeticItem in _all:
		_cache[item.id] = item
	return _all


## Kicks off background loading. all() still works normally if the caller needs
## the cache immediately (for example during a headless test run).
static func preload_async() -> void:
	if _loaded:
		return
	for path: String in _paths():
		ResourceLoader.load_threaded_request(path, "Resource")


static func get_item(id: String) -> CosmeticItem:
	all()
	return _cache.get(id) as CosmeticItem


static func items_for_slot(slot: String) -> Array[CosmeticItem]:
	var out: Array[CosmeticItem] = []
	for item: CosmeticItem in all():
		if item.slot == slot:
			out.append(item)
	return out


static func default_loadout() -> Dictionary:
	var out: Dictionary = {}
	for slot: String in SLOTS:
		out[slot] = ""
	for item: CosmeticItem in all():
		if not SLOTS.has(item.slot):
			continue
		if item.default_owned or str(out.get(item.slot, "")) == "":
			if item.default_owned:
				out[item.slot] = item.id
			elif str(out.get(item.slot, "")) == "":
				out[item.slot] = item.id
	return out


## Replaces unknown ids and wrong-slot entries with the default item.
static func sanitize_loadout(loadout: Dictionary) -> Dictionary:
	var out: Dictionary = default_loadout()
	for slot: String in SLOTS:
		var id: String = str(loadout.get(slot, ""))
		var item := get_item(id)
		if item != null and item.slot == slot:
			out[slot] = id
	return out


## Build-time definitions. The tools/CosmeticBuilder script saves these as
## individual CosmeticItem.tres resources.
static func build_defaults() -> Array[CosmeticItem]:
	var out: Array[CosmeticItem] = []

	var stock_body := _make("body_stock", "body", "Stock Body", "common", 0, true, 1, Color(0.22, 0.42, 0.65), Color(0.25, 0.8, 1.0))
	stock_body.description = "The dependable academy chassis."
	out.append(stock_body)

	var interceptor := _make("body_interceptor", "body", "Interceptor", "rare", 800, false, 5, Color(0.05, 0.45, 0.42), Color(0.2, 1.0, 0.85))
	interceptor.description = "Low, wide and built for wall runs."
	interceptor.body_scale = Vector3(1.04, 0.9, 1.04)
	interceptor.cabin_scale = Vector3(0.92, 0.78, 0.92)
	interceptor.cabin_offset = Vector3(0.0, 0.33, 0.15)
	interceptor.metallic = 0.7
	interceptor.emission_strength = 0.35
	out.append(interceptor)

	var orbiter := _make("body_orbiter", "body", "Orbiter", "epic", 1500, false, 10, Color(0.36, 0.2, 0.62), Color(0.9, 0.45, 1.0))
	orbiter.description = "A rounded gravity-era prototype."
	orbiter.body_scale = Vector3(1.0, 1.06, 1.0)
	orbiter.cabin_scale = Vector3(1.1, 1.0, 1.05)
	orbiter.cabin_offset = Vector3(0.0, 0.44, 0.1)
	orbiter.emission_strength = 0.55
	out.append(orbiter)

	var aurora_body := _make("body_aurora", "body", "Aurora", "legendary", 0, false, 1, Color(0.05, 0.7, 0.55), Color(0.55, 1.0, 0.95))
	aurora_body.description = "Season pass reward. The hull glows like a magnetosphere."
	aurora_body.body_scale = Vector3(1.03, 1.0, 1.03)
	aurora_body.emission_strength = 1.1
	aurora_body.season_only = true
	out.append(aurora_body)

	var stock_wheels := _make("wheel_stock", "wheel", "Stock Wheels", "common", 0, true, 1, Color(0.06, 0.06, 0.07), Color(0.2, 0.22, 0.26))
	stock_wheels.description = "Simple, grippy and honest."
	stock_wheels.emission_strength = 0.0
	out.append(stock_wheels)

	var neon_wheels := _make("wheel_neon", "wheel", "Neon Spokes", "rare", 500, false, 3, Color(0.05, 0.05, 0.08), Color(0.2, 0.95, 1.0))
	neon_wheels.description = "Six glowing spokes per wheel."
	neon_wheels.emission_strength = 1.8
	neon_wheels.wheel_width = 0.17
	neon_wheels.wheel_spokes = 6
	out.append(neon_wheels)

	var gravity_wheels := _make("wheel_gravity", "wheel", "Gravity Rings", "epic", 1200, false, 8, Color(0.12, 0.03, 0.2), Color(0.75, 0.3, 1.0))
	gravity_wheels.description = "Oversized rings that shrug off the shift."
	gravity_wheels.emission_strength = 1.2
	gravity_wheels.wheel_radius = 0.37
	gravity_wheels.wheel_width = 0.2
	gravity_wheels.wheel_spokes = 12
	out.append(gravity_wheels)

	var standard_boost := _make("boost_standard", "boost", "Standard Boost", "common", 0, true, 1, Color(0.3, 0.7, 1.0), Color(1.0, 1.0, 1.0))
	standard_boost.description = "Blue flame, no nonsense."
	standard_boost.trail_style = 1
	standard_boost.emission_strength = 1.0
	out.append(standard_boost)

	var ion_boost := _make("boost_ion", "boost", "Ion Trail", "rare", 600, false, 6, Color(0.15, 0.9, 0.45), Color(0.8, 1.0, 0.9))
	ion_boost.description = "A crackling green ion stream."
	ion_boost.trail_style = 2
	ion_boost.emission_strength = 1.8
	out.append(ion_boost)

	var supernova_boost := _make("boost_supernova", "boost", "Supernova", "legendary", 2000, false, 14, Color(1.0, 0.55, 0.1), Color(1.0, 0.9, 0.35))
	supernova_boost.description = "A short-lived star follows every boost."
	supernova_boost.trail_style = 3
	supernova_boost.emission_strength = 2.4
	out.append(supernova_boost)

	var no_decal := _make("decal_none", "decal", "No Decal", "common", 0, true, 1, Color.WHITE, Color.WHITE)
	no_decal.description = "Clean paint."
	out.append(no_decal)

	var stripes := _make("decal_stripes", "decal", "Twin Stripes", "uncommon", 250, false, 2, Color.WHITE, Color(0.9, 0.95, 1.0))
	stripes.description = "Two racing stripes down the hood."
	stripes.decal_pattern = 1
	out.append(stripes)

	var hex := _make("decal_hex", "decal", "Hex Shift", "epic", 1100, false, 9, Color.WHITE, Color(0.2, 1.0, 0.9))
	hex.description = "A shifting hex lattice."
	hex.decal_pattern = 2
	hex.emission_strength = 0.9
	out.append(hex)

	var standard_burst := _make("explosion_standard", "explosion", "Standard Burst", "common", 0, true, 1, Color(1.0, 0.55, 0.2), Color(1.0, 0.9, 0.5))
	standard_burst.description = "A bright, friendly goal burst."
	standard_burst.explosion_style = 1
	standard_burst.emission_strength = 2.0
	out.append(standard_burst)

	var singularity := _make("explosion_blackhole", "explosion", "Singularity", "legendary", 2500, false, 15, Color(0.2, 0.05, 0.3), Color(0.8, 0.2, 1.0))
	singularity.description = "Collapse the goal into a violet singularity."
	singularity.explosion_style = 2
	singularity.emission_strength = 2.2
	out.append(singularity)

	var no_antenna := _make("antenna_none", "antenna", "No Antenna", "common", 0, true, 1, Color.WHITE, Color.WHITE)
	no_antenna.description = "Nothing extra on the roof."
	out.append(no_antenna)

	var flag := _make("antenna_flag", "antenna", "Gravity Flag", "rare", 350, false, 4, Color(0.3, 0.9, 1.0), Color(0.9, 1.0, 1.0))
	flag.description = "A small flag that points at the current floor."
	flag.antenna_style = 1
	out.append(flag)

	var no_trail := _make("trail_none", "trail", "No Trail", "common", 0, true, 1, Color.WHITE, Color.WHITE)
	no_trail.description = "No supersonic trail."
	out.append(no_trail)

	var comet := _make("trail_comet", "trail", "Comet", "epic", 1400, false, 7, Color(1.0, 0.6, 0.2), Color(1.0, 0.9, 0.5))
	comet.description = "Supersonic runs leave a comet tail."
	comet.trail_style = 2
	comet.emission_strength = 1.6
	out.append(comet)

	var aurora_trail := _make("trail_aurora", "trail", "Aurora Wake", "legendary", 0, false, 1, Color(0.2, 1.0, 0.7), Color(0.7, 1.0, 1.0))
	aurora_trail.description = "Season pass reward. Leave ribbons of light behind you."
	aurora_trail.trail_style = 3
	aurora_trail.emission_strength = 2.0
	aurora_trail.season_only = true
	out.append(aurora_trail)

	return out


## Structural checks used by the test suite and the content builder.
static func validate() -> Array[String]:
	var issues: Array[String] = []
	var seen: Dictionary = {}
	for item: CosmeticItem in all():
		if item.id.strip_edges() == "":
			issues.append("item with empty id")
			continue
		if seen.has(item.id):
			issues.append("duplicate id %s" % item.id)
		seen[item.id] = true
		if not SLOTS.has(item.slot):
			issues.append("%s has unknown slot %s" % [item.id, item.slot])
		if item.price < 0:
			issues.append("%s has negative price" % item.id)
		if item.unlock_level < 1:
			issues.append("%s has invalid unlock level" % item.id)
		if item.season_only and item.price > 0:
			issues.append("%s is season-only but has a store price" % item.id)
	for slot: String in SLOTS:
		if items_for_slot(slot).is_empty():
			issues.append("slot %s has no items" % slot)
		var default_id: String = str(default_loadout().get(slot, ""))
		if default_id == "" or get_item(default_id) == null:
			issues.append("slot %s has no default item" % slot)
	return issues


static func _make(id: String, slot: String, display_name: String, rarity: String, price: int, owned: bool, level: int, primary: Color, accent: Color) -> CosmeticItem:
	var item := CosmeticItem.new()
	item.id = id
	item.slot = slot
	item.display_name = display_name
	item.rarity = rarity
	item.price = price
	item.default_owned = owned
	item.unlock_level = level
	item.primary_color = primary
	item.accent_color = accent
	item.secondary_color = primary.darkened(0.35)
	return item


static func _paths() -> Array[String]:
	var out: Array[String] = []
	var files: PackedStringArray = DirAccess.get_files_at(ITEM_DIR)
	for file: String in files:
		if file.ends_with(".tres"):
			out.append(ITEM_DIR + "/" + file)
	out.sort()
	return out
