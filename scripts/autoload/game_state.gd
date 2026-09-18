extends Node

## Autoload "GameState".
## **Permanent** progression that survives death and outlives a run.
##
## A roguelike has two kinds of state and mixing them is the classic mistake:
##   - run state  -> what this attempt has (gold, floor, weapons) -> RunState
##   - meta state  -> what every future attempt gets (gems, unlocks) -> here
## Dying must wipe the first and keep the second. Keeping them in one object is
## how "I lost my permanent upgrade when I died" bugs happen.

signal gems_changed(amount: int)
signal character_unlocked(id: StringName)
signal upgrade_changed(id: StringName, level: int)

## Meta currency, awarded at the end of a run.
var gems := 0
## Permanent flat bonuses bought between runs. Keys are upgrade ids.
var upgrades: Dictionary = {}
var unlocked_characters: Array[StringName] = [&"knight"]
var selected_character: StringName = &"knight"

var best_floor := 0
var total_runs := 0
var total_kills := 0
var playtime_seconds := 0.0

## Set while SceneRouter fades so every actor ignores input.
var input_locked := false

var _playtime_running := false


func _process(delta: float) -> void:
	if _playtime_running:
		playtime_seconds += delta


func begin_playtime() -> void:
	_playtime_running = true


func reset_meta() -> void:
	gems = 0
	upgrades.clear()
	unlocked_characters = [&"knight"]
	selected_character = &"knight"
	best_floor = 0
	total_runs = 0
	total_kills = 0
	playtime_seconds = 0.0
	gems_changed.emit(gems)


# --- currency --------------------------------------------------------------

func add_gems(amount: int) -> void:
	gems = maxi(gems + amount, 0)
	gems_changed.emit(gems)


## Returns false when the player cannot afford it.
func spend_gems(amount: int) -> bool:
	if amount > gems:
		return false
	gems -= amount
	gems_changed.emit(gems)
	return true


# --- permanent upgrades ----------------------------------------------------
#
# One table defines every upgrade. The hub reads it to know what to sell, and
# Game reads it to know what to apply. Keeping the two in separate lists is what
# let the `speed` upgrade be sold but never applied — the shop knew about it and
# the spawn path did not. Add upgrades here only.

const UPGRADES := {
	&"max_health": {"max_level": 5, "base_cost": 20, "cost_step": 15, "label": "Vitality +1"},
	&"max_armor": {"max_level": 5, "base_cost": 15, "cost_step": 12, "label": "Plating +1"},
	&"speed": {"max_level": 3, "base_cost": 25, "cost_step": 20, "label": "Swiftness +6%"},
}
## Move speed granted per `speed` level, as a fraction of the base value.
const SPEED_BONUS_PER_LEVEL := 0.06


func upgrade_level(id: StringName) -> int:
	return int(upgrades.get(id, 0))


func upgrade_max_level(id: StringName) -> int:
	var spec: Dictionary = UPGRADES.get(id, {})
	return int(spec.get("max_level", 0))


## Cost of the *next* level, so it rises as the player invests.
func upgrade_cost(id: StringName) -> int:
	var spec: Dictionary = UPGRADES.get(id, {})
	if spec.is_empty():
		return 0
	return int(spec.get("base_cost", 0)) + upgrade_level(id) * int(spec.get("cost_step", 0))


func upgrade_label(id: StringName) -> String:
	var spec: Dictionary = UPGRADES.get(id, {})
	return String(spec.get("label", String(id)))


func is_upgrade_maxed(id: StringName) -> bool:
	return upgrade_level(id) >= upgrade_max_level(id)


## Buys the next level at the table's price. Returns false when maxed or broke.
func buy_upgrade(id: StringName) -> bool:
	if not UPGRADES.has(id) or is_upgrade_maxed(id):
		return false
	if not spend_gems(upgrade_cost(id)):
		return false
	var level := upgrade_level(id) + 1
	upgrades[id] = level
	upgrade_changed.emit(id, level)
	return true


## Flat bonus applied on top of a base stat. Used when spawning the player.
func stat_bonus(id: StringName) -> int:
	return upgrade_level(id)


# --- characters ------------------------------------------------------------

func unlock_character(id: StringName) -> void:
	if unlocked_characters.has(id):
		return
	unlocked_characters.append(id)
	character_unlocked.emit(id)


func is_character_unlocked(id: StringName) -> bool:
	return unlocked_characters.has(id)


# --- run bookkeeping -------------------------------------------------------

func record_run_finished(floor_reached: int, kills: int, gems_earned: int) -> void:
	total_runs += 1
	total_kills += kills
	best_floor = maxi(best_floor, floor_reached)
	add_gems(gems_earned)


# --- serialisation ---------------------------------------------------------

func to_dict() -> Dictionary:
	var characters: Array[String] = []
	for id in unlocked_characters:
		characters.append(String(id))
	var upgrade_dict := {}
	for key in upgrades.keys():
		upgrade_dict[String(key)] = upgrades[key]
	return {
		"gems": gems,
		"upgrades": upgrade_dict,
		"unlocked_characters": characters,
		"selected_character": String(selected_character),
		"best_floor": best_floor,
		"total_runs": total_runs,
		"total_kills": total_kills,
		"playtime_seconds": playtime_seconds,
	}


func apply_dict(data: Dictionary) -> void:
	gems = int(data.get("gems", 0))
	upgrades.clear()
	var upgrade_dict: Dictionary = data.get("upgrades", {})
	for key in upgrade_dict.keys():
		upgrades[StringName(key)] = int(upgrade_dict[key])
	unlocked_characters.clear()
	for id in data.get("unlocked_characters", ["knight"]):
		unlocked_characters.append(StringName(id))
	if unlocked_characters.is_empty():
		unlocked_characters.append(&"knight")
	selected_character = StringName(data.get("selected_character", "knight"))
	best_floor = int(data.get("best_floor", 0))
	total_runs = int(data.get("total_runs", 0))
	total_kills = int(data.get("total_kills", 0))
	playtime_seconds = float(data.get("playtime_seconds", 0.0))
	_playtime_running = true
	gems_changed.emit(gems)
