extends SceneTree
## Direct user request: "When selecting our units, I want hotkeys for the orders. The hotkey can be the first letter of the order. It can
## override any other meaning the key may have. Also, add a 'b' for the blowup window. Another 'b' would remove the window, as would
## deselecting the unit." ... "Don't need them in the ? list. Just have them on the card."
##
## While the orders card is open: F gives Fall back (and the card goes, as the button does), E flips the mortar's expend-ammo order (mortar
## only), B shows or hides the blow-up window around the unit. Each is consumed (so E does not also toggle the heat map). Shown on the card.
##
## Run: godot --headless --path . --script scripts/tests/test_orders_card_hotkeys.gd
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

func key(code: Key, pressed: bool = true, echo: bool = false, ctrl: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = pressed
	e.echo = echo
	e.ctrl_pressed = ctrl
	return e

func make(kind: Unit.Kind) -> Dictionary:
	seed(7)
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var u: Unit = bm._make_unit(Unit.Team.PLAYER, kind, Vector2(m(-200), m(1500)))
	bm.player_units.append(u)
	bm._friendly_mortar_home_position = u.global_position
	var vp := SubViewport.new()
	root.add_child(vp)
	var panel := UnitOrdersPanel.new()
	root.add_child(panel)
	panel.setup(bm, vp, Rect2(0, 0, 1000, 700))
	bm.unit_selected.connect(panel.show_for)
	return {"bm": bm, "unit": u, "panel": panel, "vp": vp}

func cleanup(c: Dictionary) -> void:
	c.panel.free()
	c.vp.free()
	c.bm.combat_log.free()
	c.bm.free()

func run() -> void:
	# 1. the keys are on the card
	var c := make(Unit.Kind.MORTAR)
	check(c.panel._fall_back_button.text.contains("[F]"), "The Fall back button shows its key (%s)" % c.panel._fall_back_button.text)
	check(c.panel._fire_label.text.contains("[E]"), "The expend-ammo order shows its key (%s)" % c.panel._fire_label.text)
	check(c.panel._blowup_button.text.contains("[B]"), "The blow-up button shows its key (%s)" % c.panel._blowup_button.text)

	# 2. E flips the mortar's order, on and off, and is consumed
	c.bm.handle_click(c.unit.global_position)
	check(c.panel.visible and not c.bm.mortar_squad_fire_ordered(c.unit), "Setup: the mortar's card is open and the order is off")
	check(c.panel._handle_key(key(KEY_E)), "E is taken by the mortar's card")
	check(c.bm.mortar_squad_fire_ordered(c.unit), "...and gives the expend-ammo order")
	check(c.panel._handle_key(key(KEY_E)) and not c.bm.mortar_squad_fire_ordered(c.unit), "...and again lifts it")
	check(c.panel.visible, "...the card stays open for it (it is a standing order)")

	# 3. keys that do not count
	check(not c.panel._handle_key(key(KEY_F, false)), "A key release does nothing")
	check(not c.panel._handle_key(key(KEY_F, true, true)), "A held key's repeat does nothing")
	check(not c.panel._handle_key(key(KEY_F, true, false, true)), "Ctrl+F is left alone")
	check(not c.panel._handle_key(key(KEY_G)), "A key with no order is left alone")
	check(not c.bm.fall_back_ordered(c.unit) and c.panel.visible, "...none of them gave an order")

	# 4. F gives the fall-back order and the card goes, like the button
	check(c.panel._handle_key(key(KEY_F)), "F is taken")
	check(c.bm.fall_back_ordered(c.unit) and c.unit.has_move_target, "...and orders the unit to fall back")
	check(not c.panel.visible, "...and the card goes away")
	check(not c.panel._handle_key(key(KEY_F)), "With the card gone F does nothing (it is not a global key)")
	cleanup(c)

	# 5. a squad's card has no expend-ammo order: E is not taken there (it stays the heat map's key)
	c = make(Unit.Kind.SQUAD)
	c.bm.handle_click(c.unit.global_position)
	check(not c.panel._handle_key(key(KEY_E)), "E is not taken by a squad's card")
	var asked := [0]
	c.panel.blowup_requested.connect(func(): asked[0] += 1)
	check(c.panel._handle_key(key(KEY_B)) and asked[0] == 1, "B asks for the blow-up window")
	c.panel._blowup_button.pressed.emit()
	check(asked[0] == 2, "...and so does the card's button")
	cleanup(c)

	# 6. in a real battle screen: B shows the window on the unit, B again or deselecting takes it away; E does not also toggle the heat map
	var main = load("res://scripts/main.gd").new()
	root.add_child(main)
	await process_frame
	main._show_deployment()
	await process_frame
	main.current_screen.request_start()
	await process_frame
	await process_frame
	var battle: BattleScreen = main.current_screen
	check(battle is BattleScreen and battle.blowup != null, "Setup: a battle is running with a blow-up window")
	var squad: Unit = null
	var mortar: Unit = null
	for u in battle.battle_manager.player_units:
		if u.kind == Unit.Kind.SQUAD and squad == null:
			squad = u
		if u.kind == Unit.Kind.MORTAR:
			mortar = u
	check(not battle.blowup.visible, "The window is not shown to begin with")
	battle.battle_manager.handle_click(squad.global_position)
	await process_frame
	check(battle.unit_orders_panel.visible and not battle.blowup.visible, "Selecting a unit opens its card but not the window")
	battle.unit_orders_panel._handle_key(key(KEY_B))
	await process_frame
	check(battle.blowup.visible and battle.blowup.focus_position == squad.global_position and battle.blowup.unit_kind == Unit.Kind.SQUAD, "B shows the window on the unit")
	check(not battle.blowup.show_separation_ring, "...without the setup screen's 50 m ring")
	var labels: Array = battle.blowup.others.map(func(o): return o.label)
	check(not labels.has(squad.unit_label) and labels.size() >= 1, "...showing the other units nearby, not the unit itself (%s)" % str(labels))
	squad.global_position += Vector2(m(40.0), 0.0)
	await process_frame
	check(battle.blowup.focus_position == squad.global_position, "...and it follows the unit")
	battle.unit_orders_panel._handle_key(key(KEY_B))
	await process_frame
	check(not battle.blowup.visible, "B again takes it away")
	battle.unit_orders_panel._handle_key(key(KEY_B))
	await process_frame
	check(battle.blowup.visible, "...and again shows it")
	battle.unit_orders_panel.hide_panel()
	await process_frame
	check(not battle.blowup.visible, "Deselecting the unit takes it away")
	battle.battle_manager.handle_click(squad.global_position)
	await process_frame
	check(battle.unit_orders_panel.visible and not battle.blowup.visible, "Selecting again does not bring it back by itself")
	battle.unit_orders_panel.hide_panel()

	# an enemy unit in sight shows in it, one not in sight does not
	var foe: Unit = battle.battle_manager._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, squad.global_position + Vector2(m(60.0), 0.0))
	battle.battle_manager.enemy_units.append(foe)
	foe.is_visible = false
	check(battle.blowup_others(squad).filter(func(o): return o.get("enemy", false)).is_empty(), "An enemy squad the player cannot see is not in the window")
	foe.is_visible = true
	check(battle.blowup_others(squad).filter(func(o): return o.get("enemy", false)).size() == 1, "...and one in sight is")
	battle.battle_manager.enemy_units.erase(foe)
	foe.free()

	# E on the mortar's card is the order, not the heat map
	var heat_before: bool = BattleScreen.enemy_heatmap_enabled
	battle.battle_manager.handle_click(mortar.global_position)
	await process_frame
	check(battle.unit_orders_panel.visible and battle.unit_orders_panel.unit == mortar, "Setup: the mortar's card is open")
	Input.parse_input_event(key(KEY_E))
	await process_frame
	await process_frame
	check(BattleScreen.enemy_heatmap_enabled == heat_before, "E on the mortar's card does not also toggle the heat map")
	check(battle.battle_manager.mortar_squad_fire_ordered(mortar), "...it gave the mortar's order")
	battle.unit_orders_panel.hide_panel()
	Input.parse_input_event(key(KEY_E))
	await process_frame
	await process_frame
	check(BattleScreen.enemy_heatmap_enabled != heat_before, "With no card open E is still the heat map's key")
	BattleScreen.enemy_heatmap_enabled = heat_before

	print("Orders card hotkey tests: %d failures" % failures)
	quit(1 if failures else 0)
