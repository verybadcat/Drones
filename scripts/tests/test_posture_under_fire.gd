extends SceneTree
## Posture, stage B (docs/designs/posture-and-suppression.md): a unit that is standing still in the open goes to ground a reaction time
## after fire arrives, stays down while it lasts and for a while after, and is upright again when it moves. User: "Posture should be
## something that all units have at all times", and "If we add posture, it can't just be under fire. It would have to be throughout the
## game." The first rounds of a barrage catch a unit upright; later ones find it down, protected by about a third (the UK WWII
## figure); a unit on the move is always upright, so it takes about three times what a lying one does; a crew serving its gun is
## upright; cover is as before.
##
## Run: godot --headless --path . --script scripts/tests/test_posture_under_fire.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(x: float, y: float = 0.0) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

func make() -> Dictionary:
	GameConfig.set_active_map("voznesensk")
	GameConfig._build_terrain_grid()
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.scenario_elapsed_time = 1000.0
	return {"bm": bm, "open": m(-5000, -5000), "building": GameConfig._building_rects[0].get_center()}

func unit(c: Dictionary, team: Unit.Team, kind: Unit.Kind, point: Vector2) -> Unit:
	var u: Unit = c.bm._make_unit(team, kind, point)
	if team == Unit.Team.PLAYER:
		c.bm.player_units.append(u)
	else:
		c.bm.enemy_units.append(u)
	return u

func advance(c: Dictionary, seconds: float) -> void:
	c.bm.scenario_elapsed_time += seconds
	c.bm._update_postures()

func cleanup(c: Dictionary) -> void:
	c.bm.combat_log.free()
	c.bm.free()

func run() -> void:
	var c := make()
	var bm: BattleManager = c.bm
	check(GameConfig.get_terrain_type_at(c.open) == GameConfig.TerrainType.OPEN, "Setup: open ground")
	check(GameConfig.get_terrain_type_at(c.building) == GameConfig.TerrainType.BUILDING, "Setup: a building")
	var down_factor: float = GameConfig.PRONE_IN_OPEN_FACTOR
	check(down_factor > 0.2 and down_factor < 0.5, "Setup: lying is about a third of standing (%.2f)" % down_factor)

	# 1. the timeline of one squad standing in the open: upright, fire arrives, upright for the reaction time, then down
	var squad: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, c.open)
	var foe: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.open + m(300))
	check(squad.posture() == Unit.Posture.STANDING, "A squad standing in the open is upright")
	var p_up: float = CombatResolver.hit_probability(foe, squad)
	var q_up: float = CombatResolver.blast_person_chance(squad, m(10).length(), squad.exposure_terrain())
	bm._note_fire_arrival(squad)
	advance(c, 1.0)
	check(squad.posture() == Unit.Posture.STANDING, "One second after fire arrives it is still upright")
	advance(c, GameConfig.GO_TO_GROUND_REACTION_S)
	check(squad.posture() == Unit.Posture.PRONE, "Past the reaction time it is down")
	var p_down: float = CombatResolver.hit_probability(foe, squad)
	var q_down: float = CombatResolver.blast_person_chance(squad, m(10).length(), squad.exposure_terrain())
	check(absf(p_down / p_up - down_factor) < 0.01, "A bullet finds it %.2f as easily as before (%.4f against %.4f)" % [p_down / p_up, p_down, p_up])
	check(absf(q_up / q_down - 1.0 / down_factor) < 0.05, "A fragment: three times as likely to catch a man on his feet as a lying one (%.3f against %.3f)" % [q_up, q_down])

	# 2. it stays down while fire keeps arriving, and for the stay-down time after the last; then it rises; new fire starts it over
	for i in 3:
		advance(c, 20.0)
		bm._note_fire_arrival(squad)
		check(squad.posture() == Unit.Posture.PRONE, "It stays down while the fire goes on (%d)" % i)
	advance(c, GameConfig.STAY_DOWN_AFTER_FIRE_S - 1.0)
	check(squad.posture() == Unit.Posture.PRONE, "...and just under the stay-down time after the last round")
	advance(c, 2.0)
	check(squad.posture() == Unit.Posture.STANDING, "...then it is upright again")
	bm._note_fire_arrival(squad)
	advance(c, 1.0)
	check(squad.posture() == Unit.Posture.STANDING, "A fresh round catches it upright and it takes the reaction time again")
	advance(c, GameConfig.GO_TO_GROUND_REACTION_S)
	check(squad.posture() == Unit.Posture.PRONE, "...and goes down again")

	# 3. moving is standing, at once; stopping again does not put it back down: it must react again
	squad.activity = Unit.Activity.MOVING
	check(squad.posture() == Unit.Posture.STANDING, "A squad that gets up and moves is upright at once")
	advance(c, 1.0)
	squad.activity = Unit.Activity.STATIONARY
	check(squad.posture() == Unit.Posture.STANDING, "...and when it stops it is upright, not still down from before")
	check(not squad.gone_to_ground, "...with nothing stored to put it back down")

	# 4. a crew serving its gun stays on its feet under fire; one that has not fired for a cycle goes down
	var crew: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.MORTAR, c.open + m(0, 60))
	crew.last_round_fired_at = bm.scenario_elapsed_time
	bm._note_fire_arrival(crew)
	advance(c, GameConfig.GO_TO_GROUND_REACTION_S + 2.0)
	check(crew.posture() == Unit.Posture.STANDING, "A crew that has just fired is on its feet at the tube")
	bm._note_fire_arrival(crew)
	advance(c, crew.reload_time + 1.0)
	bm._note_fire_arrival(crew)
	advance(c, 0.5)
	check(crew.posture() == Unit.Posture.PRONE, "...and one that has not fired for a whole cycle goes down under fire")
	# the crew's own casualty rolls: a crew down takes a third of what one on its feet does
	var crew_down: float = CombatResolver.blast_person_chance(crew, m(20).length(), crew.exposure_terrain())
	crew.last_round_fired_at = bm.scenario_elapsed_time
	advance(c, 0.1)
	var crew_up: float = CombatResolver.blast_person_chance(crew, m(20).length(), crew.exposure_terrain())
	check(crew_up > 0.0 and absf(crew_down / crew_up - down_factor) < 0.02, "A crew down takes %.2f of the chance of one on its feet (%.3f against %.3f)" % [crew_down / maxf(crew_up, 0.0001), crew_down, crew_up])

	# 5. in cover nothing changes: it is down behind the cover from the start, and the factor is not applied twice
	var held: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, c.building)
	var foe2: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.building + m(300))
	var in_cover_before: float = CombatResolver.hit_probability(foe2, held)
	bm._note_fire_arrival(held)
	advance(c, 10.0)
	check(held.posture() == Unit.Posture.PRONE and is_equal_approx(held.posture_factor(), 1.0), "In a building it is down, and the lying factor is not added to the building's own")
	check(is_equal_approx(CombatResolver.hit_probability(foe2, held), in_cover_before), "...so the building's protection is exactly as it was under fire")

	# 6. the real paths record fire: a direct volley (whoever it is aimed at) and a round landing within 60 m, any ground unit
	var target: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, c.open + m(2000, 0))
	var shooter: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.open + m(2200, 0))
	var before: float = target.fire_arrived_at
	bm._resolve_fire_and_check_bunching(shooter, target, target.global_position)
	check(target.fire_arrived_at == bm.scenario_elapsed_time and before < target.fire_arrived_at, "A volley aimed at a squad records that fire arrived")
	var spotter: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SPOTTER, c.open + m(4000, 0))
	var far_spotter: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SPOTTER, c.open + m(4000, 150))
	var team_crew: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, c.open + m(4030, 0))
	bm._suppress_from_blast(c.open + m(4000, 20))
	check(spotter.fire_arrived_at == bm.scenario_elapsed_time, "A round landing 20 m from a spotter: fire arrived")
	check(team_crew.fire_arrived_at == bm.scenario_elapsed_time, "...and for a drone team 30 m off")
	check(far_spotter.fire_arrived_at < 0.0, "...but not for one 130 m away")
	advance(c, GameConfig.GO_TO_GROUND_REACTION_S + 0.5)
	check(spotter.posture() == Unit.Posture.PRONE and team_crew.posture() == Unit.Posture.PRONE, "...and both are down a moment later")
	check(far_spotter.posture() == Unit.Posture.STANDING, "...the far one is not")

	# 7. what it does to a real round: casualties on nine men caught upright against the same round after they have gone down
	var trials := 400
	var up_total := 0
	var down_total := 0
	for i in trials:
		var u: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, c.open + m(-300, 0))
		bm._apply_shell_blast(u.global_position + m(6, 0), null)
		up_total += u.max_pips - u.pips
		u.pips = u.max_pips
		u.state = Unit.State.ACTIVE
		u.gone_to_ground = true
		bm._apply_shell_blast(u.global_position + m(6, 0), null)
		down_total += u.max_pips - u.pips
		bm.player_units.erase(u)
		u.free()
	var ratio: float = float(up_total) / maxf(float(down_total), 1.0)
	check(ratio > 2.4 and ratio < 3.8 and down_total > 0, "A round on men caught upright costs about three times what it does once they are down (%d against %d casualties in %d rounds, ratio %.2f)" % [up_total, down_total, trials, ratio])
	cleanup(c)

	print("Posture under fire tests: %d failures" % failures)
	quit(1 if failures else 0)
