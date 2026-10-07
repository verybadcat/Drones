extends SceneTree
## Direct user instruction: "One casualty should not cause the drone team to withdraw." A drone team is three people; with one down the
## hold-or-withdraw roll gave a hold chance of two-thirds even with no enemy near, so a third of such hits sent it home. Now one casualty
## never does (an enemy closing to overrun range still can, that being danger and not the casualty); two still can.
##
## Run: godot --headless --path . --script scripts/tests/test_drone_team_one_casualty.gd
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

## How many of `trials` fresh drone teams, each hit by `hits` aimed shots (a casualty apiece), are still ACTIVE afterwards.
func still_active(bm, hits: int, trials: int, enemy_near: bool) -> int:
	var held := 0
	for i in trials:
		var team: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, m(-800, 1500))
		bm.player_units.append(team)
		var known: Array[Vector2] = []
		if enemy_near:
			known.append(team.global_position + m(40, 0))
		for h in hits:
			if team.state == Unit.State.ACTIVE:
				team._apply_crew_casualties(known, [], false)
		if team.state == Unit.State.ACTIVE and team.crew_casualties == hits:
			held += 1
		bm.player_units.erase(team)
		team.free()
	return held

func run() -> void:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	seed(20261006)
	check(still_active(bm, 1, 200, false) == 200, "One casualty, nothing near: the drone team holds every time (%d of 200)" % still_active(bm, 1, 200, false))
	var two: int = still_active(bm, 2, 300, false)
	check(two < 300, "Setup: two casualties can still send it home (%d of 300 held)" % two)
	check(two > 0, "...but not always (%d of 300 held)" % two)
	var near: int = still_active(bm, 1, 200, true)
	check(near < 200, "One casualty with an enemy already on top of it can still send it home: that is the danger, not the hit (%d of 200 held)" % near)
	bm.combat_log.free()
	bm.free()
	print("Drone team one-casualty tests: %d failures" % failures)
	quit(1 if failures else 0)
