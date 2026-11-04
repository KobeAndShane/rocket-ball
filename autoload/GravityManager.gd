extends Node
## Single source of truth for gravity.
##
## `gravity_dir` points toward "down". Everything in the game derives local up
## from `up` (-gravity_dir). No other system may read ProjectSettings gravity.

const PHASE_FLOOR := Vector3(0.0, -1.0, 0.0)
const PHASE_WALL_A := Vector3(-1.0, 0.0, 0.0)
const PHASE_CEILING := Vector3(0.0, 1.0, 0.0)
const PHASE_WALL_B := Vector3(1.0, 0.0, 0.0)
const PHASE_NAMES := ["FLOOR", "WALL A", "CEILING", "WALL B"]
const GOAL_AXIS := Vector3(0.0, 0.0, 1.0)

var gravity_dir: Vector3 = PHASE_FLOOR
var gravity_strength: float = 20.0

var phase_index: int = 0
var time_to_shift: float = 30.0
var transition_duration: float = 2.0
var shift_interval: float = 30.0
var warning_time: float = 5.0
var active: bool = false
var transitioning: bool = false

var _phases: Array[Vector3] = [PHASE_FLOOR, PHASE_WALL_A, PHASE_CEILING, PHASE_WALL_B]
var _enabled: Array[bool] = [true, true, true, true]
var _random_order: bool = false
var _rng := RandomNumberGenerator.new()
var _seed: int = 0
var _phase_started_tick: int = 0
var _transition_elapsed: float = 0.0
var _from_dir: Vector3 = PHASE_FLOOR
var _to_dir: Vector3 = PHASE_FLOOR
var _warned: bool = false
var _next_index: int = 1
var _time_accum: float = 0.0


func _ready() -> void:
	# Gravity manager must keep running even while the match scene is paused for
	# menus; it gates itself with `active` instead of process_mode.
	process_mode = Node.PROCESS_MODE_ALWAYS


var up: Vector3:
	get:
		return -gravity_dir


func _physics_process(delta: float) -> void:
	if not active:
		return
	_time_accum += delta
	if transitioning:
		_transition_elapsed += delta
		var t: float = clampf(_transition_elapsed / maxf(transition_duration, 0.001), 0.0, 1.0)
		var eased: float = smoothstep(0.0, 1.0, t)
		gravity_dir = _blend_direction(_from_dir, _to_dir, eased)
		Events.gravity_changed.emit(gravity_dir)
		if t >= 1.0:
			transitioning = false
			gravity_dir = _to_dir
			phase_index = _next_index
			_next_index = _pick_next_index()
			_time_accum = 0.0
			time_to_shift = shift_interval
			_warned = false
			_phase_started_tick = Engine.get_physics_frames()
			Events.gravity_shift_finished.emit(phase_index)
		return

	time_to_shift -= delta
	if not _warned and time_to_shift <= warning_time:
		_warned = true
		Events.gravity_shift_warning.emit(time_to_shift, _phases[_next_index])
	if time_to_shift <= 0.0:
		_begin_shift()


func _begin_shift() -> void:
	if _phases.size() < 2:
		return
	# Never start a new shift while blending.
	if transitioning:
		return
	_from_dir = gravity_dir
	_to_dir = _phases[_next_index]
	_transition_elapsed = 0.0
	transitioning = true
	time_to_shift = 0.0
	Events.gravity_shift_started.emit(_from_dir, _to_dir, transition_duration)


## Robust slerp: antipodal vectors (floor <-> ceiling) need an explicit axis.
func _blend_direction(from_dir: Vector3, to_dir: Vector3, t: float) -> Vector3:
	var a := from_dir.normalized()
	var b := to_dir.normalized()
	var d := a.dot(b)
	if d < -0.9995:
		return a.rotated(GOAL_AXIS, -PI * t).normalized()
	return a.slerp(b, t).normalized()


func configure(rules: Resource = null, seed_value: int = 0) -> void:
	_seed = seed_value
	_rng.seed = seed_value
	_random_order = false
	shift_interval = 30.0
	transition_duration = 2.0
	warning_time = 5.0
	_enabled = [true, true, true, true]
	_phases = [PHASE_FLOOR, PHASE_WALL_A, PHASE_CEILING, PHASE_WALL_B]
	if rules != null:
		var interval: Variant = rules.get("gravity_interval")
		if interval != null:
			shift_interval = float(interval)
		var transition: Variant = rules.get("gravity_transition")
		if transition != null:
			transition_duration = float(transition)
		var warn: Variant = rules.get("gravity_warning")
		if warn != null:
			warning_time = float(warn)
		var random_v: Variant = rules.get("random_gravity")
		if random_v != null:
			_random_order = bool(random_v)
		var phases_v: Variant = rules.get("enabled_phases")
		if phases_v is Array:
			_enabled = (phases_v as Array).duplicate()
			while _enabled.size() < 4:
				_enabled.append(false)
		var strength: Variant = rules.get("gravity_strength")
		if strength != null:
			gravity_strength = float(strength)
	_rebuild_phases()
	reset_to_phase(0)


func _rebuild_phases() -> void:
	var base := [PHASE_FLOOR, PHASE_WALL_A, PHASE_CEILING, PHASE_WALL_B]
	var built: Array[Vector3] = []
	for i in base.size():
		if bool(_enabled[i]):
			built.append(base[i])
	if built.size() < 2:
		built = [PHASE_FLOOR, PHASE_WALL_A]
	_phases = built


func reset_to_phase(index: int = 0) -> void:
	transitioning = false
	_transition_elapsed = 0.0
	phase_index = clampi(index, 0, _phases.size() - 1)
	gravity_dir = _phases[phase_index]
	_next_index = _pick_next_index()
	time_to_shift = shift_interval
	_warned = false
	_time_accum = 0.0
	_phase_started_tick = Engine.get_physics_frames()


func _pick_next_index() -> int:
	if _phases.size() < 2:
		return 0
	if _random_order:
		var candidates: Array[int] = []
		for i in _phases.size():
			if i != phase_index:
				candidates.append(i)
		if candidates.is_empty():
			return phase_index
		return candidates[_rng.randi_range(0, candidates.size() - 1)]
	return (phase_index + 1) % _phases.size()


## Debug / tests: immediately set gravity, no blend.
func force_direction(dir: Vector3) -> void:
	gravity_dir = dir.normalized()
	transitioning = false
	for i in _phases.size():
		if _phases[i].is_equal_approx(gravity_dir):
			phase_index = i
			_next_index = _pick_next_index()
			break
	time_to_shift = shift_interval
	_warned = false
	Events.gravity_changed.emit(gravity_dir)


## Debug / tests: jump to next phase instantly.
func force_next_phase() -> void:
	phase_index = _next_index
	gravity_dir = _phases[phase_index]
	_next_index = _pick_next_index()
	time_to_shift = shift_interval
	_warned = false
	Events.gravity_changed.emit(gravity_dir)
	Events.gravity_shift_finished.emit(phase_index)


## Starts/restarts the countdown without changing gravity.
func start() -> void:
	reset_to_phase(phase_index)
	active = true


func stop() -> void:
	active = false
	transitioning = false


func next_direction() -> Vector3:
	return _phases[_next_index]


func phases() -> Array[Vector3]:
	return _phases


func time_until_shift() -> float:
	return maxf(time_to_shift, 0.0)


func is_warning() -> bool:
	return (not transitioning) and time_to_shift <= warning_time


func phase_name() -> String:
	var idx: int = _phases.find(gravity_dir)
	if transitioning or idx < 0:
		return "SHIFTING"
	return PHASE_NAMES[clampi(phase_index, 0, PHASE_NAMES.size() - 1)]


## Server -> client synchronisation. Clients call this with the authoritative
## phase and the server tick at which it started; they derive the blend locally.
func sync_phase(index: int, server_tick: int, interval: float, transition: float) -> void:
	if index < 0 or index >= _phases.size():
		return
	var ticks_per_second: float = float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 120))
	var elapsed_ticks: int = maxi(0, Engine.get_physics_frames() - server_tick)
	var elapsed_seconds: float = float(elapsed_ticks) / ticks_per_second
	if index == phase_index and not transitioning:
		return
	if elapsed_seconds < transition and transition > 0.001:
		_from_dir = gravity_dir
		_to_dir = _phases[index]
		_transition_elapsed = elapsed_seconds
		transition_duration = transition
		transitioning = true
		_next_index = index
	else:
		force_direction(_phases[index])
	time_to_shift = maxf(0.0, interval - elapsed_seconds)


func serialize_state() -> Dictionary:
	return {
		"phase": phase_index,
		"tick": Engine.get_physics_frames(),
		"to_shift": time_to_shift,
		"dir": gravity_dir,
	}
