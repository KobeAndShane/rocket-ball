extends Node3D
## Lightweight headless test runner (no external dependency).
##
## Run with:
##   godot --headless --path . res://tests/TestRunner.tscn
##
## Exit code is 0 when every test passes, 1 otherwise.

const CAR_SCENE := preload("res://car/Car.tscn")
const BALL_SCENE := preload("res://ball/Ball.tscn")
const GOAL_SCENE := preload("res://arena/Goal.tscn")
const MATCH_SCENE := preload("res://match/Match.tscn")
const RULES := preload("res://match/MatchRules.tres")
const CAR_TUNING := preload("res://car/CarTuning.tres")

var _passes: int = 0
var _failures: Array[String] = []
var _current: String = ""
var _spawned: Array[Node] = []


func _ready() -> void:
	await get_tree().process_frame
	await _run_all()
	_report()
	var code: int = 0 if _failures.is_empty() else 1
	get_tree().quit(code)


func _run_all() -> void:
	print("=== Gravity Shift test suite ===")
	await _test_boost_component()
	await _test_car_input_serialization()
	await _test_dodge_mapping()
	await _test_gravity_phase_order()
	await _test_gravity_seeded_determinism()
	await _test_gravity_blend()
	await _test_ball_speed_clamp()
	await _test_goal_fires_once()
	await _test_pad_symmetry()
	await _test_rules_defaults()
	await _test_mutators()
	await _test_free_play_spawn()
	await _test_match_timer_and_overtime()
	await _test_demo_respawn()
	await _test_rank_helpers()
	await _test_car_settles_on_floor()


# --- helpers -----------------------------------------------------------------

func _begin(name: String) -> void:
	_current = name
	print("\n[%s]" % name)


func _check(condition: bool, what: String, detail: String = "") -> void:
	if condition:
		_passes += 1
		print("  PASS  %s" % what)
	else:
		var message := what
		if detail != "":
			message += "  (%s)" % detail
		_failures.append("%s / %s" % [_current, message])
		print("  FAIL  %s" % message)


func _near(a: float, b: float, epsilon: float = 0.001) -> bool:
	return absf(a - b) <= epsilon


func _track(node: Node) -> Node:
	_spawned.append(node)
	return node


func _cleanup() -> void:
	for node: Node in _spawned:
		if is_instance_valid(node):
			node.queue_free()
	_spawned.clear()
	await get_tree().process_frame


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


# --- 01 vehicle physics ------------------------------------------------------

func _test_boost_component() -> void:
	_begin("BoostComponent")
	var boost := BoostComponent.new()
	boost.max_boost = 100.0
	boost.consumption_per_second = 50.0
	add_child(boost)
	_track(boost)
	_check(_near(boost.amount, 100.0), "starts full")
	var consumed: bool = boost.consume(0.5)
	_check(consumed and _near(boost.amount, 75.0), "consumes rate * delta", "amount=%.2f" % boost.amount)
	boost.add(50.0)
	_check(_near(boost.amount, 100.0), "add clamps to max")
	boost.add(20.0, true)
	_check(_near(boost.amount, 120.0), "large pad may exceed max", "amount=%.2f" % boost.amount)
	boost.add(80.0, true)
	_check(_near(boost.amount, 150.0), "over-max boost is capped at 150%%", "amount=%.2f" % boost.amount)
	boost.set_amount(100.0)
	boost.set_amount(0.0)
	_check(not boost.consume(0.1), "empty meter refuses consumption")
	boost.reset()
	_check(_near(boost.amount, 100.0), "reset refills")
	boost.unlimited = true
	boost.set_amount(5.0)
	_check(boost.consume(1.0) and _near(boost.amount, 100.0), "unlimited boost stays full")
	await _cleanup()


func _test_car_input_serialization() -> void:
	_begin("CarInput serialisation")
	var source := CarInput.new()
	source.throttle = 1.0
	source.steer = -0.5
	source.pitch = 0.25
	source.yaw = -1.0
	source.roll = 0.75
	source.jump_pressed = true
	source.jump_held = true
	source.boost = true
	source.handbrake = false
	source.air_roll = true
	source.tick = 424242
	var data := source.serialize()
	_check(data.size() >= 10, "packet has >= 10 bytes", "size=%d" % data.size())
	var decoded := CarInput.deserialize(data)
	_check(_near(decoded.throttle, 1.0, 0.01), "throttle round-trips")
	_check(_near(decoded.steer, -0.5, 0.02), "negative steer round-trips", "got=%.3f" % decoded.steer)
	_check(_near(decoded.pitch, 0.25, 0.02), "pitch round-trips")
	_check(_near(decoded.yaw, -1.0, 0.02), "yaw round-trips")
	_check(_near(decoded.roll, 0.75, 0.02), "roll round-trips")
	_check(decoded.jump_pressed and decoded.jump_held, "jump flags round-trip")
	_check(decoded.boost and not decoded.handbrake and decoded.air_roll, "button flags round-trip")
	_check(decoded.tick == 424242, "tick round-trips", "got=%d" % decoded.tick)
	await _cleanup()


func _test_dodge_mapping() -> void:
	_begin("Dodge direction mapping")
	var basis := Basis.IDENTITY
	var up := Vector3.UP
	var forward := CarInput.dodge_world_direction(Vector2(0.0, 1.0), basis, up)
	_check(forward.dot(Vector3.FORWARD) > 0.98, "stick forward maps to car forward", "dot=%.3f" % forward.dot(Vector3.FORWARD))
	var back := CarInput.dodge_world_direction(Vector2(0.0, -1.0), basis, up)
	_check(back.dot(Vector3.BACK) > 0.98, "stick back maps to car back")
	var right := CarInput.dodge_world_direction(Vector2(1.0, 0.0), basis, up)
	_check(right.dot(Vector3.RIGHT) > 0.98, "stick right maps to car right")
	var left := CarInput.dodge_world_direction(Vector2(-1.0, 0.0), basis, up)
	_check(left.dot(Vector3.LEFT) > 0.98, "stick left maps to car left")
	var no_input := CarInput.dodge_world_direction(Vector2.ZERO, basis, up)
	_check(no_input.dot(Vector3.FORWARD) > 0.98, "neutral defaults forward")
	_check(CarInput.dodge_label(Vector2(0.0, 1.0)) == "forward", "8-way label forward")
	_check(CarInput.dodge_label(Vector2(1.0, 1.0)) == "forward-right", "8-way label diagonal")
	_check(CarInput.dodge_label(Vector2.ZERO) == "none", "8-way label none")
	# In a ceiling-gravity frame the dodge must stay on the plane perpendicular to up.
	var ceiling_up := Vector3.DOWN
	var ceiling_dir := CarInput.dodge_world_direction(Vector2(0.0, 1.0), basis, ceiling_up)
	_check(absf(ceiling_dir.dot(ceiling_up)) < 0.05, "dodge respects local up")
	await _cleanup()


# --- 02 ball -----------------------------------------------------------------

func _test_ball_speed_clamp() -> void:
	_begin("Ball speed clamp")
	var old_strength: float = GravityManager.gravity_strength
	GravityManager.gravity_strength = 0.0
	var ball := _track(BALL_SCENE.instantiate() as Ball) as Ball
	ball.position = Vector3(0.0, 40.0, 0.0)
	add_child(ball)
	await _frames(2)
	var tuning := ball.tuning
	ball.linear_velocity = Vector3(500.0, 0.0, 0.0)
	ball.angular_velocity = Vector3(0.0, 900.0, 0.0)
	await _frames(3)
	_check(ball.linear_velocity.length() <= tuning.max_speed + 0.5, "linear speed clamped", "v=%.2f max=%.2f" % [ball.linear_velocity.length(), tuning.max_speed])
	_check(ball.angular_velocity.length() <= tuning.max_angular_speed + 0.5, "angular speed clamped", "w=%.2f max=%.2f" % [ball.angular_velocity.length(), tuning.max_angular_speed])
	GravityManager.gravity_strength = old_strength
	await _cleanup()


func _test_goal_fires_once() -> void:
	_begin("Goal event fires once")
	var goal := _track(GOAL_SCENE.instantiate() as Goal) as Goal
	goal.defending_team = 1
	add_child(goal)
	var old_strength: float = GravityManager.gravity_strength
	GravityManager.gravity_strength = 0.0
	var ball := _track(BALL_SCENE.instantiate() as Ball) as Ball
	ball.position = Vector3(0.0, 0.0, -20.0)
	add_child(ball)
	await _frames(2)
	var hits: Array[int] = []
	var handler := func(team: int, _scorer: int) -> void:
		hits.append(team)
	Events.goal_scored.connect(handler)
	ball.global_position = goal.global_position + Vector3(0.0, 0.0, 3.0)
	await _frames(6)
	_check(hits.size() == 1, "one goal event for a ball in the trigger", "events=%d" % hits.size())
	_check(not hits.is_empty() and hits[0] == 2, "defending team 1 concedes to team 2")
	ball.global_position = goal.global_position + Vector3(0.0, 0.0, 5.0)
	await _frames(6)
	_check(hits.size() == 1, "latched goal does not fire again")
	goal.reset_latch()
	ball.global_position = goal.global_position + Vector3(0.0, 0.0, -20.0)
	await _frames(4)
	ball.global_position = goal.global_position + Vector3(0.0, 0.0, 1.0)
	await _frames(6)
	_check(hits.size() == 2, "reset_latch allows the next goal")
	Events.goal_scored.disconnect(handler)
	GravityManager.gravity_strength = old_strength
	await _cleanup()


# --- 03 arena ----------------------------------------------------------------

func _test_pad_symmetry() -> void:
	_begin("Boost pad layout")
	var arena := Arena.new()
	var layout := arena.pad_layout()
	var large := 0
	var small := 0
	for entry: Dictionary in layout:
		if bool(entry["large"]):
			large += 1
		else:
			small += 1
	_check(large == 6, "6 large pads", "got=%d" % large)
	_check(small >= 24, "at least 24 small pads", "got=%d" % small)
	_check(arena.is_pad_layout_symmetric(), "layout is mirror symmetric across X and Z")
	for entry: Dictionary in layout:
		var n: Vector3 = entry["normal"]
		_check(absf(n.length() - 1.0) < 0.01, "pad normal normalised")
		break
	arena.free()


# --- 04 gravity --------------------------------------------------------------

func _test_gravity_phase_order() -> void:
	_begin("Gravity phase order")
	GravityManager.stop()
	GravityManager.configure(null, 0)
	var expected: Array[Vector3] = [GravityManager.PHASE_WALL_A, GravityManager.PHASE_CEILING, GravityManager.PHASE_WALL_B, GravityManager.PHASE_FLOOR]
	var ok := true
	for index in expected.size():
		GravityManager.force_next_phase()
		if not GravityManager.gravity_dir.is_equal_approx(expected[index]):
			ok = false
			break
	_check(ok, "cycle is floor -> wall A -> ceiling -> wall B -> floor")
	_check(GravityManager.phases().size() == 4, "four default phases")
	_check(GravityManager.up.is_equal_approx(Vector3.DOWN) == false, "up is defined from gravity")
	GravityManager.configure(null, 0)
	_check(GravityManager.up.is_equal_approx(Vector3.UP), "configure resets to floor")
	await _frames(1)


func _test_gravity_seeded_determinism() -> void:
	_begin("Gravity seeded determinism")
	var rules := RULES.duplicate() as MatchRules
	rules.random_gravity = true
	GravityManager.configure(rules, 12345)
	var first: Array[int] = []
	for i in 8:
		GravityManager.force_next_phase()
		first.append(GravityManager.phase_index)
	GravityManager.configure(rules, 12345)
	var second: Array[int] = []
	for i in 8:
		GravityManager.force_next_phase()
		second.append(GravityManager.phase_index)
	_check(first == second, "same seed produces the same phase sequence", str(first) + " vs " + str(second))
	GravityManager.configure(rules, 999)
	var third: Array[int] = []
	for i in 8:
		GravityManager.force_next_phase()
		third.append(GravityManager.phase_index)
	_check(first != third, "different seed produces a different sequence")
	GravityManager.configure(null, 0)
	await _frames(1)


func _test_gravity_blend() -> void:
	_begin("Gravity blend")
	var mid: Vector3 = GravityManager._blend_direction(Vector3.DOWN, Vector3.UP, 0.5)
	_check(mid.length() > 0.9, "antipodal blend is normalised", "len=%.3f" % mid.length())
	_check(absf(mid.y) < 0.05, "antipodal blend passes through the horizontal plane", "y=%.3f" % mid.y)
	var start: Vector3 = GravityManager._blend_direction(Vector3.DOWN, Vector3.LEFT, 0.0)
	var finish: Vector3 = GravityManager._blend_direction(Vector3.DOWN, Vector3.LEFT, 1.0)
	_check(start.is_equal_approx(Vector3.DOWN), "blend starts at the old direction")
	_check(finish.is_equal_approx(Vector3.LEFT), "blend ends at the new direction")
	await _frames(1)


# --- 05 match ----------------------------------------------------------------

func _test_rules_defaults() -> void:
	_begin("MatchRules defaults")
	var rules := RULES as MatchRules
	_check(rules.match_duration == 300.0, "5 minute regulation")
	_check(rules.team_size == 3, "default 3v3")
	_check(rules.gravity_interval == 30.0, "gravity interval 30 s")
	_check(rules.gravity_transition == 2.0, "transition 2 s")
	_check(rules.replay_enabled, "replays enabled")
	_check(rules.enabled_phases.size() == 4, "four enabled phases")


func _test_mutators() -> void:
	_begin("Mutators")
	var rules := RULES.duplicate() as MatchRules
	var list := MutatorLibrary.build(["low_gravity", "big_ball", "fast_shift"])
	_check(list.size() == 3, "three mutators built")
	for entry: Resource in list:
		(entry as MutatorBase).apply(rules, null)
	_check(_near(rules.gravity_strength, 20.0 * 0.55, 0.01), "low gravity scales gravity strength")
	_check(_near(rules.ball_radius_scale, 1.55, 0.01), "big ball scales radius")
	_check(_near(rules.gravity_interval, 15.0, 0.01), "fast shift shortens interval")
	_check(_near(rules.gravity_warning, 3.0, 0.01), "fast shift shortens warning")
	var conflicting := MutatorLibrary.build(["no_boost", "unlimited_boost"])
	var valid := MutatorLibrary.validate(conflicting)
	_check(valid.size() == 1, "no-boost and unlimited-boost conflict", "size=%d" % valid.size())
	_check(MutatorLibrary.catalog().size() >= 6, "catalog lists six mutators")
	rules.mutators = MutatorLibrary.build(["random_shift"])
	var match_scene := MATCH_SCENE.instantiate() as MatchController
	match_scene.auto_start = false
	match_scene.headless_mode = true
	match_scene.spawn_hud = false
	match_scene.spawn_camera = false
	match_scene.rules = rules
	_track(match_scene)
	add_child(match_scene)
	await _frames(2)
	match_scene.start_match()
	_check(match_scene.rules.random_gravity, "match applies mutator at kickoff")
	_check(match_scene.rules.mutators.size() == 1, "working rules carry the mutator")
	await _cleanup()


func _test_free_play_spawn() -> void:
	_begin("Free play mode")
	var rules := RULES.duplicate() as MatchRules
	rules.free_play = true
	rules.team_size = 1
	rules.fill_with_bots = false
	rules.match_duration = 3600.0
	rules.overtime_enabled = false
	var scene := MATCH_SCENE.instantiate() as MatchController
	scene.auto_start = false
	scene.headless_mode = true
	scene.spawn_hud = false
	scene.spawn_camera = false
	scene.all_bots = false
	scene.rules = rules
	_track(scene)
	add_child(scene)
	await _frames(3)
	_check(scene.cars.size() == 1, "free play spawns only the local car", "cars=%d" % scene.cars.size())
	_check(scene.local_car != null, "free play assigns a local car")
	_check(scene.local_car.team == 1, "local car is on blue")
	await _cleanup()


func _test_match_timer_and_overtime() -> void:
	_begin("Match timer / overtime")
	var scene := MATCH_SCENE.instantiate() as MatchController
	scene.auto_start = false
	scene.headless_mode = true
	scene.spawn_hud = false
	scene.spawn_camera = false
	scene.all_bots = true
	_track(scene)
	add_child(scene)
	await _frames(3)
	_check(scene.cars.size() == 6, "3v3 spawns six cars", "got=%d" % scene.cars.size())
	_check(scene.ball != null, "ball spawned")
	_check(scene.arena != null and scene.arena.goals.size() == 2, "two goals built")
	scene.start_match()
	_check(scene.time_left == 300.0, "start resets timer")
	_check(scene.score1 == 0 and scene.score2 == 0, "start resets score")
	_check(scene.state == MatchController.State.COUNTDOWN, "kickoff countdown begins")
	# Force the regulation clock to expire while tied.
	scene.score1 = 2
	scene.score2 = 2
	scene.time_left = 0.0
	scene._on_regulation_end()
	_check(scene.in_overtime, "tied regulation starts overtime")
	_check(scene.state == MatchController.State.COUNTDOWN, "overtime restarts kickoff")
	# Overtime golden goal ends the match.
	scene.state = MatchController.State.OVERTIME
	scene._on_goal_scored(1, 0)
	_check(scene.score1 == 3, "overtime goal scores")
	_check(scene.state == MatchController.State.GOAL_PAUSE, "goal pauses play")
	scene._finish_goal_pause()
	_check(scene.state == MatchController.State.POSTGAME, "golden goal ends the match")
	# Restart resets overtime and score.
	scene.rematch()
	_check(scene.score1 == 0 and scene.score2 == 0, "rematch resets score")
	_check(not scene.in_overtime and scene.time_left == 300.0, "rematch resets overtime and clock")
	await _cleanup()


func _test_demo_respawn() -> void:
	_begin("Demolition respawn")
	var car := _track(CAR_SCENE.instantiate() as Car) as Car
	var tuning := CAR_TUNING.duplicate() as CarTuning
	tuning.demolish_respawn_time = 0.15
	car.tuning = tuning
	add_child(car)
	await _frames(2)
	car.demolish(99)
	_check(car.state == Car.State.DEMOLISHED, "demolish sets DEMOLISHED")
	_check(not car.visible, "demolished car is hidden")
	await _frames(30)
	_check(car.state != Car.State.DEMOLISHED, "auto-respawn after the timer", "state=%d" % car.state)
	_check(car.visible, "respawned car is visible")
	await _cleanup()


# --- 11 / meta ---------------------------------------------------------------

func _test_rank_helpers() -> void:
	_begin("Rank helpers")
	_check(Meta.rank_for_mmr(-1.0) == "Unranked", "negative MMR is unranked")
	_check(Meta.rank_for_mmr(0.0).begins_with("Bronze"), "0 MMR is Bronze")
	_check(Meta.rank_for_mmr(1000.0).begins_with("Platinum"), "1000 MMR is Platinum", Meta.rank_for_mmr(1000.0))
	_check(Meta.rank_for_mmr(5000.0) == "Grand Champion", "high MMR is Grand Champion")
	_check(Meta.xp_for_level(1) == 1000, "level 1 XP requirement")
	_check(Meta.xp_for_level(3) > Meta.xp_for_level(2), "XP curve grows")
	_check(Meta.cosmetic("body_stock").size() > 0, "catalog lookup works")
	_check(Meta.cosmetic("does_not_exist").is_empty(), "unknown cosmetic is empty")
	await _cleanup()


# --- 01 integration ----------------------------------------------------------

func _test_car_settles_on_floor() -> void:
	_begin("Car settles on floor")
	var arena := _track(Arena.new() as Arena) as Arena
	arena.build_environment = false
	arena.build_pads = false
	add_child(arena)
	await _frames(2)
	var car := _track(CAR_SCENE.instantiate() as Car) as Car
	car.tuning = CAR_TUNING.duplicate() as CarTuning
	car.frozen = false
	car.reset_to_kickoff(arena.get_spawn_transform(1, 1))
	add_child(car)
	await _frames(150)
	_check(car.is_grounded(), "car reports grounded after settling", "state=%d wheels=%d y=%.2f" % [car.state, car.wheels_on_ground, car.global_position.y])
	_check(car.global_position.y > -Arena.HALF_EXTENTS.y - 1.0, "car did not fall through the floor", "y=%.2f" % car.global_position.y)
	# Flip gravity to the left wall and let the car settle again.
	GravityManager.force_direction(Vector3.LEFT)
	car.reset_to_kickoff(Transform3D(Basis.IDENTITY, Vector3(-Arena.HALF_EXTENTS.x + 2.0, 0.0, 0.0)))
	await _frames(150)
	_check(car.wheels_on_ground > 0 or car.is_grounded(), "car finds a surface on the wall", "wheels=%d state=%d" % [car.wheels_on_ground, car.state])
	GravityManager.configure(null, 0)
	await _cleanup()


func _report() -> void:
	print("\n=== Results ===")
	print("Passed: %d" % _passes)
	print("Failed: %d" % _failures.size())
	for failure: String in _failures:
		print("  - %s" % failure)
	print("=== %s ===" % ("OK" if _failures.is_empty() else "FAILURES"))
