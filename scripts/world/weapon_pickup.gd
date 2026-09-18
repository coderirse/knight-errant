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

@export_group("Thrown")
@export var thrown_speed := 260.0
@export var thrown_damage := 2
@export var thrown_time := 0.9

@onready var sprite: Sprite2D = $Sprite2D

var _armed := false
var _bob_time := 0.0
var _base_y := 0.0
var _thrown := false
var _thrown_dir := Vector2.RIGHT
var _thrown_speed_now := 0.0
var _thrown_left := 0.0
var _thrown_hit := {}


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
	if _thrown:
		# The arming timer from _ready may fire mid-flight; a flying weapon is
		# not loot until it lands.
		_armed = false
		_thrown_left -= delta
		_thrown_speed_now = maxf(_thrown_speed_now - 420.0 * delta, 0.0)
		global_position += _thrown_dir * _thrown_speed_now * delta
		sprite.rotation += 14.0 * delta
		if _thrown_left <= 0.0 or _thrown_speed_now <= 1.0:
			_land()
		return
	sprite.rotation = 0.0
	_bob_time += delta
	sprite.position.y = _base_y + sin(_bob_time * 3.0) * bob_height


## Turns a resting pickup into a flying one. Called by Player right after the
## node enters the tree, so _ready has already run.
func launch(direction: Vector2, at: Vector2) -> void:
	_thrown = true
	_thrown_dir = direction.normalized() if direction.length_squared() > 0.001 else Vector2.RIGHT
	_thrown_speed_now = thrown_speed
	_thrown_left = thrown_time
	global_position = at
	# Enemies live on layer 8; a resting pickup only listens for the player.
	collision_mask = 2 | 8


func _land() -> void:
	_thrown = false
	collision_mask = 2
	sprite.rotation = 0.0
	var timer := get_tree().create_timer(pickup_delay, true, false, true)
	timer.timeout.connect(func(): _armed = true)


func _apply_icon() -> void:
	if sprite == null:
		return
	var data := WeaponRegistry.load_data(weapon_id)
	if data != null and data.icon != null:
		sprite.texture = data.icon


func _on_body_entered(body: Node2D) -> void:
	if _thrown:
		# A flying weapon hits each enemy once, then passes on.
		if body.is_in_group(&"enemy") and not _thrown_hit.has(body.get_instance_id()):
			_thrown_hit[body.get_instance_id()] = true
			var hurtbox := body.get_node_or_null("Hurtbox") as Hurtbox
			if hurtbox != null:
				var info := DamageInfo.create(thrown_damage, global_position, 160.0, &"thrown_weapon")
				info.knockback_direction = _thrown_dir
				hurtbox.receive_hit(info)
		return
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
