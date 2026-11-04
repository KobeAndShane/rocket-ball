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
	await _test_bots()
	await _test_rank_helpers()
	await _test_glicko2()
	await _test_ranked_profile()
	await _test_matchmaker_filters()
	await _test_matchmaking_population()
	await _test_matchmaking_service()
	await _test_matchmaking_menu_launch()
	await _test_cosmetics_library()
	await _test_car_cosmetics_neutral()
	await _test_progression_and_presets()
	await _test_season_pass()
	await _test_challenge_tracks()
	await _test_profile_pages()
	await _test_car_settles_on_floor()
	await _test_snapshot_codec()
	await _test_input_redundancy()
	await _test_prediction_reconciliation()
	await _test_network_simulation()
	await _test_network_roster()


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

func _test_bots() -> void:
	_begin("Bots")
	var rules := RULES.duplicate() as MatchRules
	rules.team_size = 3
	rules.fill_with_bots = true
	rules.kickoff_countdown = 0.1
	rules.gravity_interval = 2.0
	rules.gravity_transition = 0.2
	rules.gravity_warning = 0.5
	rules.replay_enabled = false
	var scene := MATCH_SCENE.instantiate() as MatchController
	scene.auto_start = true
	scene.headless_mode = true
	scene.spawn_hud = false
	scene.spawn_camera = false
	scene.all_bots = true
	scene.rules = rules
	_track(scene)
	add_child(scene)
	await _frames(3)
	_check(scene.cars.size() == 6, "bot match spawns six cars")
	var brains: Array[BotBrain] = []
	for car: Car in scene.cars:
		var brain := car.get_node_or_null("BotBrain") as BotBrain
		if brain != null:
			brains.append(brain)
	_check(brains.size() == 6, "every car has a bot brain", "brains=%d" % brains.size())
	await _frames(240)
	var roles_ok := true
	var targets_ok := true
	for brain: BotBrain in brains:
		if brain.role < 0 or brain.role > 2:
			roles_ok = false
		if not scene.arena.is_position_inside(brain._target, 2.0):
			targets_ok = false
	_check(roles_ok, "bots assign striker/support/goalie roles")
	_check(targets_ok, "bot targets stay inside the arena")
	var started := false
	for car: Car in scene.cars:
		if car.global_position.distance_to(car.spawn_transform.origin) > 1.0:
			started = true
			break
	_check(started, "bots leave their spawn and drive")
	_check(scene.ball.global_position.length() < 100.0, "ball remains simulated")
	await _cleanup()


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


# --- 11 matchmaking / ranking ------------------------------------------------

func _test_glicko2() -> void:
	_begin("Glicko-2")
	var winner := Glicko2.new(1000.0, 350.0, 0.06)
	var start_rd: float = winner.rd
	winner.update(1000.0, 200.0, 1.0)
	_check(winner.rating > 1000.0, "win raises rating", "rating=%.1f" % winner.rating)
	_check(winner.rd < start_rd, "RD shrinks after a result", "rd=%.1f" % winner.rd)
	var loser := Glicko2.new(1000.0, 120.0, 0.06)
	var before_loss: float = loser.rating
	loser.update(1000.0, 120.0, 0.0)
	_check(loser.rating < before_loss, "loss lowers rating", "rating=%.1f" % loser.rating)
	var roundtrip := Glicko2.from_dict(loser.to_dict())
	_check(_near(roundtrip.rating, loser.rating) and _near(roundtrip.rd, loser.rd), "rating serialises")
	var upset := Glicko2.new(800.0, 200.0, 0.06)
	var favourite := Glicko2.new(1400.0, 100.0, 0.06)
	var upset_gain: float = float(upset.update(1400.0, 100.0, 1.0)["delta"])
	var expected_gain: float = float(Glicko2.new(1000.0, 200.0, 0.06).update(1000.0, 100.0, 1.0)["delta"])
	_check(upset_gain > expected_gain, "upsets move ratings more", "%.1f vs %.1f" % [upset_gain, expected_gain])
	_check(favourite.rd >= Glicko2.MIN_RD, "RD never drops below the floor")
	await _cleanup()


func _test_ranked_profile() -> void:
	_begin("Ranked profile, placements, seasons and leavers")
	var original: Dictionary = Meta.profile.duplicate(true)
	Meta.profile["mmr"] = 1000.0
	Meta.profile["peak_mmr"] = 1000.0
	Meta.profile["rd"] = 350.0
	Meta.profile["volatility"] = 0.06
	Meta.profile["placement_matches"] = 0
	Meta.profile["ranked_matches"] = 0
	Meta.profile["ranked_wins"] = 0
	Meta.profile["smurf_risk"] = 0.0
	Meta.profile["season"] = 1
	Meta.profile["season_started"] = Time.get_unix_time_from_system()
	Meta.profile["season_matches"] = 0
	Meta.profile["season_wins"] = 0
	Meta.profile["season_peak_mmr"] = 1000.0
	Meta.profile["season_history"] = []
	Meta.profile["abandon_count"] = 0
	Meta.profile["leaver_cooldown_until"] = 0.0
	_check(Meta.rank_name() == "Unranked", "new accounts are unranked")
	var first := Meta.apply_rated_result(true, 1000.0, 200.0, 4.0)
	_check(float(first["mmr"]) > 1000.0, "placement win raises MMR")
	_check(float(first["rd"]) < 350.0, "placement win tightens RD")
	_check(int(Meta.profile["placement_matches"]) == 1, "placement counter increments")
	_check(float(Meta.profile["smurf_risk"]) > 0.0, "large-margin wins raise smurf risk")
	for i in 9:
		Meta.apply_rated_result(true, 1000.0, 200.0, 2.0)
	_check(int(Meta.profile["placement_matches"]) == Meta.PLACEMENT_MATCHES, "10 placements complete")
	_check(Meta.rank_name() != "Unranked", "placement completion shows rank", Meta.rank_name())
	_check(Meta.is_flagged_smurf(), "repeated high-margin wins flag smurf risk")
	Meta.profile["smurf_risk"] = 1.0
	_check(_near(Meta.smurf_multiplier(), 1.5, 0.001), "smurf multiplier caps at 1.5", "%.2f" % Meta.smurf_multiplier())
	var old_mmr: float = float(Meta.profile["mmr"])
	var old_season: int = int(Meta.profile["season"])
	var reset := Meta.start_new_season(Time.get_unix_time_from_system())
	_check(int(Meta.profile["season"]) == old_season + 1, "season increments")
	_check(_near(float(Meta.profile["mmr"]), 1000.0 + (old_mmr - 1000.0) * 0.5, 0.01), "soft reset halves distance from 1000", "mmr=%.1f" % float(Meta.profile["mmr"]))
	_check(int(Meta.profile["placement_matches"]) == 0, "new season requires placements again")
	_check(int(reset["season"]) == old_season + 1, "reset result reports the new season")
	_check((Meta.profile["season_history"] as Array).size() == 1, "season archive is stored")
	_check(Meta.rank_name() == "Unranked", "soft reset is provisional")
	var now: float = 200000.0
	var cooldown: float = Meta.register_abandon(now)
	_check(_near(cooldown, 300.0), "first abandon is a 5 minute cooldown")
	_check(not Meta.can_queue(now + 1.0), "queue is locked during cooldown")
	_check(Meta.can_queue(now + cooldown + 1.0), "queue unlocks after cooldown")
	var second: float = Meta.register_abandon(now + cooldown + 2.0)
	_check(_near(second, 900.0), "second abandon escalates to 15 minutes")
	_check(not Meta.check_season_rollover(now), "season does not roll before expiry")
	_check(Meta.check_season_rollover(Meta.season_ends_at() + 1.0), "expired season rolls over automatically")
	Meta.profile = original
	Meta.save_profile()
	await _cleanup()


func _test_matchmaker_filters() -> void:
	_begin("Matchmaker filters and party MMR")
	var matcher := Matchmaker.new()
	var average: float = matcher.effective_mmr({"party_size": 2, "party_mmrs": [1000.0, 1400.0]}, "avg")
	var maximum: float = matcher.effective_mmr({"party_size": 2, "party_mmrs": [1000.0, 1400.0]}, "max")
	_check(_near(average, 1200.0), "party average rule", "%.1f" % average)
	_check(_near(maximum, 1400.0), "party max rule", "%.1f" % maximum)
	var early: float = matcher.search_window({"joined": 0.0}, 2.0, "ranked")
	var later: float = matcher.search_window({"joined": 0.0}, 20.0, "ranked")
	_check(later > early, "search window expands with wait time")
	var ping_matcher := Matchmaker.new()
	ping_matcher.enqueue({"mmr": 1000.0, "region": "eu", "ping": 30, "joined": 0.0})
	ping_matcher.enqueue({"mmr": 1000.0, "region": "eu", "ping": 220, "joined": 0.0})
	var blocked := ping_matcher.tick(2.0, 1, "eu", 120, "avg", "ranked")
	_check(blocked.is_empty(), "high-ping players are filtered out")
	_check(ping_matcher.size() == 2, "filtered players stay queued")
	var region_matcher := Matchmaker.new()
	region_matcher.enqueue({"mmr": 1000.0, "region": "eu", "ping": 20, "joined": 0.0})
	region_matcher.enqueue({"mmr": 1000.0, "region": "na", "ping": 20, "joined": 0.0})
	_check(region_matcher.tick(2.0, 1, "eu", 120, "avg", "ranked").is_empty(), "region filter rejects cross-region pairs")
	var fair := Matchmaker.new()
	for i in 6:
		fair.enqueue({"mmr": 1000.0 + i * 5.0, "region": "eu", "ping": 25, "joined": 0.0})
	var matches := fair.tick(4.0, 3, "eu", 120, "avg", "ranked")
	_check(matches.size() == 1, "six players form one 3v3")
	if not matches.is_empty():
		_check(float(matches[0]["spread"]) <= 30.0, "balanced team MMR", "spread=%.1f" % float(matches[0]["spread"]))
	_check(fair.size() == 0, "matched players leave the queue")
	await _cleanup()


func _test_matchmaking_population() -> void:
	_begin("1000-player matchmaking simulation")
	var started: int = Time.get_ticks_msec()
	var report: Dictionary = Matchmaker.simulate_population(1000, 3, 30.0, 0.5, 7)
	var elapsed_ms: int = Time.get_ticks_msec() - started
	var formed: int = int(report["formed"])
	_check(formed >= 150, "1000 players produce at least 150 matches", "formed=%d" % formed)
	_check(float(report["max_wait"]) <= 30.0, "matches form within the 30 s target", "max_wait=%.1f" % float(report["max_wait"]))
	_check(float(report["avg_spread"]) <= 250.0, "team MMR spread stays balanced", "avg_spread=%.1f" % float(report["avg_spread"]))
	_check(elapsed_ms < 5000, "simulation completes in under 5 seconds", "%d ms" % elapsed_ms)
	# Matches must fill six seats and never reuse a queue entry. Parties are one
	# entry with multiple seats, so seat count comes from the match size field.
	var seen: Dictionary = {}
	var valid: bool = true
	for info: Dictionary in report["matches"]:
		if int(info["size"]) != 6:
			valid = false
		for id: Variant in info["players"]:
			if seen.has(int(id)):
				valid = false
			seen[int(id)] = true
	_check(valid, "every match fills six disjoint seats")
	_check(int(report["unmatched"]) <= 40, "queue drains almost completely", "unmatched=%d" % int(report["unmatched"]))
	await _cleanup()


func _test_matchmaking_service() -> void:
	_begin("Matchmaking service")
	var original: Dictionary = Meta.profile.duplicate(true)
	Meta.profile["mmr"] = 1000.0
	Meta.profile["rd"] = 200.0
	Meta.profile["placement_matches"] = Meta.PLACEMENT_MATCHES
	Meta.profile["leaver_cooldown_until"] = 0.0
	Settings.set_setting("game/team_size", 3, false)
	Settings.set_setting("net/region", "auto", false)
	Settings.set_setting("net/mmr_rule", "avg", false)
	var captured: Array[Dictionary] = []
	var on_found := func(info: Dictionary) -> void: captured.append(info)
	Matchmaking.match_found.connect(on_found)
	_check(Matchmaking.queue("ranked"), "ranked queue starts")
	_check(Matchmaking.in_queue, "service reports queued")
	_check(Matchmaking.queue_size() >= 6, "synthetic population fills the queue", "size=%d" % Matchmaking.queue_size())
	_check(not Matchmaking.queue("casual"), "cannot queue twice")
	for i in 8:
		if Matchmaking.in_queue:
			Matchmaking.elapsed += 1.0
			Matchmaking.tick_now()
	_check(captured.size() == 1, "service emits one match", "count=%d" % captured.size())
	if not captured.is_empty():
		var info: Dictionary = captured[0]
		_check(bool(info.get("ranked", false)), "match carries ranked flag")
		_check(int(info.get("team_size", 0)) == 3, "match carries team size")
		_check(int(info.get("size", 0)) == 6, "match fills six seats")
		_check((info.get("team_mmr", []) as Array).size() == 2, "match reports both team MMRs")
		_check(int(info.get("local_team", -1)) >= 0, "match resolves the local team")
	captured.clear()
	_check(Matchmaking.queue("casual"), "casual queue starts")
	for i in 8:
		if Matchmaking.in_queue:
			Matchmaking.elapsed += 1.0
			Matchmaking.tick_now()
	_check(captured.size() == 1, "casual service emits one match")
	if not captured.is_empty():
		_check(not bool(captured[0].get("ranked", true)), "casual match is unrated")
	_check(Matchmaking.queue("ranked"), "queue can be restarted")
	Matchmaking.cancel(true)
	_check(not Matchmaking.in_queue, "cancel clears the queue")
	_check(Matchmaking.queue_size() == 0, "cancel empties the matcher")
	Matchmaking.match_found.disconnect(on_found)
	Meta.profile = original
	Meta.save_profile()
	await _cleanup()


func _test_matchmaking_menu_launch() -> void:
	_begin("Matchmaking menu integration")
	var original: Dictionary = Meta.profile.duplicate(true)
	Meta.profile["mmr"] = 1100.0
	Meta.profile["rd"] = 180.0
	Meta.profile["placement_matches"] = Meta.PLACEMENT_MATCHES
	Meta.profile["leaver_cooldown_until"] = 0.0
	var menu := _track(load("res://ui/Main.tscn").instantiate()) as Control
	add_child(menu)
	await get_tree().process_frame
	var started: bool = Matchmaking.queue("ranked")
	_check(started, "menu can start a ranked queue")
	for i in 8:
		if Matchmaking.in_queue:
			Matchmaking.elapsed += 1.0
			Matchmaking.tick_now()
	await get_tree().process_frame
	var controller: MatchController = menu.get("_match") as MatchController
	_check(controller != null, "queue result launches the match scene")
	if controller != null:
		_check(controller.rules.ranked, "launched rules are ranked")
		_check(controller.rules.team_size == 3, "launched rules keep 3v3")
		_check(controller.rules.opponent_mmr > 0.0, "launched rules carry opponent MMR")
		_check(controller.rules.match_id != "", "launched match has an id")
		_check(not menu.visible, "menu hides when the match starts")
	Matchmaking.cancel(true)
	Meta.profile = original
	Meta.save_profile()
	await _cleanup()


# --- 12 progression / cosmetics ---------------------------------------------

func _test_cosmetics_library() -> void:
	_begin("Cosmetic library")
	var issues := CosmeticLibrary.validate()
	_check(issues.is_empty(), "catalog is structurally valid", str(issues))
	var items := CosmeticLibrary.all()
	_check(items.size() >= 20, "catalog contains at least 20 items", "count=%d" % items.size())
	_check(CosmeticLibrary.get_item("body_orbiter") != null, "named resource loads")
	_check(CosmeticLibrary.get_item("missing") == null, "unknown id returns null")
	for slot: String in CosmeticLibrary.SLOTS:
		_check(not CosmeticLibrary.items_for_slot(slot).is_empty(), "%s has items" % slot)
	var default := CosmeticLibrary.default_loadout()
	_check(default.size() == CosmeticLibrary.SLOTS.size(), "default loadout covers every slot")
	var clean := CosmeticLibrary.sanitize_loadout({
		"body": "does_not_exist",
		"wheel": "body_stock",
		"boost": "boost_ion",
	})
	_check(clean["body"] == "body_stock", "unknown id falls back to default")
	_check(clean["wheel"] == "wheel_stock", "wrong-slot id falls back to default")
	_check(clean["boost"] == "boost_ion", "valid id survives sanitising")
	await _cleanup()


func _test_car_cosmetics_neutral() -> void:
	_begin("Car cosmetics are presentation-only")
	var car := _track(CAR_SCENE.instantiate() as Car) as Car
	var tuning := CAR_TUNING.duplicate() as CarTuning
	car.tuning = tuning
	add_child(car)
	await _frames(1)
	var collider := car.get_node("CollisionShape3D") as CollisionShape3D
	var before: Vector3 = (collider.shape as BoxShape3D).size
	var loadout := {
		"body": "body_orbiter",
		"wheel": "wheel_neon",
		"boost": "boost_ion",
		"trail": "trail_comet",
		"decal": "decal_hex",
		"explosion": "explosion_blackhole",
		"antenna": "antenna_flag",
	}
	car.apply_cosmetics(loadout)
	_check(car.cosmetic_body_id == "body_orbiter", "body cosmetic applied")
	_check(car.cosmetic_wheel_id == "wheel_neon", "wheel cosmetic applied")
	_check(car.cosmetic_boost_id == "boost_ion", "boost cosmetic applied")
	_check(car.cosmetic_decal_id == "decal_hex", "decal cosmetic applied")
	_check(car.cosmetic_antenna_id == "antenna_flag", "antenna cosmetic applied")
	_check(car.cosmetic_explosion_id == "explosion_blackhole", "explosion cosmetic stored")
	var after: Vector3 = (collider.shape as BoxShape3D).size
	_check(before.is_equal_approx(after), "collider size never changes", "%s -> %s" % [before, after])
	_check(before.is_equal_approx(tuning.collider_size), "collider still follows tuning")
	var decal := car.get_node_or_null("DecalMesh") as MeshInstance3D
	_check(decal != null and decal.visible, "decal overlay is visible")
	var antenna := car.get_node_or_null("Antenna") as Node3D
	_check(antenna != null and antenna.visible, "antenna is visible")
	_check(car.get_node_or_null("BoostTrail") is CPUParticles3D, "boost trail particles exist")
	var wheels: Array = car.get("_wheel_nodes") as Array
	_check(wheels.size() == tuning.wheel_offsets.size(), "every wheel exists")
	car.apply_cosmetics({"body": "nope"})
	_check(car.cosmetic_body_id == "body_stock", "invalid loadout falls back safely")
	await _cleanup()


func _test_progression_and_presets() -> void:
	_begin("XP, unlocks, presets and career stats")
	var original: Dictionary = Meta.profile.duplicate(true)
	Meta.profile["level"] = 1
	Meta.profile["xp"] = 0
	Meta.profile["credits"] = 5000
	Meta.profile["inventory"] = CosmeticLibrary.default_loadout().values()
	Meta.profile["loadout"] = CosmeticLibrary.default_loadout()
	Meta.profile["loadout_presets"] = [{"name": "Default", "loadout": CosmeticLibrary.default_loadout()}]
	Meta.add_xp(1000)
	_check(int(Meta.profile["level"]) == 2, "1000 XP levels up", "level=%d" % int(Meta.profile["level"]))
	_check(int(Meta.profile["credits"]) == 5100, "level up grants credits")
	_check(not Meta.purchase("body_interceptor"), "store gates on player level")
	Meta.profile["level"] = 5
	_check(Meta.purchase("body_interceptor"), "unlocked item can be purchased")
	_check(Meta.owns("body_interceptor"), "purchase enters the inventory")
	_check(Meta.equip("body_interceptor"), "owned item equips")
	_check(Meta.equipped("body") == "body_interceptor", "equipped id round-trips")
	_check(Meta.unequip("body"), "unequip returns the default body")
	_check(Meta.equipped("body") == "body_stock", "default body restored")
	Meta.profile["inventory"].append("wheel_neon")
	Meta.equip("body_interceptor")
	Meta.equip("wheel_neon")
	var preset_index: int = Meta.save_loadout_preset("Test Preset")
	_check(preset_index >= 0, "preset saves", "index=%d" % preset_index)
	Meta.set_loadout(CosmeticLibrary.default_loadout())
	_check(Meta.equipped("body") == "body_stock", "loadout can be reset")
	_check(Meta.apply_loadout_preset(preset_index), "preset loads")
	_check(Meta.equipped("body") == "body_interceptor", "preset restores body")
	_check(Meta.equipped("wheel") == "wheel_neon", "preset restores wheels")
	_check(Meta.delete_loadout_preset(preset_index), "preset deletes")
	Meta.profile["matches"] = 10
	Meta.profile["wins"] = 6
	Meta.profile["playtime"] = 3660.0
	var summary := Meta.career_summary()
	_check(_near(float(summary["win_rate"]), 0.6, 0.001), "career win rate", "%.2f" % float(summary["win_rate"]))
	_check(str(summary["playtime_text"]) == "1h 01m", "playtime formats", str(summary["playtime_text"]))
	Meta.profile = original
	Meta.save_profile()
	await _cleanup()


func _test_season_pass() -> void:
	_begin("Season pass tracks")
	var original: Dictionary = Meta.profile.duplicate(true)
	Meta.profile["season_xp"] = 20000
	Meta.profile["season_rewards_claimed"] = []
	Meta.profile["premium_pass"] = false
	Meta.profile["credits"] = 5000
	var progress := Meta.season_pass_progress()
	_check(int(progress["level"]) == 5, "season XP maps to a pass level", "level=%d" % int(progress["level"]))
	_check(Meta.claim_season_reward(1, false), "free reward claims")
	_check(not Meta.claim_season_reward(1, false), "free reward cannot be double-claimed")
	_check(not Meta.claim_season_reward(2, true), "premium reward is gated")
	_check(Meta.purchase_premium_pass(), "premium track can be unlocked")
	_check(Meta.claim_season_reward(2, true), "premium reward claims after unlock")
	_check(not Meta.claim_season_reward(10, false), "locked level cannot be claimed")
	Meta.profile["season_xp"] = 120000
	_check(Meta.season_pass_level() == 25, "season level caps at the track", "level=%d" % Meta.season_pass_level())
	_check(Meta.claim_season_reward(25, false), "season-exclusive cosmetic claims")
	_check(Meta.owns("body_aurora"), "season reward grants the cosmetic")
	var reward := Meta.season_reward(25, false)
	_check(str(reward["cosmetic"]) == "body_aurora", "level 25 free reward is the Aurora body")
	Meta.profile = original
	Meta.save_profile()
	await _cleanup()


func _test_challenge_tracks() -> void:
	_begin("Daily and weekly challenge tracks")
	var original: Dictionary = Meta.profile.duplicate(true)
	Meta.profile["challenges_date"] = ""
	Meta.profile["challenges_week"] = ""
	Meta.profile["challenge_progress"] = {}
	Meta.profile["challenges_claimed"] = {"daily": [], "weekly": []}
	Meta.daily_challenges.clear()
	Meta.weekly_challenges.clear()
	Meta._ensure_challenges()
	_check(Meta.daily_challenges.size() == 3, "three daily challenges", "count=%d" % Meta.daily_challenges.size())
	_check(Meta.weekly_challenges.size() == 4, "four weekly challenges", "count=%d" % Meta.weekly_challenges.size())
	Meta._add_challenge_progress("goals", 5)
	var goal_entry: Dictionary = {}
	for entry: Dictionary in Meta.weekly_challenges:
		if str(entry["id"]) == "goals":
			goal_entry = entry
	_check(not goal_entry.is_empty(), "weekly goals challenge exists")
	var state := Meta.challenge_state(goal_entry)
	_check(int(state["progress"]) == 5, "weekly progress is tracked separately", "progress=%d" % int(state["progress"]))
	Meta.profile["challenge_progress"]["weekly:goals"] = int(goal_entry["target"])
	var credits_before: int = int(Meta.profile["credits"])
	_check(Meta.claim_challenge(goal_entry), "completed weekly challenge claims")
	_check(int(Meta.profile["credits"]) > credits_before, "challenge pays credits")
	_check(not Meta.claim_challenge(goal_entry), "challenge cannot be claimed twice")
	_check(str(Meta._week_key()).begins_with(str(Time.get_datetime_dict_from_system()["year"])), "week key is year-scoped")
	Meta.profile = original
	Meta.save_profile()
	await _cleanup()


func _test_profile_pages() -> void:
	_begin("Profile, locker and season pass pages")
	var menu := _track(load("res://ui/Main.tscn").instantiate()) as Control
	add_child(menu)
	await get_tree().process_frame
	menu.call("_show_profile")
	var content := menu.get("content") as VBoxContainer
	_check(content != null and content.get_child_count() > 0, "profile page builds")
	menu.call("_show_season_pass")
	_check(content != null and content.get_child_count() > 0, "season pass page builds")
	menu.call("_show_locker")
	await get_tree().process_frame
	var preview := menu.find_child("LockerPreview", true, false) as CarPreview
	_check(preview != null, "locker embeds the car preview")
	if preview != null and preview.car != null:
		_check(preview.car.get_node_or_null("DecalMesh") != null, "preview car has cosmetics applied")
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


func _test_snapshot_codec() -> void:
	_begin("Snapshot codec")
	GravityManager.configure(null, 0)
	var car := _track(CAR_SCENE.instantiate() as Car) as Car
	car.car_id = 3
	car.tuning = CAR_TUNING.duplicate() as CarTuning
	add_child(car)
	await _frames(1)
	car.global_transform = Transform3D(Basis(Vector3.UP, 0.6), Vector3(4.0, -2.5, 7.25))
	car.linear_velocity = Vector3(3.5, -1.25, 12.0)
	if car.boost_component != null:
		car.boost_component.set_amount(77.0)
	var ball := _track(BALL_SCENE.instantiate() as Ball) as Ball
	add_child(ball)
	await _frames(1)
	ball.set_snapshot_state({"p": Vector3(-6.5, 8.25, -12.0), "q": Quaternion.IDENTITY, "v": Vector3(1.0, 2.0, 3.0), "w": Vector3(0.5, 0.25, 0.125)})
	var meta := {"state": 2, "score1": 4, "score2": 1, "time_left": 87.38, "countdown": 0.0, "overtime": 12.5}
	var data := SnapshotCodec.encode(12345, 2, [car], ball, meta)
	_check(data.size() > 20 and data.size() < 160, "snapshot fits the bandwidth budget", "bytes=%d" % data.size())
	var decoded := SnapshotCodec.decode(data)
	_check(int(decoded["tick"]) == 12345, "tick round-trips")
	_check(int(decoded["phase"]) == 2, "gravity phase round-trips")
	_check((decoded["cars"] as Array).size() == 1, "car count round-trips")
	var snap_car: Dictionary = (decoded["cars"] as Array)[0]
	_check(int(snap_car["id"]) == 3, "car id round-trips")
	_check((snap_car["p"] as Vector3).distance_to(car.global_position) < 0.02, "quantised position is accurate")
	_check(absf(absf((snap_car["q"] as Quaternion).dot(car.global_transform.basis.get_rotation_quaternion())) - 1.0) < 0.002, "packed quaternion is accurate")
	_check((snap_car["v"] as Vector3).distance_to(car.linear_velocity) < 0.05, "velocity is accurate")
	var snap_ball: Dictionary = decoded["ball"]
	_check(not snap_ball.is_empty() and (snap_ball["p"] as Vector3).distance_to(ball.global_position) < 0.02, "ball state round-trips")
	var dm: Dictionary = decoded["m"]
	_check(int(dm["state"]) == 2 and int(dm["score1"]) == 4 and int(dm["score2"]) == 1, "match metadata round-trips")
	_check(absf(float(dm["time_left"]) - 87.38) < 0.02, "match clock round-trips")
	await _cleanup()


func _test_input_redundancy() -> void:
	_begin("Input buffering")
	var buffer := InputBuffer.new()
	for i in 5:
		var input := CarInput.new()
		input.tick = i
		input.throttle = float(i) / 10.0
		input.boost = i == 4
		buffer.push(input)
		buffer.push(input) # duplicate retransmission
	var first := buffer.consume_new()
	_check(first.size() == 5, "server applies each tick exactly once", "applied=%d" % first.size())
	_check(buffer.consume_new().is_empty(), "duplicate retransmissions are ignored")
	var latest := buffer.latest(3)
	_check(latest.size() == 3 and latest[0].tick == 2 and latest[2].tick == 4, "redundancy carries the last three inputs")
	var packed := InputBuffer.pack(latest)
	var unpacked := InputBuffer.unpack(packed)
	_check(unpacked.size() == 3, "input packet round-trips")
	_check(unpacked[2].tick == 4 and unpacked[2].boost, "input tick and buttons survive packing")
	_check(absf(unpacked[1].throttle - 0.3) < 0.02, "analogue throttle is quantised accurately")
	await _cleanup()


func _test_prediction_reconciliation() -> void:
	_begin("Prediction reconciliation")
	GravityManager.configure(null, 0)
	var car := _track(CAR_SCENE.instantiate() as Car) as Car
	car.tuning = CAR_TUNING.duplicate() as CarTuning
	car.car_id = 0
	add_child(car)
	await _frames(1)
	var prediction := PredictionController.new()
	prediction.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(prediction)
	_track(prediction)
	prediction.setup(car, NetManager)
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(50.0, 20.0, 0.0))
	var pending := CarInput.new()
	pending.tick = 10
	prediction.history.push(pending)
	prediction.apply_snapshot({"p": Vector3(0.0, 2.0, 0.0), "q": Quaternion.IDENTITY, "v": Vector3.ZERO, "s": 0}, 9)
	_check(prediction.corrections == 1, "large divergence triggers a correction")
	_check(car.global_position.distance_to(Vector3(0.0, 2.0, 0.0)) < 0.2, "car snaps to authority then replays pending input", "pos=%s" % car.global_position)
	car.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.12, 2.0, 0.0))
	prediction.history.clear()
	prediction.apply_snapshot({"p": Vector3(0.0, 2.0, 0.0), "q": Quaternion.IDENTITY, "v": Vector3.ZERO, "s": 0}, 11)
	_check(prediction.last_snapshot_error > 0.05, "small divergence is measured")
	_check(prediction._has_correction, "small divergence is blended rather than teleported")
	await _cleanup()


func _test_network_simulation() -> void:
	_begin("Network simulation")
	NetManager.set_simulated_network(120, 0.0)
	_check(NetManager.get_ping_ms() == 120, "artificial latency is reported")
	_check(_near(NetManager.latency_seconds(), 0.12, 0.001), "latency converts to seconds")
	NetManager.set_simulated_network(0, 1.0)
	_check(NetManager.should_drop_packet(), "100% loss drops packets")
	NetManager.set_simulated_network(0, 0.0)
	_check(not NetManager.should_drop_packet(), "zero loss delivers packets")
	var before := NetManager.server_tick
	NetManager._physics_process(1.0 / 120.0)
	NetManager._physics_process(1.0 / 120.0)
	_check(NetManager.server_tick == before + 2, "shared tick counter advances at physics rate")
	await _cleanup()


func _test_network_roster() -> void:
	_begin("Network roster")
	NetManager.is_offline = false
	NetManager.is_server = false
	NetManager.local_peer_id = 2
	NetManager.players = {
		1: {"name": "Host", "team": 1, "car_id": 0, "ready": true, "party": "", "loadout": {"body": "body_interceptor"}},
		2: {"name": "Client", "team": 1, "car_id": 1, "ready": true, "party": "", "loadout": {"body": "body_orbiter"}},
	}
	var rules := RULES.duplicate() as MatchRules
	rules.team_size = 3
	rules.fill_with_bots = true
	rules.kickoff_countdown = 3.0
	var scene := MATCH_SCENE.instantiate() as MatchController
	scene.rules = rules
	scene.auto_start = false
	scene.headless_mode = true
	scene.spawn_camera = false
	scene.spawn_hud = false
	_track(scene)
	add_child(scene)
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	_check(scene.cars.size() == 6, "client builds the full 3v3 roster", "cars=%d" % scene.cars.size())
	_check(NetManager.cars.size() == 6, "every car is registered with the network")
	_check(scene.local_car != null and scene.local_car.car_id == 1, "local car follows the lobby assignment")
	_check(scene.local_car.control_mode == Car.DriveMode.HUMAN, "local car is human-controlled")
	_check(scene.local_car.cosmetic_body_id == "body_orbiter", "local loadout renders from the lobby", scene.local_car.cosmetic_body_id)
	var host_car: Car = null
	for car: Car in scene.cars:
		if car.car_id == 0:
			host_car = car
			break
	_check(host_car != null and host_car.cosmetic_body_id == "body_interceptor", "remote loadout replicates to this client")
	var remote_ok := true
	for car: Car in scene.cars:
		if car == scene.local_car:
			continue
		if car.control_mode != Car.DriveMode.NETWORK or not car.frozen or car.collision_layer != 0:
			remote_ok = false
	_check(remote_ok, "remote cars are frozen snapshot proxies")
	_check(scene.ball.freeze and scene.ball.collision_layer == 0, "client ball is snapshot-driven")
	await _cleanup()
	NetManager.start_offline()
	GravityManager.configure(null, 0)


func _report() -> void:
	print("\n=== Results ===")
	print("Passed: %d" % _passes)
	print("Failed: %d" % _failures.size())
	for failure: String in _failures:
		print("  - %s" % failure)
	print("=== %s ===" % ("OK" if _failures.is_empty() else "FAILURES"))
