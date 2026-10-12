extends SceneTree
## Direct user rulings, after watching two enemy squads stand 300 m from our squads for minutes with no line of sight, firing nothing, while
## the rest of the force fought: "They do it, but slowly. OK, then give them a chance every minute to do something sensible. They may sit
## for a while, but not indefinitely", and: "Do the same thing for our squads, but probably a higher chance per minute as individual
## initiative is expected."
##
## A squad that has stopped with nothing to shoot at rolls once every full minute it has been idle (enemy 0.2, ours 0.4): on success it moves
## to a nearby place with a line of sight on the opposing squad it faces within range (cover preferred); the enemy, failing that, closes on it;
## ours go only to cover. Waits are timed per squad and start afresh when it was not idle for a while.
##
## Run: godot --headless --path . --script scripts/tests/test_squad_standoff_initiative.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
const Orders = preload("res://scripts/unit_doctrine.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(x: float, y: float) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

## Our squad at (1665, 1855) (a Voznesensk tree patch), an enemy squad 300 m east.
func make() -> Dictionary:
	GameConfig.set_active_map("voznesensk")
	seed(9)
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.unit_type_doctrines[Unit.Team.ENEMY] = Orders.sanitize({})
	var ours: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(1665, 1855))
	bm.player_units.append(ours)
	ours.enemy_has_been_sighted = true
	ours.enemy_known_position = ours.global_position
	ours.enemy_known_state = Unit.State.ACTIVE
	var foe: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(1665 + 300, 1855))
	bm.enemy_units.append(foe)
	foe.sought_cover = true
	foe.player_has_been_sighted = true
	foe.player_known_position = foe.global_position
	foe.player_known_state = Unit.State.ACTIVE
	return {"bm": bm, "ours": ours, "foe": foe}

## Waits `minutes` full minutes calling the function each time; returns true once it acted.
func wait_and_try(bm: BattleManager, u: Unit, facing: Vector2, chance: float, close_if_none: bool, require_cover: bool, minutes: int) -> int:
	# called every few seconds, as the real update does (a gap of more than 15 s counts as having stopped being idle)
	for i in minutes:
		for step in 13:
			bm.scenario_elapsed_time += 5.0
			if bm._squad_standoff_initiative(u, facing, chance, close_if_none, require_cover):
				return i + 1
	return -1

func run() -> void:
	# 1. the enemy: nothing in the first minute; acts within an hour; the reason is stated; the place is within range of the squad it faces
	var c := make()
	var bm: BattleManager = c.bm
	var foe: Unit = c.foe
	var facing: Vector2 = c.ours.global_position
	check(not bm._squad_standoff_initiative(foe, facing, 0.2, true, false), "At the first sight of its idleness nothing happens (the wait is timed from there)")
	for step in 6:
		bm.scenario_elapsed_time += 5.0
		bm._squad_standoff_initiative(foe, facing, 0.2, true, false)
	check(not foe.has_move_target, "...nor half a minute on")
	var after: int = wait_and_try(bm, foe, facing, 0.2, true, false, 60)
	check(after >= 1, "It does act within an hour (at 0.2 a minute the chance of not doing so is a millionth) (after %d minutes)" % after)
	check(foe.has_move_target and foe.last_order_reason.begins_with("Taking the initiative"), "...with its reason stated (%s)" % foe.last_order_reason)
	check(foe.move_target.distance_to(foe.global_position) > 0.0, "...to somewhere other than where it stands")
	bm.combat_log.free()
	bm.free()

	# 2. the rates: after ten idle minutes about 1 - 0.8^10 = 89% of enemy squads have acted, 1 - 0.6^10 = 99% of ours
	var results := {}
	for entry in [["enemy", 0.2, Unit.Team.ENEMY, true, false], ["ours", 0.4, Unit.Team.PLAYER, false, true]]:
		c = make()
		bm = c.bm
		var acted := 0
		var trials := 300
		for i in trials:
			var squad: Unit = bm._make_unit(entry[2], Unit.Kind.SQUAD, m(1665 + 300, 1855) if entry[2] == Unit.Team.ENEMY else m(1665, 1855))
			if entry[2] == Unit.Team.ENEMY:
				bm.enemy_units.append(squad)
			else:
				bm.player_units.append(squad)
			var face: Vector2 = c.ours.global_position if entry[2] == Unit.Team.ENEMY else c.foe.global_position
			var t0: float = bm.scenario_elapsed_time
			bm._squad_standoff_initiative(squad, face, entry[1], entry[3], entry[4])
			if wait_and_try(bm, squad, face, entry[1], entry[3], entry[4], 10) > 0:
				acted += 1
			bm.scenario_elapsed_time = t0
		results[entry[0]] = float(acted) / float(trials)
		bm.combat_log.free()
		bm.free()
	check(results["enemy"] > 0.78 and results["enemy"] < 0.97, "About 89%% of enemy squads have acted after ten idle minutes (%.0f%%)" % (100.0 * results["enemy"]))
	check(results["ours"] > results["enemy"], "...more of ours: individual initiative is expected (%.0f%% against %.0f%%)" % [100.0 * results["ours"], 100.0 * results["enemy"]])

	# 3. ours go only to cover: with require_cover and a place in the open the only one with a line of sight, it stays put (a wait the full
	# hour finds no place) -- checked here through the destination being in cover whenever it does act
	c = make()
	bm = c.bm
	var squad2: Unit = c.ours
	var acted_to_cover := true
	var acted_any := false
	for i in 40:
		for step in 13:
			bm.scenario_elapsed_time += 5.0
			if bm._squad_standoff_initiative(squad2, c.foe.global_position, 1.0, false, true):
				acted_any = true
				if not GameConfig.is_in_cover(GameConfig.get_terrain_type_at(squad2.move_target)):
					acted_to_cover = false
				squad2.has_move_target = false
	check(acted_to_cover, "Our squad's initiative never takes it out of cover%s" % ("" if acted_any else " (it found no place at all)"))
	bm.combat_log.free()
	bm.free()

	# 4. the wait starts afresh when the squad was not idle for a while
	c = make()
	bm = c.bm
	for step in 11:
		bm.scenario_elapsed_time += 5.0
		bm._squad_standoff_initiative(c.foe, c.ours.global_position, 0.0, true, false) # idle for 55 s, rolling nothing
	bm.scenario_elapsed_time += 600.0 # it fought, or moved, for ten minutes: not idle
	var acted_now: bool = bm._squad_standoff_initiative(c.foe, c.ours.global_position, 1.0, true, false)
	check(not acted_now and float(bm._standoff_idle[c.foe].since) == bm.scenario_elapsed_time, "A squad idle again after a long spell of something else starts its wait afresh")
	bm.combat_log.free()
	bm.free()

	# 5. through the real paths: an idle enemy squad at the ring (its objective a known friendly squad) acts in time; so does ours in cover with
	# an enemy squad known within reach
	c = make()
	bm = c.bm
	bm._update_enemy_attack_stance()
	bm._known_friendly_squad_objective(c.foe)
	var moved := false
	for i in 80 * 13:
		bm.scenario_elapsed_time += 5.0
		bm._update_enemy_squad_advance()
		if c.foe.has_move_target and c.foe.last_order_reason.begins_with("Taking the initiative"):
			moved = true
			break
	check(moved or not c.foe.is_targetable(), "An enemy squad held at the ring through the real update takes the initiative in the end (or it found a target and fought)")
	bm.combat_log.free()
	bm.free()

	# 6. ours, through the real path: standing in cover with an enemy squad known 300 m off that it cannot shoot at, the wait is timed (and when
	# a place in cover with a line of sight on it is near, it takes it)
	c = make()
	bm = c.bm
	c.foe.is_visible = false
	check(GameConfig.is_in_cover(c.ours.terrain_type()), "Setup: our squad stands in cover")
	var timed := false
	var took_it := false
	for i in 40 * 13:
		bm.scenario_elapsed_time += 5.0
		bm._update_friendly_squad_positioning()
		if bm._standoff_idle.has(c.ours):
			timed = true
		if c.ours.has_move_target and c.ours.last_order_reason.begins_with("Taking the initiative"):
			took_it = true
			break
	check(timed, "Our idle squad in cover, with an enemy squad known within reach, is timed by the real positioning update%s" % (" and took the initiative" if took_it else ""))
	bm.combat_log.free()
	bm.free()

	print("Squad standoff initiative tests: %d failures" % failures)
	quit(1 if failures else 0)
