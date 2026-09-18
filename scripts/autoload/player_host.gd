extends Node

## Autoload "PlayerHost".
## Owns the single player instance for the whole session.
##
## The player is not part of a scene because it has to survive scene changes
## (menu -> run -> menu) and floor rebuilds while keeping its weapons, energy and
## health. Scenes only *adopt* it:
##   - Game._spawn_player() creates it on the first run of a session;
##   - Game._clear_level() rebuilds the floor but deliberately leaves the player
##     alone, so descending a floor does not reset the build;
##   - despawn() is called when returning to the menu, so the next run starts
##     fresh instead of inheriting a dead player's state.

const PLAYER_SCENE := "res://scenes/player/player.tscn"

var player: Player

var _container: Node2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_container = Node2D.new()
	_container.name = "PlayerContainer"
	add_child(_container)


func has_player() -> bool:
	return player != null and is_instance_valid(player)


func spawn_player() -> Player:
	if has_player():
		return player
	var packed := load(PLAYER_SCENE) as PackedScene
	if packed == null:
		push_error("PlayerHost: cannot load %s" % PLAYER_SCENE)
		return null
	player = packed.instantiate() as Player
	if player == null:
		push_error("PlayerHost: %s root is not a Player" % PLAYER_SCENE)
		return null
	_container.add_child(player)
	return player


## Creates the player if needed and hands it to the scene. The caller is
## responsible for positioning it.
func adopt(scene: Node) -> Player:
	var instance := spawn_player()
	if instance != null and scene != null and instance.get_parent() != scene:
		instance.reparent(scene, true)
	return instance


func despawn() -> void:
	if not has_player():
		return
	player.queue_free()
	player = null


## Pulls the player back out of a scene that is about to be freed.
func detach() -> void:
	if not has_player():
		return
	if player.get_parent() != _container:
		player.reparent(_container, true)
