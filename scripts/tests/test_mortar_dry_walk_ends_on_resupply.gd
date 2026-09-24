extends SceneTree
## Direct user report from a live battle: "why is the mortar falling back? It looks
## like it has a good shot at the enemy mortar" and, once it did fire, "it took way
## too long." The crew had run dry and was walking to meet an inbound resupply run
## ("linkup"). The run delivered 20 rounds — but the sticky no-ammunition walk carried
## on to its stale destination, and a mortar under way never has a shot (a crew must
## sit stationary GameConfig.MORTAR_SETUP_TEARDOWN_TIME before it can fire), so it
## walked away from a visible enemy mortar in range until it arrived and set up.
## Now, once ammunition is back, the no-ammunition walks ("linkup", "out_of_ammo")
## end and the ladder decides afresh; the survival walks (evade, conceal) do not.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_dry_walk_ends_on_resupply.gd
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

## A friendly mortar walking west with `intent`, holding `rounds`, and a visible
## enemy mortar in range.
func make_battle(rounds: int, intent: String):
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(m(-650), m(2145)))
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = rounds
	var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(m(3234), m(422)))
	bm.enemy_units.append(em)
	em.is_visible = true
	bm._issue_mortar_move(mortar, Vector2(m(-952), m(2133)), GameConfig.MORTAR_RELOCATE_SPEED, intent)
	return bm

func cleanup(bm) -> void:
	bm.combat_log.free()
	bm.free()

func run() -> void:
	test_the_dry_walks_end_when_ammunition_arrives()
	test_they_continue_while_still_dry()
	test_the_survival_walks_are_not_cut_short()
	test_the_crew_then_takes_the_shot()
	print("Mortar dry-walk tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_the_dry_walks_end_when_ammunition_arrives() -> void:
	for intent in ["linkup", "out_of_ammo"]:
		var bm = make_battle(20, intent)
		var mortar: Unit = bm.player_units[0]
		check(mortar.has_move_target and bm._mortar_move_intent.get(mortar, "") == intent, "Setup: walking with intent %s" % intent)
		bm._update_mortar_decisions()
		check(not mortar.has_move_target, "%s: with 20 rounds delivered the walk must end (still walking to %s)" % [intent, str(mortar.move_target)])
		check(bm._mortar_move_intent.get(mortar, "") == "", "%s: ...and its intent is cleared" % intent)
		cleanup(bm)


func test_they_continue_while_still_dry() -> void:
	for intent in ["linkup", "out_of_ammo"]:
		var bm = make_battle(0, intent)
		var mortar: Unit = bm.player_units[0]
		bm._update_mortar_decisions()
		check(mortar.has_move_target and bm._mortar_move_intent.get(mortar, "") == intent, "%s: a crew still out of ammunition keeps walking" % intent)
		cleanup(bm)


func test_the_survival_walks_are_not_cut_short() -> void:
	for intent in ["evade", "conceal"]:
		var bm = make_battle(20, intent)
		var mortar: Unit = bm.player_units[0]
		bm._update_mortar_decisions()
		check(mortar.has_move_target and bm._mortar_move_intent.get(mortar, "") == intent, "%s: getting clear of a threat is not ended just because ammunition arrived" % intent)
		cleanup(bm)


## The point of it: with the walk ended and the crew stationary long enough to
## emplace, the visible enemy mortar in range is a shot.
func test_the_crew_then_takes_the_shot() -> void:
	var bm = make_battle(20, "linkup")
	var mortar: Unit = bm.player_units[0]
	mortar.fire_timer = 0.0
	bm._update_mortar_decisions()
	mortar.seconds_stationary = GameConfig.MORTAR_SETUP_TEARDOWN_TIME + 1.0
	bm._mortar_tick_shot.clear()
	var before: int = mortar.mortar_rounds_remaining
	bm._tick_fire(mortar, 0.5, 6.0, bm.enemy_units)
	check(mortar.mortar_rounds_remaining < before, "Once set up, the crew fires at the visible enemy mortar in range (rounds %d -> %d)" % [before, mortar.mortar_rounds_remaining])
	cleanup(bm)
