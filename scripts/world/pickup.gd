class_name Pickup
extends Area2D

## Gold / health / energy drop. Uses the same Area2D-on-player-body pattern as
## every other interactable in the project.

enum Kind { GOLD, HEALTH, ENERGY }

@export var kind: Kind = Kind.GOLD
@export var amount := 1
@export var bob_height := 3.0
## Auto-collect radius. Small so the player still has to walk over it.
@export var magnet_radius := 0.0

@onready var sprite: Sprite2D = $Sprite2D

var _bob_time := 0.0
var _base_y := 0.0
var _collected := false


func _ready() -> void:
	add_to_group(&"pickup")
	body_entered.connect(_on_body_entered)
	_base_y = sprite.position.y if sprite != null else 0.0


func _process(delta: float) -> void:
	if _collected or sprite == null:
		return
	_bob_time += delta
	sprite.position.y = _base_y + sin(_bob_time * 3.2) * bob_height


func _on_body_entered(body: Node2D) -> void:
	if _collected or not (body is Player):
		return
	var player := body as Player
	_collected = true

	match kind:
		Kind.GOLD:
			if RunState.active:
				RunState.add_gold(amount)
		Kind.HEALTH:
			player.health.heal(amount)
		Kind.ENERGY:
			player.energy.refill(float(amount))

	_play_collect_animation()


func _play_collect_animation() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.6, 1.6), 0.15)
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	tween.chain().tween_callback(queue_free)
