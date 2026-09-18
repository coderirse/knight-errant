class_name DamageInfo
extends Resource

## Payload handed from an attacker's [Hitbox] to a target's [Hurtbox].
## A Resource (instead of a plain Dictionary) so attack data can be authored,
## duplicated per hit and reused by projectiles / spells later on.

@export var amount := 1
## Damage flavour, looked up in [DamageTypes] for per-layer multipliers and
## critability. Defaults to physical so existing callers keep their behaviour.
@export var type: StringName = &"physical"
## Resolved by the SHOOTER before the hit lands: when true, `amount` already
## carries the crit bonus. Kept as a flag so the receiver can flash harder.
@export var crit := false
## Horizontal push applied to the receiver.
@export var knockback_force := 260.0
## Zero means "derive it from the relative positions at hit time".
@export var knockback_direction := Vector2.ZERO
## How long the receiver is locked out of player/enemy control.
@export var stagger_time := 0.15
## Used for auto knockback direction and for spawning hit VFX.
@export var source_position := Vector2.ZERO
## Free-form tag: "nail", "spell", "spike", "boss_slam", ...
@export var tag := &"nail"
## Set by hazards/late-game enemies that ignore i-frames.
@export var ignores_invincibility := false


static func create(p_amount: int, p_source_position: Vector2, p_knockback := 260.0, p_tag := &"nail") -> DamageInfo:
	var info := DamageInfo.new()
	info.amount = p_amount
	info.source_position = p_source_position
	info.knockback_force = p_knockback
	info.tag = p_tag
	return info
