class_name InputBuffer
extends RefCounted
## Tick-stamped input history with redundancy. Clients send the last three
## inputs in every packet; the server applies each tick exactly once.

const REDUNDANCY := 3
const MAX_HISTORY := 240

var _by_tick: Dictionary = {}
var _last_applied: int = -1


func push(input: CarInput) -> void:
	_by_tick[input.tick] = input
	while _by_tick.size() > MAX_HISTORY:
		var oldest: int = 2147483647
		for tick: int in _by_tick.keys():
			oldest = mini(oldest, tick)
		_by_tick.erase(oldest)


func latest(count: int = REDUNDANCY) -> Array[CarInput]:
	var ticks: Array[int] = []
	for tick: int in _by_tick.keys():
		ticks.append(tick)
	ticks.sort()
	var out: Array[CarInput] = []
	var start: int = maxi(0, ticks.size() - count)
	for i in range(start, ticks.size()):
		out.append(_by_tick[ticks[i]] as CarInput)
	return out


func unacked(after_tick: int) -> Array[CarInput]:
	var ticks: Array[int] = []
	for tick: int in _by_tick.keys():
		if tick > after_tick:
			ticks.append(tick)
	ticks.sort()
	var out: Array[CarInput] = []
	for tick: int in ticks:
		out.append(_by_tick[tick] as CarInput)
	return out


## Server-side: apply every tick newer than the last one accepted.
func consume_new() -> Array[CarInput]:
	var ticks: Array[int] = []
	for tick: int in _by_tick.keys():
		if tick > _last_applied:
			ticks.append(tick)
	ticks.sort()
	var out: Array[CarInput] = []
	for tick: int in ticks:
		out.append(_by_tick[tick] as CarInput)
		_last_applied = tick
	return out


func mark_applied(tick: int) -> void:
	_last_applied = maxi(_last_applied, tick)


func last_tick() -> int:
	var newest: int = -1
	for tick: int in _by_tick.keys():
		newest = maxi(newest, tick)
	return newest


func prune(before_tick: int) -> void:
	for tick: int in _by_tick.keys():
		if tick < before_tick:
			_by_tick.erase(tick)


func clear() -> void:
	_by_tick.clear()
	_last_applied = -1


static func pack(inputs: Array[CarInput]) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(inputs.size())
	for input: CarInput in inputs:
		var data := input.serialize()
		buf.put_u8(data.size())
		buf.put_data(data)
	return buf.data_array


static func unpack(data: PackedByteArray) -> Array[CarInput]:
	var out: Array[CarInput] = []
	if data.size() < 1:
		return out
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	var count: int = buf.get_u8()
	for i in count:
		if buf.get_available_bytes() < 1:
			break
		var size: int = buf.get_u8()
		if size == 0 or buf.get_available_bytes() < size:
			break
		var chunk: PackedByteArray = buf.get_data(size)[1]
		out.append(CarInput.deserialize(chunk))
	return out
