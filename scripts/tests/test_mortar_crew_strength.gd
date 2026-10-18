extends SceneTree
## A mortar crew short of people. User, 2026-10-18, on a mortar still operating with two uninjured people: "Rate of fire -- yes, but the bigger
## issue is movement. They need enough people to carry everything." Walking wounded: "if they are defined as lost to the unit, treat them as not
## participating." The design the user gave:
##  - a hard minimum of TWO to fire the gun at all (the survivor of fewer leaves it);
##  - THREE can move it, at 70% of the pace with 30 rounds aboard, rising in a straight line to the full pace with none; FOUR or more at the full pace;
##  - TWO cannot move it in any combat-effective way: they shoot and hide (down and away from the gun except just after a burst), and if they feel they
##    must leave they fire off every remaining round at the threat and abandon the mortar;
##  - the cycle between bursts and the time to set up or break down the tube go as the crew serving does.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_crew_strength.gd
const TestCombatLogScript := preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(x: float) -> float:
	return x * GameConfig.PIXELS_PER_METER

func near(a: float, b: float, tolerance: float) -> bool:
	return absf(a - b) <= tolerance

func crew(team: Unit.Team, casualties: int, rounds: int = 20) -> Unit:
	var u := Unit.new()
	u.setup(team, Unit.Kind.MORTAR, Vector2(m(-5000), m(-5000)))
	u.crew_casualties = casualties
	u.mortar_rounds_remaining = rounds
	return u

func run() -> void:
	# --- who is serving, and the cycle and set-up time that go with it
	for casualties in [0, 1, 2, 3]:
		var u: Unit = crew(Unit.Team.PLAYER, casualties)
		var serving: int = 4 - casualties
		var expected: float = 30.0 / (float(serving) / 4.0)
		check(u.crew_serving() == serving, "crew of 4 with %d down: %d serving" % [casualties, u.crew_serving()])
		check(near(u.serving_reload_time(), expected, 0.01), "%d serving: the cycle is %.1f s (%.1f)" % [serving, u.serving_reload_time(), expected])
		check(near(u.setup_time(), expected, 0.01), "%d serving: set-up %.1f s (%.1f)" % [serving, u.setup_time(), expected])
		check(u.can_fire_gun() == (serving >= 2), "%d serving: can fire the gun: %s" % [serving, str(u.can_fire_gun())])
		check(u.is_stuck_with_gun() == (serving == 2), "%d serving: stuck with the gun: %s" % [serving, str(u.is_stuck_with_gun())])
		u.free()
	var enemy: Unit = crew(Unit.Team.ENEMY, 2)
	check(near(enemy.serving_reload_time(), 50.0, 0.01) and not enemy.is_stuck_with_gun(), "crew of 5 with 2 down: 3 serving, a 50 s cycle, not stuck")
	enemy.free()
	# walking wounded are casualties: out of the crew like the dead
	var hurt: Unit = crew(Unit.Team.PLAYER, 2)
	hurt.walking_wounded_count = 2
	check(hurt.crew_serving() == 2 and hurt.is_stuck_with_gun(), "two walking wounded leave two serving")
	hurt.free()
	var gone: Unit = crew(Unit.Team.PLAYER, 2)
	gone.mortar_gun_abandoned = true
	check(not gone.is_stuck_with_gun() and gone.load_speed_factor() == 1.0, "a crew that has left the gun is not stuck with it and walks free")
	gone.free()
	var squad := Unit.new()
	squad.setup(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(m(-5000), m(-5000)))
	check(squad.can_fire_gun() and not squad.is_stuck_with_gun() and squad.load_speed_factor() == 1.0 and squad.crew_strength() == 1.0, "only a mortar crew has any of this")
	squad.free()

	# --- the pace
	for rounds in [0, 15, 20, 30, 40]:
		var four: Unit = crew(Unit.Team.PLAYER, 0, rounds)
		check(four.load_speed_factor() == 1.0, "a full crew of four with %d rounds moves at its usual pace" % rounds)
		four.free()
	var five_less_one: Unit = crew(Unit.Team.ENEMY, 1, 30)
	check(five_less_one.load_speed_factor() == 1.0, "a crew of five with one lost (four serving) moves at its usual pace")
	five_less_one.free()
	var expected_three := {0: 1.0, 15: 0.85, 20: 0.8, 30: 0.7, 40: 0.7}
	for rounds in expected_three:
		var three: Unit = crew(Unit.Team.PLAYER, 1, rounds)
		check(near(three.load_speed_factor(), expected_three[rounds], 0.001), "three serving with %d rounds: %.3f of the pace (%.3f)" % [rounds, three.load_speed_factor(), expected_three[rounds]])
		three.free()
	var two: Unit = crew(Unit.Team.PLAYER, 2, 0)
	check(two.load_speed_factor() == 0.0, "two serving do not move the gun, whatever they carry")
	two.free()

	# --- in a battle
	GameConfig.set_active_map("voznesensk")
	GameConfig._build_terrain_grid()
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = TestCombatLogScript.new()
	bm.scenario_elapsed_time = 1000.0
	var spot := Vector2(m(-5000), m(-5000))

	# moving: three can be sent, two cannot
	for casualties in [1, 2]:
		var gun: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, spot)
		bm.player_units.append(gun)
		gun.crew_casualties = casualties
		bm._issue_mortar_move(gun, spot + Vector2(m(300), 0), GameConfig.MORTAR_RELOCATE_SPEED, "conceal")
		check(gun.has_move_target == (casualties == 1), "(%d serving) a move order %s" % [4 - casualties, "is taken" if casualties == 1 else "is not taken"])
		check(bm._relocate_mortar(gun, "evade") == false or casualties == 1, "(2 serving) the relocation search finds nowhere to go: they cannot move the gun")
		bm._queue_mortar_displacement(gun, "scoot", false)
		check(bm._pending_mortar_displacement.has(gun) == (casualties == 1), "(%d serving) a scoot after firing %s" % [4 - casualties, "is queued" if casualties == 1 else "is not"])
		bm._pending_mortar_displacement.erase(gun)
		bm.player_units.erase(gun)

	# the pace on the ground: ten seconds at 2.2 m/s
	for case in [{"down": 0, "rounds": 20, "walk": 22.0}, {"down": 1, "rounds": 30, "walk": 15.4}, {"down": 1, "rounds": 0, "walk": 22.0}]:
		var gun: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, spot)
		bm.player_units.append(gun)
		gun.crew_casualties = case.down
		gun.mortar_rounds_remaining = case.rounds
		gun.move_target = spot + Vector2(m(300), 0)
		gun.has_move_target = true
		gun.move_speed = GameConfig.MORTAR_RELOCATE_SPEED
		bm._step_toward_target(gun, 10.0)
		var walked: float = gun.global_position.distance_to(spot) / GameConfig.PIXELS_PER_METER
		check(near(walked, case.walk, 0.05), "(%d down, %d rounds) walks %.1f m in ten seconds (%.1f)" % [case.down, case.rounds, walked, case.walk])
		bm.player_units.erase(gun)

	# firing: fewer than two cannot; two can, on the longer cycle
	for casualties in [0, 2, 3]:
		var gun: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, spot)
		bm.player_units.append(gun)
		gun.crew_casualties = casualties
		var foe: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, spot + Vector2(m(1500), 0))
		bm.enemy_units.append(foe)
		foe.is_visible = true
		var fired := false
		for attempt in 60:
			gun.fire_timer = 0.0
			gun.mortar_rounds_remaining = 20
			bm._mortar_tick_shot.clear()
			bm._tick_fire(gun, 0.5, 0.5, bm.enemy_units)
			if gun.mortar_rounds_remaining < 20:
				fired = true
				break
		check(fired == (casualties < 3), "(%d serving) the gun %s" % [4 - casualties, "fires" if casualties < 3 else "does not fire"])
		if fired:
			var cycle: float = 30.0 / (float(4 - casualties) / 4.0)
			check(near(gun.fire_timer, cycle, 0.01), "(%d serving) the next burst is %.0f s away (%.1f)" % [4 - casualties, cycle, gun.fire_timer])
		bm.player_units.erase(gun)
		bm.enemy_units.erase(foe)

	# a compromised position does not stop a crew that cannot move from firing
	for casualties in [1, 2]:
		var gun: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, spot)
		bm.player_units.append(gun)
		gun.crew_casualties = casualties
		var foe: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, spot + Vector2(m(1500), 0))
		var rival: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, spot + Vector2(m(2500), 0))
		bm.enemy_units.append(foe)
		bm.enemy_units.append(rival)
		foe.is_visible = true
		bm._last_detected_mortar_fire[gun] = {"position": spot, "time": bm.scenario_elapsed_time}
		var owed: bool = bm._mortar_should_relocate_for_safety(gun)
		var shot := false
		for attempt in 40:
			bm._mortar_tick_shot.clear()
			if bm._mortar_shot_this_tick(gun, bm.enemy_units) != null:
				shot = true
				break
		check(owed, "(%d serving) the scene has the position compromised (a detected shot and an enemy mortar in reach)" % (4 - casualties))
		if owed:
			check(shot == (casualties == 2), "(%d serving) with the position compromised, the crew %s" % [4 - casualties, "still looks for a shot" if casualties == 2 else "stops trading shots to relocate"])
		bm._last_detected_mortar_fire.erase(gun)
		bm.player_units.erase(gun)
		bm.enemy_units.erase(foe)
		bm.enemy_units.erase(rival)

	# shoot and hide: two serving are down between bursts, away from the gun; three are not
	for casualties in [1, 2]:
		var gun: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, spot)
		bm.player_units.append(gun)
		gun.crew_casualties = casualties
		gun.last_round_fired_at = bm.scenario_elapsed_time - 5.0
		bm._update_postures()
		check(not gun.gone_to_ground, "(%d serving) 5 s after a burst the crew is at the gun" % (4 - casualties))
		gun.last_round_fired_at = bm.scenario_elapsed_time - 20.0
		bm._update_postures()
		check(gun.gone_to_ground == (casualties == 2), "(%d serving) 20 s after a burst the crew is %s" % [4 - casualties, "down, hiding" if casualties == 2 else "still up"])
		bm.player_units.erase(gun)

	# the last stand: every round at the threat (a mortar before a squad), then the gun is left
	var gun: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, spot)
	bm.player_units.append(gun)
	gun.crew_casualties = 2
	gun.mortar_rounds_remaining = 17
	var squad_foe: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, spot + Vector2(m(900), 0))
	var rival_gun: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, spot + Vector2(m(3000), 0))
	bm.enemy_units.append(squad_foe)
	bm.enemy_units.append(rival_gun)
	squad_foe.is_visible = true
	rival_gun.is_visible = true
	bm._pending_mortar_shots.clear()
	bm._mortar_flee_as_last_resort(gun)
	var at_rival := 0
	var at_squad := 0
	for s in bm._pending_mortar_shots:
		if s.mortar == gun and s.target == rival_gun:
			at_rival += 1
		elif s.mortar == gun and s.target == squad_foe:
			at_squad += 1
	check(at_rival == 17 and at_squad == 0, "the last stand fires all 17 rounds at the enemy mortar in reach (%d at it, %d at the squad)" % [at_rival, at_squad])
	check(gun.mortar_rounds_remaining == 0, "...and nothing is left")
	check(gun.state == Unit.State.RETREATING and gun.mortar_gun_abandoned, "...and the crew leaves the gun")
	bm.player_units.erase(gun)

	# with only a squad in reach, it is the squad; with nothing in reach, the crew simply leaves
	bm.enemy_units.erase(rival_gun)
	var gun2: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, spot)
	bm.player_units.append(gun2)
	gun2.crew_casualties = 2
	gun2.mortar_rounds_remaining = 9
	bm._pending_mortar_shots.clear()
	bm._stuck_crew_last_stand(gun2)
	var at_squad2 := 0
	for s in bm._pending_mortar_shots:
		if s.mortar == gun2 and s.target == squad_foe:
			at_squad2 += 1
	check(at_squad2 == 9 and gun2.state == Unit.State.RETREATING, "with only a squad in reach the 9 rounds go at it, and the crew leaves (%d)" % at_squad2)
	bm.player_units.erase(gun2)
	bm.enemy_units.erase(squad_foe)
	var gun3: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, spot)
	bm.player_units.append(gun3)
	gun3.crew_casualties = 2
	gun3.mortar_rounds_remaining = 9
	bm._pending_mortar_shots.clear()
	bm._stuck_crew_last_stand(gun3)
	check(bm._pending_mortar_shots.is_empty() and gun3.state == Unit.State.RETREATING and gun3.mortar_gun_abandoned, "with nothing in reach the crew leaves without firing")
	bm.player_units.erase(gun3)

	# fewer than two left: the survivor leaves the gun; an order to fall back from a crew of two: it leaves the mortar
	var stayed := 0
	for trial in 60:
		var gun4: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, spot)
		bm.player_units.append(gun4)
		gun4.mortar_rounds_remaining = 0
		gun4.take_hit(true, [], [], 0.0, 3)
		if not (gun4.crew_serving() == 1 and gun4.state == Unit.State.RETREATING and gun4.mortar_gun_abandoned):
			stayed += 1
		bm.player_units.erase(gun4)
	check(stayed == 0, "one left: the survivor leaves the gun every time (it stayed %d of 60)" % stayed)
	var gun5: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, spot)
	bm.player_units.append(gun5)
	gun5.crew_casualties = 2
	bm._issue_fall_back_move(gun5, spot + Vector2(m(300), 0))
	check(gun5.state == Unit.State.RETREATING and gun5.mortar_gun_abandoned, "ordered to fall back, two left leave the mortar")
	bm.player_units.erase(gun5)
	var gun6: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, spot)
	bm.player_units.append(gun6)
	gun6.crew_casualties = 1
	bm._issue_fall_back_move(gun6, spot + Vector2(m(300), 0))
	check(gun6.state == Unit.State.ACTIVE and gun6.has_move_target, "ordered to fall back, three serving carry the mortar with them")
	bm.player_units.erase(gun6)

	print("Mortar crew strength tests: %d failures" % failures)
	quit(1 if failures else 0)
