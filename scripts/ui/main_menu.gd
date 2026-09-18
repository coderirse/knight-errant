extends Control

## Main menu / hub. Buttons are wired in _ready() so the scene file stays dumb and
## the layout can be rebuilt in the editor without losing signal connections.

@onready var _start_button: Button = %StartButton
@onready var _shop_button: Button = %ShopButton
@onready var _quit_button: Button = %QuitButton
@onready var _stats: Label = %Stats


func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_shop_button.pressed.connect(_on_shop_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_start_button.grab_focus()
	# Load the meta save so the hub shows the player's permanent progression.
	SaveManager.load_game(1)
	_refresh_stats()


func _refresh_stats() -> void:
	var levels: PackedStringArray = []
	for id in GameState.UPGRADES.keys():
		levels.append("%s %d/%d" % [
			String(id), GameState.upgrade_level(id), GameState.upgrade_max_level(id),
		])
	_stats.text = "gems %d      best floor %d      runs %d\n%s" % [
		GameState.gems, GameState.best_floor, GameState.total_runs,
		"   ".join(levels),
	]


func _all_upgrades_maxed() -> bool:
	for id in GameState.UPGRADES.keys():
		if not GameState.is_upgrade_maxed(id):
			return false
	return true


func _on_start_pressed() -> void:
	_start_button.disabled = true
	await SceneRouter.start_new_run()


func _on_shop_pressed() -> void:
	# Permanent upgrades bought with gems. Which upgrades exist, what they cost
	# and what they do all come from GameState.UPGRADES; this button only picks
	# the first affordable one, so a new upgrade needs no change here.
	var bought: StringName = &""
	for id in GameState.UPGRADES.keys():
		if GameState.is_upgrade_maxed(id):
			continue
		if GameState.gems < GameState.upgrade_cost(id):
			continue
		if GameState.buy_upgrade(id):
			bought = id
			break

	if bought != &"":
		SaveManager.save_game(1)
		HUD.show_banner("%s  ->  Lv.%d" % [
			GameState.upgrade_label(bought), GameState.upgrade_level(bought),
		], 1.4)
	else:
		HUD.show_banner("NOT ENOUGH GEMS" if not _all_upgrades_maxed() else "ALL MAXED", 1.2)
	_refresh_stats()


func _on_quit_pressed() -> void:
	get_tree().quit()
