extends Node
## Global audio service: UI one-shots, master limiting and music side-chain
## ducking. Match-specific synthesis lives in audio/MatchAudio.gd.

const LIBRARY := preload("res://audio/AudioLibrary.gd")
const UI_VOICES := 4

var _ui_players: Array[AudioStreamPlayer] = []
var _ui_cursor: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_master_limiter()
	_ensure_music_sidechain()
	_build_ui_players()
	# UI sounds are tiny and used immediately by the menu.
	LIBRARY.get_stream("ui_click")
	LIBRARY.get_stream("ui_hover")
	LIBRARY.get_stream("ui_back")


func play_ui(id: String = "ui_click", volume_db: float = -3.0) -> void:
	if _ui_players.is_empty():
		return
	var player := _ui_players[_ui_cursor % _ui_players.size()]
	_ui_cursor = (_ui_cursor + 1) % _ui_players.size()
	player.stream = LIBRARY.get_stream(id)
	player.volume_db = volume_db
	player.play()


func ui_voice_count() -> int:
	return _ui_players.size()


func _build_ui_players() -> void:
	for i in UI_VOICES:
		var player := AudioStreamPlayer.new()
		player.name = "UiVoice%d" % i
		player.bus = "SFX"
		player.max_polyphony = 1
		add_child(player)
		_ui_players.append(player)


func _ensure_master_limiter() -> void:
	var index := AudioServer.get_bus_index("Master")
	if index < 0 or _has_effect(index, "AudioEffectLimiter"):
		return
	var limiter := AudioEffectLimiter.new()
	limiter.ceiling_db = -0.4
	limiter.threshold_db = -3.0
	limiter.soft_clip_db = -1.5
	limiter.soft_clip_ratio = 1.4
	AudioServer.add_bus_effect(index, limiter)


func _ensure_music_sidechain() -> void:
	var index := AudioServer.get_bus_index("Music")
	if index < 0 or _has_effect(index, "AudioEffectCompressor"):
		return
	# The announcer and goal stingers live on the Announcer bus, so this makes
	# music duck automatically during celebrations without fighting the user's
	# saved Music volume.
	var compressor := AudioEffectCompressor.new()
	compressor.sidechain = &"Announcer"
	compressor.threshold = -22.0
	compressor.ratio = 4.5
	compressor.attack_us = 8000.0
	compressor.release_ms = 260.0
	compressor.gain = 0.0
	AudioServer.add_bus_effect(index, compressor)


func _has_effect(bus_index: int, type_name: String) -> bool:
	for i in AudioServer.get_bus_effect_count(bus_index):
		var effect := AudioServer.get_bus_effect(bus_index, i)
		if effect != null and effect.get_class() == type_name:
			return true
	return false
