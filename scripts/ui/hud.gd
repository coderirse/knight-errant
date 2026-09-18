extends CanvasLayer

## Autoload "HUD".
## Soul Knight-style layout: health pips + armour bar top-left, gold top-right,
## energy bar and weapon slots along the bottom.
##
## Listens to signals only — it never polls the player for state, so it works in
## any scene including menus and the boss room. The one exception is the current
## weapon, which is read on demand because it changes without a signal being
## convenient to wire.
##
## Rebuild the visuals with real textures during the art pass; the layout logic
## and the signal wiring are what matter here.

const MASK_SIZE := 16.0
const MASK_GAP := 3.0
const BAR_WIDTH := 96.0
const BAR_HEIGHT := 7.0

var _root: Control
var _hearts: HBoxContainer
var _armor_bg: ColorRect
var _armor_fill: ColorRect
var _energy_bg: ColorRect
var _energy_fill: ColorRect
var _gold_label: Label
var _floor_label: Label
var _weapon_label: Label
var _kills_label: Label
var _banner: Label
var _player: Player


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()

	GameState.input_locked = false
	RunState.gold_changed.connect(_on_gold_changed)
	RunState.floor_changed.connect(_on_floor_changed)
	_on_gold_changed(RunState.gold)
	_on_floor_changed(RunState.floor)


func _process(_delta: float) -> void:
	var current := get_tree().current_scene
	var in_game := current != null and (current.is_in_group(&"game") or current.get_node_or_null("LevelHolder") != null)
	_root.visible = in_game
	if not in_game:
		return

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Player
		if _player != null:
			_bind_player(_player)
	if _player == null:
		return

	_refresh_bars()
	_refresh_weapon()
	_kills_label.text = "kills %d" % RunState.kills


# --- build -----------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# --- top-left: hearts + armour
	_hearts = HBoxContainer.new()
	_hearts.position = Vector2(10, 8)
	_hearts.add_theme_constant_override("separation", int(MASK_GAP))
	_root.add_child(_hearts)

	_armor_bg = ColorRect.new()
	_armor_bg.color = Color(0.10, 0.12, 0.20, 0.80)
	_armor_bg.position = Vector2(10, 28)
	_armor_bg.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_root.add_child(_armor_bg)

	_armor_fill = ColorRect.new()
	_armor_fill.color = Color(0.35, 0.70, 1.0)
	_armor_fill.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_armor_bg.add_child(_armor_fill)

	# --- top-right: gold + floor
	_gold_label = Label.new()
	_gold_label.position = Vector2(360, 6)
	_gold_label.size = Vector2(112, 20)
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_gold_label.add_theme_font_size_override("font_size", 15)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.28))
	_root.add_child(_gold_label)

	_floor_label = Label.new()
	_floor_label.position = Vector2(360, 24)
	_floor_label.size = Vector2(112, 18)
	_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_floor_label.add_theme_font_size_override("font_size", 12)
	_floor_label.add_theme_color_override("font_color", Color(0.70, 0.76, 0.90))
	_root.add_child(_floor_label)

	# --- bottom-left: energy + weapon
	_energy_bg = ColorRect.new()
	_energy_bg.color = Color(0.10, 0.12, 0.20, 0.80)
	_energy_bg.position = Vector2(10, 246)
	_energy_bg.size = Vector2(BAR_WIDTH * 1.6, BAR_HEIGHT + 2.0)
	_root.add_child(_energy_bg)

	_energy_fill = ColorRect.new()
	_energy_fill.color = Color(0.40, 0.85, 1.0)
	_energy_fill.size = _energy_bg.size
	_energy_bg.add_child(_energy_fill)

	_weapon_label = Label.new()
	_weapon_label.position = Vector2(10, 226)
	_weapon_label.size = Vector2(240, 18)
	_weapon_label.add_theme_font_size_override("font_size", 13)
	_weapon_label.add_theme_color_override("font_color", Color(0.92, 0.94, 1.0))
	_root.add_child(_weapon_label)

	_kills_label = Label.new()
	_kills_label.position = Vector2(10, 210)
	_kills_label.size = Vector2(200, 16)
	_kills_label.add_theme_font_size_override("font_size", 11)
	_kills_label.add_theme_color_override("font_color", Color(0.60, 0.64, 0.76))
	_root.add_child(_kills_label)

	# --- centred banner for events
	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.position = Vector2(-200, 60)
	_banner.custom_minimum_size = Vector2(400, 0)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 22)
	_banner.add_theme_color_override("font_color", Color(1, 1, 1))
	_banner.modulate.a = 0.0
	_root.add_child(_banner)


func _bind_player(player: Player) -> void:
	player.health.changed.connect(func(_c, _m): _refresh_bars())
	player.health.armor_changed.connect(func(_c, _m): _refresh_bars())
	player.energy.changed.connect(func(_c, _m): _refresh_bars())
	player.weapon_swapped.connect(func(_w): _refresh_weapon())


# --- refresh ---------------------------------------------------------------

func _refresh_bars() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var health := _player.health

	if _hearts.get_child_count() != health.maximum:
		for child in _hearts.get_children():
			child.queue_free()
		for i in health.maximum:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(MASK_SIZE, MASK_SIZE)
			_hearts.add_child(pip)

	for i in _hearts.get_child_count():
		var pip := _hearts.get_child(i) as ColorRect
		pip.color = Color(0.92, 0.28, 0.32) if i < health.current else Color(0.22, 0.16, 0.20, 0.85)

	var armor_ratio := 0.0
	if health.maximum_armor > 0:
		armor_ratio = float(health.armor) / float(health.maximum_armor)
	_armor_fill.size.x = BAR_WIDTH * clampf(armor_ratio, 0.0, 1.0)
	_armor_bg.visible = health.maximum_armor > 0

	var energy_ratio := 0.0
	if _player.energy.maximum > 0.0:
		energy_ratio = _player.energy.current / _player.energy.maximum
	_energy_fill.size.x = _energy_bg.size.x * clampf(energy_ratio, 0.0, 1.0)


func _refresh_weapon() -> void:
	var weapon := _player.current_weapon()
	if weapon == null or weapon.data == null:
		_weapon_label.text = "unarmed"
		return
	var slots := _player.weapons.size()
	var index := _player.weapon_index + 1
	var data := weapon.data
	var cost := "melee" if data.is_melee else "energy %d" % int(data.energy_cost)
	_weapon_label.text = "[%d/%d] %s   dmg %d   %s" % [index, slots, data.display_name, data.damage, cost]


func _on_gold_changed(amount: int) -> void:
	if _gold_label != null:
		_gold_label.text = "%d G" % amount


func _on_floor_changed(floor_number: int) -> void:
	if _floor_label != null:
		_floor_label.text = "floor %d" % floor_number


func show_banner(text: String, duration := 2.0) -> void:
	if _banner == null:
		return
	_banner.text = text
	var tween := create_tween()
	tween.tween_property(_banner, "modulate:a", 1.0, 0.25)
	tween.tween_interval(duration)
	tween.tween_property(_banner, "modulate:a", 0.0, 0.6)
