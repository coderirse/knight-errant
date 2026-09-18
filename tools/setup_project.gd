extends SceneTree

## One-shot project bootstrap.
## Writes autoloads, input map, window/render settings and the main scene, then
## lets Godot serialise project.godot itself so the file format is guaranteed
## correct for this engine version.
##
## Run with:
##   Godot --headless --path . --script res://tools/setup_project.gd
##
## Safe to re-run: it overwrites exactly the keys it owns.

const AUTOLOADS := [
	["GameState", "res://scripts/autoload/game_state.gd"],
	["RunState", "res://scripts/autoload/run_state.gd"],
	["SaveManager", "res://scripts/autoload/save_manager.gd"],
	["PlayerHost", "res://scripts/autoload/player_host.gd"],
	["SceneRouter", "res://scripts/autoload/scene_router.gd"],
	["HUD", "res://scripts/ui/hud.gd"],
	["DebugOverlay", "res://scripts/debug/debug_overlay.gd"],
	["TuningPanel", "res://scripts/debug/tuning_panel.gd"],
]

const KEY_ACTIONS := {
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"dodge": [KEY_SPACE, KEY_SHIFT],
	"fire": [KEY_J],
	"interact": [KEY_E],
	"swap_weapon": [KEY_Q, KEY_TAB],
	"debug_overlay": [KEY_F3],
	"debug_shapes": [KEY_F4],
	"debug_god": [KEY_F7],
	"debug_reload": [KEY_F9],
	"debug_cheat": [KEY_F10],
	# Tuning bench. Deliberately built from keys the gameplay bindings do not use,
	# so parameters can be adjusted while still moving and shooting.
	"tune_panel": [KEY_F2],
	"tune_prev": [KEY_BRACKETLEFT],
	"tune_next": [KEY_BRACKETRIGHT],
	"tune_down": [KEY_MINUS],
	"tune_up": [KEY_EQUAL],
	"tune_reset": [KEY_F5],
	"tune_dump": [KEY_F6],
}

## action -> joypad buttons. A = 0, B = 1, X = 2, Y = 3 on Xbox layout.
##
## Every action named here must also be in KEY_ACTIONS or RETIRED_ACTIONS; a name
## only in this table is written here and pruned there, on every run.
const JOY_ACTIONS := {
	"dodge": [0, 5],
	"fire": [7, 10],
	"interact": [2],
	"swap_weapon": [3, 9],
}

## action -> [axis index, direction]. Left stick = axes 0/1, right stick = 2/3.
const AXIS_ACTIONS := {
	"move_left": [1, -1.0],
	"move_right": [1, 1.0],
	"move_up": [0, -1.0],
	"move_down": [0, 1.0],
	"aim_left": [2, -1.0],
	"aim_right": [2, 1.0],
	"aim_up": [3, -1.0],
	"aim_down": [3, 1.0],
}

## Mouse buttons live on their own actions so the twin-stick layout can fire
## without also firing when a gamepad trigger is half-pressed.
const MOUSE_ACTIONS := {
	"fire": [MOUSE_BUTTON_LEFT],
	"dodge": [MOUSE_BUTTON_RIGHT],
}


func _initialize() -> void:
	_setup_application()
	_setup_window()
	_setup_physics()
	_setup_input()
	_setup_autoloads()
	ProjectSettings.save()
	print("project.godot updated")
	quit()


func _setup_application() -> void:
	ProjectSettings.set_setting("application/config/name", "Knight Errant")
	ProjectSettings.set_setting("application/run/main_scene", "res://scenes/ui/main_menu.tscn")
	ProjectSettings.set_setting("application/config/icon", "res://assets/placeholder/player.png")
	ProjectSettings.set_setting("application/config/features", PackedStringArray(["4.7", "Forward Plus"]))


func _setup_window() -> void:
	# 480x270 virtual resolution: the same 16:9 canvas Soul Knight targets, and a
	# clean 4x scale to 1080p. Characters are ~20px tall on screen, which is the
	# floor for chibi sprites to stay readable in a twin-stick game where several
	# enemies and bullets share the screen.
	ProjectSettings.set_setting("display/window/size/viewport_width", 480)
	ProjectSettings.set_setting("display/window/size/viewport_height", 270)
	ProjectSettings.set_setting("display/window/size/window_width_override", 1440)
	ProjectSettings.set_setting("display/window/size/window_height_override", 810)
	ProjectSettings.set_setting("display/window/size/resizable", true)
	ProjectSettings.set_setting("display/window/stretch/mode", "canvas_items")
	ProjectSettings.set_setting("display/window/stretch/aspect", "keep")
	ProjectSettings.set_setting("display/window/stretch/scale_mode", "integer")
	ProjectSettings.set_setting("display/window/vsync/vsync_mode", 1)

	ProjectSettings.set_setting("rendering/textures/canvas_textures/default_texture_filter", 0)
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/msaa_2d", 0)
	ProjectSettings.set_setting("rendering/2d/snap/snap_2d_transforms_to_pixel", false)
	ProjectSettings.set_setting("rendering/2d/snap/snap_2d_vertices_to_pixel", false)
	# The rock between rooms is whatever the viewport clears to. Engine-default
	# grey read as "unfinished"; near-black reads as unexcavated stone.
	ProjectSettings.set_setting("rendering/environment/defaults/default_clear_color",
		Color(0.05, 0.05, 0.08))


func _setup_physics() -> void:
	# Top-down: nothing falls. The player and enemies are CharacterBody2D with
	# MOTION_MODE_FLOATING and integrate their own motion, so this only matters
	# for stray RigidBody2D props — but leaving gravity at 980 means any rigid
	# debris added later slides off the bottom of the screen.
	ProjectSettings.set_setting("physics/2d/default_gravity", 0.0)
	ProjectSettings.set_setting("physics/common/physics_ticks_per_second", 60)


func _setup_input() -> void:
	_report_table_conflicts()

	for action in KEY_ACTIONS.keys():
		var events: Array[InputEvent] = []
		for keycode in KEY_ACTIONS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			events.append(event)
		_write_action(action, events)

	for action in MOUSE_ACTIONS.keys():
		var events: Array[InputEvent] = []
		for button in MOUSE_ACTIONS[action]:
			var event := InputEventMouseButton.new()
			event.button_index = button
			events.append(event)
		_write_action(action, events, true)

	for action in JOY_ACTIONS.keys():
		var events: Array[InputEvent] = []
		for button in JOY_ACTIONS[action]:
			var event := InputEventJoypadButton.new()
			event.button_index = button
			events.append(event)
		_write_action(action, events, true)

	for action in AXIS_ACTIONS.keys():
		var axis: Array = AXIS_ACTIONS[action]
		var event := InputEventJoypadMotion.new()
		event.axis = int(axis[0])
		event.axis_value = float(axis[1])
		_write_action(action, [event], true)

	# Prune LAST. Running it first means any name present in both a live table
	# and RETIRED_ACTIONS is deleted and then immediately written back — which is
	# exactly what happened when `pause` lingered in JOY_ACTIONS while being
	# listed as retired. Pruning last makes the retired list win unconditionally.
	_prune_retired_actions()


## Fails loudly when a name is both retired and live, since the outcome would
## otherwise depend on execution order.
func _report_table_conflicts() -> void:
	var live := {}
	for table in [KEY_ACTIONS, JOY_ACTIONS, AXIS_ACTIONS, MOUSE_ACTIONS]:
		for action in table.keys():
			live[action] = true
	for action in RETIRED_ACTIONS:
		if live.has(action):
			push_error("setup_project: '%s' is in RETIRED_ACTIONS and a live input table; remove it from one" % action)


## Actions that were deleted from the code but linger in project.godot.
##
## Retired by name rather than "everything not in the tables above", because that
## broader rule has two failure modes this project already hit:
##
##  1. It also matches Godot's built-in `ui_*` navigation actions (90+ of them),
##     deleting them from project.godot. That turns out to be harmless — the
##     engine restores the defaults at startup, verified at runtime — but it
##     makes the file's contents unpredictable and would silently discard any
##     re-binding a user had made in the editor.
##  2. It would delete any action someone adds through the editor UI without
##     also adding it to the tables above.
##
## So: retired actions are listed explicitly, and anything unrecognised is left
## alone.
const RETIRED_ACTIONS: Array[String] = [
	# Side-scrolling build leftovers; their code was deleted long ago.
	"jump", "attack", "dash", "focus", "pause", "debug_unlock_all",
]


func _prune_retired_actions() -> void:
	var removed: Array[String] = []
	for action in RETIRED_ACTIONS:
		var setting := "input/%s" % action
		if not ProjectSettings.has_setting(setting):
			continue
		ProjectSettings.set_setting(setting, null)
		removed.append(action)
	if not removed.is_empty():
		print("pruned retired input actions: %s" % [", ".join(removed)])


## InputMap.add_action() only mutates the runtime map; it does not write
## "input/*" into ProjectSettings, so the actions have to be written directly in
## the format the editor reads back.
func _write_action(action: String, events: Array, append := false) -> void:
	var setting := "input/%s" % action
	var existing: Dictionary = ProjectSettings.get_setting(setting, {}) if append else {}
	var merged: Array = existing.get("events", []) if append else []
	for event in events:
		merged.append(event)
	ProjectSettings.set_setting(setting, {
		"deadzone": float(existing.get("deadzone", 0.25)),
		"events": merged,
	})


func _setup_autoloads() -> void:
	for entry in AUTOLOADS:
		ProjectSettings.set_setting("autoload/%s" % entry[0], "*%s" % entry[1])
