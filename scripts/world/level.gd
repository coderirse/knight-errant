class_name Level
extends Node2D

## Builds and drives one floor of the dungeon: a small graph of rooms laid out in
## a grid, with doorways carved between neighbours.
##
## Layout rule (deliberately simple and readable): rooms sit on a grid, the player
## enters at the left, and one room on the right is the exit. Extra rooms branch
## off the main path as optional treasure. Every room on the guaranteed path from
## entry to exit is COMBAT or BOSS, so the run cannot be walked through empty.
##
## The whole floor is one scene, not one scene per room. Rooms are 480x270-ish
## arenas; keeping them all loaded means walking through a door is a camera move,
## not a scene reload, so there is no hitch and no state to serialise. This is the
## single biggest structural difference from the side-scrolling build, where each
## room was its own .tscn.

signal floor_completed(floor_number: int)
signal player_died

const ROOM_SCENE := "res://scenes/world/room.tscn"
const TILE := 16
## Interior size used only when the template catalogue is empty (see _plan_sizes).
const DEFAULT_INTERIOR := 21
## Gap of solid rock between adjacent rooms, in tiles.
const ROOM_GAP := 2

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


func generate(floor_num: int, level_seed: int) -> void:
	floor_number = floor_num
	seed_value = level_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = level_seed

	_plan_layout(rng)
	_instantiate_rooms()
	_carve_doors()
	_place_player()


# --- layout ----------------------------------------------------------------

## Lays out a left-to-right chain with occasional branches, then assigns a kind
## to each room. The chain is the guaranteed path; branches are optional.
##
## Chain steps are restricted to orthogonal grid moves. A diagonal step would put
## two consecutive path rooms at grid positions that share no wall, and since
## doors can only be carved between physical neighbours, the path would silently
## be broken — the player reaches a dead end and the floor cannot be finished.
## Rooms still *look* scattered because the side-steps alternate the row.
##
## Planning works entirely on the local `cells` array. Reading `_grid` here would
## see the *previous* floor's cells (it is rebuilt only at the end).
func _plan_layout(rng: RandomNumberGenerator) -> void:
	var chain_length := clampi(3 + floor_number, 3, 6)
	var branches := clampi(1 + floor_number / 2, 1, 3)

	var cells: Array[Vector2i] = [Vector2i.ZERO]
	var cursor := Vector2i.ZERO

	for step_index in chain_length - 1:
		# Step right most of the time, sometimes up or down; never left, so
		# progress is monotonic and the player can tell which way is forward.
		var options: Array[Vector2i] = [
			Vector2i(1, 0), Vector2i(1, 0), Vector2i(1, 0),
			Vector2i(0, -1), Vector2i(0, 1),
		]
		var next := cursor + options[rng.randi_range(0, options.size() - 1)]

		# Keep the layout in positive space so world coordinates stay simple.
		if next.y < 0:
			for index in cells.size():
				cells[index] += Vector2i(0, 1)
			cursor += Vector2i(0, 1)
			next += Vector2i(0, 1)

		if cells.has(next):
			next = cursor + Vector2i(1, 0)
			while cells.has(next):
				next += Vector2i(1, 0)
		cells.append(next)
		cursor = next

	# Branches: hang optional rooms off existing ones. Orthogonal only, so the
	# branch always shares a wall with its parent and a door can be carved.
	for branch_index in branches:
		var base: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		var offsets: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0)]
		var candidate := base + offsets[rng.randi_range(0, offsets.size() - 1)]
		if candidate.y < 0:
			candidate = base + Vector2i(0, 1)
		if not cells.has(candidate):
			cells.append(candidate)

	_path.clear()
	_grid.clear()
	_cell_of.clear()
	for i in cells.size():
		var cell := cells[i]
		_grid[cell] = i
		_cell_of[i] = cell
		# The chain is the first `chain_length` entries; everything after is a
		# branch, so the path to the exit is exactly the chain.
		if i < chain_length:
			_path.append(i)

	_exit_room_index = _path[_path.size() - 1]


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
