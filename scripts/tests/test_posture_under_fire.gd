extends SceneTree
## Posture, stages B and C (docs/designs/posture-and-suppression.md): a unit that is standing still goes to ground a reaction time
## after fire arrives, stays down while it lasts and for a while after, and is upright again when it moves. User: "Posture should be
## something that all units have at all times", and "If we add posture, it can't just be under fire. It would have to be throughout the
## game." The first rounds of a barrage catch a unit upright; later ones find it down, protected by about a third (the UK WWII
## figure in the open, a half in cover, on top of the cover's own); a unit on the move is always upright, so it takes about three
## times what a lying one does; a crew serving its gun is upright; a unit that is down and told to move gets up first; a man lying in
## the open is harder to spot; a unit in a building is upright at its post, with the building's protection, until fire gives it a reason.
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

func spot_rate(watcher: Unit, target: Unit, trials: int) -> float:
	var n := 0
	for i in trials:
		if CombatResolver.roll_spot(watcher, target, 1.0):
			n += 1
	return float(n) / float(trials)

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

	# 5. in cover: the building is the protection of a man at his post and he is upright there (not lying on the floor); fire sends him
	# down, and that is worth a further half (not a third: the cover has already done part of it), on top of the building
	var held: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, c.building)
	var foe2: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.building + m(300))
	var at_post: float = CombatResolver.hit_probability(foe2, held)
	var person_at_post: float = CombatResolver.blast_person_chance(held, m(20).length(), held.exposure_terrain())
	check(held.posture() == Unit.Posture.STANDING and is_equal_approx(held.posture_factor(), 1.0), "In a building a squad is upright at its post until fire arrives")
	check(held.exposure_terrain() == GameConfig.TerrainType.BUILDING, "...and has the building's protection")
	bm._note_fire_arrival(held)
	advance(c, GameConfig.GO_TO_GROUND_REACTION_S + 0.5)
	check(held.posture() == Unit.Posture.PRONE and held.posture_factor() > 0.4 and held.posture_factor() < 0.6, "Under fire it goes down on the floor, worth about a half (UK: firing from a trench 1/15-1/50, crouching in it 1/25-1/100)")
	var down_in_cover: float = CombatResolver.hit_probability(foe2, held)
	check(absf(down_in_cover / at_post - held.posture_factor()) < 0.01 and held.posture_factor() < 0.6, "A bullet finds it half as easily, on top of the building (%.4f against %.4f)" % [down_in_cover, at_post])
	var person_down: float = CombatResolver.blast_person_chance(held, m(20).length(), held.exposure_terrain())
	check(absf(person_down / person_at_post - held.posture_factor()) < 0.02 and person_down < 0.6 * person_at_post, "A fragment: half as likely to catch a man down in the building (%.4f against %.4f)" % [person_down, person_at_post])
	# the squad's 0.2 per person is the figure at its post in cover and lying in the open: not three times that in a building
	var open_lying := unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, c.open + m(0, 500))
	open_lying.gone_to_ground = true
	var open_up := unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, c.open + m(0, 1000))
	var open_q_lying: float = CombatResolver.blast_person_chance(open_lying, 0.0, open_lying.exposure_terrain())
	var open_q_up: float = CombatResolver.blast_person_chance(open_up, 0.0, open_up.exposure_terrain())
	check(absf(open_q_up / open_q_lying - 3.0) < 0.05, "In the open a squad on its feet has three times the casualty area of one lying (%.3f against %.3f)" % [open_q_up, open_q_lying])
	# a crew in a building: the building's curve at its post, half of it down
	var building_crew: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.MORTAR, c.building + m(2, 2))
	var crew_post: float = CombatResolver.blast_person_chance(building_crew, m(15).length(), building_crew.exposure_terrain())
	building_crew.gone_to_ground = true
	var crew_floor: float = CombatResolver.blast_person_chance(building_crew, m(15).length(), building_crew.exposure_terrain())
	check(crew_post > 0.0 and absf(crew_floor / crew_post - 0.5) < 0.02, "A crew in cover: half the chance down (%.4f against %.4f)" % [crew_floor, crew_post])

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

	# 8. stage C, concealment: a man lying in the open is half as likely to be noticed from the ground; not in cover (the terrain's own
	# concealment is the effect there), not a spotter (his multiplier is already field craft)
	var c2 := make()
	var watcher: Unit = unit(c2, Unit.Team.ENEMY, Unit.Kind.SQUAD, c2.open)
	var lying_squad: Unit = unit(c2, Unit.Team.PLAYER, Unit.Kind.SQUAD, c2.open + m(120))
	var spotter_lying: Unit = unit(c2, Unit.Team.PLAYER, Unit.Kind.SPOTTER, c2.open + m(0, 120))
	var trials8 := 4000
	seed(5150)
	var up_rate: float = spot_rate(watcher, lying_squad, trials8)
	lying_squad.gone_to_ground = true
	var down_rate: float = spot_rate(watcher, lying_squad, trials8)
	check(up_rate > 0.05 and absf(down_rate / up_rate - GameConfig.LYING_SPOT_MULTIPLIER) < 0.12, "A squad lying in the open is spotted at %.2f of the rate of one upright (%.3f against %.3f)" % [down_rate / maxf(up_rate, 0.0001), down_rate, up_rate])
	var sp_up: float = spot_rate(watcher, spotter_lying, trials8)
	spotter_lying.gone_to_ground = true
	var sp_down: float = spot_rate(watcher, spotter_lying, trials8)
	check(sp_up > 0.02 and absf(sp_down / sp_up - 1.0) < 0.25, "A spotter's own field craft is not counted twice (%.3f against %.3f)" % [sp_down, sp_up])
	cleanup(c2)

	# 9. stage C, getting up: a unit that is down and told to move waits RISE_DELAY_S where it is, and then goes; one at its post goes at once
	var c3 := make()
	var down: Unit = unit(c3, Unit.Team.PLAYER, Unit.Kind.SQUAD, c3.open)
	var post: Unit = unit(c3, Unit.Team.PLAYER, Unit.Kind.SQUAD, c3.open + m(0, 400))
	down.gone_to_ground = true
	for u in [down, post]:
		u.move_target = u.position + m(300)
		u.has_move_target = true
		u.move_speed = 2.0 * GameConfig.PIXELS_PER_METER
	var start_down: Vector2 = down.position
	var start_post: Vector2 = post.position
	c3.bm._tick_movement(0.5)
	check(post.position != start_post and post.activity == Unit.Activity.MOVING, "A squad at its post is under way on the first tick")
	check(down.position == start_down and down.activity == Unit.Activity.STATIONARY and down.gone_to_ground, "A squad that is down has not moved after half a second: it is getting up")
	for i in 2:
		c3.bm._tick_movement(0.5)
	check(down.position == start_down, "...nor after a second and a half")
	for i in 3:
		c3.bm._tick_movement(0.5)
	check(down.position != start_down and not down.gone_to_ground and down.posture() == Unit.Posture.STANDING, "...but is under way once the rise time has passed, and upright")
	cleanup(c3)

	# 10. shooting from prone: a shooter's own posture does not change what he hits (prone is the steadiest position; the cost, a narrower
	# view, has no figure found: see docs/designs/posture-and-suppression.md)
	var c4 := make()
	var lying_shooter: Unit = unit(c4, Unit.Team.ENEMY, Unit.Kind.SQUAD, c4.open)
	var mark: Unit = unit(c4, Unit.Team.PLAYER, Unit.Kind.SQUAD, c4.open + m(250))
	var before_prone: float = CombatResolver.hit_probability(lying_shooter, mark)
	lying_shooter.gone_to_ground = true
	check(is_equal_approx(CombatResolver.hit_probability(lying_shooter, mark), before_prone), "A shooter lying down hits as well as one on his feet")
	cleanup(c4)

	cleanup(c)

	print("Posture under fire tests: %d failures" % failures)
	quit(1 if failures else 0)
