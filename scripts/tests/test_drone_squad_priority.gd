extends SceneTree
## Direct user report: "Right now, the drone is making a curious choice. As far as we know, there are
## no remaining enemy mortars. All enemy squads are advancing towards our positions. The drone is
## tracking a far off one rather than some of the near ones. As a general matter, enemy squads that
## are threatening the mortar would have higher priority than ones that are not. If nothing is
## threatening the mortar, next would be enemy squads that are approaching our squads."
##
## The live snapshot showed the cause of the lock-on: the drone was hovering over the squad it tracked
## and counted as a friendly unit, so that squad read as in contact (danger 10/10) however far it was
## from our positions. Drones no longer count as the force a squad threatens, and the squad to track
## is chosen by class: threatening the mortar, then approaching our squads, then the rest.
##
## Run: godot --headless --path . --script scripts/tests/test_drone_squad_priority.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
const TIER := "Tracking dangerous squad"
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(x: float, y: float) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

## Two friendly squads, a friendly mortar behind them, the drone team and an airborne drone at `drone_m`.
func make_battle(drone_m: Vector2, with_mortar: bool = true):
	var w := Weather.new()
	w.wind_speed_10m = 0.0
	w.temperature_c = 10.0
	w._gust_z = 0.0
	w.rng.seed = 1
	Weather.current = w
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.weather = w
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	for p in [Vector2(1400, 1800), Vector2(1400, 1300)]:
		bm.player_units.append(bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(p.x, p.y)))
	if with_mortar:
		bm.player_units.append(bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(700, 1900)))
	bm.drone_team = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, m(-800, 1500))
	bm.player_units.append(bm.drone_team)
	var d: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, m(drone_m.x, drone_m.y))
	bm.player_units.append(d)
	d.move_speed = GameConfig.DRONE_CRUISE_SPEED
	d.drone_battery_charge = 0.9
	bm.active_drone = d
	return bm

## A visible enemy squad at `pos_m`, advancing toward `toward_m` (or standing still when null).
func add_enemy(bm, pos_m: Vector2, toward_m = null) -> Unit:
	var s: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(pos_m.x, pos_m.y))
	bm.enemy_units.append(s)
	s.is_visible = true
	s.player_has_been_sighted = true
	s.player_known_position = s.global_position
	s.player_known_state = Unit.State.ACTIVE
	if toward_m != null:
		s.move_target = m(toward_m.x, toward_m.y)
		s.has_move_target = true
		s.move_speed = GameConfig.ENEMY_ADVANCE_SPEED
	return s

func picked(bm) -> Vector2:
	return bm._drone_search_target()

func cleanup(bm) -> void:
	bm.combat_log.free()
	bm.free()

func run() -> void:
	test_the_live_case_near_squads_beat_the_far_one_under_the_drone()
	test_squads_threatening_the_mortar_come_first()
	test_approaching_our_squads_beats_merely_being_near()
	test_a_threat_to_the_drone_team_counts_like_one_to_a_squad()
	test_the_spotter_barely_matters()
	test_the_drone_goes_to_where_a_lost_squad_was()
	test_a_lost_squad_is_not_chased_again_once_the_drone_has_looked()
	test_which_lost_squad_and_the_battery()
	test_a_suspected_mortar_does_not_send_the_drone_away_from_the_lost_squad()
	test_the_drone_watches_a_force_it_can_see()
	print("Drone squad priority tests: %d failures" % failures)
	quit(1 if failures else 0)


## No enemy mortar; every enemy squad advancing on our positions; the drone hovering over a far one.
func test_the_live_case_near_squads_beat_the_far_one_under_the_drone() -> void:
	var bm = make_battle(Vector2(3700, 1870), false)
	var far := add_enemy(bm, Vector2(3700, 1870), Vector2(1400, 1800)) # far off, drone right on top of it
	var near_a := add_enemy(bm, Vector2(2100, 1700), Vector2(1400, 1800))
	var near_b := add_enemy(bm, Vector2(2500, 1400), Vector2(1400, 1300))
	var target: Vector2 = picked(bm)
	check(bm._drone_pilot_reasoning.get("tier", "") == TIER, "Set-up: it is tracking a squad (%s)" % str(bm._drone_pilot_reasoning.get("tier", "")))
	check(target.distance_to(near_a.global_position) < 1.0, "It tracks the nearest advancing squad, not the far one under it (target %s, near %s, far %s)" % [target / GameConfig.PIXELS_PER_METER, near_a.global_position / GameConfig.PIXELS_PER_METER, far.global_position / GameConfig.PIXELS_PER_METER])
	# The drone's own position does not make a squad dangerous.
	check(bm._squad_danger_priority(far) < 1.0, "A far squad with the drone hovering over it is not 'in contact' (danger %.1f)" % bm._squad_danger_priority(far))
	cleanup(bm)


func test_squads_threatening_the_mortar_come_first() -> void:
	# A squad 700 m from the mortar and closing on it, against a squad closer to our squads.
	var bm = make_battle(Vector2(2000, 1000))
	var near_squads := add_enemy(bm, Vector2(1900, 1750), Vector2(1400, 1800)) # 500 m from our squad, approaching it
	var at_mortar := add_enemy(bm, Vector2(1300, 2300), Vector2(700, 1900)) # ~700 m from the mortar, closing on it
	var target: Vector2 = picked(bm)
	check(target.distance_to(at_mortar.global_position) < 1.0, "The squad threatening the mortar is tracked over one nearer our squads (%s)" % str(bm._drone_pilot_reasoning))
	check("mortar" in str(bm._drone_pilot_reasoning.get("detail", "")), "...and the reasoning says so (%s)" % str(bm._drone_pilot_reasoning.get("detail", "")))
	# The same squad moving AWAY from the mortar is not a threat to it.
	at_mortar.move_target = m(2400, 2600)
	target = picked(bm)
	check(target.distance_to(near_squads.global_position) < 1.0, "Moving away from the mortar it no longer outranks the squad approaching ours (%s)" % str(bm._drone_pilot_reasoning))
	# Out of range of the mortar altogether: not a threat to it either.
	at_mortar.global_position = m(3200, 2300)
	at_mortar.move_target = m(700, 1900)
	target = picked(bm)
	check(target.distance_to(near_squads.global_position) < 1.0, "A squad far from the mortar is not a threat to it, however it is heading")
	cleanup(bm)


## With nothing threatening the mortar: a squad approaching our squads over one that is only near.
func test_approaching_our_squads_beats_merely_being_near() -> void:
	var bm = make_battle(Vector2(2500, 1000), false)
	var loiterer := add_enemy(bm, Vector2(1400, 2400)) # 600 m from a friendly squad (over the 400 m engagement range), standing still
	var approaching := add_enemy(bm, Vector2(2400, 1700), Vector2(1400, 1800)) # 1000 m out, coming on
	check(bm._squad_danger_priority(loiterer) > bm._squad_danger_priority(approaching), "Set-up: the loiterer is the nearer to our forces")
	var target: Vector2 = picked(bm)
	check(target.distance_to(approaching.global_position) < 1.0, "The squad approaching ours is tracked over one that is merely nearer (%s)" % str(bm._drone_pilot_reasoning))
	cleanup(bm)


## "The drone should never count as one of our units for purposes of deciding what is threatening. A
## threat to the drone team would however count. It would be similar to a threat to a squad."
func test_a_threat_to_the_drone_team_counts_like_one_to_a_squad() -> void:
	var bm = make_battle(Vector2(2500, 300), false)
	# Our squads far from the action; the drone team out in front at (900, 500).
	bm.drone_team.global_position = m(900, 500)
	var near_team := add_enemy(bm, Vector2(1400, 600), Vector2(900, 500)) # 500 m from the drone team, coming at it
	var loiterer := add_enemy(bm, Vector2(3600, 1500)) # far from everything, standing still
	var target: Vector2 = picked(bm)
	check(target.distance_to(near_team.global_position) < 1.0, "A squad approaching the drone team is tracked (%s)" % str(bm._drone_pilot_reasoning))
	check("drone team" in str(bm._drone_pilot_reasoning.get("detail", "")), "...and the reasoning names the drone team")
	# The airborne drone, though, is never the thing being threatened: hovering over a squad or beside one
	# it neither raises the danger nor makes a squad 'approaching our squads'.
	var bm2 = make_battle(Vector2(3600, 1500), false)
	bm2.drone_team.global_position = m(-800, 1500)
	var under_drone := add_enemy(bm2, Vector2(3600, 1500), Vector2(3600, 1400)) # advancing, but nowhere near our squads or the team
	check(bm2._drone_squad_to_track().get("score", 99.0) < 1.0, "A squad under the airborne drone is not dangerous for it (score %.1f)" % bm2._drone_squad_to_track().get("score", 99.0))
	check(not ("approaching" in str(bm2._drone_squad_to_track().get("why", ""))), "...and is not 'approaching our squads' because of the drone")
	cleanup(bm)
	cleanup(bm2)


## "The spotter should have only a very minor affect on what to track." A squad next to the spotter is
## a little more dangerous than one far from everything, but far less than one the same distance from a squad.
func test_the_spotter_barely_matters() -> void:
	var bm = make_battle(Vector2(2500, 300), false)
	var spotter: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, m(300, 300))
	bm.player_units.append(spotter)
	var by_spotter := add_enemy(bm, Vector2(400, 300)) # 100 m from the spotter only
	var by_squad := add_enemy(bm, Vector2(1500, 1800)) # 100 m from a friendly squad
	var far := add_enemy(bm, Vector2(3800, 300)) # far from everything
	var d_spotter: float = bm._squad_danger_priority(by_spotter)
	var d_squad: float = bm._squad_danger_priority(by_squad)
	var d_far: float = bm._squad_danger_priority(far)
	check(d_spotter > d_far, "A squad by the spotter is still a touch more dangerous than one far from everything (%.1f vs %.1f)" % [d_spotter, d_far])
	check(d_spotter < d_squad * 0.3, "...but under a third as much as one the same distance from a squad (%.1f vs %.1f)" % [d_spotter, d_squad])
	cleanup(bm)


## Direct user report: "We know the area the enemy is in. The drone is not going there. That's wrong."
## The live snapshot: an enemy squad last seen 271 s ago at (2787, 624), not in sight, the drone at
## (3033, 1910) on "routine background recon" toward a flank gap at (1340, 2571).
func test_the_drone_goes_to_where_a_lost_squad_was() -> void:
	var bm = make_battle(Vector2(3033, 1910), false)
	bm.scenario_elapsed_time = 2000.0
	var lost := add_enemy(bm, Vector2(2419, 530)) # where it really is (not known to the player)
	lost.is_visible = false
	lost.player_known_position = m(2787, 624)
	lost.player_known_position_time = bm.scenario_elapsed_time - 271.0
	var target: Vector2 = picked(bm)
	check(bm._drone_pilot_reasoning.get("tier", "") == "Regaining contact with a lost squad", "The drone goes to look for the squad it lost (%s)" % str(bm._drone_pilot_reasoning))
	check(target.distance_to(m(2787, 624)) < 1.0, "...at where it was last seen, not the truth it cannot know (target %s)" % (target / GameConfig.PIXELS_PER_METER))
	# A sighting that has gone stale is not worth the trip.
	# "Too old" is when the squad could be in a different part of the map: a third of the map's width at
	# the enemy's advance pace (about 20 minutes here), not a fixed number of seconds.
	var expiry: float = bm._lost_contact_expiry_s()
	var reach_m: float = expiry * GameConfig.ENEMY_ADVANCE_SPEED / GameConfig.PIXELS_PER_METER
	check(is_equal_approx(reach_m, GameConfig.MAP_WIDTH_M / 3.0), "The expiry is the time to cross a third of the map at the advance pace (%.0f s, %.0f m)" % [expiry, reach_m])
	check(expiry > 600.0 and expiry < 2400.0, "...which is a sensible number of minutes (%.0f s)" % expiry)
	lost.player_known_position_time = bm.scenario_elapsed_time - expiry + 60.0
	picked(bm)
	check(bm._drone_pilot_reasoning.get("tier", "") == "Regaining contact with a lost squad", "A sighting just inside that is still chased (%s)" % str(bm._drone_pilot_reasoning))
	lost.player_known_position_time = bm.scenario_elapsed_time - expiry - 10.0
	picked(bm)
	check(bm._drone_pilot_reasoning.get("tier", "") != "Regaining contact with a lost squad", "A sighting older than that is not chased: the squad could be anywhere by now (%s)" % str(bm._drone_pilot_reasoning.get("tier", "")))
	lost.player_known_position_time = bm.scenario_elapsed_time - 271.0
	# Something the player believes destroyed or gone is not.
	lost.player_known_state = Unit.State.DESTROYED
	picked(bm)
	check(bm._drone_pilot_reasoning.get("tier", "") != "Regaining contact with a lost squad", "A squad known to be out of the fight is not chased")
	lost.player_known_state = Unit.State.ACTIVE
	# A squad in sight is tracked as before, over a lost one.
	var seen := add_enemy(bm, Vector2(2000, 1700), Vector2(1400, 1800))
	picked(bm)
	check(bm._drone_pilot_reasoning.get("tier", "") == "Tracking dangerous squad", "A squad in sight outranks one that was lost (%s)" % str(bm._drone_pilot_reasoning.get("tier", "")))
	cleanup(bm)


## Once the drone has been there and found nothing, it does not stay.
func test_a_lost_squad_is_not_chased_again_once_the_drone_has_looked() -> void:
	var bm = make_battle(Vector2(2787, 700), false) # the drone is already at the last known position
	bm.scenario_elapsed_time = 2000.0
	var lost := add_enemy(bm, Vector2(2419, 530))
	lost.is_visible = false
	lost.player_known_position = m(2787, 624)
	lost.player_known_position_time = bm.scenario_elapsed_time - 100.0
	picked(bm)
	check(bm._drone_pilot_reasoning.get("tier", "") != "Regaining contact with a lost squad", "Having reached the spot and found nothing, the drone moves on (%s)" % str(bm._drone_pilot_reasoning.get("tier", "")))
	check(bm._lost_contact_checked.has(lost), "...and the squad is marked as checked")
	# It is chased again after the recheck time, or as soon as it is seen and lost again.
	bm.scenario_elapsed_time += BattleManager.LOST_CONTACT_RECHECK_S + 1.0
	bm.active_drone.global_position = m(3033, 1910)
	lost.player_known_position_time = bm.scenario_elapsed_time - 100.0
	picked(bm)
	check(bm._drone_pilot_reasoning.get("tier", "") == "Regaining contact with a lost squad", "After the recheck time it is worth another look")
	cleanup(bm)


## Of several lost squads, the one nearest our forces first; the battery must afford the trip.
func test_which_lost_squad_and_the_battery() -> void:
	var bm = make_battle(Vector2(3500, 1000), false)
	bm.scenario_elapsed_time = 2000.0
	var far := add_enemy(bm, Vector2(4600, 700))
	far.is_visible = false
	far.player_known_position = m(4600, 700)
	far.player_known_position_time = bm.scenario_elapsed_time - 60.0 # fresher, but far from us
	var near := add_enemy(bm, Vector2(2200, 1500))
	near.is_visible = false
	near.player_known_position = m(2200, 1500)
	near.player_known_position_time = bm.scenario_elapsed_time - 500.0 # older, but near our squads
	var target: Vector2 = picked(bm)
	check(target.distance_to(m(2200, 1500)) < 1.0, "Of two lost squads, the one nearer our forces is gone to first (%s)" % (target / GameConfig.PIXELS_PER_METER))
	bm.active_drone.drone_battery_charge = 0.02
	picked(bm)
	check(bm._drone_pilot_reasoning.get("tier", "") != "Regaining contact with a lost squad", "A drone that cannot afford the trip does not go")
	cleanup(bm)


## The live battle had a suspected mortar (mortar-existence confidence 0.48), which makes routine recon
## worth far more than any squad tier (its score is 100 x the confidence): the drone took a flank gap
## 1800 m away instead of the area a squad was last seen in. The lost squad's area is now one of the
## routine search's own candidates, so it is still what the drone goes to.
func test_a_suspected_mortar_does_not_send_the_drone_away_from_the_lost_squad() -> void:
	var bm = make_battle(Vector2(3033, 1910), true)
	bm.scenario_elapsed_time = 2000.0
	var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4800, 1000))
	bm.enemy_units.append(em)
	em.is_visible = false
	bm._last_detected_mortar_fire[em] = {"position": m(4859, 1017), "time": bm.scenario_elapsed_time - 700.0} # too old for the fresh-lead tier
	check(bm._mortar_existence_confidence() > 0.3, "Set-up: a mortar is suspected (confidence %.2f)" % bm._mortar_existence_confidence())
	var lost := add_enemy(bm, Vector2(2419, 530))
	lost.is_visible = false
	lost.player_known_position = m(2787, 624)
	lost.player_known_position_time = bm.scenario_elapsed_time - 271.0
	var target: Vector2 = picked(bm)
	check(bm._drone_pilot_reasoning.get("tier", "") == "Regaining contact with a lost squad" and target.distance_to(m(2787, 624)) < 1.0, "Even with routine recon worth a lot, the drone goes to where the squad was lost (%s)" % str(bm._drone_pilot_reasoning))
	cleanup(bm)


## Direct user report: "Current drone behavior is crazy. We have seen a lot of enemies in the North. It should
## track them." Ten enemy squads in sight around (4090, 700) m, a suspected mortar making routine recon worth
## dozens, and the drone committed to a sweep cell at the far south-east (4950, 2450): it stayed committed,
## and a force 2500 m from our units scored nothing in the tracking tier.
func test_the_drone_watches_a_force_it_can_see() -> void:
	var bm = make_battle(Vector2(3877, 1919), true)
	bm.scenario_elapsed_time = 2000.0
	var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4715, 837))
	bm.enemy_units.append(em)
	em.is_visible = false
	bm._last_detected_mortar_fire[em] = {"position": m(4715, 837), "time": bm.scenario_elapsed_time - 700.0}
	# The drone had committed to a far sweep cell.
	bm._drone_current_destination_key = "sweep:15"
	var squads: Array[Unit] = []
	for p in [Vector2(4098, 945), Vector2(4153, 1062), Vector2(4082, 998), Vector2(4082, 536), Vector2(4098, 714), Vector2(4082, 709), Vector2(4088, 721), Vector2(4082, 825), Vector2(4084, 567), Vector2(4098, 541)]:
		squads.append(add_enemy(bm, p, Vector2(1500, 1500)))
	var target: Vector2 = picked(bm)
	check(bm._drone_pilot_reasoning.get("tier", "") == "Watching the enemy force", "The drone goes to the force it can see, not the sweep cell it had committed to (%s)" % str(bm._drone_pilot_reasoning))
	check(target.x > m(3900, 0).x and target.y < m(0, 1200).y, "...in the north-east, where the squads are (%s)" % (target / GameConfig.PIXELS_PER_METER))
	check(int(str(bm._drone_pilot_reasoning.get("detail", "")).split(" ")[0]) >= 8, "...and the reasoning counts them (%s)" % str(bm._drone_pilot_reasoning.get("detail", "")))
	# It stays with them as they move, rather than leaving once it has arrived.
	bm.active_drone.global_position = target
	for s in squads:
		s.global_position += m(-150, 30)
	var again: Vector2 = picked(bm)
	check(bm._drone_pilot_reasoning.get("tier", "") == "Watching the enemy force" and again.distance_to(target) > 1.0, "Arrived, it stays with the force and follows it (%s)" % str(bm._drone_pilot_reasoning.get("tier", "")))
	# Squads not in sight do not count.
	for s in squads:
		s.is_visible = false
	picked(bm)
	check(bm._drone_pilot_reasoning.get("tier", "") != "Watching the enemy force", "With the force out of sight there is nothing to watch")
	# A bigger force is worth more; a couple of squads are not "a lot of enemies".
	check(bm._visible_force_candidates().is_empty(), "Set-up: none in sight")
	for i in 3:
		squads[i].is_visible = true
	check(bm._visible_force_candidates().is_empty(), "Three squads in sight are not a force worth leaving the mortar search for")
	squads[3].is_visible = true
	var small: float = bm._visible_force_candidates()[0].value
	for s in squads:
		s.is_visible = true
	var large: float = bm._visible_force_candidates()[0].value
	check(large > small and small > 1.2, "A larger force is worth more (%.2f for four, %.2f for ten), each above any grid cell" % [small, large])
	cleanup(bm)
