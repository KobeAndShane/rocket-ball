class_name DrillLibrary
extends RefCounted
## Built-in training packs plus user pack persistence. Packs are order-preserving
## arrays of DrillBase; the on-disk format is versioned JSON in user://.

const PACK_DIR := "user://training_packs"
const PACK_VERSION := 1
const REQUIRED_PACKS := ["onboarding", "gravity", "shots", "saves", "wall_plays", "aerials", "shift_drills"]
const STARTER_IDS := ["drive_forward", "boost", "jump", "dodge", "ball_touch"]


static func built_in_packs() -> Array[Dictionary]:
	return [
		_onboarding_pack(),
		_gravity_pack(),
		_shots_pack(),
		_saves_pack(),
		_wall_pack(),
		_aerials_pack(),
		_shift_pack(),
	]


static func all_packs() -> Array[Dictionary]:
	var packs: Array[Dictionary] = built_in_packs()
	packs.append_array(user_packs())
	return packs


static func pack_by_id(pack_id: String) -> Dictionary:
	for pack: Dictionary in all_packs():
		if str(pack.get("id", "")) == pack_id:
			return pack
	return {}


static func onboarding() -> Array[DrillBase]:
	return (_onboarding_pack()["drills"] as Array[DrillBase]).duplicate()


static func gravity_tutorial() -> Array[DrillBase]:
	return (_gravity_pack()["drills"] as Array[DrillBase]).duplicate()


static func starter_drill_ids() -> Array[String]:
	var out: Array[String] = []
	for id: String in STARTER_IDS:
		out.append(id)
	return out


static func _onboarding_pack() -> Dictionary:
	var drills: Array[DrillBase] = []
	drills.append(_drill("drive_forward", "Drive forward", "Hold accelerate and roll onto the pitch. Every surface is drivable once gravity turns.", "Hold W or push the left stick up.", DrillBase.SuccessKind.DRIVE_DISTANCE, 14.0))
	var boost := _drill("boost", "Use boost", "Boost is your speed and your air control. It refills on every gravity shift.", "Hold boost while driving forward.", DrillBase.SuccessKind.REACH_SPEED)
	boost.target_speed = 20.0
	drills.append(boost)
	drills.append(_drill("jump", "Jump", "Jump to clear the ball or start an aerial.", "Press jump.", DrillBase.SuccessKind.JUMP))
	drills.append(_drill("dodge", "Dodge", "Jump, then push a direction and jump again to dodge. Dodges are how you win kickoffs.", "Jump, steer, then jump again.", DrillBase.SuccessKind.DODGE))
	drills.append(_ball_touch_drill())
	var first_goal := _shot_drill("first_goal", "Score your first goal", "The orange goal is straight ahead. Drive through the ball and finish.", Vector3(0.0, -12.9, 24.0), Vector3(0.0, -14.1, 8.0), 0.0, 20.0)
	drills.append(first_goal)
	var pack := _pack("onboarding", "Onboarding", "Six steps from first drive to first goal.", drills, true)
	pack["tutorial"] = true
	return pack


static func _gravity_pack() -> Dictionary:
	var drills: Array[DrillBase] = []
	var wall := _drill("drive_up_wall", "Drive up the wall", "When gravity points sideways the wall becomes your floor. Keep your wheels planted and drive.", "Gravity now pulls you toward the right wall. Hold accelerate and steer with the surface.", DrillBase.SuccessKind.WALL_DRIVE)
	wall.gravity_dir = Vector3.LEFT
	wall.target_time = 2.5
	wall.car_spawn = Vector3(28.4, -8.0, -26.0)
	wall.car_forward = Vector3.FORWARD
	wall.has_car_spawn = true
	drills.append(wall)
	var ceiling := _drill("ceiling_land", "Land on the ceiling", "The ceiling is a pitch too. Fall toward it, let the suspension settle, then look for the ball.", "Gravity now pulls you toward the ceiling.", DrillBase.SuccessKind.CEILING_TOUCH)
	ceiling.gravity_dir = Vector3.UP
	ceiling.car_spawn = Vector3(0.0, 13.0, -18.0)
	ceiling.car_forward = Vector3.FORWARD
	ceiling.has_car_spawn = true
	drills.append(ceiling)
	var upside := _drill("upside_down_goal", "Score upside down", "With the ceiling under your wheels, push the ball into the orange goal at the far end.", "Gravity pulls you toward the ceiling. Drive forward into the ball.", DrillBase.SuccessKind.SCORE)
	upside.gravity_dir = Vector3.UP
	upside.ball_spawn = Vector3(0.0, 12.95, 27.0)
	upside.ball_velocity = Vector3(0.0, 0.0, 11.0)
	upside.has_ball_spawn = true
	upside.car_spawn = Vector3(0.0, 13.6, 16.0)
	upside.car_forward = Vector3.FORWARD
	upside.has_car_spawn = true
	upside.scoring_team = 1
	upside.require_upside_down = true
	upside.time_limit = 18.0
	drills.append(upside)
	var pack := _pack("gravity", "Gravity Tutorial", "Guided wall, ceiling and upside-down drills.", drills, true)
	pack["tutorial"] = true
	return pack


static func _shots_pack() -> Dictionary:
	var drills: Array[DrillBase] = []
	var ground := _shot_drill("ground_shot", "Ground shot", "Meet the ball with your nose and drive through it.", Vector3(0.0, -12.9, 12.0), Vector3(0.0, -14.1, -1.0), 0.0, 14.0)
	drills.append(ground)
	var long := _shot_drill("long_shot", "Long shot", "Boost through the ball from distance.", Vector3(0.0, -12.9, 22.0), Vector3(0.0, -14.1, -10.0), 24.0, 12.0)
	drills.append(long)
	var angled := _shot_drill("angled_shot", "Angled shot", "Approach from the side and aim across the goal mouth.", Vector3(9.0, -12.9, 24.0), Vector3(15.0, -14.1, 2.0), 0.0, 16.0)
	angled.scoring_team = 1
	drills.append(angled)
	return _pack("shots", "Shots", "Finish from the ground, from distance and from an angle.", drills, true)


static func _saves_pack() -> Dictionary:
	var drills: Array[DrillBase] = []
	var block := _drill("block_shot", "Block the shot", "The ball is heading for your goal. Get between the ball and the net.", "Drive toward your own goal and intercept.", DrillBase.SuccessKind.BALL_TOUCH)
	block.ball_spawn = Vector3(0.0, -12.9, 2.0)
	block.ball_velocity = Vector3(0.0, 0.0, -18.0)
	block.has_ball_spawn = true
	block.car_spawn = Vector3(0.0, -14.1, 18.0)
	block.car_forward = Vector3(0.0, 0.0, -1.0)
	block.has_car_spawn = true
	block.min_hit_strength = 3.0
	block.time_limit = 10.0
	drills.append(block)
	var clear := _drill("clear_ball", "Clear the ball", "A soft touch is not enough. Hit the ball hard enough to send it away.", "Drive through the ball.", DrillBase.SuccessKind.BALL_HIT_STRENGTH)
	clear.ball_spawn = Vector3(0.0, -12.9, -15.0)
	clear.ball_velocity = Vector3(0.0, 0.0, -8.0)
	clear.has_ball_spawn = true
	clear.car_spawn = Vector3(0.0, -14.1, 2.0)
	clear.car_forward = Vector3(0.0, 0.0, -1.0)
	clear.has_car_spawn = true
	clear.target_speed = 9.0
	clear.time_limit = 12.0
	drills.append(clear)
	var line := _drill("goal_line_save", "Goal-line save", "Stay on your line and meet the ball before it crosses.", "Wait near the goal then drive forward.", DrillBase.SuccessKind.BALL_TOUCH)
	line.ball_spawn = Vector3(0.0, -12.9, -26.0)
	line.ball_velocity = Vector3(0.0, 0.0, -12.0)
	line.has_ball_spawn = true
	line.car_spawn = Vector3(0.0, -14.1, -34.0)
	line.car_forward = Vector3.FORWARD
	line.has_car_spawn = true
	line.time_limit = 10.0
	drills.append(line)
	return _pack("saves", "Saves", "Read the shot, block it and clear it.", drills, true)


static func _wall_pack() -> Dictionary:
	var drills: Array[DrillBase] = []
	var ride := _drill("wall_ride", "Wall ride", "Gravity is sideways. Hold accelerate and let the wall carry you.", "Keep your wheels on the right wall.", DrillBase.SuccessKind.WALL_DRIVE)
	ride.gravity_dir = Vector3.LEFT
	ride.car_spawn = Vector3(28.4, -4.0, -24.0)
	ride.car_forward = Vector3.FORWARD
	ride.has_car_spawn = true
	ride.target_time = 3.0
	drills.append(ride)
	var jump := _drill("wall_jump", "Wall jump", "Jump off the wall, then use your second jump or a dodge to reach the ball.", "Press jump while on the wall.", DrillBase.SuccessKind.JUMP)
	jump.gravity_dir = Vector3.LEFT
	jump.car_spawn = Vector3(28.4, 0.0, -12.0)
	jump.car_forward = Vector3.FORWARD
	jump.has_car_spawn = true
	drills.append(jump)
	var touch := _drill("wall_touch", "Wall ball", "Drive along the wall and poke the ball away from it.", "The ball is floating beside the wall.", DrillBase.SuccessKind.BALL_TOUCH)
	touch.gravity_dir = Vector3.LEFT
	touch.car_spawn = Vector3(28.4, 0.0, -14.0)
	touch.car_forward = Vector3.FORWARD
	touch.has_car_spawn = true
	touch.ball_spawn = Vector3(26.0, 0.0, 2.0)
	touch.has_ball_spawn = true
	touch.ball_frozen = false
	touch.min_hit_strength = 2.0
	touch.time_limit = 18.0
	drills.append(touch)
	return _pack("wall_plays", "Wall Plays", "Ride, jump and strike from the wall.", drills, true)


static func _aerials_pack() -> Dictionary:
	var drills: Array[DrillBase] = []
	var floating := _drill("aerial_touch", "Aerial touch", "Jump, boost and meet the floating ball with your nose.", "Use jump then boost in the air.", DrillBase.SuccessKind.BALL_TOUCH)
	floating.ball_spawn = Vector3(0.0, -6.0, 8.0)
	floating.has_ball_spawn = true
	floating.ball_frozen = true
	floating.car_spawn = Vector3(0.0, -14.1, -2.0)
	floating.car_forward = Vector3.FORWARD
	floating.has_car_spawn = true
	floating.min_hit_strength = 2.0
	floating.time_limit = 20.0
	drills.append(floating)
	var double := _drill("double_jump", "Double jump", "Use both jumps to gain height before gravity pulls you back.", "Jump, then jump again in the air.", DrillBase.SuccessKind.JUMP)
	double.ball_spawn = Vector3(0.0, -4.0, 12.0)
	double.has_ball_spawn = true
	double.ball_frozen = true
	double.car_spawn = Vector3(0.0, -14.1, 0.0)
	double.car_forward = Vector3.FORWARD
	double.has_car_spawn = true
	drills.append(double)
	var aerial_goal := _drill("aerial_goal", "Aerial goal", "Meet the floating ball above the goal and knock it in.", "Boost early and aim your nose at the goal.", DrillBase.SuccessKind.SCORE)
	aerial_goal.ball_spawn = Vector3(0.0, -3.0, 33.0)
	aerial_goal.has_ball_spawn = true
	aerial_goal.ball_frozen = true
	aerial_goal.car_spawn = Vector3(0.0, -14.1, 16.0)
	aerial_goal.car_forward = Vector3.FORWARD
	aerial_goal.has_car_spawn = true
	aerial_goal.time_limit = 18.0
	drills.append(aerial_goal)
	return _pack("aerials", "Aerials", "Floating-ball touches, double jumps and aerial finishes.", drills, true)


static func _shift_pack() -> Dictionary:
	var drills: Array[DrillBase] = []
	var survive := _drill("shift_awareness", "Shift awareness", "Read the warning, stay off the walls and keep control through the shift.", "The arena rotates in 5 seconds. Keep moving.", DrillBase.SuccessKind.SURVIVE_SHIFT)
	survive.gravity_active = true
	survive.gravity_interval = 7.0
	survive.target_time = 6.0
	drills.append(survive)
	var fast := _drill("fast_shift", "Fast shift", "Short intervals force you to re-read gravity constantly.", "Another shift is coming almost immediately.", DrillBase.SuccessKind.SURVIVE_SHIFT)
	fast.gravity_active = true
	fast.gravity_interval = 4.5
	fast.target_time = 8.0
	drills.append(fast)
	var wall_shift := _drill("shift_wall", "Shift onto the wall", "When gravity turns sideways, get your wheels down and drive it out.", "A shift is coming. Keep driving.", DrillBase.SuccessKind.WALL_DRIVE)
	wall_shift.gravity_active = true
	wall_shift.gravity_interval = 5.0
	wall_shift.target_time = 2.0
	wall_shift.time_limit = 20.0
	drills.append(wall_shift)
	return _pack("shift_drills", "Shift Drills", "Practice reading and surviving gravity changes.", drills, true)


static func _shot_drill(id: String, title: String, description: String, ball: Vector3, car: Vector3, ball_speed: float, timeout: float) -> DrillBase:
	var drill := _drill(id, title, description, "Drive through the ball toward the far goal.", DrillBase.SuccessKind.SCORE)
	drill.ball_spawn = ball
	drill.has_ball_spawn = true
	drill.ball_velocity = Vector3(0.0, 0.0, ball_speed)
	drill.car_spawn = car
	drill.car_forward = (ball - car).normalized() if (ball - car).length_squared() > 0.01 else Vector3.FORWARD
	drill.has_car_spawn = true
	drill.scoring_team = 1
	drill.time_limit = timeout
	return drill


static func _ball_touch_drill() -> DrillBase:
	var drill := _drill("ball_touch", "Touch the ball", "Drive into the ball. Any solid contact counts.", "Roll forward into the ball.", DrillBase.SuccessKind.BALL_TOUCH)
	drill.ball_spawn = Vector3(0.0, -12.9, 3.0)
	drill.has_ball_spawn = true
	drill.car_spawn = Vector3(0.0, -14.1, -8.0)
	drill.car_forward = Vector3.FORWARD
	drill.has_car_spawn = true
	drill.min_hit_strength = 1.0
	drill.time_limit = 16.0
	return drill


static func _drill(id: String, title: String, description: String, hint: String, kind: int, distance: float = 0.0) -> DrillBase:
	var drill := DrillBase.new()
	drill.id = id
	drill.title = title
	drill.description = description
	drill.hint = hint
	drill.success_kind = kind
	if distance > 0.0:
		drill.target_distance = distance
	return drill


static func _pack(id: String, name: String, description: String, drills: Array[DrillBase], built_in: bool) -> Dictionary:
	return {
		"id": id,
		"name": name,
		"description": description,
		"drills": drills,
		"built_in": built_in,
		"path": "",
	}


# --- User packs --------------------------------------------------------------

static func ensure_pack_dir() -> void:
	if not DirAccess.dir_exists_absolute(PACK_DIR):
		DirAccess.make_dir_recursive_absolute(PACK_DIR)


static func user_packs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	ensure_pack_dir()
	var dir := DirAccess.open(PACK_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file := dir.get_next()
	while file != "":
		if not dir.current_is_dir() and file.ends_with(".json"):
			var loaded := load_user_pack(PACK_DIR.path_join(file))
			if not loaded.is_empty():
				out.append(loaded)
		file = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0
	)
	return out


static func save_user_pack(name: String, drills: Array[DrillBase], description: String = "") -> String:
	ensure_pack_dir()
	var safe := _safe_name(name)
	if safe == "":
		safe = "custom_pack"
	var path := PACK_DIR.path_join("%s.json" % safe)
	var payload := {
		"version": PACK_VERSION,
		"id": "user_%s" % safe,
		"name": name if name.strip_edges() != "" else "Custom Pack",
		"description": description,
		"drills": [],
	}
	var list: Array = payload["drills"]
	for drill: DrillBase in drills:
		list.append(drill.to_dict())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return path


static func load_user_pack(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return {}
	var data: Dictionary = parsed
	var drills: Array[DrillBase] = []
	for entry: Variant in data.get("drills", []):
		if entry is Dictionary:
			drills.append(DrillBase.from_dict(entry))
	if drills.is_empty():
		return {}
	return {
		"id": str(data.get("id", "user_pack")),
		"name": str(data.get("name", "Custom Pack")),
		"description": str(data.get("description", "")),
		"drills": drills,
		"built_in": false,
		"path": path,
	}


static func delete_user_pack(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var full := path
	if not full.begins_with("user://"):
		full = "user://" + path
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(full)) == OK


static func validate_pack(drills: Array[DrillBase]) -> Array[String]:
	var issues: Array[String] = []
	if drills.is_empty():
		issues.append("Pack has no drills")
	var ids: Dictionary = {}
	for drill: DrillBase in drills:
		if drill.id.strip_edges() == "":
			issues.append("Drill is missing an id")
		elif ids.has(drill.id):
			issues.append("Duplicate drill id: %s" % drill.id)
		ids[drill.id] = true
		if drill.title.strip_edges() == "":
			issues.append("Drill %s is missing a title" % drill.id)
		if drill.time_limit <= 0.0:
			issues.append("Drill %s has no time limit" % drill.id)
	return issues


static func _safe_name(name: String) -> String:
	var lower := name.to_lower().strip_edges()
	var out := ""
	for i in lower.length():
		var ch := lower[i]
		if ch == " " or ch == "-":
			out += "_"
		elif (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_":
			out += ch
	return out.trim_prefix("_").trim_suffix("_")
