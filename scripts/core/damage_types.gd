class_name DamageTypes
extends RefCounted

## The damage-type table: one place that says how each flavour of damage treats
## each layer of a [Health] pool, and whether it can crit.
##
## Mirrors GunfireDungeon's DamageConfig in spirit (per-type multipliers per
## layer + critable flag), reduced to THIS project's two layers: the armour
## shield and health. Their table has three layers (hp/shield/armour); we have
## two, so the shield multiplier is the armour-layer multiplier here.
##
## Semantics, kept deliberately boring:
##   - While armour holds, it absorbs the hit entirely; `armor_multiplier`
##     says how fast that armour melts against this type.
##   - Once armour is gone, `health_multiplier` scales what health loses.
##   - No overflow between layers: a standing shield still fully protects
##     health, exactly as before types existed.
##
## A single const table rather than per-weapon numbers because the P2 lesson
## applies: a definition split across files silently diverges.

const TYPES := {
	&"physical": {
		"armor_multiplier": 1.0,
		"health_multiplier": 1.0,
		"critable": true,
		"color": Color(0.80, 0.80, 1.00),
	},
	# Burns through shields, glances off bare health: the anti-armour flavour.
	&"fire": {
		"armor_multiplier": 1.5,
		"health_multiplier": 0.8,
		"critable": false,
		"color": Color(1.00, 0.50, 0.20),
	},
	# Blunt force: slow against shields, brutal once they are down.
	&"explosive": {
		"armor_multiplier": 0.6,
		"health_multiplier": 1.4,
		"critable": false,
		"color": Color(1.00, 0.72, 0.25),
	},
	# Ignores what armour is for, but bleeds less into health.
	&"pierce": {
		"armor_multiplier": 2.0,
		"health_multiplier": 0.75,
		"critable": true,
		"color": Color(0.70, 0.60, 1.00),
	},
}


static func entry(type: StringName) -> Dictionary:
	return TYPES.get(type, TYPES[&"physical"])


static func armor_multiplier(type: StringName) -> float:
	return float(entry(type)["armor_multiplier"])


static func health_multiplier(type: StringName) -> float:
	return float(entry(type)["health_multiplier"])


static func is_critable(type: StringName) -> bool:
	return bool(entry(type)["critable"])


static func color(type: StringName) -> Color:
	return entry(type)["color"]
