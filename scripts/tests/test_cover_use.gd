extends SceneTree
## A unit standing in cover has its people use it. User, 2026-10-24: "If there is cover, the people should use it. while standing that is. When moving, not
## necessarily." (CombatResolver.person_point, people_use_cover: a standing unit in trees or a building has each of its people at a place in that same kind
## of cover; a unit on the move has them over its disc, in the open or in the cover. The blast's escape chance is decided at each person's own place.)
##
## Run: godot --headless --path . --script scripts/tests/test_cover_use.gd
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

## The share of 400 people of `unit` that stand at a place of the given terrain.
func share_in(unit: Unit, terrain: GameConfig.TerrainType) -> float:
	var spread: float = CombatResolver.blast_spread_m(unit)
	var inside := 0
	for i in 400:
		if GameConfig.get_terrain_type_at(CombatResolver.person_point(unit, spread)) == terrain:
			inside += 1
	return float(inside) / 400.0

func run() -> void:
	GameConfig.set_active_map("voznesensk")
	GameConfig._build_terrain_grid()
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.scenario_elapsed_time = 1000.0
	seed(77)

	# --- in a building
	var rect: Rect2 = GameConfig._building_rects[0]
	var inside: Vector2 = rect.get_center()
	var still: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, inside)
	bm.player_units.append(still)
	check(CombatResolver.people_use_cover(still), "a squad standing in a building uses it")
	check(share_in(still, GameConfig.TerrainType.BUILDING) == 1.0, "...every one of its people is in the building")
	var mover: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, inside)
	bm.player_units.append(mover)
	mover.activity = Unit.Activity.MOVING
	check(not CombatResolver.people_use_cover(mover), "a squad on the move does not have to")
	var mover_in: float = share_in(mover, GameConfig.TerrainType.BUILDING)
	check(mover_in < 0.9, "...so over its 50 m disc some of its people are in the open (%.2f in the building)" % mover_in)

	# --- in the open: nothing forces the people together; they are over the whole 30 m disc
	var open_point: Vector2 = m(-5000, -5000)
	var in_open: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, open_point + m(0, 800))
	bm.player_units.append(in_open)
	check(not CombatResolver.people_use_cover(in_open), "a squad in the open has no cover to use")
	var far := 0.0
	for i in 400:
		far = maxf(far, CombatResolver.person_point(in_open, 30.0).distance_to(in_open.global_position) / GameConfig.PIXELS_PER_METER)
	check(far > 25.0, "...its people are over the whole disc (the farthest %.0f m)" % far)

	# --- in trees
	var tree_point := Vector2.INF
	for x in range(-2000, 6000, 40):
		for y in range(-500, 6000, 40):
			var p := m(x, y)
			if GameConfig.get_terrain_type_at(p) == GameConfig.TerrainType.TREES:
				tree_point = p
				break
		if not is_inf(tree_point.x):
			break
	check(not is_inf(tree_point.x), "setup: a place in trees")
	if not is_inf(tree_point.x):
		var in_trees: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, tree_point)
		bm.player_units.append(in_trees)
		check(share_in(in_trees, GameConfig.TerrainType.TREES) == 1.0, "a squad standing in trees: every one of its people is in the trees")

	# --- in a battle: a round outside the building. Standing in it, the walls take all the fragments; on the move, the people over the disc are not behind them.
	var burst: Vector2 = Vector2(rect.end.x + m(20).x, rect.get_center().y)
	var lost_still := 0
	var lost_moving := 0
	for i in 150:
		var a: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, inside)
		var b: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, inside)
		b.activity = Unit.Activity.MOVING
		bm.player_units.append(a)
		bm.player_units.append(b)
		bm._apply_shell_blast(burst, null)
		lost_still += a.max_pips - a.pips
		lost_moving += b.max_pips - b.pips
		bm.player_units.erase(a)
		bm.player_units.erase(b)
		a.free()
		b.free()
	check(lost_still == 0, "a squad standing in a building loses nobody to a round outside it (%d)" % lost_still)
	check(lost_moving > 0, "...a squad on the move over the same place does (%d)" % lost_moving)

	print("Cover use tests: %d failures" % failures)
	bm.combat_log.free()
	bm.free()
	quit(1 if failures else 0)
