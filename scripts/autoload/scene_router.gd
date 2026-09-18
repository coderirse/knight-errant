extends Node

## Autoload "SceneRouter".
## Scene switching with a fade: main menu <-> run.
##
## In this design the whole floor is one scene (all rooms instantiated at once),
## so this router only handles the coarse transitions — menu to run, run to menu.
## Walking through a doorway inside a floor is a teleport handled by Level, not a
## scene change, which is why there is no room-level API here anymore.
##
## The player is owned by PlayerHost rather than by a scene, so it must be
## detached before the old scene is freed. See detach_player() below.

signal scene_changed(scene_path: String)

const FADE_TIME := 0.25

var _busy := false
var _layer: CanvasLayer
var _fade: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(_fade)


func is_busy() -> bool:
	return _busy


## Fades out, swaps the scene, fades in. Blocks until the new scene is current.
##
## Every step that can fail (bad path, unloadable scene) runs BEFORE the global
## state is touched. That ordering is deliberate: an earlier version read a
## property that did not exist *after* fading to black and pausing the tree, so
## the exception killed the coroutine with `paused = true` and `input_locked =
## true` still set — a permanent black screen with every later transition
## silently refused. Loading first means a failure can only return early.
func go_to_scene(scene_path: String) -> void:
	if _busy:
		return
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_error("SceneRouter: cannot load %s" % scene_path)
		return
	var packed := ResourceLoader.load(scene_path) as PackedScene
	if packed == null:
		push_error("SceneRouter: %s is not a PackedScene" % scene_path)
		return

	_busy = true
	GameState.input_locked = true
	get_tree().paused = true
	await _fade_to(1.0)

	# The player lives outside the scene tree's current scene, so pull it back
	# under PlayerHost before the outgoing scene is freed. Unconditional: both
	# callers change to a different scene, and a same-scene reload would still
	# need the player out before the old instance is freed.
	PlayerHost.detach()

	var err := get_tree().change_scene_to_packed(packed)
	if err != OK:
		push_error("SceneRouter: change_scene_to_packed failed (%s)" % error_string(err))
		await _abort()
		return

	if not await _await_current_scene(scene_path):
		await _abort()
		return

	scene_changed.emit(scene_path)
	await _release()
	await _fade_to(0.0)


## Starts a fresh run from the menu.
func start_new_run(seed_value := 0) -> void:
	PlayerHost.despawn()
	await go_to_scene("res://scenes/world/game.tscn")
	var game := get_tree().current_scene as Game
	if game == null:
		push_error("SceneRouter: game scene did not load")
		await _release()
		return
	await game.start_run(seed_value)
	await _release()


# --- internals -------------------------------------------------------------

## Restores every piece of global state the transition touched.
##
## One function on purpose. These three flags used to be reset inline on the
## success path while `_abort()` reset them separately, and a restructure dropped
## `paused = false` from the success path — a frozen game whose router still
## reported itself idle. Keeping the reset in a single place means the two paths
## cannot drift again.
func _release() -> void:
	get_tree().paused = false
	GameState.input_locked = false
	_busy = false


func _abort() -> void:
	await _release()
	await _fade_to(0.0)


## Blocks until the requested scene is current. change_scene_to_packed() swaps on
## a deferred call that can land on either side of the next process_frame, so
## waiting a fixed number of frames is a coin flip; wait for the observable state.
##
## Returns false on timeout so the caller can restore the paused/input-locked
## state instead of leaving the game frozen.
func _await_current_scene(scene_path: String, timeout_frames := 600) -> bool:
	var frames := 0
	while frames < timeout_frames:
		var current := get_tree().current_scene
		if current != null and current.scene_file_path == scene_path:
			await get_tree().process_frame
			return true
		await get_tree().process_frame
		frames += 1
	push_error("SceneRouter: timed out waiting for %s to become current" % scene_path)
	return false


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_fade, "color:a", alpha, FADE_TIME)
	await tween.finished
