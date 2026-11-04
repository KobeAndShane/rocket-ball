class_name Accessibility
extends Node
## Global accessibility service. Owns the single full-screen colourblind pass,
## centralises team colours and flash scaling, and filters chat text.

const COLORBLIND_SHADER := preload("res://vfx/colorblind.gdshader")
const MODE_NAMES := ["Off", "Deuteranopia", "Protanopia", "Tritanopia"]
const BLOCKED_WORDS := [
	"fuck", "shit", "bitch", "asshole", "cunt", "nigger", "faggot", "retard",
]

var overlay: CanvasLayer
var overlay_rect: ColorRect
var overlay_material: ShaderMaterial


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_overlay()
	Events.settings_changed.connect(_on_settings_changed)
	apply()


func _build_overlay() -> void:
	overlay = CanvasLayer.new()
	overlay.name = "AccessibilityOverlay"
	overlay.layer = 90
	add_child(overlay)
	overlay_rect = ColorRect.new()
	overlay_rect.name = "ColorblindPass"
	overlay_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_material = ShaderMaterial.new()
	overlay_material.shader = COLORBLIND_SHADER
	overlay_rect.material = overlay_material
	overlay_rect.visible = false
	overlay.add_child(overlay_rect)


func _on_settings_changed(key: String, _value: Variant) -> void:
	if key.begins_with("a11y/") or key == "*":
		apply()


func apply() -> void:
	var mode: int = clampi(Settings.get_int("a11y/colorblind_mode"), 0, 3)
	if overlay_material != null:
		overlay_material.set_shader_parameter("mode", mode)
	if overlay_rect != null:
		overlay_rect.visible = mode != 0


func colorblind_mode() -> int:
	return clampi(Settings.get_int("a11y/colorblind_mode"), 0, 3)


func colorblind_mode_name() -> String:
	return MODE_NAMES[colorblind_mode()]


func flash_scale() -> float:
	return clampf(Settings.get_float("a11y/flash_intensity"), 0.0, 1.5)


func team_color(team: int) -> Color:
	if team == 1:
		return Settings.get_color("a11y/team1_color") if Settings.get_bool("a11y/team_color_override") else Color(0.18, 0.64, 1.0)
	if team == 2:
		return Settings.get_color("a11y/team2_color") if Settings.get_bool("a11y/team_color_override") else Color(1.0, 0.42, 0.16)
	return Color(0.75, 0.75, 0.8)


func team_colors() -> Array[Color]:
	return [team_color(1), team_color(2)]


func chat_muted() -> bool:
	return Settings.get_bool("a11y/chat_mute")


func filter_chat(text: String) -> String:
	if not Settings.get_bool("a11y/chat_filter") or text == "":
		return text
	var out := text
	for word: String in BLOCKED_WORDS:
		out = _mask_word(out, word)
	return out


func _mask_word(text: String, word: String) -> String:
	var out := text
	var lower := out.to_lower()
	var index := lower.find(word)
	while index >= 0:
		out = out.substr(0, index) + "*".repeat(word.length()) + out.substr(index + word.length())
		lower = out.to_lower()
		index = lower.find(word, index + word.length())
	return out
