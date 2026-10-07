extends SceneTree
## Direct user report, from a live battle: "enemy mortar is taking evasive action as if it knows it has been spotted. In the circumstance,
## our mortar should fire at it less and might even choose to go after squads. If there were another enemy mortar, it would make sense to go
## after that." A mortar seen changing direction (from its visible positions alone) is dodging; a round takes 40 s to land, so it is worth a
## fraction of an ordinary mortar as a target, a round at it that is picked anyway is often held back, and another mortar or a squad is
## chosen ahead of it.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_dodging_target.gd
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

func make() -> Dictionary:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.scenario_elapsed_time = 1000.0
	var um: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(600, 1700)); bm.player_units.append(um)
	um.mortar_rounds_remaining = 20
	um.seconds_stationary = 1e9
	var observer: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, m(2400, 1700)); bm.player_units.append(observer)
	var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(2500, 1700)); bm.enemy_units.append(em)
	em.is_visible = true
	bm.unit_type_doctrines[Unit.Team.PLAYER] = preload("res://scripts/unit_doctrine.gd").sanitize({})
	bm.unit_type_doctrines[Unit.Team.ENEMY] = preload("res://scripts/unit_doctrine.gd").sanitize({})
	bm._update_player_intel()
	return {"bm": bm, "um": um, "em": em}

## Walk `u` for `seconds` seconds, turning to a new heading every `leg` seconds (0: never), updating the observer each second.
func walk(bm: BattleManager, u: Unit, seconds: int, leg: int) -> void:
	var heading := 0.3
	for s in seconds:
		bm.scenario_elapsed_time += 1.0
		if leg > 0 and s % leg == 0 and s > 0:
			heading += 2.2
		u.global_position += Vector2(cos(heading), sin(heading)) * 2.6 * GameConfig.PIXELS_PER_METER
		bm._update_observed_movement()

func make_dodge(bm: BattleManager, u: Unit) -> void:
	walk(bm, u, 120, 20)

func picks(bm: BattleManager, shooter: Unit, n: int) -> Dictionary:
	var counts := {"mortar": 0, "other_mortar": 0, "squad": 0, "none": 0}
	for i in n:
		var pick: Unit = bm._pick_target(shooter, bm.enemy_units)
		if pick == null:
			counts.none += 1
		elif pick.kind == Unit.Kind.SQUAD:
			counts.squad += 1
		elif pick == bm.enemy_units[0]:
			counts.mortar += 1
		else:
			counts.other_mortar += 1
	return counts

func run() -> void:
	GameConfig.set_active_map("pishchane")
	# 1. what is seen: changing direction twice in the window reads as dodging; a straight march, standing still or being out of sight does not
	var c := make()
	var bm: BattleManager = c.bm
	var em: Unit = c.em
	walk(bm, em, 200, 0)
	check(not bm._mortar_looks_evasive(em), "A mortar seen walking in a straight line for 200 s does not look like it is dodging")
	walk(bm, em, 120, 20)
	check(bm._mortar_looks_evasive(em), "...one seen changing direction every 20 s does")
	em.is_visible = false
	check(not bm._mortar_looks_evasive(em), "...but not once it is out of sight (nothing is known of it then)")
	em.is_visible = true
	bm._update_observed_movement()
	bm.scenario_elapsed_time += GameConfig.OBSERVED_EVASIVE_WINDOW_S + 5.0
	check(not bm._mortar_looks_evasive(em), "...and the impression fades once the turns are old")
	bm.combat_log.free()
	bm.free()
	c = make()
	bm = c.bm
	em = c.em
	walk(bm, em, 60, 0)
	check(not bm._mortar_looks_evasive(em) and bm._observed_mortar_track.get(em, {}).has("heading"), "A mortar seen walking one way for 60 s has been watched and does not look like it is dodging")
	bm.combat_log.free()
	bm.free()

	# 2. only the dodging mortar to shoot at: worth a fraction, fired on a quarter of the time or so, not never
	c = make()
	bm = c.bm
	var um: Unit = c.um
	em = c.em
	seed(21)
	var steady: Dictionary = picks(bm, um, 400)
	check(steady.mortar >= 390, "Control: a mortar not seen dodging is fired on every time it is the target (%d of 400)" % steady.mortar)
	make_dodge(bm, em)
	check(bm._mortar_looks_evasive(em), "Setup: it is dodging")
	em.global_position = m(2500, 1700)
	bm._update_player_intel()
	check(absf(bm._enemy_target_value(um, em) - GameConfig.TARGET_PRIORITY_MORTAR * GameConfig.MORTAR_EVASIVE_TARGET_VALUE_MULTIPLIER) < 0.01, "It is worth a fraction of an ordinary mortar as a target (%.1f)" % bm._enemy_target_value(um, em))
	seed(22)
	var alone: Dictionary = picks(bm, um, 400)
	check(alone.mortar < 160, "A mortar seen dodging is fired on much less often than a steady one (%d of 400, against %d)" % [alone.mortar, steady.mortar])
	check(alone.mortar > 0, "...but not never (%d of 400)" % alone.mortar)

	# 3. with a squad in view the squad is chosen at least as often as the dodging mortar
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(2300, 1800))
	bm.enemy_units.append(squad)
	squad.is_visible = true
	bm._update_player_intel()
	seed(23)
	var with_squad: Dictionary = picks(bm, um, 600)
	check(with_squad.squad >= with_squad.mortar, "With a squad in view, the squad is chosen at least as often as the mortar seen dodging (%d squad, %d mortar of 600)" % [with_squad.squad, with_squad.mortar])
	check(with_squad.squad > 40, "...it is chosen (%d of 600)" % with_squad.squad)

	# 4. another enemy mortar that is not dodging is chosen ahead of it, every time it is picked at all
	var second: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(2600, 1500))
	bm.enemy_units.append(second)
	second.is_visible = true
	bm._update_player_intel()
	seed(24)
	var with_second: Dictionary = {"dodger": 0, "second": 0, "squad": 0, "none": 0}
	for i in 300:
		var pick: Unit = bm._pick_target(um, bm.enemy_units)
		if pick == em:
			with_second.dodger += 1
		elif pick == second:
			with_second.second += 1
		elif pick == squad:
			with_second.squad += 1
		else:
			with_second.none += 1
	check(with_second.second >= 295 and with_second.dodger == 0 and with_second.squad == 0, "With another mortar in view that is not dodging, that is the one fired on (%s)" % str(with_second))

	# 5. a remembered fix on the dodging mortar does not hold the mortar back from squads
	check(bm._mortar_fix_is_evasive(um, {"position": em.global_position, "trusted": true, "unit": em}), "A remembered fix naming the mortar seen dodging is recognised")
	check(bm._mortar_fix_is_evasive(um, {"position": em.global_position + m(10, 0), "trusted": true}), "...and one at the place it stands")
	check(not bm._mortar_fix_is_evasive(um, {"position": second.global_position, "trusted": true, "unit": second}), "...but not a fix on another mortar")
	bm.combat_log.free()
	bm.free()
	print("Mortar dodging-target tests: %d failures" % failures)
	quit(1 if failures else 0)
