class_name EnergyPool
extends Node

## Weapon ammunition, shared across every weapon the player carries.
##
## Soul Knight's energy bar is a single pool that all guns draw from, which is
## what makes weapon choice a resource decision instead of a cooldown timer: a
## shotgun that eats 8 per shot competes with the pistol that eats 1. A melee
## weapon costs nothing, so it doubles as the fallback when the bar is empty.
##
## Regenerates continuously; `regen_per_second` of 0 makes it finite.

signal changed(current: float, maximum: float)
signal depleted

@export var maximum := 200.0
@export var regen_per_second := 12.0
## Seconds before regeneration resumes after spending.
@export var regen_delay := 0.6
@export var starts_full := true

var current := 0.0

var _quiet_time := 0.0


func _ready() -> void:
	current = maximum if starts_full else 0.0
	changed.emit(current, maximum)


func _process(delta: float) -> void:
	if regen_per_second <= 0.0 or current >= maximum:
		return
	_quiet_time += delta
	if _quiet_time < regen_delay:
		return
	current = minf(current + regen_per_second * delta, maximum)
	changed.emit(current, maximum)


func has_enough(cost: float) -> bool:
	return cost <= 0.0 or current >= cost


## All-or-nothing: a weapon either fires and pays the full cost, or does not fire.
func spend(cost: float) -> bool:
	if not has_enough(cost):
		return false
	if cost <= 0.0:
		return true
	current = maxf(current - cost, 0.0)
	_quiet_time = 0.0
	changed.emit(current, maximum)
	if current <= 0.0:
		depleted.emit()
	return true


func refill(amount: float) -> float:
	var before := current
	current = minf(current + amount, maximum)
	var gained := current - before
	if gained > 0.0:
		changed.emit(current, maximum)
	return gained


func fill() -> void:
	current = maximum
	changed.emit(current, maximum)
