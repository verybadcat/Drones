extends SceneTree
## Direct user report, live: "Friendly squad 3 is oscillating uselessly." The squad's reason was "Known enemies threaten encirclement:
## consolidate toward friendly units", and its target kept jumping between spots a few dozen metres apart. With known enemies between the
## squad and its friends, the cover search (which throws out any zone near a known enemy and picks at random among the nearest) could
## only offer cover BEHIND it, so each arrival chose a fresh spot, often farther from the rally point than before. Reproduced here: a squad
## 1,074 m from the rally point went 1,166, 1,159, 1,157, 1,144, 1,148, 1,159, 1,162 m.
##
## The cover chosen now has to be a real step toward the rally point (ENCIRCLEMENT_MIN_PROGRESS_FRACTION of the capped step); if none is, the
## squad stays where it is.
##
## Run: godot --headless --path . --script scripts/tests/test_encirclement_consolidation_progress.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(x: float, y: float) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER


## Enemies on cover zones 150-580 m from `here`, at least 50 degrees apart: a ring of known, dug-in enemies.
func ring_of_enemies(bm, here: Vector2) -> int:
	bm.enemy_units.clear()
	var cands: Array = []
	for z in GameConfig._all_cover_zones():
		var d: float = z.center.distance_to(here) / GameConfig.PIXELS_PER_METER
		if d > 150.0 and d < 580.0:
			cands.append([z.center, (z.center - here).angle()])
	var chosen: Array = []
	for c in cands:
		var ok := true
		for o in chosen:
			if absf(angle_difference(c[1], o[1])) < deg_to_rad(50.0):
				ok = false
		if ok:
			chosen.append(c)
	if chosen.size() < 3:
		return 0
	for c in chosen:
		var e: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, c[0])
		bm.enemy_units.append(e)
		e.is_visible = true
	bm._update_player_intel()
	return chosen.size()


## Runs the consolidation from `here` for up to 25 arrivals; returns the squad's distance to the rally point after each, or [] if it never began.
func run_from(bm, here: Vector2, rally: Vector2, squad: Unit) -> Array[float]:
	var out: Array[float] = []
	squad.global_position = here
	squad.has_move_target = false
	var known: Array[Vector2] = bm._known_enemy_positions(Unit.Team.PLAYER)
	for i in 25:
		var dest: Vector2 = bm._reposition_for_encirclement(squad, known, bm._ally_positions_for(squad))
		if dest == squad.global_position:
			break
		squad.global_position = dest # arrives
		squad.has_move_target = false
		out.append(dest.distance_to(rally) / GameConfig.PIXELS_PER_METER)
	return out


func run() -> void:
	GameConfig.set_active_map("voznesensk")
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var friends: Array = []
	for p in [Vector2(-700, 1400), Vector2(-500, 1100)]:
		var u: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(p.x, p.y))
		bm.player_units.append(u)
		friends.append(u)
	var squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(300, 1200))
	bm.player_units.append(squad)
	var rally: Vector2 = (friends[0].global_position + friends[1].global_position) / 2.0
	var tried := 0
	var moved_at_least_once := 0
	var worst_backslide := 0.0
	for start in [Vector2(-100, 300), Vector2(-100, 400), Vector2(-100, 1600), Vector2(-100, 1700), Vector2(-100, 1900)]:
		if ring_of_enemies(bm, m(start.x, start.y)) == 0:
			continue
		for seed_value in 12:
			seed(seed_value)
			var d0: float = m(start.x, start.y).distance_to(rally) / GameConfig.PIXELS_PER_METER
			var path: Array[float] = run_from(bm, m(start.x, start.y), rally, squad)
			tried += 1
			if path.size() > 0:
				moved_at_least_once += 1
			var prev := d0
			for d in path:
				worst_backslide = maxf(worst_backslide, d - prev)
				prev = d
	check(tried >= 20, "Setup: the scenario was run from several starts and seeds (%d runs)" % tried)
	check(moved_at_least_once > 0, "Setup: the squad does set about consolidating in some of them (%d runs)" % moved_at_least_once)
	check(worst_backslide <= 1.0, "Each consolidation step brings the squad closer to the rally point, never farther (worst step back: %.0f m)" % worst_backslide)
	bm.combat_log.free()
	bm.free()
	print("Encirclement consolidation progress tests: %d failures" % failures)
	quit(1 if failures else 0)
