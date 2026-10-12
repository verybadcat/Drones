extends SceneTree
## Direct user instruction: "Mortars should attempt not to shell their own side." Since a round hurts whoever is where it lands (see
## test_shell_effects_depend_on_landing), a crew does not fire a round whose aim point is closer than GameConfig.MORTAR_DANGER_CLOSE_M to a
## unit of its own side, or one that, over the scatter this shot will really have, would catch an own unit with more than
## GameConfig.MORTAR_FRIENDLY_FIRE_RISK_TOLERANCE in total. Both sides; ordinary fire and counter-battery replies. Not a prohibition on the
## target being shot at all: the same target is fired on once the own units are away from it.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_danger_close.gd
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

## A mortar of `team` 2 km west of an enemy squad (of the other side) that is in plain sight, in the open, and the battle around them.
func make(team: Unit.Team) -> Dictionary:
	seed(31)
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var own_x: float = -1000.0 if team == Unit.Team.PLAYER else 5000.0
	var foe_x: float = 1000.0 if team == Unit.Team.PLAYER else 3000.0
	var gun: Unit = bm._make_unit(team, Unit.Kind.MORTAR, Vector2(m(own_x), m(1500.0)))
	gun.mortar_rounds_remaining = 40
	var foe_team: Unit.Team = Unit.Team.ENEMY if team == Unit.Team.PLAYER else Unit.Team.PLAYER
	var foe: Unit = bm._make_unit(foe_team, Unit.Kind.SQUAD, Vector2(m(foe_x), m(1500.0)))
	if team == Unit.Team.PLAYER:
		bm.player_units.append(gun)
		bm.enemy_units.append(foe)
		foe.is_visible = true
	else:
		bm.enemy_units.append(gun)
		bm.player_units.append(foe)
		foe.player_has_been_sighted = true
		foe.enemy_has_been_sighted = true
		foe.enemy_known_position = foe.global_position
		foe.enemy_known_state = Unit.State.ACTIVE
		foe.is_visible = true
	return {"bm": bm, "gun": gun, "foe": foe, "foe_x": foe_x, "team": team}

func own_squad(c: Dictionary, x_m: float, y_m: float = 1500.0) -> Unit:
	var u: Unit = c.bm._make_unit(c.team, Unit.Kind.SQUAD, Vector2(m(x_m), m(y_m)))
	if c.team == Unit.Team.PLAYER:
		c.bm.player_units.append(u)
	else:
		c.bm.enemy_units.append(u)
	return u

func shoots(c: Dictionary, trials: int = 60) -> int:
	var opposing: Array[Unit] = c.bm.enemy_units if c.team == Unit.Team.PLAYER else c.bm.player_units
	var n := 0
	for i in trials:
		c.gun.seconds_stationary = 999.0
		c.bm._mortar_tick_shot.clear()
		if c.bm._pick_target(c.gun, opposing) == c.foe:
			n += 1
	return n

func cleanup(c: Dictionary) -> void:
	c.bm.combat_log.free()
	c.bm.free()

func run() -> void:
	for team in [Unit.Team.PLAYER, Unit.Team.ENEMY]:
		var label: String = "Our" if team == Unit.Team.PLAYER else "The enemy's"
		# 1. nobody of its own side near the target: it fires (some of the time: ammunition and other holds still apply)
		var c := make(team)
		check(shoots(c) > 0, "%s mortar fires at a visible squad with none of its own near it" % label)
		# 2. an own squad 40 m from the target: it does not
		var near := own_squad(c, c.foe_x - 40.0)
		check(shoots(c) == 0, "%s mortar holds fire on a target with its own squad 40 m from it" % label)
		# 3. the same squad 300 m away: it fires again (the target is not forbidden, only the danger)
		near.global_position = Vector2(m(c.foe_x - 300.0), m(1500.0))
		check(shoots(c) > 0, "...and fires once that squad is 300 m from the target")
		# 4. a retreating own squad counts; a destroyed one does not
		near.global_position = Vector2(m(c.foe_x - 30.0), m(1500.0))
		near.state = Unit.State.RETREATING
		check(shoots(c) == 0, "...a retreating own squad 30 m away counts")
		near.state = Unit.State.DESTROYED
		check(shoots(c) > 0, "...a destroyed one does not")
		cleanup(c)

		# 5. a unit of the OTHER side near the target is not an own unit: no effect
		c = make(team)
		var other_team: Unit.Team = Unit.Team.ENEMY if team == Unit.Team.PLAYER else Unit.Team.PLAYER
		var stranger: Unit = c.bm._make_unit(other_team, Unit.Kind.SQUAD, Vector2(m(c.foe_x - 20.0), m(1500.0)))
		if team == Unit.Team.PLAYER:
			c.bm.enemy_units.append(stranger)
		else:
			c.bm.player_units.append(stranger)
		check(shoots(c) > 0, "%s mortar is not held back by units of the other side near the target" % label)
		cleanup(c)

	# 6. the check itself: nearest distance and expected risk fall off with distance; risk is larger for tighter fire
	var c2 := make(Unit.Team.PLAYER)
	var sq := own_squad(c2, c2.foe_x - 100.0)
	var aim: Vector2 = c2.foe.global_position
	var r100: Dictionary = c2.bm._mortar_friendly_fire_check(c2.gun, c2.foe, aim)
	sq.global_position = Vector2(m(c2.foe_x - 200.0), m(1500.0))
	var r200: Dictionary = c2.bm._mortar_friendly_fire_check(c2.gun, c2.foe, aim)
	check(is_equal_approx(r100.nearest_m, 100.0) and is_equal_approx(r200.nearest_m, 200.0), "The check reports the nearest own unit's distance to the aim point (%.0f, %.0f)" % [r100.nearest_m, r200.nearest_m])
	check(r100.risk > r200.risk, "...and an expected risk that falls with distance (%.3f at 100 m, %.3f at 200 m)" % [r100.risk, r200.risk])
	check(not r200.endangered, "A squad 200 m from the aim point is outside both limits at this range (%.3f)" % r200.risk)
	cleanup(c2)

	# 7. counter-battery: a reply called in on a position with its own units around is not fired, and costs nothing
	var c3 := make(Unit.Team.ENEMY)
	var gun3: Unit = c3.gun
	var target3: Unit = c3.bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(m(2000.0), m(1500.0)))
	c3.bm.player_units.append(target3)
	var guard := own_squad(c3, 1990.0, 1520.0)
	gun3.seconds_stationary = 999.0
	var rounds_before: int = gun3.mortar_rounds_remaining
	var strikes: Array[Dictionary] = [{
		"target": target3, "attacker": gun3, "fired": false, "fire_time": c3.bm.scenario_elapsed_time - 1.0,
		"impact_position": target3.global_position, "aim_position": target3.global_position, "impact_time": c3.bm.scenario_elapsed_time + 40.0,
	}]
	c3.bm._pending_counter_battery = strikes
	c3.bm._resolve_pending_counter_battery()
	check(gun3.mortar_rounds_remaining == rounds_before and c3.bm._pending_counter_battery.is_empty(), "A counter-battery reply onto a position with its own squad beside it is dropped and spends nothing")
	guard.global_position = Vector2(m(1000.0), m(1500.0))
	strikes = [{
		"target": target3, "attacker": gun3, "fired": false, "fire_time": c3.bm.scenario_elapsed_time - 1.0,
		"impact_position": target3.global_position, "aim_position": target3.global_position, "impact_time": c3.bm.scenario_elapsed_time + 40.0,
	}]
	c3.bm._pending_counter_battery = strikes
	c3.bm._resolve_pending_counter_battery()
	check(gun3.mortar_rounds_remaining == rounds_before - 1, "...and fired once its own squad is a kilometre from it")
	cleanup(c3)

	print("Mortar danger-close tests: %d failures" % failures)
	quit(1 if failures else 0)
