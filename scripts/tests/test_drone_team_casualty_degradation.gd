extends SceneTree
## Direct user instruction: "If the drone team takes one casualty, it should continue to function as a drone team. Might be slightly degraded
## but not much." A casualty no longer sends the team home (see test_drone_team_one_casualty.gd); it now costs a little: each casualty of
## the three makes the drones 7% less likely to notice what is in view and takes 10% of the drone-directed mortar's accuracy edge away.
## The team still launches and flies its drones.
##
## Run: godot --headless --path . --script scripts/tests/test_drone_team_casualty_degradation.gd
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

func spotted_fraction(casualties: int, trials: int) -> float:
	var observer := Unit.new()
	observer.kind = Unit.Kind.DRONE
	observer.team = Unit.Team.PLAYER
	observer.global_position = m(1000, 1000)
	observer.drone_operator_casualties = casualties
	var target := Unit.new()
	target.kind = Unit.Kind.SQUAD
	target.team = Unit.Team.ENEMY
	target.global_position = m(1300, 1000)
	root.add_child(observer)
	root.add_child(target)
	seed(99)
	var seen := 0
	for i in trials:
		if CombatResolver.roll_spot(observer, target, 3.0):
			seen += 1
	observer.free()
	target.free()
	return float(seen) / float(trials)

func run() -> void:
	GameConfig.set_active_map("pishchane")
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	bm.drone_team = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, m(-800, 1500))
	bm.player_units.append(bm.drone_team)
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(500, 1500))
	bm.player_units.append(mortar)
	var d: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, m(-500, 1500))
	bm.player_units.append(d)
	bm.active_drone = d
	var whole: float = bm._drone_directing_multiplier(mortar)
	bm.drone_team._apply_crew_casualties([], [], false) # one aimed shot: one casualty
	check(bm.drone_team.state == Unit.State.ACTIVE, "Setup: with one casualty the team is still ACTIVE (state %d)" % bm.drone_team.state)
	check(bm.drone_team.crew_casualties == 1, "Setup: one casualty (%d)" % bm.drone_team.crew_casualties)
	var one_down: float = bm._drone_directing_multiplier(mortar)
	check(one_down > 1.0, "With one casualty the drone still directs the mortar better than a plain spotter would (%.3f)" % one_down)
	check(one_down < whole, "...slightly less well than a whole team does (%.3f against %.3f)" % [one_down, whole])
	check((whole - one_down) <= 0.1 * (whole - 1.0) + 1e-6, "...losing no more than a tenth of the edge (%.3f of %.3f)" % [whole - one_down, whole - 1.0])
	var f0: float = spotted_fraction(0, 6000)
	var f1: float = spotted_fraction(1, 6000)
	check(f0 > 0.05 and f0 < 0.95, "Setup: the trial's spot chance is neither nothing nor certain (%.3f)" % f0)
	check(f1 < f0, "A drone flown by a team with one down notices a little less (%.3f against %.3f)" % [f1, f0])
	check(f1 > f0 * 0.8, "...but not much less (%.3f against %.3f)" % [f1, f0])
	bm.combat_log.free()
	bm.free()
	print("Drone team casualty degradation tests: %d failures" % failures)
	quit(1 if failures else 0)
