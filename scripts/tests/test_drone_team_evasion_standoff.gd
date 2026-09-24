extends SceneTree
## Guards a direct user bug report: "drone team seems to be fleeing towards
## enemy squads? It may be fleeing from something. But seeing enemy squads
## in front of it should cause it to reconsider."
##
## This is the same underlying defect test_mortar_evade_standoff.gd guards
## (GameConfig._ring_search_hidden_point's concealment/facing bonuses could
## outscore the standoff-from-known-threat preference) surfacing through a
## SECOND real caller: BattleManager._update_drone_team_evasion routes
## through the exact same shared search. The mortar fix alone didn't cover
## this — it hardcoded MORTAR_CREW_OVERRUN_DANGER_RANGE (750m, the right
## scale for "close enough to physically overrun a mortar crew") directly
## inside the search, but the drone team's own trigger already uses a much
## larger scale, DRONE_TEAM_EVASION_RANGE (1200m) — a destination well
## outside 750m of a known enemy squad could still read as "walking toward
## it" at the drone team's own relevant distance. Fixed by threading
## `danger_range` through nearest_hidden_point/_ring_search_hidden_point as
## a caller-supplied parameter instead of a hardcoded constant.
##
## This exact (from, near-threat, far-threat) triple was found by randomized
## search against REAL map terrain, at DRONE_TEAM_EVASION_RANGE scale — it
## reproduced the bug in 60/60 trials before this fix (with danger_range
## hardcoded to the mortar's own tighter 750m), 0/500 after.
##
## Run: godot --headless --path . --script scripts/tests/test_drone_team_evasion_standoff.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var danger: float = GameConfig.DRONE_TEAM_EVASION_RANGE
	var from := Vector2(230.0, 250.0)
	var near_threat := Vector2(410.2372, 370.6412)
	var far_threat := Vector2(-1767.555, -214.515)
	var threats: Array[Vector2] = [near_threat, far_threat]

	var too_close := 0
	var trials := 500
	for i in trials:
		# Same call shape _update_drone_team_evasion uses: avoid_buildings=
		# false, urgent=false, danger_range=DRONE_TEAM_EVASION_RANGE.
		var result: Vector2 = GameConfig._ring_search_hidden_point(from, threats, false, false, [], Vector2.INF, INF, 0.0, [], [], Vector2.ZERO, Vector2.INF, danger)
		if result.distance_to(near_threat) < danger or result.distance_to(far_threat) < danger:
			too_close += 1

	check(too_close == 0, "Expected zero too-close-to-known-threat evasion destinations at drone-team scale with a clear alternative always available, got %d/%d" % [too_close, trials])

	print("Drone team evasion standoff tests: %d failures" % failures)
	quit(1 if failures else 0)
