extends SceneTree
## Guards a direct user correction: "For our drones, a fleeing enemy
## mortar should be a lower priority target than enemy squads... at least
## than squads that are not fleeing."
##
## _drone_search_target's own "Finishing a retreating contact" tier
## already stated exactly this intent in its own comment ("a low-priority
## distraction next to whatever's still actually fighting"), but compared
## a flat TARGET_PRIORITY_RETREATING_ENEMY_LOW constant (2.0) against
## best_squad_score's own continuous, distance-based scale (0 to
## TARGET_PRIORITY_SQUAD_MAX, 10.0) — a real, currently-visible, still-
## ACTIVE squad merely distant from any friendly unit (score under 2)
## could still lose that comparison to a fleeing straggler, backwards
## from the stated principle. Fixed by capping the retreating tier's
## score to never exceed whatever a real active squad already scored.
##
## Run: godot --headless --path . --script scripts/tests/test_drone_deprioritizes_fleeing_enemy.gd
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


## The exact reported shape: a fleeing (RETREATING) enemy mortar, visible,
## versus an ACTIVE, visible enemy squad placed far enough from any
## friendly unit that its own individual danger score is near zero —
## well under TARGET_PRIORITY_RETREATING_ENEMY_LOW. The active squad must
## still win.
func test_low_danger_active_squad_still_beats_a_fleeing_mortar() -> void:
	var bm = make_battle()
	# Deliberately NOT a friendly mortar: _flank_watch_candidates only
	# returns anything when a friendly mortar exists, and its own standing
	# priority (30.0) would dominate both tiers under test here regardless
	# of this fix, confounding the comparison entirely (confirmed directly
	# — the very first version of this test picked a flank-watch point,
	# passing and failing identically with and without the fix). A plain
	# friendly squad still gives _squad_danger_priority a real reference
	# point to measure distance from, without triggering that unrelated
	# standing duty.
	var friendly: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(0, 0))
	bm.player_units.append(friendly)
	bm.active_drone = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(0, 0))

	var fleeing_mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(500, 500))
	bm.enemy_units.append(fleeing_mortar)
	fleeing_mortar.state = Unit.State.RETREATING
	fleeing_mortar.is_visible = true

	# Far from the only friendly unit -- well beyond SQUAD_DANGER_RANGE,
	# so _squad_danger_priority scores this squad at (or very near) 0,
	# the lowest a real active squad can score.
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(GameConfig.SQUAD_DANGER_RANGE * 5.0, 0))
	bm.enemy_units.append(squad)
	squad.is_visible = true
	check(bm._squad_danger_priority(squad) < GameConfig.TARGET_PRIORITY_RETREATING_ENEMY_LOW,
		"Test setup check: the squad's own danger score must be below the flat retreating-enemy priority for this test to mean anything")

	var target: Vector2 = bm._drone_search_target()
	check(target.distance_to(squad.global_position) < target.distance_to(fleeing_mortar.global_position),
		"A real, currently-visible ACTIVE squad must outrank a fleeing enemy mortar for drone attention, even when that squad's own individual danger score is very low (chosen target %s, squad at %s, fleeing mortar at %s)" % [target, squad.global_position, fleeing_mortar.global_position])


func run() -> void:
	test_low_danger_active_squad_still_beats_a_fleeing_mortar()
	print("Drone deprioritizes-fleeing-enemy tests: %d failures" % failures)
	quit(1 if failures else 0)
