class_name Projectile
extends Area2D

## A bullet. Travels in a straight line, damages the first hostile Hurtbox it
## overlaps, and dies on walls.
##
## Wall detection is a manual raycast rather than an Area2D overlap test on the
## world layer: a fast bullet moves further in one physics frame than a wall is
## thick, so an overlap check would let it tunnel through. The ray spans the exact
## distance travelled this frame, so it cannot.

signal expired

@export var speed := 300.0
@export var damage := 1
@export var knockback := 130.0
@export var lifetime := 1.4
## Extra enemies the bullet passes through before stopping.
@export var pierce := 0
@export var is_player_team := true
@export var tag := &"bullet"
## Damage flavour, resolved against DamageTypes when the hit lands.
@export var type: StringName = &"physical"
## Set by the shooter; the receiver only reads it to flash harder.
@export var crit := false
## Wall bounces left. Each bounce reflects off the wall's real normal, taken
## from the same raycast that stops non-bouncing bullets.
@export var bounce_count := 0
## Area damage dealt when this bullet dies. 0 radius disables it.
@export var explode_radius := 0.0
@export var explode_damage := 0
## Child bullets fanned out when this bullet dies WITHOUT hitting a target
## (expiry or wall), so splitting into a wall is not a free reset.
@export var split_count := 0
## Collision layer the terrain lives on, used for the wall raycast.
@export var world_mask := 1
## Layer of the opposing team's Hurtbox. Player bullets look for enemy hurtboxes
## (layer 16) and enemy bullets look for the player's (layer 4); a single shared
## mask would make one side's bullets unable to hit anything.
@export var enemy_hurtbox_layer := 16
@export var player_hurtbox_layer := 4

var direction := Vector2.RIGHT

var _hits := 0
var _life := 0.0
var _spent := false


func _ready() -> void:
	# Team decides what this bullet can touch, so set the mask here rather than
	# relying on the scene's default.
	collision_mask = enemy_hurtbox_layer if is_player_team else player_hurtbox_layer
	area_entered.connect(_on_area_entered)
	rotation = direction.angle()


func _physics_process(delta: float) -> void:
	if _spent:
		return

	_life += delta
	if _life >= lifetime:
		_despawn(true)
		return

	var step := direction * speed * delta

	# Wall check first: raycast the exact distance about to be travelled.
	var space := get_world_2d().direct_space_state
	if space != null:
		var query := PhysicsRayQueryParameters2D.create(global_position, global_position + step, world_mask)
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			if bounce_count > 0:
				bounce_count -= 1
				var normal: Vector2 = hit.get("normal", Vector2.ZERO)
				if normal.length_squared() < 0.5:
					normal = -direction
				direction = direction.bounce(normal)
				rotation = direction.angle()
				global_position = hit.position + normal * 0.5
				return
			global_position = hit.position
			_despawn(true)
			return

	global_position += step


func _on_area_entered(area: Area2D) -> void:
	if _spent or not (area is Hurtbox):
		return
	var hurtbox := area as Hurtbox
	# Bullets only hurt the other team, so a player bullet never clips the player
	# and an enemy bullet never hits the enemy that fired it.
	if hurtbox.is_player_team == is_player_team:
		return

	var info := DamageInfo.create(damage, global_position, knockback, tag)
	info.knockback_direction = direction
	info.type = type
	info.crit = crit
	hurtbox.receive_hit(info)

	_hits += 1
	if _hits > pierce:
		# Spent on a target: it explodes on impact but does not split — a split
		# is what a bullet does instead of reaching someone.
		_despawn(false)


func _despawn(can_split: bool) -> void:
	if _spent:
		return
	_spent = true
	if explode_radius > 0.0:
		_explode()
	if can_split and split_count > 0:
		_split()
	# _despawn() is reached from area_entered, and Godot forbids mutating
	# monitoring during physics signal dispatch. Defer the flag, then free.
	set_deferred("monitoring", false)
	expired.emit()
	queue_free()


## Area damage to the opposing team only, falling off to nothing at the rim is
## deliberately NOT modelled: a flat radius reads better at this sprite scale
## and keeps the numbers honest in the tuning panel.
func _explode() -> void:
	var targets: Array[Node] = []
	if is_player_team:
		targets.assign(get_tree().get_nodes_in_group(&"enemy"))
	else:
		var player := get_tree().get_first_node_in_group(&"player")
		if player != null:
			targets.append(player)
	for target in targets:
		var hurtbox := target.get_node_or_null("Hurtbox") as Hurtbox
		if hurtbox == null:
			continue
		if hurtbox.global_position.distance_to(global_position) > explode_radius:
			continue
		var info := DamageInfo.create(
			explode_damage if explode_damage > 0 else damage,
			global_position, knockback * 0.5, &"explosion")
		info.type = type
		var away := hurtbox.global_position - global_position
		info.knockback_direction = away.normalized() if away.length_squared() > 0.001 else Vector2.UP
		hurtbox.receive_hit(info)


func _split() -> void:
	var container := get_tree().get_first_node_in_group(&"projectile_container")
	if container == null:
		# Same fallback Weapon uses: outside a level (tests) bullets still need
		# a home, or splitting would silently spawn nothing.
		container = get_tree().current_scene
	if container == null:
		return
	var packed := load("res://scenes/weapons/projectile.tscn") as PackedScene
	if packed == null:
		return
	var base_angle := direction.angle()
	var fan := deg_to_rad(90.0)
	for i in split_count:
		var t := 0.0 if split_count == 1 else float(i) / float(split_count - 1) - 0.5
		var child := packed.instantiate() as Projectile
		child.direction = Vector2.RIGHT.rotated(base_angle + t * fan)
		child.speed = speed * 0.8
		child.damage = damage
		child.knockback = knockback
		child.lifetime = lifetime * 0.6
		child.pierce = pierce
		child.is_player_team = is_player_team
		child.tag = tag
		child.type = type
		child.global_position = global_position
		child.modulate = modulate
		container.add_child(child)
		child.global_position = global_position
