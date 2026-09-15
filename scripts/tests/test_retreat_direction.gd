extends SceneTree
## Guards GameConfig._prefer_retreat_direction — shared by nearest_cover_
## point/safest_cover_point/retreat_cover_point_toward, so a fix here
## covers every retreating unit kind at once.
##
## A real, user-reported bug, TWICE: "I hit retreat now. The mortar started
## my moving forwards a fair distance. Then it retreated." Confirmed
## directly at the mortar's own real map deployment position — retreat_
## cover_point_toward consistently chose a cover zone ~90-115m EAST (toward
## the enemy) of the mortar's current position as its first "go to cover"
## waypoint, because the old lenient-tolerance fallback's small forward
## allowance let that close wrong-side candidate outrank a real, reachable
## correct-side one that existed further out but well within the same
## overall travel budget the code was already willing to pay.
##
## Reported again after that fix shipped, this time ~1000m forward — real
## battle geometry (not this file's own simpler hand-built scenarios)
## found a SECOND, deeper gap: when _prefer_clear_path strips out every
## correct-side candidate (a building blocks the straight line to each
## one), the old code gave up on direction ENTIRELY and returned every
## remaining wrong-side candidate with no preference for the least-wrong
## one — see _prefer_retreat_direction's own doc comment for the exact
## repro and the "prefer least-wrong, budgeted" fix.
##
## Run: godot --headless --path . --script scripts/tests/test_retreat_direction.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func _candidate(x: float, y: float) -> Dictionary:
	return {"zone": {"center": Vector2(x, y)}}


## The exact reported shape: a close candidate on the WRONG side and a
## farther-but-still-reachable candidate on the CORRECT side. The correct
## one must win outright, however much closer the wrong one is.
func test_correct_side_preferred_over_close_wrong_side() -> void:
	var from := Vector2(0, 0)
	var wrong_side_close := _candidate(50.0, 0.0) # 50px "east" — forward for a west-retreating unit
	var right_side_reachable := _candidate(-300.0, 0.0) # 300px "west" — correct, well within budget
	var candidates: Array[Dictionary] = [wrong_side_close, right_side_reachable]
	var result := GameConfig._prefer_retreat_direction(candidates, from, -1.0)
	var has_right := false
	var has_wrong := false
	for c in result:
		if c.zone.center.x < 0: has_right = true
		if c.zone.center.x > 0: has_wrong = true
	check(has_right, "A reachable correct-side candidate must survive the filter")
	check(not has_wrong, "A close wrong-side candidate must NOT be preferred over a reachable correct-side one")


## The ORIGINAL historical case this whole mechanism was built for
## (see RETREAT_DIRECTION_MAX_EXTRA_M's own doc comment): a near correct-
## side option and a far correct-side outlier, nothing else nearby — the
## outlier must still be excluded, not just included alongside the near
## one for a weighted-random pick to occasionally choose anyway.
func test_near_correct_side_excludes_far_correct_side_outlier() -> void:
	var from := Vector2(0, 0)
	var near := _candidate(-638.0 * GameConfig.PIXELS_PER_METER, 0.0)
	var far := _candidate(-2400.0 * GameConfig.PIXELS_PER_METER, 0.0)
	var candidates: Array[Dictionary] = [near, far]
	var result := GameConfig._prefer_retreat_direction(candidates, from, -1.0)
	check(result.size() == 1 and is_same(result[0], near),
		"A far correct-side outlier must still be excluded when a much closer correct-side option exists (got %d candidates)" % result.size())


## With NOTHING at all on the correct side, the nearby wrong-side option
## must still be returned (never an empty result) — a retreating unit
## needs SOME answer rather than none when genuinely nothing better exists.
func test_no_correct_side_falls_back_to_lenient_nearby() -> void:
	var from := Vector2(0, 0)
	var only_wrong_side_close := _candidate(50.0, 0.0)
	var candidates: Array[Dictionary] = [only_wrong_side_close]
	var result := GameConfig._prefer_retreat_direction(candidates, from, -1.0)
	check(result.size() == 1, "With no correct-side option anywhere, the nearby wrong-side one must still be returned, not an empty result")


## The exact second reported shape (see this file's own doc comment): with
## NOTHING at all on the correct side, and more than one wrong-side option
## at meaningfully different distances, the badly-wrong-direction outlier
## must be excluded, not returned alongside the least-wrong one for some
## LATER, direction-blind tie-break to pick indifferently between them.
func test_no_correct_side_prefers_least_wrong_over_worse_outlier() -> void:
	var from := Vector2(0, 0)
	var mildly_wrong := _candidate(50.0, 0.0) # 50px east — the least-wrong option
	var badly_wrong := _candidate(1000.0, 0.0) # 1000px east — a real repro found ~950m worse than this
	var candidates: Array[Dictionary] = [mildly_wrong, badly_wrong]
	var result := GameConfig._prefer_retreat_direction(candidates, from, -1.0)
	var has_mild := false
	var has_bad := false
	for c in result:
		if c.zone.center.x < 500.0: has_mild = true
		if c.zone.center.x >= 500.0: has_bad = true
	check(has_mild, "The least-wrong-direction candidate must survive")
	check(not has_bad, "A badly-wrong-direction outlier must not ride along just because nothing correct-side exists at all (got %d candidates)" % result.size())


## End-to-end reproduction of the exact reported scenario, at the real
## mortar's real map deployment position — the destination a retreat
## order would actually walk to first must never be forward of where the
## mortar currently is. Run several times (weighted-random pool pick
## inside retreat_cover_point_toward) for confidence beyond one draw.
func test_real_map_mortar_retreat_never_goes_forward() -> void:
	var start: Vector2 = GameConfig.CURRENT_MAP.player.mortar_default_position
	var enemies: Array[Vector2] = [start + Vector2(400, 0)]
	var reference := Vector2(-GameConfig.WEST_FLANK_WIDTH_PX, start.y)
	for i in 20:
		var dest: Vector2 = GameConfig.retreat_cover_point_toward(start, reference, enemies, -1.0, true)
		check(dest.x <= start.x,
			"A player mortar's retreat destination must never be forward (east) of its own current position (got dx=%.1fm on draw %d)" % [(dest.x - start.x) / GameConfig.PIXELS_PER_METER, i])


func run() -> void:
	test_correct_side_preferred_over_close_wrong_side()
	test_near_correct_side_excludes_far_correct_side_outlier()
	test_no_correct_side_falls_back_to_lenient_nearby()
	test_no_correct_side_prefers_least_wrong_over_worse_outlier()
	test_real_map_mortar_retreat_never_goes_forward()
	if failures == 0:
		print("Retreat direction tests: 0 failures")
	else:
		print("Retreat direction tests: %d failures" % failures)
	quit(1 if failures else 0)
