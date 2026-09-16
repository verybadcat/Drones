extends SceneTree
## Guards a real, reported oscillation: "mortar is now oscillating" /
## "if the mortar moves, stops, fires, then moves in the opposite
## direction after firing, that is probably OK" / "what if you just put
## in a strong discouragement to any reversal while on the move?" — the
## user's own sequence of clarifications while this was investigated.
##
## Covers the deepest, most subtle root cause found: nearest_cover_point's
## reversal filters checked a cover ZONE's own center, but the actual
## destination handed back is a randomized point somewhere WITHIN that
## zone (see GameConfig._random_point_in_cover_zone) — for a zone
## meaningfully larger than MORTAR_NO_REVERSAL_RADIUS, a zone whose
## CENTER cleared every check could still hand back an actual point close
## enough to count as a real reversal, since the random draw inside it
## had no awareness of either check at all. Reproduced directly from a
## live trace's own real coordinates, not synthesized.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_reversal_avoidance.gd
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


## The exact real-world coordinates a live trace reproduced this bug at:
## an enemy mortar near (879, 337) with no known threats, whose own
## recently-used cover zone was large enough that a "clear" zone center
## still handed back an actual point within MORTAR_NO_REVERSAL_RADIUS of
## a remembered destination on a real fraction of draws before the fix.
func test_returned_point_never_lands_within_no_reversal_radius_of_a_large_zone() -> void:
	seed(778899)
	var from := Vector2(879.2907, 336.7322)
	var no_reversal: Array[Vector2] = [Vector2(879.5906, 370.6953), Vector2(879.2907, 336.7322)]
	var violations := 0
	const DRAWS := 40
	for i in DRAWS:
		var point: Vector2 = GameConfig.nearest_cover_point(from, 0.0, true, [], [], [], no_reversal)
		for p in no_reversal:
			if point.distance_to(p) < GameConfig.MORTAR_NO_REVERSAL_RADIUS:
				violations += 1
				break
	check(violations == 0,
		"nearest_cover_point returned a point within MORTAR_NO_REVERSAL_RADIUS of a remembered destination %d/%d times — the zone's own CENTER clearing the check isn't enough if the actual randomized point inside it doesn't" % [violations, DRAWS])


## The user's own direct correction: reversing direction is fine once a
## real fire mission happened in between. _mortar_fired_since_relocation
## must correctly gate the directional check off in that case.
func test_fired_since_relocation_flag_set_and_cleared_correctly() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(500, 500))
	mortar.mortar_rounds_remaining = 10
	bm.enemy_units.append(mortar)
	var target: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(510, 500))
	bm.player_units.append(target)

	check(not bm._mortar_fired_since_relocation.get(mortar, false),
		"A mortar that has never fired must not read as having fired since its last relocation")
	bm._launch_mortar_shot(mortar, target)
	check(bm._mortar_fired_since_relocation.get(mortar, false),
		"_launch_mortar_shot must record that this mortar has now fired since its last relocation")
	bm._remember_mortar_position(mortar, Vector2(600, 600))
	check(not bm._mortar_fired_since_relocation.get(mortar, false),
		"Accepting a fresh relocation must clear the fired-since-relocation flag — the NEXT leg has its own fresh fire-or-not status")


func run() -> void:
	test_returned_point_never_lands_within_no_reversal_radius_of_a_large_zone()
	test_fired_since_relocation_flag_set_and_cleared_correctly()
	print("Mortar reversal-avoidance tests: %d failures" % failures)
	quit(1 if failures else 0)
