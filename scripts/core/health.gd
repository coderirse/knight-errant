class_name Health
extends Node

## Hit-point component shared by the player and every enemy.
##
## Two layers, matching Soul Knight's readout: armour absorbs damage first and
## regenerates on its own after a quiet period, health does not come back. That
## split is what makes the shield an interesting resource — it rewards breaking
## contact rather than tanking.
##
## Enemies leave maximum_armor at 0 and behave like a plain health pool.

signal changed(current: int, maximum: int)
signal armor_changed(current: int, maximum: int)
signal damaged(amount: int, absorbed_by_armor: bool)
signal depleted
signal healed(amount: int, current: int)

@export var maximum := 5
## Extra buffer in front of health. 0 disables the whole armour mechanic.
@export var maximum_armor := 0
## Seconds without taking damage before armour starts refilling.
@export var armor_regen_delay := 3.0
## Armour points restored per second once regeneration starts.
@export var armor_regen_rate := 1.0
## Player uses ~0.8s. Enemies that should be punishable use 0.0-0.2s.
@export var invincibility_time := 0.8
@export var starts_full := true

var current := 0
var armor := 0
var invincible := false

var _iframe_left := 0.0
var _quiet_time := 0.0
## Fractional armour points banked toward the next whole point. Kept separate
## from `_quiet_time` because the two answer different questions: how long has
## it been quiet, and how much of the next point is paid for.
var _regen_progress := 0.0


func _ready() -> void:
	current = maximum if starts_full else 0
	armor = maximum_armor if starts_full else 0
	changed.emit(current, maximum)
	armor_changed.emit(armor, maximum_armor)


func _process(delta: float) -> void:
	if _iframe_left > 0.0:
		_iframe_left = maxf(_iframe_left - delta, 0.0)
		if is_zero_approx(_iframe_left):
			invincible = false

	if maximum_armor > 0 and armor < maximum_armor and current > 0:
		_quiet_time += delta
		if _quiet_time >= armor_regen_delay:
			# Rate is points per *second*, not per frame: this has to stay correct
			# on a 144 Hz display, where a per-frame +1 refilled 2.4x faster.
			_regen_progress += armor_regen_rate * delta
			while armor < maximum_armor and _regen_progress >= 1.0:
				_regen_progress -= 1.0
				armor += 1
				armor_changed.emit(armor, maximum_armor)
	else:
		# A full (or absent) shield banks nothing — otherwise the progress saved
		# up while it was full would burst out the moment one point was lost.
		_regen_progress = 0.0


## Returns true when the damage was actually applied. Armour soaks the hit first;
## only the overflow reaches health.
func apply_damage(info: DamageInfo) -> bool:
	if current <= 0:
		return false
	if invincible and not info.ignores_invincibility:
		return false

	_quiet_time = 0.0
	# Partial regen progress dies with the quiet period; otherwise a hit taken
	# just before the next point would be paid for by the timer it already ran.
	_regen_progress = 0.0
	# Damage flavour decides how fast each layer melts (DamageTypes). Overflow
	# carries to the next layer in BASE units, the way GunfireDungeon's
	# DamageManager does it: (layer_damage - layer_pool) / layer_multiplier.
	# With every multiplier at 1 (physical) this is exactly the old behaviour.
	var absorbed := false
	var overflow := float(info.amount)
	if armor > 0:
		var armor_multiplier := DamageTypes.armor_multiplier(info.type)
		var armor_damage := float(info.amount) * armor_multiplier
		var armor_before := armor
		var soaked := mini(armor_before, roundi(armor_damage))
		armor = armor_before - soaked
		absorbed = true
		armor_changed.emit(armor, maximum_armor)
		overflow = maxf(0.0, (armor_damage - float(armor_before)) / armor_multiplier)

	if overflow > 0.0:
		var health_damage := maxi(1, roundi(overflow * DamageTypes.health_multiplier(info.type)))
		current = maxi(current - health_damage, 0)
		changed.emit(current, maximum)

	damaged.emit(info.amount, absorbed)
	if current == 0:
		depleted.emit()
	return true


## Returns the amount actually restored. Healing never revives: a depleted
## Health is dead for good, and the respawn flow is what brings the player back.
func heal(amount: int) -> int:
	if current <= 0:
		return 0
	var before := current
	current = mini(current + amount, maximum)
	var gained := current - before
	if gained > 0:
		healed.emit(gained, current)
		changed.emit(current, maximum)
	return gained


func restore_armor(amount: int) -> int:
	if current <= 0 or maximum_armor <= 0:
		return 0
	var before := armor
	armor = mini(armor + amount, maximum_armor)
	var gained := armor - before
	if gained > 0:
		armor_changed.emit(armor, maximum_armor)
	return gained


func start_invincibility(duration := -1.0) -> void:
	invincible = true
	_iframe_left = invincibility_time if duration < 0.0 else duration


func set_maximum(value: int, refill := false) -> void:
	maximum = maxi(value, 1)
	current = maximum if refill else mini(current, maximum)
	changed.emit(current, maximum)


func is_alive() -> bool:
	return current > 0


## Total effective hit points, armour included. Used by tests and UI.
func effective_total() -> int:
	return current + armor
