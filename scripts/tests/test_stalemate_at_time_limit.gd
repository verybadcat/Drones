extends SceneTree
## Direct user report from a live battle: "Current battle should have been scored
## as a stalemate. It says Position held." The battle had run to
## GameConfig.BATTLE_TIME_LIMIT (then 4 tactical hours) with both sides still ACTIVE;
## the limit ended it like any other end and "the player still has an active
## unit" read as Position held (+20, verdict SUCCESSFUL DEFENSE). Running out the
## clock with both sides still on the field decides nothing: a stalemate.
##
## Run: godot --headless --path . --script scripts/tests/test_stalemate_at_time_limit.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func battle(player_state: Unit.State, enemy_state: Unit.State, elapsed: float):
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var ours: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2.ZERO)
	bm.player_units.append(ours)
	ours.state = player_state
	var theirs: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(500, 0))
	bm.enemy_units.append(theirs)
	theirs.state = enemy_state
	bm.scenario_elapsed_time = elapsed
	return bm

func finish(bm) -> Dictionary:
	bm._check_battle_end()
	var out := {"over": bm.battle_over, "result": bm.battle_result, "log": bm.combat_log.captured.duplicate()}
	bm.combat_log.free()
	bm.free()
	return out

func run() -> void:
	var limit: float = GameConfig.BATTLE_TIME_LIMIT

	# The reported case: time runs out, both sides still fighting-fit.
	var r: Dictionary = finish(battle(Unit.State.ACTIVE, Unit.State.ACTIVE, limit))
	check(r.over, "The time limit ends the battle")
	check(r.result.inputs.position == "stalemate" and r.result.verdict == "STALEMATE", "Both sides still ACTIVE at the limit is a stalemate (got %s / %s)" % [r.result.inputs.position, r.result.verdict])
	check(r.result.stalemate and is_equal_approx(BattleScore.score({"position": r.result.inputs.position}), 0.0), "...which scores 0 for the position, not +20")
	check(r.log.any(func(t): return "Time limit reached" in t and "stalemate" in t), "...and the combat log says why (got %s)" % str(r.log))

	# Before the limit nothing ends it.
	r = finish(battle(Unit.State.ACTIVE, Unit.State.ACTIVE, limit - 60.0))
	check(not r.over, "Before the time limit a fight between two active sides goes on")

	# Time up but the enemy is already broken (only retreating): the fight WAS decided.
	r = finish(battle(Unit.State.ACTIVE, Unit.State.RETREATING, limit))
	check(r.over and r.result.inputs.position == "held", "Time up with the enemy pulling out is still Position held (got %s)" % r.result.inputs.position)
	r = finish(battle(Unit.State.ACTIVE, Unit.State.WITHDRAWN, limit))
	check(r.over and r.result.inputs.position == "held", "Everyone on the enemy side gone is a hold, however it ended (got %s)" % r.result.inputs.position)

	# Time up but we are the broken side: lost, not a stalemate.
	r = finish(battle(Unit.State.RETREATING, Unit.State.ACTIVE, limit))
	check(r.over and r.result.inputs.position == "lost", "Time up with our force pulling out is Position lost (got %s)" % r.result.inputs.position)

	print("Stalemate at time limit tests: %d failures" % failures)
	quit(1 if failures else 0)
