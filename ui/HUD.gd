class_name GameHUD
extends CanvasLayer
## Signal-driven HUD. A 10 Hz timer handles continuously-changing readouts;
## everything discrete updates from the Events bus.

const BASE_SIZE := Vector2(1600.0, 900.0)
const FEED_POOL := 6

var match_ref: MatchController
var root: Control
var score_label: Label
var team1_label: Label
var team2_label: Label
var timer_label: Label
var gravity_label: Label
var shift_label: Label
var next_label: Label
var shift_bar: ProgressBar
var boost_bar: ProgressBar
var boost_label: Label
var speed_label: Label
var super_label: Label
var center_label: Label
var feed_box: VBoxContainer
var pause_overlay: ColorRect
var postgame_overlay: ColorRect
var postgame_score: Label
var postgame_mvp: Label
var stats_grid: GridContainer
var indicators: HudIndicators

var _feed_labels: Array[Label] = []
var _feed_tweens: Array[Tween] = []
var _feed_index: int = 0
var _center_tween: Tween
var _font_bases: Dictionary = {}
var _warning_active: bool = false
var _warning_second: int = -1
var _ui_scale: float = 1.0
var _text_scale: float = 1.0
var _last_timer_text: String = ""
var _last_gravity_text: String = ""
var _last_shift_text: String = ""
var _last_speed_text: String = ""
var _last_boost_text: String = ""
var _tick_timer: Timer


func _ready() -> void:
	layer = 10
	_build()
	_connect_events()
	_apply_scales()
	get_viewport().size_changed.connect(_apply_scales)
	_tick_timer = Timer.new()
	_tick_timer.wait_time = 0.1
	_tick_timer.autostart = true
	_tick_timer.timeout.connect(_tick)
	add_child(_tick_timer)


func setup(match_controller: MatchController) -> void:
	match_ref = match_controller
	if indicators != null:
		indicators.camera = match_ref.camera
		indicators.ball = match_ref.ball
		indicators.local_car = match_ref.local_car
		indicators.teammates.clear()
		for car: Car in match_ref.cars:
			if match_ref.local_car != null and car.team == match_ref.local_car.team and car != match_ref.local_car:
				indicators.teammates.append(car)
	_on_score_changed(match_ref.score1, match_ref.score2)
	_tick()


func _build() -> void:
	root = Control.new()
	root.name = "HUDRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_score()
	_build_gravity()
	_build_boost()
	_build_feed()
	_build_center()
	_build_indicators()
	_build_pause()
	_build_postgame()


func _build_score() -> void:
	var panel := _panel(Control.PRESET_CENTER_TOP, -250.0, 14.0, 250.0, 92.0, Color(0.02, 0.04, 0.09, 0.82), Color(0.2, 0.85, 1.0, 0.55))
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 22)
	vbox.add_child(hbox)
	team1_label = _label("BLUE", 22, Color(0.25, 0.72, 1.0))
	hbox.add_child(team1_label)
	score_label = _label("0 - 0", 38, Color.WHITE)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(score_label)
	team2_label = _label("ORANGE", 22, Color(1.0, 0.5, 0.2))
	hbox.add_child(team2_label)
	timer_label = _label("05:00", 26, Color(0.88, 0.92, 1.0))
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(timer_label)


func _build_gravity() -> void:
	var panel := _panel(Control.PRESET_TOP_LEFT, 20.0, 16.0, 410.0, 152.0, Color(0.02, 0.04, 0.09, 0.72), Color(0.2, 0.85, 1.0, 0.35))
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	gravity_label = _label("GRAVITY: FLOOR", 20, Color(0.75, 0.95, 1.0))
	vbox.add_child(gravity_label)
	shift_label = _label("SHIFT IN 30s", 15, Color(0.75, 0.8, 0.9))
	vbox.add_child(shift_label)
	shift_bar = _progress(Color(0.06, 0.1, 0.18), Color(0.15, 0.8, 1.0), 350.0, 9.0)
	shift_bar.max_value = 1.0
	shift_bar.value = 1.0
	vbox.add_child(shift_bar)
	next_label = _label("NEXT: WALL A", 14, Color(1.0, 0.72, 0.3))
	vbox.add_child(next_label)


func _build_boost() -> void:
	var panel := _panel(Control.PRESET_BOTTOM_RIGHT, -390.0, -178.0, -20.0, -18.0, Color(0.02, 0.04, 0.09, 0.78), Color(0.2, 0.85, 1.0, 0.4))
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	panel.add_child(vbox)
	var hbox := HBoxContainer.new()
	vbox.add_child(hbox)
	var title := _label("BOOST", 18, Color(0.7, 0.9, 1.0))
	hbox.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)
	boost_label = _label("100", 22, Color(0.3, 0.95, 1.0))
	hbox.add_child(boost_label)
	boost_bar = _progress(Color(0.05, 0.09, 0.15), Color(0.15, 0.9, 1.0), 340.0, 22.0)
	boost_bar.max_value = 100.0
	boost_bar.value = 100.0
	vbox.add_child(boost_bar)
	var hbox2 := HBoxContainer.new()
	vbox.add_child(hbox2)
	speed_label = _label("0 km/h", 17, Color(0.8, 0.85, 0.95))
	hbox2.add_child(speed_label)
	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox2.add_child(spacer2)
	super_label = _label("SUPERSONIC", 17, Color(0.2, 1.0, 1.0))
	super_label.modulate.a = 0.0
	hbox2.add_child(super_label)


func _build_feed() -> void:
	feed_box = VBoxContainer.new()
	feed_box.name = "EventFeed"
	feed_box.anchor_left = 1.0
	feed_box.anchor_right = 1.0
	feed_box.offset_left = -500.0
	feed_box.offset_right = -22.0
	feed_box.offset_top = 112.0
	feed_box.offset_bottom = 390.0
	feed_box.alignment = BoxContainer.ALIGNMENT_END
	feed_box.add_theme_constant_override("separation", 3)
	feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(feed_box)
	for i in FEED_POOL:
		var lbl := _label("", 17, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		lbl.modulate.a = 0.0
		feed_box.add_child(lbl)
		_feed_labels.append(lbl)
		_feed_tweens.append(null)


func _build_center() -> void:
	center_label = _label("", 76, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_label.offset_top = -90.0
	center_label.modulate.a = 0.0
	center_label.outline_size = 14
	root.add_child(center_label)


func _build_indicators() -> void:
	indicators = HudIndicators.new()
	indicators.name = "Indicators"
	root.add_child(indicators)


func _build_pause() -> void:
	pause_overlay = ColorRect.new()
	pause_overlay.color = Color(0.0, 0.01, 0.03, 0.68)
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.visible = false
	root.add_child(pause_overlay)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -210.0
	panel.offset_right = 210.0
	panel.offset_top = -190.0
	panel.offset_bottom = 190.0
	panel.add_theme_stylebox_override("panel", _style(Color(0.03, 0.05, 0.1, 0.96), Color(0.2, 0.85, 1.0, 0.55), 18))
	pause_overlay.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)
	var title := _label("PAUSED", 40, Color(0.9, 0.97, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(title)
	vbox.add_child(_button("Resume", _resume))
	vbox.add_child(_button("Restart Match", _restart))
	vbox.add_child(_button("Main Menu", _menu))


func _build_postgame() -> void:
	postgame_overlay = ColorRect.new()
	postgame_overlay.color = Color(0.0, 0.01, 0.03, 0.82)
	postgame_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	postgame_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	postgame_overlay.visible = false
	root.add_child(postgame_overlay)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -430.0
	panel.offset_right = 430.0
	panel.offset_top = -310.0
	panel.offset_bottom = 310.0
	panel.add_theme_stylebox_override("panel", _style(Color(0.03, 0.05, 0.1, 0.97), Color(0.2, 0.85, 1.0, 0.55), 18))
	postgame_overlay.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	var title := _label("MATCH COMPLETE", 38, Color(0.9, 0.97, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(title)
	postgame_score = _label("0 - 0", 52, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(postgame_score)
	postgame_mvp = _label("", 20, Color(1.0, 0.85, 0.3), HORIZONTAL_ALIGNMENT_CENTER)
	vbox.add_child(postgame_mvp)
	stats_grid = GridContainer.new()
	stats_grid.columns = 7
	stats_grid.add_theme_constant_override("h_separation", 22)
	stats_grid.add_theme_constant_override("v_separation", 2)
	vbox.add_child(stats_grid)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(hbox)
	hbox.add_child(_button("Rematch", _restart))
	hbox.add_child(_button("Main Menu", _menu))


func _connect_events() -> void:
	Events.score_changed.connect(_on_score_changed)
	Events.timer_changed.connect(_on_timer_changed)
	Events.countdown_changed.connect(_on_countdown)
	Events.boost_changed.connect(_on_boost_changed)
	Events.gravity_shift_warning.connect(_on_shift_warning)
	Events.gravity_shift_started.connect(_on_shift_started)
	Events.gravity_shift_finished.connect(_on_shift_finished)
	Events.match_state_changed.connect(_on_match_state)
	Events.match_ended.connect(_on_match_ended)
	Events.stats_updated.connect(_on_stats_updated)
	Events.event_feed.connect(_on_event_feed)
	Events.notification.connect(_on_notification)
	Events.request_pause.connect(_on_pause_requested)
	Events.overtime_started.connect(_on_overtime)
	Events.settings_changed.connect(_on_settings_changed)


# --- Events ------------------------------------------------------------------

func _on_score_changed(team1: int, team2: int) -> void:
	if score_label != null:
		score_label.text = "%d - %d" % [team1, team2]


func _on_timer_changed(_seconds: float) -> void:
	# The 10 Hz tick refreshes from MatchController for an accurate clock.
	pass


func _on_countdown(value: int) -> void:
	if value > 0:
		_flash_center(str(value), Color.WHITE, 0.9)
	else:
		_flash_center("GO!", Color(0.3, 1.0, 0.55), 0.8)


func _on_boost_changed(car_id: int, amount: float) -> void:
	if match_ref == null or match_ref.local_car == null or car_id != match_ref.local_car.car_id:
		return
	if boost_bar != null:
		boost_bar.value = amount
	if boost_label != null:
		boost_label.text = "%d" % int(round(amount))


func _on_shift_warning(seconds_left: float, next_dir: Vector3) -> void:
	_warning_active = true
	_warning_second = int(ceil(seconds_left))
	next_label.text = "NEXT: %s" % _dir_name(next_dir)
	_flash_center("GRAVITY SHIFT IN %d" % _warning_second, Color(1.0, 0.78, 0.25), 1.2)


func _on_shift_started(_from: Vector3, _to: Vector3, _duration: float) -> void:
	_warning_active = false
	_flash_center("GRAVITY SHIFT", Color(0.2, 0.95, 1.0), 1.4)
	Events.screen_shake.emit(0.35, 0.8)


func _on_shift_finished(_phase: int) -> void:
	_warning_active = false
	_update_gravity()


func _on_match_state(state: int, _previous: int) -> void:
	if state == MatchController.State.GOAL_PAUSE:
		_flash_center("GOAL!", Color(1.0, 0.85, 0.25), 1.4)
	elif state == MatchController.State.OVERTIME:
		_flash_center("OVERTIME", Color(1.0, 0.6, 0.2), 1.2)


func _on_match_ended(team1: int, team2: int, winner: int) -> void:
	if postgame_overlay == null:
		return
	postgame_overlay.visible = true
	postgame_score.text = "%d - %d" % [team1, team2]
	var result := "DRAW"
	if winner == 1:
		result = "BLUE WINS"
	elif winner == 2:
		result = "ORANGE WINS"
	postgame_mvp.text = result


func _on_stats_updated(stats: Dictionary) -> void:
	if stats.has("players"):
		_fill_postgame(stats)


func _on_event_feed(text: String, color: Color) -> void:
	if _feed_labels.is_empty():
		return
	var idx := _feed_index
	_feed_index = (_feed_index + 1) % _feed_labels.size()
	var label := _feed_labels[idx]
	if _feed_tweens[idx] != null and (_feed_tweens[idx] as Tween).is_valid():
		(_feed_tweens[idx] as Tween).kill()
	label.text = text
	label.modulate = color
	label.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(4.2)
	tw.tween_property(label, "modulate:a", 0.0, 0.8)
	_feed_tweens[idx] = tw


func _on_notification(text: String) -> void:
	if text == "GOAL!":
		return
	_flash_center(text, Color(0.9, 0.95, 1.0), 1.0)


func _on_pause_requested(paused: bool) -> void:
	if pause_overlay != null:
		pause_overlay.visible = paused


func _on_overtime() -> void:
	_flash_center("OVERTIME", Color(1.0, 0.6, 0.2), 1.2)


func _on_settings_changed(key: String, _value: Variant) -> void:
	if key.begins_with("a11y/") or key == "*":
		_apply_scales()


# --- Tick --------------------------------------------------------------------

func _tick() -> void:
	if match_ref == null:
		return
	var time_text := match_ref.display_time()
	if time_text != _last_timer_text:
		_last_timer_text = time_text
		timer_label.text = time_text
	_update_gravity()
	if match_ref.local_car != null:
		var car := match_ref.local_car
		if car.boost_component != null:
			var amount := car.boost_component.amount
			boost_bar.value = amount
			var txt := "%d" % int(round(amount))
			if txt != _last_boost_text:
				_last_boost_text = txt
				boost_label.text = txt
			var fill := Color(0.15, 0.9, 1.0)
			if amount < 25.0:
				fill = Color(1.0, 0.35, 0.2)
			_set_bar_fill(boost_bar, fill)
		var speed_text := "%d km/h" % int(round(car.speed * 3.6))
		if speed_text != _last_speed_text:
			_last_speed_text = speed_text
			speed_label.text = speed_text
		super_label.modulate.a = 1.0 if car.is_supersonic else 0.0
		if indicators != null:
			indicators.visible = not postgame_overlay.visible
	if _warning_active:
		var sec := int(ceil(GravityManager.time_until_shift()))
		if sec != _warning_second and sec > 0:
			_warning_second = sec
			center_label.text = "GRAVITY SHIFT IN %d" % sec
			center_label.modulate = Color(1.0, 0.78, 0.25)


func _update_gravity() -> void:
	if gravity_label == null:
		return
	var gname := "SHIFTING" if GravityManager.transitioning else _dir_name(GravityManager.gravity_dir)
	var gtext := "GRAVITY: %s" % gname
	if gtext != _last_gravity_text:
		_last_gravity_text = gtext
		gravity_label.text = gtext
	var stext := ""
	if GravityManager.transitioning:
		stext = "BLENDING"
	elif GravityManager.is_warning():
		stext = "SHIFT IN %.0fs" % GravityManager.time_until_shift()
	else:
		stext = "SHIFT IN %ds" % int(ceil(GravityManager.time_until_shift()))
	if stext != _last_shift_text:
		_last_shift_text = stext
		shift_label.text = stext
	var interval: float = maxf(GravityManager.shift_interval, 0.01)
	shift_bar.value = clampf(GravityManager.time_until_shift() / interval, 0.0, 1.0)
	next_label.text = "NEXT: %s" % _dir_name(GravityManager.next_direction())


func _dir_name(dir: Vector3) -> String:
	if dir.y < -0.5:
		return "FLOOR"
	if dir.y > 0.5:
		return "CEILING"
	if dir.x < -0.5:
		return "WALL A"
	if dir.x > 0.5:
		return "WALL B"
	return "UNKNOWN"


func _fill_postgame(stats: Dictionary) -> void:
	for child in stats_grid.get_children():
		child.queue_free()
	var headers := ["PLAYER", "GOALS", "ASSISTS", "SAVES", "SHOTS", "DEMOS", "PTS"]
	for h: String in headers:
		stats_grid.add_child(_label(h, 14, Color(0.55, 0.8, 1.0)))
	var players: Array = stats.get("players", [])
	players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("points", 0)) > int(b.get("points", 0))
	)
	var mvp_id: int = int(stats.get("mvp_id", -1))
	for p: Dictionary in players:
		var is_mvp: bool = int(p.get("car_id", -1)) == mvp_id
		var prefix := "* " if is_mvp else ""
		var name_color := Color(0.35, 0.78, 1.0) if int(p.get("team", 1)) == 1 else Color(1.0, 0.55, 0.25)
		stats_grid.add_child(_label(prefix + str(p.get("name", "")), 15, name_color))
		stats_grid.add_child(_label(str(p.get("goals", 0)), 15, Color.WHITE))
		stats_grid.add_child(_label(str(p.get("assists", 0)), 15, Color.WHITE))
		stats_grid.add_child(_label(str(p.get("saves", 0)), 15, Color.WHITE))
		stats_grid.add_child(_label(str(p.get("shots", 0)), 15, Color.WHITE))
		stats_grid.add_child(_label(str(p.get("demolitions", 0)), 15, Color.WHITE))
		stats_grid.add_child(_label(str(p.get("points", 0)), 15, Color(1.0, 0.85, 0.3)))
	if mvp_id >= 0:
		for p: Dictionary in players:
			if int(p.get("car_id", -1)) == mvp_id:
				postgame_mvp.text = "MVP: %s" % str(p.get("name", ""))
				break


# --- Actions -----------------------------------------------------------------

func _resume() -> void:
	if match_ref != null and match_ref.paused:
		match_ref.toggle_pause()


func _restart() -> void:
	pause_overlay.visible = false
	postgame_overlay.visible = false
	if match_ref != null:
		match_ref.rematch()


func _menu() -> void:
	if match_ref != null:
		match_ref.return_to_menu()


func _flash_center(text: String, color: Color, duration: float) -> void:
	if center_label == null:
		return
	if _center_tween != null and _center_tween.is_valid():
		_center_tween.kill()
	center_label.text = text
	center_label.modulate = color
	center_label.modulate.a = 1.0
	center_label.scale = Vector2.ONE
	_center_tween = create_tween()
	_center_tween.tween_interval(duration)
	_center_tween.tween_property(center_label, "modulate:a", 0.0, 0.45)


# --- Helpers -----------------------------------------------------------------

func _apply_scales() -> void:
	_ui_scale = Settings.get_float("a11y/ui_scale")
	_text_scale = Settings.get_float("a11y/text_scale")
	if is_instance_valid(root):
		var size := get_viewport().get_visible_rect().size
		var offset := Vector2(size.x * 0.5 * (1.0 - _ui_scale), size.y * 0.5 * (1.0 - _ui_scale))
		transform = Transform2D(0.0, Vector2(_ui_scale, _ui_scale), 0.0, offset)
	_refresh_fonts()


func _refresh_fonts() -> void:
	for key: Variant in _font_bases.keys():
		var label := key as Label
		if is_instance_valid(label):
			label.add_theme_font_size_override("font_size", int(round(float(_font_bases[key]) * _text_scale)))


func _label(text: String, size: int, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = color
	lbl.horizontal_alignment = align
	lbl.add_theme_font_size_override("font_size", int(round(size * _text_scale)))
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	lbl.add_theme_constant_override("outline_size", 5)
	_font_bases[lbl] = size
	return lbl


func _button(text: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(280.0, 48.0)
	btn.add_theme_font_size_override("font_size", 20)
	btn.pressed.connect(callback)
	return btn


func _panel(preset: int, left: float, top: float, right: float, bottom: float, bg: Color, border: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(preset)
	panel.offset_left = left
	panel.offset_top = top
	panel.offset_right = right
	panel.offset_bottom = bottom
	panel.add_theme_stylebox_override("panel", _style(bg, border, 12))
	root.add_child(panel)
	return panel


func _style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb


func _progress(bg: Color, fill: Color, width: float, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(width, height)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = bg
	bg_style.set_corner_radius_all(4)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill
	fill_style.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg_style)
	bar.add_theme_stylebox_override("fill", fill_style)
	bar.set_meta("fill_style", fill_style)
	return bar


func _set_bar_fill(bar: ProgressBar, color: Color) -> void:
	var style: Variant = bar.get_meta("fill_style", null)
	if style is StyleBoxFlat:
		(style as StyleBoxFlat).bg_color = color
