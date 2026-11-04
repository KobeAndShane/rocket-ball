class_name CarInput
extends RefCounted
## One physics tick of car input. Humans, bots and network packets all produce this.
## Kept allocation-light and serialisable for the netcode.

var throttle: float = 0.0 # -1 reverse .. +1 forward
var steer: float = 0.0 # -1 left .. +1 right
var pitch: float = 0.0 # -1 nose down .. +1 nose up (air only)
var yaw: float = 0.0
var roll: float = 0.0
var jump_pressed: bool = false
var jump_held: bool = false
var boost: bool = false
var handbrake: bool = false
var air_roll: bool = false

## Network/player metadata, not part of the input itself.
var tick: int = 0


func clear_edges() -> void:
	jump_pressed = false


func copy_from(other: CarInput) -> void:
	throttle = other.throttle
	steer = other.steer
	pitch = other.pitch
	yaw = other.yaw
	roll = other.roll
	jump_pressed = other.jump_pressed
	jump_held = other.jump_held
	boost = other.boost
	handbrake = other.handbrake
	air_roll = other.air_roll
	tick = other.tick


func get_flat_direction() -> Vector2:
	return Vector2(steer, throttle)


## Maps an 8-way stick direction into a world-space horizontal dodge direction,
## using the car's current basis and the local gravity up.
static func dodge_world_direction(flat: Vector2, basis: Basis, up: Vector3) -> Vector3:
	var local := Vector3(flat.x, 0.0, -flat.y)
	if local.length_squared() < 0.01:
		local = Vector3(0.0, 0.0, -1.0)
	local = local.normalized()
	var world := (basis * local)
	world -= up * world.dot(up)
	if world.length_squared() < 0.001:
		world = -up.cross(basis.x).normalized()
		if world.length_squared() < 0.001:
			world = Vector3.FORWARD
	return world.normalized()


## Coarse 8-way label, used by tests and the input display.
static func dodge_label(flat: Vector2) -> String:
	if flat.length_squared() < 0.04:
		return "none"
	var angle := atan2(flat.x, flat.y) # forward = +y
	var idx := int(round(angle / (PI / 4.0)))
	var labels := ["forward", "forward-right", "right", "back-right", "back", "back-left", "left", "forward-left"]
	return labels[posmod(idx, 8)]


func serialize() -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_8(int(clampf(throttle, -1.0, 1.0) * 127.0) & 0xFF)
	buf.put_8(int(clampf(steer, -1.0, 1.0) * 127.0) & 0xFF)
	buf.put_8(int(clampf(pitch, -1.0, 1.0) * 127.0) & 0xFF)
	buf.put_8(int(clampf(yaw, -1.0, 1.0) * 127.0) & 0xFF)
	buf.put_8(int(clampf(roll, -1.0, 1.0) * 127.0) & 0xFF)
	var flags: int = 0
	if jump_pressed:
		flags |= 1
	if jump_held:
		flags |= 2
	if boost:
		flags |= 4
	if handbrake:
		flags |= 8
	if air_roll:
		flags |= 16
	buf.put_8(flags)
	buf.put_u32(tick)
	return buf.data_array


static func deserialize(data: PackedByteArray) -> CarInput:
	var input := CarInput.new()
	if data.size() < 9:
		return input
	input.throttle = _decode_byte(data[0])
	input.steer = _decode_byte(data[1])
	input.pitch = _decode_byte(data[2])
	input.yaw = _decode_byte(data[3])
	input.roll = _decode_byte(data[4])
	var flags: int = data[5]
	input.jump_pressed = (flags & 1) != 0
	input.jump_held = (flags & 2) != 0
	input.boost = (flags & 4) != 0
	input.handbrake = (flags & 8) != 0
	input.air_roll = (flags & 16) != 0
	input.tick = int(data.decode_u32(6))
	return input


static func _decode_byte(value: int) -> float:
	var signed_value: int = value - 256 if value > 127 else value
	return clampf(float(signed_value) / 127.0, -1.0, 1.0)
