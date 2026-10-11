extends SceneTree
## Direct user report, live: the enemy squads went to the bottom of the map and then "were advancing towards empty terrain". The first bound a
## squad takes when the march is broken (max_step INF, so the whole remaining distance) used the whole distance for every bent candidate too:
## from far out, a bend of 50-120 degrees was a swing of 1000-2000 m to the side or past the objective. Now only the straight candidate takes
## the whole distance; a bent one is an ordinary bound (GameConfig.ENEMY_ADVANCE_RUSH_DISTANCE). Nearer the objective than that nothing changes.
##
## Run: godot --headless --path . --script scripts/tests/test_alert_scatter_limited.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(v: Vector2) -> Vector2:
	return v * GameConfig.PIXELS_PER_METER

func make(start_m: Vector2) -> Array:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(start_m))
	bm.enemy_units.append(squad)
	return [bm, squad]

func run() -> void:
	GameConfig.set_active_map("pishchane")
	var village: Vector2 = GameConfig.CURRENT_MAP.village_center
	var rush: float = GameConfig.ENEMY_ADVANCE_RUSH_DISTANCE

	# 1. far out: no bound ends more than a bound's length off the straight line, and none is farther from the squad than the whole way
	var made := make(Vector2(3500.0, 500.0))
	var bm: BattleManager = made[0]
	var squad: Unit = made[1]
	var to_obj: Vector2 = village - squad.global_position
	var whole: float = to_obj.length() - GameConfig.ENEMY_SURROUND_STANDOFF_RADIUS
	var dir: Vector2 = to_obj.normalized()
	var worst_lateral := 0.0
	var straight_n := 0
	var far_south := 0
	var n := 400
	for i in n:
		var p: Vector2 = bm._next_advance_point(squad, INF)
		var offset: Vector2 = p - squad.global_position
		worst_lateral = maxf(worst_lateral, absf(offset.dot(dir.orthogonal())))
		if absf(offset.dot(dir.orthogonal())) < 1.0:
			straight_n += 1
		if p.y > village.y + m(Vector2(0.0, 250.0)).y:
			far_south += 1
	check(worst_lateral <= rush + 1.0, "A bent first bound from 2400 m out is at most a bound (%.0f m) off the straight line, not the whole way (worst %.0f m)" % [rush / GameConfig.PIXELS_PER_METER, worst_lateral / GameConfig.PIXELS_PER_METER])
	check(straight_n > 0, "...and the straight candidate still takes the whole distance, sometimes (%d of %d)" % [straight_n, n])
	check(far_south * 4 < n, "...so squads are not thrown to the south side of the village (%d of %d ended more than 250 m south of it)" % [far_south, n])
	bm.combat_log.free()
	bm.free()

	# 2. near the objective (less than a bound beyond the standoff) a bent candidate is exactly as long as before: the whole way there
	made = make(Vector2(1564.0, 1362.0)) # ~390 m from the village centre: well inside one bound
	bm = made[0]
	squad = made[1]
	var near_whole: float = (village - squad.global_position).length() - GameConfig.ENEMY_SURROUND_STANDOFF_RADIUS
	check(near_whole < rush, "(setup) the near start is within a bound of the standoff ring (%.0f m)" % (near_whole / GameConfig.PIXELS_PER_METER))
	var lens_ok := true
	for i in 100:
		var p2: Vector2 = bm._next_advance_point(squad, INF)
		var leg: float = (p2 - squad.global_position).length()
		if leg > near_whole + 1.0:
			lens_ok = false
	check(lens_ok, "Within a bound of the ring, no candidate is longer than the way to the ring (unchanged)")
	bm.combat_log.free()
	bm.free()

	print("Alert scatter tests: %d failures" % failures)
	quit(1 if failures else 0)
