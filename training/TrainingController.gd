class_name TrainingController
extends Node3D
## Self-contained training arena. One human car, one ball, no opponents. Drills
## are a sequence of data objects; the controller owns reset, timing, success
## detection and the lightweight pack editor.

signal drill_changed(index: int)
signal drill_completed(index: int)
signal pack_finished
signal editor_changed(active: bool)

const ARENA_SCENE := preload("res://arena/Arena.tscn")
const CAR_SCENE := preload("res://car/Car.tscn")
const BALL_SCENE := preload("res://ball/Ball.tscn")
const CAMERA_SCENE := preload("res://camera/ChaseCamera.tscn")
const BASE_RULES := preload("res://match/MatchRules.tres")
const BASE_CAR_TUNING := preload("res://car/CarTuning.tres")
const BASE_BALL_TUNING := preload("res://ball/BallTuning.tres")
const VFX_SERVICE := preload("res://vfx/VFXService.gd")
const ARENA_LAYER := 1

static var selected_pack_id: String = "onboarding"
static var selected_drill_index: int = 0

var arena: Arena
var car: Car
var ball: Ball
var camera: ChaseCamera
var vfx: VFXService

var pack: Dictionary = {}
var drills: Array[DrillBase] = []
var current_index: int = -1
var drill: DrillBase
var running: bool = false
var completed: bool = false
var failed: bool = false
var elapsed: float = 0.0
var result_text: String = ""
var editor_mode: bool = false
var headless_mode: bool = false

var _scored_team: int = 0
var _last_hit_id: int = -1
var _last_hit_strength: float = 0.0
var _jumped: bool = false
var _dodged: bool = false
var _ui_accum: float = 0.0
var _rules: MatchRules
var _ui: CanvasLayer
var _objective_label: Label
var _title_label: Label
var _timer_label: Label
var _progress_bar: ProgressBar
var _hint_label: Label
var _drill_list: VBoxContainer
var _pack_option: OptionButton
var _result_overlay: ColorRect
var _result_label: Label
var _result_detail: Label
var _next_button: Button
var _toast_label: Label
var _editor_panel: PanelContainer
var _editor_name: LineEdit
var _editor_speed: HSlider
var _editor_label: Label
var _editor_drills: Array[DrillBase] = []
var _editor_ball_pos := Vector3.ZERO
var _editor_ball_vel := Vector3.ZERO
var _editor_initialized: bool = false
var _pack_done: bool = false


func _ready() -> void:
	headless_mode = DisplayServer.get_name() == "headless"
	_build_world()
	_build_ui()
	Events.ball_hit.connect(_on_ball_hit)
	Events.goal_scored.connect(_on_goal_scored)
	if car != null:
		car.state_changed.connect(_on_car_state_changed)
	var requested := selected_pack_id
	var start_index := selected_drill_index
	selected_pack_id = "onboarding"
	selected_drill_index = 0
	start_pack(requested, start_index)


func _exit_tree() -> void:
	if Events.ball_hit.is_connected(_on_ball_hit):
		Events.ball_hit.disconnect(_on_ball_hit)
	if Events.goal_scored.is_connected(_on_goal_scored):
		Events.goal_scored.disconnect(_on_goal_scored)
	GravityManager.stop()


func _build_world() -> void:
	_rules = BASE_RULES.duplicate() as MatchRules
	_rules.team_size = 1
	_rules.free_play = true
	_rules.fill_with_bots = false
	_rules.replay_enabled = false
	_rules.boost_pads_enabled = true
	_rules.match_duration = 3600.0
	arena = ARENA_SCENE.instantiate() as Arena
	arena.build_pads = false
	arena.build_environment = true
	arena.configure(_rules)
	add_child(arena)
	var ball_tuning := BASE_BALL_TUNING.duplicate() as BallTuning
	ball = BALL_SCENE.instantiate() as Ball
	ball.tuning = ball_tuning
	add_child(ball)
	ball.reset_to_kickoff(arena.get_ball_spawn())
	car = CAR_SCENE.instantiate() as Car
	car.team = 1
	car.car_id = 0
	car.display_name = str(Meta.profile.get("name", "Pilot"))
	car.tuning = BASE_CAR_TUNING.duplicate() as CarTuning
	car.control_mode = Car.DriveMode.HUMAN
	car.set_local_player(true)
	car.auto_respawn = false
	car.demolition_enabled = false
	add_child(car)
	car.apply_cosmetics(Meta.profile.get("loadout", {}))
	car.reset_to_kickoff(arena.get_spawn_transform(1, 1))
	vfx = VFX_SERVICE.new() as VFXService
	vfx.name = "VFX"
	vfx.setup(self, arena)
	add_child(vfx)
	if not headless_mode:
		camera = CAMERA_SCENE.instantiate() as ChaseCamera
		add_child(camera)
		camera.setup(car, ball)


func start_pack(pack_id: String, start_index: int = 0) -> void:
	var found := DrillLibrary.pack_by_id(pack_id)
	if found.is_empty():
		found = DrillLibrary.pack_by_id("onboarding")
		start_index = 0
	if found.is_empty():
		return
	pack = found
	drills = (pack.get("drills", []) as Array[DrillBase]).duplicate()
	if drills.is_empty():
		return
	current_index = clampi(start_index, 0, drills.size() - 1)
	_pack_done = false
	selected_pack_id = str(pack.get("id", "onboarding"))
	_select_pack_option(selected_pack_id)
	_rebuild_drill_list()
	_start_drill(current_index)


func _start_drill(index: int) -> void:
	if index < 0 or index >= drills.size():
		return
	current_index = index
	drill = drills[index]
	drill.reset_runtime()
	_pack_done = false
	elapsed = 0.0
	running = true
	completed = false
	failed = false
	result_text = ""
	_scored_team = 0
	_last_hit_id = -1
	_last_hit_strength = 0.0
	_jumped = false
	_dodged = false
	if _result_overlay != null:
		_result_overlay.visible = false
	_configure_gravity()
	_reset_ball()
	_reset_car()
	for goal: Goal in arena.goals:
		goal.set_enabled(true)
		goal.reset_latch()
	drill.begin(car.global_position, GravityManager.phase_index, GravityManager.up)
	_update_objective()
	_refresh_drill_list()
	drill_changed.emit(index)


func _configure_gravity() -> void:
	var temp := _rules.duplicate() as MatchRules
	temp.gravity_interval = maxf(drill.gravity_interval, 0.5)
	temp.gravity_transition = 1.2
	temp.gravity_warning = minf(2.5, temp.gravity_interval * 0.4)
	var phases: Array[bool] = []
	for value: bool in drill.enable_phases:
		phases.append(value)
	temp.enabled_phases = phases
	GravityManager.configure(temp, 424242)
	if drill.gravity_dir.length_squared() > 0.01:
		GravityManager.force_direction(drill.gravity_dir.normalized())
	GravityManager.active = drill.gravity_active


func _reset_ball() -> void:
	ball.freeze = false
	ball.global_transform = Transform3D(Basis.IDENTITY, arena.get_ball_spawn() + GravityManager.up * ball.tuning.kickoff_height)
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.last_hitter_id = -1
	if drill.has_ball_spawn:
		ball.global_position = drill.ball_spawn
	ball.linear_velocity = drill.ball_velocity
	ball.freeze = drill.ball_frozen


func _reset_car() -> void:
	var pos: Vector3 = arena.get_spawn_transform(1, 1).origin
	if drill.has_car_spawn:
		pos = drill.car_spawn
	var up: Vector3 = GravityManager.up
	var forward: Vector3 = drill.car_forward if drill.car_forward.length_squared() > 0.01 else Vector3.FORWARD
	var tf := Transform3D(_basis_facing(forward, up), pos)
	car.frozen = false
	car.visible = true
	car.reset_to_kickoff(tf)
	car.control_mode = Car.DriveMode.HUMAN
	car.set_local_player(true)
	if car.boost_component != null:
		car.boost_component.enabled = true
		car.boost_component.reset()
	if camera != null:
		camera.setup(car, ball)
		camera.set_free_camera(false)
		camera.stop_replay()


func _basis_facing(forward: Vector3, up: Vector3) -> Basis:
	var y := up.normalized()
	var z := -forward.normalized()
	var x := y.cross(z).normalized()
	if x.length_squared() < 0.001:
		x = Vector3.RIGHT
	z = x.cross(y).normalized()
	return Basis(x, y, z)


func _physics_process(delta: float) -> void:
	if editor_mode or not running or drill == null or car == null:
		return
	elapsed += delta
	if Input.is_action_just_pressed("jump"):
		_jumped = true
	var ctx := _context(delta)
	if drill.evaluate(ctx):
		_finish(true)
		return
	if elapsed >= drill.time_limit:
		_finish(false)


func _process(delta: float) -> void:
	if _ui == null:
		return
	_ui_accum += delta
	if _ui_accum < 0.08:
		return
	_ui_accum = 0.0
	if running and drill != null:
		var time_left: float = maxf(drill.time_limit - elapsed, 0.0)
		_timer_label.text = "%0.1fs" % time_left
		_progress_bar.value = drill.progress(_context(0.0))
		if camera != null:
			_hint_label.text = _hint_for_state()


func _context(delta: float) -> Dictionary:
	return {
		"delta": delta,
		"elapsed": elapsed,
		"car_pos": car.global_position,
		"car_speed": car.get_speed(),
		"car_state": car.state,
		"grounded": car.is_grounded(),
		"wheels": car.wheels_on_ground,
		"up": GravityManager.up,
		"phase": GravityManager.phase_index,
		"gravity_dir": GravityManager.gravity_dir,
		"jumped": _jumped,
		"dodged": _dodged,
		"hit_car_id": _last_hit_id,
		"hit_strength": _last_hit_strength,
		"car_id": car.car_id,
		"scored_team": _scored_team,
		"ball_pos": ball.global_position,
	}


func _hint_for_state() -> String:
	if drill.success_kind == DrillBase.SuccessKind.WALL_DRIVE:
		return "Wall time: %0.1fs / %0.1fs" % [_wall_seconds(), drill.target_time]
	if drill.success_kind == DrillBase.SuccessKind.CEILING_TOUCH:
		return "Find the ceiling and land on it."
	return drill.hint


func _wall_seconds() -> float:
	return float(drill.get("_wall_time"))


func _finish(success: bool) -> void:
	if not running:
		return
	running = false
	completed = success
	failed = not success
	car.set_frozen(true)
	ball.freeze = true
	if success:
		result_text = "DRILL COMPLETE"
		Meta.record_training(str(pack.get("id", "")), drill.id, elapsed, true)
		if current_index == drills.size() - 1:
			Meta.mark_training_pack_completed(str(pack.get("id", "")))
		_show_result("DRILL COMPLETE", "%s   %0.1fs" % [drill.title, elapsed], true)
		drill_completed.emit(current_index)
	else:
		result_text = "TIME UP"
		Meta.record_training(str(pack.get("id", "")), drill.id, elapsed, false)
		_show_result("TIME UP", drill.hint, false)
	_refresh_drill_list()


func next_drill() -> void:
	if _pack_done:
		_pack_done = false
		start_pack(str(pack.get("id", "onboarding")), 0)
		return
	if current_index + 1 < drills.size():
		_start_drill(current_index + 1)
	else:
		_pack_done = true
		pack_finished.emit()
		_show_result("PACK COMPLETE", "Every drill in %s is cleared." % str(pack.get("name", "pack")), true)
		_result_detail.text = "Choose another pack from the left panel, or replay this pack."
		_next_button.text = "REPLAY"


func restart_drill() -> void:
	if current_index >= 0:
		_start_drill(current_index)


func _on_ball_hit(strength: float, _position: Vector3, hitter_id: int) -> void:
	if not running:
		return
	_last_hit_id = hitter_id
	_last_hit_strength = strength


func _on_goal_scored(team: int, _scorer_id: int) -> void:
	if running:
		_scored_team = team
	if ball != null:
		Events.goal_explosion.emit(team, ball.global_position)


func _on_car_state_changed(new_state: int) -> void:
	if new_state == Car.State.DODGING:
		_dodged = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not editor_mode:
		if running:
			restart_drill()
		else:
			return_to_menu()


# --- UI ----------------------------------------------------------------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "TrainingUI"
	_ui.layer = 10
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.offset_left = -330.0
	top.offset_right = 330.0
	top.offset_top = 18.0
	top.offset_bottom = 154.0
	top.add_theme_stylebox_override("panel", _style(Color(0.02, 0.04, 0.09, 0.86), Color(0.2, 0.85, 1.0, 0.5), 12))
	root.add_child(top)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 3)
	top.add_child(tv)
	_title_label = _label("", 24, Color(0.9, 0.97, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	tv.add_child(_title_label)
	_objective_label = _label("", 16, Color(0.35, 0.88, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	tv.add_child(_objective_label)
	_progress_bar = _progress(Color(0.06, 0.1, 0.18), Color(0.2, 0.9, 1.0), 560.0, 12.0)
	tv.add_child(_progress_bar)
	var bottom_row := HBoxContainer.new()
	bottom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_child(bottom_row)
	_timer_label = _label("", 15, Color(1.0, 0.82, 0.32))
	bottom_row.add_child(_timer_label)
	_hint_label = _label("", 14, Color(0.62, 0.75, 0.9))
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bottom_row.add_child(_hint_label)

	var left := PanelContainer.new()
	left.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	left.offset_left = 18.0
	left.offset_top = 18.0
	left.offset_right = 330.0
	left.offset_bottom = 610.0
	left.add_theme_stylebox_override("panel", _style(Color(0.02, 0.04, 0.09, 0.82), Color(0.15, 0.7, 1.0, 0.35), 12))
	root.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left.add_child(lv)
	lv.add_child(_label("TRAINING", 14, Color(0.35, 0.85, 1.0)))
	_pack_option = OptionButton.new()
	_pack_option.name = "PackOption"
	_pack_option.custom_minimum_size = Vector2(280.0, 36.0)
	_pack_option.item_selected.connect(func(index: int) -> void: _on_pack_selected(index))
	lv.add_child(_pack_option)
	_drill_list = VBoxContainer.new()
	_drill_list.add_theme_constant_override("separation", 2)
	lv.add_child(_drill_list)
	lv.add_child(_spacer(6))
	lv.add_child(_small_button("RESTART DRILL", restart_drill, 250.0))
	lv.add_child(_small_button("SKIP / NEXT", next_drill, 250.0))
	lv.add_child(_small_button("REPLAY BROWSER", _open_replays, 250.0))
	lv.add_child(_small_button("PACK EDITOR", _toggle_editor, 250.0))
	lv.add_child(_small_button("MAIN MENU", return_to_menu, 250.0))
	_toast_label = _label("", 13, Color(1.0, 0.8, 0.35))
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(_toast_label)

	_result_overlay = ColorRect.new()
	_result_overlay.color = Color(0.0, 0.01, 0.03, 0.68)
	_result_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_overlay.visible = false
	root.add_child(_result_overlay)
	var rp := PanelContainer.new()
	rp.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	rp.offset_left = -300.0
	rp.offset_right = 300.0
	rp.offset_top = -150.0
	rp.offset_bottom = 150.0
	rp.add_theme_stylebox_override("panel", _style(Color(0.03, 0.05, 0.1, 0.97), Color(0.2, 0.85, 1.0, 0.55), 16))
	_result_overlay.add_child(rp)
	var rv := VBoxContainer.new()
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	rv.add_theme_constant_override("separation", 12)
	rp.add_child(rv)
	_result_label = _label("", 36, Color(0.35, 1.0, 0.55), HORIZONTAL_ALIGNMENT_CENTER)
	rv.add_child(_result_label)
	_result_detail = _label("", 16, Color(0.7, 0.82, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	_result_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(_result_detail)
	var rb := HBoxContainer.new()
	rb.alignment = BoxContainer.ALIGNMENT_CENTER
	rb.add_theme_constant_override("separation", 12)
	rv.add_child(rb)
	rb.add_child(_small_button("RETRY", restart_drill, 140.0))
	_next_button = _small_button("NEXT", next_drill, 140.0)
	rb.add_child(_next_button)
	rb.add_child(_small_button("MENU", return_to_menu, 140.0))

	_build_editor(root)
	_populate_packs()


func _build_editor(root: Control) -> void:
	_editor_panel = PanelContainer.new()
	_editor_panel.name = "EditorPanel"
	_editor_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_editor_panel.offset_left = -390.0
	_editor_panel.offset_right = -18.0
	_editor_panel.offset_top = 18.0
	_editor_panel.offset_bottom = 420.0
	_editor_panel.add_theme_stylebox_override("panel", _style(Color(0.05, 0.03, 0.02, 0.9), Color(1.0, 0.7, 0.25, 0.6), 12))
	_editor_panel.visible = false
	root.add_child(_editor_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	_editor_panel.add_child(v)
	v.add_child(_label("PACK EDITOR", 15, Color(1.0, 0.78, 0.3)))
	v.add_child(_label("Aim the camera and place the ball, or type coordinates.", 12, Color(0.75, 0.8, 0.9)))
	v.add_child(_small_button("PLACE BALL AT AIM", _place_ball_at_aim, 320.0))
	var speed_row := HBoxContainer.new()
	speed_row.add_child(_label("Launch speed", 13, Color(0.8, 0.85, 0.95)))
	_editor_speed = HSlider.new()
	_editor_speed.min_value = 0.0
	_editor_speed.max_value = 40.0
	_editor_speed.step = 1.0
	_editor_speed.value = 12.0
	_editor_speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_row.add_child(_editor_speed)
	v.add_child(speed_row)
	_editor_name = LineEdit.new()
	_editor_name.placeholder_text = "Pack name"
	_editor_name.text = "My Pack"
	v.add_child(_editor_name)
	v.add_child(_small_button("ADD DRILL FROM BALL", _add_editor_drill_from_ball, 320.0))
	_editor_label = _label("0 editor drills", 12, Color(0.55, 0.8, 1.0))
	v.add_child(_editor_label)
	v.add_child(_small_button("SAVE PACK", _save_editor_pack, 320.0))
	v.add_child(_small_button("CLOSE EDITOR", _toggle_editor, 320.0))


func _populate_packs() -> void:
	if _pack_option == null:
		return
	_pack_option.clear()
	var packs := DrillLibrary.all_packs()
	for pack_entry: Dictionary in packs:
		var index: int = _pack_option.item_count
		_pack_option.add_item(str(pack_entry.get("name", "Pack")))
		_pack_option.set_item_metadata(index, str(pack_entry.get("id", "")))


func _select_pack_option(pack_id: String) -> void:
	if _pack_option == null:
		return
	for i in _pack_option.item_count:
		if str(_pack_option.get_item_metadata(i)) == pack_id:
			_pack_option.select(i)
			return


func _on_pack_selected(index: int) -> void:
	if _pack_option == null or index < 0:
		return
	var pack_id := str(_pack_option.get_item_metadata(index))
	if pack_id != "":
		if editor_mode:
			_toggle_editor()
		start_pack(pack_id)


func _rebuild_drill_list() -> void:
	if _drill_list == null:
		return
	for child in _drill_list.get_children():
		child.queue_free()
	for i in drills.size():
		var d: DrillBase = drills[i]
		var status := "  "
		if i < current_index or _is_drill_done(d):
			status = "\u2713 "
		elif i == current_index:
			status = "\u25B6 "
		var lbl := _label("%s%d. %s" % [status, i + 1, d.title], 14, Color(0.82, 0.9, 1.0))
		_drill_list.add_child(lbl)


func _is_drill_done(d: DrillBase) -> bool:
	return Meta.training_drill_completed(str(pack.get("id", "")), d.id)


func _refresh_drill_list() -> void:
	_rebuild_drill_list()


func _update_objective() -> void:
	if drill == null:
		return
	_title_label.text = drill.title
	_objective_label.text = drill.objective_text()
	_hint_label.text = drill.hint
	_timer_label.text = "%0.1fs" % drill.time_limit
	_progress_bar.value = 0.0
	if _result_overlay != null:
		_result_overlay.visible = false


func _show_result(title: String, detail: String, success: bool) -> void:
	_result_label.text = title
	_result_label.modulate = Color(0.35, 1.0, 0.55) if success else Color(1.0, 0.4, 0.3)
	_result_detail.text = detail
	_next_button.text = "NEXT" if current_index + 1 < drills.size() else "REPLAY"
	_result_overlay.visible = true


# --- Editor ------------------------------------------------------------------

func _toggle_editor() -> void:
	editor_mode = not editor_mode
	if _editor_panel != null:
		_editor_panel.visible = editor_mode
	if editor_mode:
		running = false
		car.set_frozen(true)
		ball.freeze = true
		if not _editor_initialized:
			_editor_ball_pos = ball.global_position
			_editor_ball_vel = Vector3.ZERO
			_editor_initialized = true
		_refresh_editor_label()
	else:
		restart_drill()
	editor_changed.emit(editor_mode)


func place_ball(position: Vector3, velocity: Vector3 = Vector3.ZERO) -> void:
	_editor_ball_pos = position
	_editor_ball_vel = velocity
	_editor_initialized = true
	ball.freeze = true
	ball.global_position = position
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	_refresh_editor_label()


func _place_ball_at_aim() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var center := viewport_size * 0.5
	var origin := cam.project_ray_origin(center)
	var dir := cam.project_ray_normal(center)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 180.0, ARENA_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var point: Vector3 = hit.get("position", origin + dir * 30.0)
	place_ball(point + (hit.get("normal", Vector3.UP) as Vector3) * 0.8, dir * _editor_speed.value)


func _add_editor_drill_from_ball() -> void:
	var d := DrillBase.new()
	d.id = "editor_%d" % (_editor_drills.size() + 1)
	d.title = "Editor drill %d" % (_editor_drills.size() + 1)
	d.description = "Ball placed in the pack editor."
	d.hint = "Hit the ball into the far goal."
	d.success_kind = DrillBase.SuccessKind.BALL_TOUCH
	d.ball_spawn = _editor_ball_pos
	d.ball_velocity = _editor_ball_vel
	d.has_ball_spawn = true
	d.car_spawn = arena.get_spawn_transform(1, 1).origin
	d.car_forward = Vector3.FORWARD
	d.has_car_spawn = true
	d.time_limit = 30.0
	_editor_drills.append(d)
	_refresh_editor_label()
	_toast("Added %s" % d.title)


func _save_editor_pack() -> void:
	if _editor_drills.is_empty():
		_toast("Add at least one drill first")
		return
	var name := _editor_name.text if _editor_name != null else "My Pack"
	var issues := DrillLibrary.validate_pack(_editor_drills)
	if not issues.is_empty():
		_toast(issues[0])
		return
	var path := DrillLibrary.save_user_pack(name, _editor_drills, "Created in the training pack editor.")
	if path == "":
		_toast("Could not save pack")
		return
	_toast("Saved %s" % path.get_file())
	_populate_packs()
	start_pack("user_%s" % DrillLibrary._safe_name(name))


func _refresh_editor_label() -> void:
	if _editor_label == null:
		return
	_editor_label.text = "Ball %s   speed %.0f   |   %d draft drill(s)" % [
		_format_vec(_editor_ball_pos), _editor_ball_vel.length(), _editor_drills.size(),
	]


func _format_vec(v: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [v.x, v.y, v.z]


func _toast(text: String) -> void:
	if _toast_label != null:
		_toast_label.text = text


func _open_replays() -> void:
	ReplayStorage.selected_path = ""
	get_tree().change_scene_to_file("res://replay/ReplayBrowser.tscn")


func return_to_menu() -> void:
	GravityManager.stop()
	get_tree().change_scene_to_file("res://ui/Main.tscn")


# --- UI helpers --------------------------------------------------------------

func _label(text: String, size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = color
	lbl.horizontal_alignment = align
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.82))
	lbl.add_theme_constant_override("outline_size", 4)
	return lbl


func _small_button(text: String, callback: Callable, width: float = 120.0) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(width, 34.0)
	btn.add_theme_font_size_override("font_size", 13)
	btn.pressed.connect(callback)
	return btn


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0.0, height)
	return c


func _style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb


func _progress(bg: Color, fill: Color, width: float, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(width, height)
	bar.max_value = 1.0
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = bg
	bg_style.set_corner_radius_all(4)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill
	fill_style.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg_style)
	bar.add_theme_stylebox_override("fill", fill_style)
	return bar
