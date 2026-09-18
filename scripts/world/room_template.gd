class_name RoomTemplate
extends RefCounted

## A hand-authored room interior.
##
## Templates describe the INTERIOR only — the surrounding wall ring is generated
## by Room. Two invariants make that split work, and both are enforced by
## problems() rather than by discipline:
##
##   1. The outer ring of the interior stays walkable. Level carves doorways at
##      arbitrary points on the perimeter, so a solid tile there would silently
##      wall off a door. Keeping the ring clear means Level never has to inspect
##      the template when placing doors.
##   2. The interior is fully connected. A layout that seals off a pocket would
##      strand enemies (and the player) inside it, and the room would never be
##      cleared — an unwinnable floor that no seed-based test would attribute to
##      the template.
##
## Authored as ASCII rather than as a TileMap scene so it is diffable and
## reviewable while the layouts are still churning. Once they settle these should
## become editor-authored scenes; see docs/roadmap.md §7.

const SOLID := "#"
const FLOOR := "."

var id: StringName
var rows: PackedStringArray
var tags: PackedStringArray


func _init(p_id: StringName = &"", p_rows: PackedStringArray = [], p_tags: PackedStringArray = []) -> void:
	id = p_id
	rows = p_rows
	tags = p_tags


func size() -> Vector2i:
	if rows.is_empty():
		return Vector2i.ZERO
	return Vector2i(rows[0].length(), rows.size())


func has_tag(tag: StringName) -> bool:
	return tags.has(tag)


## Out-of-bounds is treated as solid: a template should never be queried outside
## its own grid, and returning solid makes such a mistake fail safe (a wall)
## rather than silently opening a hole in the room.
func is_solid(local: Vector2i) -> bool:
	if local.y < 0 or local.y >= rows.size():
		return true
	var row := rows[local.y]
	if local.x < 0 or local.x >= row.length():
		return true
	return row[local.x] == SOLID


func is_walkable(local: Vector2i) -> bool:
	if local.y < 0 or local.y >= rows.size():
		return false
	var row := rows[local.y]
	if local.x < 0 or local.x >= row.length():
		return false
	return row[local.x] != SOLID


func walkable_tiles() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in rows.size():
		for x in rows[y].length():
			if is_walkable(Vector2i(x, y)):
				result.append(Vector2i(x, y))
	return result


## Walkable tiles at least `inset` tiles in from the border ring.
##
## Spawns use this rather than a random point in the room rectangle: a random
## point can land inside a pillar, and even a walkable tile on the border ring is
## bad because that is where the doorways are — an enemy standing in the doorway
## would hit the player the instant they entered.
func spawn_tiles(inset := 2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var bounds := size()
	for y in range(inset, bounds.y - inset):
		for x in range(inset, bounds.x - inset):
			if is_walkable(Vector2i(x, y)):
				result.append(Vector2i(x, y))
	return result


## Walkable tile closest to the centre, for one-off placements like a chest.
##
## Uses nearest-to-centre rather than "the centre tile" because the centre of a
## ring or plus layout is often solid.
func center_walkable() -> Vector2i:
	var bounds := size()
	var centre := Vector2(bounds) * 0.5
	var best := Vector2i(-1, -1)
	var best_distance := INF
	for tile in walkable_tiles():
		var distance := Vector2(tile).distance_squared_to(centre)
		if distance < best_distance:
			best_distance = distance
			best = tile
	return best


## Flood fill from the first walkable tile; returns how many tiles it reaches.
func reachable_count() -> int:
	var bounds := size()
	var start := Vector2i(-1, -1)
	for y in bounds.y:
		for x in bounds.x:
			if is_walkable(Vector2i(x, y)):
				start = Vector2i(x, y)
				break
		if start.x >= 0:
			break
	if start.x < 0:
		return 0

	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var tile: Vector2i = queue.pop_front()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = tile + (step as Vector2i)
			if seen.has(next) or not is_walkable(next):
				continue
			seen[next] = true
			queue.append(next)
	return seen.size()


func border_is_clear() -> bool:
	var bounds := size()
	for y in bounds.y:
		for x in bounds.x:
			var on_border := x == 0 or y == 0 or x == bounds.x - 1 or y == bounds.y - 1
			if on_border and is_solid(Vector2i(x, y)):
				return false
	return true


## Everything wrong with this template, as human-readable strings. Empty means
## valid. Called by the test suite so a mistyped row fails loudly instead of
## producing a subtly broken room.
func problems() -> PackedStringArray:
	var found: PackedStringArray = []

	if rows.is_empty():
		found.append("'%s': has no rows" % id)
		return found

	var width := rows[0].length()
	if width == 0:
		found.append("'%s': first row is empty" % id)

	for y in rows.size():
		if rows[y].length() != width:
			found.append("'%s': row %d is %d wide, expected %d" % [id, y, rows[y].length(), width])
	for y in rows.size():
		for x in rows[y].length():
			var symbol := rows[y][x]
			if symbol != SOLID and symbol != FLOOR:
				found.append("'%s': unknown symbol '%s' at (%d,%d)" % [id, symbol, x, y])
				return found

	if not border_is_clear():
		found.append("'%s': outer ring has solid tiles, so a doorway could be blocked" % id)

	var walkable := walkable_tiles().size()
	var reachable := reachable_count()
	if reachable != walkable:
		found.append("'%s': interior is not connected (%d walkable, %d reachable)" % [id, walkable, reachable])

	return found
