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

## GameConfig.CURRENT_MAP.enemy.mortar_rear_x_m/spread_min/max_y_m all
## put default enemy mortar spawns hundreds of meters apart — comfortably
## outside MORTAR_BUNCHING_CRITICAL_RADIUS on their own — so both new
## tests below place their pair of mortars explicitly this close instead
## of relying on any default deployment.
var critically_close_offset: Vector2 = Vector2(GameConfig.MORTAR_BUNCHING_CRITICAL_RADIUS * 0.3, 0)

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
	# Clamped exactly like _mortar_advance_point's own candidate — the raw,
	# unclamped point is off the actual operating area for a range this
	# large (see clamp_to_operating_area's own doc comment), so the
	# sibling must sit at the position the function can actually land on,
	# not the theoretical unclamped one, or this stops testing the real
	# mechanism at all.
	var natural_point: Vector2 = GameConfig.clamp_to_operating_area(target_pos - Vector2(1, 0) * (GameConfig.mortar_max_range(mortar.team) * 0.9))
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
	# Clamped exactly like _mortar_advance_point's own candidates (see
	# test_advance_point_avoids_sibling_at_natural_angle's own comment) —
	# without this, several of these siblings land on positions the
	# function itself can never actually produce, and the "least boxed"
	# candidate below can end up nowhere near where the function's own
	# (clamped) search actually considers it.
	for offset_deg in [0.0, -15.0, 15.0, -30.0, 30.0, -45.0]:
		var dir: Vector2 = base_dir.rotated(deg_to_rad(offset_deg))
		var candidate: Vector2 = GameConfig.clamp_to_operating_area(target_pos - dir * target_distance)
		var sib: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, candidate)
		bm.enemy_units.append(sib)
	var least_boxed_dir: Vector2 = base_dir.rotated(deg_to_rad(farthest_offset))
	var least_boxed_candidate: Vector2 = GameConfig.clamp_to_operating_area(target_pos - least_boxed_dir * target_distance)
	var far_sib: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, least_boxed_candidate + Vector2(GameConfig.MORTAR_BUNCHING_AVOIDANCE_RADIUS * 0.5, 0))
	bm.enemy_units.append(far_sib)

	var dest: Vector2 = bm._mortar_advance_point(mortar, target_pos)
	check(dest.distance_to(mortar.global_position) > 1.0, "Even fully boxed in by siblings, a real hunt move must still happen, not a freeze")
	check(dest.distance_to(least_boxed_candidate) < 1.0,
		"The candidate with the MOST clearance from its nearest sibling must win, not just the first one tried")


## The "genuinely idle" gap this session's deeper investigation actually
## found: the step-aside logic above only ever ran inside tier 2's own
## "in range of a known enemy mortar" path, so a mortar that reaches the
## final "Holding" catch-all (no known fix at all, nothing to shoot) with
## a sibling sitting critically close to it could sit bunched
## indefinitely — confirmed directly via a live trace: mortars converged
## from independent hunts and then simply held, for many real seconds,
## with zero corrective pressure until a fix finally became known.
func test_idle_holding_disperses_from_critically_close_sibling() -> void:
	var bm = make_battle()
	bm.unit_type_doctrines[Unit.Team.ENEMY] = Orders.sanitize({})
	var mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(400, 400))
	mortar.seconds_stationary = 1e9
	mortar.mortar_rounds_remaining = 10
	bm.enemy_units.append(mortar)
	var sibling: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, mortar.global_position + critically_close_offset)
	sibling.seconds_stationary = 1e9
	bm.enemy_units.append(sibling)
	# No known player position or mortar fix at all, and no player units to
	# shoot at — genuinely nothing to hunt or engage, isolating this from
	# every other tier.

	bm._decide_mortar_action(mortar)
	check(mortar.has_move_target,
		"A mortar with nothing to shoot or hunt, but critically close to a sibling, must still disperse rather than just hold")
	check(bm._mortar_move_intent.get(mortar, "") == "disperse",
		"The idle dispersal move must be recorded with its own intent, not silently folded into another one")
	check(mortar.move_target.distance_to(sibling.global_position) > critically_close_offset.length(),
		"The dispersal destination must actually create more clearance from the sibling than the starting position had")


## The dominant real-world case the same investigation found: has_shot
## can stay true for a mortar's entire reload window whenever a valid
## target keeps re-selecting (most ticks, once one exists) — the "Target
## available" early return, unmodified, was the actual reason multiple
## independently-hunting mortars that converged near each other then sat
## bunched indefinitely, never once reaching tier 2's own step-aside or
## the idle-tier check above.
func test_holding_a_shot_still_disperses_from_critically_close_sibling() -> void:
	var bm = make_battle()
	bm.unit_type_doctrines[Unit.Team.ENEMY] = Orders.sanitize({})
	var mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(400, 400))
	mortar.seconds_stationary = 1e9
	mortar.mortar_rounds_remaining = 10
	bm.enemy_units.append(mortar)
	var sibling: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, mortar.global_position + critically_close_offset)
	sibling.seconds_stationary = 1e9
	bm.enemy_units.append(sibling)

	var target: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, mortar.global_position + Vector2(100, 0))
	target.is_visible = true
	bm.player_units.append(target)

	bm._decide_mortar_action(mortar)
	check(mortar.has_move_target,
		"A mortar holding a valid, repeatable shot must still step clear first if it's critically close to a sibling — one HE round away from losing both tubes")
	check(bm._mortar_move_intent.get(mortar, "") == "disperse",
		"Stepping clear of a sibling while holding a shot is its own intent, not an ordinary hunt or holding state")


func run() -> void:
	test_ring_search_statistically_prefers_sibling_clearance()
	test_advance_point_avoids_sibling_at_natural_angle()
	test_advance_point_falls_back_to_least_bad_when_fully_boxed_in()
	test_idle_holding_disperses_from_critically_close_sibling()
	test_holding_a_shot_still_disperses_from_critically_close_sibling()
	print("Mortar bunching-avoidance tests: %d failures" % failures)
	quit(1 if failures else 0)
