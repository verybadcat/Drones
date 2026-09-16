extends SceneTree
## Guards a live bug report: enemy mortars (and squads) were seen firing
## at a player drone hundreds of meters away — an HE round has no way to
## engage a small, fast-moving aerial point target at all, and ordinary
## infantry small arms are reported as unable to even track and hit
## something this small and fast, altitude aside (see the design doc's
## own revision-log entry for the real-world sourcing). A DRONE must
## never be selectable as a target, by either weapon type, on either
## side, and hit_probability against one must be a hard, unconditional
## zero regardless of attacker.
##
## Run: godot --headless --path . --script scripts/tests/test_no_fire_at_drone.gd
const TestCombatLogScript := preload("res://scripts/tests/test_combat_log.gd")
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


func test_mortar_and_squad_never_select_a_drone_target() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(400, 400))
	mortar.mortar_rounds_remaining = 10
	bm.enemy_units.append(mortar)
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(400, 400))
	bm.enemy_units.append(squad)
	# Directly adjacent, fully visible, and the ONLY candidate at all —
	# the most favorable possible case for a bug to slip through.
	var drone: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(410, 410))
	drone.is_visible = true
	bm.player_units.append(drone)

	check(bm._pick_target(mortar, bm.player_units) == null,
		"A mortar must never select a drone as a target, even as the only candidate in range")
	check(bm._pick_target(squad, bm.player_units) == null,
		"A squad must never select a drone as a target, even directly adjacent and in LOS")
	bm.combat_log.free()
	bm.free()


func test_hit_probability_against_a_drone_is_a_hard_zero() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(0, 0))
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(0, 0))
	var drone: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(10, 10))
	check(CombatResolver.hit_probability(mortar, drone) == 0.0,
		"hit_probability against a drone must be a hard zero for a mortar attacker")
	check(CombatResolver.hit_probability(squad, drone) == 0.0,
		"hit_probability against a drone must be a hard zero for a squad attacker")
	bm.combat_log.free()
	bm.free()


func run() -> void:
	test_mortar_and_squad_never_select_a_drone_target()
	test_hit_probability_against_a_drone_is_a_hard_zero()
	print("No-fire-at-drone tests: %d failures" % failures)
	quit(1 if failures else 0)
