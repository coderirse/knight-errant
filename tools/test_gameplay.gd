extends Node

## Core system tests: damage pipeline with armour, energy pool, weapon data,
## weapons firing, and save round trip.
##
## Run with:
##   Godot --headless --path . res://tools/test_gameplay.tscn
##
## It is a scene rather than a --script tool on purpose: --script mode does not
## instantiate autoloads, so GameState/RunState/PlayerHost would be missing.

var _failures: PackedStringArray = []
var _checks := 0


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", label)
	else:
		_failures.append(label)
		print("  FAIL ", label)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame

	print("\n== 1. autoloads ==")
	_check(GameState != null, "GameState present")
	_check(RunState != null, "RunState present")
	_check(SaveManager != null, "SaveManager present")
	_check(PlayerHost != null, "PlayerHost present")
	_check(SceneRouter != null, "SceneRouter present")

	print("\n== 2. meta vs run state are separate ==")
	GameState.reset_meta()
	RunState.start_run(1234)
	GameState.add_gems(50)
	RunState.add_gold(30)
	_check(GameState.gems == 50 and RunState.gold == 30, "gems and gold tracked independently")
	RunState.end_run(false)
	_check(GameState.gems == 50, "ending a run keeps permanent gems")
	RunState.start_run(999)
	_check(RunState.gold == 0, "a new run resets run gold")
	_check(RunState.floor == 1, "a new run starts on floor 1")

	print("\n== 3. damage pipeline ==")
	var damage := DamageInfo.create(3, Vector2.ZERO, 200.0, &"test")
	_check(damage.amount == 3 and damage.knockback_force == 200.0, "DamageInfo.create sets fields")

	var health := Health.new()
	health.maximum = 5
	health.maximum_armor = 5
	health.armor_regen_delay = 99.0
	add_child(health)
	await get_tree().process_frame
	_check(health.current == 5 and health.armor == 5, "health and armour start full")
	_check(health.effective_total() == 10, "effective total counts armour")

	health.apply_damage(damage)
	_check(health.armor == 2 and health.current == 5, "armour absorbs before health (armour %d hp %d)" % [health.armor, health.current])

	var overflow := DamageInfo.create(4, Vector2.ZERO, 0.0, &"test")
	health.apply_damage(overflow)
	_check(health.armor == 0, "armour fully depleted")
	_check(health.current == 3, "only the overflow reaches health (hp %d)" % health.current)

	health.invincibility_time = 5.0
	health.start_invincibility()
	_check(not health.apply_damage(damage), "i-frames block damage")
	_check(health.current == 3, "hp unchanged during i-frames")

	var lethal := DamageInfo.create(99, Vector2.ZERO, 0.0, &"test")
	lethal.ignores_invincibility = true
	_check(health.apply_damage(lethal), "damage ignoring i-frames lands")
	_check(health.current == 0 and not health.is_alive(), "health depleted")
	_check(health.heal(3) == 0, "healing cannot revive the dead")
	_check(health.restore_armor(3) == 0, "armour cannot be restored while dead")
	health.queue_free()

	print("\n== 4. armour regeneration ==")
	var regen := Health.new()
	regen.maximum = 5
	regen.maximum_armor = 3
	regen.armor_regen_delay = 1.0
	regen.armor_regen_rate = 4.0
	regen.invincibility_time = 0.0
	add_child(regen)
	await get_tree().process_frame
	await regenerate_probe(regen)

	# The bug this catches: refill used to be `armor + 1` once per *frame*, so
	# `armor_regen_rate` was decoration and the shield refilled in five frames.
	# Two shields that differ ONLY in rate must therefore differ in progress.
	var slow := Health.new()
	slow.maximum = 5
	slow.maximum_armor = 3
	slow.armor_regen_delay = 0.0
	slow.armor_regen_rate = 0.5
	slow.invincibility_time = 0.0
	var fast := Health.new()
	fast.maximum = 5
	fast.maximum_armor = 3
	fast.armor_regen_delay = 0.0
	fast.armor_regen_rate = 4.0
	fast.invincibility_time = 0.0
	add_child(slow)
	add_child(fast)
	await get_tree().process_frame
	slow.apply_damage(DamageInfo.create(3, Vector2.ZERO, 0.0, &"test"))
	fast.apply_damage(DamageInfo.create(3, Vector2.ZERO, 0.0, &"test"))
	# Both accumulate the same deltas, so the gap is purely the rate:
	# 0.5/s has earned nothing after 1 s, 4.0/s has earned all three points.
	await get_tree().create_timer(1.0).timeout
	_check(slow.armor == 0 and fast.armor == fast.maximum_armor,
		"regen speed comes from the rate, not the frame count (slow %d / fast %d)"
		% [slow.armor, fast.armor])
	slow.queue_free()
	fast.queue_free()

	print("\n== 5. energy pool ==")
	var energy := EnergyPool.new()
	energy.maximum = 100.0
	energy.regen_per_second = 0.0
	add_child(energy)
	await get_tree().process_frame
	_check(energy.current == 100.0, "energy starts full")
	_check(energy.spend(30.0), "spending within budget succeeds")
	_check(is_equal_approx(energy.current, 70.0), "energy deducted (%.0f)" % energy.current)
	_check(not energy.spend(100.0), "overspending is refused")
	_check(is_equal_approx(energy.current, 70.0), "a refused spend changes nothing")
	energy.refill(20.0)
	_check(is_equal_approx(energy.current, 90.0), "refill adds")
	energy.refill(999.0)
	_check(is_equal_approx(energy.current, 100.0), "refill clamps at maximum")
	energy.queue_free()

	print("\n== 6. weapon registry ==")
	var ids := WeaponRegistry.all_ids()
	_check(ids.size() >= 5, "weapon resources exist (%d found)" % ids.size())
	_check(ids.has(&"pistol") and ids.has(&"shotgun") and ids.has(&"sword"), "expected weapons registered")

	var pistol := WeaponRegistry.load_data(&"pistol")
	_check(pistol != null, "pistol data loads")
	if pistol != null:
		_check(not pistol.is_melee, "pistol is ranged")
		_check(pistol.projectile_count == 1, "pistol fires one bullet")
		_check(pistol.cooldown_time() > 0.0, "pistol has a cooldown")
	var shotgun := WeaponRegistry.load_data(&"shotgun")
	if shotgun != null:
		_check(shotgun.projectile_count == 5, "shotgun fires five pellets")
		_check(shotgun.spread_degrees > 0.0, "shotgun has spread")
	var sword := WeaponRegistry.load_data(&"sword")
	if sword != null:
		_check(sword.is_melee, "sword is melee")
		_check(is_equal_approx(sword.energy_cost, 0.0), "melee costs no energy")

	print("\n== 7. projectile ==")
	var bullet_scene := load("res://scenes/weapons/projectile.tscn") as PackedScene
	_check(bullet_scene != null, "projectile scene loads")
	if bullet_scene != null:
		var bullet := bullet_scene.instantiate() as Projectile
		add_child(bullet)
		await get_tree().process_frame
		_check(bullet.is_player_team, "player bullets are player team by default")
		var start := bullet.global_position
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(bullet.global_position != start, "bullet moves without being told to")
		bullet.queue_free()

	print("\n== 8. save round trip (permanent progression) ==")
	GameState.reset_meta()
	GameState.add_gems(777)
	# Cost comes from the GameState.UPGRADES table now, so buy through the table
	# and let it deduct. Buying must spend gems, so capture what is left.
	var gems_before := GameState.gems
	GameState.buy_upgrade(&"max_health")
	GameState.buy_upgrade(&"max_health")
	var gems_after_buys := GameState.gems
	_check(gems_after_buys < gems_before,
		"buying upgrades deducts gems (%d -> %d)" % [gems_before, gems_after_buys])

	GameState.unlock_character(&"rogue")
	GameState.best_floor = 4
	GameState.total_runs = 9
	_check(GameState.upgrade_level(&"max_health") == 2, "two upgrade levels bought")

	_check(SaveManager.save_game(1), "save writes")
	_check(SaveManager.has_save(1), "slot reports present")

	GameState.reset_meta()
	_check(GameState.gems == 0 and GameState.upgrade_level(&"max_health") == 0, "meta cleared before load")

	_check(SaveManager.load_game(1), "save loads")
	_check(GameState.gems == gems_after_buys,
		"gems restored after reload (%d, expected %d)" % [GameState.gems, gems_after_buys])
	_check(GameState.upgrade_level(&"max_health") == 2, "upgrade levels restored")
	_check(GameState.is_character_unlocked(&"rogue"), "unlocked character restored")
	_check(GameState.best_floor == 4, "best floor restored")
	_check(GameState.total_runs == 9, "run count restored")

	var summary := SaveManager.slot_summary(1)
	_check(int(summary.get("gems", -1)) == gems_after_buys,
		"slot summary reports gems (%d)" % int(summary.get("gems", -1)))
	_check(int(summary.get("best_floor", -1)) == 4, "slot summary reports best floor")
	SaveManager.delete_save(1)
	_check(not SaveManager.has_save(1), "delete removes the slot")

	print("\n== 9. room template catalogue ==")
	# Validated here rather than in test_run because it is a pure data check: a
	# mistyped row or an unsealed pocket is wrong regardless of how it is used.
	var templates := RoomTemplateLibrary.all()
	_check(templates.size() >= 6, "catalogue has templates (%d)" % templates.size())

	var problems := RoomTemplateLibrary.validate_all()
	_check(problems.is_empty(), "every template is valid")
	for problem in problems:
		print("     ! ", problem)

	# The properties Room and Level rely on, asserted per template so a failure
	# names the offending layout instead of just saying "something is wrong".
	var bad_border := 0
	var disconnected := 0
	var empty := 0
	for template in templates:
		if template.walkable_tiles().is_empty():
			empty += 1
			print("     ! '%s' has no walkable tiles" % template.id)
		if not template.border_is_clear():
			bad_border += 1
			print("     ! '%s' blocks its outer ring" % template.id)
		var walkable := template.walkable_tiles().size()
		if template.reachable_count() != walkable:
			disconnected += 1
			print("     ! '%s' is not connected (%d/%d)" % [template.id, template.reachable_count(), walkable])

	_check(empty == 0, "no template is empty")
	_check(bad_border == 0, "every template keeps its outer ring clear (so doors can be carved)")
	_check(disconnected == 0, "every template is internally connected (so a room can be cleared)")

	# Level draws room sizes from the catalogue, so it must offer at least one size
	# and every offered size must resolve to a template.
	var sizes := RoomTemplateLibrary.sizes()
	_check(sizes.size() >= 1, "catalogue offers %d room size(s)" % sizes.size())
	var unresolved := 0
	for size in sizes:
		if RoomTemplateLibrary.for_size(size).is_empty():
			unresolved += 1
	_check(unresolved == 0, "every offered size resolves to a template")

	# Spawn tiles must avoid the border ring: that is where the doorways are, and
	# an enemy parked in a doorway hits the player the moment they walk in.
	var spawn_border_hits := 0
	for template in templates:
		var bounds := template.size()
		for tile in template.spawn_tiles(2):
			if tile.x < 2 or tile.y < 2 or tile.x >= bounds.x - 2 or tile.y >= bounds.y - 2:
				spawn_border_hits += 1
	_check(spawn_border_hits == 0, "spawn tiles stay clear of the border ring")

	# Picking must be deterministic for a seed and must never return null for a
	# size that the catalogue advertises.
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 99
	var first := RoomTemplateLibrary.pick(sizes[0], rng_a)
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 99
	var second := RoomTemplateLibrary.pick(sizes[0], rng_b)
	_check(first != null and second != null, "pick returns a template for an advertised size")
	_check(first != null and second != null and first.id == second.id,
		"pick is deterministic for the same seed")
	_check(RoomTemplateLibrary.pick(Vector2i(7, 7), rng_a) == null,
		"pick returns null for a size with no template (callers fall back)")

	print("\n== summary ==")
	if _failures.is_empty():
		print("ALL %d CHECKS PASSED" % _checks)
	else:
		print("%d of %d CHECKS FAILED:" % [_failures.size(), _checks])
		for failure in _failures:
			print("   - ", failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


## Armour regen runs on real time and `create_timer` overshoots by up to a whole
## frame, so these margins are wide on purpose: the old 0.15 s delay probed at
## 0.1 s left 0.05 s of slack, and one slow frame failed the suite at random.
func regenerate_probe(regen: Health) -> void:
	regen.apply_damage(DamageInfo.create(3, Vector2.ZERO, 0.0, &"test"))
	_check(regen.armor == 0, "armour broken before regen test")

	# 0.2 s < armor_regen_delay (1.0 s): still empty.
	await get_tree().create_timer(0.2).timeout
	_check(regen.armor == 0, "armour does not regen before the delay elapses")

	# 1.5 s total > delay + 1/rate (1.25 s): at least one point back, and true
	# both under the current per-frame +1 and under a fixed armor_regen_rate.
	await get_tree().create_timer(1.3).timeout
	_check(regen.armor >= 1, "armour regenerates after the delay (armour %d)" % regen.armor)
	regen.queue_free()
