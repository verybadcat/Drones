extends SceneTree
## Direct user report: clicked "Retreat Now," the squads and mortar made it safely off, but the report
## window (score / AAR) popped up the instant the player's own spotter was killed mid-retreat — before
## there was any real chance to see it happen on screen, since the window covers the map immediately on
## battle_ended. A battle that ends on a KILL now holds its final frame for
## BattleManager.BATTLE_END_KILL_PAUSE_S real (wall-clock) seconds before battle_ended actually fires; a
## peaceful ending with nothing killed on the final tick (a withdrawal completing, a stalemate) is
## unaffected and still reports immediately — that kind of ending has no single, otherwise-invisible
## instant to actually witness the way a kill does.
##
## Run: godot --headless --path . --script scripts/tests/test_battle_end_kill_pause.gd
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

func run() -> void:
	await test_a_kill_ending_holds_the_final_frame_before_reporting()
	await test_a_peaceful_withdrawal_reports_immediately()
	print("Battle end kill pause tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_a_kill_ending_holds_the_final_frame_before_reporting() -> void:
	var bm = make_battle()
	var squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2.ZERO)
	bm.player_units.append(squad)
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(100, 0))
	bm.enemy_units.append(enemy)
	var fired := [false]
	bm.battle_ended.connect(func(_t): fired[0] = true)
	# The same transition + signal a real kill (Unit.take_hit -> _apply_crew_casualties/pips<=0) produces —
	# _make_unit already wired every unit's state_changed to BattleManager's own tracking, exactly as it
	# would for a real hit.
	squad.state = Unit.State.DESTROYED
	squad.state_changed.emit(squad) # sets _kill_happened_this_tick, exactly like a real kill mid-_process would
	bm._check_battle_end() # the same call _process makes each tick, without _process's OWN top-of-tick
	# reset in between — that reset runs BEFORE any of this tick's own combat, same as a real kill: it
	# happens mid-tick, after the reset already ran, not before it.
	check(bm.battle_over, "The battle itself is already over — score computed, ticking stopped")
	check(not fired[0], "But it does not report immediately on the same tick a kill just ended the battle")
	await bm.get_tree().create_timer(BattleManager.BATTLE_END_KILL_PAUSE_S + 0.2).timeout
	check(fired[0], "...and reports once the hold has actually elapsed")
	bm.combat_log.free()
	bm.free()


func test_a_peaceful_withdrawal_reports_immediately() -> void:
	var bm = make_battle()
	var squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2.ZERO)
	bm.player_units.append(squad)
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(100, 0))
	bm.enemy_units.append(enemy)
	var fired := [false]
	bm.battle_ended.connect(func(_t): fired[0] = true)
	squad.state = Unit.State.WITHDRAWN
	squad.state_changed.emit(squad)
	bm._check_battle_end()
	check(bm.battle_over, "Set-up: the battle is over here too")
	check(fired[0], "A battle that ends on a peaceful withdrawal (nothing killed this tick) reports right away, no hold")
	bm.combat_log.free()
	bm.free()
