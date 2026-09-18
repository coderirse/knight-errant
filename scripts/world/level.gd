class_name Level
extends Node2D

## Builds and drives one floor of the dungeon: a small graph of rooms laid out in
## a grid, with doorways carved between neighbours.
##
## Layout rule: rooms sit on a 5x5 grid, the player enters in the **centre**, and
## the exit is on the border. Extra rooms dangle off it as optional treasure.
## Every room between entry and exit is COMBAT or BOSS, so the run cannot be
## walked through empty — see _plan_layout for the two properties that are
## enforced by construction rather than hoped for.
##
## The whole floor is one scene, not one scene per room. Rooms are 480x270-ish
## arenas; keeping them all loaded means walking through a door is a camera move,
## not a scene reload, so there is no hitch and no state to serialise. This is the
## single biggest structural difference from the side-scrolling build, where each
## room was its own .tscn.

signal floor_completed(floor_number: int)
signal player_died
## Emitted whenever the player's current room changes, including the initial
## placement. The minimap listens to this rather than polling.
signal room_changed(index: int)

const ROOM_SCENE := "res://scenes/world/room.tscn"
const TILE := 16
## Interior size used only when the template catalogue is empty (see _plan_sizes).
const DEFAULT_INTERIOR := 21
## Gap of solid rock between adjacent rooms, in tiles.
const ROOM_GAP := 2
## The floor is laid out on a 5x5 cell grid with the entrance in the middle, the
## way Soul Knight does it, so any of four directions can hold the next room.
const GRID_SIDE := 5
const GRID_CENTRE := 2
## What everything looks like where no light reaches. Dark and a little blue, so
## the warm torches read as light rather than merely as "brighter". Tuned from a
## screenshot: at 0.30 the floor was bright enough that the torch pools vanished.
const AMBIENT_COLOR := Color(0.14, 0.16, 0.24)

@export var tile_set: TileSet

var floor_number := 1
var seed_value := 0
var rooms: Array[Room] = []
var player: Player

var _path: Array[int] = []
var _grid: Dictionary = {}       # Vector2i grid cell -> room index
var _cell_of: Dictionary = {}    # room index -> Vector2i grid cell
var _sizes: Array[Vector2i] = []
var _origins: Array[Vector2] = []
var _player_spawn := Vector2.ZERO
var _exit_room_index := -1
var _completed := false
## Which room the player is standing in, tracked so floor completion can require
## the player to actually reach the exit.
var _current_room_index := -1
var _ambience: CanvasModulate
## Which room the light scope was last applied for; _process only acts on change.
## -2 means "never", so the first update always runs.
var _lit_room := -2


func generate(floor_num: int, level_seed: int) -> void:
	floor_number = floor_num
	seed_value = level_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = level_seed

	_plan_layout(rng)
	_instantiate_rooms()
	_carve_doors()
	_place_player()
	_ensure_ambience()
	# After _place_player: the scope depends on which room the player landed in.
	_apply_light_scope()


# --- layout ----------------------------------------------------------------

## Lays out a 5x5 grid with the entrance in the **centre** and the exit on the
## border, then hangs optional treasure rooms off it as dead ends.
##
## Why centre-out rather than the old left-to-right chain: a chain tells you
## exactly one thing (forward) and every door you did not take is invisible.
## Starting in the middle means four directions are all plausible, which is what
## makes a Soul Knight floor feel like a place rather than a corridor.
##
## Two properties are enforced by construction, not hoped for:
##
## 1. Path steps are orthogonal. A diagonal pair shares no wall, so no door can be
##    carved and the floor silently becomes unwinnable (roadmap §7: 141 of 200
##    seeds were, before this was pinned down).
## 2. The route from the entrance to the exit passes at least `required_enemies`
##    combat rooms, so the floor's effort budget is designed rather than rolled.
##    That holds because the door graph is a **tree**: path steps may not touch any
##    earlier cell of the path (an extra door there would be a shortcut past the
##    fights), and branches are only accepted when they touch nothing but their
##    parent. So the unique route start→exit *is* the chain.
func _plan_layout(rng: RandomNumberGenerator) -> void:
	var required_enemies := 3 if floor_number % 2 == 0 else 2
	var cells := _grow_path(rng, required_enemies)
	var chain_length := cells.size()

	# Branches: optional rewards, one room deep, dangling from an existing cell.
	var branches := clampi(1 + floor_number / 2, 1, 3)
	for branch_index in branches:
		var base: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		for offset in _shuffled([Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)], rng):
			var candidate: Vector2i = base + offset
			if not _in_grid(candidate) or cells.has(candidate):
				continue
			# Anything that touches a second cell could shortcut the fights.
			if not _only_touches(candidate, cells, base):
				continue
			cells.append(candidate)
			break

	_path.clear()
	_grid.clear()
	_cell_of.clear()
	for i in cells.size():
		var cell := cells[i]
		_grid[cell] = i
		_cell_of[i] = cell
		# The path is the first `chain_length` entries; everything after is a
		# branch, so the route to the exit is exactly the chain.
		if i < chain_length:
			_path.append(i)

	_exit_room_index = _path[_path.size() - 1]


## Randomised depth-first search for an orthogonal path from the centre cell to a
## border cell with at least `required_enemies` rooms in between.
##
## Exhaustive rather than "walk and retry": a path of the required length always
## exists on a 5x5 grid, so there is no unbounded retry loop that could hang the
## generator — and the search is deterministic for a given seed.
func _grow_path(rng: RandomNumberGenerator, required_enemies: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	var path: Array[Vector2i] = [Vector2i(GRID_CENTRE, GRID_CENTRE)]
	_search_path(path, required_enemies, found, rng)
	return found


func _search_path(path: Array[Vector2i], required: int, found: Array[Vector2i],
		rng: RandomNumberGenerator) -> bool:
	if not found.is_empty():
		return true
	var cursor: Vector2i = path[path.size() - 1]
	if path.size() >= required + 2 and _is_border(cursor):
		found.append_array(path)
		return true
	# Cap the sprawl: a floor longer than this is a chore, not a dungeon.
	if path.size() > required + 4:
		return false

	for option in _shuffled(_free_neighbours(cursor, path), rng):
		path.append(option)
		if _search_path(path, required, found, rng):
			return true
		path.pop_back()
	return false


## Orthogonal in-grid neighbours of `cell` that the path may extend into.
##
## Stricter than "not used yet": the candidate must also touch **no other** cell of
## the path. Doors are carved between every pair of adjacent rooms, so a path that
## runs alongside itself gets an extra door there — and that door is a shortcut
## past the fights the path exists to guarantee. With this rule the door graph is
## a tree: the chain, plus leaves that only ever dangle.
func _free_neighbours(cell: Vector2i, path: Array[Vector2i]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var candidate: Vector2i = cell + offset
		if _in_grid(candidate) and not path.has(candidate) and _only_touches(candidate, path, cell):
			result.append(candidate)
	return result


func _in_grid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < GRID_SIDE and cell.y < GRID_SIDE


func _is_border(cell: Vector2i) -> bool:
	return cell.x == 0 or cell.y == 0 or cell.x == GRID_SIDE - 1 or cell.y == GRID_SIDE - 1


## True when `cell` is orthogonally adjacent to no occupied cell except `parent`.
func _only_touches(cell: Vector2i, cells: Array[Vector2i], parent: Vector2i) -> bool:
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var neighbour: Vector2i = cell + offset
		if neighbour != parent and cells.has(neighbour):
			return false
	return true


## A shuffled copy, drawn from the *seeded* rng.
##
## Deliberately not `Array.shuffle()`: that consumes the engine's global RNG, so a
## floor built with it is not reproducible from `level_seed` — which quietly
## breaks "same seed, same floor" (test_run §11 catches exactly this).
func _shuffled(source: Array[Vector2i], rng: RandomNumberGenerator) -> Array[Vector2i]:
	var copy := source.duplicate()
	for i in range(copy.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Vector2i = copy[i]
		copy[i] = copy[j]
		copy[j] = swap
	return copy


# --- instantiation ---------------------------------------------------------

func _instantiate_rooms() -> void:
	rooms.clear()
	var room_scene := load(ROOM_SCENE) as PackedScene
	if room_scene == null:
		push_error("Level: cannot load %s" % ROOM_SCENE)
		return

	_plan_sizes()
	_plan_origins()

	for i in _grid.size():
		var room := room_scene.instantiate() as Room
		var kind := _kind_for(i)
		room.setup(i, seed_value, kind, tile_set, _sizes[i])
		room.name = "Room%d" % i
		room.position = _origins[i]
		room.cleared.connect(_on_room_cleared)
		add_child(room)
		rooms.append(room)


## Room sizes come from the template catalogue, so every size has at least one
## layout authored for it.
##
## Square, and drawn from {15, 21, 25} as Soul Knight does. Fixed sizes rather
## than random ones because the doorway between two rooms has to line up on both
## walls: with a handful of known sizes the overlap maths in _connect() is exact,
## and a new size only ever needs a matching template. Random sizes made every
## room a slightly different shape for no gameplay gain.
func _plan_sizes() -> void:
	_sizes.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var available: Array[Vector2i] = RoomTemplateLibrary.sizes()
	if available.is_empty():
		# No catalogue: fall back to a single fixed size so the floor is still
		# playable rather than degenerating into zero-sized rooms.
		available = [Vector2i(DEFAULT_INTERIOR, DEFAULT_INTERIOR)]

	for i in _grid.size():
		_sizes.append(available[rng.randi_range(0, available.size() - 1)])


## Places each room by its grid coordinate, so grid neighbours end up physically
## adjacent. Columns accumulate their widest room; rows accumulate their tallest.
##
## Row-based vertical placement is what makes horizontal doorways work: rooms in
## the same row share a y band, so a doorway between them always finds overlapping
## wall. Stacking by column height instead would let a tall neighbour in one
## column push its rows out of alignment, and the door between two rooms that the
## grid says are adjacent would have nothing to attach to.
func _plan_origins() -> void:
	_origins.resize(_sizes.size())

	var column_width: Dictionary = {}
	var row_height: Dictionary = {}
	for index in _sizes.size():
		var cell: Vector2i = _cell_of[index]
		var full := Vector2((_sizes[index].x + 2) * TILE, (_sizes[index].y + 2) * TILE)
		column_width[cell.x] = maxf(float(column_width.get(cell.x, 0.0)), full.x)
		row_height[cell.y] = maxf(float(row_height.get(cell.y, 0.0)), full.y)

	var column_left: Dictionary = {}
	var running_x := 0.0
	var columns := column_width.keys()
	columns.sort()
	for column in columns:
		column_left[column] = running_x
		running_x += float(column_width[column]) + ROOM_GAP * TILE

	var row_top: Dictionary = {}
	var running_y := 0.0
	var rows := row_height.keys()
	rows.sort()
	for row in rows:
		row_top[row] = running_y
		running_y += float(row_height[row]) + ROOM_GAP * TILE

	for index in _sizes.size():
		var cell: Vector2i = _cell_of[index]
		_origins[index] = Vector2(float(column_left[cell.x]), float(row_top[cell.y]))


## World position of a room's origin (its top-left wall corner).
func _room_origin(index: int) -> Vector2:
	return _origins[index]


func _kind_for(index: int) -> Room.Kind:
	if index == _path[0]:
		return Room.Kind.START
	if index == _exit_room_index:
		return Room.Kind.BOSS if floor_number % 2 == 0 else Room.Kind.TREASURE
	if not _path.has(index):
		return Room.Kind.TREASURE
	return Room.Kind.COMBAT


# --- doors -----------------------------------------------------------------

func _carve_doors() -> void:
	for cell in _grid.keys():
		var index: int = _grid[cell]
		# Only connect right and down, so each pair is handled exactly once.
		for step in [Vector2i(1, 0), Vector2i(0, 1)]:
			var neighbour_cell: Vector2i = cell + step
			if not _grid.has(neighbour_cell):
				continue
			_connect(index, _grid[neighbour_cell], step)


func _connect(a_index: int, b_index: int, step: Vector2i) -> void:
	var a := rooms[a_index]
	var b := rooms[b_index]
	var a_size := a.world_size()
	var b_size := b.world_size()

	if step.x != 0:
		# Horizontal neighbours. Rooms in a column are stacked vertically, so the
		# doorway must line up with the *overlap* of the two interiors, not with
		# either room's own centre.
		var a_rect := Rect2(a.position, a_size)
		var b_rect := Rect2(b.position, b_size)
		var top := maxf(a_rect.position.y, b_rect.position.y)
		var bottom := minf(a_rect.end.y, b_rect.end.y)
		if bottom - top < TILE * 3.0:
			push_warning("Level: rooms %d and %d overlap %.0f px vertically (need %d); skipping door" % [
				a_index, b_index, bottom - top, TILE * 3])
			return
		var y := (top + bottom) * 0.5
		a.add_door(Vector2(a_size.x - TILE * 0.5, y - a.position.y), 0, b_index, 1)
		b.add_door(Vector2(TILE * 0.5, y - b.position.y), 1, a_index, 0)
	else:
		var a_rect := Rect2(a.position, a_size)
		var b_rect := Rect2(b.position, b_size)
		var left := maxf(a_rect.position.x, b_rect.position.x)
		var right := minf(a_rect.end.x, b_rect.end.x)
		if right - left < TILE * 3.0:
			push_warning("Level: rooms %d and %d overlap %.0f px horizontally (need %d); skipping door" % [
				a_index, b_index, right - left, TILE * 3])
			return
		var x := (left + right) * 0.5
		a.add_door(Vector2(x - a.position.x, a_size.y - TILE * 0.5), 2, b_index, 3)
		b.add_door(Vector2(x - b.position.x, TILE * 0.5), 3, a_index, 2)


func _place_player() -> void:
	var start := rooms[_path[0]]
	_current_room_index = start.room_index
	var rect := start.interior_rect()
	_player_spawn = start.position + Vector2(rect.position.x + 28.0, rect.get_center().y)
	if player != null and is_instance_valid(player):
		player.global_position = _player_spawn
	room_changed.emit(_current_room_index)


# --- ambience ---------------------------------------------------------------

## One CanvasModulate darkens everything the lights do not reach. It is a child of
## the Level so it dies with the floor instead of leaking into the main menu, and
## the HUD / overlay / tuning panel are CanvasLayers, so they stay readable.
func _ensure_ambience() -> void:
	if _ambience != null and is_instance_valid(_ambience):
		return
	_ambience = CanvasModulate.new()
	_ambience.name = "Ambience"
	_ambience.color = AMBIENT_COLOR
	add_child(_ambience)


## Rooms the player cannot see do not need their lights rasterised. Only the
## current room and those joined to it by a door stay lit, so the per-frame cost
## tracks how many rooms are *adjacent* to the player rather than how big the
## floor is — which matters because a whole floor is one live scene (see §2.2).
func _apply_light_scope() -> void:
	_lit_room = _current_room_index
	var scope := {_current_room_index: true}
	for index in _neighbor_rooms(_current_room_index):
		scope[index] = true
	for room in rooms:
		room.set_lights_active(scope.has(room.room_index))


func _process(_delta: float) -> void:
	if _lit_room != _current_room_index:
		_apply_light_scope()


func _neighbor_rooms(index: int) -> Array[int]:
	var result: Array[int] = []
	if not _cell_of.has(index):
		return result
	var cell: Vector2i = _cell_of[index]
	for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _grid.has(cell + step):
			result.append(int(_grid[cell + step]))
	return result


# --- runtime ---------------------------------------------------------------

## Called by RoomDoor when the player walks through an unlocked door.
func move_player_to_room(target_index: int, entry_side: int) -> void:
	var target := rooms[target_index]
	var rect := target.interior_rect()
	var centre := rect.get_center()
	# Enter just inside the wall opposite the door we came through.
	var margin := 28.0
	var local := centre
	match entry_side:
		0: local.x = rect.position.x + margin            # came in from the left
		1: local.x = rect.end.x - margin                 # from the right
		2: local.y = rect.position.y + margin            # from the top
		3: local.y = rect.end.y - margin                 # from the bottom
	if player != null and is_instance_valid(player):
		player.global_position = target.position + local
		player.velocity = Vector2.ZERO

	_current_room_index = target_index
	room_changed.emit(target_index)
	Juice.shake_camera(2.0)
	# Entering the exit room is what finishes the floor.
	_try_complete_floor(target)


func _on_room_cleared(room: Room) -> void:
	RunState.rooms_cleared += 1
	_try_complete_floor(room)


## A floor is finished when the player *stands in* a cleared exit room. Keying off
## the room's cleared signal alone is wrong: the exit room can be a treasure room
## with nothing to fight, so it reports itself cleared during generation and the
## floor would complete before the player had moved.
func _try_complete_floor(room: Room) -> void:
	if _completed or room.room_index != _exit_room_index:
		return
	if not room.is_cleared:
		return
	if _current_room_index != room.room_index:
		return
	_completed = true
	floor_completed.emit(floor_number)


## Read-only view of the grid placement, for tests and (later) a minimap.
func cell_of(index: int) -> Vector2i:
	return _cell_of.get(index, Vector2i(-1, -1))


## Which room finishes the floor.
func exit_room() -> int:
	return _exit_room_index


## Which room the player is standing in; -1 before the first placement.
func current_room() -> int:
	return _current_room_index


## Rooms reachable through a single door from `index`. Public because the minimap
## draws the links — the graph itself keeps exactly one source of truth here.
func neighbors_of(index: int) -> Array[int]:
	return _neighbor_rooms(index)


func rooms_remaining() -> int:
	var count := 0
	for room in rooms:
		if not room.is_cleared:
			count += 1
	return count


func clear_percent() -> float:
	if rooms.is_empty():
		return 0.0
	var done := 0
	for room in rooms:
		if room.is_cleared:
			done += 1
	return float(done) / float(rooms.size())
