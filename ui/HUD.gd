extends CanvasLayer
class_name HUD
## Signal-driven HUD (Task 07). Labels are only touched when their displayed
## value changes; the center prompt handles countdowns, goals and shifts.

var car: Car
var ball: Ball

var _score_label: Label
var _timer_label: Label
var _shift_label: Label
var _shift_bar: ProgressBar
var _boost_bar: ProgressBar
var _speed_label: Label
var _supersonic_label: Label
var _prompt_label: Label
var _feed_label: Label
var _debug_label: Label
var _controls_label: Label

var _prompt_timer: float = 0.0
var _feed_timer: float = 0.0
var _last_second: int = -999
var _last_speed: int = -999
var _last_boost: int = -999
var _base_font: int = 20


func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var ui_scale: float = float(Settings.get_setting("accessibility/ui_scale", 1.0))
	_base_font = int(round(20.0 * clampf(ui_scale, 0.75, 1.75)))

	_score_label = _make_label(root, "", _base_font + 12)
	_anchor_center(_score_label, 0.0, 18.0, 900.0, 46.0)

	_timer_label = _make_label(root, "5:00", _base_font + 8)
	_anchor_center(_timer_label, 0.0, 64.0, 300.0, 34.0)

	_shift_label = _make_label(root, "", _base_font)
	_anchor_center(_shift_label, 0.0, 98.0, 600.0, 28.0)

	_shift_bar = _make_bar(root, Color(0.35, 0.85, 1.0))
	_shift_bar.anchor_left = 0.5
	_shift_bar.anchor_right = 0.5
	_shift_bar.offset_left = -180.0
	_shift_bar.offset_right = 180.0
	_shift_bar.offset_top = 130.0
	_shift_bar.offset_bottom = 140.0
	_shift_bar.max_value = 30.0

	_boost_bar = _make_bar(root, Color(1.0, 0.55, 0.08))
	_boost_bar.anchor_left = 0.0
	_boost_bar.anchor_top = 1.0
	_boost_bar.anchor_bottom = 1.0
	_boost_bar.offset_left = 30.0
	_boost_bar.offset_right = 270.0
	_boost_bar.offset_top = -58.0
	_boost_bar.offset_bottom = -30.0
	_boost_bar.max_value = 100.0
	_boost_bar.value = 100.0

	var boost_caption := _make_label(root, "BOOST", _base_font)
	boost_caption.anchor_left = 0.0
	boost_caption.anchor_top = 1.0
	boost_caption.anchor_bottom = 1.0
	boost_caption.offset_left = 30.0
	boost_caption.offset_right = 200.0
	boost_caption.offset_top = -88.0
	boost_caption.offset_bottom = -60.0

	_speed_label = _make_label(root, "0 km/h", _base_font + 2)
	_speed_label.anchor_left = 1.0
	_speed_label.anchor_right = 1.0
	_speed_label.anchor_top = 1.0
	_speed_label.anchor_bottom = 1.0
	_speed_label.offset_left = -240.0
	_speed_label.offset_right = -30.0
	_speed_label.offset_top = -62.0
	_speed_label.offset_bottom = -30.0
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_supersonic_label = _make_label(root, "SUPERSONIC", _base_font)
	_supersonic_label.anchor_left = 1.0
	_supersonic_label.anchor_right = 1.0
	_supersonic_label.anchor_top = 1.0
	_supersonic_label.anchor_bottom = 1.0
	_supersonic_label.offset_left = -240.0
	_supersonic_label.offset_right = -30.0
	_supersonic_label.offset_top = -92.0
	_supersonic_label.offset_bottom = -64.0
	_supersonic_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_supersonic_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.15))
	_supersonic_label.visible = false

	_prompt_label = _make_label(root, "", _base_font + 32)
	_prompt_label.anchor_left = 0.5
	_prompt_label.anchor_right = 0.5
	_prompt_label.anchor_top = 0.5
	_prompt_label.anchor_bottom = 0.5
	_prompt_label.offset_left = -420.0
	_prompt_label.offset_right = 420.0
	_prompt_label.offset_top = -70.0
	_prompt_label.offset_bottom = 70.0
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_label.visible = false

	_feed_label = _make_label(root, "", _base_font - 2)
	_feed_label.anchor_left = 0.5
	_feed_label.anchor_right = 0.5
	_feed_label.anchor_top = 1.0
	_feed_label.anchor_bottom = 1.0
	_feed_label.offset_left = -420.0
	_feed_label.offset_right = 420.0
	_feed_label.offset_top = -100.0
	_feed_label.offset_bottom = -70.0
	_feed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_controls_label = _make_label(root, "WASD drive  SPACE jump  SHIFT boost  Q ball cam  G shift gravity", _base_font - 4)
	_controls_label.anchor_left = 0.0
	_controls_label.anchor_right = 0.0
	_controls_label.anchor_top = 1.0
	_controls_label.anchor_bottom = 1.0
	_controls_label.offset_left = 30.0
	_controls_label.offset_right = 720.0
	_controls_label.offset_top = -26.0
	_controls_label.offset_bottom = -4.0
	_controls_label.modulate = Color(1, 1, 1, 0.55)

	_debug_label = _make_label(root, "", _base_font - 2)
	_debug_label.position = Vector2(18, 14)
	_debug_label.visible = false

	Events.score_changed.connect(_on_score_changed)
	Events.timer_changed.connect(_on_timer_changed)
	Events.ui_prompt.connect(show_prompt)
	Events.event_feed.connect(show_feed)
	Events.car_demolished.connect(_on_car_demolished)


func bind(p_car: Car, p_ball: Ball) -> void:
	car = p_car
	ball = p_ball
	if car != null and car.boost != null:
		car.boost.changed.connect(_on_boost_changed)
		_on_boost_changed(car.boost.amount)
	if car != null:
		car.supersonic_changed.connect(_on_supersonic)


func _process(delta: float) -> void:
	if _prompt_timer > 0.0:
		_prompt_timer -= delta
		if _prompt_timer <= 0.0:
			_prompt_label.visible = false
	if _feed_timer > 0.0:
		_feed_timer -= delta
		if _feed_timer <= 0.0:
			_feed_label.text = ""

	if car != null:
		var kmh: int = int(round(car.speed * 3.6))
		if kmh != _last_speed:
			_last_speed = kmh
			_speed_label.text = "%d km/h" % kmh

	var shift_second: int = int(ceil(GravityManager.time_to_shift))
	if shift_second != _last_second:
		_last_second = shift_second
		if GravityManager.is_in_transition():
			_shift_label.text = "GRAVITY SHIFTING..."
		else:
			_shift_label.text = "Gravity shift in %ds" % shift_second
		_shift_bar.max_value = maxf(GravityManager.interval, 0.1)
		_shift_bar.value = maxf(GravityManager.time_to_shift, 0.0)

	if Input.is_action_just_pressed("debug_overlay"):
		_debug_label.visible = not _debug_label.visible
	if _debug_label.visible:
		_update_debug()


func _update_debug() -> void:
	var phase_name: String = "FLOOR"
	match GravityManager.phase_index:
		1:
			phase_name = "WALL A"
		2:
			phase_name = "CEILING"
		3:
			phase_name = "WALL B"
	_debug_label.text = "FPS %d\nGravity %s (phase %s)\nUp %s\nCar state %d  speed %.1f\nShift in %.1fs" % [
		Engine.get_frames_per_second(),
		Vector3(GravityManager.gravity_dir).snapped(Vector3.ONE * 0.01),
		phase_name,
		Vector3(GravityManager.up).snapped(Vector3.ONE * 0.01),
		car.state if car != null else -1,
		car.speed if car != null else 0.0,
		GravityManager.time_to_shift,
	]


func show_prompt(text: String, duration: float = 1.5) -> void:
	_prompt_label.text = text
	_prompt_label.visible = true
	_prompt_timer = duration


func show_feed(text: String) -> void:
	_feed_label.text = text
	_feed_timer = 2.5


func _on_score_changed(blue: int, orange: int) -> void:
	_score_label.text = "BLUE  %d      %d  ORANGE" % [blue, orange]


func _on_timer_changed(seconds_left: int) -> void:
	var minutes: int = int(seconds_left / 60.0)
	var seconds: int = seconds_left % 60
	_timer_label.text = "%d:%02d" % [minutes, seconds]


func _on_boost_changed(amount: float) -> void:
	var rounded: int = int(round(amount))
	if rounded == _last_boost:
		return
	_last_boost = rounded
	_boost_bar.value = amount


func _on_supersonic(value: bool) -> void:
	_supersonic_label.visible = value


func _on_car_demolished(_car: Node, _by: Node) -> void:
	show_feed("DEMOLITION!")


func _make_label(parent: Control, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", maxi(font_size, 10))
	label.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _make_bar(parent: Control, fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.05, 0.08, 0.8)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar


func _anchor_center(ctrl: Control, anchor_y: float, offset_y: float, width: float, height: float) -> void:
	ctrl.anchor_left = 0.5
	ctrl.anchor_right = 0.5
	ctrl.anchor_top = anchor_y
	ctrl.anchor_bottom = anchor_y
	ctrl.offset_left = -width * 0.5
	ctrl.offset_right = width * 0.5
	ctrl.offset_top = offset_y
	ctrl.offset_bottom = offset_y + height
	ctrl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
