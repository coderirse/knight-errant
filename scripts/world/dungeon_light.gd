class_name DungeonLight
extends RefCounted

## Shared assets for the dungeon lighting pass.
##
## A PointLight2D needs a texture to shape its falloff. Generating one at runtime
## keeps the repo free of a binary the art generator would have to emit and the
## editor would have to import before anything could load it — which is also why
## the lights are built in code rather than placed in a .tscn: a hand-authored
## PointLight2D would reference an asset that does not exist on disk.

## 128 px is plenty for a smooth falloff at 480x270 logical resolution.
const TEXTURE_SIZE := 128

static var _falloff: GradientTexture2D


## One shared white radial falloff, tinted per light via `PointLight2D.color`.
static func falloff() -> GradientTexture2D:
	if _falloff != null and is_instance_valid(_falloff):
		return _falloff

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.5),
		Color(1.0, 1.0, 1.0, 0.0),
	])

	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = TEXTURE_SIZE
	tex.height = TEXTURE_SIZE
	tex.fill = GradientTexture2D.FILL_RADIAL
	# Centre outward to half the width, so the falloff is an inscribed circle.
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)

	_falloff = tex
	return _falloff
