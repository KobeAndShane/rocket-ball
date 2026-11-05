extends Node
## Single source of truth for gravity (architecture rule 1).
## Owns the current down direction, the phase cycle and the 2 s blend.
## Server-authoritative in multiplayer; offline play acts as the server.

signal shift_warning(seconds_left: float, next_dir: Vector3)
signal shift_started(from_dir: Vector3, to_dir: Vector3, duration: float)
signal shift_finished(phase_index: int, dir: Vector3)
signal phase_changed(phase_index: int, dir: Vector3)

const PHASE_FLOOR := Vector3(0.0, -1.0, 0.0)
const PHASE_WALL_A := Vector3(0.0, 0.0, -1.0)
const PHASE_CEILING := Vector3(0.0, 1.0, 0.0)
const PHASE_WALL_B := Vector3(0.0, 0.0, 1.0)
const DEFAULT_PHASES: Array[Vector3] = [
	PHASE_FLOOR, PHASE_WALL_A, PHASE_CEILING, PHASE_WALL_B,
]

var gravity_dir: Vector3 = PHASE_FLOOR
var up: Vector3 = -PHASE_FLOOR
var gravity_strength: float = 9.8

var phases: Array[Vector3] = DEFAULT_PHASES.duplicate()
var phase_index: int = 0
var interval: float = 30.0
var warning_time: float = 5.0
var transition_time: float = 2.0
var time_to_shift: float = 30.0
var running: bool = false
var random_order: bool = false
var boost_refill_on_shift: float = 0.0
var rng := RandomNumberGenerator.new()

var _in_transition: bool = false
var _transition_t: float = 0.0
var _from: Vector3 = PHASE_FLOOR
var _to: Vector3 = PHASE_FLOOR
var _warned: bool = false


func _ready() -> void:
	rng.randomize()
	time_to_shift = interval


func _physics_process(delta: float) -> void:
	advance(delta)


## Configure from MatchRules.tres. Everything is data-driven.
func configure(
	p_phases: Array,
	p_interval: float,
	p_warning: float,
	p_transition: float,
	p_strength: float,
	p_random: bool,
	p_seed: int,
	p_boost_refill: float
) -> void:
	phases.clear()
	for d: Variant in p_phases:
		var v: Vector3 = d as Vector3
		if v.length() > 0.0001:
			phases.append(v.normalized())
	if phases.is_empty():
		phases = DEFAULT_PHASES.duplicate()
	interval = maxf(p_interval, 0.5)
	warning_time = clampf(p_warning, 0.0, interval)
	transition_time = maxf(p_transition, 0.0)
	gravity_strength = maxf(p_strength, 0.0)
	random_order = p_random
	boost_refill_on_shift = maxf(p_boost_refill, 0.0)
	rng.seed = p_seed
	reset_phase(0)


## Advance the phase clock. Public so headless tests can drive it directly.
func advance(delta: float) -> void:
	if not running:
		return

	if _in_transition:
		_transition_t += delta / maxf(transition_time, 0.0001)
		var weight: float = _smooth(_transition_t)
		if _transition_t >= 1.0:
			_transition_t = 1.0
			weight = 1.0

		# Rotate the down vector along the shortest arc, easing both ways.
		var q := Quaternion(_from.normalized(), _to.normalized())
		var blended := Quaternion.IDENTITY.slerp(q, weight) * _from
		gravity_dir = blended.normalized()
		up = -gravity_dir

		if _transition_t >= 1.0:
			_in_transition = false
			_transition_t = 0.0
			gravity_dir = _to
			up = -_to
			time_to_shift = interval
			_warned = false
			shift_finished.emit(phase_index, gravity_dir)
			if boost_refill_on_shift > 0.0:
				Events.ui_prompt.emit("Gravity locked - boost pulse!", 1.0)
		return

	time_to_shift -= delta
	if not _warned and time_to_shift <= warning_time:
		_warned = true
		shift_warning.emit(maxf(time_to_shift, 0.0), phases[next_index()])

	if time_to_shift <= 0.0:
		_begin_shift()


func _begin_shift() -> void:
	if _in_transition or phases.size() < 2:
		return
	phase_index = next_index()
	_from = gravity_dir
	_to = phases[phase_index]
	_in_transition = true
	_transition_t = 0.0
	time_to_shift = 0.0
	phase_changed.emit(phase_index, _to)
	Events.gravity_phase_changed.emit(phase_index, _to)
	shift_started.emit(_from, _to, transition_time)
	Events.ui_prompt.emit("GRAVITY SHIFT", 1.2)


func next_index() -> int:
	if phases.size() <= 1:
		return phase_index
	if random_order:
		var choice: int = rng.randi_range(0, phases.size() - 2)
		if choice >= phase_index:
			choice += 1
		return choice
	return (phase_index + 1) % phases.size()


func start() -> void:
	running = true
	_warned = false
	time_to_shift = interval


func stop() -> void:
	running = false


## Teleport the gravity phase without blending (used at kickoff / match start).
func reset_phase(index: int = 0, restart_timer: bool = true) -> void:
	phase_index = wrapi(index, 0, phases.size())
	_in_transition = false
	_transition_t = 0.0
	gravity_dir = phases[phase_index]
	up = -gravity_dir
	_warned = false
	if restart_timer:
		time_to_shift = interval


## Debug key: force the next transition now.
func debug_shift() -> void:
	if _in_transition:
		return
	if time_to_shift > 0.0:
		time_to_shift = 0.0
		_begin_shift()
	else:
		_begin_shift()


func is_in_transition() -> bool:
	return _in_transition


func _smooth(t: float) -> float:
	var x: float = clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)
