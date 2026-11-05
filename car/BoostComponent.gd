class_name BoostComponent
extends Node
## Boost meter 0-100 with data-driven consumption and refills.

signal changed(amount: float)
signal depleted()

var tuning: CarTuning
var amount: float = 100.0


func setup(p_tuning: CarTuning) -> void:
	tuning = p_tuning
	amount = tuning.boost_capacity
	changed.emit(amount)


func add(value: float) -> void:
	if tuning == null:
		return
	var before := amount
	amount = clampf(amount + value, 0.0, tuning.boost_capacity)
	if not is_equal_approx(before, amount):
		changed.emit(amount)


func can_boost() -> bool:
	return tuning != null and amount > 0.0


## Consume for one physics step. Returns true when boost was actually applied.
func consume(delta: float) -> bool:
	if not can_boost():
		return false
	var before := amount
	amount = maxf(0.0, amount - tuning.boost_consumption * delta)
	changed.emit(amount)
	if amount <= 0.0:
		depleted.emit()
	return before > 0.0


func is_empty() -> bool:
	return amount <= 0.0
