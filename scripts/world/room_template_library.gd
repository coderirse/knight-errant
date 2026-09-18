class_name RoomTemplateLibrary
extends RefCounted

## The room template catalogue, grouped by interior size.
##
## Level asks for a size; this returns a template of that size. The size comes
## from the level generator (Soul Knight-style fixed 15 / 21 / 25 for combat
## rooms) rather than from the template, so door alignment stays exact — see
## Level._plan_sizes() and Level._connect().
##
## Templates are ASCII: '.' walkable, '#' solid. They cover the interior only;
## Room generates the surrounding wall ring. Every template is checked by
## validate_all(), which the test suite calls, so a mistyped row or an unsealed
## pocket fails a test instead of producing a subtly broken room.
##
## To add a layout: append an entry here, keep the outer ring clear of '#' (or a
## doorway may be blocked) and the interior connected. Nothing else needs to
## change — Room picks templates by size, not by id.

## size (as "WxH") -> array of template dictionaries.
const TEMPLATES: Array[Dictionary] = [
	{
		"id": &"open_s",
		"size": Vector2i(15, 15),
		"tags": [&"open"],
		"rows": [
			"...............",
			"...............",
			"...............",
			"...............",
			"...............",
			"...............",
			"...............",
			"...............",
			"...............",
			"...............",
			"...............",
			"...............",
			"...............",
			"...............",
			"...............",
		],
	},
	{
		"id": &"pillars_s",
		"size": Vector2i(15, 15),
		"tags": [],
		"rows": [
			"...............",
			"...............",
			"...............",
			"...##.....##...",
			"...##.....##...",
			"...............",
			"...............",
			"...............",
			"...............",
			"...............",
			"...##.....##...",
			"...##.....##...",
			"...............",
			"...............",
			"...............",
		],
	},
	{
		"id": &"weave_s",
		"size": Vector2i(15, 15),
		"tags": [],
		"rows": [
			"...............",
			".....#.........",
			".....#.........",
			".....#.........",
			".....#.........",
			".....#.........",
			"...............",
			"...............",
			"...............",
			".........#.....",
			"..###....#.....",
			".........#.....",
			".........#.....",
			".........#.....",
			"...............",
		],
	},
	{
		"id": &"open_m",
		"size": Vector2i(21, 21),
		"tags": [&"open"],
		"rows": [
			".....................",
			".....................",
			".....................",
			".....................",
			".....................",
			".....................",
			".....................",
			".....................",
			".....................",
			".....................",
			".....................",
			".....................",
			".....................",
			".....................",
			".....................",
			".....................",
			".....................",
			".....................",
			".....................",
			".....................",
			".....................",
		],
	},
	{
		"id": &"ring_m",
		"size": Vector2i(21, 21),
		"tags": [],
		"rows": [
			".....................",
			".....................",
			".....................",
			".....................",
			".....................",
			".....................",
			"......###...###......",
			"......#.......#......",
			"......#.......#......",
			".....................",
			".....................",
			".....................",
			"......#.......#......",
			"......#.......#......",
			"......###...###......",
			".....................",
			".....................",
			".....................",
			".....................",
			".....................",
			".....................",
		],
	},
	{
		"id": &"cross_m",
		"size": Vector2i(21, 21),
		"tags": [],
		"rows": [
			".....................",
			".....................",
			".....................",
			"..........#..........",
			"..........#..........",
			"..........#..........",
			"..........#..........",
			"..........#..........",
			"..........#..........",
			"..........#..........",
			"...###############...",
			"..........#..........",
			"..........#..........",
			"..........#..........",
			"..........#..........",
			"..........#..........",
			"..........#..........",
			"..........#..........",
			".....................",
			".....................",
			".....................",
		],
	},
	{
		"id": &"open_l",
		"size": Vector2i(25, 25),
		"tags": [&"open"],
		"rows": [
			".........................",
			".........................",
			".........................",
			".........................",
			".........................",
			".........................",
			".........................",
			".........................",
			".........................",
			".........................",
			".........................",
			".........................",
			".........................",
			".........................",
			".........................",
			".........................",
			".........................",
			".........................",
			".........................",
			".........................",
			".........................",
			".........................",
			".........................",
			".........................",
			".........................",
		],
	},
	{
		"id": &"arena_l",
		"size": Vector2i(25, 25),
		"tags": [],
		"rows": [
			".........................",
			".........................",
			".........................",
			".........................",
			"....#####.......#####....",
			"....#...............#....",
			"....#...............#....",
			"....#...............#....",
			"....#...............#....",
			".........................",
			".........................",
			".........................",
			".........................",
			".........................",
			".........................",
			".........................",
			"....#...............#....",
			"....#...............#....",
			"....#...............#....",
			"....#...............#....",
			"....#####.......#####....",
			".........................",
			".........................",
			".........................",
			".........................",
		],
	},
	{
		"id": &"cols_l",
		"size": Vector2i(25, 25),
		"tags": [],
		"rows": [
			".........................",
			".........................",
			".........................",
			".........................",
			"......##.........##......",
			"......##.........##......",
			"......##.........##......",
			"......##.........##......",
			"......##.........##......",
			"......##.........##......",
			"......##.........##......",
			"......##.........##......",
			"...........##............",
			"...........##............",
			"...........##............",
			"...........##............",
			"...........##............",
			"...........##............",
			"...........##............",
			"...........##............",
			"...........##............",
			".........................",
			".........................",
			".........................",
			".........................",
		],
	},
]

## Parsed templates, built once per session. Templates are immutable, so caching
## them is safe and keeps generation cheap (Level asks on every room).
static var _cache: Array[RoomTemplate] = []


static func all() -> Array[RoomTemplate]:
	if _cache.is_empty():
		for entry in TEMPLATES:
			_cache.append(RoomTemplate.new(
				entry.get("id", &"unnamed"),
				PackedStringArray(entry.get("rows", [])),
				PackedStringArray(entry.get("tags", [])),
			))
	return _cache


## Templates whose size matches exactly. Empty when nothing fits, which the
## caller must treat as "no template for this size" rather than falling back to
## a default — a wrong-sized template would overflow its room.
static func for_size(size: Vector2i) -> Array[RoomTemplate]:
	var result: Array[RoomTemplate] = []
	for template in all():
		if template.size() == size:
			result.append(template)
	return result


## Picks a template of `size`. When `prefer_tag` is set, tagged templates are
## used if any exist, otherwise any template of that size is acceptable.
##
## Returns null when no template matches the size. Room treats null as "build a
## plain open arena", so a missing template degrades to the previous behaviour
## instead of leaving the room empty.
static func pick(size: Vector2i, rng: RandomNumberGenerator, prefer_tag: StringName = &"") -> RoomTemplate:
	var candidates := for_size(size)
	if candidates.is_empty():
		return null

	if prefer_tag != &"":
		var tagged: Array[RoomTemplate] = []
		for template in candidates:
			if template.has_tag(prefer_tag):
				tagged.append(template)
		if not tagged.is_empty():
			candidates = tagged

	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func sizes() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for template in all():
		var size: Vector2i = template.size()
		if not result.has(size):
			result.append(size)
	return result


## Every problem found across the catalogue, as human-readable strings.
static func validate_all() -> PackedStringArray:
	var found: PackedStringArray = []
	if TEMPLATES.is_empty():
		found.append("template catalogue is empty")
		return found

	var seen_ids: Array[StringName] = []
	for template in all():
		if seen_ids.has(template.id):
			found.append("duplicate template id '%s'" % template.id)
		seen_ids.append(template.id)
		found.append_array(template.problems())
	return found
