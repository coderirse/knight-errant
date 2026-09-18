class_name Boss
extends CharacterBody2D

## The floor's gatekeeper: a large two-phase enemy that stands between the player
## and the next floor. Killing it is what clears the exit room, so every run ends
## its floor here.
##
## Two phases, split by remaining health:
##   Phase 1 — slow pursuit, periodic radial bullet rings.
##   Phase 2 (at phase2_threshold) — faster pursuit, adds an aimed volley on a
##   shorter clock. The change of pace is the telegraph: the player sees the boss
##   speed up and knows the endgame has started.
##
## Every number is an @export so the F2 tuning panel can reach it while playing —
## the feel of this fight is a feel-stage decision that must not be frozen in a
## constant (roadmap §10: M1 不要跳).

@export var max_speed := 34.0
@export var acceleration := 420.0
## How close the player must be before the boss commits to pursuing.
@export var aggro_radius := 420.0
@export var stop_distance := 22.0
@export var contact_damage := 2
@export var gold_drop := 40

@export_group("Health")
@export var base_health := 40
@export var health_per_floor := 12

@export_group("Phase 2")
## Fraction of maximum health at or below which phase 2 begins.
@export var phase2_threshold := 0.5
@export var phase2_speed_multiplier := 1.7

@export_group("Radial burst")
@export var burst_count := 8
@export var burst_speed := 130.0
@export var burst_damage := 1
@export var burst_interval := 2.6
@export var burst_bullet_lifetime := 2.0

@export_group("Aimed volley (phase 2 only)")
@export var volley_count := 3
@export var volley_spread_degrees := 18.0
@export var volley_speed := 200.0
@export var volley_interval := 1.7
## Do not attack at all beyond this distance — an off-room player is not a target.
@export var fire_range := 340.0
## Seconds of flash before each attack, so the patterns are dodgeable by design.
@export var telegraph_time := 0.4

@onready var health: Health = $Health
@onready var sprite: Sprite2D = $Sprite2D
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var hitbox: Hitbox = $Hitbox

## Set by Room when the boss is spawned. The boss lives under Room/Actors, so
## get_parent() returns Actors rather than the Room that must hear about the kill.
var room: Room = null

var _player: Node2D
var _knockback := Vector2.ZERO
var _burst_timer := 0.0
var _volley_timer := 0.0
var _telegraph_left := 0.0
var _telegraph_kind := 0   # 1 = burst, 2 = volley
var _phase2 := false


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	floor_snap_length = 0.0
	add_to_group(&"enemy")
	add_to_group(&"boss")

	# Refill matters: Health._ready has already run by the time a parent's _ready
	# does, so current was seeded from the scene's default maximum, not this one.
	health.set_maximum(base_health + health_per_floor * (RunState.floor - 1), true)

	health.depleted.connect(_on_depleted)
	health.damaged.connect(_on_damaged)
	hurtbox.hurt.connect(_on_hurt)
	hurtbox.health = health
	hurtbox.is_player_team = false
	hitbox.always_active = true
	hitbox.damage = contact_damage

	_burst_timer = burst_interval
	_volley_timer = volley_interval
	_resolve_player()


## Room._ready() spawns enemies before Game creates the player; caching the lookup
## there would freeze a null and the boss would never move or attack.
func _resolve_player() -> bool:
	if _player != null and is_instance_valid(_player):
		return true
	_player = get_tree().get_first_node_in_group(&"player") as Node2D
	return _player != null


func _physics_process(delta: float) -> void:
	_tick_attacks(delta)

	if not health.is_alive():
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		move_and_slide()
		return

	_update_phase()
	_knockback = _knockback.move_toward(Vector2.ZERO, 900.0 * delta)

	var desired := Vector2.ZERO
	if _resolve_player() and is_instance_valid(_player):
		desired = _steer(_player.global_position)

	var speed := max_speed * (phase2_speed_multiplier if _phase2 else 1.0)
	velocity = (velocity + desired * acceleration * delta).limit_length(speed) + _knockback
	move_and_slide()
	_update_visual()


func _steer(target: Vector2) -> Vector2:
	var to_target := target - global_position
	var distance := to_target.length()
	if distance > aggro_radius or distance <= stop_distance:
		return Vector2.ZERO
	return to_target.normalized()


## Phase 2 flips on once, when health first drops to the threshold. Reading the
## flag rather than the live fraction means the phase does not flicker back when
## the shield/invincibility maths rounds HP up a point.
func _update_phase() -> void:
	if _phase2:
		return
	if health.current <= int(float(health.maximum) * phase2_threshold):
		_phase2 = true
		# The acceleration is the announcement; give it a visual beat too.
		_flash(Color(1.0, 0.45, 0.35), 0.5)


func _tick_attacks(delta: float) -> void:
	if not health.is_alive() or not _resolve_player() or not is_instance_valid(_player):
		return
	if global_position.distance_to(_player.global_position) > fire_range:
		return

	if _telegraph_left > 0.0:
		_telegraph_left -= delta
		if _telegraph_left <= 0.0:
			if _telegraph_kind == 1:
				_fire_burst()
				_burst_timer = burst_interval
			else:
				_fire_volley()
				_volley_timer = volley_interval
		return

	_burst_timer -= delta
	if _burst_timer <= 0.0:
		_telegraph_kind = 1
		_telegraph_left = telegraph_time
		_flash(Color(1.4, 1.2, 0.7), telegraph_time)
		return

	if _phase2:
		_volley_timer -= delta
		if _volley_timer <= 0.0:
			_telegraph_kind = 2
			_telegraph_left = telegraph_time
			_flash(Color(1.5, 0.8, 0.5), telegraph_time)


func _fire_burst() -> void:
	var offset := randf() * TAU
	for i in burst_count:
		var angle := offset + TAU * float(i) / float(burst_count)
		_spawn_bullet(Vector2.from_angle(angle), burst_speed, burst_damage)


func _fire_volley() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var to_player := _player.global_position - global_position
	if to_player.length_squared() < 0.001:
		return
	var centre := to_player.angle()
	var spread := deg_to_rad(volley_spread_degrees)
	for i in volley_count:
		var t := 0.0 if volley_count == 1 else float(i) / float(volley_count - 1) - 0.5
		_spawn_bullet(Vector2.from_angle(centre + t * 2.0 * spread), volley_speed, burst_damage)


func _spawn_bullet(direction: Vector2, speed: float, damage: int) -> void:
	var packed := load("res://scenes/weapons/projectile.tscn") as PackedScene
	if packed == null:
		return
	var bullet := packed.instantiate() as Projectile
	# is_player_team=false makes the projectile look for the player's hurtbox
	# (layer 4) — the mask split from AGENTS §2.3, set before _ready reads it.
	bullet.is_player_team = false
	bullet.speed = speed
	bullet.damage = damage
	bullet.lifetime = burst_bullet_lifetime
	bullet.direction = direction.normalized()
	bullet.global_position = global_position
	var container := get_tree().get_first_node_in_group(&"projectile_container")
	if container != null:
		container.add_child(bullet)


func _flash(tint: Color, seconds: float) -> void:
	if sprite == null:
		return
	sprite.modulate = tint
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color.WHITE, seconds)


func _update_visual() -> void:
	if sprite == null:
		return
	if absf(velocity.x) > 1.0:
		sprite.scale.x = absf(sprite.scale.x) * signf(velocity.x)


func _on_hurt(info: DamageInfo) -> void:
	if not health.apply_damage(info):
		return
	health.start_invincibility()
	# The boss takes knockback at a fraction of a normal enemy's: at full force a
	# light pistol could stunlock a 40-HP target across the room.
	_knockback = info.knockback_direction.normalized() * info.knockback_force * 0.25


func _on_damaged(_amount: int, _absorbed: bool) -> void:
	_flash(Color(1.6, 0.8, 0.8), 0.15)


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
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_property(sprite, "scale", sprite.scale * 0.5, 0.4)
	tween.chain().tween_callback(queue_free)
