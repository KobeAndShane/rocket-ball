class_name MatchAudio
extends Node3D
## Match mix: spatial engine loops, tiered ball impacts, gravity-shift cues,
## crowd/announcer reactions and adaptive music.
##
## Everything is pooled or looping. No stream is created during play: the
## procedural streams come from AudioLibrary's cache and the announcer WAVs are
## imported resources. Music is three looping players crossfaded on the Music
## bus, which keeps transitions sample-synced and avoids playhead restarts.

const LIBRARY := preload("res://audio/AudioLibrary.gd")

const HIT_VOICES := 8
const ANNOUNCER_VOICES := 3

const MUSIC_STATES: Array[String] = ["calm", "tense", "overtime"]
const MUSIC_ACTIVE_DB := -4.0
const MUSIC_SILENT_DB := -60.0
const MUSIC_FADE_DB_PER_SECOND := 18.0

const HIT_LIGHT_THRESHOLD := 8.0
const HIT_HEAVY_THRESHOLD := 22.0

const STATE_PLAYING := 2
const STATE_GOAL_PAUSE := 3
const STATE_REPLAY := 4
const STATE_OVERTIME := 5

var context: Node

var _engine_players: Dictionary = {}
var _hit_players: Array[AudioStreamPlayer3D] = []
var _hit_cursor: int = 0
var _announcer_players: Array[AudioStreamPlayer] = []
var _announcer_cursor: int = 0
var _music_players: Dictionary = {}
var _crowd_loop: AudioStreamPlayer
var _crowd_cheer: AudioStreamPlayer
var _warning_player: AudioStreamPlayer
var _whoosh_player: AudioStreamPlayer

var _shift_warning_playing: bool = false
var _shift_whoosh_playing: bool = false
var _last_hit_tier: String = ""
var _last_announcer: String = ""
var _last_music_state: String = "calm"
var _praise_cooldown: float = 0.0
var _events_connected: bool = false


func setup(match_context: Node = null) -> void:
	context = match_context
	refresh_engine()
	_snap_music()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_pools()
	_connect_events()
	# Warm the large loops so the first kickoff never synthesises audio in a frame.
	LIBRARY.get_stream("engine_loop")
	LIBRARY.get_stream("crowd_loop")


func _exit_tree() -> void:
	_disconnect_events()


func _process(delta: float) -> void:
	_praise_cooldown = maxf(_praise_cooldown - delta, 0.0)
	refresh_engine()
	_update_music(delta)


# --- construction ------------------------------------------------------------

func _build_pools() -> void:
	var engine_stream := LIBRARY.get_stream("engine_loop")
	for i in HIT_VOICES:
		var hit := AudioStreamPlayer3D.new()
		hit.name = "BallHit%d" % i
		hit.bus = "SFX"
		hit.max_polyphony = 1
		hit.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		hit.unit_size = 9.0
		hit.max_distance = 90.0
		hit.max_db = 3.0
		hit.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		hit.volume_db = -80.0
		add_child(hit)
		_hit_players.append(hit)
	# One hidden source is cloned per car on demand; this keeps the scene file
	# small while still giving every engine a looping 3D voice.
	set_meta("engine_stream", engine_stream)

	for i in ANNOUNCER_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.name = "Announcer%d" % i
		voice.bus = "Announcer"
		voice.max_polyphony = 1
		voice.volume_db = -80.0
		add_child(voice)
		_announcer_players.append(voice)

	for state: String in MUSIC_STATES:
		var music := AudioStreamPlayer.new()
		music.name = "Music_%s" % state
		music.bus = "Music"
		music.stream = LIBRARY.get_stream("music_%s" % state)
		music.max_polyphony = 1
		music.volume_db = MUSIC_ACTIVE_DB if state == "calm" else MUSIC_SILENT_DB
		add_child(music)
		music.play()
		_music_players[state] = music

	_crowd_loop = AudioStreamPlayer.new()
	_crowd_loop.name = "CrowdLoop"
	_crowd_loop.bus = "SFX"
	_crowd_loop.stream = LIBRARY.get_stream("crowd_loop")
	_crowd_loop.max_polyphony = 1
	_crowd_loop.volume_db = -22.0
	add_child(_crowd_loop)
	_crowd_loop.play()

	_crowd_cheer = AudioStreamPlayer.new()
	_crowd_cheer.name = "CrowdCheer"
	_crowd_cheer.bus = "SFX"
	_crowd_cheer.stream = LIBRARY.get_stream("crowd_cheer")
	_crowd_cheer.max_polyphony = 1
	_crowd_cheer.volume_db = -6.0
	add_child(_crowd_cheer)

	_warning_player = _make_one_shot("ShiftWarning", "Voice", "shift_warning")
	_whoosh_player = _make_one_shot("ShiftWhoosh", "Voice", "shift_whoosh")


func _make_one_shot(node_name: String, bus_name: String, stream_id: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.bus = bus_name
	player.stream = LIBRARY.get_stream(stream_id)
	player.max_polyphony = 1
	player.volume_db = -6.0
	add_child(player)
	return player


func _make_engine_player() -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = "Engine%d" % _engine_players.size()
	player.bus = "SFX"
	player.stream = get_meta("engine_stream") as AudioStream
	player.max_polyphony = 1
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.unit_size = 11.0
	player.max_distance = 80.0
	player.max_db = 2.0
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	player.volume_db = -26.0
	add_child(player)
	player.play()
	return player


# --- events ------------------------------------------------------------------

func _connect_events() -> void:
	if _events_connected:
		return
	_events_connected = true
	Events.ball_hit.connect(_on_ball_hit)
	Events.goal_scored.connect(_on_goal_scored)
	Events.car_demolished.connect(_on_car_demolished)
	Events.overtime_started.connect(_on_overtime_started)
	Events.gravity_shift_warning.connect(_on_shift_warning)
	Events.gravity_shift_started.connect(_on_shift_started)
	Events.gravity_shift_finished.connect(_on_shift_finished)
	Events.countdown_changed.connect(_on_countdown_changed)
	Events.shot_taken.connect(_on_shot_taken)
	Events.save_made.connect(_on_save_made)


func _disconnect_events() -> void:
	if not _events_connected:
		return
	_events_connected = false
	if Events.ball_hit.is_connected(_on_ball_hit):
		Events.ball_hit.disconnect(_on_ball_hit)
	if Events.goal_scored.is_connected(_on_goal_scored):
		Events.goal_scored.disconnect(_on_goal_scored)
	if Events.car_demolished.is_connected(_on_car_demolished):
		Events.car_demolished.disconnect(_on_car_demolished)
	if Events.overtime_started.is_connected(_on_overtime_started):
		Events.overtime_started.disconnect(_on_overtime_started)
	if Events.gravity_shift_warning.is_connected(_on_shift_warning):
		Events.gravity_shift_warning.disconnect(_on_shift_warning)
	if Events.gravity_shift_started.is_connected(_on_shift_started):
		Events.gravity_shift_started.disconnect(_on_shift_started)
	if Events.gravity_shift_finished.is_connected(_on_shift_finished):
		Events.gravity_shift_finished.disconnect(_on_shift_finished)
	if Events.countdown_changed.is_connected(_on_countdown_changed):
		Events.countdown_changed.disconnect(_on_countdown_changed)
	if Events.shot_taken.is_connected(_on_shot_taken):
		Events.shot_taken.disconnect(_on_shot_taken)
	if Events.save_made.is_connected(_on_save_made):
		Events.save_made.disconnect(_on_save_made)


func _on_ball_hit(strength: float, position: Vector3, _hitter_id: int) -> void:
	if strength < 2.0:
		return
	var tier := tier_for_strength(strength)
	_last_hit_tier = tier
	var volume := -9.0
	if tier == "ball_medium":
		volume = -6.0
	elif tier == "ball_heavy":
		volume = -2.0
	var pitch: float = 1.0 + clampf((strength - 2.0) / 55.0, 0.0, 0.18)
	_play_hit(position, LIBRARY.get_stream(tier), volume, pitch)


func _play_hit(position: Vector3, stream: AudioStream, volume_db: float, pitch: float) -> void:
	if _hit_players.is_empty():
		return
	var player := _hit_players[_hit_cursor % _hit_players.size()]
	_hit_cursor = (_hit_cursor + 1) % _hit_players.size()
	player.global_position = position
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


func _on_goal_scored(_team: int, _scorer_id: int) -> void:
	if _crowd_cheer != null:
		_crowd_cheer.play()
	_play_announcer("announcer_goal", -1.0)


func _on_car_demolished(_victim_id: int, _attacker_id: int) -> void:
	_play_announcer("announcer_demolition", -6.0)


func _on_overtime_started() -> void:
	if _crowd_cheer != null:
		_crowd_cheer.play()
	_play_announcer("announcer_overtime", -1.0)


func _on_shift_warning(_seconds_left: float, _next_dir: Vector3) -> void:
	_shift_warning_playing = true
	_shift_whoosh_playing = false
	if _whoosh_player != null:
		_whoosh_player.stop()
	if _warning_player != null:
		_warning_player.pitch_scale = 1.0
		_warning_player.volume_db = -7.0
		_warning_player.play()


func _on_shift_started(_from_dir: Vector3, _to_dir: Vector3, _duration: float) -> void:
	_shift_warning_playing = false
	_shift_whoosh_playing = true
	if _warning_player != null:
		_warning_player.stop()
	if _whoosh_player != null:
		_whoosh_player.volume_db = -2.0
		_whoosh_player.play()
	_play_announcer("announcer_gravity_shift", -4.0)


func _on_shift_finished(_phase_index: int) -> void:
	_shift_warning_playing = false
	_shift_whoosh_playing = false


func _on_countdown_changed(value: int) -> void:
	# One spoken countdown per kickoff, not per digit.
	if value == 3:
		_play_announcer("countdown", -6.0)


func _on_shot_taken(_car_id: int) -> void:
	_praise("announcer_nice_shot", "nice_shot")


func _on_save_made(_car_id: int) -> void:
	_praise("announcer_what_a_save", "what_a_save")


func _praise(stream_id: String, event_name: String) -> void:
	if _praise_cooldown > 0.0:
		return
	_praise_cooldown = 7.0
	_play_announcer(stream_id, -7.0, event_name)


func _play_announcer(stream_id: String, volume_db: float, event_name: String = "") -> void:
	if _announcer_players.is_empty():
		return
	_last_announcer = stream_id
	var player := _announcer_players[_announcer_cursor % _announcer_players.size()]
	_announcer_cursor = (_announcer_cursor + 1) % _announcer_players.size()
	player.stream = LIBRARY.get_stream(stream_id)
	player.volume_db = volume_db
	player.play()
	if event_name == "":
		event_name = stream_id.trim_prefix("announcer_")
	var line := LIBRARY.announcer_line_for(event_name)
	if line != "":
		Events.show_subtitle.emit(line, 2.4)


# --- engine ------------------------------------------------------------------

## Public so tests and replay viewers can resync without waiting for _process.
func refresh_engine() -> void:
	var cars := _context_cars()
	var seen: Dictionary = {}
	for car: Car in cars:
		if car == null or not is_instance_valid(car):
			continue
		seen[car.car_id] = true
		var player: AudioStreamPlayer3D = _engine_players.get(car.car_id) as AudioStreamPlayer3D
		if player == null:
			player = _make_engine_player()
			_engine_players[car.car_id] = player
		var top_speed: float = car.tuning.max_speed if car.tuning != null else 40.0
		var speed_ratio: float = clampf(car.speed / maxf(top_speed, 1.0), 0.0, 1.0)
		var boosting: bool = car.input.boost and car.boost_component != null and car.boost_component.amount > 0.0
		player.global_position = car.global_position
		player.pitch_scale = engine_pitch(speed_ratio, boosting)
		var target_db := engine_volume_db(speed_ratio, boosting)
		if car.state == Car.State.DEMOLISHED:
			target_db = -60.0
		player.volume_db = lerpf(player.volume_db, target_db, 0.22)
		if car.state != Car.State.DEMOLISHED and not player.playing:
			player.play()
	for id: int in _engine_players.keys():
		if not seen.has(id):
			var stale := _engine_players[id] as AudioStreamPlayer3D
			if stale != null:
				stale.stop()
				stale.queue_free()
			_engine_players.erase(id)


func _context_cars() -> Array[Car]:
	var out: Array[Car] = []
	if context == null:
		return out
	var list: Variant = context.get("cars")
	if list is Array:
		for entry: Variant in list:
			if entry is Car:
				out.append(entry as Car)
	var single: Variant = context.get("car")
	if single is Car:
		out.append(single as Car)
	return out


static func engine_pitch(speed_ratio: float, boosting: bool) -> float:
	return clampf(0.72 + clampf(speed_ratio, 0.0, 1.0) * 0.82 + (0.22 if boosting else 0.0), 0.6, 2.1)


static func engine_volume_db(speed_ratio: float, boosting: bool) -> float:
	return clampf(lerpf(-24.0, -8.0, clampf(speed_ratio, 0.0, 1.0)) + (4.0 if boosting else 0.0), -26.0, 0.0)


static func tier_for_strength(strength: float) -> String:
	if strength < HIT_LIGHT_THRESHOLD:
		return "ball_light"
	if strength < HIT_HEAVY_THRESHOLD:
		return "ball_medium"
	return "ball_heavy"


# --- music -------------------------------------------------------------------

## Pure mapping used by both the live service and tests.
static func music_state_for(state: int, in_overtime: bool, time_left: float, score1: int, score2: int) -> String:
	if in_overtime or state == STATE_OVERTIME:
		return "overtime"
	if state == STATE_GOAL_PAUSE or state == STATE_REPLAY:
		return "tense"
	if state == STATE_PLAYING:
		if time_left <= 45.0:
			return "tense"
		if time_left <= 90.0 and absi(score1 - score2) <= 1:
			return "tense"
	return "calm"


func music_state() -> String:
	if context == null:
		return "calm"
	var state: int = int(context.get("state")) if context.get("state") != null else 0
	var overtime: bool = bool(context.get("in_overtime")) if context.get("in_overtime") != null else false
	var remaining: float = float(context.get("time_left")) if context.get("time_left") != null else 300.0
	var s1: int = int(context.get("score1")) if context.get("score1") != null else 0
	var s2: int = int(context.get("score2")) if context.get("score2") != null else 0
	return music_state_for(state, overtime, remaining, s1, s2)


func _update_music(delta: float) -> void:
	var wanted := music_state()
	_last_music_state = wanted
	for state: String in MUSIC_STATES:
		var player := _music_players.get(state) as AudioStreamPlayer
		if player == null:
			continue
		var target: float = MUSIC_ACTIVE_DB if state == wanted else MUSIC_SILENT_DB
		player.volume_db = move_toward(player.volume_db, target, delta * MUSIC_FADE_DB_PER_SECOND)
	if _crowd_loop != null:
		_crowd_loop.volume_db = move_toward(_crowd_loop.volume_db, _crowd_target_db(wanted), delta * 6.0)


## Selecting a layer at spawn is instant; only live state changes fade.
func _snap_music() -> void:
	_last_music_state = music_state()
	for state: String in MUSIC_STATES:
		var player := _music_players.get(state) as AudioStreamPlayer
		if player != null:
			player.volume_db = MUSIC_ACTIVE_DB if state == _last_music_state else MUSIC_SILENT_DB
	if _crowd_loop != null:
		_crowd_loop.volume_db = _crowd_target_db(_last_music_state)


static func _crowd_target_db(state: String) -> float:
	if state == "tense":
		return -19.0
	if state == "overtime":
		return -16.5
	return -22.0


# --- introspection -----------------------------------------------------------

func engine_voice_count() -> int:
	return _engine_players.size()


func engine_player(car_id: int) -> AudioStreamPlayer3D:
	return _engine_players.get(car_id) as AudioStreamPlayer3D


func hit_voice_count() -> int:
	return _hit_players.size()


func announcer_voice_count() -> int:
	return _announcer_players.size()


func music_player(state: String) -> AudioStreamPlayer:
	return _music_players.get(state) as AudioStreamPlayer


func music_volume(state: String) -> float:
	var player := music_player(state)
	return player.volume_db if player != null else MUSIC_SILENT_DB


func active_music_state() -> String:
	return _last_music_state


func last_hit_tier() -> String:
	return _last_hit_tier


func last_announcer() -> String:
	return _last_announcer


func is_shift_warning_playing() -> bool:
	return _shift_warning_playing


func is_shift_whoosh_playing() -> bool:
	return _shift_whoosh_playing


func crowd_volume_db() -> float:
	return _crowd_loop.volume_db if _crowd_loop != null else -80.0
