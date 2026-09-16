extends SceneTree
## Guards _check_enemy_mortar_isolated_retreat: the enemy's own mortar(s)
## must retreat once no enemy squad is still ACTIVE ("fighting"), even
## when _check_enemy_commander_retreat's own whole-force hopeless
## threshold was never crossed (squads can also retreat one at a time on
## their own individual casualty threshold — see that function's own doc
## comment for the real gap this closes).
##
## Run: godot --headless --path . --script scripts/tests/test_enemy_mortar_isolated_retreat.gd
const TestCombatLogScript = preload("res://scripts/tests/test_combat_log.gd")
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
	bm.combat_log = TestCombatLogScript.new()
	return bm


func test_mortar_holds_while_a_squad_is_still_active() -> void:
	var bm = make_battle()
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(500, 0))
	bm.enemy_units.append(squad)
	var mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2.ZERO)
	bm.enemy_units.append(mortar)

	bm._check_enemy_mortar_isolated_retreat()
	check(not bm.enemy_mortar_isolated_retreat_ordered, "Must not trigger while an enemy squad is still ACTIVE")
	check(mortar.state == Unit.State.ACTIVE, "The mortar must not be ordered to retreat while a squad still fights")


func test_mortar_retreats_once_no_squad_is_active_regardless_of_reason() -> void:
	for squad_state in [Unit.State.DESTROYED, Unit.State.RETREATING, Unit.State.SURRENDERED]:
		var bm = make_battle()
		var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(500, 0))
		squad.state = squad_state
		bm.enemy_units.append(squad)
		var mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2.ZERO)
		bm.enemy_units.append(mortar)

		bm._check_enemy_mortar_isolated_retreat()
		check(bm.enemy_mortar_isolated_retreat_ordered,
			"Must trigger once the only squad is no longer ACTIVE (state=%s)" % Unit.State.keys()[squad_state])
		check(mortar.state == Unit.State.RETREATING,
			"The mortar must be ordered to retreat once no squad is fighting any more (squad state=%s)" % Unit.State.keys()[squad_state])
		bm.combat_log.free()
		bm.free()


## _check_enemy_commander_retreat's own hopeless threshold is gated on the
## WHOLE force's casualty percentage — a real gap this whole mechanism
## exists to close: squads can retreat one at a time on their own
## individual threshold without that whole-force percentage ever
## crossing ENEMY_COMMANDER_RETREAT_THRESHOLD if the mortar itself stayed
## undamaged. Confirms the isolated check fires independently of that
## other trigger ever having fired at all.
func test_fires_independently_of_the_whole_force_hopeless_trigger() -> void:
	var bm = make_battle()
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(500, 0))
	squad.state = Unit.State.DESTROYED
	bm.enemy_units.append(squad)
	var mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2.ZERO)
	bm.enemy_units.append(mortar)
	check(not bm.enemy_general_retreat_ordered, "Sanity: the whole-force hopeless trigger must not have fired")
	bm._check_enemy_mortar_isolated_retreat()
	check(bm.enemy_mortar_isolated_retreat_ordered, "Must trigger even though the whole-force hopeless check never did")
	check(mortar.state == Unit.State.RETREATING, "The mortar must retreat once its only squad is gone")


## A real regression caught while implementing this: an enemy roster that
## never fielded any squads at all (a mortar-only doctrine, or a test
## harness scenario built around an isolated mortar target) has nothing
## to have "lost" — this must never fire for such a roster, since "zero
## ACTIVE squads" would otherwise be trivially true from the very first
## tick and instantly retreat a mortar that was never actually isolated
## from anything.
func test_never_fires_for_a_roster_with_no_squads_at_all() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2.ZERO)
	bm.enemy_units.append(mortar)
	bm._check_enemy_mortar_isolated_retreat()
	check(not bm.enemy_mortar_isolated_retreat_ordered, "Must not trigger for a roster that never had any squads at all")
	check(mortar.state == Unit.State.ACTIVE, "A mortar-only roster's mortar must not be retreated by this check")


func test_one_shot_does_not_reissue_every_tick() -> void:
	var bm = make_battle()
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(500, 0))
	squad.state = Unit.State.DESTROYED
	bm.enemy_units.append(squad)
	var mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2.ZERO)
	bm.enemy_units.append(mortar)
	bm._check_enemy_mortar_isolated_retreat()
	check(bm.enemy_mortar_isolated_retreat_ordered, "First call must trigger once its only squad is gone")
	var move_target_after_first: Vector2 = mortar.move_target
	# A second call must be a pure no-op — re-ordering retreat every tick
	# would reset the crew's own "pack up" delay right back to zero.
	bm._check_enemy_mortar_isolated_retreat()
	check(mortar.move_target == move_target_after_first, "A second call must not re-issue the retreat order")


func run() -> void:
	test_mortar_holds_while_a_squad_is_still_active()
	test_mortar_retreats_once_no_squad_is_active_regardless_of_reason()
	test_fires_independently_of_the_whole_force_hopeless_trigger()
	test_never_fires_for_a_roster_with_no_squads_at_all()
	test_one_shot_does_not_reissue_every_tick()
	print("Enemy mortar isolated-retreat tests: %d failures" % failures)
	quit(1 if failures else 0)
