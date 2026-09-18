extends SceneTree

## Generates the placeholder art for the top-down build, so the first run has
## something visible without pulling in any third-party asset.
##
## Run with:
##   Godot --headless --path . --script res://tools/generate_placeholder_art.gd
##
## Replace everything in assets/placeholder/ once real art is imported. The node
## structure and collision shapes do not depend on these textures, so swapping
## them is a pure art change.
##
## Sprites are drawn top-down / three-quarter view like Soul Knight: you look
## down at the character, so it is a big head with a sliver of body and shoulders,
## not a side-on silhouette.

const OUT_DIR := "res://assets/placeholder"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_write("player.png", _make_player())
	_write("chaser.png", _make_chaser())
	_write("shooter.png", _make_shooter())
	_write("bullet.png", _make_bullet())
	_write("enemy_bullet.png", _make_enemy_bullet())
	_write("tile_ground.png", _make_tiles())
	_write("gun_pistol.png", _make_pistol())
	_write("gun_shotgun.png", _make_shotgun())
	_write("sword.png", _make_sword())
	_write("coin.png", _make_coin())
	_write("heart.png", _make_heart())
	_write("energy_orb.png", _make_energy_orb())
	_write("portal.png", _make_portal())
	_write("chest.png", _make_chest())
	print("top-down placeholder art written to ", OUT_DIR)
	quit()


func _write(file_name: String, image: Image) -> void:
	var path := "%s/%s" % [OUT_DIR, file_name]
	var err := image.save_png(path)
	if err != OK:
		push_error("could not write %s (%s)" % [path, error_string(err)])


func _canvas(width: int, height: int, fill := Color(0, 0, 0, 0)) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(fill)
	return image


func _rect(image: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	for px in range(maxi(x, 0), mini(x + w, image.get_width())):
		for py in range(maxi(y, 0), mini(y + h, image.get_height())):
			image.set_pixel(px, py, color)


func _disc(image: Image, cx: float, cy: float, radius: float, color: Color) -> void:
	for px in image.get_width():
		for py in image.get_height():
			var dx := px + 0.5 - cx
			var dy := py + 0.5 - cy
			if dx * dx + dy * dy <= radius * radius:
				image.set_pixel(px, py, color)


func _outline(image: Image, color: Color) -> void:
	# Cheap 1px outline: any transparent pixel touching an opaque one becomes
	# outline. Gives the sprites the readable silhouette these games rely on.
	var source := image.duplicate() as Image
	var neighbours: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for px in image.get_width():
		for py in image.get_height():
			if source.get_pixel(px, py).a > 0.0:
				continue
			var touching := false
			for offset in neighbours:
				var nx: int = px + offset.x
				var ny: int = py + offset.y
				if nx < 0 or ny < 0 or nx >= image.get_width() or ny >= image.get_height():
					continue
				if source.get_pixel(nx, ny).a > 0.0:
					touching = true
					break
			if touching:
				image.set_pixel(px, py, color)


# --- characters ------------------------------------------------------------

## Top-down knight: helmet dome, visor slit, shoulder plates, cape hint.
func _make_player() -> Image:
	var image := _canvas(24, 24)
	var metal := Color(0.72, 0.78, 0.88)
	var metal_dark := Color(0.45, 0.51, 0.62)
	var visor := Color(0.30, 0.85, 1.0)
	var cape := Color(0.24, 0.30, 0.52)

	# Cape/shoulders peek out below the head.
	_rect(image, 5, 12, 14, 9, cape)
	_disc(image, 12, 11.0, 8.4, metal_dark)   # body ring
	_disc(image, 12, 10.5, 7.0, metal)        # helmet
	_rect(image, 7, 10, 10, 3, visor)         # visor slit
	_disc(image, 12, 15.5, 4.4, metal_dark)   # chin/jaw shadow
	_rect(image, 4, 13, 3, 4, metal_dark)     # left pauldron
	_rect(image, 17, 13, 3, 4, metal_dark)    # right pauldron
	_outline(image, Color(0.10, 0.11, 0.16))
	return image


## Small aggressive blob with two eyes — the melee chaser.
func _make_chaser() -> Image:
	var image := _canvas(20, 20)
	var body := Color(0.72, 0.26, 0.34)
	var body_dark := Color(0.48, 0.14, 0.22)
	var eye := Color(1.0, 0.92, 0.45)

	_disc(image, 10, 11.0, 7.5, body_dark)
	_disc(image, 10, 10.0, 6.4, body)
	_disc(image, 7.2, 8.5, 2.0, eye)          # eyes
	_disc(image, 12.8, 8.5, 2.0, eye)
	_disc(image, 7.2, 8.5, 0.9, Color(0.1, 0.1, 0.1))
	_disc(image, 12.8, 8.5, 0.9, Color(0.1, 0.1, 0.1))
	# Little spikes for a menacing read at 1x.
	_rect(image, 2, 12, 3, 3, body_dark)
	_rect(image, 15, 12, 3, 3, body_dark)
	_outline(image, Color(0.10, 0.11, 0.16))
	return image


## Hooded cultist with a stubby gun — the ranged enemy.
func _make_shooter() -> Image:
	var image := _canvas(20, 20)
	var robe := Color(0.42, 0.30, 0.62)
	var robe_dark := Color(0.28, 0.19, 0.44)
	var face := Color(0.10, 0.09, 0.14)
	var eye := Color(1.0, 0.45, 0.30)
	var gun := Color(0.30, 0.32, 0.38)

	_disc(image, 10, 11.0, 7.4, robe_dark)
	_disc(image, 10, 10.0, 6.2, robe)
	_disc(image, 10, 8.5, 3.6, face)          # hood opening
	_disc(image, 8.6, 8.6, 1.0, eye)
	_disc(image, 11.4, 8.6, 1.0, eye)
	_rect(image, 14, 11, 6, 3, gun)           # gun sticking out to the right
	_rect(image, 14, 10, 2, 5, gun.darkened(0.2))
	_outline(image, Color(0.10, 0.11, 0.16))
	return image


# --- projectiles -----------------------------------------------------------

func _make_bullet() -> Image:
	var image := _canvas(8, 8)
	_disc(image, 4, 4, 3.4, Color(0.55, 0.85, 1.0, 0.55))
	_disc(image, 4, 4, 2.2, Color(1.0, 1.0, 1.0))
	return image


func _make_enemy_bullet() -> Image:
	var image := _canvas(8, 8)
	_disc(image, 4, 4, 3.4, Color(1.0, 0.42, 0.30, 0.55))
	_disc(image, 4, 4, 2.2, Color(1.0, 0.86, 0.55))
	return image


# --- terrain atlas ---------------------------------------------------------
## 64x16 strip of four 16x16 tiles. Keep this layout in sync with
## tools/build_scenes.gd, which builds the TileSet from it.
##   0 = floor        1 = floor variant        2 = wall        3 = wall top
func _make_tiles() -> Image:
	var image := _canvas(64, 16)
	var floor_a := Color(0.20, 0.22, 0.28)
	var floor_b := Color(0.24, 0.26, 0.33)
	var grout := Color(0.15, 0.17, 0.22)
	var wall := Color(0.36, 0.38, 0.48)
	var wall_top := Color(0.52, 0.55, 0.66)
	var wall_dark := Color(0.24, 0.26, 0.34)

	# Tile 0: plain floor with a subtle grid.
	_rect(image, 0, 0, 16, 16, floor_a)
	for i in range(0, 16, 8):
		_rect(image, i, 0, 1, 16, grout)
		_rect(image, 0, i, 16, 1, grout)

	# Tile 1: floor variant with speckles, breaks up large flat areas.
	_rect(image, 16, 0, 16, 16, floor_b)
	_rect(image, 16, 0, 1, 16, grout)
	var speckles: Array[Vector2i] = [
		Vector2i(3, 4), Vector2i(9, 7), Vector2i(5, 12), Vector2i(12, 11), Vector2i(7, 2),
	]
	for spot in speckles:
		image.set_pixel(16 + spot.x, spot.y, grout)

	# Tile 2: wall body (collision tile).
	_rect(image, 32, 0, 16, 16, wall)
	_rect(image, 32, 0, 16, 3, wall_top)
	_rect(image, 32, 13, 16, 3, wall_dark)
	for x in range(32, 48, 5):
		_rect(image, x, 3, 1, 10, wall_dark)

	# Tile 3: wall top edge, for the row of wall the camera sees most.
	_rect(image, 48, 0, 16, 16, wall)
	_rect(image, 48, 0, 16, 5, wall_top)
	_rect(image, 48, 5, 16, 2, wall.darkened(0.15))
	return image


# --- weapon icons ----------------------------------------------------------

func _make_pistol() -> Image:
	var image := _canvas(16, 12)
	var body := Color(0.42, 0.45, 0.55)
	var grip := Color(0.28, 0.24, 0.22)
	_rect(image, 2, 4, 10, 4, body)
	_rect(image, 6, 8, 3, 4, grip)
	_rect(image, 12, 5, 3, 2, body.lightened(0.2))
	_outline(image, Color(0.10, 0.11, 0.16))
	return image


func _make_shotgun() -> Image:
	var image := _canvas(16, 12)
	var body := Color(0.52, 0.34, 0.24)
	var barrel := Color(0.36, 0.38, 0.46)
	_rect(image, 1, 4, 8, 4, body)
	_rect(image, 9, 3, 6, 2, barrel)
	_rect(image, 9, 7, 6, 2, barrel)
	_rect(image, 4, 8, 3, 4, body.darkened(0.2))
	_outline(image, Color(0.10, 0.11, 0.16))
	return image


func _make_sword() -> Image:
	var image := _canvas(16, 12)
	var blade := Color(0.82, 0.86, 0.94)
	var hilt := Color(0.62, 0.48, 0.24)
	# Blade along the top-left to bottom-right diagonal.
	for i in range(7):
		image.set_pixel(3 + i, 8 - i, blade)
		image.set_pixel(4 + i, 8 - i, blade)
		image.set_pixel(3 + i, 7 - i, blade)
	_rect(image, 1, 8, 4, 2, hilt)
	_rect(image, 4, 9, 2, 3, hilt.darkened(0.25))
	_outline(image, Color(0.10, 0.11, 0.16))
	return image


# --- pickups ---------------------------------------------------------------

func _make_coin() -> Image:
	var image := _canvas(12, 12)
	_disc(image, 6, 6, 5.4, Color(0.55, 0.40, 0.10))
	_disc(image, 6, 5.4, 4.2, Color(1.0, 0.84, 0.28))
	_rect(image, 5, 3, 2, 6, Color(0.62, 0.46, 0.12))
	_outline(image, Color(0.20, 0.14, 0.05))
	return image


func _make_heart() -> Image:
	var image := _canvas(12, 12)
	var red := Color(0.90, 0.22, 0.28)
	_disc(image, 4.2, 4.6, 2.9, red)
	_disc(image, 7.8, 4.6, 2.9, red)
	for row in range(4, 11):
		var half := (10 - row) * 1.1
		_rect(image, int(6 - half), row, int(half * 2), 1, red)
	_outline(image, Color(0.35, 0.06, 0.10))
	return image


func _make_energy_orb() -> Image:
	var image := _canvas(12, 12)
	_disc(image, 6, 6, 5.4, Color(0.20, 0.55, 0.95, 0.5))
	_disc(image, 6, 6, 3.6, Color(0.35, 0.80, 1.0))
	_disc(image, 5, 5, 1.4, Color(0.90, 0.98, 1.0))
	_outline(image, Color(0.08, 0.22, 0.42))
	return image


func _make_portal() -> Image:
	var image := _canvas(28, 28)
	_disc(image, 14, 14, 13.0, Color(0.30, 0.55, 1.0, 0.28))
	_disc(image, 14, 14, 10.0, Color(0.35, 0.65, 1.0, 0.45))
	_disc(image, 14, 14, 6.5, Color(0.70, 0.90, 1.0, 0.9))
	_disc(image, 14, 14, 3.0, Color(1.0, 1.0, 1.0))
	return image


func _make_chest() -> Image:
	var image := _canvas(20, 18)
	var wood := Color(0.52, 0.34, 0.20)
	var wood_dark := Color(0.34, 0.21, 0.12)
	var band := Color(0.72, 0.60, 0.26)
	_rect(image, 1, 5, 18, 12, wood)
	_rect(image, 1, 3, 18, 4, wood_dark)     # lid
	_rect(image, 8, 3, 4, 14, band)          # strap
	_rect(image, 8, 9, 4, 4, band.lightened(0.25))  # lock
	_outline(image, Color(0.12, 0.09, 0.05))
	return image
