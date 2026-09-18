class_name WeaponPickup
extends Area2D

## A weapon lying on the floor. Walking over it swaps it into the player's hands,
## dropping whatever was equipped in that slot back onto the ground.
##
## The swap-in-place behaviour (rather than "refuse if full") is what makes floor
## loot a real decision in a run: you are always trading, never just collecting.

@export var weapon_id: StringName = &"pistol"
## Seconds before the pickup can be collected, so a chest drop does not get
## instantly re-collected by the chest's opener.
@export var pickup_delay := 0.8
@export var bob_height := 3.0

@onready var sprite: Sprite2D = $Sprite2D

var _armed := false
var _bob_time := 0.0
var _base_y := 0.0


func _ready() -> void:
	add_to_group(&"weapon_pickup")
	body_entered.connect(_on_body_entered)
	_apply_icon()
	_base_y = sprite.position.y if sprite != null else 0.0

	var timer := get_tree().create_timer(pickup_delay, true, false, true)
	timer.timeout.connect(func(): _armed = true)


func _process(delta: float) -> void:
	if sprite == null:
		return
	_bob_time += delta
	sprite.position.y = _base_y + sin(_bob_time * 3.0) * bob_height


func _apply_icon() -> void:
	if sprite == null:
		return
	var data := WeaponRegistry.load_data(weapon_id)
	if data != null and data.icon != null:
		sprite.texture = data.icon


func _on_body_entered(body: Node2D) -> void:
	if not _armed or not (body is Player):
		return
	var player := body as Player
	var dropped := player.pick_up_weapon(weapon_id)
	if dropped == null:
		return

	RunState.remember_weapon(weapon_id)

	# Put the displaced weapon on the floor where this one was, so the trade is
	# reversible without a menu.
	var previous := StringName(player.get_meta(&"last_dropped_weapon", &""))
	if previous != &"":
		var packed := load("res://scenes/world/weapon_pickup.tscn") as PackedScene
		if packed != null:
			var drop := packed.instantiate() as Node2D
			drop.set(&"weapon_id", previous)
			drop.global_position = global_position
			get_parent().add_child(drop)

	queue_free()
