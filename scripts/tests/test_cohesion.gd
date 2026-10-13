extends SceneTree
## Cohesion for a squad that is cut off, mild on purpose. User: "Cohesion for cut-off yes, but make it mild. This is a tactical surround,
## not a strategic one." A squad's cohesion is worn down while enemy squads it knows of hold two opposite sides or more of it, faster
## while pinned, recovers when they do not, and falls with each person lost; it lowers the casualty threshold at which it breaks off
## (50% becomes at worst 30%) and raises its chance of laying down its arms when overrun, by at most half.
##
## Run: godot --headless --path . --script scripts/tests/test_cohesion.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(x: float, y: float = 0.0) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

func make() -> Dictionary:
	GameConfig.set_active_map("voznesensk")
	GameConfig._build_terrain_grid()
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.scenario_elapsed_time = 1000.0
	return {"bm": bm, "open": m(-5000, -5000)}

func unit(c: Dictionary, team: Unit.Team, kind: Unit.Kind, point: Vector2) -> Unit:
	var u: Unit = c.bm._make_unit(team, kind, point)
	if team == Unit.Team.PLAYER:
		c.bm.player_units.append(u)
	else:
		c.bm.enemy_units.append(u)
	return u

func known_to_player(f: Unit) -> void:
	f.player_has_been_sighted = true
	f.player_known_position = f.global_position
	f.player_known_state = Unit.State.ACTIVE
	f.player_known_pips = f.pips

func cleanup(c: Dictionary) -> void:
	c.bm.combat_log.free()
	c.bm.free()

func minutes(c: Dictionary, n: float) -> void:
	for i in int(n * 6.0):
		c.bm._update_cohesion(10.0)

func run() -> void:
	var c := make()
	var bm: BattleManager = c.bm
	var o: Vector2 = c.open
	var squad: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, o)
	check(squad.cohesion == 1.0, "A squad starts whole")

	# 1. one enemy squad, or two on the same side: no wear
	var e1: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, o + m(200, 0))
	known_to_player(e1)
	minutes(c, 10.0)
	check(squad.cohesion == 1.0, "One enemy squad on one side wears nothing (%.2f)" % squad.cohesion)
	var e2: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, o + m(220, 40))
	known_to_player(e2)
	minutes(c, 10.0)
	check(squad.cohesion == 1.0, "Two on the same side: nothing (%.2f)" % squad.cohesion)

	# 2. on opposite sides: worn down slowly; pinned, twice as fast; mild
	e2.global_position = o + m(-200, 0)
	known_to_player(e2)
	minutes(c, 5.0)
	var after_five: float = squad.cohesion
	check(absf(after_five - (1.0 - 5.0 * GameConfig.COHESION_DECAY_PER_MIN)) < 0.02, "Held on two opposite sides for five minutes: down by about %.2f (%.2f)" % [5.0 * GameConfig.COHESION_DECAY_PER_MIN, after_five])
	squad.pinned = true
	minutes(c, 5.0)
	var pinned_drop: float = after_five - squad.cohesion
	check(pinned_drop > 1.7 * 5.0 * GameConfig.COHESION_DECAY_PER_MIN * 0.99 and pinned_drop < 2.1 * 5.0 * GameConfig.COHESION_DECAY_PER_MIN, "Pinned, twice as fast (%.2f in five minutes)" % pinned_drop)
	check(after_five > 0.7, "...and mild: five minutes surrounded takes under a third (%.2f)" % after_five)
	squad.pinned = false

	# 3. the floor is zero, and it returns when they go
	minutes(c, 60.0)
	check(squad.cohesion == 0.0, "Surrounded for an hour it is at its floor, no lower (%.2f)" % squad.cohesion)
	e1.state = Unit.State.WITHDRAWN
	e1.player_known_state = Unit.State.WITHDRAWN
	e2.state = Unit.State.WITHDRAWN
	e2.player_known_state = Unit.State.WITHDRAWN
	minutes(c, 4.0)
	check(squad.cohesion > 0.3 and squad.cohesion < 0.5, "Four minutes after they have gone it has come back about %.2f (%.2f)" % [4.0 * GameConfig.COHESION_RECOVERY_PER_MIN, squad.cohesion])
	minutes(c, 30.0)
	check(squad.cohesion == 1.0, "...and in the end it is whole again")

	# 4. a person lost
	squad.pips = 9
	squad.cohesion_last_pips = 9
	bm._update_cohesion(1.0)
	squad.pips = 6
	bm._update_cohesion(1.0)
	check(absf(squad.cohesion - (1.0 - 3.0 * GameConfig.COHESION_PER_CASUALTY)) < 0.01, "Three people lost take a little (%.2f)" % squad.cohesion)

	# 5. what it does: the threshold for breaking off, at most 50% -> 30%; the chance of laying down arms, at most half as much again
	squad.cohesion = 1.0
	squad.pips = 9
	squad.max_pips = 9
	squad.retreat_threshold = 0.5
	squad.pips = 5 # 44% lost: not yet
	squad._check_retreat([], [])
	check(squad.state == Unit.State.ACTIVE, "A whole squad at 44% lost holds on")
	squad.cohesion = 0.0
	squad.pips = 6 # 33% lost: past a threshold lowered to 30%
	squad._check_retreat([], [])
	check(squad.state == Unit.State.RETREATING, "One with no cohesion left breaks at 33% (the threshold is then 30%)")
	var low_threshold: float = 0.5 * (1.0 - GameConfig.COHESION_BREAK_SHIFT)
	check(low_threshold >= 0.29 and low_threshold <= 0.31, "...never lower than that (%.2f)" % low_threshold)
	var foe: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, o + m(5, 0))
	var ally: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, o + m(400, 0))
	var holder: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, o + m(20, 0))
	holder.cohesion = 1.0
	var whole: float = bm._squad_surrender_chance(holder)
	holder.cohesion = 0.0
	var broken: float = bm._squad_surrender_chance(holder)
	check(whole > 0.0 and broken > whole and broken <= 1.5 * whole + 0.0001, "No cohesion raises the chance of laying down arms by at most half as much again (%.3f against %.3f)" % [broken, whole])
	cleanup(c)

	print("Cohesion tests: %d failures" % failures)
	quit(1 if failures else 0)
