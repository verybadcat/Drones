extends SceneTree
## Direct user report, live: "Right now, enemy squads 2 and 6 are not attacking the friendly squads. I see no
## rational explanation." Polling the live unit snapshot showed they WERE moving, but not toward the friendly
## squads: squad 6, ~1200 m west of the friendly line with the squads as its objective, stepped north-west
## (away), then north-east, then...; squad 2 (on its flank route) stepped west, away from its waypoint, then
## south. Each bound is a rolled pick among candidates bent up to +-120 degrees off the line to the objective,
## weighted by cover (+3), concealment (+2) and encirclement (+3) bonuses against a small angle penalty. Those
## bonuses are about a fight: terrain to fight from, staying out of known fire, spreading around the enemy.
## 1200 m from any friendly none of them buys anything, yet they still outweighed the straight line, so the
## squad drifted sideways with a net advance of only about three quarters of a bound per bound, and about a one-in-three chance that any given bound was a wasted or backward one.
##
## Fix: cover, concealment and encirclement count for nothing far from the objective and fully close to it
## (BattleManager._advance_tactical_pressure: a ramp from GameConfig.ENEMY_ADVANCE_TACTICAL_RANGE down to the
## standoff ring). The angle penalty and the exposure penalty are untouched, and the alert-time scatter
## (max_step = INF) is unchanged, since it only ever happens at contact.
##
## Run: godot --headless --path . --script scripts/tests/test_enemy_advance_far_from_contact.gd
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

## Friendly squads (the objective) at the origin; no friendly mortar, so the squads are the objective.
func make_battle() -> BattleManager:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	for p in [Vector2(0.0, 0.0), Vector2(0.0, 100.0), Vector2(0.0, -100.0)]:
		var f: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(p.x, p.y))
		f.enemy_has_been_sighted = true
		f.enemy_known_state = Unit.State.ACTIVE
		bm.player_units.append(f)
	return bm

func enemy_at(bm: BattleManager, pos_m: Vector2) -> Unit:
	var e: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(pos_m.x, pos_m.y))
	e.sought_cover = true
	bm.enemy_units.append(e)
	return e

func cleanup(bm: BattleManager) -> void:
	bm.combat_log.free()
	bm.free()

func run() -> void:
	seed(12345)
	test_far_from_the_objective_a_bound_goes_straight_at_it()
	test_close_to_the_objective_the_squad_still_bends_around_it()
	test_the_pressure_ramps_smoothly()
	print("Enemy advance far-from-contact tests: %d failures" % failures)
	quit(1 if failures else 0)


## Mean fraction of a bound's length that is real progress toward the objective, over many rolled bounds.
func mean_progress(bm: BattleManager, u: Unit, objective: Vector2, rolls: int) -> float:
	var start: Vector2 = u.global_position
	var sum := 0.0
	var dir: Vector2 = (objective - start).normalized()
	var rush: float = GameConfig.ENEMY_ADVANCE_RUSH_DISTANCE
	for i in rolls:
		var p: Vector2 = bm._next_advance_point(u)
		sum += (p - start).dot(dir) / rush
	return sum / rolls


func test_far_from_the_objective_a_bound_goes_straight_at_it() -> void:
	var bm := make_battle()
	var u: Unit = enemy_at(bm, Vector2(-1200.0, 500.0)) # the live case: ~1300 m west and a little south of the line
	var objective: Vector2 = bm._enemy_advance_objective(u)
	check(u.global_position.distance_to(objective) > GameConfig.ENEMY_ADVANCE_TACTICAL_RANGE, "Setup: well beyond the range where tactics matter (%.0f m)" % (u.global_position.distance_to(objective) / GameConfig.PIXELS_PER_METER))
	var progress: float = mean_progress(bm, u, objective, 600)
	check(progress > 0.9, "A far squad makes nearly a full bound of progress per bound (mean %.2f of a bound; it was 0.74 before the fix)" % progress)
	# And not by luck of the average: no single bound may be a step backward or sideways either.
	var worst := 1.0
	var dir: Vector2 = (objective - u.global_position).normalized()
	for i in 300:
		worst = minf(worst, (bm._next_advance_point(u) - u.global_position).dot(dir) / GameConfig.ENEMY_ADVANCE_RUSH_DISTANCE)
	check(worst > 0.7, "...and no bound bends far off the line (worst %.2f of a bound)" % worst)
	cleanup(bm)


## Close in, bending around the objective for cover and spread is exactly what the scoring is for: it must
## still happen (otherwise every squad would pile in on the one bearing).
func test_close_to_the_objective_the_squad_still_bends_around_it() -> void:
	var bm := make_battle()
	var u: Unit = enemy_at(bm, Vector2(-550.0, 0.0)) # just past the standoff ring, inside tactical range
	var objective: Vector2 = bm._enemy_advance_objective(u)
	var dir: Vector2 = (objective - u.global_position).normalized()
	var bent := 0
	var rolls := 400
	for i in rolls:
		var p: Vector2 = bm._next_advance_point(u)
		var step: Vector2 = (p - u.global_position).normalized()
		if absf(rad_to_deg(dir.angle_to(step))) > 20.0:
			bent += 1
	check(bent > rolls / 5, "Close to the objective a good share of bounds still bend off the straight line (%d of %d)" % [bent, rolls])
	cleanup(bm)


func test_the_pressure_ramps_smoothly() -> void:
	var bm := make_battle()
	var ring: float = GameConfig.ENEMY_SURROUND_STANDOFF_RADIUS
	var far: float = GameConfig.ENEMY_ADVANCE_TACTICAL_RANGE
	check(is_equal_approx(bm._advance_tactical_pressure(far * 2.0), 0.0), "No pressure far away")
	check(is_equal_approx(bm._advance_tactical_pressure(ring), 1.0), "Full pressure at the standoff ring")
	var mid: float = bm._advance_tactical_pressure((ring + far) * 0.5)
	check(mid > 0.4 and mid < 0.6, "Half way, about half (%.2f)" % mid)
	var last := 1.0
	var monotonic := true
	for i in 21:
		var p: float = bm._advance_tactical_pressure(ring + (far - ring) * (i / 20.0))
		if p > last + 0.0001:
			monotonic = false
		last = p
	check(monotonic, "It only ever falls as the distance grows")
	cleanup(bm)
