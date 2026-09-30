extends SceneTree
## A drone has no weapon, so it cannot overrun a mortar crew: an enemy (or friendly)
## mortar must not run — least of all off the map — because a drone came near or
## sighted it. It still reacts to anything else: a squad, counter-battery fire.
##
## Direct user ruling, extending the exact same reasoning to a SPOTTER: "If the enemy has not seen the
## spotter, the spotter should have no effect on their actions. If they have seen the spotter, this is good
## reason for the mortar to take evasive action, but not to leave the map. Instead, the mortar should
## assume its location is known and move in a way that makes it hard for friendly artillery to hit it,
## similar to what it would do if seen by a drone." A lone forward observer, like an aircraft overhead, has
## no weapon and cannot physically overrun or assault a crew either — the same tier-1 treatment, not a
## separate mechanism (_mortar_troubled_only_by_unarmed_observers/_mortar_has_seen_an_unarmed_observer).
## "If we ever have a scenario with an enemy spotter, this would apply symmetrically to friendly mortars" —
## already true here: `make()`'s `other` unit can be on either team, and the last test in this file already
## exercises the mirror direction for a drone; nothing about the fix is team-specific.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_ignores_drone.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(v: float) -> float:
	return v * GameConfig.PIXELS_PER_METER

## An enemy mortar with a sighted player unit of `kind` `dist_m` to its west. `seen`
## makes the mortar visible (spotted) to that unit.
func make(kind: Unit.Kind, dist_m: float, seen: bool) -> Dictionary:
	seed(3)
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var mort: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(4700, 637))
	bm.enemy_units.append(mort)
	var other: Unit = bm._make_unit(Unit.Team.PLAYER, kind, mort.global_position + Vector2(-m(dist_m), 0))
	bm.player_units.append(other)
	other.is_visible = true
	bm._update_enemy_intel()
	mort.is_visible = seen
	return {"bm": bm, "mortar": mort, "other": other}

func cleanup(c: Dictionary) -> void:
	c.bm.combat_log.free()
	c.bm.free()

func reacted(c: Dictionary) -> bool:
	return c.mortar.has_move_target or c.mortar.state != Unit.State.ACTIVE

func run() -> void:
	test_a_nearby_drone_does_not_make_an_unspotted_mortar_run()
	test_a_nearby_squad_still_does()
	test_a_drone_alone_sighting_the_mortar_never_sends_it_off_the_map()
	test_a_squad_sighting_it_still_can()
	test_counter_battery_fire_is_a_reason_even_with_only_a_drone_around()
	test_the_friendly_mortar_ignores_an_enemy_drone_the_same_way()
	test_a_nearby_spotter_does_not_make_an_unspotted_mortar_run()
	test_a_spotter_alone_sighting_the_mortar_never_sends_it_off_the_map()
	test_both_a_drone_and_a_spotter_together_are_still_just_unarmed_observers()
	test_a_friendly_mortar_would_ignore_an_enemy_spotter_the_same_way()
	print("Mortar-ignores-drone tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_a_nearby_drone_does_not_make_an_unspotted_mortar_run() -> void:
	for dist in [4.0, 260.0, 700.0]:
		var c := make(Unit.Kind.DRONE, dist, false)
		c.bm._decide_mortar_action(c.mortar)
		check(not reacted(c), "An unspotted mortar ignores a drone %d m away (intent '%s', state %s)" % [dist, c.bm._mortar_move_intent.get(c.mortar, ""), c.mortar.state])
		cleanup(c)


## The exact mirror for a SPOTTER: unseen, it must have no effect at all — "If the enemy has not seen the
## spotter, the spotter should have no effect on their actions."
func test_a_nearby_spotter_does_not_make_an_unspotted_mortar_run() -> void:
	for dist in [4.0, 260.0, 700.0]:
		var c := make(Unit.Kind.SPOTTER, dist, false)
		c.bm._decide_mortar_action(c.mortar)
		check(not reacted(c), "An unspotted mortar ignores a spotter %d m away (intent '%s', state %s)" % [dist, c.bm._mortar_move_intent.get(c.mortar, ""), c.mortar.state])
		cleanup(c)


func test_a_nearby_squad_still_does() -> void:
	var c := make(Unit.Kind.SQUAD, 260.0, false)
	c.bm._decide_mortar_action(c.mortar)
	check(reacted(c), "Control: an unspotted mortar still reacts to a squad 260 m away")
	cleanup(c)


## The last-resort flight itself, from inside the off-map commit distance, where a
## cornered crew would otherwise leave for good.
func test_a_drone_alone_sighting_the_mortar_never_sends_it_off_the_map() -> void:
	var c := make(Unit.Kind.DRONE, 4.0, true)
	c.mortar.global_position.x = c.mortar.retreat_target_x - m(200)
	c.other.global_position = c.mortar.global_position + Vector2(-m(4), 0)
	check(c.bm._mortar_troubled_only_by_unarmed_observers(c.mortar), "Setup: the drone overhead is all that has the crew in sight")
	c.bm._decide_mortar_action(c.mortar)
	check(c.mortar.state == Unit.State.ACTIVE, "Spotted only by a drone, in the flee-commit zone: the crew stays (state %s)" % Unit.State.keys()[c.mortar.state])
	for i in 5:
		c.bm._decide_mortar_action(c.mortar)
	check(c.mortar.state == Unit.State.ACTIVE, "...however many ticks it goes on being watched")
	c.bm._clear_mortar_move(c.mortar) # a hiding place may well have turned up and been walked to
	c.bm._mortar_flee_as_last_resort(c.mortar)
	check(c.mortar.state == Unit.State.ACTIVE and not c.mortar.has_move_target, "...and the last-resort flight itself refuses: the reason it gives is that only a drone sees it")
	cleanup(c)


## The exact mirror for a SPOTTER, seen: "this is good reason for the mortar to take evasive action, but
## not to leave the map."
func test_a_spotter_alone_sighting_the_mortar_never_sends_it_off_the_map() -> void:
	var c := make(Unit.Kind.SPOTTER, 4.0, true)
	c.mortar.global_position.x = c.mortar.retreat_target_x - m(200)
	c.other.global_position = c.mortar.global_position + Vector2(-m(4), 0)
	check(c.bm._mortar_troubled_only_by_unarmed_observers(c.mortar), "Setup: the spotter is all that has the crew in sight")
	c.bm._decide_mortar_action(c.mortar)
	check(c.mortar.state == Unit.State.ACTIVE, "Spotted only by a spotter, in the flee-commit zone: the crew stays (state %s)" % Unit.State.keys()[c.mortar.state])
	for i in 5:
		c.bm._decide_mortar_action(c.mortar)
	check(c.mortar.state == Unit.State.ACTIVE, "...however many ticks it goes on being watched")
	c.bm._clear_mortar_move(c.mortar)
	c.bm._mortar_flee_as_last_resort(c.mortar)
	check(c.mortar.state == Unit.State.ACTIVE and not c.mortar.has_move_target, "...and the last-resort flight itself refuses: the reason it gives is that only an unarmed observer sees it")
	cleanup(c)


## A drone AND a spotter together, nothing else: still just "unarmed observers," not a mix that somehow
## counts as a real ground threat.
func test_both_a_drone_and_a_spotter_together_are_still_just_unarmed_observers() -> void:
	var c := make(Unit.Kind.SPOTTER, 4.0, true)
	var drone: Unit = c.bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, c.mortar.global_position + Vector2(-m(6), 0))
	c.bm.player_units.append(drone)
	drone.is_visible = true
	check(c.bm._mortar_troubled_only_by_unarmed_observers(c.mortar), "A spotter and a drone together are still only unarmed observers")
	cleanup(c)


func test_a_squad_sighting_it_still_can() -> void:
	var c := make(Unit.Kind.SQUAD, 200.0, true)
	check(not c.bm._mortar_troubled_only_by_unarmed_observers(c.mortar), "Setup: a squad watching the crew from 200 m is not 'only a drone'")
	c.mortar.global_position.x = c.mortar.retreat_target_x - m(200)
	c.other.global_position = c.mortar.global_position + Vector2(-m(200), 0)
	c.bm._mortar_flee_as_last_resort(c.mortar)
	check(c.mortar.state != Unit.State.ACTIVE, "A cornered crew watched by a squad still leaves the map (state %s)" % Unit.State.keys()[c.mortar.state])
	cleanup(c)


func test_counter_battery_fire_is_a_reason_even_with_only_a_drone_around() -> void:
	var c := make(Unit.Kind.DRONE, 4.0, true)
	c.mortar.global_position.x = c.mortar.retreat_target_x - m(200)
	c.mortar.evading_counter_battery = true
	c.bm._mortar_flee_as_last_resort(c.mortar)
	check(c.mortar.state != Unit.State.ACTIVE, "Shells landing on the crew are a real reason to leave, whoever directed them")
	cleanup(c)


func test_the_friendly_mortar_ignores_an_enemy_drone_the_same_way() -> void:
	seed(3)
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var mort: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(600, 1270))
	bm.player_units.append(mort)
	var d: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.DRONE, mort.global_position + Vector2(m(260), 0))
	bm.enemy_units.append(d)
	d.is_visible = true
	mort.is_visible = true # the crew is actually seen (by the drone) — otherwise "spotted" never even triggers
	bm._update_player_intel()
	bm._decide_mortar_action(mort)
	check(not (mort.has_move_target or mort.state != Unit.State.ACTIVE), "A friendly mortar does not run from an enemy drone either")
	bm.combat_log.free()
	bm.free()


## "If we ever have a scenario with an enemy spotter, this would apply symmetrically to friendly mortars."
## Nothing in this game currently spawns an ENEMY spotter, but the mechanism itself (opposing = the OTHER
## side's own units, whichever team `m` belongs to) has no player-only assumption baked in — built here
## directly to prove that now, rather than leaving it merely asserted.
func test_a_friendly_mortar_would_ignore_an_enemy_spotter_the_same_way() -> void:
	seed(3)
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var mort: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(600, 1270))
	bm.player_units.append(mort)
	var s: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SPOTTER, mort.global_position + Vector2(m(4), 0))
	bm.enemy_units.append(s)
	s.is_visible = true
	mort.is_visible = true # the crew is actually seen (by the spotter) — otherwise "spotted" never even triggers
	bm._update_player_intel()
	check(bm._mortar_troubled_only_by_unarmed_observers(mort), "Setup: an enemy spotter alone is exactly as 'unarmed observer only' for a friendly mortar as a drone is")
	bm._decide_mortar_action(mort)
	check(not (mort.has_move_target or mort.state != Unit.State.ACTIVE), "A friendly mortar does not run from an enemy spotter either")
	bm.combat_log.free()
	bm.free()
