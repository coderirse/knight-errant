class_name Game
extends Node2D

## Root of a play session: owns the floor, the camera, and the run lifecycle.
##
## Flow:
##   start_run()  -> generate floor 1, spawn the player
##   player dies  -> end_run()  -> back to the menu
##   exit cleared -> advance_floor() -> generate the next floor
##
## There is no save-anywhere here on purpose. A run-based game saves between runs
## (permanent progression in GameState), not mid-run, so the only thing that needs
## persisting from a run is the best floor reached.

const LEVEL_SCENE := "res://scenes/world/level.tscn"
const TILESET_PATH := "res://resources/tilesets/prototype_tileset.tres"

signal run_finished(victory: bool)

@onready var camera: CameraRig = $CameraRig
@onready var level_holder: Node2D = $LevelHolder

var level: Level
var player: Player

var _gems_earned := 0
var _floor_pending_advance := false


func _ready() -> void:
	add_to_group(&"game")


## Blocks until the floor is built and the player is in it.
func start_run(seed_value := 0) -> void:
	RunState.start_run(seed_value)
	GameState.begin_playtime()
	await build_floor(RunState.floor, RunState.level_seed)


func build_floor(floor_number: int, seed_value: int) -> void:
	_clear_level()

	var packed := load(LEVEL_SCENE) as PackedScene
	if packed == null:
		push_error("Game: cannot load %s" % LEVEL_SCENE)
		return
	level = packed.instantiate() as Level
	level.tile_set = load(TILESET_PATH) as TileSet
	level_holder.add_child(level)
	level.floor_completed.connect(_on_floor_completed)
	level.generate(floor_number, seed_value)

	_spawn_player()
	level.player = player
	level._place_player()
	# After placement: the minimap reads the current room on attach, and the initial
	# room_changed fires before anything is listening.
	HUD.attach_level(level)

	# Levels are static geometry; tell the tile map it can stop updating layer data
	# now that the layout is final.
	for room in level.rooms:
		var layer := room.get_node_or_null("Terrain/Ground") as TileMapLayer
		if layer != null:
			layer.update_internals()

	# Camera follows the player and is bounded to the floor's extent.
	camera.set_target(player)
	camera.set_room_bounds(level_bounds())
	camera.snap_to_target()


func _spawn_player() -> void:
	# PlayerHost owns the instance so it survives floor rebuilds. On the second
	# and later floors this returns the same object, keeping weapons and health.
	var already_existed := PlayerHost.has_player()
	player = PlayerHost.adopt(level_holder)
	if player == null:
		return

	if not already_existed:
		# Permanent upgrades are applied once, on creation, so a run always starts
		# from the meta progression bought between runs.
		player.apply_meta_upgrades()
	if not player.died.is_connected(_on_player_died):
		player.died.connect(_on_player_died)


func level_bounds() -> Rect2:
	if level == null or level.rooms.is_empty():
		return Rect2()
	var bounds := Rect2(level.rooms[0].position, level.rooms[0].world_size())
	for room in level.rooms:
		bounds = bounds.merge(Rect2(room.position, room.world_size()))
	return bounds


func _clear_level() -> void:
	for child in level_holder.get_children():
		if child == player:
			# The player survives a floor rebuild so weapons and health carry over;
			# only the level geometry is replaced.
			continue
		child.queue_free()
	level = null


func _on_player_died() -> void:
	run_finished.emit(false)
	GameState.record_run_finished(RunState.floor, RunState.kills, _gems_earned)
	RunState.end_run(false)
	await get_tree().create_timer(1.4).timeout
	await SceneRouter.go_to_scene("res://scenes/ui/main_menu.tscn")
	# Free the corpse once we are back in the hub. It is detached (not freed) by
	# the scene change, so without this it lingers in PlayerHost and is returned
	# by get_nodes_in_group(&"player") while the player is in the menu.
	PlayerHost.despawn()
	player = null


func _on_floor_completed(floor_number: int) -> void:
	if _floor_pending_advance:
		return
	_floor_pending_advance = true

	# Award gems for the floor, then offer the next one. Gems are the bridge from
	# run state to permanent state.
	_gems_earned += 5 + floor_number * 2
	RunState.advance_floor()
	print("[run] floor %d cleared, descending to %d" % [floor_number, RunState.floor])

	await get_tree().create_timer(0.6).timeout
	await build_floor(RunState.floor, RunState.level_seed)
	_floor_pending_advance = false
