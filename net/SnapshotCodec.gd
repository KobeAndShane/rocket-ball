class_name SnapshotCodec
extends RefCounted
## Compact, quantised snapshot format. One packet carries every car, the ball,
## the authoritative gravity phase and the server tick.
##
## Budget: ~170 bytes at 60 Hz = ~10 KB/s per client.

const POS_SCALE := 128.0
const VEL_SCALE := 32.0
const MAX_POS := 300.0
const MAX_VEL := 400.0


static func encode(tick: int, phase: int, cars: Array, ball: Ball, meta: Dictionary = {}) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u32(tick)
	buf.put_u8(clampi(phase, 0, 255))
	buf.put_u8(cars.size())
	for car: Car in cars:
		buf.put_u8(car.car_id & 0xFF)
		var tf: Transform3D = car.global_transform
		_put_vec3(buf, tf.origin, POS_SCALE, MAX_POS)
		_put_quat(buf, tf.basis.get_rotation_quaternion())
		_put_vec3(buf, car.linear_velocity, VEL_SCALE, MAX_VEL)
		var boost: float = car.boost_component.amount if car.boost_component != null else 0.0
		buf.put_u8(int(clampf(boost, 0.0, 150.0)))
		buf.put_u8(int(car.state) & 0xFF)
	buf.put_u8(1 if ball != null else 0)
	if ball != null:
		_put_vec3(buf, ball.global_position, POS_SCALE, MAX_POS)
		_put_quat(buf, ball.global_transform.basis.get_rotation_quaternion())
		_put_vec3(buf, ball.linear_velocity, VEL_SCALE, MAX_VEL)
		_put_vec3(buf, ball.angular_velocity, VEL_SCALE, MAX_VEL)
	_put_meta(buf, meta)
	return buf.data_array


static func decode(data: PackedByteArray) -> Dictionary:
	if data.size() < 6:
		return {}
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	var tick: int = buf.get_u32()
	var phase: int = buf.get_u8()
	var count: int = buf.get_u8()
	var cars: Array[Dictionary] = []
	for i in count:
		if buf.get_available_bytes() < 1 + 6 + 8 + 6 + 2:
			break
		var id: int = buf.get_u8()
		var p: Vector3 = _get_vec3(buf, POS_SCALE)
		var q: Quaternion = _get_quat(buf)
		var v: Vector3 = _get_vec3(buf, VEL_SCALE)
		var boost: float = float(buf.get_u8())
		var state: int = buf.get_u8()
		cars.append({"id": id, "p": p, "q": q, "v": v, "b": boost, "s": state})
	var result := {"tick": tick, "phase": phase, "cars": cars, "ball": {}, "m": {}}
	if buf.get_available_bytes() >= 1:
		var has_ball: int = buf.get_u8()
		if has_ball == 1 and buf.get_available_bytes() >= 6 + 8 + 6 + 6:
			result["ball"] = {
				"p": _get_vec3(buf, POS_SCALE),
				"q": _get_quat(buf),
				"v": _get_vec3(buf, VEL_SCALE),
				"w": _get_vec3(buf, VEL_SCALE),
			}
	if buf.get_available_bytes() >= 10:
		result["m"] = _get_meta(buf)
	return result


## Match metadata rides along with every snapshot so clients never drift on
## score, clock, countdown or match phase.
static func _put_meta(buf: StreamPeerBuffer, meta: Dictionary) -> void:
	buf.put_u8(1) # meta version
	buf.put_u8(clampi(int(meta.get("state", 0)), 0, 255))
	buf.put_u8(clampi(int(meta.get("score1", 0)), 0, 255))
	buf.put_u8(clampi(int(meta.get("score2", 0)), 0, 255))
	buf.put_u16(_centiseconds(float(meta.get("time_left", 0.0))))
	buf.put_u16(_centiseconds(float(meta.get("countdown", 0.0))))
	buf.put_u16(_centiseconds(float(meta.get("overtime", 0.0))))


static func _get_meta(buf: StreamPeerBuffer) -> Dictionary:
	var version: int = buf.get_u8()
	if version != 1:
		return {}
	return {
		"state": buf.get_u8(),
		"score1": buf.get_u8(),
		"score2": buf.get_u8(),
		"time_left": float(buf.get_u16()) / 100.0,
		"countdown": float(buf.get_u16()) / 100.0,
		"overtime": float(buf.get_u16()) / 100.0,
	}


static func _centiseconds(seconds: float) -> int:
	return clampi(int(round(maxf(seconds, 0.0) * 100.0)), 0, 65535)


static func _put_vec3(buf: StreamPeerBuffer, v: Vector3, scale: float, limit: float) -> void:
	buf.put_16(_quantise(v.x, scale, limit))
	buf.put_16(_quantise(v.y, scale, limit))
	buf.put_16(_quantise(v.z, scale, limit))


static func _get_vec3(buf: StreamPeerBuffer, scale: float) -> Vector3:
	return Vector3(float(buf.get_16()) / scale, float(buf.get_16()) / scale, float(buf.get_16()) / scale)


static func _quantise(value: float, scale: float, limit: float) -> int:
	return clampi(int(round(clampf(value, -limit, limit) * scale)), -32768, 32767)


## Smallest-three quaternion packing: 2 bits for the dropped component, three
## signed 16-bit values for the rest.
static func _put_quat(buf: StreamPeerBuffer, q: Quaternion) -> void:
	var comps: Array[float] = [q.x, q.y, q.z, q.w]
	var largest: int = 0
	for i in 4:
		if absf(comps[i]) > absf(comps[largest]):
			largest = i
	var sign_value: float = 1.0 if comps[largest] >= 0.0 else -1.0
	buf.put_u8(largest & 0x03)
	for i in 4:
		if i == largest:
			continue
		buf.put_16(clampi(int(round(clampf(comps[i] * sign_value, -1.0, 1.0) * 32767.0)), -32767, 32767))


static func _get_quat(buf: StreamPeerBuffer) -> Quaternion:
	var largest: int = buf.get_u8() & 0x03
	var values: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var sum: float = 0.0
	for i in 4:
		if i == largest:
			continue
		var v: float = clampf(float(buf.get_16()) / 32767.0, -1.0, 1.0)
		values[i] = v
		sum += v * v
	values[largest] = sqrt(maxf(0.0, 1.0 - sum))
	return Quaternion(values[0], values[1], values[2], values[3]).normalized()
