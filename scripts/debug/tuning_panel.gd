extends CanvasLayer

## Autoload "TuningPanel".
## Live parameter tuning bench. Open with F2, play with the panel open, and the
## values you settle on get dumped for baking into the code.
##
## Why a bench instead of editing numbers and restarting: feel is judged by
## playing, not by reading values. The loop this enables is adjust -> keep
## playing -> adjust, with no rebuild in between.
##
## Parameters are discovered by reflection over the live objects' @export vars
## rather than from a hand-written list, so a new `@export var` on the Player or
## on WeaponData shows up here automatically. (The `speed` meta-upgrade was sold
## but never applied precisely because two hand-written lists had to agree; this
## is the same lesson applied.)
##
## Movement keys stay free while tuning: navigation is [ and ], adjustment is -
## and =, so the player can still move and shoot while a value changes.

## Only numeric parameters are tunable; Textures, Colors, StringNames and arrays
## are skipped rather than shown as dead rows.
const TUNABLE_TYPES := [TYPE_INT, TYPE_FLOAT]
## Fraction of the current value one keypress moves. Adaptive so a 132.0 speed
## and a 0.20 dodge window both get a sensible step from the same rule.
const COARSE_RATIO := 0.02
const FINE_RATIO := 0.002

## Panel geometry in logical pixels. The viewport is 480x270; the panel sits on
## the right, below the HUD's gold/floor readout so it does not cover it.
##
## Measured from a screenshot rather than derived, because two things are not
## obvious from the constants: a row is ~15px at font size 11, and RichTextLabel
## adds ~7px of internal top padding before the first line. Listing 11 rows
## overflowed the list box and cut the last row in half.
const PANEL_X := 232.0
const PANEL_Y := 46.0
const PANEL_W := 240.0
const PANEL_H := 222.0
## Padding between the panel edge and its contents.
const PAD := 6.0
## Height of the parameter list. 9 rows x 15px + 7px label padding = 142, so 150
## leaves the last row fully visible.
const LIST_H := 150.0
const VISIBLE_LINES := 9
## Pixels between the panel top and the start of the list.
const LIST_TOP := 20.0

var _panel: Control
var _text: RichTextLabel
var _footer: Label
var _entries: Array[Dictionary] = []
var _defaults: Dictionary = {}
var _index := 0
var _open := false
var _rebuild_timer := 0.0


func _ready() -> void:
	layer = 98          # under DebugOverlay (99) so F3 stats stay readable on top
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_panel.visible = false


## The panel only makes sense during a run; in the menu it hides itself so it
## does not sit on top of the hub UI.
func _process(delta: float) -> void:
	_rebuild_timer -= delta
	if _rebuild_timer <= 0.0:
		_rebuild_timer = 0.25
		if _open and _collect_entries():
			_render()

	if Input.is_action_just_pressed(&"tune_panel"):
		_open = not _open
		_panel.visible = _open
		if _open:
			_collect_entries()
			_render()

	if not _open:
		return

	if Input.is_action_just_pressed(&"tune_prev"):
		_move(-1)
	elif Input.is_action_just_pressed(&"tune_next"):
		_move(1)
	elif Input.is_action_just_pressed(&"tune_down"):
		_adjust(-1.0)
	elif Input.is_action_just_pressed(&"tune_up"):
		_adjust(1.0)
	elif Input.is_action_just_pressed(&"tune_reset"):
		_reset_all()
	elif Input.is_action_just_pressed(&"tune_dump"):
		_dump()


# --- collection ------------------------------------------------------------

## Gathers tunables from the live player and its equipped weapon. Returns true
## when the set changed, so the view can be rebuilt.
func _collect_entries() -> bool:
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player == null:
		var had_entries := not _entries.is_empty()
		_entries.clear()
		return had_entries

	var fresh: Array[Dictionary] = []
	_collect_from(player, "Player", fresh)

	# The shield is feel too, and its numbers live on the Health node rather than
	# on the Player, so reflection has to be pointed at it explicitly.
	if player.health != null:
		_collect_from(player.health, "Health", fresh)

	var weapon := player.current_weapon()
	if weapon != null and weapon.data != null:
		_collect_from(weapon.data, "Weapon: %s" % weapon.data.display_name, fresh)

	# Cheap identity check: same count and same property names means the same set.
	if fresh.size() == _entries.size():
		var same := true
		for i in fresh.size():
			if fresh[i]["title"] != _entries[i]["title"] or fresh[i]["prop"] != _entries[i]["prop"]:
				same = false
				break
		if same:
			return false

	_entries = fresh
	_index = clampi(_index, 0, maxi(_entries.size() - 1, 0))
	return true


func _collect_from(obj: Object, group_title: String, into: Array[Dictionary]) -> void:
	var object_id := obj.get_instance_id()
	for prop in obj.get_property_list():
		var usage: int = prop.usage
		var is_export := (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 \
			and (usage & PROPERTY_USAGE_EDITOR) != 0
		if not is_export:
			continue
		if not TUNABLE_TYPES.has(prop.type):
			continue

		var key := "%d:%s" % [object_id, prop.name]
		var value: Variant = obj.get(prop.name)
		if not _defaults.has(key):
			_defaults[key] = value
		into.append({
			"obj": obj,
			"key": key,
			"group": group_title,
			"prop": String(prop.name),
			"title": "%s.%s" % [group_title, prop.name],
			"is_float": prop.type == TYPE_FLOAT,
			"default": _defaults[key],
		})


# --- editing ---------------------------------------------------------------

func _move(step: int) -> void:
	if _entries.is_empty():
		return
	_index = wrapi(_index + step, 0, _entries.size())
	_render()


func _adjust(direction: float) -> void:
	if _entries.is_empty():
		return
	var entry := _entries[_index]
	var obj: Object = entry["obj"]
	if not is_instance_valid(obj):
		return

	var current: Variant = obj.get(entry["prop"])
	var is_float: bool = entry["is_float"]
	var fine := Input.is_key_pressed(KEY_SHIFT)
	var ratio := FINE_RATIO if fine else COARSE_RATIO

	var next: Variant
	if is_float:
		var value := float(current)
		# Adaptive step, but never smaller than the value's own precision floor.
		var step := maxf(absf(value) * ratio, 0.0005)
		next = maxf(value + step * direction, 0.0)
		obj.set(entry["prop"], next)
	else:
		var value := int(current)
		var step_int := maxi(int(roundf(maxf(absf(float(value)) * ratio, 1.0))), 1)
		next = maxi(value + step_int * int(signf(direction)), 0)
		obj.set(entry["prop"], next)

	_render()


func _reset_all() -> void:
	for entry in _entries:
		var obj: Object = entry["obj"]
		if is_instance_valid(obj):
			obj.set(entry["prop"], entry["default"])
	_render()
	HUD.show_banner("TUNING RESET", 0.8)


## Writes the changed values out in a paste-ready form.
##
## Deliberately does NOT save the .tres files: WeaponData resources are generated
## by tools/build_scenes.gd, so saving from here would silently overwrite the
## generator's output and the two would drift. The dump is what gets baked in.
func _dump() -> void:
	var lines: PackedStringArray = []
	lines.append("--- tuning dump ---")
	var changed := 0
	for entry in _entries:
		var obj: Object = entry["obj"]
		if not is_instance_valid(obj):
			continue
		var current: Variant = obj.get(entry["prop"])
		var is_default: bool = _values_match(current, entry["default"])
		var value_text := _format(current, entry["is_float"])
		if is_default:
			continue
		changed += 1
		lines.append("%s = %s   (was %s)" % [
			entry["prop"], value_text, _format(entry["default"], entry["is_float"]),
		])

	if changed == 0:
		lines.append("(nothing changed from the startup values)")
	lines.append("-------------------")

	var text := "\n".join(lines)
	print(text)
	# Headless and some platforms have no clipboard; has_feature() is the guard
	# (a bare clipboard_set() logs "Clipboard is not supported" under --headless).
	var copied := false
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(text)
		copied = true
	if HUD != null:
		HUD.show_banner("DUMPED %d CHANGE(S)%s" % [
			changed, " TO CLIPBOARD" if copied else " (see console)",
		], 1.6)


func _values_match(a: Variant, b: Variant) -> bool:
	if a is float or b is float:
		return is_equal_approx(float(a), float(b))
	return a == b


func _format(value: Variant, is_float: bool) -> String:
	# `String(int)` is not a valid constructor in GDScript; formatting is the
	# way to convert a number to text.
	if is_float:
		return "%.4f" % float(value)
	return "%d" % int(value)


# --- view ------------------------------------------------------------------

func _build() -> void:
	_panel = Control.new()
	_panel.name = "TuningPanel"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	# Fixed geometry in logical pixels (the viewport is 480x270). Placed on the
	# right, starting below the HUD's gold/floor readout, so the panel does not
	# sit on top of it. Values here are deliberately explicit: the list area and
	# the footer used to be positioned independently and overlapped.
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.03, 0.04, 0.07, 0.90)
	backdrop.position = Vector2(PANEL_X, PANEL_Y)
	backdrop.size = Vector2(PANEL_W, PANEL_H)
	_panel.add_child(backdrop)

	var title := Label.new()
	title.text = "TUNING    [F2] close"
	title.position = Vector2(PANEL_X + PAD, PANEL_Y + 4)
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.4))
	_panel.add_child(title)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_active = false
	# clip_contents keeps a stray extra line from spilling over the footer; the
	# row count is sized so it never actually has to clip.
	_text.clip_contents = true
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.position = Vector2(PANEL_X + PAD, PANEL_Y + LIST_TOP)
	_text.size = Vector2(PANEL_W - PAD * 2.0, LIST_H)
	_text.custom_minimum_size = _text.size
	_text.add_theme_font_size_override("normal_font_size", 11)
	_panel.add_child(_text)

	_footer = Label.new()
	_footer.position = Vector2(PANEL_X + PAD, PANEL_Y + LIST_TOP + LIST_H + 4.0)
	_footer.add_theme_font_size_override("font_size", 10)
	_footer.add_theme_color_override("font_color", Color(0.62, 0.68, 0.82))
	_panel.add_child(_footer)


func _render() -> void:
	if _entries.is_empty():
		_text.text = "[color=#888]no player in the scene[/color]"
		_footer.text = "waiting for a run"
		return

	# Exactly one line per entry, no inline group headers.
	#
	# Headers were an extra line that the row budget did not account for, so the
	# last row landed on the clip boundary and was cut in half — which reads as a
	# rendering bug rather than as "there is more below". Which object an entry
	# belongs to is shown in the footer instead, so nothing is lost and the row
	# count is exact.
	var first := clampi(_index - VISIBLE_LINES / 2, 0, maxi(_entries.size() - VISIBLE_LINES, 0))
	var last := mini(first + VISIBLE_LINES, _entries.size())

	var lines: PackedStringArray = []
	for i in range(first, last):
		var entry := _entries[i]
		var obj: Object = entry["obj"]
		var value_text := "?"
		if is_instance_valid(obj):
			value_text = _format(obj.get(entry["prop"]), entry["is_float"])
		var changed := is_instance_valid(obj) and not _values_match(obj.get(entry["prop"]), entry["default"])

		if i == _index:
			lines.append("[bgcolor=#2a3a5a][color=#fff]> %s[/color][/bgcolor]" % _row(entry["prop"], value_text))
		else:
			var mark := "*" if changed else " "
			var colour := "#ffd166" if changed else "#c8cede"
			lines.append("[color=%s]%s %s[/color]" % [colour, mark, _row(entry["prop"], value_text)])

	_text.text = "\n".join(lines)

	# Names the object being edited up front: a weapon's fields and the player's
	# fields are both plain property names, so without this the list is ambiguous.
	# Keys go on two short lines — one long line does not fit at this panel width.
	var selected: Dictionary = _entries[_index]
	_footer.text = "%s                    %d/%d\n[] select    -= adjust    Shift fine\nF5 reset     F6 dump     * = changed" % [
		selected["group"], _index + 1, _entries.size(),
	]


## Lays a parameter name and its value into the fixed panel width.
##
## Padded with spaces rather than aligned with columns because RichTextLabel does
## not lay out columns, and a fixed-width format keeps long names like
## `dodge_invincibility_bonus` from pushing the value off the panel.
func _row(name: String, value: String) -> String:
	return "%-26s %s" % [name, value]