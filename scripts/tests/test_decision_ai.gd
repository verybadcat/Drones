extends SceneTree
## Run: godot --headless --path . --script scripts/tests/test_decision_ai.gd
const Profile = preload("res://scripts/commander_profile.gd")
const Log = preload("res://scripts/tests/test_combat_log.gd")
const Inspector = preload("res://scripts/decision_inspector.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func doctrine(id: String, mode: int, trial_seed: int) -> Dictionary:
	var squads: Array[Dictionary] = []
	for pos in GameConfig.PLAYER_DEFAULT_POSITIONS:
		squads.append({"position": pos, "retreat_threshold": Profile.preset(id).retreat_threshold})
	return {"squads": squads,
		"mortar": {"position": GameConfig.PLAYER_MORTAR_DEFAULT_POSITION, "shoot_and_scoot": false},
		"spotter": {"position": GameConfig.PLAYER_SPOTTER_DEFAULT_POSITION}, "recon_mode": mode,
		"player_profile": Profile.preset(id), "enemy_profile": Profile.preset(id), "seed": trial_seed}

func run_battle(id: String, mode: int, inspect: bool = false) -> Dictionary:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	var log = Log.new()
	bm.start_battle(doctrine(id, mode, 731), log)
	var panel = Inspector.new()
	panel.setup(bm)
	if inspect:
		root.add_child(panel)
	var ticks := 0
	while not bm.battle_over and ticks < 30000:
		bm._process(0.5)
		if inspect and ticks % 20 == 0:
			panel._refresh()
		ticks += 1
	check(bm.battle_over, "%s mode %d must finish" % [id, mode])
	check(bm.decisions.events.size() <= bm.decisions.MAX_EVENTS, "Trace must remain bounded")
	check(not bm.decisions.events.is_empty(), "Battle must record decisions")
	var states: Array = []
	for u in bm.player_units + bm.enemy_units:
		states.append([u.pips, u.state, u.position, u.killed_count, u.heavily_wounded_count])
	var result := {"ticks": ticks, "states": states, "fire": bm.battle_history_fire_events().duplicate(true)}
	panel.free()
	bm.free()
	log.free()
	return result

func test_preferences() -> void:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	var actor := Unit.new()
	actor.team = Unit.Team.PLAYER
	actor.kind = Unit.Kind.SQUAD
	bm.add_child(actor)
	bm.player_units.append(actor)
	var near := Unit.new()
	near.team = Unit.Team.ENEMY
	near.kind = Unit.Kind.SQUAD
	near.pips = 1
	near.max_pips = 9
	near.unit_label = "Nearby damaged squad"
	near.is_visible = true
	bm.add_child(near)
	var far := Unit.new()
	far.team = Unit.Team.ENEMY
	far.kind = Unit.Kind.SQUAD
	far.pips = 9
	far.max_pips = 9
	far.unit_label = "Distant full squad"
	far.is_visible = true
	bm.add_child(far)
	far.position = Vector2(GameConfig.SQUAD_DANGER_RANGE * 2.0, 0)
	bm.enemy_units.assign([near, far])
	var candidates: Array[Unit] = [near, far]
	for id in ["cautious", "aggressive"]:
		var p: Dictionary = Profile.preset(id)
		p.deterministic = true
		bm.commander_profiles[Unit.Team.PLAYER] = p
		var choice := bm._weighted_mortar_target_pick(actor, candidates)
		check(choice == (near if id == "cautious" else far), "%s must express its preference" % id)
	# Hidden and out-of-range contacts cannot become candidates through a profile.
	near.is_visible = false
	check(bm._pick_target(actor, bm.enemy_units) == null, "Profile must respect visibility and range")
	var record: Dictionary = bm.decisions.records_for(actor.get_instance_id())[0]
	check(record.candidates.size() == 1, "Hidden contact must not leak into explanations")
	check(not record.candidates[0].eligible, "Out-of-range contact must have a rejection")
	# The conservation preference must change a real hold/fire branch, not
	# just the displayed score. Keep this target far from any immediate threat.
	actor.kind = Unit.Kind.MORTAR
	actor.mortar_rounds_remaining = GameConfig.MORTAR_STARTING_AMMO / 2
	actor.is_visible = true
	far.position = Vector2(GameConfig.MORTAR_MAX_RANGE * 0.8, 0)
	for id in ["cautious", "aggressive"]:
		var p: Dictionary = Profile.preset(id)
		p.deterministic = true
		bm.commander_profiles[Unit.Team.PLAYER] = p
		var choice := bm._pick_target(actor, bm.enemy_units)
		check(choice == (null if id == "cautious" else far), "%s must apply its ammunition preference" % id)
	# Distinct targets with identical names remain distinguishable in traces.
	near.unit_label = "Squad"
	far.unit_label = "Squad"
	check(bm.decisions.label_for(near) != bm.decisions.label_for(far), "Trace identities must disambiguate squads")
	# Returned records are independent copies and reads consume no randomness.
	record = bm.decisions.records_for(actor.get_instance_id())[0]
	record.reason = "mutated"
	check(bm.decisions.records_for(actor.get_instance_id())[0].reason != "mutated", "Trace must be immutable to readers")
	seed(99)
	var expected := randi()
	seed(99)
	bm.decisions.records_for(actor.get_instance_id())
	bm.decisions.history_for(actor.get_instance_id())
	check(randi() == expected, "Inspector accessors must not draw random values")
	bm.free()

func run() -> void:
	test_preferences()
	var clean := run_battle("baseline", GameConfig.ReconMode.DRONE_TEAM)
	var inspected := run_battle("baseline", GameConfig.ReconMode.DRONE_TEAM, true)
	check(clean == inspected, "Inspecting must preserve the entire seeded battle outcome and firing history")
	print("PASS: baseline with/without inspector agrees")
	for id in Profile.IDS:
		for mode in [GameConfig.ReconMode.SPOTTER, GameConfig.ReconMode.DRONE_TEAM]:
			run_battle(id, mode)
			print("Completed: %s / mode %d" % [id, mode])
	check(Profile.sanitize({"id": "unknown"}).id == "baseline", "Unknown profile must safely use baseline")
	check(Profile.sanitize({"id": "cautious", "protection": INF}).protection == 2.5, "Non-finite weights must use the preset")
	print("Decision AI tests: %d failures" % failures)
	quit(1 if failures else 0)
