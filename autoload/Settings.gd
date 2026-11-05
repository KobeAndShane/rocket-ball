extends Node
## Persisted user settings (user://settings.cfg) and the runtime InputMap.
## Actions are registered here so the project runs even before the editor
## InputMap is populated, and remaps are saved through the same file.

const SAVE_PATH := "user://settings.cfg"
const SECTION := "settings"

const ACTION_BINDINGS: Dictionary = {
	"throttle": KEY_W,
	"brake": KEY_S,
	"steer_left": KEY_A,
	"steer_right": KEY_D,
	"jump": KEY_SPACE,
	"boost": KEY_SHIFT,
	"handbrake": KEY_CTRL,
	"air_roll": KEY_E,
	"pitch_up": KEY_UP,
	"pitch_down": KEY_DOWN,
	"yaw_left": KEY_LEFT,
	"yaw_right": KEY_RIGHT,
	"ball_cam": KEY_Q,
	"look_behind": KEY_R,
	"reset_car": KEY_R,
	"debug_gravity": KEY_G,
	"debug_overlay": KEY_F3,
	"pause": KEY_ESCAPE,
}

const DEFAULTS: Dictionary = {
	"video/window_mode": 0,
	"video/vsync": true,
	"video/fps_cap": 120,
	"video/msaa_3d": 2,
	"accessibility/reduced_motion": false,
	"accessibility/screen_shake": 1.0,
	"accessibility/flash_intensity": 1.0,
	"accessibility/ui_scale": 1.0,
	"accessibility/high_contrast": false,
	"audio/master": 1.0,
	"audio/music": 0.8,
	"audio/sfx": 1.0,
	"audio/voice": 1.0,
	"audio/announcer": 0.8,
	"camera/fov": 80.0,
	"camera/distance": 9.0,
	"camera/height": 3.6,
	"camera/stiffness": 6.0,
	"camera/ball_cam": false,
}

var _config := ConfigFile.new()
var _values: Dictionary = {}


func _ready() -> void:
	load_settings()
	_register_actions()
	apply_all()


func load_settings() -> void:
	_values = DEFAULTS.duplicate(true)
	if _config.load(SAVE_PATH) == OK:
		for key: Variant in _values.keys():
			var section: String = SECTION
			if _config.has_section_key(section, String(key)):
				_values[key] = _config.get_value(section, String(key))


func save_settings() -> void:
	for key: Variant in _values.keys():
		_config.set_value(SECTION, String(key), _values[key])
	_config.save(SAVE_PATH)


func get_setting(key: String, fallback: Variant = null) -> Variant:
	if _values.has(key):
		return _values[key]
	if fallback == null:
		return DEFAULTS.get(key)
	return fallback


func set_setting(key: String, value: Variant) -> void:
	_values[key] = value


func reset_to_defaults() -> void:
	_values = DEFAULTS.duplicate(true)
	_register_actions()
	apply_all()
	save_settings()


func apply_all() -> void:
	apply_video()
	apply_audio()
	apply_controls()


func apply_video() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode: int = int(get_setting("video/window_mode"))
	match mode:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	var vsync: bool = bool(get_setting("video/vsync"))
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)
	# Renderer settings are project-wide; expose them for the options menu.
	var msaa: int = int(get_setting("video/msaa_3d"))
	if RenderingServer.get_video_adapter_name() != "":
		get_viewport().msaa_3d = msaa as Viewport.MSAA


func apply_audio() -> void:
	for bus_name: String in ["Master", "Music", "SFX", "Voice", "Announcer"]:
		var index := AudioServer.get_bus_index(bus_name)
		if index < 0:
			continue
		var key := "audio/" + bus_name.to_lower()
		if not _values.has(key):
			key = "audio/master" if bus_name == "Master" else "audio/" + bus_name.to_lower()
		var linear: float = float(get_setting(key, 1.0))
		AudioServer.set_bus_volume_db(index, linear_to_db(clampf(linear, 0.0001, 1.0)))
		AudioServer.set_bus_mute(index, linear <= 0.001)


func apply_controls() -> void:
	for action: String in ACTION_BINDINGS.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		InputMap.action_erase_events(action)
		var saved: int = int(get_setting("controls/" + action, ACTION_BINDINGS[action]))
		if saved != 0:
			var ev := InputEventKey.new()
			ev.physical_keycode = saved as Key
			InputMap.action_add_event(action, ev)


func _register_actions() -> void:
	for action: String in ACTION_BINDINGS.keys():
		if not _values.has("controls/" + action):
			_values["controls/" + action] = ACTION_BINDINGS[action]


func get_binding(action: String) -> Key:
	return int(get_setting("controls/" + action, ACTION_BINDINGS.get(action, 0))) as Key


func set_binding(action: String, key: Key) -> void:
	set_setting("controls/" + action, key)
	apply_controls()
	save_settings()
