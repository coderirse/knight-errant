class_name Player
extends CharacterBody2D

## Top-down twin-stick controller.
##
## Deliberately not a platformer: motion is floating (no gravity, no jump), the
## right stick / mouse sets the aim independently of the movement direction, and
## the defensive move is a dodge roll with i-frames rather than a jump.
##
## Feel notes that matter more here than in a side-scroller:
##   - acceleration is high but not instant, so the character has weight;
##   - dodge has a fixed duration and carries fixed momentum, so it is a
##     commitment rather than a speed boost;
##   - the aim direction is never overridden by the movement direction, because
##     backpedalling while shooting is the core skill of the genre.

enum State { MOVE, DODGE, DEAD }

@export_group("Movement")
@export var max_speed := 132.0
@export var acceleration := 1300.0
@export var friction := 1500.0

@export_group("Dodge")
@export var dodge_speed := 400.0
@export var dodge_time := 0.20
@export var dodge_cooldown := 0.42
## Extra i-frames on top of the dodge duration. A little slack at the end means
## a well-timed roll through a bullet works even with a frame of latency.
@export var dodge_invincibility_bonus := 0.10

@export_group("Combat")
@export var max_weapons := 2
@export var starting_weapons: Array[StringName] = [&"pistol"]
## How far from the body the weapon pivots. Keeps the muzzle clear of the sprite.
@export var weapon_mount_offset := 6.0

## Warm, so the player reads as the same kind of light source as the torches.
const LIGHT_TINT := Color(1.0, 0.88, 0.66)

@export_group("Light")
## Both setters write straight through to the light rather than being copied each
## frame: a value the panel changes with nothing consuming it is exactly the bug
## class documented in roadmap §11.0-C.
@export var light_energy := 1.1:
	set(value):
		light_energy = value
		if _light != null:
			_light.energy = value
## Diameter multiplier on the falloff texture, so 1.0 is 128 logical pixels across.
@export var light_scale := 1.7:
	set(value):
		light_scale = value
		if _light != null:
			_light.texture_scale = value

signal state_changed(state: State)
signal died
signal weapon_swapped(weapon: Weapon)
signal dodge_started

var state: State = State.MOVE
var facing := 1
var aim_direction := Vector2.RIGHT
## Weapon nodes in slot order. Slot 0 is always occupied.
var weapons: Array[Weapon] = []
var weapon_index := 0

@onready var health: Health = $Health
@onready var energy: EnergyPool = $Energy
@onready var visual: Node2D = $Visual
@onready var sprite: Sprite2D = $Visual/Sprite2D
@onready var aim_pivot: Node2D = $AimPivot
@onready var hurtbox: Hurtbox = $Hurtbox

var _dodge_time_left := 0.0
var _dodge_cooldown_left := 0.0
var _dodge_direction := Vector2.RIGHT
var _receiving_health_sync := false
## Built in code, not the scene: its texture is generated at runtime.
var _light: PointLight2D


func _ready() -> void:
	add_to_group(&"player")
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	# No floor concept in top-down; sliding along walls is what we want, so keep
	# the default slide behaviour and disable floor snapping entirely.
	floor_snap_length = 0.0
	floor_stop_on_slope = false

	hurtbox.is_player_team = true
	hurtbox.health = health
	hurtbox.hurt.connect(_on_hurt)

	health.damaged.connect(_on_damaged)
	health.depleted.connect(_on_depleted)

	_equip_starting_weapons()
	_set_state(State.MOVE)
	_update_visual()
	_build_light()


## The player carries the dungeon's main light source, so the room reads outward
## from them and the aim direction stays legible away from the torches.
func _build_light() -> void:
	_light = PointLight2D.new()
	_light.name = "Light"
	_light.texture = DungeonLight.falloff()
	_light.color = LIGHT_TINT
	_light.energy = light_energy
	_light.texture_scale = light_scale
	_light.shadow_enabled = true
	add_child(_light)


func _physics_process(delta: float) -> void:
	_dodge_cooldown_left = maxf(_dodge_cooldown_left - delta, 0.0)

	if state != State.DEAD:
		aim_direction = _read_aim_direction()
		aim_pivot.rotation = aim_direction.angle()

	match state:
		State.DEAD:
			velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		State.DODGE:
			_tick_dodge(delta)
		State.MOVE:
			_tick_move(delta)

	move_and_slide()
	_update_visual()


# --- movement --------------------------------------------------------------

func _tick_move(delta: float) -> void:
	var input := _read_move_vector()

	if input.length_squared() > 0.0:
		velocity = velocity.move_toward(input * max_speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)

	if GameState.input_locked:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		return

	if Input.is_action_just_pressed(&"dodge") and _dodge_cooldown_left <= 0.0:
		_start_dodge(input)
		return

	if Input.is_action_pressed(&"fire"):
		_try_fire()

	if Input.is_action_just_pressed(&"swap_weapon"):
		swap_weapon()

	if Input.is_action_just_pressed(&"reload"):
		var reloading_weapon := current_weapon()
		if reloading_weapon != null:
			reloading_weapon.start_reload()

	if Input.is_action_just_pressed(&"throw_weapon"):
		throw_current_weapon()


func _tick_dodge(delta: float) -> void:
	_dodge_time_left = maxf(_dodge_time_left - delta, 0.0)
	# Constant momentum for the whole roll: the commitment is the point, so no
	# deceleration until it ends.
	velocity = _dodge_direction * dodge_speed
	if _dodge_time_left <= 0.0:
		_set_state(State.MOVE)
		velocity *= 0.45


func _start_dodge(input: Vector2) -> void:
	_dodge_direction = input.normalized() if input.length_squared() > 0.01 else aim_direction
	_dodge_time_left = dodge_time
	_dodge_cooldown_left = dodge_cooldown
	health.start_invincibility(dodge_time + dodge_invincibility_bonus)
	_set_state(State.DODGE)
	dodge_started.emit()


## Normalised movement input. Diagonals are normalised so moving north-east is not
## 1.41x faster than moving north.
func _read_move_vector() -> Vector2:
	if GameState.input_locked:
		return Vector2.ZERO
	var raw := Vector2(
		Input.get_axis(&"move_left", &"move_right"),
		Input.get_axis(&"move_up", &"move_down")
	)
	return raw.normalized() if raw.length() > 1.0 else raw


## Right stick if it is being pushed, otherwise the mouse. Letting the stick win
## when present means a gamepad plugged into a PC does not fight the mouse.
func _read_aim_direction() -> Vector2:
	var stick := Vector2(
		Input.get_axis(&"aim_left", &"aim_right"),
		Input.get_axis(&"aim_up", &"aim_down")
	)
	if stick.length() > 0.35:
		return stick.normalized()

	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length_squared() > 1.0:
		return to_mouse.normalized()

	return Vector2(float(facing), 0.0)


# --- weapons ---------------------------------------------------------------

func _equip_starting_weapons() -> void:
	var ids := starting_weapons.duplicate()
	if ids.is_empty():
		ids = [&"pistol"]
	for id in ids:
		if weapons.size() >= max_weapons:
			break
		_add_weapon(id)
	if not weapons.is_empty():
		weapon_index = 0


func _add_weapon(id: StringName) -> Weapon:
	var data := WeaponRegistry.load_data(id)
	if data == null:
		return null
	# Weapons are mounted on the aim pivot and offset along its +X so they orbit
	# the body as the aim rotates.
	var weapon := Weapon.new()
	weapon.name = "Weapon_%s" % String(id)
	weapon.position = Vector2(weapon_mount_offset, 0)
	weapon.data = data
	weapon.energy = energy
	aim_pivot.add_child(weapon)
	# setup() needs the node in the tree to resolve its muzzle and hitbox.
	weapon.setup(data, energy, true)
	weapons.append(weapon)
	return weapon


func current_weapon() -> Weapon:
	if weapons.is_empty():
		return null
	return weapons[clampi(weapon_index, 0, weapons.size() - 1)]


func swap_weapon() -> void:
	if weapons.size() < 2:
		return
	weapon_index = (weapon_index + 1) % weapons.size()
	weapon_swapped.emit(current_weapon())


## Hurls the equipped weapon: it flies as a damaging pickup and lands wherever
## it stops, so throwing is both an attack and a way to put a gun somewhere on
## purpose. The slot empties — an empty hand cannot fire until something is
## picked back up, which is the price of the throw.
func throw_current_weapon() -> WeaponPickup:
	var weapon := current_weapon()
	if weapon == null:
		return null
	var id: StringName = weapon.data.id
	weapons.remove_at(weapon_index)
	weapon.queue_free()
	if weapons.is_empty():
		weapon_index = 0
	else:
		weapon_index = clampi(weapon_index, 0, weapons.size() - 1)
	weapon_swapped.emit(current_weapon())

	var packed := load("res://scenes/world/weapon_pickup.tscn") as PackedScene
	if packed == null:
		return null
	var drop := packed.instantiate() as WeaponPickup
	drop.weapon_id = id
	var holder := get_parent()
	if holder == null:
		return null
	holder.add_child(drop)
	drop.launch(aim_direction, global_position + aim_direction * 12.0)
	return drop


## Picks up a weapon. If both slots are full the current one is dropped, which is
## the Soul Knight behaviour and keeps the choice meaningful.
func pick_up_weapon(id: StringName) -> Weapon:
	var data := WeaponRegistry.load_data(id)
	if data == null:
		return null

	if weapons.size() < max_weapons:
		var added := _add_weapon(id)
		weapon_index = weapons.size() - 1
		weapon_swapped.emit(current_weapon())
		return added

	var dropped_index := weapon_index
	var dropped_id: StringName = weapons[dropped_index].data.id
	weapons[dropped_index].queue_free()
	weapons.remove_at(dropped_index)
	var added := _add_weapon(id)
	weapon_swapped.emit(current_weapon())
	# The caller uses this to spawn the weapon we just dropped as a floor pickup.
	set_meta(&"last_dropped_weapon", dropped_id)
	return added


func _try_fire() -> void:
	var weapon := current_weapon()
	if weapon == null:
		return
	if not weapon.is_inside_tree():
		return
	weapon.aim_at(aim_direction)
	weapon.try_fire(aim_direction)


# --- damage ----------------------------------------------------------------

func _on_hurt(info: DamageInfo) -> void:
	if state == State.DEAD:
		return
	if not health.apply_damage(info):
		return
	# Enemies use 0.0-0.2s invincibility; the player uses the value on Health.
	health.start_invincibility()

	if info.knockback_direction.length_squared() > 0.0001:
		velocity = info.knockback_direction.normalized() * info.knockback_force
	else:
		velocity = -aim_direction * info.knockback_force

	_flash()
	Juice.shake_camera(6.0)


func _on_damaged(amount: int, absorbed_by_armor: bool) -> void:
	# Armour hits should read as cheaper than health hits.
	Juice.hit_stop(0.03 if absorbed_by_armor else 0.05)


func _on_depleted() -> void:
	_set_state(State.DEAD)
	hurtbox.vulnerable = false
	died.emit()


func _flash() -> void:
	var tween := create_tween()
	var loops := maxi(int(health.invincibility_time / 0.1), 1)
	tween.set_loops(loops)
	tween.tween_property(visual, "modulate:a", 0.3, 0.05)
	tween.tween_property(visual, "modulate:a", 1.0, 0.05)


# --- helpers ---------------------------------------------------------------

func _update_visual() -> void:
	if absf(aim_direction.x) > 0.1:
		facing = 1 if aim_direction.x > 0.0 else -1
	sprite.scale.x = absf(sprite.scale.x) * facing
	# Hide the held weapon sprite while rolling so the roll reads clearly.
	if aim_pivot != null:
		aim_pivot.visible = state != State.DEAD


func _set_state(next: State) -> void:
	if state == next:
		return
	state = next
	state_changed.emit(state)


func is_dodge_ready() -> bool:
	return _dodge_cooldown_left <= 0.0


func dodge_cooldown_ratio() -> float:
	if dodge_cooldown <= 0.0:
		return 0.0
	return clampf(_dodge_cooldown_left / dodge_cooldown, 0.0, 1.0)


## Applies every permanent (meta) upgrade from GameState.
##
## Lives on the player rather than in Game so it can be exercised without a full
## Game scene, and so there is exactly one place that knows how a meta upgrade
## maps onto a stat. It is driven by GameState.UPGRADES: a hand-written list here
## is how `speed` ended up purchasable but inert.
## Call once, on creation — these are additive and not idempotent.
func apply_meta_upgrades() -> void:
	health.maximum += GameState.upgrade_level(&"max_health")
	health.maximum_armor += GameState.upgrade_level(&"max_armor")
	max_speed *= 1.0 + GameState.upgrade_level(&"speed") * GameState.SPEED_BONUS_PER_LEVEL


## Called on respawn / new floor.
func full_restore() -> void:
	health.current = health.maximum
	health.armor = health.maximum_armor
	health.invincible = false
	health.changed.emit(health.current, health.maximum)
	health.armor_changed.emit(health.armor, health.maximum_armor)
	energy.fill()
	hurtbox.vulnerable = true
	velocity = Vector2.ZERO
	_set_state(State.MOVE)

