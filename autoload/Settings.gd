extends Node
## Persistent user settings, display/audio application and input remapping.
## Values are intentionally keyed strings so menus, tests and config files share one shape.

const CONFIG_PATH := "user://settings.cfg"
const CONFIG_VERSION := 1

const BUSES := ["Master", "Music", "SFX", "Voice", "Announcer"]

var _values: Dictionary = {}
var _input_overrides: Dictionary = {}


func _ready() -> void:
	_ensure_buses()
	_build_defaults()
	_load()
	_ensure_input_actions()
	_apply_input_overrides()
	apply_all()
	# Re-apply viewport-bound settings once the main loop has a viewport.
	call_deferred("apply_all")


func _build_defaults() -> void:
	_values = {
		# Video
		"video/window_mode": 0,
		"video/resolution": Vector2i(1600, 900),
		"video/vsync": 1,
		"video/fps_cap": 0,
		"video/quality": 2, # 0 low, 1 medium, 2 high, 3 ultra
		"video/msaa": 1,
		"video/render_scale": 1.0,
		"video/upscaler": 0, # 0 off, 1 FSR
		"video/taa": false,
		# Audio (linear 0..1)
		"audio/master": 0.9,
		"audio/music": 0.7,
		"audio/sfx": 0.9,
		"audio/voice": 0.8,
		"audio/announcer": 0.8,
		# Controls
		"controls/deadzone": 0.18,
		"controls/steer_sensitivity": 1.0,
		"controls/camera_sensitivity": 1.0,
		"controls/invert_pitch": false,
		"controls/vibration": true,
		# Camera
		"camera/fov": 100.0,
		"camera/distance": 7.2,
		"camera/height": 2.4,
		"camera/angle": -12.0,
		"camera/stiffness": 8.0,
		"camera/swivel_speed": 3.0,
		"camera/ball_cam": true,
		"camera/ball_cam_blend": 0.55,
		# Accessibility
		"a11y/reduced_motion": false,
		"a11y/fixed_horizon": false,
		"a11y/screen_shake": 1.0,
		"a11y/flash_intensity": 1.0,
		"a11y/ui_scale": 1.0,
		"a11y/text_scale": 1.0,
		"a11y/high_contrast": false,
		"a11y/colorblind_mode": 0, # 0 off, 1 deuteranopia, 2 protanopia, 3 tritanopia
		"a11y/team_color_override": false,
		"a11y/team1_color": Color(0.2, 0.75, 1.0),
		"a11y/team2_color": Color(1.0, 0.35, 0.25),
		"a11y/subtitles": true,
		"a11y/subtitle_size": 22.0,
		"a11y/chat_filter": true,
		# Gameplay / match defaults
		"game/team_size": 3,
		"game/bot_difficulty": 1,
		"game/mode": "standard",
		# Network
		"net/region": "auto",
		"net/player_name": "Pilot",
		"net/test_latency": 0,
		"net/test_loss": 0.0,
	}
	for i in BUSES.size():
		_values["audio/%s" % BUSES[i].to_lower()] = _values.get("audio/%s" % BUSES[i].to_lower(), 0.9)
	_values["audio/master"] = 0.9
	_values["audio/music"] = 0.7
	_values["audio/sfx"] = 0.9
	_values["audio/voice"] = 0.8
	_values["audio/announcer"] = 0.8


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	var version: int = int(cfg.get_value("meta", "version", 0))
	if version < 1:
		_migrate_v0(cfg)
	for key: String in _values.keys():
		var section: String = key.get_slice("/", 0)
		var entry: String = key.get_slice("/", 1)
		if cfg.has_section_key(section, entry):
			var v: Variant = cfg.get_value(section, entry)
			if typeof(v) == typeof(_values[key]) or (v is Vector2i and _values[key] is Vector2i):
				_values[key] = v
	_input_overrides = cfg.get_value("input", "bindings", {})
	if not (_input_overrides is Dictionary):
		_input_overrides = {}


func _migrate_v0(_cfg: ConfigFile) -> void:
	# Future migrations go here. v0 had no version key.
	pass


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", CONFIG_VERSION)
	for key: String in _values.keys():
		cfg.set_value(key.get_slice("/", 0), key.get_slice("/", 1), _values[key])
	cfg.set_value("input", "bindings", _input_overrides)
	cfg.save(CONFIG_PATH)


func get_setting(key: String) -> Variant:
	return _values.get(key)


func get_float(key: String) -> float:
	return float(_values.get(key, 0.0))


func get_int(key: String) -> int:
	return int(_values.get(key, 0))


func get_bool(key: String) -> bool:
	return bool(_values.get(key, false))


func get_color(key: String) -> Color:
	var v: Variant = _values.get(key, Color.WHITE)
	return v if v is Color else Color.WHITE


func set_setting(key: String, value: Variant, save_now: bool = true) -> void:
	if not _values.has(key):
		return
	_values[key] = value
	_apply_one(key, value)
	Events.settings_changed.emit(key, value)
	if save_now:
		save()


func reset_to_defaults() -> void:
	_build_defaults()
	_input_overrides.clear()
	_ensure_input_actions()
	apply_all()
	save()
	Events.settings_changed.emit("*", null)


func reset_category(prefix: String) -> void:
	var defaults: Dictionary = {}
	var saved := _values.duplicate()
	_build_defaults()
	for key: String in _values.keys():
		if key.begins_with(prefix + "/"):
			saved[key] = _values[key]
	_values = saved
	apply_all()
	save()


func apply_all() -> void:
	for key: String in _values.keys():
		_apply_one(key, _values[key])


func _apply_one(key: String, value: Variant) -> void:
	match key:
		"video/window_mode":
			var mode: int = int(value)
			match mode:
				1:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
				2:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
				_:
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		"video/resolution":
			if int(_values.get("video/window_mode", 0)) == 0 and value is Vector2i:
				DisplayServer.window_set_size(value)
		"video/vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(int(value)) else DisplayServer.VSYNC_DISABLED)
		"video/fps_cap":
			Engine.max_fps = int(value)
		"video/msaa":
			var vp := get_viewport()
			if vp != null:
				vp.msaa_3d = int(value)
		"video/render_scale":
			var vp := get_viewport()
			if vp != null:
				vp.scaling_3d_scale = clampf(float(value), 0.5, 2.0)
		"video/upscaler":
			var vp := get_viewport()
			if vp != null:
				vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if int(value) == 1 else Viewport.SCALING_3D_MODE_BILINEAR
		"video/taa":
			var vp := get_viewport()
			if vp != null:
				vp.use_taa = bool(value)
		"audio/master", "audio/music", "audio/sfx", "audio/voice", "audio/announcer":
			var bus_name: String = key.get_slice("/", 1).capitalize()
			_set_bus_volume(bus_name, float(value))
		"a11y/ui_scale", "a11y/text_scale":
			pass # HUD reads these live.


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0001, 1.0)))


func _ensure_buses() -> void:
	for bus_name: String in BUSES:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


# --- Input -------------------------------------------------------------------

const DEFAULT_ACTIONS := {
	"throttle": ["key:87", "key:4194320", "joy_axis:1:-1.0"],
	"brake": ["key:83", "key:4194322", "joy_axis:1:1.0"],
	"steer_left": ["key:65", "key:4194319", "joy_axis:0:-1.0"],
	"steer_right": ["key:68", "key:4194321", "joy_axis:0:1.0"],
	"jump": ["key:32", "joy_button:0"],
	"boost": ["key:4194325", "joy_button:1", "mouse:1"],
	"handbrake": ["key:88", "joy_button:2"],
	"air_roll": ["key:81", "joy_button:3"],
	"ball_cam": ["key:67", "joy_button:9"],
	"look_behind": ["key:66", "joy_button:8"],
	"reset_car": ["key:82"],
	"pause": ["key:4194305", "joy_button:6"],
	"scoreboard": ["key:4194308", "joy_button:4"],
	"toggle_debug": ["key:4194334"],
	"toggle_fullscreen": ["key:4194342"],
}


func _ensure_input_actions() -> void:
	for action: String in DEFAULT_ACTIONS.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.12)
		var existing: Array[InputEvent] = InputMap.action_get_events(action)
		if existing.is_empty():
			for spec: String in DEFAULT_ACTIONS[action]:
				var ev := _spec_to_event(spec)
				if ev != null:
					InputMap.action_add_event(action, ev)


func _spec_to_event(spec: String) -> InputEvent:
	var parts := spec.split(":")
	if parts.is_empty():
		return null
	match parts[0]:
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(parts[1]) as Key
			return k
		"joy_axis":
			var m := InputEventJoypadMotion.new()
			m.axis = int(parts[1]) as JoyAxis
			m.axis_value = float(parts[2])
			return m
		"joy_button":
			var b := InputEventJoypadButton.new()
			b.button_index = int(parts[1]) as JoyButton
			return b
		"mouse":
			var mb := InputEventMouseButton.new()
			mb.button_index = int(parts[1]) as MouseButton
			return mb
	return null


func _event_to_dict(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		return {"t": "key", "code": int(k.physical_keycode), "ctrl": k.ctrl_pressed, "alt": k.alt_pressed, "shift": k.shift_pressed}
	if ev is InputEventJoypadMotion:
		var m := ev as InputEventJoypadMotion
		return {"t": "joy_axis", "axis": int(m.axis), "value": m.axis_value}
	if ev is InputEventJoypadButton:
		var b := ev as InputEventJoypadButton
		return {"t": "joy_button", "button": int(b.button_index)}
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		return {"t": "mouse", "button": int(mb.button_index)}
	return {}


func _dict_to_event(d: Dictionary) -> InputEvent:
	match str(d.get("t", "")):
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(d.get("code", 0)) as Key
			k.ctrl_pressed = bool(d.get("ctrl", false))
			k.alt_pressed = bool(d.get("alt", false))
			k.shift_pressed = bool(d.get("shift", false))
			return k
		"joy_axis":
			var m := InputEventJoypadMotion.new()
			m.axis = int(d.get("axis", 0)) as JoyAxis
			m.axis_value = float(d.get("value", 0.0))
			return m
		"joy_button":
			var b := InputEventJoypadButton.new()
			b.button_index = int(d.get("button", 0)) as JoyButton
			return b
		"mouse":
			var mb := InputEventMouseButton.new()
			mb.button_index = int(d.get("button", 0)) as MouseButton
			return mb
	return null


func _apply_input_overrides() -> void:
	for action: String in _input_overrides.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.12)
		var arr: Variant = _input_overrides[action]
		if not (arr is Array):
			continue
		InputMap.action_erase_events(action)
		for entry: Variant in arr:
			if entry is Dictionary:
				var ev := _dict_to_event(entry)
				if ev != null:
					InputMap.action_add_event(action, ev)


## Replace one binding slot for an action. Returns false for an invalid event.
func rebind_action(action: String, slot: int, event: InputEvent) -> bool:
	if not InputMap.has_action(action) or event == null:
		return false
	var d := _event_to_dict(event)
	if d.is_empty():
		return false
	var specs: Array = []
	for ev: InputEvent in InputMap.action_get_events(action):
		specs.append(_event_to_dict(ev))
	if slot < 0 or slot >= specs.size():
		specs.append(d)
	else:
		specs[slot] = d
	_input_overrides[action] = specs
	InputMap.action_erase_events(action)
	for entry: Variant in specs:
		if entry is Dictionary:
			var ev := _dict_to_event(entry)
			if ev != null:
				InputMap.action_add_event(action, ev)
	save()
	Events.bindings_changed.emit()
	return true


func reset_bindings() -> void:
	_input_overrides.clear()
	for action: String in DEFAULT_ACTIONS.keys():
		InputMap.action_erase_events(action)
		for spec: String in DEFAULT_ACTIONS[action]:
			var ev := _spec_to_event(spec)
			if ev != null:
				InputMap.action_add_event(action, ev)
	save()
	Events.bindings_changed.emit()


func get_action_slots(action: String) -> Array:
	var out: Array = []
	if not InputMap.has_action(action):
		return out
	for ev: InputEvent in InputMap.action_get_events(action):
		out.append(_event_to_dict(ev))
	return out


## Deadzone-corrected stick value for an action pair (left/right or up/down).
func axis_from_actions(negative: String, positive: String) -> float:
	var raw := Input.get_action_strength(positive) - Input.get_action_strength(negative)
	var dz := get_float("controls/deadzone")
	if absf(raw) < dz:
		return 0.0
	return signf(raw) * inverse_lerp(dz, 1.0, absf(raw))
