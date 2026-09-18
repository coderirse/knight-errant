extends SceneTree

## Builds the tile set, weapon resources, level/game scenes and the main menu,
## then writes them out as normal .tscn / .tres files.
##
## Run with:
##   Godot --headless --path . --script res://tools/build_scenes.gd
##
## Generating scenes from code instead of hand-writing .tscn text guarantees the
## files match this engine version's format, and the definitions below double as
## documentation for how a scene is assembled.
##
## This is scaffolding. Once you start authoring rooms in the TileMap editor,
## delete this script and edit the scenes directly.

const TILE := 16
const TILESET_PATH := "res://resources/tilesets/prototype_tileset.tres"
const TILE_TEXTURE := "res://assets/placeholder/tile_ground.png"
const WEAPON_DIR := "res://resources/weapons"

const LEVEL_SCENE := "res://scenes/world/level.tscn"
const ROOM_SCENE := "res://scenes/world/room.tscn"
const GAME_SCENE := "res://scenes/world/game.tscn"
const MAIN_MENU := "res://scenes/ui/main_menu.tscn"

## Weapon definitions: id -> stats. Tuning these is the fastest way to change how
## the game feels, so they live in one readable table.
const WEAPONS := [
	{
		"id": &"pistol", "name": "Rusty Pistol", "damage": 2, "fire_rate": 4.0,
		"spread": 3.0, "count": 1, "speed": 320.0, "energy": 1.0, "recovery": 0.02,
		"knockback": 90.0, "icon": "gun_pistol.png", "tint": Color(1, 1, 1, 1),
		"scale": 1.0, "desc": "starting sidearm",
		"ammo": 12, "reload": 1.1, "scatter_final": 12.0, "crit_rate": 0.10,
	},
	{
		"id": &"shotgun", "name": "Scrap Shotgun", "damage": 2, "fire_rate": 1.3,
		"spread": 34.0, "count": 5, "speed": 250.0, "energy": 8.0, "recovery": 0.18,
		"knockback": 220.0, "icon": "gun_shotgun.png", "tint": Color(1.0, 0.85, 0.6),
		"scale": 1.15, "desc": "short range, heavy stagger",
		"ammo": 6, "reload": 1.6, "scatter_final": 44.0, "scatter_per_shot": 6.0,
	},
	{
		"id": &"smg", "name": "Chatter SMG", "damage": 1, "fire_rate": 11.0,
		"spread": 11.0, "count": 1, "speed": 360.0, "energy": 1.5, "recovery": 0.0,
		"knockback": 45.0, "icon": "gun_pistol.png", "tint": Color(0.7, 0.95, 1.0),
		"scale": 0.85, "desc": "spray, eats energy",
		"ammo": 30, "reload": 1.4, "scatter_final": 26.0, "scatter_per_shot": 2.0,
	},
	{
		"id": &"railgun", "name": "Piercer", "damage": 4, "fire_rate": 1.1,
		"spread": 0.0, "count": 1, "speed": 700.0, "energy": 12.0, "recovery": 0.25,
		"knockback": 260.0, "pierce": 4, "icon": "gun_pistol.png",
		"tint": Color(0.75, 0.6, 1.0), "scale": 1.3, "desc": "pierces a line",
		"ammo": 4, "reload": 1.8, "type": &"pierce", "crit_rate": 0.20,
	},
	{
		"id": &"sword", "name": "Chipped Blade", "damage": 3, "fire_rate": 2.2,
		"is_melee": true, "melee_range": 24.0, "energy": 0.0, "recovery": 0.06,
		"knockback": 240.0, "icon": "sword.png", "tint": Color(1, 1, 1, 1),
		"scale": 1.0, "desc": "free swings, no ammo",
	},
	{
		"id": &"launcher", "name": "Scrap Launcher", "damage": 3, "fire_rate": 0.9,
		"spread": 2.0, "count": 1, "speed": 220.0, "energy": 10.0, "recovery": 0.2,
		"knockback": 200.0, "icon": "gun_shotgun.png", "tint": Color(1.0, 0.6, 0.3),
		"scale": 1.4, "desc": "lobbed shell, area damage on impact",
		"ammo": 4, "reload": 2.0, "type": &"explosive",
		"explode_radius": 44.0, "explode_damage": 2, "lifetime": 0.9,
	},
	{
		"id": &"splitter", "name": "Splitter Wand", "damage": 2, "fire_rate": 2.0,
		"spread": 4.0, "count": 1, "speed": 260.0, "energy": 6.0, "recovery": 0.1,
		"knockback": 80.0, "icon": "gun_pistol.png", "tint": Color(1.0, 0.5, 0.7),
		"scale": 1.1, "desc": "bolt fans out when it expires",
		"ammo": 10, "reload": 1.3, "type": &"fire", "split": 3, "lifetime": 0.55,
	},
	{
		"id": &"ricochet", "name": "Nail Ricochet", "damage": 1, "fire_rate": 6.0,
		"spread": 6.0, "count": 1, "speed": 340.0, "energy": 1.0, "recovery": 0.0,
		"knockback": 60.0, "icon": "gun_pistol.png", "tint": Color(0.6, 1.0, 0.7),
		"scale": 0.9, "desc": "nails bounce off walls",
		"ammo": 24, "reload": 1.2, "bounce": 2,
	},
	{
		"id": &"enemy_pistol", "name": "Cultist Wand", "damage": 1, "fire_rate": 1.0,
		"spread": 4.0, "count": 1, "speed": 190.0, "energy": 0.0, "recovery": 0.0,
		"knockback": 70.0, "icon": "gun_pistol.png", "tint": Color(1.0, 0.5, 0.4),
		"scale": 1.0, "desc": "enemy weapon",
	},
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://resources/tilesets")
	DirAccess.make_dir_recursive_absolute(WEAPON_DIR)
	DirAccess.make_dir_recursive_absolute("res://scenes/world")
	DirAccess.make_dir_recursive_absolute("res://scenes/ui")

	var tile_set := _build_tile_set()
	ResourceSaver.save(tile_set, TILESET_PATH)
	print("tile set -> %s" % TILESET_PATH)

	_build_weapons()
	_build_projectile_scene()
	_build_room_scene(tile_set)
	_build_level_scene(tile_set)
	_build_game_scene()
	_build_main_menu()

	print("scenes written")
	quit()


# --- tile set --------------------------------------------------------------

func _build_tile_set() -> TileSet:
	var atlas := TileSetAtlasSource.new()
	atlas.texture = load(TILE_TEXTURE) as Texture2D
	atlas.texture_region_size = Vector2i(TILE, TILE)
	# Three tiles in a row: floor, floor variant, wall. The strip only has what
	# Room._build_tiles() stamps (see Room.FLOOR_TILE / FLOOR_VARIANT_TILE /
	# WALL_TILE) — a fourth slot used to exist and went stale with the art swap.
	for i in 3:
		atlas.create_tile(Vector2i(i, 0))

	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	tile_set.add_physics_layer(0)
	tile_set.set_physics_layer_collision_layer(0, 1)   # world layer; actors mask 1
	tile_set.set_physics_layer_collision_mask(0, 0)
	tile_set.add_source(atlas)

	# Only the wall tile gets a collider; floors must not block movement.
	var half := TILE * 0.5
	var wall := atlas.get_tile_data(Vector2i(2, 0), 0)
	wall.set_collision_polygons_count(0, 1)
	wall.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half),
	]))
	return tile_set


# --- weapons ---------------------------------------------------------------

func _build_weapons() -> void:
	for entry in WEAPONS:
		var data := WeaponData.new()
		data.id = entry["id"]
		data.display_name = entry["name"]
		data.damage = int(entry.get("damage", 1))
		data.fire_rate = float(entry.get("fire_rate", 4.0))
		data.recovery = float(entry.get("recovery", 0.0))
		data.spread_degrees = float(entry.get("spread", 0.0))
		data.projectile_count = int(entry.get("count", 1))
		data.projectile_speed = float(entry.get("speed", 300.0))
		data.pierce = int(entry.get("pierce", 0))
		data.knockback = float(entry.get("knockback", 120.0))
		data.energy_cost = float(entry.get("energy", 1.0))
		data.projectile_lifetime = float(entry.get("lifetime", 1.4))
		data.ammo_capacity = int(entry.get("ammo", -1))
		data.reload_time = float(entry.get("reload", 1.2))
		data.auto_reload = bool(entry.get("auto_reload", true))
		data.scatter_final_degrees = float(entry.get("scatter_final", 0.0))
		data.scatter_per_shot = float(entry.get("scatter_per_shot", 4.0))
		data.scatter_recovery = float(entry.get("scatter_recovery", 30.0))
		data.damage_type = entry.get("type", &"physical")
		data.crit_rate = float(entry.get("crit_rate", 0.0))
		data.crit_bonus = float(entry.get("crit_bonus", 0.5))
		data.bounce_count = int(entry.get("bounce", 0))
		data.explode_radius = float(entry.get("explode_radius", 0.0))
		data.explode_damage = int(entry.get("explode_damage", 0))
		data.split_count = int(entry.get("split", 0))
		data.is_melee = bool(entry.get("is_melee", false))
		data.melee_range = float(entry.get("melee_range", 22.0))
		data.bullet_tint = entry.get("tint", Color.WHITE)
		data.bullet_scale = float(entry.get("scale", 1.0))
		var icon_path := "res://assets/placeholder/%s" % String(entry.get("icon", "gun_pistol.png"))
		data.icon = load(icon_path) as Texture2D

		var path := "%s/%s.tres" % [WEAPON_DIR, String(data.id)]
		if ResourceSaver.save(data, path) != OK:
			push_error("could not save %s" % path)
		else:
			print("  weapon -> %s" % path)


func _build_projectile_scene() -> void:
	var scene := PackedScene.new()
	var path := "res://scenes/weapons/projectile.tscn"
	if ResourceLoader.exists(path):
		print("  (projectile scene already exists, leaving it alone)")
		return
	scene.free()


# --- rooms and levels ------------------------------------------------------

## The room scene is just the script plus the structure Room._ensure_structure()
## expects. Everything else (tiles, enemies, doors) is generated at runtime.
func _build_room_scene(tile_set: TileSet) -> void:
	var root := Node2D.new()
	root.name = "Room"
	root.set_script(load("res://scripts/world/room.gd"))

	var terrain := Node2D.new()
	terrain.name = "Terrain"
	root.add_child(terrain)

	var layer := TileMapLayer.new()
	layer.name = "Ground"
	layer.tile_set = tile_set
	terrain.add_child(layer)

	var actors := Node2D.new()
	actors.name = "Actors"
	actors.y_sort_enabled = true
	root.add_child(actors)

	var bullets := Node2D.new()
	bullets.name = "Projectiles"
	bullets.add_to_group(&"projectile_container")
	root.add_child(bullets)

	_assign_owners(root, root)
	var scene := PackedScene.new()
	if scene.pack(root) != OK:
		push_error("failed to pack room scene")
	else:
		var err := ResourceSaver.save(scene, ROOM_SCENE)
		print("  room scene -> %s" % ROOM_SCENE if err == OK else "  FAILED room scene")
	root.free()


func _build_level_scene(tile_set: TileSet) -> void:
	var root := Node2D.new()
	root.name = "Level"
	root.set_script(load("res://scripts/world/level.gd"))
	root.set("tile_set", tile_set)

	_assign_owners(root, root)
	var scene := PackedScene.new()
	if scene.pack(root) != OK:
		push_error("failed to pack level scene")
	else:
		var err := ResourceSaver.save(scene, LEVEL_SCENE)
		print("  level scene -> %s" % LEVEL_SCENE if err == OK else "  FAILED level scene")
	root.free()


func _build_game_scene() -> void:
	var root := Node2D.new()
	root.name = "Game"
	root.set_script(load("res://scripts/world/game.gd"))

	var holder := Node2D.new()
	holder.name = "LevelHolder"
	holder.y_sort_enabled = true
	root.add_child(holder)

	var camera := Camera2D.new()
	camera.name = "CameraRig"
	camera.set_script(load("res://scripts/world/camera_rig.gd"))
	root.add_child(camera)

	var ambience := CanvasModulate.new()
	ambience.name = "Ambience"
	# Top-down dungeons read better slightly cool and dim, so the warm muzzle
	# flashes and bullets pop against it.
	ambience.color = Color(0.74, 0.76, 0.88)
	root.add_child(ambience)

	_assign_owners(root, root)
	var scene := PackedScene.new()
	if scene.pack(root) != OK:
		push_error("failed to pack game scene")
	else:
		var err := ResourceSaver.save(scene, GAME_SCENE)
		print("  game scene -> %s" % GAME_SCENE if err == OK else "  FAILED game scene")
	root.free()


# --- main menu -------------------------------------------------------------

func _build_main_menu() -> void:
	var root := Control.new()
	root.name = "MainMenu"
	root.set_script(load("res://scripts/ui/main_menu.gd"))
	root.set_anchors_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.name = "Background"
	background.color = Color(0.06, 0.06, 0.10)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)

	# A faint band behind the centre column, so the text blocks read as one
	# composition instead of floating labels on flat black.
	var band := ColorRect.new()
	band.name = "Band"
	band.color = Color(0.09, 0.10, 0.16)
	band.position = Vector2(120, 0)
	band.size = Vector2(240, 270)
	root.add_child(band)

	var accent := ColorRect.new()
	accent.name = "Accent"
	accent.color = Color(0.95, 0.75, 0.25)
	accent.position = Vector2(200, 66)
	accent.size = Vector2(80, 2)
	root.add_child(accent)

	var title := Label.new()
	title.name = "Title"
	title.text = "KNIGHT ERRANT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.90, 0.93, 1.0))
	title.position = Vector2(0, 24)
	title.size = Vector2(480, 42)
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "TWIN-STICK DUNGEON PROTOTYPE"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 10)
	subtitle.add_theme_color_override("font_color", Color(0.50, 0.55, 0.70))
	subtitle.position = Vector2(0, 72)
	subtitle.size = Vector2(480, 16)
	root.add_child(subtitle)

	var stats := Label.new()
	stats.name = "Stats"
	stats.unique_name_in_owner = true
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", 10)
	stats.add_theme_color_override("font_color", Color(0.62, 0.67, 0.82))
	stats.position = Vector2(0, 94)
	stats.size = Vector2(480, 28)
	root.add_child(stats)

	# The buttons sit on a raised panel. Without it, three bare buttons read as
	# grey slots and the hover state has nothing to sit against.
	var panel := Panel.new()
	panel.name = "ButtonPanel"
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.10, 0.11, 0.17)
	panel_style.border_color = Color(0.30, 0.34, 0.48)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	panel_style.content_margin_left = 12.0
	panel_style.content_margin_right = 12.0
	panel_style.content_margin_top = 10.0
	panel_style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.position = Vector2(146, 128)
	panel.size = Vector2(188, 110)
	root.add_child(panel)

	var box := VBoxContainer.new()
	box.name = "Buttons"
	# Positioned by hand rather than PRESET_FULL_RECT: a plain Panel's stylebox
	# content margins do not inset an anchored child, and the VBox would spill
	# past the panel's border on the bottom.
	box.position = Vector2(14, 10)
	box.size = Vector2(160, 90)
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	for entry in [
		["StartButton", "New Run"],
		["ShopButton", "Upgrades"],
		["QuitButton", "Quit"],
	]:
		var button := Button.new()
		button.name = entry[0]
		button.text = entry[1]
		button.unique_name_in_owner = true
		button.custom_minimum_size = Vector2(160, 26)
		button.add_theme_font_size_override("font_size", 13)
		button.add_theme_color_override("font_color", Color(0.85, 0.88, 0.97))
		button.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.85))
		button.add_theme_color_override("font_focus_color", Color(1.0, 0.96, 0.85))
		button.add_theme_color_override("font_pressed_color", Color(0.95, 0.75, 0.25))
		_style_button(button)
		box.add_child(button)

	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "WASD move    Mouse aim + LMB fire    Space dodge    Q swap    E interact\nF3 debug    F4 hitboxes    F7 god    F9 rebuild floor    F10 cheat"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 8)
	hint.add_theme_color_override("font_color", Color(0.40, 0.44, 0.56))
	hint.position = Vector2(0, 242)
	hint.size = Vector2(480, 26)
	root.add_child(hint)

	_assign_owners(root, root)
	var scene := PackedScene.new()
	if scene.pack(root) != OK:
		push_error("failed to pack main menu")
	elif ResourceSaver.save(scene, MAIN_MENU) != OK:
		push_error("could not save %s" % MAIN_MENU)
	else:
		print("  main menu -> %s" % MAIN_MENU)
	root.free()


## One style set, four states: flat dark plates that brighten on hover and take a
## gold border when focused, so keyboard navigation is visible at a glance.
func _style_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.13, 0.15, 0.22)
	normal.border_color = Color(0.32, 0.37, 0.52)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.18, 0.21, 0.31)
	hover.border_color = Color(0.55, 0.62, 0.80)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.08, 0.09, 0.14)

	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = Color(0.95, 0.75, 0.25)
	focus.set_border_width_all(2)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)


## PackedScene.pack() ignores any child whose `owner` is not set, which silently
## produces an empty scene file. Recursively claim every descendant for `root`.
func _assign_owners(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_assign_owners(child, root)
