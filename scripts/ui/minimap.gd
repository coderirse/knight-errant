class_name Minimap
extends Node2D

## The floor's 5x5 room graph, drawn small in the corner.
##
## Why this exists: the player now enters in the **centre** (roadmap §7), so unlike
## the old left-to-right chain there is no obvious "forward". A waypoint arrow would
## solve that by deleting the choice, and the choice is the entire point of the
## layout. A map keeps it and still answers the question that actually recurs:
## "have I already cleared that side?"
##
## Deliberately shows the whole floor rather than fogging it. The rooms are fixed
## once the floor is generated, so hiding them would only hide the doors, and
## deciding which door to take blind is the part players find unfair rather than
## interesting.

const CELL := 9.0
const GAP := 2.0
const STEP := CELL + GAP

## Backing plate, so the map stays legible over both the dark floor and the lit
## wall tiles. Sized from the grid rather than fixed, so a bigger GRID_SIDE later
## cannot leave cells hanging off the edge.
const PLATE_INSET := 3.0
const PLATE_COLOR := Color(0.05, 0.06, 0.10, 0.72)

const COLOR_START := Color(0.42, 0.58, 0.82)
const COLOR_COMBAT := Color(0.72, 0.34, 0.34)
const COLOR_TREASURE := Color(0.94, 0.78, 0.32)
const COLOR_BOSS := Color(0.94, 0.42, 0.24)
const COLOR_LINK := Color(0.34, 0.38, 0.52)
const COLOR_CURRENT := Color(0.96, 0.98, 1.0)
## The exit ring: gold rather than red, because the exit can *be* a treasure room
## or a boss room and the ring has to read independently of the cell's kind.
const COLOR_EXIT := Color(1.0, 0.84, 0.28)

var _level: Level
var _current := -1


func attach(level: Level) -> void:
	_level = level
	if level == null:
		_current = -1
		visible = false
		queue_redraw()
		return

	if not level.room_changed.is_connected(_on_room_changed):
		level.room_changed.connect(_on_room_changed)
	# The initial placement emitted room_changed before we were listening.
	_current = level.current_room()
	visible = true
	queue_redraw()


## Which room is highlighted. The tests read this to prove the signal wiring works
## rather than assuming it.
func current_index() -> int:
	return _current


func _on_room_changed(index: int) -> void:
	_current = index
	queue_redraw()


func _process(_delta: float) -> void:
	# A floor rebuild frees the Level under us; stop drawing a stale graph rather
	# than showing last floor's rooms for a frame.
	if _level != null and not is_instance_valid(_level):
		_level = null
		_current = -1
		visible = false


func _draw() -> void:
	if _level == null or not is_instance_valid(_level):
		return

	var span := float(Level.GRID_SIDE) * STEP - GAP
	draw_rect(Rect2(Vector2(-PLATE_INSET, -PLATE_INSET),
		Vector2(span + PLATE_INSET * 2.0, span + PLATE_INSET * 2.0)), PLATE_COLOR)

	# Links first, so the cells overdraw their ends.
	for i in _level.rooms.size():
		var from := _centre(_level.cell_of(i))
		for j in _level.neighbors_of(i):
			if j <= i:
				continue
			draw_line(from, _centre(_level.cell_of(j)), COLOR_LINK, 2.0)

	var exit_index := _level.exit_room()
	for i in _level.rooms.size():
		var rect := Rect2(_top_left(_level.cell_of(i)), Vector2(CELL, CELL))
		draw_rect(rect, _colour_for(_level.rooms[i].kind))
		if i == exit_index:
			draw_rect(rect.grow(1.5), COLOR_EXIT, false, 1.0)
		if i == _current:
			draw_rect(rect.grow(2.5), COLOR_CURRENT, false, 1.0)


func _top_left(cell: Vector2i) -> Vector2:
	return Vector2(cell.x, cell.y) * STEP


func _centre(cell: Vector2i) -> Vector2:
	return _top_left(cell) + Vector2(CELL * 0.5, CELL * 0.5)


func _colour_for(kind: Room.Kind) -> Color:
	match kind:
		Room.Kind.START:
			return COLOR_START
		Room.Kind.TREASURE:
			return COLOR_TREASURE
		Room.Kind.BOSS:
			return COLOR_BOSS
		_:
			return COLOR_COMBAT
