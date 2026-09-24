extends SceneTree
## Direct user report from a live battle: "now the mortar retreated off map. I don't
## understand that at all ... I also don't understand why the enemy one retreated."
## Every route into a retreat used to leave the same last order reason, "Withdrawal
## ordered.", in the debug snapshots, so a mortar found WITHDRAWN could not be
## explained afterward (a crew fleeing as a last resort, a mortar left without
## squads and a general retreat were indistinguishable). Each route now records its
## own reason (Unit.order_retreat's `reason`).
##
## Run: godot --headless --path . --script scripts/tests/test_retreat_reasons_recorded.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(v: float) -> float:
	return v * GameConfig.PIXELS_PER_METER

func make_battle():
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	return bm

func cleanup(bm) -> void:
	bm.combat_log.free()
	bm.free()

func run() -> void:
	test_a_crew_fleeing_as_a_last_resort_says_why()
	test_a_mortar_left_without_squads_says_so()
	test_a_general_retreat_says_so()
	test_the_default_is_unchanged()
	print("Retreat reason tests: %d failures" % failures)
	quit(1 if failures else 0)


## The player's mortar as found in the live battle: out of ammunition, spotted, no
## place to hide.
func test_a_crew_fleeing_as_a_last_resort_says_why() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(m(-1260), m(2459)))
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = 0
	mortar.is_visible = true
	bm._update_mortar_decisions()
	check(mortar.state != Unit.State.ACTIVE, "Setup: a dry, spotted mortar with nowhere to hide leaves the field")
	var r: String = mortar.last_order_reason
	check("last resort" in r and "out of ammunition" in r and "spotted" in r, "The reason names what got it there (got '%s')" % r)
	check(r != "Withdrawal ordered.", "...instead of the generic 'Withdrawal ordered.'")
	cleanup(bm)
	# An enemy mortar spotted with ammunition says that instead (no 'out of ammunition').
	bm = make_battle()
	var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(m(4984), m(770)))
	bm.enemy_units.append(em)
	em.mortar_rounds_remaining = 20
	em.is_visible = true
	bm._mortar_flee_as_last_resort(em)
	r = em.last_order_reason
	check("last resort" in r and "spotted" in r and not ("out of ammunition" in r), "An armed, spotted mortar's reason says only that (got '%s')" % r)
	cleanup(bm)


## The enemy mortar pulling back because no enemy squad is left fighting.
func test_a_mortar_left_without_squads_says_so() -> void:
	var bm = make_battle()
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(m(3000), m(1500)))
	bm.enemy_units.append(squad)
	squad.state = Unit.State.WITHDRAWN
	var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(m(4900), m(1000)))
	bm.enemy_units.append(em)
	bm._check_enemy_mortar_isolated_retreat()
	check(em.state == Unit.State.RETREATING, "Setup: the isolated mortar pulls back")
	check("No enemy squad left fighting" in em.last_order_reason, "The reason says no squad was left fighting (got '%s')" % em.last_order_reason)
	cleanup(bm)


func test_a_general_retreat_says_so() -> void:
	var bm = make_battle()
	var squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(m(500), m(1500)))
	bm.player_units.append(squad)
	bm.order_general_retreat()
	check(squad.state == Unit.State.RETREATING, "Setup: the squad retreats")
	check("general retreat" in squad.last_order_reason, "The commander's general retreat is named (got '%s')" % squad.last_order_reason)
	cleanup(bm)


## Callers that do not say why keep the old wording.
func test_the_default_is_unchanged() -> void:
	var bm = make_battle()
	var squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(m(500), m(1500)))
	bm.player_units.append(squad)
	squad.order_retreat()
	check(squad.last_order_reason == "Withdrawal ordered.", "With no reason given the old text stands (got '%s')" % squad.last_order_reason)
	cleanup(bm)
