extends Control
## Standalone replay browser. Lists saved matches, lets the player load one into
## the replay viewer or delete it, and links back to training and the main menu.

const REPLAY_SCENE := "res://replay/Replay.tscn"
const TRAINING_SCENE := "res://training/Training.tscn"
const MAIN_SCENE := "res://ui/Main.tscn"

var _rows: VBoxContainer
var _status: Label
var _count_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	refresh()


func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists("res://vfx/menu_background.gdshader"):
		var mat := ShaderMaterial.new()
		mat.shader = load("res://vfx/menu_background.gdshader")
		bg.material = mat
	else:
		bg.color = Color(0.015, 0.025, 0.055)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 54)
	margin.add_theme_constant_override("margin_right", 54)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	add_child(margin)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color(0.02, 0.035, 0.075, 0.9), Color(0.15, 0.7, 1.0, 0.35), 16))
	margin.add_child(panel)
	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left", 30)
	inner.add_theme_constant_override("margin_right", 30)
	inner.add_theme_constant_override("margin_top", 24)
	inner.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(inner)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	inner.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	root.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	titles.add_child(_label("REPLAYS", 34, Color(0.9, 0.97, 1.0)))
	_count_label = _label("", 13, Color(0.35, 0.82, 1.0))
	titles.add_child(_count_label)
	header.add_child(_small_button("TRAINING", _open_training, 120.0))
	header.add_child(_small_button("MAIN MENU", _open_menu, 120.0))

	root.add_child(_label("Replays store the initial state, the input timeline and compact snapshots every half second. Scrub, slow down and fly the camera in the viewer.", 14, Color(0.62, 0.74, 0.9)))
	_status = _label("", 13, Color(1.0, 0.8, 0.35))
	root.add_child(_status)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 10)
	root.add_child(toolbar)
	toolbar.add_child(_small_button("WATCH LATEST", _play_latest, 150.0))
	toolbar.add_child(_small_button("REFRESH", refresh, 110.0))
	toolbar.add_child(_small_button("OPEN REPLAY FOLDER", _open_folder, 175.0))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 8)
	scroll.add_child(_rows)


func refresh() -> void:
	if _rows == null:
		return
	for child: Node in _rows.get_children():
		child.queue_free()
	var entries := ReplayStorage.list()
	_count_label.text = "%d saved replay%s   -   capped at %d files" % [
		entries.size(), "" if entries.size() == 1 else "s", ReplayStorage.MAX_FILES,
	]
	if entries.is_empty():
		var empty := _label("No replays yet. Finish a match and it will appear here automatically.", 15, Color(0.55, 0.68, 0.82))
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_rows.add_child(empty)
		return
	for entry: Dictionary in entries:
		_rows.add_child(_row(entry))


func _row(entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color(0.035, 0.06, 0.11, 0.88), Color(0.12, 0.5, 0.8, 0.3), 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 1)
	row.add_child(text)
	var mode := str(entry.get("mode", "Standard"))
	var created := float(entry.get("created", 0.0))
	var duration := float(entry.get("duration", 0.0))
	var file := str(entry.get("file", ""))
	text.add_child(_label("%s   -   %s" % [mode.to_upper(), _fmt_date(created)], 16, Color(0.88, 0.95, 1.0)))
	text.add_child(_label("%s   score %d-%d   %d inputs   %d snapshots   %.1f KB   %s" % [
		_fmt_time(duration),
		int(entry.get("score1", 0)),
		int(entry.get("score2", 0)),
		int(entry.get("inputs", 0)),
		int(entry.get("snapshots", 0)),
		float(entry.get("size", 0)) / 1024.0,
		file,
	], 12, Color(0.55, 0.7, 0.86)))

	var path := str(entry.get("path", ""))
	row.add_child(_small_button("PLAY", func() -> void: _play(path), 90.0))
	var delete_button := _small_button("DELETE", func() -> void: _delete(path), 90.0)
	delete_button.modulate = Color(1.0, 0.72, 0.68)
	row.add_child(delete_button)
	return panel


func _play(path: String) -> void:
	if path == "" or not FileAccess.file_exists(path):
		_status.text = "That replay is no longer on disk."
		refresh()
		return
	ReplayStorage.selected_path = path
	get_tree().change_scene_to_file(REPLAY_SCENE)


func _play_latest() -> void:
	var path := ReplayStorage.latest_path()
	if path == "":
		_status.text = "No replay to watch yet."
		return
	_play(path)


func _delete(path: String) -> void:
	if ReplayStorage.delete_path(path):
		_status.text = "Deleted %s" % path.get_file()
	else:
		_status.text = "Could not delete that replay."
	refresh()


func _open_training() -> void:
	get_tree().change_scene_to_file(TRAINING_SCENE)


func _open_menu() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE)


func _open_folder() -> void:
	OS.shell_open(ProjectSettings.globalize_path(ReplayStorage.DIR))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_open_menu()


func _fmt_time(seconds: float) -> String:
	var total: int = maxi(0, int(seconds))
	return "%d:%02d" % [total / 60, total % 60]


func _fmt_date(unix_seconds: float) -> String:
	if unix_seconds <= 0.0:
		return "unknown date"
	var dt := Time.get_datetime_dict_from_unix_time(int(unix_seconds))
	return "%04d-%02d-%02d %02d:%02d" % [
		int(dt.get("year", 0)), int(dt.get("month", 0)), int(dt.get("day", 0)),
		int(dt.get("hour", 0)), int(dt.get("minute", 0)),
	]


func _label(text: String, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = color
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	lbl.add_theme_constant_override("outline_size", 4)
	return lbl


func _small_button(text: String, callback: Callable, width: float = 120.0) -> Button:
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
