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
	},
	{
		"id": &"shotgun", "name": "Scrap Shotgun", "damage": 2, "fire_rate": 1.3,
		"spread": 34.0, "count": 5, "speed": 250.0, "energy": 8.0, "recovery": 0.18,
		"knockback": 220.0, "icon": "gun_shotgun.png", "tint": Color(1.0, 0.85, 0.6),
		"scale": 1.15, "desc": "short range, heavy stagger",
	},
	{
		"id": &"smg", "name": "Chatter SMG", "damage": 1, "fire_rate": 11.0,
		"spread": 11.0, "count": 1, "speed": 360.0, "energy": 1.5, "recovery": 0.0,
		"knockback": 45.0, "icon": "gun_pistol.png", "tint": Color(0.7, 0.95, 1.0),
		"scale": 0.85, "desc": "spray, eats energy",
	},
	{
		"id": &"railgun", "name": "Piercer", "damage": 4, "fire_rate": 1.1,
		"spread": 0.0, "count": 1, "speed": 700.0, "energy": 12.0, "recovery": 0.25,
		"knockback": 260.0, "pierce": 4, "icon": "gun_pistol.png",
		"tint": Color(0.75, 0.6, 1.0), "scale": 1.3, "desc": "pierces a line",
	},
	{
		"id": &"sword", "name": "Chipped Blade", "damage": 3, "fire_rate": 2.2,
		"is_melee": true, "melee_range": 24.0, "energy": 0.0, "recovery": 0.06,
		"knockback": 240.0, "icon": "sword.png", "tint": Color(1, 1, 1, 1),
		"scale": 1.0, "desc": "free swings, no ammo",
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
	# Four tiles in a row: floor, floor variant, wall, wall top.
	for i in 4:
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
	background.color = Color(0.07, 0.07, 0.11)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)

	var title := Label.new()
	title.name = "Title"
	title.text = "KNIGHT ERRANT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.90, 0.93, 1.0))
	title.position = Vector2(0, 34)
	title.size = Vector2(480, 54)
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "twin-stick dungeon prototype"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.55, 0.60, 0.75))
	subtitle.position = Vector2(0, 84)
	subtitle.size = Vector2(480, 20)
	root.add_child(subtitle)

	var stats := Label.new()
	stats.name = "Stats"
	stats.unique_name_in_owner = true
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", 12)
	stats.add_theme_color_override("font_color", Color(0.65, 0.70, 0.85))
	stats.position = Vector2(0, 112)
	stats.size = Vector2(480, 36)
	root.add_child(stats)

	var box := VBoxContainer.new()
	box.name = "Buttons"
	box.position = Vector2(170, 158)
	box.custom_minimum_size = Vector2(140, 96)
	box.add_theme_constant_override("separation", 7)
	root.add_child(box)
	for entry in [
		["StartButton", "New Run"],
		["ShopButton", "Upgrades"],
		["QuitButton", "Quit"],
	]:
		var button := Button.new()
		button.name = entry[0]
		button.text = entry[1]
		button.unique_name_in_owner = true
		button.custom_minimum_size = Vector2(140, 24)
		box.add_child(button)

	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "WASD move    Mouse aim + LMB fire    Space dodge    Q swap    E interact\nF3 debug    F4 hitboxes    F7 god    F9 rebuild floor    F10 cheat"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.42, 0.46, 0.58))
	hint.position = Vector2(0, 240)
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


## PackedScene.pack() ignores any child whose `owner` is not set, which silently
## produces an empty scene file. Recursively claim every descendant for `root`.
func _assign_owners(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_assign_owners(child, root)
