extends Node

## Autoload "SaveManager".
## JSON slots under user://saves, written atomically (tmp -> rename) with a .bak
## of the previous file, so a crash mid-write can never eat a playthrough.
##
## What is saved is the *permanent* progression (GameState: gems, upgrades,
## unlocked characters, records). A run in progress is deliberately not saved —
## this is a run-based game, so dying is supposed to cost you the run. If you later
## want mid-run saves, add RunState.to_dict() here, but note that the floor layout
## is regenerated from RunState.level_seed, so the seed must go in too.

signal saved(slot: int)
signal loaded(slot: int)

const SAVE_DIR := "user://saves"
const SAVE_VERSION := 1
const SLOT_COUNT := 3


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func slot_path(slot: int) -> String:
	return "%s/slot_%02d.json" % [SAVE_DIR, slot]


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


func save_game(slot: int) -> bool:
	var data := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"engine": Engine.get_version_info().string,
		"game_state": GameState.to_dict(),
	}
	return _write_json(slot_path(slot), data)


func load_game(slot: int) -> bool:
	var data := _read_json(slot_path(slot))
	if data.is_empty():
		return false
	var version := int(data.get("version", 0))
	if version > SAVE_VERSION:
		push_error("SaveManager: slot %d was written by a newer build (v%d)." % [slot, version])
		return false
	# Migrate old versions here as the schema evolves:
	# if version < 2: data = _migrate_v1_to_v2(data)
	GameState.apply_dict(data.get("game_state", {}))
	loaded.emit(slot)
	return true


func delete_save(slot: int) -> void:
	var path := slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func slot_summary(slot: int) -> Dictionary:
	var data := _read_json(slot_path(slot))
	if data.is_empty():
		return {}
	var state: Dictionary = data.get("game_state", {})
	return {
		"saved_at": String(data.get("saved_at", "")),
		"gems": int(state.get("gems", 0)),
		"best_floor": int(state.get("best_floor", 0)),
		"total_runs": int(state.get("total_runs", 0)),
		"playtime": float(state.get("playtime_seconds", 0.0)),
	}


# --- internals -------------------------------------------------------------

func _write_json(path: String, data: Dictionary) -> bool:
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write %s (%s)" % [tmp_path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	var abs_path := ProjectSettings.globalize_path(path)
	var abs_tmp := ProjectSettings.globalize_path(tmp_path)
	if FileAccess.file_exists(path):
		var abs_bak := ProjectSettings.globalize_path(path + ".bak")
		if FileAccess.file_exists(path + ".bak"):
			DirAccess.remove_absolute(abs_bak)
		DirAccess.rename_absolute(abs_path, abs_bak)
	var err := DirAccess.rename_absolute(abs_tmp, abs_path)
	if err != OK:
		push_error("SaveManager: rename failed (%s)" % error_string(err))
		return false
	saved.emit(_slot_of(path))
	return true


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SaveManager: cannot read %s" % path)
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveManager: corrupt save at %s" % path)
		return {}
	return parsed as Dictionary


func _slot_of(path: String) -> int:
	return int(path.get_file().get_basename().replace("slot_", ""))
