class_name Weapon
extends Node2D

## A weapon mounted on an actor's aim pivot. Owns its cooldown and spawns either
## bullets or a melee sweep.
##
## The weapon is a Node2D child of the wielder, positioned at the muzzle and
## rotated to the aim angle, so "where does the bullet come from" is just
## Muzzle.global_position. Both the player and (later) armed enemies use this
## same node — nothing here assumes a player.

signal fired(weapon: Weapon)
signal dry_fire(weapon: Weapon)

const PROJECTILE_SCENE := "res://scenes/weapons/projectile.tscn"

@export var data: WeaponData
## Where bullets spawn and melee sweeps are centred. Defaults to this node.
@export var muzzle_path: NodePath

@onready var muzzle: Node2D = get_node_or_null(muzzle_path) as Node2D

var energy: EnergyPool
var muzzle_offset := 8.0

var _cooldown_left := 0.0
var _melee_time_left := 0.0
var _melee_hitbox: Hitbox
var _source_is_player := false


func _ready() -> void:
	if muzzle == null:
		muzzle = self
	_melee_hitbox = get_node_or_null("MeleeHitbox") as Hitbox
	if _melee_hitbox != null:
		_melee_hitbox.deactivate()


func _process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)

	if _melee_time_left > 0.0:
		_melee_time_left -= delta
		if _melee_time_left <= 0.0 and _melee_hitbox != null:
			_melee_hitbox.deactivate()


func setup(weapon_data: WeaponData, energy_pool: EnergyPool, is_player_team: bool) -> void:
	data = weapon_data
	energy = energy_pool
	_source_is_player = is_player_team
	if is_inside_tree():
		_apply_data_to_nodes()


func can_fire() -> bool:
	if data == null or _cooldown_left > 0.0:
		return false
	if data.is_melee:
		return true
	return energy == null or energy.has_enough(data.energy_cost)


## Fires if possible. Returns true when a shot actually came out, so callers can
## distinguish "fired" from "out of energy" for feedback.
func try_fire(aim_direction: Vector2) -> bool:
	if not can_fire():
		if data != null and not data.is_melee and energy != null and not energy.has_enough(data.energy_cost):
			dry_fire.emit(self)
		return false

	if not data.is_melee and energy != null:
		energy.spend(data.energy_cost)

	_cooldown_left = data.cooldown_time()
	if data.is_melee:
		_fire_melee(aim_direction)
	else:
		_fire_ranged(aim_direction)
	fired.emit(self)
	return true


func aim_at(direction: Vector2) -> void:
	if direction.length_squared() < 0.0001:
		return
	rotation = direction.angle()
	# Keep the sprite upright: a flipped gun reads better than an upside-down one.
	if scale.y > 0.0 and absf(rotation) > PI * 0.5:
		scale.y = -1.0
	elif scale.y < 0.0 and absf(rotation) <= PI * 0.5:
		scale.y = 1.0


func _fire_ranged(aim_direction: Vector2) -> void:
	var packed := load(PROJECTILE_SCENE) as PackedScene
	if packed == null:
		push_error("Weapon: cannot load %s" % PROJECTILE_SCENE)
		return

	var origin := muzzle.global_position if muzzle != null else global_position
	# Fan the shots evenly across the spread arc so a 3-shot spread is
	# symmetric around the aim direction instead of biased to one side.
	var base_angle := aim_direction.angle()
	var spread := deg_to_rad(data.spread_degrees)
	for i in data.projectile_count:
		var offset := 0.0
		if data.projectile_count > 1:
			offset = -spread * 0.5 + spread * (float(i) / float(data.projectile_count - 1))
		var shot_angle := base_angle + offset

		var bullet := packed.instantiate() as Projectile
		bullet.direction = Vector2.RIGHT.rotated(shot_angle)
		bullet.speed = data.projectile_speed
		bullet.damage = data.damage
		bullet.knockback = data.knockback
		bullet.lifetime = data.projectile_lifetime
		bullet.pierce = data.pierce
		bullet.is_player_team = _source_is_player
		bullet.tag = &"bullet_player" if _source_is_player else &"bullet_enemy"
		bullet.global_position = origin
		bullet.modulate = data.bullet_tint
		bullet.scale = Vector2.ONE * data.bullet_scale
		_projectile_container().add_child(bullet)
		bullet.global_position = origin


func _fire_melee(aim_direction: Vector2) -> void:
	if _melee_hitbox == null:
		return
	_melee_hitbox.damage = data.damage
	_melee_hitbox.knockback_force = data.knockback

	# Place the sweep in front of the wielder and fan the hitbox out to a rough
	# arc by scaling its rectangle. A single rotated rectangle is enough for a
	# prototype; swap in several staggered hitboxes for a real arc.
	var angle := aim_direction.angle()
	rotation = angle
	var local_offset := Vector2(data.melee_range, 0.0)
	_melee_hitbox.position = local_offset
	_melee_hitbox.rotation = 0.0
	var shape := _melee_hitbox.get_child(0) as CollisionShape2D
	if shape != null and shape.shape is RectangleShape2D:
		var rect := shape.shape as RectangleShape2D
		rect.size = Vector2(data.melee_range, data.melee_range * 0.9)
		shape.position = Vector2(data.melee_range * 0.5, 0.0)

	_melee_hitbox.activate()
	_melee_time_left = data.melee_active_time
	# One-shot sweep: deactivation is driven by _process so it ends on time even
	# if the wielder stops firing.
	_schedule_melee_end()


func _schedule_melee_end() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var timer := tree.create_timer(data.melee_active_time, true, false, true)
	await timer.timeout
	if _melee_hitbox != null and is_instance_valid(_melee_hitbox):
		_melee_hitbox.deactivate()


## Bullets are added to the level, not to the weapon: a projectile parented to
## the player would inherit the player's motion and would be freed the moment the
## player dies or the room reloads.
func _projectile_container() -> Node:
	var container := get_tree().get_first_node_in_group(&"projectile_container")
	if container != null:
		return container
	return get_tree().current_scene


func _apply_data_to_nodes() -> void:
	if data != null and data.icon != null:
		for child in get_children():
			if child is Sprite2D:
				(child as Sprite2D).texture = data.icon
