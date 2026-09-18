extends CanvasLayer

## Autoload "DebugOverlay".
## F3 = stats overlay, F4 = physics shapes, F7 = god mode, F9 = restart run,
## F10 = cheat (full energy + all weapons).
##
## A run-based game is iterated on by playing it, so the overlay is a first class
## feature rather than something bolted on at the end.

const REFRESH_INTERVAL := 0.25

var _label: RichTextLabel
var _timer := 0.0
var _visible := false
var _god_mode := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 99

	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.position = Vector2(12, 44)
	_label.custom_minimum_size = Vector2(360, 0)
	_label.add_theme_font_size_override("normal_font_size", 12)
	_label.visible = false
	add_child(_label)


func _process(delta: float) -> void:
	_handle_hotkeys()
	if not _visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH_INTERVAL
		_refresh()


func _handle_hotkeys() -> void:
	if Input.is_action_just_pressed(&"debug_overlay"):
		_visible = not _visible
		_label.visible = _visible
	if Input.is_action_just_pressed(&"debug_shapes"):
		get_tree().debug_collisions_hint = not get_tree().debug_collisions_hint
	if Input.is_action_just_pressed(&"debug_reload"):
		var game := get_tree().current_scene as Game
		if game != null:
			game.build_floor(RunState.floor, RunState.level_seed)
			print("[debug] rebuilt floor %d" % RunState.floor)
	if Input.is_action_just_pressed(&"debug_cheat"):
		_apply_cheat()
	if Input.is_action_just_pressed(&"debug_god"):
		_god_mode = not _god_mode
		var player := get_tree().get_first_node_in_group(&"player")
		if player is Player:
			(player as Player).hurtbox.vulnerable = not _god_mode
		print("[debug] god mode: %s" % _god_mode)


func _apply_cheat() -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player == null:
		return
	player.energy.fill()
	player.health.current = player.health.maximum
	player.health.armor = player.health.maximum_armor
	player.health.changed.emit(player.health.current, player.health.maximum)
	player.health.armor_changed.emit(player.health.armor, player.health.maximum_armor)
	for id in WeaponRegistry.all_ids():
		player.pick_up_weapon(id)
	player.full_restore()
	print("[debug] cheated: full energy/health, %d weapons" % player.weapons.size())


func _refresh() -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Player
	var lines: PackedStringArray = []
	lines.append("[b]FPS[/b] %d   [b]draws[/b] %d   [b]nodes[/b] %d" % [
		Engine.get_frames_per_second(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		get_tree().get_node_count(),
	])

	var game := get_tree().current_scene as Game
	if game != null and game.level != null:
		lines.append("[b]floor[/b] %d  [b]seed[/b] %d   [b]rooms[/b] %d  [b]cleared[/b] %d%%" % [
			RunState.floor, RunState.level_seed, game.level.rooms.size(),
			int(game.level.clear_percent() * 100.0),
		])
		lines.append("[b]enemies alive[/b] %d   [b]kills[/b] %d" % [
			get_tree().get_nodes_in_group(&"enemy").size(), RunState.kills,
		])

	if player != null:
		lines.append("[b]state[/b] %s   [b]pos[/b] %d,%d   [b]vel[/b] %.0f" % [
			Player.State.keys()[player.state], player.global_position.x, player.global_position.y,
			player.velocity.length(),
		])
		lines.append("[b]hp[/b] %d/%d  [b]armor[/b] %d/%d  [b]energy[/b] %d/%d" % [
			player.health.current, player.health.maximum,
			player.health.armor, player.health.maximum_armor,
			int(player.energy.current), int(player.energy.maximum),
		])
		lines.append("[b]aim[/b] %.2f,%.2f   [b]dodge[/b] %s" % [
			player.aim_direction.x, player.aim_direction.y,
			"ready" if player.is_dodge_ready() else "%.0f%%" % ((1.0 - player.dodge_cooldown_ratio()) * 100.0),
		])
		var weapon := player.current_weapon()
		if weapon != null and weapon.data != null:
			lines.append("[b]weapon[/b] %s" % weapon.data.describe())
		lines.append("[b]bullets[/b] %d" % get_tree().get_nodes_in_group(&"projectile_container").size())
	lines.append("[b]gold[/b] %d   [b]gems[/b] %d" % [RunState.gold, GameState.gems])

	_label.text = "\n".join(lines)
