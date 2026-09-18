class_name WeaponRegistry
extends RefCounted

## Loads WeaponData by id from res://resources/weapons/. Static so it can be
## called from anywhere without an autoload, and cached so repeated lookups in a
## fire loop stay cheap.

const DIR := "res://resources/weapons"

static var _cache: Dictionary = {}


static func load_data(id: StringName) -> WeaponData:
	if _cache.has(id):
		return _cache[id] as WeaponData
	var path := "%s/%s.tres" % [DIR, String(id)]
	if not ResourceLoader.exists(path):
		push_error("WeaponRegistry: no weapon data at %s" % path)
		return null
	var data := ResourceLoader.load(path) as WeaponData
	_cache[id] = data
	return data


static func exists(id: StringName) -> bool:
	return ResourceLoader.exists("%s/%s.tres" % [DIR, String(id)])


## Ids of every weapon asset in the project. Used by the debug overlay and by
## random weapon drops, so a new .tres is picked up without touching code.
static func all_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return ids
	for file_name in dir.get_files():
		if file_name.ends_with(".tres"):
			ids.append(StringName(file_name.get_basename()))
	ids.sort()
	return ids


## Weapon drops from chests and enemies. Melee is excluded so the player always
## has something to spend energy on from a random roll.
static func random_ranged_id(rng: RandomNumberGenerator) -> StringName:
	var candidates: Array[StringName] = []
	for id in all_ids():
		var data := load_data(id)
		if data != null and not data.is_melee:
			candidates.append(id)
	if candidates.is_empty():
		return &"pistol"
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func clear_cache() -> void:
	_cache.clear()
