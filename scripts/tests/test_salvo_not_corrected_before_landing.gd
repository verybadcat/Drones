extends SceneTree
## Direct user question: "In three salvoes, the mortar destroyed two enemy mortar teams and hurt a third one in the current battle. Is that
## realistic?" ... "it's a real world question". It was not. Cause found: every round LAUNCHED counted as a correction on the next, so the
## second, third and fourth rounds of one salvo (all fired within seconds, and all forty seconds in the air before any lands) were aimed as if
## the crew had watched the earlier ones fall: from 4.3 km a spotter-observed salvo went from a mean miss of 138 m on the first round to 62,
## 33 and 24 m on the next three, and a drone-observed one much tighter.
##
## Now a correction is made from a round that has LANDED and been seen (BattleManager._note_round_landed), and the rounds of one salvo that
## land together are one observation.
##
## Run: godot --headless --path . --script scripts/tests/test_salvo_not_corrected_before_landing.gd
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

func make(observed: bool) -> Dictionary:
	GameConfig.set_active_map("pishchane")
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.scenario_elapsed_time = 1000.0
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(0, 1500))
	bm.player_units.append(mortar)
	var target: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4300, 1500))
	bm.enemy_units.append(target)
	target.is_visible = true
	if observed:
		var spotter: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, target.global_position + m(0, 110)) # beyond the 100 m a fragment reaches from rounds landing 50 m the other side of the target: the observer survives to watch
		bm.player_units.append(spotter)
	return {"bm": bm, "mortar": mortar, "target": target}

func miss_m(bm: BattleManager, c: Dictionary) -> float:
	return bm._mortar_dispersion_offset(c.mortar, c.target, c.target.global_position).length() / GameConfig.PIXELS_PER_METER

func run() -> void:
	var trials := 500
	seed(77)
	# 1. four rounds of one salvo, fired before any has landed: all have the first round's scatter
	var c := make(true)
	var bm: BattleManager = c.bm
	check(bm._mortar_fire_observation_quality(c.mortar, c.target) == "spotter", "Setup: the fall of shot is watched by a spotter")
	var first := 0.0
	var fourth := 0.0
	for i in trials:
		bm._mortar_fire_adjustment.erase(c.mortar)
		first += miss_m(bm, c)
		miss_m(bm, c)
		miss_m(bm, c)
		fourth += miss_m(bm, c)
	first /= trials
	fourth /= trials
	check(first > 90.0, "Setup: from 4.3 km an unadjusted round misses by about 100 m or more (%.0f m)" % first)
	check(fourth > 0.8 * first, "The fourth round of a salvo fired before any has landed is no better than the first (%.0f m against %.0f m)" % [fourth, first])

	# 2. once that salvo has landed and been seen, the next round is corrected: once, not four times
	var after_one := 0.0
	var after_four := 0.0
	for i in trials:
		bm._mortar_fire_adjustment.erase(c.mortar)
		miss_m(bm, c)
		bm.scenario_elapsed_time += 40.0
		for r in 4: # four rounds landing together
			bm._note_round_landed(c.mortar, c.target)
		after_one += miss_m(bm, c)
		bm._mortar_fire_adjustment.erase(c.mortar)
		miss_m(bm, c)
		for r in 4: # four salvos, each landing and seen before the next
			bm.scenario_elapsed_time += 40.0
			bm._note_round_landed(c.mortar, c.target)
		after_four += miss_m(bm, c)
	after_one /= trials
	after_four /= trials
	check(after_one < 0.8 * first, "After a salvo has landed the next round is better corrected (%.0f m against %.0f m)" % [after_one, first])
	check(after_four < 0.8 * after_one, "...and four successive salvos landed and seen correct further than one (%.0f m against %.0f m)" % [after_four, after_one])
	check(bm._mortar_fire_adjustment[c.mortar].shots == 4, "...the rounds that land together are one correction (shots counted: %d of four salvos)" % bm._mortar_fire_adjustment[c.mortar].shots)
	bm.combat_log.free()
	bm.free()

	# 3. nobody watching: landing corrects nothing
	c = make(false)
	bm = c.bm
	bm._mortar_dispersion_offset(c.mortar, c.target, c.target.global_position)
	for r in 3:
		bm.scenario_elapsed_time += 40.0
		bm._note_round_landed(c.mortar, c.target)
	check(int(bm._mortar_fire_adjustment[c.mortar].get("shots", 0)) == 0, "With no one watching where rounds fall, landing corrects nothing")
	bm.combat_log.free()
	bm.free()

	# 4. through the real landing path: a round that lands is one observation
	c = make(true)
	bm = c.bm
	bm._mortar_dispersion_offset(c.mortar, c.target, c.target.global_position)
	var shots: Array[Dictionary] = []
	for r in 3:
		shots.append({"mortar": c.mortar, "target": c.target, "aim_point": c.target.global_position, "impact_point": c.target.global_position + m(50, 0), "impact_time": bm.scenario_elapsed_time - 1.0})
	bm._pending_mortar_shots = shots
	bm._resolve_pending_mortar_shots()
	check(int(bm._mortar_fire_adjustment[c.mortar].get("shots", 0)) == 1, "Three rounds of a salvo landing together through the real path are one correction (%d)" % int(bm._mortar_fire_adjustment[c.mortar].get("shots", 0)))
	bm.combat_log.free()
	bm.free()

	print("Salvo-not-corrected-before-landing tests: %d failures" % failures)
	quit(1 if failures else 0)
