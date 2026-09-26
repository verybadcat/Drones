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
