extends SceneTree
## Guards mortar bunching-avoidance — user report: "Enemy mortars
## sometimes bunch up. They should try hard to avoid that." See
## GameConfig.MORTAR_BUNCHING_AVOIDANCE_RADIUS's own doc comment for the
## real citation (FM 7-90 Ch.7's individual-tube lateral dispersion
## standard, NOT the wrong-scale 300m whole-platoon figure an earlier,
## measurably inert version of this fix used) and for why the final
## design is a continuous score factor rather than a hard/two-stage gate
## (a two-stage version silently did nothing at all once two mortars were
## already close, and later also failed to prefer the least-bad option
## once several mortars were all squeezed toward the same map edge).
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_bunching_avoidance.gd
const Orders = preload("res://scripts/unit_doctrine.gd")
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func make_battle():
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	return bm


## Direct calibration check on the scoring function itself: a candidate
## exactly at MORTAR_BUNCHING_AVOIDANCE_RADIUS from a sibling should score
## at full (1.0x) credit, and one right on top of a sibling should score
## far lower (but never literally zero — see the constant's own doc
## comment on why a cornered mortar must still be able to move at all).
func test_ring_search_statistically_prefers_sibling_clearance() -> void:
	var from := Vector2(0, 0)
	# No threats at all — isolates the comparison to the bunching factor
	# alone: with nothing to hide from, every candidate is trivially
	# "hidden" and the away-from-threat bonus defaults to the same theta=0
	# axis in BOTH runs below, so it can't bias the comparison itself.
	var threats: Array[Vector2] = []
	# 75m east — comfortably within CONCEALMENT_SEARCH_RINGS_M's own
	# smallest ring (also 75m), so roughly half the 48 candidates land
	# meaningfully closer to this than the other half.
	var sibling := Vector2(15.0, 0.0)
	var bunch_avoid: Array[Vector2] = [sibling]
	var total_dist_with_avoidance := 0.0
	var total_dist_without_avoidance := 0.0
	const DRAWS := 40
	seed(112233)
	for i in DRAWS:
		var with_point: Vector2 = GameConfig._ring_search_hidden_point(from, threats, false, false, [], Vector2.INF, INF, 0.0, bunch_avoid)
		total_dist_with_avoidance += with_point.distance_to(sibling)
	seed(112233) # same draws, same underlying randf() stream, only bunch_avoid differs
	for i in DRAWS:
		var without_point: Vector2 = GameConfig._ring_search_hidden_point(from, threats, false, false, [], Vector2.INF, INF, 0.0, [])
		total_dist_without_avoidance += without_point.distance_to(sibling)
	var avg_with: float = total_dist_with_avoidance / DRAWS
	var avg_without: float = total_dist_without_avoidance / DRAWS
	check(avg_with > avg_without,
		"Candidates should average a real, measurably GREATER distance from a sibling when bunching-avoidance is active (with=%.1f, without=%.1f)" % [avg_with, avg_without])


## The exact reported mechanism (see the design doc's own entry): with a
## sibling positioned right where the natural (offset 0) hunting advance
## point would land, the function must pick a genuinely different angle
## that clears real distance from it, not the one that bunches.
func test_advance_point_avoids_sibling_at_natural_angle() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(0, 0))
	bm.enemy_units.append(mortar)
	var target_pos := Vector2(500, 0)
	var natural_point: Vector2 = target_pos - Vector2(1, 0) * (GameConfig.mortar_max_range(mortar.team) * 0.9)
	var sibling: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, natural_point)
	bm.enemy_units.append(sibling)

	var dest: Vector2 = bm._mortar_advance_point(mortar, target_pos)
	check(dest.distance_to(natural_point) > 1.0,
		"With a sibling sitting exactly at the natural (offset-0) advance point, a different angle must be chosen")
	check(dest.distance_to(sibling.global_position) >= GameConfig.MORTAR_BUNCHING_AVOIDANCE_RADIUS - 1.0,
		"A real alternative angle exists here (open ground, no buildings) — it must be chosen over one that still bunches")


## When EVERY candidate angle is within the avoidance radius of some
## sibling (a real, if rare, geometrically cornered case), the function
## must still return a genuine move — never freeze in place — and must
## prefer whichever candidate keeps the MOST distance from the nearest
## sibling, not just the first one tried in priority order.
func test_advance_point_falls_back_to_least_bad_when_fully_boxed_in() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(0, 0))
	bm.enemy_units.append(mortar)
	var target_pos := Vector2(500, 0)
	var target_distance: float = GameConfig.mortar_max_range(mortar.team) * 0.9
	var base_dir: Vector2 = (target_pos - mortar.global_position).normalized()
	# Place a sibling directly on top of every single candidate angle this
	# function tries, EXCEPT one — that one must win outright, and every
	# candidate must clearly be "some real point," not a frozen no-op.
	var farthest_offset := 45.0
	for offset_deg in [0.0, -15.0, 15.0, -30.0, 30.0, -45.0]:
		var dir: Vector2 = base_dir.rotated(deg_to_rad(offset_deg))
		var candidate: Vector2 = target_pos - dir * target_distance
		var sib: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, candidate)
		bm.enemy_units.append(sib)
	var least_boxed_dir: Vector2 = base_dir.rotated(deg_to_rad(farthest_offset))
	var least_boxed_candidate: Vector2 = target_pos - least_boxed_dir * target_distance
	var far_sib: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, least_boxed_candidate + Vector2(GameConfig.MORTAR_BUNCHING_AVOIDANCE_RADIUS * 0.5, 0))
	bm.enemy_units.append(far_sib)

	var dest: Vector2 = bm._mortar_advance_point(mortar, target_pos)
	check(dest.distance_to(mortar.global_position) > 1.0, "Even fully boxed in by siblings, a real hunt move must still happen, not a freeze")
	check(dest.distance_to(least_boxed_candidate) < 1.0,
		"The candidate with the MOST clearance from its nearest sibling must win, not just the first one tried")


func run() -> void:
	test_ring_search_statistically_prefers_sibling_clearance()
	test_advance_point_avoids_sibling_at_natural_angle()
	test_advance_point_falls_back_to_least_bad_when_fully_boxed_in()
	print("Mortar bunching-avoidance tests: %d failures" % failures)
	quit(1 if failures else 0)
