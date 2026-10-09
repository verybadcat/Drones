extends SceneTree
## Direct user ruling, after research on what a squad's small arms include (hand grenades, room and trench clearing): "About cover being
## defeated inside of 25 meters. Yes do that." Within CLOSE_RANGE_COVER_DEFEAT_M of the shooter a target's cover (trees, a building) no longer
## lowers the chance to hit; a target in the open keeps its exposure penalty; a moving target and a mortar's plunging fire are as before.
##
## Run: godot --headless --path . --script scripts/tests/test_close_range_cover_defeat.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(x: float, y: float = 0.0) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

## The close-range multiplier on a direct shot at `distance_m`, as the resolver applies it.
func close_factor(distance_m: float) -> float:
	var decay: float = exp(-distance_m * GameConfig.PIXELS_PER_METER / GameConfig.SQUAD_CLOSE_RANGE_DECAY_M)
	return 1.0 + (GameConfig.SQUAD_CLOSE_RANGE_HIT_MULTIPLIER - 1.0) * decay

func chance(attacker: Unit, defender: Unit, point: Vector2, distance_m: float) -> float:
	return CombatResolver.hit_probability(attacker, defender, 1.0, point, point + m(distance_m))

func run() -> void:
	var shooter := Unit.new(); shooter.setup(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2.ZERO)
	var target := Unit.new(); target.setup(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2.ZERO)
	var gun := Unit.new(); gun.setup(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2.ZERO)
	var base: float = shooter.base_hit_chance
	var range_m: float = GameConfig.CLOSE_RANGE_COVER_DEFEAT_M
	check(is_equal_approx(range_m, 25.0), "Setup: the range is 25 m, as ruled")

	# trees (Pishchane's west flank is woods)
	GameConfig.set_active_map("pishchane")
	var in_trees: Vector2 = m(-20, 2080)
	check(GameConfig.get_terrain_type_at(in_trees) == GameConfig.TerrainType.TREES, "Setup: a point in trees")
	var far_trees: float = chance(shooter, target, in_trees, 30.0)
	var near_trees: float = chance(shooter, target, in_trees, 20.0)
	var tree_cover: float = CombatResolver.SQUAD_COVER_MULTIPLIER[GameConfig.TerrainType.TREES]
	check(is_equal_approx(far_trees, base * tree_cover * close_factor(30.0)), "Beyond 25 m, trees protect as before (%.4f)" % far_trees)
	check(is_equal_approx(near_trees, base * 1.0 * close_factor(20.0)), "Inside 25 m, trees no longer protect (%.4f, expected %.4f)" % [near_trees, base * close_factor(20.0)])
	check(near_trees > 4.0 * far_trees, "...so a squad in trees is far easier to hit at 20 m than at 30 m (%.3f against %.3f)" % [near_trees, far_trees])
	# the edge: at exactly 25 m the cover is defeated, just beyond it is not
	check(is_equal_approx(chance(shooter, target, in_trees, 25.0), base * close_factor(25.0)), "At exactly 25 m cover is defeated")
	check(is_equal_approx(chance(shooter, target, in_trees, 25.5), base * tree_cover * close_factor(25.5)), "...at 25.5 m it is not")

	# a building
	GameConfig.set_active_map("voznesensk")
	GameConfig._build_terrain_grid()
	var in_building: Vector2 = GameConfig._building_rects[0].get_center()
	check(GameConfig.get_terrain_type_at(in_building) == GameConfig.TerrainType.BUILDING, "Setup: a point in a building")
	var b_cover: float = CombatResolver.SQUAD_COVER_MULTIPLIER[GameConfig.TerrainType.BUILDING]
	check(is_equal_approx(chance(shooter, target, in_building, 40.0), base * b_cover * close_factor(40.0)), "A building protects at 40 m as before")
	check(is_equal_approx(chance(shooter, target, in_building, 10.0), base * close_factor(10.0)), "...and not at 10 m")
	check(chance(shooter, target, in_building, 10.0) > 8.0 * chance(shooter, target, in_building, 40.0), "...so the same squad is many times easier to hit at 10 m than at 40 m")

	# open ground keeps its exposure penalty, whatever the range
	var open_point := Vector2.INF
	for x in range(100, 4900, 100):
		var p: Vector2 = m(float(x), 100.0)
		if GameConfig.get_terrain_type_at(p) == GameConfig.TerrainType.OPEN:
			open_point = p
			break
	check(not is_inf(open_point.x), "Setup: a point in the open")
	var open_cover: float = CombatResolver.SQUAD_COVER_MULTIPLIER[GameConfig.TerrainType.OPEN]
	for d in [10.0, 20.0, 40.0]:
		check(is_equal_approx(chance(shooter, target, open_point, d), base * open_cover * close_factor(d)), "A target in the open is as exposed at %d m as before" % int(d))

	# a moving target has no cover either way
	target.activity = Unit.Activity.MOVING
	check(is_equal_approx(chance(shooter, target, in_building, 10.0), chance(shooter, target, in_building, 10.0)) and is_equal_approx(chance(shooter, target, in_building, 10.0), base * GameConfig.MOVING_HIT_MULTIPLIER * close_factor(10.0)), "A moving target is as before (no cover to defeat)")
	target.activity = Unit.Activity.STATIONARY

	# a mortar's plunging fire is not affected
	GameConfig.set_active_map("pishchane")
	var mortar_close: float = CombatResolver.hit_probability(gun, target, 1.0, in_trees, in_trees + m(20.0))
	var mortar_far: float = CombatResolver.hit_probability(gun, target, 1.0, in_trees, in_trees + m(2000.0))
	check(is_equal_approx(mortar_close, mortar_far) and mortar_close < gun.base_hit_chance, "A mortar round's chance does not depend on range or on this rule, and trees still help (%.3f)" % mortar_close)
	for u in [shooter, target, gun]:
		u.free()
	print("Close-range cover defeat tests: %d failures" % failures)
	quit(1 if failures else 0)
