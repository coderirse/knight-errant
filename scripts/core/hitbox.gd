class_name Hitbox
extends Area2D

## The "deals damage" volume. Enabled for the active frames of an attack, or kept
## on permanently for contact damage (set always_active = true).
##
## Set collision_layer / collision_mask in the scene. The mask must contain the
## layers used by the Hurtboxes this box may hit — see the layer table in
## docs/roadmap.md.
##
## monitoring stays true for the node's whole life. Turning it off and on would
## delay detection by a physics frame, and a swing that starts while an enemy is
## already inside the volume would miss it. Instead the box is gated by an
## internal flag, and activate() does one explicit overlap query to catch
## whatever is already inside.

signal hit_landed(hurtbox: Hurtbox, info: DamageInfo)

@export var damage := 1
@export var knockback_force := 260.0
@export var stagger_time := 0.15
@export var tag := &"nail"
## True for contact damage (spikes, a body that hurts on touch), which never
## deactivates and may hit the same target again after it leaves and re-enters.
@export var always_active := false

var _active := false
var _already_hit: Array[Hurtbox] = []


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	_active = always_active


## Called at the start of an attack's active frames.
func activate() -> void:
	_already_hit.clear()
	_active = true
	# Anything already overlapping never emits area_entered, so sweep manually.
	for area in get_overlapping_areas():
		_on_area_entered(area)


func deactivate() -> void:
	_active = false


func is_active() -> bool:
	return _active


func _on_area_exited(area: Area2D) -> void:
	# Contact hitboxes never deactivate, so a target that leaves and comes back
	# must be hittable again. Swing hitboxes keep the list for the whole swing:
	# one swing damages a given target at most once no matter how it moves.
	if always_active:
		_already_hit.erase(area as Hurtbox)


func _on_area_entered(area: Area2D) -> void:
	if not _active or not (area is Hurtbox):
		return
	var hurtbox := area as Hurtbox
	if _already_hit.has(hurtbox):
		return
	_already_hit.append(hurtbox)

	var origin := global_position
	var owner_2d := owner as Node2D
	if owner_2d != null:
		origin = owner_2d.global_position

	var info := DamageInfo.create(damage, origin, knockback_force, tag)
	info.stagger_time = stagger_time
	var away := hurtbox.global_position - origin
	if away.length_squared() > 0.0001:
		info.knockback_direction = away.normalized()

	if hurtbox.receive_hit(info):
		hit_landed.emit(hurtbox, info)
