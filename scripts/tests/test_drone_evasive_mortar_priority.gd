extends SceneTree
## Direct user ruling: "Enemy mortar is taking evasive action. That should lower its priority for our drone. It could still be higher than
## squads, but lower than other mortars that are known to exist." A visible enemy mortar that has been seen turning unpredictably
## (BattleManager._mortar_looks_evasive) is worth DRONE_EVASIVE_MORTAR_PRIORITY_MULTIPLIER of an ordinary mortar contact to the drone: still above
## a squad, but below any other mortar the drone knows of (one in sight, or a lead on one), and the friendly mortar's own lead prefers a
## mortar that is not dodging.
##
## Run: godot --headless --path . --script scripts/tests/test_drone_evasive_mortar_priority.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func make() -> BattleManager:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.scenario_elapsed_time = 1000.0
	return bm

func friendly_force(bm: BattleManager) -> Dictionary:
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(0, 0)); bm.player_units.append(mortar)
	var squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(500, 300)); bm.player_units.append(squad)
	return {"mortar": mortar, "squad": squad}

func enemy_mortar(bm: BattleManager, at: Vector2, visible: bool, dodging: bool) -> Unit:
	var u: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, at)
	bm.enemy_units.append(u)
	u.is_visible = visible
	if visible:
		u.player_has_been_sighted = true
		u.player_known_position = at
		u.player_known_position_time = bm.scenario_elapsed_time
		u.player_known_state = Unit.State.ACTIVE
	if dodging:
		bm._observed_mortar_track[u] = {"turns": [bm.scenario_elapsed_time - 10.0, bm.scenario_elapsed_time - 35.0]}
	return u

func enemy_squad(bm: BattleManager, at: Vector2) -> Unit:
	var u: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, at)
	bm.enemy_units.append(u)
	u.is_visible = true
	u.player_has_been_sighted = true
	u.player_known_position = at
	return u

func run() -> void:
	GameConfig.set_active_map("pishchane")
	var mult: float = GameConfig.DRONE_EVASIVE_MORTAR_PRIORITY_MULTIPLIER
	check(GameConfig.TARGET_PRIORITY_MORTAR * mult > GameConfig.TARGET_PRIORITY_SQUAD_MAX, "Setup: a dodging mortar's value is above any squad's (%.0f against %.0f)" % [GameConfig.TARGET_PRIORITY_MORTAR * mult, GameConfig.TARGET_PRIORITY_SQUAD_MAX])
	check(GameConfig.TARGET_PRIORITY_MORTAR * mult < GameConfig.TARGET_PRIORITY_MORTAR * GameConfig.TARGET_PRIORITY_MORTAR_LEAD_DISCOUNT, "...and below a lead on another mortar (%.0f against %.0f)" % [GameConfig.TARGET_PRIORITY_MORTAR * mult, GameConfig.TARGET_PRIORITY_MORTAR * GameConfig.TARGET_PRIORITY_MORTAR_LEAD_DISCOUNT])

	# 1. a steady visible mortar is watched at full value; the same mortar dodging is watched at a fraction, still above a squad
	var bm := make()
	friendly_force(bm)
	var gun: Unit = enemy_mortar(bm, Vector2(300, 0), true, false)
	var foe: Unit = enemy_squad(bm, Vector2(560, 330))
	var pos: Vector2 = bm._drone_search_target()
	check(pos.distance_to(gun.global_position) < 1.0 and str(bm._drone_pilot_reasoning.get("tier", "")) == "Live mortar contact", "A steady mortar in sight is the drone's target at full value (%s)" % str(bm._drone_pilot_reasoning.get("tier", "")))
	bm._observed_mortar_track[gun] = {"turns": [bm.scenario_elapsed_time - 10.0, bm.scenario_elapsed_time - 35.0]}
	check(bm._mortar_looks_evasive(gun), "Setup: it now looks like it is dodging")
	pos = bm._drone_search_target()
	check(pos.distance_to(gun.global_position) < 1.0 and str(bm._drone_pilot_reasoning.get("tier", "")).contains("evasive"), "...dodging, and with no other mortar known, it is still the target, above the squad (%s)" % str(bm._drone_pilot_reasoning.get("tier", "")))
	bm.combat_log.free()
	bm.free()

	# 2. another mortar known to exist (a lead on one not in sight) outranks the dodging one in sight
	bm = make()
	friendly_force(bm)
	var dodger: Unit = enemy_mortar(bm, Vector2(300, 0), true, true)
	var hidden: Unit = enemy_mortar(bm, Vector2(500, -200), false, false)
	hidden.player_has_been_sighted = true
	hidden.player_known_position = Vector2(500, -200)
	hidden.player_known_position_time = bm.scenario_elapsed_time - 20.0
	hidden.player_known_state = Unit.State.ACTIVE
	enemy_squad(bm, Vector2(560, 330))
	pos = bm._drone_search_target()
	check(pos.distance_to(bm._clamp_to_drone_operating_area(hidden.player_known_position)) < 1.0 and str(bm._drone_pilot_reasoning.get("tier", "")) == "Last-seen mortar position", "With another mortar known (last seen, in range), the drone goes for that one, not the dodging mortar in sight (%s)" % str(bm._drone_pilot_reasoning.get("tier", "")))
	bm.combat_log.free()
	bm.free()

	# 3. another mortar in sight that is not dodging is the one chosen, and the friendly mortar's own lead too, even if the dodger is nearer
	bm = make()
	friendly_force(bm)
	dodger = enemy_mortar(bm, Vector2(250, 0), true, true)
	var steady: Unit = enemy_mortar(bm, Vector2(600, 100), true, false)
	var pick: Dictionary = bm._priority_visible_enemy_mortar()
	check(pick.get("unit", null) == steady and not pick.get("evasive", false), "With two mortars in sight the one not dodging is the drone's pick, though the dodger is nearer")
	var lead: Dictionary = bm._known_enemy_mortar_lead()
	check(lead.get("unit", null) == steady, "...and the friendly mortar's own lead is the same one")
	check(bm._is_priority_hunt_target(steady) and not bm._is_priority_hunt_target(dodger), "...so it is the mortar the force is oriented to engage")
	pos = bm._drone_search_target()
	check(pos.distance_to(steady.global_position) < 1.0, "...and the drone's target")
	# when the steady one is gone, the dodger is back as the lead
	steady.state = Unit.State.DESTROYED
	lead = bm._known_enemy_mortar_lead()
	check(lead.get("unit", null) == dodger, "With the other mortar out of action, the dodging one is the lead again")
	bm.combat_log.free()
	bm.free()

	# 4. a squad in sight and nothing else: unchanged
	bm = make()
	friendly_force(bm)
	var lone_foe: Unit = enemy_squad(bm, Vector2(560, 330))
	pos = bm._drone_search_target()
	check(str(bm._drone_pilot_reasoning.get("tier", "")) != "Live mortar contact" and not str(bm._drone_pilot_reasoning.get("tier", "")).contains("evasive"), "With no mortar in sight the drone's reasoning is not about one (%s)" % str(bm._drone_pilot_reasoning.get("tier", "")))
	bm.combat_log.free()
	bm.free()
	print("Drone evasive-mortar priority tests: %d failures" % failures)
	quit(1 if failures else 0)
