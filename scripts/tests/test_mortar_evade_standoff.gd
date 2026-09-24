extends SceneTree
## Guards a direct user bug report from a live battle: "right now, mortar is
## going towards known enemy squads" — then, after pausing: "it should never
## have moved as close as it is." Traced against the real battle's own
## mortar_decision_snapshot.json: "Player Mortar 1" walked one continuous
## "evade" leg, 58 tactical seconds long, that got closer to a known enemy
## squad every single tick along the way.
##
## Root cause: GameConfig._ring_search_hidden_point weighs real LOS-blocking
## concealment at `score *= 3.0` and facing away from the threat picture at
## up to `score *= 1.5`, while standing off from a known threat's own
## MORTAR_CREW_OVERRUN_DANGER_RANGE was only ever a flat `score *= 0.5` — a
## soft, one-time penalty, not the same two-stage "prefer exclusively, only
## fall back when nothing clears it" treatment the function's other three
## soft preferences (floor_ok, critically_close, is_reversal/
## reverses_direction) already get. A hidden, threat-facing candidate
## (3.0 * 0.5 * up to 1.5) can trivially outscore a merely-safe, exposed one
## (1.0 * up to 1.5) — this actually happens with multiple known threats,
## since the search's own "face away from the threat picture" bearing is the
## AVERAGE of every known threat, so a candidate can face away from that
## average while still closing on one specific nearby threat.
##
## This exact (from, near-threat, far-threat) triple was found by randomized
## search against REAL map terrain (not a synthetic concealment stand-in) —
## it reproduced the bug in 127/500 trials (25%) before the fix, 0/500 after.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_evade_standoff.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var danger: float = GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE
	var from := Vector2(230.0, 250.0)
	var near_threat := Vector2(381.4298, 242.3109) # ~152 raw units away -- just outside the danger range
	var far_threat := Vector2(-645.2595, -1475.722) # pulls the "face away" bearing off-axis from near_threat
	var threats: Array[Vector2] = [near_threat, far_threat]

	var too_close := 0
	var trials := 500
	for i in trials:
		var result: Vector2 = GameConfig._ring_search_hidden_point(from, threats, false, true)
		if result.distance_to(near_threat) < danger or result.distance_to(far_threat) < danger:
			too_close += 1

	check(too_close == 0, "Expected zero too-close-to-known-threat relocation destinations with a clear alternative always available, got %d/%d" % [too_close, trials])

	print("Mortar evade standoff tests: %d failures" % failures)
	quit(1 if failures else 0)
