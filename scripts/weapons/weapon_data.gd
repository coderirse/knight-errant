class_name WeaponData
extends Resource

## Stats for one weapon. Everything that distinguishes a pistol from a shotgun
## lives here, so adding a weapon is authoring a .tres — not writing code.
##
## Ranged weapons fire `projectile_count` bullets per shot in a fan of
## `spread_degrees`; melee weapons don't spawn bullets at all, they sweep a
## hitbox in front of the wielder (see Weapon._fire_melee()).

@export var id: StringName = &"pistol"
@export var display_name := "Pistol"
@export var icon: Texture2D
## Damage per bullet, or per melee swing.
@export var damage := 1
## Shots per second. Melee weapons use this as swings per second.
@export var fire_rate := 4.0
## Extra seconds after the cooldown before the next shot is allowed. 0 for
## automatic feel; raise it for heavy weapons that should punish spamming.
@export var recovery := 0.0
## Total fan angle. 0 for a single accurate shot.
@export var spread_degrees := 0.0
@export var projectile_count := 1
@export var projectile_speed := 300.0
@export var projectile_lifetime := 1.4
## Extra enemies a bullet passes through before stopping.
@export var pierce := 0
@export var knockback := 130.0
## Energy drawn from the shared pool per shot. Melee is free by design, which is
## what makes it the fallback when the bar runs dry.
@export var energy_cost := 1.0

@export_group("Melee")
@export var is_melee := false
## Reach of the swing, measured from the wielder's centre.
@export var melee_range := 22.0
@export var melee_arc_degrees := 100.0
## How long the swing hitbox stays active.
@export var melee_active_time := 0.12

## Colours let the placeholder projectiles read differently per weapon without
## needing real art.
@export var bullet_tint := Color(1, 1, 1, 1)
@export var bullet_scale := 1.0


func cooldown_time() -> float:
	if fire_rate <= 0.0:
		return 1.0
	return 1.0 / fire_rate + recovery


func describe() -> String:
	return "%s  dmg %d  %s%s" % [
		display_name,
		damage,
		"melee" if is_melee else "%d/s" % int(fire_rate),
		"" if is_melee else "  energy %d" % int(energy_cost),
	]
