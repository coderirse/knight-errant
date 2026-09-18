class_name Chaser
extends CharacterBody2D

## Melee enemy: walks straight at the player and damages on contact.
##
## Movement is a simple seek with separation from other enemies, no pathfinding.
## Soul Knight's rooms are open arenas with few obstacles, so direct seeking reads
## as aggressive rather than stupid; the separation term is what stops a mob from
## collapsing into a single overlapping blob.
##
## If a room later has real walls to navigate, swap _steer() for
## NavigationAgent2D — the rest of the class does not care how the velocity was
## chosen.

@export var max_speed := 58.0
@export var acceleration := 700.0
@export var contact_damage := 1
## How close the player must be before the enemy commits to a charge.
@export var aggro_radius := 200.0
## Enemies stop just short of the player so they do not shove them around.
@export var stop_distance := 12.0
@export var gold_drop := 3
@export var separation_radius := 18.0

@onready var health: Health = $Health
@onready var sprite: Sprite2D = $Sprite2D
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var hitbox: Hitbox = $Hitbox

## Set by Room when the enemy is spawned. Enemies live under Room/Actors, so
## get_parent() would return the Actors node rather than the room that needs to
## hear about the kill.
var room: Room = null

var _player: Node2D
var _knockback := Vector2.ZERO


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	floor_snap_length = 0.0
	add_to_group(&"enemy")

	health.depleted.connect(_on_depleted)
	health.damaged.connect(_on_damaged)
	hurtbox.hurt.connect(_on_hurt)
	hurtbox.health = health
	hurtbox.is_player_team = false
	hitbox.always_active = true

	hitbox.damage = contact_damage
	_resolve_player()


## Enemies are spawned by Room._ready() while the level is being generated, which
## is *before* Game creates the player. Looking the player up once in _ready()
## therefore caches null and the enemy stands still forever, so re-resolve on
## demand instead.
func _resolve_player() -> bool:
	if _player != null and is_instance_valid(_player):
		return true
	_player = get_tree().get_first_node_in_group(&"player") as Node2D
	return _player != null


func _physics_process(delta: float) -> void:
	if not health.is_alive():
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		move_and_slide()
		return

	# Knockback decays rather than being cancelled, so a hit visibly shoves the
	# enemy before it resumes chasing.
	_knockback = _knockback.move_toward(Vector2.ZERO, 900.0 * delta)

	var desired := Vector2.ZERO
	if _resolve_player() and is_instance_valid(_player):
		desired = _steer(_player.global_position)

	velocity = (velocity + desired * acceleration * delta).limit_length(max_speed) + _knockback
	move_and_slide()
	_update_visual()


func _steer(target: Vector2) -> Vector2:
	var to_target := target - global_position
	var distance := to_target.length()
	if distance > aggro_radius:
		return Vector2.ZERO
	if distance <= stop_distance:
		return Vector2.ZERO

	var seek := to_target.normalized()
	return (seek + _separation() * 0.8).normalized()


## Pushes away from nearby enemies so a group spreads into a ring instead of
## stacking on one pixel.
func _separation() -> Vector2:
	var push := Vector2.ZERO
	for other in get_tree().get_nodes_in_group(&"enemy"):
		if other == self or not (other is Node2D):
			continue
		var offset := global_position - (other as Node2D).global_position
		var distance := offset.length()
		if distance > 0.001 and distance < separation_radius:
			push += offset / distance * (1.0 - distance / separation_radius)
	return push


func _update_visual() -> void:
	if sprite == null:
		return
	if absf(velocity.x) > 1.0:
		sprite.scale.x = absf(sprite.scale.x) * signf(velocity.x)
	# A small bob while moving sells the walk without an animation.
	var bob := sin(Time.get_ticks_msec() * 0.012) * 1.0 if velocity.length() > 4.0 else 0.0
	sprite.position.y = bob


func _on_hurt(info: DamageInfo) -> void:
	if not health.apply_damage(info):
		return
	health.start_invincibility()
	_knockback = info.knockback_direction.normalized() * info.knockback_force


func _on_damaged(_amount: int, _absorbed: bool) -> void:
	sprite.modulate = Color(1.6, 0.8, 0.8)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.15)


func _on_depleted() -> void:
	hurtbox.vulnerable = false
	$Hurtbox/CollisionShape2D.set_deferred("disabled", true)
	$Hitbox/CollisionShape2D.set_deferred("disabled", true)
	$CollisionShape2D.set_deferred("disabled", true)

	if RunState.active:
		RunState.add_gold(gold_drop)

	if room != null and is_instance_valid(room):
		room.on_enemy_died(self)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.22)
	tween.tween_property(sprite, "scale", sprite.scale * 0.5, 0.22)
	tween.chain().tween_callback(queue_free)
