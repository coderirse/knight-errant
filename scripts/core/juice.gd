class_name Juice
extends RefCounted

## Small screen-feel helpers shared by player, enemies and bosses.
## Static so they can be called from anywhere without an autoload.


## Freezes the game for a few real-time milliseconds on impact.
## Uses ignore_time_scale so the timer still fires while time_scale == 0.
static func hit_stop(duration := 0.05, scale := 0.0) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	Engine.time_scale = scale
	await tree.create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


## Convenience wrapper: hit stop + camera shake in one call.
static func impact(shake := 4.0, stop := 0.05) -> void:
	shake_camera(shake)
	await hit_stop(stop)


static func shake_camera(amount: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for node in tree.get_nodes_in_group(&"camera_rig"):
		var rig := node as Node
		if rig != null and rig.has_method(&"shake"):
			rig.call(&"shake", amount)
