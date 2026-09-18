class_name RoomDoor
extends Area2D

## Doorway between two rooms of the same floor.
##
## The level is one scene with all rooms already instantiated, so "going through a
## door" is a teleport to the neighbouring room plus a camera move — not a scene
## load. That is why this node only needs to tell the Level which room to enter;
## there is no transition state to serialise.
##
## `locked` is set by Room while enemies are alive. A locked door still detects
## the player, but refuses to move them, so walking into it reads as "the way is
## blocked" instead of doing nothing at all.

@export var side := 0            # 0 right, 1 left, 2 bottom, 3 top (of the owning room)
@export var target_room := 0
@export var target_door := 0
@export var locked := false

var _cooldown := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_apply_lock_visual()


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


## Rooms call this when the encounter is cleared.
func set_locked(value: bool) -> void:
	if locked == value:
		return
	locked = value
	_apply_lock_visual()


func _apply_lock_visual() -> void:
	var visual := get_node_or_null("Visual") as ColorRect
	if visual == null:
		return
	visual.color = Color(0.85, 0.25, 0.25, 0.45) if locked else Color(0.95, 0.75, 0.25, 0.45)


func _on_body_entered(body: Node2D) -> void:
	if locked or _cooldown > 0.0:
		return
	if not (body is Player):
		return
	_cooldown = 0.6

	var level := _find_level()
	if level == null:
		return
	# Enter through the wall opposite this door: a right-side door (0) leads into
	# the neighbour's left side (1), and so on.
	level.move_player_to_room(target_room, side ^ 1)


func _find_level() -> Level:
	var node: Node = get_parent()
	while node != null:
		if node is Level:
			return node as Level
		node = node.get_parent()
	return null
