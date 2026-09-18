class_name CameraRig
extends Camera2D

## Follows the player in a top-down arena and shakes on impact.
##
## Two things are specific to this genre:
##   - the camera leads the *aim* slightly, not the movement, so the player can
##     see what they are shooting at;
##   - bounds are the whole floor, not one room, because rooms are physically
##     adjacent and the camera should glide across the doorway rather than snap.
##
## When the project grows, Phantom Camera (MIT) is a drop-in replacement that also
## handles room transitions, dead zones and follow groups.

@export var follow_speed := 9.0
@export var aim_lead_distance := 26.0
@export var aim_lead_speed := 5.0
@export var shake_decay := 8.0
@export var max_shake_offset := 24.0
@export var pixel_snap := true

var _target: Node2D
var _lead := Vector2.ZERO
var _shake := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(&"camera_rig")
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	position_smoothing_enabled = true
	position_smoothing_speed = follow_speed
	_rng.randomize()
	if _target == null:
		_target = get_tree().get_first_node_in_group(&"player") as Node2D
	if _target != null:
		global_position = _target.global_position


func set_target(node: Node2D) -> void:
	_target = node
	if node != null:
		global_position = node.global_position


func snap_to_target() -> void:
	if _target != null:
		global_position = _target.global_position
		_lead = Vector2.ZERO
	reset_smoothing()


func set_room_bounds(bounds: Rect2) -> void:
	limit_left = int(bounds.position.x)
	limit_top = int(bounds.position.y)
	limit_right = int(bounds.position.x + bounds.size.x)
	limit_bottom = int(bounds.position.y + bounds.size.y)
	reset_smoothing()


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _physics_process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_target = get_tree().get_first_node_in_group(&"player") as Node2D
		return

	# Lead toward where the player is aiming. Read defensively: the camera must
	# not break if the target stops being a Player (menus, cutscenes, replays).
	var aim := Vector2.ZERO
	if _target is Player:
		aim = (_target as Player).aim_direction
	var desired_lead := aim * aim_lead_distance
	_lead = _lead.lerp(desired_lead, clampf(aim_lead_speed * delta, 0.0, 1.0))

	var desired := _target.global_position + _lead
	if pixel_snap:
		desired = desired.round()
	global_position = desired

	if _shake > 0.001:
		_shake = maxf(_shake - shake_decay * delta, 0.0)
		offset = Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * minf(_shake, max_shake_offset)
	elif offset != Vector2.ZERO:
		offset = offset.lerp(Vector2.ZERO, clampf(14.0 * delta, 0.0, 1.0))
