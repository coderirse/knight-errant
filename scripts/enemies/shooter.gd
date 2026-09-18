class_name Shooter
extends CharacterBody2D

## Ranged enemy: keeps its distance from the player, strafes, and fires bullets
## on a cooldown.
##
## The interesting part is the spacing behaviour. A shooter that only backs away
## gets pinned in a corner; one that only strafes is trivial to walk into. This
## one holds a ring: too close and it retreats, too far and it closes, and while
## in the accepted band it circles the player, so the player has to lead their
## shots and reposition.

@export var max_speed := 46.0
@export var acceleration := 560.0
## Distance the enemy tries to hold from the player.
@export var preferred_distance := 120.0
## Half-width of the accepted band around preferred_distance.
@export var distance_tolerance := 30.0
@export var aggro_radius := 260.0

@export_group("Gun")
@export var weapon_id: StringName = &"enemy_pistol"
@export var fire_interval := 1.6
## Random jitter added to the interval so a group does not fire in lockstep.
@export var fire_interval_jitter := 0.5
## Don't shoot until the player is inside this radius, so distant enemies idle.
@export var fire_range := 240.0
## Seconds of "aiming" before the shot, giving the player time to react.
@export var telegraph_time := 0.35
@export var gold_drop := 5

@onready var health: Health = $Health
@onready var sprite: Sprite2D = $Sprite2D
@onready var hurtbox: Hurtbox = $Hurtbox

## Set by Room when the enemy is spawned. Enemies live under Room/Actors, so
## get_parent() would return the Actors node rather than the room that needs to
## hear about the kill.
var room: Room = null

var _player: Node2D
var _knockback := Vector2.ZERO
var _fire_timer := 0.0
var _telegraph_left := 0.0
var _strafe_sign := 1
var _mount: Node2D
var _weapon: Weapon
var _energy: EnergyPool


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	floor_snap_length = 0.0
	add_to_group(&"enemy")

	health.depleted.connect(_on_depleted)
	health.damaged.connect(_on_damaged)
	hurtbox.hurt.connect(_on_hurt)
	hurtbox.health = health
	hurtbox.is_player_team = false

	_player = null
	_strafe_sign = 1 if randf() < 0.5 else -1
	_fire_timer = randf_range(0.3, fire_interval)

	_setup_weapon()
	_resolve_player()


## Enemies are spawned by Room._ready() while the level is being generated, which
## is *before* Game creates the player. Looking the player up once in _ready()
## therefore caches null and the enemy never fires, so re-resolve on demand.
func _resolve_player() -> bool:
	if _player != null and is_instance_valid(_player):
		return true
	_player = get_tree().get_first_node_in_group(&"player") as Node2D
	return _player != null


## Enemies run their own EnergyPool (left at 0 regen) so they share the exact
## same Weapon node the player uses, without drawing on the player's bar.
func _setup_weapon() -> void:
	var data := WeaponRegistry.load_data(weapon_id)
	if data == null:
		return
	_energy = EnergyPool.new()
	_energy.maximum = 1000.0
	_energy.regen_per_second = 0.0
	_energy.starts_full = true
	add_child(_energy)

	_mount = Node2D.new()
	_mount.name = "AimPivot"
	add_child(_mount)

	_weapon = Weapon.new()
	_weapon.name = "Weapon"
	_weapon.position = Vector2(7, 0)
	_mount.add_child(_weapon)
	_weapon.setup(data, _energy, false)


func _physics_process(delta: float) -> void:
	_tick_fire(delta)

	if not health.is_alive():
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		move_and_slide()
		return

	_knockback = _knockback.move_toward(Vector2.ZERO, 900.0 * delta)

	var desired := Vector2.ZERO
	var aim := Vector2.RIGHT
	if _resolve_player() and is_instance_valid(_player):
		var to_player := _player.global_position - global_position
		aim = to_player.normalized() if to_player.length_squared() > 0.001 else Vector2.RIGHT
		desired = _steer(to_player)

	velocity = (velocity + desired * acceleration * delta).limit_length(max_speed) + _knockback
	move_and_slide()

	if _mount != null:
		_mount.rotation = aim.angle()
	_update_visual(desired)


## Ring-holding: retreat when too close, advance when too far, strafe in the band.
func _steer(to_player: Vector2) -> Vector2:
	var distance := to_player.length()
	if distance > aggro_radius:
		return Vector2.ZERO

	var radial := to_player.normalized()
	var tangent := Vector2(-radial.y, radial.x) * _strafe_sign

	if distance < preferred_distance - distance_tolerance:
		return -radial                      # too close: back off
	if distance > preferred_distance + distance_tolerance:
		return radial                       # too far: close in
	return tangent                          # in the band: circle


func _tick_fire(delta: float) -> void:
	if _weapon == null or not health.is_alive():
		return

	_fire_timer -= delta

	if _telegraph_left > 0.0:
		_telegraph_left -= delta
		if _telegraph_left <= 0.0:
			_weapon.try_fire(_aim_vector())
		return

	if _fire_timer > 0.0:
		return

	if not _resolve_player() or not is_instance_valid(_player):
		return
	var distance := global_position.distance_to(_player.global_position)
	if distance > fire_range:
		_fire_timer = 0.35
		return

	# Telegraph before shooting: flash, then fire. Telegraphed attacks are what
	# make a bullet-hell room fair.
	_telegraph_left = telegraph_time
	_fire_timer = fire_interval + randf_range(0.0, fire_interval_jitter)
	_flash_telegraph()


func _aim_vector() -> Vector2:
	if _player == null or not is_instance_valid(_player):
		return Vector2.RIGHT
	var to_player := _player.global_position - global_position
	return to_player.normalized() if to_player.length_squared() > 0.001 else Vector2.RIGHT


func _flash_telegraph() -> void:
	if sprite == null:
		return
	sprite.modulate = Color(1.5, 1.2, 0.7)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color.WHITE, telegraph_time)


func _update_visual(move_direction: Vector2) -> void:
	if sprite == null:
		return
	if absf(move_direction.x) > 0.1:
		sprite.scale.x = absf(sprite.scale.x) * signf(move_direction.x)
	var bob := sin(Time.get_ticks_msec() * 0.01) * 1.0 if velocity.length() > 4.0 else 0.0
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
	$CollisionShape2D.set_deferred("disabled", true)
	if _mount != null:
		_mount.queue_free()

	if RunState.active:
		RunState.add_gold(gold_drop)

	if room != null and is_instance_valid(room):
		room.on_enemy_died(self)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.22)
	tween.tween_property(sprite, "scale", sprite.scale * 0.5, 0.22)
	tween.chain().tween_callback(queue_free)
