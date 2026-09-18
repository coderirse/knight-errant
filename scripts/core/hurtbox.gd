class_name Hurtbox
extends Area2D

## The "can be damaged" volume. Owned by the player, enemies, breakable walls...
##
## Dependency direction is intentionally one-way: [Hitbox] looks for [Hurtbox],
## never the other way around. Two classes referencing each other by class_name
## makes GDScript complain about cyclic references, so keep it that way.

## Emitted once a hit is accepted (i.e. not blocked by i-frames or a shield).
signal hurt(info: DamageInfo)

## Owner flips this during death animations and scripted sequences.
@export var vulnerable := true
## Multiplier for weak points / armoured plates.
@export var damage_multiplier := 1.0
## Lets attackers tell the player apart from enemies (pogo, parry, lifesteal).
@export var is_player_team := false
## Shields and parry windows set this from their own state machine.
@export var blocking := false
## Optional Health that owns this box. When set, hits the Health would refuse
## (i-frames, already dead) are rejected here too, so [signal hurt] means
## "damage was actually dealt" and listeners can safely play hit reactions.
## Assign it in _ready(): hurtbox.health = $Health.
var health: Health = null


func receive_hit(info: DamageInfo) -> bool:
	if not vulnerable or blocking:
		return false
	if health != null and not _health_would_accept(info):
		return false
	var applied := info
	if not is_equal_approx(damage_multiplier, 1.0):
		applied = info.duplicate() as DamageInfo
		applied.amount = int(roundf(info.amount * damage_multiplier))
	hurt.emit(applied)
	return true


func _health_would_accept(info: DamageInfo) -> bool:
	if not health.is_alive():
		return false
	if health.invincible and not info.ignores_invincibility:
		return false
	return true
