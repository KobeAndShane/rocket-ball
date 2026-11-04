class_name BoostComponent
extends Node
## Boost meter. Pure state + rates, emits signals so HUD never polls.

signal changed(amount: float, max_amount: float)
signal depleted
signal filled

@export var max_boost: float = 100.0
@export var consumption_per_second: float = 33.3
@export var enabled: bool = true
@export var unlimited: bool = false

var amount: float = 100.0
var _was_empty: bool = false
var _was_full: bool = true


func _ready() -> void:
	amount = max_boost
	_was_full = true


func set_tuning(tuning: CarTuning) -> void:
	max_boost = tuning.boost_max
	consumption_per_second = tuning.boost_consumption
	amount = max_boost


## Consumes one physics tick of boost. Returns true when boost was available.
func consume(delta: float) -> bool:
	if not enabled:
		return false
	if unlimited:
		_set_amount(max_boost)
		return true
	if amount <= 0.0:
		if not _was_empty:
			_was_empty = true
			depleted.emit()
		return false
	var before := amount
	amount = maxf(0.0, amount - consumption_per_second * delta)
	if not is_equal_approx(before, amount):
		changed.emit(amount, max_boost)
	if amount <= 0.0 and not _was_empty:
		_was_empty = true
		depleted.emit()
	return before > 0.0


func add(value: float, allow_over_max: bool = false) -> void:
	if not enabled or unlimited:
		return
	var cap: float = max_boost if not allow_over_max else max_boost * 1.5
	amount = clampf(amount + value, 0.0, cap)
	changed.emit(amount, max_boost)
	if amount >= max_boost and not _was_full:
		_was_full = true
		filled.emit()
	_was_empty = amount <= 0.0


func set_amount(value: float) -> void:
	_set_amount(clampf(value, 0.0, max_boost))


func _set_amount(value: float) -> void:
	if is_equal_approx(amount, value):
		return
	amount = value
	changed.emit(amount, max_boost)


func reset() -> void:
	amount = max_boost
	_was_empty = false
	_was_full = true
	changed.emit(amount, max_boost)


func fraction() -> float:
	return 0.0 if max_boost <= 0.0 else amount / max_boost


func is_empty() -> bool:
	return amount <= 0.001
