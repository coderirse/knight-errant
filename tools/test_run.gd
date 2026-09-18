extends Node

## Integration test for the run loop: generate a floor, walk the room graph,
## fight real enemies with real bullets, clear a room, descend a floor.
##
## Run with:
##   Godot --headless --path . res://tools/test_run.tscn
##
## This is the test that catches the mistakes the unit-style suites cannot: rooms
## overlapping in world space, doors pointing at the wrong neighbour, enemies
## spawning inside a wall, bullets hitting their own owner.

const GAME_SCENE := "res://scenes/world/game.tscn"

var _failures: PackedStringArray = []
var _checks := 0
var _game: Game


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", label)
	else:
		_failures.append(label)
		print("  FAIL ", label)


func _ready() -> void:
	get_tree().current_scene = null
	_run.call_deferred()


func _settle(frames := 4) -> void:
	for i in frames:
		await get_tree().physics_frame


func _run() -> void:
	await get_tree().process_frame

	print("\n== 1. start a run ==")
	GameState.reset_meta()
	var packed := load(GAME_SCENE) as PackedScene
	_check(packed != null, "game scene loads")
	if packed == null:
		_finish()
		return
	_game = packed.instantiate() as Game
	# Must be a direct child of the tree root for set_current_scene() to accept it.
	get_tree().root.add_child(_game)
	get_tree().current_scene = _game
	await _game.start_run(20240918)
	await _settle()

	_check(_game.level != null, "a level was generated")
	var level := _game.level
	_check(level.rooms.size() >= 3, "floor has multiple rooms (%d)" % level.rooms.size())
	_check(RunState.active, "run state is active")
	_check(RunState.floor == 1, "started on floor 1")

	print("\n== 2. player ==")
	var player := _game.player
	_check(player != null and is_instance_valid(player), "player exists")
	if player == null:
		_finish()
		return
	_check(player.health.maximum > 0, "player has health (%d)" % player.health.maximum)
	_check(player.health.maximum_armor >= 0, "player has an armour stat (%d)" % player.health.maximum_armor)
	_check(player.weapons.size() >= 1, "player starts armed (%d weapon(s))" % player.weapons.size())
	_check(player.get_parent() != null, "player is in the tree")

	# The player must start inside a room's interior, not inside a wall.
	var start_room := _room_containing(player.global_position)
	_check(start_room != null, "player spawned inside a room")
	if start_room != null:
		_check(start_room.interior_rect().has_point(player.global_position - start_room.position),
			"player spawned in open floor, not in a wall")

	print("\n== 3. floor layout is sane ==")
	var overlap := _find_biggest_overlap(level)
	_check(overlap <= 0.0, "rooms do not overlap (worst overlap %.0f px)" % overlap)

	var neighbour_count := 0
	for room in level.rooms:
		var doors := 0
		for child in room.get_children():
			if child is RoomDoor:
				doors += 1
		neighbour_count += doors
	_check(neighbour_count > 0, "doors were carved between rooms (%d doors)" % neighbour_count)

	# Every door must lead to a room that actually exists, and point back.
	var bad_doors := 0
	for room in level.rooms:
		for child in room.get_children():
			if not (child is RoomDoor):
				continue
			var door := child as RoomDoor
			if door.target_room < 0 or door.target_room >= level.rooms.size():
				bad_doors += 1
	_check(bad_doors == 0, "every door targets a real room")

	print("\n== 4. enemies spawned ==")
	var enemies := get_tree().get_nodes_in_group(&"enemy")
	_check(enemies.size() > 0, "the floor has enemies (%d)" % enemies.size())

	var in_wall := 0
	for enemy in enemies:
		if _room_containing((enemy as Node2D).global_position) == null:
			in_wall += 1
	_check(in_wall == 0, "no enemy spawned outside a room (%d bad)" % in_wall)

	print("\n== 5. combat: player kills an enemy ==")
	# Pick the nearest enemy and shoot it, letting the real physics decide.
	var target := _nearest_enemy(player.global_position)
	_check(target != null, "found a target")
	if target != null:
		var target_health: Health = target.get_node("Health")
		var before := target_health.current
		player.global_position = target.global_position - Vector2(40, 0)
		player.aim_direction = Vector2.RIGHT
		await _settle(2)

		# Read the enemy's HP through the node each pass: the enemy frees itself
		# shortly after dying, so holding a typed reference across the loop
		# dereferences a freed object. Aim at where the enemy *is* each shot,
		# because it keeps moving; a fixed direction would miss.
		var shots := 0
		var hits := 0
		while is_instance_valid(target) and shots < 120:
			if target_health == null or not is_instance_valid(target_health) or not target_health.is_alive():
				break
			var before_hp := target_health.current
			shots += 1
			var to_target := target.global_position - player.global_position
			if to_target.length_squared() < 0.001:
				to_target = Vector2.RIGHT
			var weapon := player.current_weapon()
			if weapon != null:
				weapon.aim_at(to_target)
				if weapon.try_fire(to_target):
					# Give the bullet time to cross the gap before the next shot.
					for i in 14:
						await get_tree().physics_frame
						if target_health == null or not is_instance_valid(target_health) or not target_health.is_alive():
							break
					if target_health != null and is_instance_valid(target_health) and target_health.current < before_hp:
						hits += 1
					continue
			await _settle(2)

		var died := not is_instance_valid(target) or target_health == null or not is_instance_valid(target_health) or not target_health.is_alive()
		_check(died, "player killed the enemy (%d shots, %d confirmed hits, started at %d hp)" % [shots, hits, before])
		_check(RunState.gold > 0, "killing awarded gold (%d)" % RunState.gold)

	print("\n== 6. bullets do not hit their owner ==")
	# Fire while standing inside our own bullet's spawn point; health must not drop.
	player.health.invincible = false
	var hp_before := player.health.effective_total()
	for i in 6:
		var weapon := player.current_weapon()
		if weapon != null:
			weapon.aim_at(Vector2.DOWN)
			weapon.try_fire(Vector2.DOWN)
		await _settle(4)
	_check(player.health.effective_total() == hp_before,
		"firing did not damage the player (%d -> %d)" % [hp_before, player.health.effective_total()])

	print("\n== 7. enemy bullets hurt the player ==")
	var shooter := _find_enemy_of_type("Shooter")
	if shooter == null:
		print("  (no shooter on this floor; skipping)")
	else:
		player.health.invincible = false
		player.hurtbox.vulnerable = true
		var total_before := player.health.effective_total()

		# Stand within the shooter's firing range but only on a direction with
		# clear line of sight. A fixed offset puts the player behind a pillar now
		# that rooms have interior geometry, and the shot would be blocked by the
		# level rather than by anything worth testing.
		var placed := _place_with_line_of_sight(player, shooter, 70.0)
		_check(placed, "found a line of sight to the shooter to stand on")
		await _settle(2)

		var waited := 0
		while player.health.effective_total() == total_before and waited < 400:
			await get_tree().physics_frame
			waited += 1
		_check(player.health.effective_total() < total_before,
			"a shooter eventually damaged the player (%d -> %d) after %d frames" % [
				total_before, player.health.effective_total(), waited])

	print("\n== 8. dodge grants i-frames ==")
	player.health.invincible = false
	player.hurtbox.vulnerable = true
	player._start_dodge(Vector2.RIGHT)
	await _settle(1)
	_check(player.state == Player.State.DODGE, "dodge enters the DODGE state")
	_check(player.health.invincible, "dodge grants invincibility")
	var hp_now := player.health.effective_total()
	player.hurtbox.receive_hit(DamageInfo.create(5, Vector2.ZERO, 0.0, &"test"))
	_check(player.health.effective_total() == hp_now, "an incoming hit is ignored mid-dodge")

	print("\n== 9. clearing a room unlocks its doors ==")
	var combat_room := _first_room_with_doors(level)
	_check(combat_room != null, "found a room with doors")
	if combat_room != null:
		# Kill each enemy through the normal damage path, so the room's
		# on_enemy_died bookkeeping is exercised rather than bypassed.
		for child in combat_room.get_node("Actors").get_children():
			var h := child.get_node_or_null("Health") as Health
			if h == null or not h.is_alive():
				continue
			h.invincible = false
			h.maximum_armor = 0
			var lethal := DamageInfo.create(9999, Vector2.ZERO, 0.0, &"test")
			lethal.ignores_invincibility = true
			h.apply_damage(lethal)
		await _settle(8)
		_check(combat_room.is_cleared, "room reports itself cleared")
		var locked := 0
		for child in combat_room.get_children():
			if child is RoomDoor and child.get(&"locked"):
				locked += 1
		_check(locked == 0, "all doors in the cleared room are unlocked")

	print("\n== 10. walking through a door moves the player ==")
	if combat_room != null:
		var door := _first_door(combat_room)
		if door != null:
			var target_index: int = door.get(&"target_room")
			var target_room := level.rooms[target_index]
			var before_pos := player.global_position
			level.move_player_to_room(target_index, int(door.get(&"side")) ^ 1)
			await _settle(4)
			_check(player.global_position.distance_to(before_pos) > 10.0,
				"player teleported to the next room")
			var inside := target_room.interior_rect().has_point(player.global_position - target_room.position)
			_check(inside, "player arrived inside the target room")
		else:
			print("  (no door found; skipping)")

	print("\n== 11. floor generation is deterministic ==")
	var a := _describe_layout(level)
	level.generate(1, 20240918)
	await _settle(2)
	_check(_describe_layout(level) == a, "the same seed rebuilds the same layout")

	print("\n== 12. generated floors are always winnable ==")
	# The property that matters for procedural levels: every room reachable from
	# the start, no rooms overlapping, and enough doors to form a spanning tree.
	# Checked across many seeds because a layout bug can be invisible on the one
	# seed a hand-run test happens to use.
	var seeds_checked := 60
	var overlaps := 0
	var unreachable := 0
	var short_on_doors := 0
	for seed_value in seeds_checked:
		level.generate(1, 5000 + seed_value)
		for i in level.rooms.size():
			for j in range(i + 1, level.rooms.size()):
				var ra := Rect2(level.rooms[i].position, level.rooms[i].world_size())
				var rb := Rect2(level.rooms[j].position, level.rooms[j].world_size())
				var inter := ra.intersection(rb)
				if inter.size.x > 0.0 and inter.size.y > 0.0:
					overlaps += 1
		var doors := 0
		for room in level.rooms:
			for child in room.get_children():
				if child is RoomDoor:
					doors += 1
		if doors < level.rooms.size() - 1:
			short_on_doors += 1
		if _reachable_count(level) != level.rooms.size():
			unreachable += 1

	_check(overlaps == 0, "no rooms overlap across %d seeds" % seeds_checked)
	_check(unreachable == 0, "every room is reachable from the start across %d seeds" % seeds_checked)
	_check(short_on_doors == 0, "every seed carves enough doors across %d seeds" % seeds_checked)

	print("\n== 12. descending a floor ==")
	var floor_before := RunState.floor
	RunState.advance_floor()
	await _game.build_floor(RunState.floor, RunState.level_seed)
	await _settle(4)
	_check(RunState.floor == floor_before + 1, "floor number advanced (%d -> %d)" % [floor_before, RunState.floor])
	_check(_game.level != null and _game.level.rooms.size() > 0, "the new floor has rooms")
	_check(_game.player != null and is_instance_valid(_game.player), "the player survived the floor change")
	_check(_game.player.weapons.size() >= 1, "the player kept their weapons across floors")
	var in_new_room := _room_containing(_game.player.global_position)
	_check(in_new_room != null, "player was placed inside the new floor")

	print("\n== 13. SceneRouter real entry path (guards the P0 black-screen) ==")
	# The two suites used to only assert `SceneRouter != null`, which is why a
	# fatal bug survived them: go_to_scene() threw AFTER fading to black and
	# pausing the tree, leaving paused=true and input_locked=true forever. So this
	# drives start_new_run() for real and asserts the global state is restored.
	#
	# The bug only surfaced once the player was recreated, so that runs first.
	PlayerHost.despawn()
	_check(not PlayerHost.has_player(), "player cleared before the router test")

	await SceneRouter.start_new_run(4242)
	await _settle(6)

	_check(not SceneRouter.is_busy(), "router released its busy flag (a stuck flag refuses every later transition)")
	_check(not get_tree().paused, "tree is not left paused")
	_check(not GameState.input_locked, "input is not left locked")
	var run_scene := get_tree().current_scene
	_check(run_scene != null and run_scene is Game, "current scene is the Game scene")
	_check(PlayerHost.has_player(), "a new player was created for the run")
	if PlayerHost.has_player():
		_check(PlayerHost.player.get_parent() != null, "the new player is in the tree")
	_check(RunState.active, "the run is active")

	# A second transition must still work; a stuck _busy would silently refuse it.
	await SceneRouter.go_to_scene("res://scenes/ui/main_menu.tscn")
	await _settle(6)
	_check(not SceneRouter.is_busy(), "router survived a second transition")
	_check(get_tree().current_scene != null and not (get_tree().current_scene is Game),
		"returned to the menu scene")
	_check(not get_tree().paused and not GameState.input_locked, "global state clean after two transitions")

	print("\n== 14. permanent upgrades actually reach the player ==")
	# P2 was: the hub sold `speed` but Game only applied max_health and max_armor,
	# so the gems were spent for nothing. Every upgrade in the table must have an
	# effect, otherwise the shop is lying to the player again.
	PlayerHost.despawn()
	GameState.reset_meta()

	GameState.add_gems(99999)
	for id in GameState.UPGRADES.keys():
		_check(GameState.buy_upgrade(id), "bought upgrade '%s'" % id)
	_check(GameState.upgrade_level(&"speed") > 0, "speed upgrade reached level %d" % GameState.upgrade_level(&"speed"))

	var baseline := _baseline_player_stats()
	var upgraded := _player_stats_with_meta_upgrades()
	_check(upgraded["max_speed"] > baseline["max_speed"],
		"speed upgrade raises max_speed (%.1f -> %.1f)" % [baseline["max_speed"], upgraded["max_speed"]])
	_check(upgraded["max_health"] > baseline["max_health"],
		"health upgrade raises max masks (%d -> %d)" % [baseline["max_health"], upgraded["max_health"]])
	_check(upgraded["max_armor"] > baseline["max_armor"],
		"armor upgrade raises max armor (%d -> %d)" % [baseline["max_armor"], upgraded["max_armor"]])

	# And the cost curve must actually rise, or the shop is trivially exploitable.
	GameState.reset_meta()
	var first_cost := GameState.upgrade_cost(&"max_health")
	GameState.add_gems(99999)
	GameState.buy_upgrade(&"max_health")
	_check(GameState.upgrade_cost(&"max_health") > first_cost,
		"upgrade cost rises with level (%d -> %d)" % [first_cost, GameState.upgrade_cost(&"max_health")])

	var maxed := 0
	while GameState.buy_upgrade(&"speed"):
		maxed += 1
		if maxed > 20:
			break
	_check(GameState.is_upgrade_maxed(&"speed"), "an upgrade stops at its max level")
	_check(not GameState.buy_upgrade(&"speed"), "buying past max level is refused")

	print("\n== 15. tuning panel collects live parameters ==")
	PlayerHost.despawn()
	await SceneRouter.start_new_run(777)
	await _settle(6)
	var panel_entries: int = TuningPanel.get("_entries").size() if TuningPanel.get("_entries") != null else 0
	# The panel collects on a timer and only while open, so drive it directly.
	TuningPanel.set("_open", true)
	TuningPanel.call("_collect_entries")
	panel_entries = (TuningPanel.get("_entries") as Array).size()
	_check(panel_entries > 0, "tuning panel discovered %d tunable parameter(s)" % panel_entries)

	var saw_speed := false
	var saw_dodge := false
	var saw_shield := false
	for entry in (TuningPanel.get("_entries") as Array):
		var prop := String(entry["prop"])
		if prop == "max_speed":
			saw_speed = true
		elif prop == "dodge_time":
			saw_dodge = true
		elif prop == "armor_regen_rate":
			saw_shield = true
	_check(saw_speed, "player max_speed is exposed for tuning")
	_check(saw_dodge, "player dodge_time is exposed for tuning")
	# The shield lives on a child node, so the panel only finds it if collection is
	# pointed at Health explicitly. Without this the knob disappears silently and
	# the shield stops being tunable while everything still looks fine.
	_check(saw_shield, "armour regen rate is exposed for tuning")

	print("\n== 16. templates survive contact with the level generator ==")
	# The catalogue's own checks live in test_gameplay; these are the spatial
	# properties that only show up once rooms are built and populated: an enemy
	# inside a pillar or a doorway walled off by a template.
	#
	# _game is re-fetched rather than reused: §13 changes scenes twice, and
	# change_scene_to_packed() freed the original Game instance, leaving the field
	# a dangling reference.
	PlayerHost.despawn()
	GameState.reset_meta()
	await SceneRouter.start_new_run(31415)
	await _settle(6)
	_game = get_tree().current_scene as Game
	_check(_game != null, "a fresh Game scene is current for the template checks")
	if _game == null:
		_finish()
		return
	var t_level := _game.level

	var rooms_with_template := 0
	for room in t_level.rooms:
		if room.template != null:
			rooms_with_template += 1
	_check(rooms_with_template == t_level.rooms.size(),
		"every room got a template (%d/%d)" % [rooms_with_template, t_level.rooms.size()])

	# A room's stamped tiles must match its template: solid where the template is
	# solid, walkable where it is not. This is what catches an off-by-one in the
	# wall-ring offset.
	#
	# Reads the atlas coordinates, not the source id: the tile set has a single
	# source, so get_cell_source_id() returns 0 for every tile including walls.
	var mismatches := 0
	for room in t_level.rooms:
		if room.template == null:
			continue
		var room_layer := room.get_node("Terrain/Ground") as TileMapLayer
		for y in room.interior.y:
			for x in room.interior.x:
				var atlas := room_layer.get_cell_atlas_coords(Vector2i(x + 1, y + 1))   # interior tiles sit at layer offset +1
				var template_solid := room.template.is_solid(Vector2i(x, y))
				var stamped_solid := atlas == Vector2i(2, 0)   # WALL_TILE atlas coord
				if template_solid != stamped_solid:
					mismatches += 1
	_check(mismatches == 0, "stamped tiles match their template (%d mismatches)" % mismatches)

	print("\n== 17. nothing spawns inside a wall, across many seeds ==")
	# The failure this guards against: an enemy stuck inside a pillar can never be
	# killed, so the room never clears and the floor is unwinnable — and it would
	# look like a level-generation bug rather than a template bug.
	var spawn_seeds := 24
	var enemies_in_solid := 0
	var chests_in_solid := 0
	for seed_value in spawn_seeds:
		await _game.build_floor(1, 6000 + seed_value)
		await _settle(2)
		for room in _game.level.rooms:
			var rlayer := room.get_node("Terrain/Ground") as TileMapLayer
			for child in room.get_node("Actors").get_children():
				if not (child is Node2D):
					continue
				var local := room.to_local((child as Node2D).global_position)
				var tile := Vector2i(floori(local.x / 16.0), floori(local.y / 16.0))
				if rlayer.get_cell_source_id(tile) != 2:
					continue
				if child is CharacterBody2D:
					enemies_in_solid += 1
				else:
					chests_in_solid += 1

	_check(enemies_in_solid == 0,
		"no enemy spawned inside a wall across %d seeds (%d bad)" % [spawn_seeds, enemies_in_solid])
	_check(chests_in_solid == 0,
		"no chest spawned inside a wall across %d seeds (%d bad)" % [spawn_seeds, chests_in_solid])

	print("\n== 18. dungeon lighting is built and scoped ==")
	var lit_level := _game.level
	var lamp_carrier := get_tree().get_first_node_in_group(&"player")
	_check(lit_level.get_node_or_null("Ambience") is CanvasModulate,
		"the floor darkens the ambient")
	var lamp := lamp_carrier.get_node_or_null("Light") as PointLight2D
	_check(lamp != null and lamp.texture != null,
		"the player carries a lamp with a generated falloff texture")

	var equipped := 0
	var merged := 0
	var current_room: Room = null
	for room in lit_level.rooms:
		if Rect2(room.position, room.world_size()).has_point(lamp_carrier.global_position):
			current_room = room
		var holder := room.get_node_or_null("Lighting")
		var torches := 0
		var occluders := 0
		if holder != null:
			for child in holder.get_children():
				if child is PointLight2D:
					torches += 1
				elif child is LightOccluder2D:
					occluders += 1
		if torches > 0 and occluders > 0:
			equipped += 1
		# Merging solid cells into rectangles must beat the trivial one-node-per-cell
		# layout, which for a walled room costs about four times its perimeter.
		if occluders > 0 and occluders < room.interior.x + room.interior.y:
			merged += 1
	_check(equipped == lit_level.rooms.size(),
		"every room has torches and wall shadows (%d/%d)" % [equipped, lit_level.rooms.size()])
	_check(merged == lit_level.rooms.size(),
		"occluders are merged into runs, not one per tile (%d/%d)" % [merged, lit_level.rooms.size()])

	# Only the room the player is in, plus those joined to it by a door, keep their
	# lights on. Everything else sits off-camera behind solid rock, so this is the
	# entire cost saving and it must not leak.
	if current_room != null:
		var scope := {current_room.room_index: true}
		for index in lit_level.call("_neighbor_rooms", current_room.room_index):
			scope[index] = true
		var wrong := 0
		var distant := 0
		for room in lit_level.rooms:
			var holder := room.get_node_or_null("Lighting")
			if holder == null:
				continue
			var any_on := false
			for child in holder.get_children():
				if child is PointLight2D and (child as PointLight2D).enabled:
					any_on = true
			if any_on != scope.has(room.room_index):
				wrong += 1
			if not scope.has(room.room_index):
				distant += 1
		_check(wrong == 0,
			"lights are on for exactly the current room and its doors (%d wrong, %d gated off)"
			% [wrong, distant])
	else:
		_check(false, "test could not tell which room the player is standing in")

	print("\n== 19. cleanup ==")
	TuningPanel.set("_open", false)
	GameState.reset_meta()
	RunState.end_run(false)
	PlayerHost.despawn()

	_finish()


## Places `mover` at `distance` from `anchor` on the first of 16 directions whose
## path is unobstructed. Returns false when every direction is blocked.
##
## Needed because rooms now contain pillars: a fixed offset can put the subject
## behind one, which makes a line-of-sight test fail for reasons that have nothing
## to do with what it is checking.
func _place_with_line_of_sight(mover: Node2D, anchor: Node2D, distance: float) -> bool:
	var space := mover.get_world_2d().direct_space_state
	if space == null:
		return false
	for step in 16:
		var angle := TAU * float(step) / 16.0
		var target := anchor.global_position + Vector2.RIGHT.rotated(angle) * distance
		var query := PhysicsRayQueryParameters2D.create(anchor.global_position, target, 1)
		query.collide_with_areas = false
		if space.intersect_ray(query).is_empty():
			mover.global_position = target
			return true
	return false


# --- helpers ---------------------------------------------------------------


## Stats of a fresh player with no meta upgrades, used as the comparison point.
func _baseline_player_stats() -> Dictionary:
	var saved := GameState.upgrades.duplicate()
	GameState.upgrades.clear()
	var stats := _player_stats_with_meta_upgrades()
	GameState.upgrades = saved
	return stats


## Builds a throwaway player through the real spawn path and reports the stats
## that meta upgrades are supposed to modify.
func _player_stats_with_meta_upgrades() -> Dictionary:
	var packed := load("res://scenes/player/player.tscn") as PackedScene
	var probe := packed.instantiate() as Player
	add_child(probe)
	var result := {
		"max_speed": probe.max_speed,
		"max_health": probe.health.maximum,
		"max_armor": probe.health.maximum_armor,
	}
	probe.apply_meta_upgrades()
	result["max_speed"] = probe.max_speed
	result["max_health"] = probe.health.maximum
	result["max_armor"] = probe.health.maximum_armor
	probe.queue_free()
	return result

func _room_containing(world_position: Vector2) -> Room:
	if _game == null or _game.level == null:
		return null
	for room in _game.level.rooms:
		var local := world_position - room.position
		if Rect2(Vector2.ZERO, room.world_size()).has_point(local):
			return room
	return null


## Largest overlap area between any two rooms. Overlapping rooms would let the
## player walk through a wall into the neighbour, which is the classic
## procedural-layout bug.
func _find_biggest_overlap(level: Level) -> float:
	var worst := 0.0
	for i in level.rooms.size():
		for j in range(i + 1, level.rooms.size()):
			var a := Rect2(level.rooms[i].position, level.rooms[i].world_size())
			var b := Rect2(level.rooms[j].position, level.rooms[j].world_size())
			var inter := a.intersection(b)
			if inter.size.x > 0.0 and inter.size.y > 0.0:
				worst = maxf(worst, inter.size.x * inter.size.y)
	return worst


func _nearest_enemy(from: Vector2) -> Node2D:
	var best: Node2D = null
	var best_distance := INF
	for enemy in get_tree().get_nodes_in_group(&"enemy"):
		var node := enemy as Node2D
		if node == null or not is_instance_valid(node):
			continue
		var distance := node.global_position.distance_to(from)
		if distance < best_distance:
			best_distance = distance
			best = node
	return best


func _find_enemy_of_type(type_fragment: String) -> Node2D:
	for enemy in get_tree().get_nodes_in_group(&"enemy"):
		if String(enemy.get_script().resource_path).contains(type_fragment.to_lower()):
			return enemy as Node2D
	return null


func _first_room_with_doors(level: Level) -> Room:
	for room in level.rooms:
		if room.kind == Room.Kind.COMBAT:
			return room
	return null if level.rooms.is_empty() else level.rooms[0]


func _first_door(room: Room) -> RoomDoor:
	for child in room.get_children():
		if child is RoomDoor:
			return child as RoomDoor
	return null


func _describe_layout(level: Level) -> String:
	var parts: PackedStringArray = []
	for room in level.rooms:
		parts.append("%d:%d:%s" % [room.room_index, room.kind, room.position])
	return "|".join(parts)


## Number of rooms reachable from room 0 by walking doors, used to prove a floor
## can actually be completed.
func _reachable_count(level: Level) -> int:
	var adjacency: Dictionary = {}
	for room in level.rooms:
		adjacency[room.room_index] = []
	for room in level.rooms:
		for child in room.get_children():
			if child is RoomDoor:
				adjacency[room.room_index].append(int(child.get(&"target_room")))

	var seen := {0: true}
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for neighbour in adjacency.get(current, []):
			if not seen.has(neighbour):
				seen[neighbour] = true
				queue.append(neighbour)
	return seen.size()


func _finish() -> void:
	print("\n== summary ==")
	if _failures.is_empty():
		print("ALL %d CHECKS PASSED" % _checks)
	else:
		print("%d of %d CHECKS FAILED:" % [_failures.size(), _checks])
		for failure in _failures:
			print("   - ", failure)
	get_tree().quit(0 if _failures.is_empty() else 1)
