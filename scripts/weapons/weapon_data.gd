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

@export_group("Ammo")
## Rounds in one magazine. -1 means no magazine at all (melee, or a weapon that
## runs on the energy pool alone). Reserve ammo is infinite: reloading costs
## time, not resources.
@export var ammo_capacity := -1
@export var reload_time := 1.2
## Start reloading the moment the magazine empties, without waiting for the key.
@export var auto_reload := true

@export_group("Scatter")
## Scatter grows from spread_degrees toward this angle while shots are fired in
## quick succession, and recovers when firing stops. 0 keeps spread constant.
@export var scatter_final_degrees := 0.0
## Degrees of scatter added per shot.
@export var scatter_per_shot := 4.0
## Degrees of scatter recovered per second once firing stops.
@export var scatter_recovery := 30.0

@export_group("Damage type")
## Flavour looked up in DamageTypes for per-layer multipliers and critability.
@export var damage_type: StringName = &"physical"
@export var crit_rate := 0.0
## Extra damage fraction on a crit: 0.5 means a crit hits for 1.5x.
@export var crit_bonus := 0.5

@export_group("Bullet behaviour")
## Wall bounces left per bullet.
@export var bounce_count := 0
## Area damage on bullet expiry. 0 radius disables the whole behaviour.
@export var explode_radius := 0.0
@export var explode_damage := 0
## Child bullets spawned in a fan when the parent expires.
@export var split_count := 0

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
	var tail := "  melee" if is_melee else "  %d/s  energy %d" % [int(fire_rate), int(energy_cost)]
	if not is_melee and ammo_capacity >= 0:
		tail += "  mag %d" % ammo_capacity
	return "%s  dmg %d%s" % [display_name, damage, tail]
