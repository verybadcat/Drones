extends SceneTree
## Direct user report: "Enemy mortars were still shooting at our spotter when enemy squads were nearby,
## and friendly squads were not. Instead, the enemy should have tasked an enemy squad with that, as the
## squad could have done it easily." A lone forward observer is unarmed and undefended — infantry can
## simply walk over and deal with it directly, at no cost to a scarce HE round, whenever a squad is free
## and close enough to (see _spotter_hunt_candidate's own doc comment for that exact availability check,
## reused here rather than a second, looser one). This only withholds the MORTAR's own fire on the spotter
## when a squad is available; a squad itself engaging the spotter directly (its own ordinary "stay and
## fight" targeting) is completely unaffected and is exactly the desired outcome.
##
## Scoping note: _spotter_hunt_candidate (and so this fix) is ENEMY-side only, matching that function's own
## existing scope — nothing in this game currently spawns an ENEMY spotter for a symmetric PLAYER mortar to
## defer on, so that mirror direction isn't built or tested here.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_defers_spotter_to_squad.gd
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

## A known, visible spotter plus a free, nearby enemy squad able to deal with it directly (matching
## _spotter_hunt_candidate's own eligibility exactly).
func setup_with_available_squad(bm) -> Dictionary:
	var mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2.ZERO)
	bm.enemy_units.append(mortar)
	var spotter: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, Vector2(m(1000.0), 0))
	bm.player_units.append(spotter)
	spotter.is_visible = true # the mortar itself can see it right now
	spotter.enemy_has_been_sighted = true
	spotter.enemy_known_position = spotter.global_position
	spotter.enemy_known_state = Unit.State.ACTIVE
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, spotter.global_position + Vector2(-m(200.0), 0))
	squad.sought_cover = true
	squad.village_reached = true
	bm.enemy_units.append(squad)
	return {"mortar": mortar, "spotter": spotter, "squad": squad}

func run() -> void:
	test_mortar_does_not_target_spotter_when_a_squad_can_handle_it()
	test_mortar_still_targets_spotter_when_no_squad_is_free()
	test_mortar_still_targets_a_real_squad_over_deferring()
	test_a_squad_can_still_engage_the_spotter_itself()
	print("Mortar-defers-spotter-to-squad tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_mortar_does_not_target_spotter_when_a_squad_can_handle_it() -> void:
	var bm = make_battle()
	var c: Dictionary = setup_with_available_squad(bm)
	check(bm._spotter_hunt_candidate() == c.squad, "Setup: the squad is available and would be tasked with the spotter")
	var target: Unit = bm._pick_target(c.mortar, bm.player_units)
	check(target == null, "The mortar does not target the spotter when a squad is free to deal with it directly")
	cleanup(bm)


## Same scene, but the squad is too far off (beyond SQUAD_DANGER_RANGE) to be a real candidate — nothing
## is available to deal with the spotter on the ground, so the mortar still may.
func test_mortar_still_targets_spotter_when_no_squad_is_free() -> void:
	var bm = make_battle()
	var c: Dictionary = setup_with_available_squad(bm)
	c.squad.global_position = c.spotter.global_position + Vector2(GameConfig.SQUAD_DANGER_RANGE * 2.0, 0)
	check(bm._spotter_hunt_candidate() == null, "Setup: too far off to be a real candidate")
	var target: Unit = bm._pick_target(c.mortar, bm.player_units)
	check(target == c.spotter, "With nothing free to deal with it on the ground, the mortar may still target the spotter")
	cleanup(bm)


## A real, armed player squad in range is still picked over deferring on the spotter — this fix only ever
## withholds fire when the alternative is otherwise "shoot the spotter or shoot nothing at all."
func test_mortar_still_targets_a_real_squad_over_deferring() -> void:
	var bm = make_battle()
	var c: Dictionary = setup_with_available_squad(bm)
	var real_squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(m(1500.0), 0))
	bm.player_units.append(real_squad)
	real_squad.is_visible = true
	var target: Unit = bm._pick_target(c.mortar, bm.player_units)
	check(target == real_squad, "A real, armed squad is still a valid, preferred target regardless of the spotter deferral")
	cleanup(bm)


## The exact ground engagement this fix defers TO: an enemy squad within its own ordinary engagement range
## and line of sight of a visible spotter still picks it as `shootable`, completely unaffected — the
## exclusion added to _pick_target only applies when `unit.kind == MORTAR`.
func test_a_squad_can_still_engage_the_spotter_itself() -> void:
	var bm = make_battle()
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2.ZERO)
	bm.enemy_units.append(squad)
	var spotter: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, Vector2(m(100.0), 0))
	bm.player_units.append(spotter)
	spotter.is_visible = true
	var target: Unit = bm._pick_target(squad, bm.player_units)
	check(target == spotter, "A squad in range and LOS still engages the spotter directly, unaffected by the mortar-only deferral")
	cleanup(bm)
