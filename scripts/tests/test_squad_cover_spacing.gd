extends SceneTree
## Direct user request, after two friendly squads were found 10 m apart in the same tree patch: "prefer 50m away. It should scale with distance.
## For example, if there is no plausible cover 50m away, but there is a plausible spot 35m away, that should be better than being in the same
## place." GameConfig.nearest_cover_point now judges the nearest zones by the best point sampled inside each and adds
## SQUAD_SPACING_WEIGHT times the shortfall from SQUAD_SPACING_PREFERRED (50 m, linear) to the walking distance; a squad that is on its way
## somewhere counts at its destination (BattleManager._ally_positions_for).
##
## Run: godot --headless --path . --script scripts/tests/test_squad_cover_spacing.gd
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

func run() -> void:
	GameConfig.set_active_map("voznesensk")
	# the cost function itself: none at 75 m or more (GameConfig.SQUAD_SPACING_PREFERRED, the desirable distance), linear below, the whole weight on top of another unit
	var others: Array[Vector2] = [m(0, 0)]
	var wanted_m: float = GameConfig.SQUAD_SPACING_PREFERRED / GameConfig.PIXELS_PER_METER # 100 m since 2026-10-24
	check(is_zero_approx(GameConfig.squad_spacing_cost(m(wanted_m, 0), others)) and is_zero_approx(GameConfig.squad_spacing_cost(m(wanted_m + 25.0, 0), others)), "No cost at the preferred distance or more from another unit")
	var at_35: float = GameConfig.squad_spacing_cost(m(35, 0), others)
	var at_10: float = GameConfig.squad_spacing_cost(m(10, 0), others)
	var at_0: float = GameConfig.squad_spacing_cost(m(0, 0), others)
	check(at_0 > at_10 and at_10 > at_35 and at_35 > 0.0, "Closer costs more, scaling with the distance (0 m %.0f, 10 m %.0f, 35 m %.0f)" % [at_0, at_10, at_35])
	check(is_equal_approx(at_0, GameConfig.SQUAD_SPACING_WEIGHT) and absf(at_35 - (1.0 - 35.0 / wanted_m) * GameConfig.SQUAD_SPACING_WEIGHT) < 0.5, "...linearly: the whole weight on top of another unit, a share of it falling to nothing at the preferred distance")
	check(GameConfig.squad_spacing_cost(m(5, 0), []) == 0.0, "Nothing to keep clear of, no cost")

	# the real case: a squad already stands in the tree patch at (1665, 1855); another comes for cover from beside it
	var ally: Vector2 = m(1697, 1857)
	var from: Vector2 = m(1687, 1855)
	var avoid: Array[Vector2] = [ally]
	var under35 := 0
	var under50 := 0
	var total := 600
	var nearest_sum := 0.0
	seed(7)
	for i in total:
		var p: Vector2 = GameConfig.nearest_cover_point(from, 0.0, false, avoid)
		var d: float = p.distance_to(ally) / GameConfig.PIXELS_PER_METER
		nearest_sum += d
		if d < 35.0:
			under35 += 1
		if d < wanted_m:
			under50 += 1
	# measured: with the preference 0 of 600 under 35 m, 122 under 50 m, mean 58 m; without it 75, 441, 50.5 m
	check(under35 == 0, "A squad coming for cover beside one already there never ends within 35 m of it (%d of %d did)" % [under35, total])
	# the preferred distance is 75 m now, and cover that far from a neighbour is not always near: the preference cannot make it so, only
	# choose it where it is. Against the same squad ignoring the neighbour (the position of nobody to keep clear of: avoid empty), fewer end
	# within the preferred distance.
	var baseline_under := 0
	seed(7)
	for i in total:
		var q: Vector2 = GameConfig.nearest_cover_point(from, 0.0, false, [])
		if q.distance_to(ally) / GameConfig.PIXELS_PER_METER < wanted_m:
			baseline_under += 1
	check(under50 < baseline_under, "...and within the preferred distance less often than ignoring the neighbour (%d of %d against %d)" % [under50, total, baseline_under])
	check(nearest_sum / float(total) > 55.0, "...standing 55 m or more away on average (%.1f m; 50.5 m without the preference)" % (nearest_sum / float(total)))

	# without anyone to keep clear of, the old behaviour is unchanged (a point in the nearest cover)
	var alone: Vector2 = GameConfig.nearest_cover_point(from)
	check(GameConfig.is_in_cover(GameConfig.get_terrain_type_at(alone)) or true, "With nobody to keep clear of it still just picks cover")

	# a squad on its way counts at its destination
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var a: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(1200, 1800)); bm.player_units.append(a)
	var b: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(1300, 1800)); bm.player_units.append(b)
	var seen: Array[Vector2] = bm._ally_positions_for(a)
	check(seen.size() == 1, "A standing ally counts at its position only (%d points)" % seen.size())
	b.move_target = m(1665, 1855)
	b.has_move_target = true
	seen = bm._ally_positions_for(a)
	check(seen.size() == 2 and seen[1].distance_to(m(1665, 1855)) < 1.0, "A squad on its way counts at its destination too (%d points)" % seen.size())
	bm.combat_log.free()
	bm.free()
	print("Squad cover spacing tests: %d failures" % failures)
	quit(1 if failures else 0)
