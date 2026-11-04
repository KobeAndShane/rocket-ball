class_name PredictionController
extends Node
## Client-side prediction for the local car.
##
## Every physics tick the local input is recorded and sent (with two redundant
## previous inputs). When an authoritative snapshot arrives we compare the local
## state with the server state. Small errors are blended out; large errors reset
## the car and replay the unacknowledged inputs through a lightweight kinematic
## model so the correction matches what the player is currently doing.

const TICK_RATE := 120.0

var car: Car
var net: Node
var history := InputBuffer.new()
var last_server_tick: int = -1
var last_snapshot_error: float = 0.0
var corrections: int = 0

var _correction := Vector3.ZERO
var _correction_rot := Quaternion.IDENTITY
var _has_correction: bool = false


func _ready() -> void:
	process_physics_priority = 100


func setup(car_ref: Car, net_ref: Node) -> void:
	car = car_ref
	net = net_ref


func _physics_process(delta: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	if car.state == Car.State.DEMOLISHED:
		return
	if net != null and not net.is_server and not net.is_offline and not car.frozen:
		var input := car.input.duplicate() as CarInput
		var tick: int = int(net.server_tick)
		if tick <= history.last_tick():
			tick = history.last_tick() + 1
		input.tick = tick
		history.push(input)
		if net.has_method("send_inputs"):
			net.send_inputs(car.car_id, history.latest(3))
	if _has_correction:
		car.global_position += _correction * clampf(12.0 * delta, 0.0, 1.0)
		_correction *= exp(-12.0 * delta)
		if _correction.length_squared() < 0.0004:
			_correction = Vector3.ZERO
			_has_correction = false


func apply_snapshot(state: Dictionary, server_tick: int) -> void:
	if car == null or not is_instance_valid(car):
		return
	last_server_tick = server_tick
	var server_pos: Vector3 = state.get("p", car.global_position)
	var server_vel: Vector3 = state.get("v", car.linear_velocity)
	var server_q: Quaternion = state.get("q", car.global_transform.basis.get_rotation_quaternion())
	var pos_error: float = car.global_position.distance_to(server_pos)
	var vel_error: float = car.linear_velocity.distance_to(server_vel)
	last_snapshot_error = pos_error
	var unacked := history.unacked(server_tick)
	var replayed := _replay(server_pos, server_vel, server_q, unacked)
	if pos_error > 2.5 or vel_error > 14.0:
		# Large divergence: accept authority, then replay the pending inputs.
		corrections += 1
		car.global_transform = Transform3D(Basis(replayed["q"]), replayed["p"])
		car.linear_velocity = replayed["v"]
		car.angular_velocity = state.get("w", car.angular_velocity)
		history.prune(server_tick)
		_has_correction = false
	elif pos_error > 0.03:
		# Small divergence: smooth the visual/physical error over a few frames.
		_correction = replayed["p"] - car.global_position
		_has_correction = true
		car.linear_velocity = car.linear_velocity.lerp(replayed["v"], 0.35)
	history.prune(server_tick)


## Approximate the missing physics ticks. This intentionally models only the
## dominant forces; the server remains authoritative and the residual error is
## removed by the next snapshot.
func _replay(pos: Vector3, vel: Vector3, rot: Quaternion, inputs: Array[CarInput]) -> Dictionary:
	var p := pos
	var v := vel
	var q := rot
	var dt: float = 1.0 / TICK_RATE
	var tuning: CarTuning = car.tuning
	var up: Vector3 = GravityManager.up
	for input: CarInput in inputs:
		v += GravityManager.gravity_dir * GravityManager.gravity_strength * dt
		var forward: Vector3 = -Basis(q).z.normalized()
		var speed: float = v.length()
		if input.throttle != 0.0 and speed < tuning.max_speed:
			v += forward * input.throttle * tuning.drive_force / maxf(tuning.mass, 1.0) * dt
		if input.boost:
			v += forward * tuning.boost_force / maxf(tuning.mass, 1.0) * dt
		if input.jump_pressed:
			v += up * tuning.jump_velocity
		# Cheap steering prediction around local up.
		if absf(input.steer) > 0.01 and speed > 1.0:
			var yaw_axis: Vector3 = up
			var angle: float = input.steer * tuning.turn_rate_high * dt * clampf(speed / tuning.max_speed, 0.25, 1.0)
			q = Quaternion(yaw_axis, angle) * q
		var cap: float = tuning.boost_max_speed if input.boost else tuning.max_speed
		if v.length() > cap:
			v = v.normalized() * cap
		p += v * dt
	return {"p": p, "v": v, "q": q.normalized()}
