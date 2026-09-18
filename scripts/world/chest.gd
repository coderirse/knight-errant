class_name Chest
extends Area2D

## Treasure chest: opens on contact and drops a random ranged weapon as a floor
## pickup, plus some gold.
##
## Uses its own touched flag rather than a world flag, because a floor is
## regenerated from scratch each run — there is nothing to persist across visits.

@export var gold_reward := 25
@export var always_drops_weapon := true
@export var open_delay := 0.25

@onready var sprite: Sprite2D = $Sprite2D

var _opened := false


func _ready() -> void:
	add_to_group(&"chest")
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if _opened or not (body is Player):
		return
	_opened = true
	await open()


func open() -> void:
	if sprite != null:
		var tween := create_tween()
		tween.tween_property(sprite, "scale", Vector2(1.25, 0.8), 0.12)
		tween.tween_property(sprite, "scale", Vector2.ONE, 0.18)
		await tween.finished

	if RunState.active and gold_reward > 0:
		RunState.add_gold(gold_reward)

	if always_drops_weapon:
		_spawn_weapon_drop()

	Juice.shake_camera(2.0)


func _spawn_weapon_drop() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var weapon_id := WeaponRegistry.random_ranged_id(rng)
	var packed := load("res://scenes/world/weapon_pickup.tscn") as PackedScene
	if packed == null:
		return
	var drop := packed.instantiate() as Node2D
	drop.set(&"weapon_id", weapon_id)
	# Scatter the drop slightly so it does not spawn inside the chest's collider
	# and get collected in the same frame.
	drop.global_position = global_position + Vector2(rng.randf_range(-10.0, 10.0), 14.0)
	get_parent().add_child(drop)
