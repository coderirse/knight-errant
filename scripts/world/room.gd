class_name Room
extends Node2D

## A single arena — the unit a level is made of.
##
## Responsibilities:
##   1. Stamp a room template's tiles into the TileMapLayer (see
##      RoomTemplateLibrary), plus the surrounding wall ring.
##   2. Spawn the enemies for its encounter, on walkable tiles.
##   3. Lock the doors while enemies live, unlock when the room is cleared.
##   4. Report completion to the level, which decides where to go next.
##
## Seeded generation: everything random is driven by `rng`, seeded from
## (level_seed, room_index) in setup(). The same seed therefore rebuilds the same
## room layout exactly, which is what makes a run reproducible and testable.

signal cleared(room: Room)

const TILE := 16
const FLOOR_TILE := Vector2i(0, 0)
const FLOOR_VARIANT_TILE := Vector2i(1, 0)
const WALL_TILE := Vector2i(2, 0)
## Fraction of plain floor tiles that get the variant texture, purely so large
## open areas do not read as a uniform grid.
const FLOOR_VARIANT_CHANCE := 0.14
## Torch tint. Warm pools of light against a cold ambient is the whole look.
const TORCH_COLOR := Color(1.0, 0.72, 0.38)
const TORCH_ENERGY := 1.9
## Pool diameter multiplier on the falloff texture (128 px), so 1.5 is ~190 px.
## Measured from a screenshot: 2.0 with one torch in a small room spread into a
## wash instead of reading as distinct sconces.
const TORCH_SCALE := 1.5

enum Kind { START, COMBAT, TREASURE, BOSS }

@export var kind: Kind = Kind.COMBAT
## Interior size in tiles, walls excluded.
@export var interior := Vector2i(20, 12)
## Enemies to spawn. Empty means the level decides from the difficulty curve.
@export var enemy_budget := 0

var room_index := 0
var enemies_alive := 0
var is_cleared := false
## The layout stamped into this room. Null means no template matched the size and
## the room fell back to a plain open arena.
var template: RoomTemplate

var _rng := RandomNumberGenerator.new()
var _tile_layer: TileMapLayer
var _actors: Node2D
var _doors: Array[Area2D] = []
var _cleared_emitted := false
## Cached walkable spawn tiles, built on first use. The template never changes
## after setup(), so this does not need invalidating.
var _spawn_cache: Array[Vector2i] = []
## Torches built by _build_lighting(), kept so Level can switch them off at a
## distance. Rooms start lit: one that never receives an update must not be dark.
var _lights: Array[PointLight2D] = []
var _lights_active := true


func setup(index: int, seed_value: int, room_kind: Kind, tile_set: TileSet, size := Vector2i(20, 12)) -> void:
	room_index = index
	kind = room_kind
	interior = size
	_rng.seed = hash("%d:%d" % [seed_value, index])
	# BOSS rooms ask for an open layout: a pillar-heavy arena fights the fight.
	var prefer := &"open" if room_kind == Kind.BOSS else &""
	template = RoomTemplateLibrary.pick(interior, _rng, prefer)


func _ready() -> void:
	add_to_group(&"room")
	_ensure_structure()
	_build_tiles()
	_build_lighting()
	_spawn_encounter()


func interior_rect() -> Rect2:
	# Interior spans from one tile in (inside the wall ring) to one tile short of
	# the far edge.
	var origin := Vector2(TILE, TILE)
	var size := Vector2(interior.x * TILE, interior.y * TILE)
	return Rect2(origin, size)


func world_size() -> Vector2:
	# Interior plus the wall ring on all four sides.
	return Vector2((interior.x + 2) * TILE, (interior.y + 2) * TILE)


## A random point inside the arena, at least `margin` away from the walls.
func random_point(margin := 24.0) -> Vector2:
	var rect := interior_rect()
	return Vector2(
		_rng.randf_range(rect.position.x + margin, rect.end.x - margin),
		_rng.randf_range(rect.position.y + margin, rect.end.y - margin)
	)


# --- structure -------------------------------------------------------------

func _ensure_structure() -> void:
	_tile_layer = get_node_or_null("Terrain/Ground") as TileMapLayer
	if _tile_layer == null:
		var terrain := Node2D.new()
		terrain.name = "Terrain"
		add_child(terrain)
		_tile_layer = TileMapLayer.new()
		_tile_layer.name = "Ground"
		terrain.add_child(_tile_layer)

	_actors = get_node_or_null("Actors") as Node2D
	if _actors == null:
		_actors = Node2D.new()
		_actors.name = "Actors"
		_actors.y_sort_enabled = true
		add_child(_actors)

	# Bullets live here so they are not siblings of the actors that spawned them
	# (and therefore are not freed when an enemy dies mid-flight).
	if get_tree().get_first_node_in_group(&"projectile_container") == null:
		var bullets := Node2D.new()
		bullets.name = "Projectiles"
		bullets.add_to_group(&"projectile_container")
		add_child(bullets)


## Stamps the room template into the tile map and rings it with walls.
##
## Layer coordinates: the wall ring occupies layer tiles 0 and interior+1, and the
## interior occupies layer tiles 1..interior. That offset is not cosmetic — it is
## what makes layer space agree with the room's own local space, where
## interior_rect() starts at (TILE, TILE) and world_size() is (interior + 2) tiles
## across.
##
## This used to stamp the ring at layer -1 and interior+1, which shifted every
## tile one cell up-left of where the rest of the code believed the room was.
## Everything derived from interior_rect() or world_size() was then off by one
## tile: spawns landed on the wrong cell, and doorways were carved into the floor
## next to the wall instead of into the wall itself. Off-by-one in a tile grid is
## invisible to a headless logic test and obvious only when the geometry is
## measured — see RoomTemplate.problems() for the data-level checks.
func _build_tiles() -> void:
	var span := interior + Vector2i(2, 2)
	for y in span.y:
		for x in span.x:
			var pos := Vector2i(x, y)
			var is_wall := x == 0 or y == 0 or x == interior.x + 1 or y == interior.y + 1
			if is_wall:
				_tile_layer.set_cell(pos, 0, WALL_TILE)
				continue

			# Interior layer tile (x, y) is template tile (x - 1, y - 1).
			var local := Vector2i(x - 1, y - 1)
			# A solid template tile becomes a wall; that is how pillars, rings and
			# corner blocks are built without a separate "obstacle" layer.
			if template != null and template.is_solid(local):
				_tile_layer.set_cell(pos, 0, WALL_TILE)
				continue

			var variant := FLOOR_VARIANT_TILE if _rng.randf() < FLOOR_VARIANT_CHANCE else FLOOR_TILE
			_tile_layer.set_cell(pos, 0, variant)


# --- lighting ---------------------------------------------------------------

## Torches and wall shadows for this room.
##
## Every room on a floor is instantiated at once (one scene per floor), so these
## lights would all be rasterising every frame otherwise — Level gates them by
## proximity with set_lights_active().
func _build_lighting() -> void:
	var holder := Node2D.new()
	holder.name = "Lighting"
	add_child(holder)

	for i in _torch_count():
		var light := PointLight2D.new()
		light.name = "Torch%d" % i
		light.position = _torch_position(i)
		light.texture = DungeonLight.falloff()
		light.color = TORCH_COLOR
		light.energy = TORCH_ENERGY
		light.texture_scale = TORCH_SCALE
		light.shadow_enabled = true
		holder.add_child(light)
		_lights.append(light)

	# Godot 4.7 gives TileMapLayer no per-tile occluder support at all (verified
	# by probe: no occluders_enabled, no set_cell_occluders_enabled), so shadows
	# need real nodes. One per solid cell would be ~60 in a large room; merging
	# runs into rectangles brings a walled room down to a handful.
	var rects := _solid_rects()
	for i in rects.size():
		holder.add_child(_make_occluder(rects[i], i))


## Doorways are not gaps here: Level._connect only places a trigger and never
## erases the wall tile, and passing through is a teleport. The wall ring really
## is continuous, so light not leaking between rooms is the honest result.
func _make_occluder(rect: Rect2i, index: int) -> LightOccluder2D:
	var polygon := OccluderPolygon2D.new()
	var near := Vector2(rect.position.x * TILE, rect.position.y * TILE)
	var far := near + Vector2(rect.size.x * TILE, rect.size.y * TILE)
	polygon.polygon = PackedVector2Array([near, Vector2(far.x, near.y), far, Vector2(near.x, far.y)])
	polygon.closed = true

	var occluder := LightOccluder2D.new()
	occluder.name = "Wall%d" % index
	occluder.occluder = polygon
	return occluder


func set_lights_active(active: bool) -> void:
	if active == _lights_active:
		return
	_lights_active = active
	for light in _lights:
		if is_instance_valid(light):
			light.enabled = active


## Bigger rooms need more sources or their far corners stay black. Two is the
## floor even for a small room: a single torch left the opposite half unlit.
func _torch_count() -> int:
	if interior.x >= 25:
		return 4
	if interior.x >= 21:
		return 3
	return 2


## Torch `index` lands on the walkable tile closest to that corner of the room, so
## the pools hug the walls like sconces rather than piling up in the middle.
func _torch_position(index: int) -> Vector2:
	var tiles := _spawn_tiles()
	if tiles.is_empty():
		return interior_rect().get_center()

	var corners := [
		Vector2i.ZERO,
		Vector2i(interior.x - 1, interior.y - 1),
		Vector2i(interior.x - 1, 0),
		Vector2i(0, interior.y - 1),
	]
	var anchor: Vector2i = corners[index % corners.size()]
	var best: Vector2i = tiles[0]
	var best_distance := 1 << 40
	for tile in tiles:
		var distance := (tile - anchor).length_squared()
		if distance < best_distance:
			best_distance = distance
			best = tile
	return _tile_center(best)


func _is_wall_cell(cell: Vector2i) -> bool:
	return _tile_layer.get_cell_atlas_coords(cell) == WALL_TILE


## Every solid tile, as few rectangles as possible: horizontal runs per row, then
## a run whose span matches the open one above it grows downward into it.
func _solid_rects() -> Array[Rect2i]:
	var span := interior + Vector2i(2, 2)
	var rows: Array = []
	for y in span.y:
		var runs: Array[Rect2i] = []
		var x := 0
		while x < span.x:
			if not _is_wall_cell(Vector2i(x, y)):
				x += 1
				continue
			var start := x
			while x < span.x and _is_wall_cell(Vector2i(x, y)):
				x += 1
			runs.append(Rect2i(start, y, x - start, 1))
		rows.append(runs)

	var merged: Array[Rect2i] = []
	for runs in rows:
		for run in runs:
			var grown := false
			for i in merged.size():
				var previous: Rect2i = merged[i]
				if previous.position.x == run.position.x and previous.size.x == run.size.x \
						and previous.end.y == run.position.y:
					merged[i] = Rect2i(previous.position,
						Vector2i(previous.size.x, previous.size.y + 1))
					grown = true
					break
			if not grown:
				merged.append(run)
	return merged


# --- encounter -------------------------------------------------------------

func _spawn_encounter() -> void:
	enemies_alive = 0

	if kind == Kind.TREASURE:
		_spawn_chest()
		# A treasure room has nothing to fight, so its doors open immediately. The
		# floor is only considered finished when the player actually walks into the
		# exit room (see Level.move_player_to_room), which is why clearing a room
		# is not the same as completing a floor.
		_mark_cleared()
		return
	if kind == Kind.BOSS:
		_spawn_boss()
		return
	if kind == Kind.START:
		_mark_cleared()
		return

	var budget := enemy_budget if enemy_budget > 0 else _default_budget()
	for i in budget:
		_spawn_enemy(i)

	if enemies_alive == 0:
		# A room with nothing to fight must not lock the player in.
		_mark_cleared()


func _default_budget() -> int:
	return 3 + RunState.floor


## The exit room holds one boss, not a budget of regular enemies. It is the last
## fight of the floor, so it is authored as its own scene rather than rolled from
## the encounter table.
func _spawn_boss() -> void:
	var packed := load("res://scenes/enemies/boss.tscn") as PackedScene
	if packed == null:
		push_error("Room: cannot load res://scenes/enemies/boss.tscn")
		return
	var boss := packed.instantiate() as Node2D
	boss.name = "Boss"
	# Same rule as the chest: the geometric centre can be a pillar on ring or
	# plus layouts, so use the walkable tile nearest the middle.
	if template != null:
		boss.position = _tile_center(template.center_walkable())
	else:
		boss.position = interior_rect().get_center()
	boss.set("room", self)
	_actors.add_child(boss)
	enemies_alive += 1


func _spawn_enemy(index: int) -> void:
	var is_shooter := _rng.randf() < 0.4
	var scene_path := "res://scenes/enemies/shooter.tscn" if is_shooter else "res://scenes/enemies/chaser.tscn"
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("Room: cannot load %s" % scene_path)
		return

	var enemy := packed.instantiate() as Node2D
	enemy.name = "%s%d" % ["Shooter" if is_shooter else "Chaser", index]
	enemy.position = _pick_spawn_position(index)
	# Hand the enemy a direct reference to this room. Enemies are parented to
	# Actors/, so get_parent() from inside them returns Actors, not the Room — a
	# bug that silently stops rooms from ever being marked cleared.
	enemy.set("room", self)
	_actors.add_child(enemy)
	enemies_alive += 1


## Position for the `index`-th enemy, always on a walkable tile.
##
## This used to pick a random point in the room rectangle, which was fine while
## every room was empty and is wrong now that templates have pillars: an enemy
## could spawn inside a wall, stuck and unkillable, leaving the room permanently
## locked. Candidates come from the template's interior tiles, so they clear the
## border ring (where the doorways are) and every solid tile.
func _pick_spawn_position(index: int) -> Vector2:
	var tiles := _spawn_tiles()
	if tiles.is_empty():
		# No template, or a template with no interior — fall back to the room
		# centre rather than returning something random.
		return interior_rect().get_center()

	# Spread enemies out instead of letting the RNG stack them. Walking the list
	# with a stride derived from the spawn count keeps them apart while staying
	# deterministic for a given seed.
	var stride := maxi(tiles.size() / maxi(_default_budget(), 1), 1)
	var start := _rng.randi_range(0, tiles.size() - 1)
	var tile: Vector2i = tiles[(start + index * stride) % tiles.size()]
	return _tile_center(tile)


func _spawn_tiles() -> Array[Vector2i]:
	if _spawn_cache.is_empty():
		_spawn_cache = (template.spawn_tiles(2) if template != null else _fallback_spawn_tiles())
	return _spawn_cache


## Used when no template matched: every tile of a plain rectangle, inset so it
## does not sit in the wall ring.
func _fallback_spawn_tiles() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(2, interior.y - 2):
		for x in range(2, interior.x - 2):
			result.append(Vector2i(x, y))
	return result


## Tile coordinates are relative to the interior's top-left, whose centre sits one
## tile in from the room origin because of the surrounding wall ring.
func _tile_center(tile: Vector2i) -> Vector2:
	return Vector2(
		(tile.x + 1) * TILE + TILE * 0.5,
		(tile.y + 1) * TILE + TILE * 0.5
	)


func _spawn_chest() -> void:
	var packed := load("res://scenes/world/chest.tscn") as PackedScene
	if packed == null:
		return
	var chest := packed.instantiate() as Node2D
	# The rectangle's centre can be solid on a ring or plus layout, so drop the
	# chest on the walkable tile nearest the middle instead of the geometric middle.
	if template != null:
		chest.position = _tile_center(template.center_walkable())
	else:
		chest.position = interior_rect().get_center()
	_actors.add_child(chest)


## Called by every enemy as it dies (see Chaser._on_depleted).
func on_enemy_died(enemy: Node) -> void:
	enemies_alive = maxi(enemies_alive - 1, 0)
	RunState.kills += 1
	if enemies_alive == 0 and not is_cleared:
		_mark_cleared()
		# Deliberately no auto-advance: the player walks out through a door, which
		# keeps the pace in their hands.


func _mark_cleared() -> void:
	is_cleared = true
	for door in _doors:
		if is_instance_valid(door):
			door.set(&"locked", false)
	if not _cleared_emitted:
		_cleared_emitted = true
		cleared.emit(self)


# --- doors -----------------------------------------------------------------

## The level generator calls this to carve a doorway and register it.
func add_door(world_position: Vector2, side: int, target_room: int, target_door: int) -> Area2D:
	var door := Area2D.new()
	door.name = "Door%d" % _doors.size()
	door.set_script(load("res://scripts/world/room_door.gd"))
	door.position = world_position
	door.set(&"side", side)
	door.set(&"target_room", target_room)
	door.set(&"target_door", target_door)
	door.collision_layer = 256   # interactable
	door.collision_mask = 2      # player body
	door.set(&"locked", not is_cleared)

	# The trigger is deliberately larger than the doorway and reaches into the
	# room. The door sits in the wall tile, so a player walking into that wall
	# stops with their body edge exactly on the wall/floor boundary — with a
	# doorway-sized box the two would only touch, which is not a reliable overlap.
	# Extending 8px inward gives a solid overlap and makes the doorway forgiving.
	#
	# The long axis follows the wall: a left/right door sits in a vertical wall and
	# reaches inward along x, a top/bottom door reaches along y.
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	var horizontal_wall := side == 0 or side == 1
	rect.size = Vector2(TILE * 2.0, TILE) if horizontal_wall else Vector2(TILE, TILE * 2.0)
	shape.shape = rect
	door.add_child(shape)

	# Visual so a door is not an invisible trigger. Sized to the doorway tile, not
	# to the (larger) trigger, so it reads as a doorway rather than a wall panel.
	var visual := ColorRect.new()
	visual.name = "Visual"
	visual.color = Color(0.95, 0.75, 0.25, 0.45)
	visual.size = Vector2(TILE, TILE)
	visual.position = -visual.size * 0.5
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	door.add_child(visual)

	add_child(door)
	_doors.append(door)
	return door
