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
		_despawn()
		return

	var step := direction * speed * delta

	# Wall check first: raycast the exact distance about to be travelled.
	var space := get_world_2d().direct_space_state
	if space != null:
		var query := PhysicsRayQueryParameters2D.create(global_position, global_position + step, world_mask)
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		if not hit.is_empty():
			global_position = hit.position
			_despawn()
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
	hurtbox.receive_hit(info)

	_hits += 1
	if _hits > pierce:
		_despawn()


func _despawn() -> void:
	if _spent:
		return
	_spent = true
	# _despawn() is reached from area_entered, and Godot forbids mutating
	# monitoring during physics signal dispatch. Defer the flag, then free.
	set_deferred("monitoring", false)
	expired.emit()
	queue_free()
