class_name ReplayPlayer
extends Node3D
## Replay viewer. Plays compact snapshots for smooth scrubbing while keeping the
## input timeline for re-simulation and future physics-version tooling.

const ARENA_SCENE := preload("res://arena/Arena.tscn")
const CAR_SCENE := preload("res://car/Car.tscn")
const BALL_SCENE := preload("res://ball/Ball.tscn")
const CAMERA_SCENE := preload("res://camera/ChaseCamera.tscn")
const BASE_RULES := preload("res://match/MatchRules.tres")
const BASE_CAR_TUNING := preload("res://car/CarTuning.tres")
const BASE_BALL_TUNING := preload("res://ball/BallTuning.tres")

var data: ReplayData
var arena: Arena
var ball: Ball
var cars: Array[Car] = []
var camera: ChaseCamera
var playing: bool = true
var playback_time: float = 0.0
var duration: float = 0.0
var speed_scale: float = 1.0
var free_camera: bool = false
var current_tick: int = 0

var _ui: CanvasLayer
var _time_label: Label
var _slider: HSlider
var _play_button: Button
var _free_button: Button
var _info_label: Label
var _updating_slider: bool = false
var _current_phase: int = -1
var _last_applied_tick: int = -1


func _ready() -> void:
	var path := ReplayStorage.selected_path
	if path == "" or not FileAccess.file_exists(path):
		path = ReplayStorage.latest_path()
	data = ReplayStorage.load_path(path) if path != "" else null
	if data == null:
		_build_error_ui()
		return
	duration = maxf(data.duration, 0.1)
	_build_world()
	_build_ui()
	_apply_state(0)


func _exit_tree() -> void:
	GravityManager.stop()


func _build_error_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -260.0
	panel.offset_right = 260.0
	panel.offset_top = -110.0
	panel.offset_bottom = 110.0
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(v)
	v.add_child(_label("NO REPLAY FOUND", 28, Color(1.0, 0.7, 0.35), HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_label("Finish a match to create a replay, or pick one from the browser.", 14, Color(0.7, 0.8, 0.95), HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_button("REPLAY BROWSER", _open_browser))
	v.add_child(_button("MAIN MENU", _menu))


func _build_world() -> void:
	var rules := BASE_RULES.duplicate() as MatchRules
	rules.team_size = 1
	rules.free_play = true
	rules.fill_with_bots = false
	rules.replay_enabled = false
	rules.boost_pads_enabled = true
	rules.match_duration = 3600.0
	arena = ARENA_SCENE.instantiate() as Arena
	arena.build_pads = false
	arena.configure(rules)
	add_child(arena)
	var ball_tuning := BASE_BALL_TUNING.duplicate() as BallTuning
	ball = BALL_SCENE.instantiate() as Ball
	ball.tuning = ball_tuning
	add_child(ball)
	ball.set_network_ghost(true)
	var initial_cars: Array = data.initial.get("cars", [])
	for entry: Variant in initial_cars:
		if not (entry is Dictionary):
			continue
		var info: Dictionary = entry
		var car := CAR_SCENE.instantiate() as Car
		car.car_id = int(info.get("id", 0))
		car.team = int(info.get("team", 1))
		car.display_name = str(info.get("name", "Pilot"))
		car.tuning = BASE_CAR_TUNING.duplicate() as CarTuning
		car.control_mode = Car.DriveMode.NETWORK
		car.frozen = true
		car.auto_respawn = false
		car.demolition_enabled = false
		add_child(car)
		car.apply_cosmetics(info.get("loadout", {}))
		car.collision_layer = 0
		car.collision_mask = 0
		car.global_transform = Transform3D(Basis(_decode_quat(info.get("q", [0, 0, 0, 1]))), _decode_vec(info.get("p", [0, 0, 0])))
		if car.boost_component != null:
			car.boost_component.set_amount(float(info.get("b", 0.0)))
		cars.append(car)
	var initial_ball: Variant = data.initial.get("ball", [])
	if initial_ball is Array:
		ball.set_snapshot_state(ReplayData.decode_ball(initial_ball))
	current_tick = 0
	_current_phase = int(data.initial.get("phase", 0))
	GravityManager.reset_to_phase(_current_phase)
	GravityManager.active = false
	if not cars.is_empty():
		camera = CAMERA_SCENE.instantiate() as ChaseCamera
		add_child(camera)
		camera.setup(cars[0], ball)
		camera.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 7.0, 26.0))
		camera.set_free_camera(true)
		camera.free_camera = false
		free_camera = false


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "ReplayUI"
	_ui.layer = 10
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.offset_left = -340.0
	top.offset_right = 340.0
	top.offset_top = 16.0
	top.offset_bottom = 108.0
	top.add_theme_stylebox_override("panel", _style(Color(0.02, 0.04, 0.09, 0.85), Color(0.2, 0.85, 1.0, 0.45), 12))
	root.add_child(top)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 2)
	top.add_child(tv)
	tv.add_child(_label("REPLAY  %s" % data.mode.to_upper(), 24, Color(0.9, 0.97, 1.0), HORIZONTAL_ALIGNMENT_CENTER))
	_info_label = _label("", 13, Color(0.55, 0.78, 0.92), HORIZONTAL_ALIGNMENT_CENTER)
	tv.add_child(_info_label)

	var bottom := PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 90.0
	bottom.offset_right = -90.0
	bottom.offset_top = -142.0
	bottom.offset_bottom = -18.0
	bottom.add_theme_stylebox_override("panel", _style(Color(0.02, 0.04, 0.09, 0.88), Color(0.2, 0.85, 1.0, 0.42), 12))
	root.add_child(bottom)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 6)
	bottom.add_child(bv)
	var time_row := HBoxContainer.new()
	bv.add_child(time_row)
	_time_label = _label("0:00 / 0:00", 15, Color(0.85, 0.92, 1.0))
	time_row.add_child(_time_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_row.add_child(spacer)
	time_row.add_child(_label("Drag to scrub", 12, Color(0.5, 0.68, 0.85)))
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = maxf(duration, 0.1)
	_slider.step = 0.01
	_slider.value_changed.connect(_on_seek)
	bv.add_child(_slider)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	bv.add_child(buttons)
	buttons.add_child(_small_button("-5s", func() -> void: seek(playback_time - 5.0), 70.0))
	_play_button = _small_button("PAUSE", _toggle_play, 100.0)
	buttons.add_child(_play_button)
	buttons.add_child(_small_button("+5s", func() -> void: seek(playback_time + 5.0), 70.0))
	buttons.add_child(_small_button("SPEED x0.5", func() -> void: _cycle_speed(), 115.0))
	_free_button = _small_button("FREE CAM", _toggle_free_camera, 115.0)
	buttons.add_child(_free_button)
	buttons.add_child(_small_button("BROWSER", _open_browser, 110.0))
	buttons.add_child(_small_button("MENU", _menu, 80.0))
	_update_info()


func _update_info() -> void:
	if _info_label == null or data == null:
		return
	_info_label.text = "%s   %d inputs   %d snapshots   %s" % [
		data.physics_version,
		data.inputs.size(),
		data.snapshots.size(),
		"inputs + snapshots" if not data.inputs.is_empty() else "snapshots only",
	]


func _process(delta: float) -> void:
	if data == null:
		return
	if playing:
		playback_time = minf(playback_time + delta * speed_scale, duration)
		if playback_time >= duration:
			playing = false
			_play_button.text = "PLAY"
	var tick := int(playback_time * data.tick_rate)
	if tick != _last_applied_tick:
		_last_applied_tick = tick
		_apply_state(tick)
	_update_time_ui()


func _apply_state(tick: int) -> void:
	current_tick = tick
	var before := data.snapshot_before(tick)
	var after := data.snapshot_after(tick)
	if before.is_empty() and after.is_empty():
		return
	if before.is_empty():
		before = after
	if after.is_empty():
		after = before
	var t0 := int(before.get("t", 0))
	var t1 := int(after.get("t", t0))
	var alpha: float = clampf(float(tick - t0) / float(maxi(t1 - t0, 1)), 0.0, 1.0)
	var rows_a: Array = before.get("c", [])
	var rows_b: Array = after.get("c", [])
	for row: Variant in rows_a:
		var a: Dictionary = ReplayData.decode_car(row as Array)
		if a.is_empty():
			continue
		var b: Dictionary = a
		for other: Variant in rows_b:
			var candidate: Dictionary = ReplayData.decode_car(other as Array)
			if int(candidate.get("id", -1)) == int(a.get("id", -2)):
				b = candidate
				break
		var car := _find_car(int(a.get("id", -1)))
		if car == null:
			continue
		var p: Vector3 = (a.get("p", Vector3.ZERO) as Vector3).lerp(b.get("p", a.get("p", Vector3.ZERO)), alpha)
		var q: Quaternion = (a.get("q", Quaternion.IDENTITY) as Quaternion).slerp(b.get("q", a.get("q", Quaternion.IDENTITY)), alpha)
		var v: Vector3 = (a.get("v", Vector3.ZERO) as Vector3).lerp(b.get("v", a.get("v", Vector3.ZERO)), alpha)
		car.global_transform = Transform3D(Basis(q).orthonormalized(), p)
		car.linear_velocity = v
		car.visible = int(a.get("s", 0)) != Car.State.DEMOLISHED
		if car.boost_component != null:
			car.boost_component.set_amount(lerpf(float(a.get("b", 0.0)), float(b.get("b", a.get("b", 0.0))), alpha))
	var ball_a: Array = before.get("b", [])
	if not ball_a.is_empty():
		var ball_b: Array = after.get("b", ball_a)
		var da := ReplayData.decode_ball(ball_a)
		var db := ReplayData.decode_ball(ball_b)
		ball.set_snapshot_state({
			"p": (da.get("p", Vector3.ZERO) as Vector3).lerp(db.get("p", da.get("p", Vector3.ZERO)), alpha),
			"q": (da.get("q", Quaternion.IDENTITY) as Quaternion).slerp(db.get("q", da.get("q", Quaternion.IDENTITY)), alpha),
			"v": (da.get("v", Vector3.ZERO) as Vector3).lerp(db.get("v", da.get("v", Vector3.ZERO)), alpha),
			"w": (da.get("w", Vector3.ZERO) as Vector3).lerp(db.get("w", da.get("w", Vector3.ZERO)), alpha),
		})
	var phase: int = int(before.get("g", _current_phase))
	if phase != _current_phase:
		_current_phase = phase
		GravityManager.reset_to_phase(phase)


func _find_car(car_id: int) -> Car:
	for car: Car in cars:
		if car.car_id == car_id:
			return car
	return null


func _on_seek(value: float) -> void:
	if _updating_slider:
		return
	seek(value)


func seek(value: float) -> void:
	playback_time = clampf(value, 0.0, duration)
	_last_applied_tick = -1
	_apply_state(int(playback_time * data.tick_rate))
	_update_time_ui()


func _toggle_play() -> void:
	playing = not playing
	_play_button.text = "PAUSE" if playing else "PLAY"


func _toggle_free_camera() -> void:
	free_camera = not free_camera
	if camera != null:
		camera.set_free_camera(free_camera)
	if _free_button != null:
		_free_button.text = "CHASE CAM" if free_camera else "FREE CAM"


func _cycle_speed() -> void:
	speed_scale = [0.5, 1.0, 1.5, 2.0][( [0.5, 1.0, 1.5, 2.0].find(speed_scale) + 1) % 4]
	if _free_button != null:
		pass


func _update_time_ui() -> void:
	if _slider == null:
		return
	_updating_slider = true
	_slider.max_value = maxf(duration, 0.1)
	_slider.value = playback_time
	_updating_slider = false
	_time_label.text = "%s / %s" % [_fmt(playback_time), _fmt(duration)]


func _fmt(seconds: float) -> String:
	var t: int = maxi(0, int(seconds))
	return "%d:%02d" % [t / 60, t % 60]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_play()
	elif event.is_action_pressed("steer_left"):
		seek(playback_time - 5.0)
	elif event.is_action_pressed("steer_right"):
		seek(playback_time + 5.0)
	elif event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_F:
		_toggle_free_camera()


func _open_browser() -> void:
	ReplayStorage.selected_path = ""
	get_tree().change_scene_to_file("res://replay/ReplayBrowser.tscn")


func _menu() -> void:
	get_tree().change_scene_to_file("res://ui/Main.tscn")


func _decode_vec(value: Variant) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3.ZERO


func _decode_quat(value: Variant) -> Quaternion:
	if value is Array and (value as Array).size() >= 4:
		return Quaternion(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	return Quaternion.IDENTITY


# --- UI helpers --------------------------------------------------------------

func _label(text: String, size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = color
	lbl.horizontal_alignment = align
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	lbl.add_theme_constant_override("outline_size", 4)
	return lbl


func _button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(300.0, 42.0)
	btn.pressed.connect(callback)
	return btn


func _small_button(text: String, callback: Callable, width: float) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(width, 34.0)
	btn.add_theme_font_size_override("font_size", 13)
	btn.pressed.connect(callback)
	return btn


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
