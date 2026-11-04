class_name ReplayData
extends RefCounted
## Compact replay container. The primary stream is the initial state plus the
## per-car input timeline; dense snapshots every few ticks act as a scrub and
## cross-version fallback, exactly as recommended for physics re-simulation.

const VERSION := 1
const INPUT_STRIDE := 8
const SNAPSHOT_STRIDE := 30

var version: int = VERSION
var created: float = 0.0
var mode: String = "Standard"
var tick_rate: int = 120
var physics_version: String = ""
var seed_value: int = 0
var initial: Dictionary = {}
var inputs: Array = []
var snapshots: Array = []
var duration: float = 0.0
var score1: int = 0
var score2: int = 0


func to_dict() -> Dictionary:
	return {
		"version": version,
		"created": created,
		"mode": mode,
		"tick_rate": tick_rate,
		"physics_version": physics_version,
		"seed": seed_value,
		"initial": initial,
		"inputs": inputs,
		"snapshots": snapshots,
		"duration": duration,
		"score1": score1,
		"score2": score2,
	}


static func from_dict(data: Dictionary) -> ReplayData:
	var r := ReplayData.new()
	r.version = int(data.get("version", VERSION))
	r.created = float(data.get("created", 0.0))
	r.mode = str(data.get("mode", "Standard"))
	r.tick_rate = maxi(1, int(data.get("tick_rate", 120)))
	r.physics_version = str(data.get("physics_version", ""))
	r.seed_value = int(data.get("seed", 0))
	r.initial = data.get("initial", {}) as Dictionary
	r.inputs = data.get("inputs", []) as Array
	r.snapshots = data.get("snapshots", []) as Array
	r.duration = float(data.get("duration", 0.0))
	r.score1 = int(data.get("score1", 0))
	r.score2 = int(data.get("score2", 0))
	return r


func add_input(tick: int, car: Car) -> bool:
	var flags := 0
	if car.input.jump_pressed:
		flags |= 1
	if car.input.jump_held:
		flags |= 2
	if car.input.boost:
		flags |= 4
	if car.input.handbrake:
		flags |= 8
	if car.input.air_roll:
		flags |= 16
	var entry := [
		tick,
		car.car_id,
		snappedf(car.input.throttle, 0.01),
		snappedf(car.input.steer, 0.01),
		snappedf(car.input.pitch, 0.01),
		snappedf(car.input.yaw, 0.01),
		snappedf(car.input.roll, 0.01),
		flags,
	]
	if inputs.is_empty():
		inputs.append(entry)
		return true
	var last: Array = inputs[inputs.size() - 1]
	if int(last[1]) == car.car_id and _same_input(last, entry):
		return false
	inputs.append(entry)
	return true


func _same_input(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(2, a.size()):
		if a[i] != b[i]:
			return false
	return true


## Latest input for every car at or before the requested tick. Playback can call
## this after a scrub instead of re-walking the whole stream.
func inputs_at(tick: int) -> Dictionary:
	var out: Dictionary = {}
	for entry: Variant in inputs:
		var row: Array = entry as Array
		if row.size() < 8:
			continue
		var t: int = int(row[0])
		if t > tick:
			break
		out[int(row[1])] = _input_from_row(row)
	return out


static func input_from_row(row: Array) -> CarInput:
	return _input_from_row(row)


static func _input_from_row(row: Array) -> CarInput:
	var input := CarInput.new()
	if row.size() < 8:
		return input
	input.tick = int(row[0])
	input.throttle = float(row[2])
	input.steer = float(row[3])
	input.pitch = float(row[4])
	input.yaw = float(row[5])
	input.roll = float(row[6])
	var flags: int = int(row[7])
	input.jump_pressed = (flags & 1) != 0
	input.jump_held = (flags & 2) != 0
	input.boost = (flags & 4) != 0
	input.handbrake = (flags & 8) != 0
	input.air_roll = (flags & 16) != 0
	return input


func add_snapshot(tick: int, cars: Array[Car], ball: Ball, phase: int, score_a: int = 0, score_b: int = 0) -> void:
	var car_rows: Array = []
	for car: Car in cars:
		car_rows.append(encode_car(car))
	snapshots.append({
		"t": tick,
		"c": car_rows,
		"b": encode_ball(ball),
		"g": phase,
		"s": [score_a, score_b],
	})


func snapshot_before(tick: int) -> Dictionary:
	var best: Dictionary = {}
	for entry: Variant in snapshots:
		var snap: Dictionary = entry as Dictionary
		if int(snap.get("t", 0)) > tick:
			break
		best = snap
	return best


func snapshot_after(tick: int) -> Dictionary:
	for entry: Variant in snapshots:
		var snap: Dictionary = entry as Dictionary
		if int(snap.get("t", 0)) >= tick:
			return snap
	return {}


func summary() -> Dictionary:
	return {
		"mode": mode,
		"created": created,
		"duration": duration,
		"score1": score1,
		"score2": score2,
		"tick_rate": tick_rate,
		"snapshots": snapshots.size(),
		"inputs": inputs.size(),
	}


static func encode_car(car: Car) -> Array:
	var p := car.global_position
	var q := car.global_transform.basis.get_rotation_quaternion()
	var v := car.linear_velocity
	return [
		car.car_id,
		snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001),
		snappedf(q.x, 0.0001), snappedf(q.y, 0.0001), snappedf(q.z, 0.0001), snappedf(q.w, 0.0001),
		snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001),
		snappedf(car.boost_component.amount if car.boost_component != null else 0.0, 0.1),
		int(car.state),
	]


static func decode_car(row: Array) -> Dictionary:
	if row.size() < 13:
		return {}
	return {
		"id": int(row[0]),
		"p": Vector3(float(row[1]), float(row[2]), float(row[3])),
		"q": Quaternion(float(row[4]), float(row[5]), float(row[6]), float(row[7])),
		"v": Vector3(float(row[8]), float(row[9]), float(row[10])),
		"b": float(row[11]),
		"s": int(row[12]),
	}


static func encode_ball(ball: Ball) -> Array:
	var p := ball.global_position
	var q := ball.global_transform.basis.get_rotation_quaternion()
	var v := ball.linear_velocity
	var w := ball.angular_velocity
	return [
		snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001),
		snappedf(q.x, 0.0001), snappedf(q.y, 0.0001), snappedf(q.z, 0.0001), snappedf(q.w, 0.0001),
		snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001),
		snappedf(w.x, 0.001), snappedf(w.y, 0.001), snappedf(w.z, 0.001),
	]


static func decode_ball(row: Array) -> Dictionary:
	if row.size() < 13:
		return {}
	return {
		"p": Vector3(float(row[0]), float(row[1]), float(row[2])),
		"q": Quaternion(float(row[3]), float(row[4]), float(row[5]), float(row[6])),
		"v": Vector3(float(row[7]), float(row[8]), float(row[9])),
		"w": Vector3(float(row[10]), float(row[11]), float(row[12])),
	}


static func initial_car(car: Car) -> Dictionary:
	return {
		"id": car.car_id,
		"team": car.team,
		"name": car.display_name,
		"p": [snappedf(car.global_position.x, 0.001), snappedf(car.global_position.y, 0.001), snappedf(car.global_position.z, 0.001)],
		"q": _quat_array(car.global_transform.basis.get_rotation_quaternion()),
		"v": [snappedf(car.linear_velocity.x, 0.001), snappedf(car.linear_velocity.y, 0.001), snappedf(car.linear_velocity.z, 0.001)],
		"w": [snappedf(car.angular_velocity.x, 0.001), snappedf(car.angular_velocity.y, 0.001), snappedf(car.angular_velocity.z, 0.001)],
		"b": snappedf(car.boost_component.amount if car.boost_component != null else 0.0, 0.1),
		"s": int(car.state),
		"loadout": car.get_loadout(),
	}


static func _quat_array(q: Quaternion) -> Array:
	return [snappedf(q.x, 0.0001), snappedf(q.y, 0.0001), snappedf(q.z, 0.0001), snappedf(q.w, 0.0001)]
