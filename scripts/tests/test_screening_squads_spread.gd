extends SceneTree
## Direct user guidance: "I would discourage squads from taking up positions within 50 meters of each other for sure. But during movement I'm
## less sure. It is also important for them to get where they are going." Found in a live battle: three of our squads, all sent to
## "Screen an open approach to the friendly mortar", were 19, 22 and 33 m apart and all aimed at the SAME point. Sending all of them is fine
## (the user: "in general I think sending all of the squads in that situation is fine. I wasn't guiding. I was asking for info"); the point
## being the same coordinate for every squad was the fault. Squads that screen the same approach are now placed side by side
## (SCREEN_SQUAD_SPACING, 70 m).
##
## Run: godot --headless --path . --script scripts/tests/test_screening_squads_spread.gd
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


func make_battle() -> Dictionary:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(500, 2000))
	bm.player_units.append(mortar)
	# three idle squads on cover well off the lane to the threat (so the cover-seeking tier leaves them alone)
	var squads: Array[Unit] = []
	var spots: Array[Vector2] = []
	for z in GameConfig._all_cover_zones():
		var d: float = z.center.distance_to(mortar.global_position) / GameConfig.PIXELS_PER_METER
		var below: bool = z.center.y > m(0, 2400).y # south of the lane (the lane runs east along y = 2000)
		if d > 500.0 and d < 1100.0 and below:
			var far_enough := true
			for s in spots:
				if s.distance_to(z.center) < m(150, 0).x:
					far_enough = false
			if far_enough:
				spots.append(z.center)
		if spots.size() == 3:
			break
	for p in spots:
		var s: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, p)
		bm.player_units.append(s)
		squads.append(s)
	var threat: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(1500, 2000))
	bm.enemy_units.append(threat)
	threat.is_visible = true
	bm._update_player_intel()
	return {"bm": bm, "mortar": mortar, "squads": squads, "threat": threat}


func screening(squads: Array[Unit]) -> Array[Unit]:
	return squads.filter(func(s): return s.has_move_target and s.last_order_reason == BattleManager.SCREEN_REASON)


func run() -> void:
	GameConfig.set_active_map("pishchane")
	var c := make_battle()
	var bm: BattleManager = c.bm
	var squads: Array[Unit] = c.squads
	check(squads.size() == 3, "Setup: three idle squads on cover (%d)" % squads.size())
	if squads.size() < 3:
		quit(1)
		return
	# Every idle squad is sent while the approach is open (user: "in general I think sending all of the squads in that situation is fine").
	for i in 4:
		bm._update_friendly_squad_positioning()
	var on_screen: Array[Unit] = screening(squads)
	check(on_screen.size() == 3, "All three idle squads are sent to screen the open approach (%d)" % on_screen.size())
	if on_screen.size() == 3:
		var points: Array[Vector2] = []
		for s in on_screen:
			points.append(s.move_target)
		var worst := INF
		for i in 3:
			for j in range(i + 1, 3):
				worst = minf(worst, points[i].distance_to(points[j]) / GameConfig.PIXELS_PER_METER)
		check(worst >= 60.0, "...each to its own point, no two less than 60 m apart (closest pair %.0f m)" % worst)
		check(worst <= 80.0 and points[0].distance_to(points[1]) < m(150, 0).x, "...a squad-spacing and no more, so the screen stays one line across the approach (closest pair %.0f m)" % worst)
	# A lone squad takes the line itself.
	var lone: Vector2 = bm._screen_point(c.mortar, c.threat.global_position, 0, 1)
	var base: Vector2 = c.mortar.global_position + (c.threat.global_position - c.mortar.global_position).normalized() * GameConfig.MORTAR_PROTECTIVE_RADIUS
	check(lone.distance_to(base) < 1.0, "A lone screening squad goes to the point on the line itself")
	bm.combat_log.free()
	bm.free()
	print("Screening squads spread tests: %d failures" % failures)
	quit(1 if failures else 0)
