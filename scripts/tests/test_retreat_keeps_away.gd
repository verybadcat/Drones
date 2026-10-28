extends SceneTree
## A retreat keeps away from the opposing squads its side knows of. User, 2026-10-28: "Retreating enemies should avoid our squads when the position is known. This is
## similar to how retreating friendlies should avoid enemy squads when the position is known. In both cases, make sure it is really avoided." The step of a retreat
## (BattleManager._retreat_heading) is pushed away from every known opposing position within GameConfig.RETREAT_KEEP_AWAY_RANGE, keeping at least RETREAT_MIN_PROGRESS
## toward the exit; a cover detour that ends more than RETREAT_APPROACH_TOLERANCE_M nearer to a known position is not taken (Unit.detour_nears_a_known_position).
##
## Run: godot --headless --path . --script scripts/tests/test_retreat_keeps_away.gd
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

func make_battle() -> BattleManager:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	return bm

## A retreating squad of `team` at `pos`, and a known opposing squad at `threat_pos`; returns the least distance (metres) between them over `seconds` of retreat,
## and the squad's distance to its exit line at the end.
func retreat_past(team: Unit.Team, pos: Vector2, threat_pos: Vector2, seconds: float) -> Dictionary:
	var bm := make_battle()
	var squad: Unit = bm._make_unit(team, Unit.Kind.SQUAD, pos)
	bm._set_retreat_profile(squad, team)
	var foe_team: Unit.Team = Unit.Team.ENEMY if team == Unit.Team.PLAYER else Unit.Team.PLAYER
	var foe: Unit = bm._make_unit(foe_team, Unit.Kind.SQUAD, threat_pos)
	if team == Unit.Team.PLAYER:
		bm.player_units.append(squad)
		bm.enemy_units.append(foe)
		foe.player_has_been_sighted = true
		foe.player_known_position = threat_pos
	else:
		bm.enemy_units.append(squad)
		bm.player_units.append(foe)
		foe.enemy_has_been_sighted = true
		foe.enemy_known_position = threat_pos
	squad.state = Unit.State.RETREATING
	squad.has_move_target = false
	var least := INF
	var start := pos
	var t := 0.0
	while t < seconds and squad.state == Unit.State.RETREATING:
		bm._step_retreat(squad, 0.5)
		least = minf(least, squad.position.distance_to(threat_pos))
		t += 0.5
	var out := {"least_m": least / GameConfig.PIXELS_PER_METER, "start_m": start.distance_to(threat_pos) / GameConfig.PIXELS_PER_METER, "moved_x_m": absf(squad.position.x - start.x) / GameConfig.PIXELS_PER_METER, "y_m": absf(squad.position.y - start.y) / GameConfig.PIXELS_PER_METER}
	bm.combat_log.free()
	bm.free()
	return out

func run() -> void:
	GameConfig.set_active_map("voznesensk")

	# 1. the exit is west for our squads: an enemy squad known 300 m ahead, dead level, is gone round, not through
	var r1 := retreat_past(Unit.Team.PLAYER, m(2000, 1900), m(1700, 1900), 240.0)
	check(r1.least_m > 0.6 * r1.start_m, "our squad with a known enemy squad dead ahead never comes nearer than 60%% of the distance it began at (least %.0f m of %.0f m)" % [r1.least_m, r1.start_m])
	check(r1.moved_x_m > 100.0, "...and still makes its way toward the exit (%.0f m west)" % r1.moved_x_m)

	# 2. the exit is east for the enemy's: our squad known dead ahead is gone round, too
	var r2 := retreat_past(Unit.Team.ENEMY, m(2000, 1900), m(2300, 1900), 240.0)
	check(r2.least_m > 0.6 * r2.start_m, "an enemy squad with a known squad of ours dead ahead never comes nearer than 60%% of the distance it began at (least %.0f m of %.0f m)" % [r2.least_m, r2.start_m])
	check(r2.moved_x_m > 100.0, "...and still makes its way toward the exit (%.0f m east)" % r2.moved_x_m)

	# 3. a known squad off to the side: it bends away from it and does not close on it
	var r3 := retreat_past(Unit.Team.PLAYER, m(2000, 1900), m(1900, 2100), 120.0)
	check(r3.least_m >= r3.start_m - 25.0, "a known squad off the line of retreat is not closed on (least %.0f m of %.0f m)" % [r3.least_m, r3.start_m])

	# 4. nothing known: straight to the exit, along x
	var bm := make_battle()
	var lone: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(2000, 1900))
	bm.player_units.append(lone)
	check(bm._retreat_heading(lone, -1.0) == Vector2(-1.0, 0.0), "with nothing known a retreat is straight along x")
	# 5. far from what is known (beyond the range): nothing
	var far: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(2000 - 1500, 1900))
	far.player_has_been_sighted = true
	far.player_known_position = far.global_position
	bm.enemy_units.append(far)
	check(bm._retreat_heading(lone, -1.0) == Vector2(-1.0, 0.0), "a known squad beyond the keep-away range does not bend it")
	# 6. the heading never turns back from the exit by more than the minimum progress allows
	far.player_known_position = m(2000 - 100, 1900)
	var h: Vector2 = bm._retreat_heading(lone, -1.0)
	check(absf(h.length() - 1.0) < 0.001 and h.dot(Vector2(-1.0, 0.0)) >= GameConfig.RETREAT_MIN_PROGRESS - 0.001, "...a squad with one 100 m dead ahead still turns toward the exit at least that much (progress %.2f)" % h.dot(Vector2(-1.0, 0.0)))
	check(absf(h.y) > 0.9, "...and mostly sideways (%s)" % str(h))

	# 7. a cover detour that walks toward a known squad is refused; one that does not is allowed
	var from: Vector2 = m(2000, 1900)
	var known: Array[Vector2] = [m(1700, 1900)]
	check(Unit.detour_nears_a_known_position(from, m(1850, 1900), known), "a detour 150 m toward a known squad 300 m away is refused")
	check(not Unit.detour_nears_a_known_position(from, m(2000, 2000), known), "a detour that does not bring it nearer is allowed")
	check(not Unit.detour_nears_a_known_position(from, m(1990, 1900), known), "a few metres nearer is within the tolerance")
	# ...and so is one whose end is well clear of the squad but whose way runs past it (the end 300 m on, the way within 20 m of the squad)
	var passing: Array[Vector2] = [m(1800, 1920)]
	check(Unit.detour_nears_a_known_position(from, m(1500, 1900), passing), "a detour whose way runs 20 m from a known squad is refused though its end is 300 m beyond")
	check(not Unit.detour_nears_a_known_position(from, m(2000, 1500), passing), "one going the other way is allowed")
	var very_far: Array[Vector2] = [m(-2000, 1900)]
	check(not Unit.detour_nears_a_known_position(from, m(1850, 1900), very_far), "a known squad beyond the danger range does not matter")

	print("Retreat keeps-away tests: %d failures" % failures)
	bm.combat_log.free()
	bm.free()
	quit(1 if failures else 0)
