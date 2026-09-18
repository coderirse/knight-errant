extends Node

## Autoload "RunState".
## Everything that belongs to **one attempt** and must be wiped when the player
## dies: the floor they are on, gold picked up, weapons carried, the level seed.
##
## Kept separate from GameState (which holds permanent progression) because the
## two have opposite lifetimes. Gold is run-scoped in this design so that a bad
## run cannot be farmed — that is a design decision, not an engine one; move it to
## GameState if you want a persistent wallet.

signal gold_changed(amount: int)
signal floor_changed(floor_number: int)
signal run_started
signal run_ended(victory: bool)

const STARTING_FLOOR := 1

var active := false
var floor := STARTING_FLOOR
var gold := 0
var kills := 0
## Seed for the current floor's layout, so a floor can be regenerated exactly.
var level_seed := 0
## Weapon ids the player is carrying, in slot order.
var weapons: Array[StringName] = []
var rooms_cleared := 0
var rooms_total := 0


func start_run(new_seed := 0) -> void:
	active = true
	floor = STARTING_FLOOR
	gold = 0
	kills = 0
	rooms_cleared = 0
	rooms_total = 0
	weapons.clear()
	level_seed = new_seed if new_seed != 0 else randi()
	run_started.emit()
	gold_changed.emit(gold)
	floor_changed.emit(floor)


func end_run(victory := false) -> void:
	active = false
	run_ended.emit(victory)


## Advances to the next floor. Returns the new seed; the caller is responsible
## for rebuilding the level from it.
func advance_floor() -> int:
	floor += 1
	rooms_cleared = 0
	rooms_total = 0
	level_seed = randi()
	floor_changed.emit(floor)
	return level_seed


# --- gold ------------------------------------------------------------------

func add_gold(amount: int) -> void:
	gold = maxi(gold + amount, 0)
	gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if amount > gold:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true


# --- weapons ---------------------------------------------------------------

func remember_weapon(id: StringName) -> void:
	if not weapons.has(id):
		weapons.append(id)


# --- serialisation ---------------------------------------------------------

func to_dict() -> Dictionary:
	var weapon_ids: Array[String] = []
	for id in weapons:
		weapon_ids.append(String(id))
	return {
		"active": active,
		"floor": floor,
		"gold": gold,
		"kills": kills,
		"level_seed": level_seed,
		"weapons": weapon_ids,
		"rooms_cleared": rooms_cleared,
		"rooms_total": rooms_total,
	}


func apply_dict(data: Dictionary) -> void:
	active = bool(data.get("active", false))
	floor = int(data.get("floor", STARTING_FLOOR))
	gold = int(data.get("gold", 0))
	kills = int(data.get("kills", 0))
	level_seed = int(data.get("level_seed", 0))
	weapons.clear()
	for id in data.get("weapons", []):
		weapons.append(StringName(id))
	rooms_cleared = int(data.get("rooms_cleared", 0))
	rooms_total = int(data.get("rooms_total", 0))
	gold_changed.emit(gold)
	floor_changed.emit(floor)
