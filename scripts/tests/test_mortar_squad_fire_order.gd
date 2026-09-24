extends SceneTree
## Direct user request: "I am seeing battles where the mortar conserves ammo
## but should be firing at enemy squads. Rather than an AI change, ... giving
## the commander the ability to order the mortar to be willing to expend ammo
## on enemy squads. ... would still keep existing relative priority of mortar
## vs. squads. ... It should be possible to countermand this order ... accessed
## by clicking on the mortar. The drone team should be aware of the orders the
## mortar has and should act to support them." And, twice: default behavior
## must not change - only an actual order changes anything.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_squad_fire_order.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0
var _selected: Array = []

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(meters: float) -> float:
	return meters * GameConfig.PIXELS_PER_METER

## A player mortar at (-1000, 1500) m with `rounds`, one visible enemy squad 2 km
## east, optionally an unseen enemy mortar out of the crew's own reach (so the
## "another mortar may exist" hold is at its strongest).
func make_battle(rounds: int, hidden_mortar: bool):
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(m(-1000), m(1500)))
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = rounds
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(m(1000), m(1500)))
	bm.enemy_units.append(squad)
	squad.is_visible = true
	if hidden_mortar:
		var hm: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(m(4700), m(1500)))
		bm.enemy_units.append(hm)
	bm._update_player_intel()
	return bm

func hold_fraction(bm, mortar: Unit, trials: int) -> float:
	seed(5)
	var holds := 0
	for i in trials:
		if bm._pick_target(mortar, bm.enemy_units) == null:
			holds += 1
	return float(holds) / float(trials)

func click_at(pos: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pos
	return e

func cleanup(bm) -> void:
	bm.combat_log.free()
	bm.free()

func run() -> void:
	test_unknown_mortar_hold_drops_with_the_order()
	test_ordinary_conservation_hold_drops_with_the_order()
	test_default_and_countermanded_behavior_are_identical()
	test_order_never_changes_which_target_is_preferred()
	test_only_active_player_mortars_can_be_ordered()
	test_order_and_countermand_are_logged()
	test_clicking_selects_only_a_friendly_active_mortar()
	test_drone_supports_the_order()
	test_drone_default_is_untouched()
	await test_panel_reflects_and_sets_the_order()
	test_drone_ignores_unreachable_mortars_under_the_order()
	print("Mortar squad-fire order tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_unknown_mortar_hold_drops_with_the_order() -> void:
	var bm = make_battle(26, true)
	var mortar: Unit = bm.player_units[0]
	var default_hold: float = hold_fraction(bm, mortar, 2000)
	bm.set_mortar_squad_fire_order(mortar, true)
	var ordered_hold: float = hold_fraction(bm, mortar, 2000)
	check(default_hold > 0.7, "Setup: with no order the unknown-mortar hold must be strong (held %.2f)" % default_hold)
	check(ordered_hold < default_hold * 0.3, "The order must cut the hold sharply (%.2f vs %.2f)" % [ordered_hold, default_hold])
	print("  unknown-mortar hold: %.2f default, %.2f ordered" % [default_hold, ordered_hold])
	cleanup(bm)


func test_ordinary_conservation_hold_drops_with_the_order() -> void:
	# Low ammo, no other mortar: only the scarcity hold applies.
	var bm = make_battle(3, false)
	var mortar: Unit = bm.player_units[0]
	var default_hold: float = hold_fraction(bm, mortar, 2000)
	bm.set_mortar_squad_fire_order(mortar, true)
	var ordered_hold: float = hold_fraction(bm, mortar, 2000)
	check(default_hold > 0.6, "Setup: 3 rounds left must hold most of the time by default (held %.2f)" % default_hold)
	check(ordered_hold < default_hold * 0.3, "The order must cut the scarcity hold sharply (%.2f vs %.2f)" % [ordered_hold, default_hold])
	check(ordered_hold > 0.0, "The order makes firing likelier, never certain (held %.2f)" % ordered_hold)
	print("  scarcity hold: %.2f default, %.2f ordered" % [default_hold, ordered_hold])
	cleanup(bm)


## Direct user requirement: don't change default behavior. Same seed, same
## rolls: with no order - and after an order is countermanded - the mortar
## makes exactly the decisions it made before the feature existed.
func test_default_and_countermanded_behavior_are_identical() -> void:
	var bm = make_battle(8, true)
	var mortar: Unit = bm.player_units[0]
	var baseline: Array = _decisions(bm, mortar)
	bm.set_mortar_squad_fire_order(mortar, true)
	var ordered: Array = _decisions(bm, mortar)
	bm.set_mortar_squad_fire_order(mortar, false)
	var countermanded: Array = _decisions(bm, mortar)
	check(baseline == countermanded, "A countermanded order must leave decisions identical to never having ordered")
	check(baseline != ordered, "Sanity: the order itself must change the decisions")
	check(not bm.mortar_squad_fire_ordered(mortar), "Countermand must clear the order")
	cleanup(bm)

func _decisions(bm, mortar: Unit) -> Array:
	seed(77)
	var out := []
	for i in 300:
		out.append(bm._pick_target(mortar, bm.enemy_units) != null)
	return out


## "Would still keep existing relative priority of mortar vs. squads": with a
## visible, in-range enemy mortar and a squad both available, the mortar is
## still the one chosen, ordered or not.
func test_order_never_changes_which_target_is_preferred() -> void:
	for ordered in [false, true]:
		var bm = make_battle(3, false)
		var mortar: Unit = bm.player_units[0]
		var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(m(2000), m(1500)))
		bm.enemy_units.append(em)
		em.is_visible = true
		bm.set_mortar_squad_fire_order(mortar, ordered)
		var wrong := 0
		for i in 200:
			if bm._pick_target(mortar, bm.enemy_units) != em:
				wrong += 1
		check(wrong == 0, "With an enemy mortar in range it must stay the pick, ordered=%s (wrong %d/200)" % [ordered, wrong])
		cleanup(bm)


func test_only_active_player_mortars_can_be_ordered() -> void:
	var bm = make_battle(10, true)
	var enemy_mortar: Unit = bm.enemy_units[1]
	var squad: Unit = bm.player_units[0]
	bm.set_mortar_squad_fire_order(enemy_mortar, true)
	check(not bm.mortar_squad_fire_ordered(enemy_mortar), "An enemy mortar must not take the player's order")
	var friendly_squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2.ZERO)
	bm.player_units.append(friendly_squad)
	bm.set_mortar_squad_fire_order(friendly_squad, true)
	check(not bm.mortar_squad_fire_ordered(friendly_squad), "Only mortars can take the order")
	# A crew that's been knocked out reads as un-ordered (factor 1.0).
	bm.set_mortar_squad_fire_order(squad, true)
	check(bm.mortar_squad_fire_ordered(squad), "Setup: player mortar takes the order")
	squad.state = Unit.State.RETREATING
	check(is_equal_approx(bm._mortar_squad_order_hold_factor(squad), 1.0), "A non-ACTIVE mortar must not get the willingness boost")
	cleanup(bm)


func test_order_and_countermand_are_logged() -> void:
	var bm = make_battle(10, false)
	var mortar: Unit = bm.player_units[0]
	bm.set_mortar_squad_fire_order(mortar, true)
	bm.set_mortar_squad_fire_order(mortar, true) # repeat: no second entry
	bm.set_mortar_squad_fire_order(mortar, false)
	var log: Array = bm.combat_log.captured
	check(log.size() == 2, "Expected exactly one order and one countermand entry, got %d: %s" % [log.size(), str(log)])
	check(log.size() == 2 and "ordered to expend" in log[0] and "cancelled" in log[1], "Log wording")
	cleanup(bm)


func test_clicking_selects_only_a_friendly_active_mortar() -> void:
	var bm = make_battle(10, true)
	var mortar: Unit = bm.player_units[0]
	_selected.clear()
	bm.mortar_selected.connect(func(u): _selected.append(u))
	check(bm.handle_click(mortar.global_position + Vector2(5, 5)) == mortar, "Clicking on the mortar selects it")
	check(_selected.size() == 1 and _selected[0] == mortar, "mortar_selected emitted once with the mortar")
	check(bm.handle_click(mortar.global_position + Vector2(200, 0)) == null, "Clicking empty ground selects nothing")
	check(bm.handle_click(bm.enemy_units[1].global_position) == null, "An enemy mortar can't be selected")
	mortar.state = Unit.State.RETREATING
	check(bm.handle_click(mortar.global_position) == null, "A mortar that's no longer ACTIVE can't be ordered")
	check(_selected.size() == 1, "No further emissions")
	cleanup(bm)


func drone_battle(ordered: bool, squad_visible: bool, squad_x_m: float):
	var w := Weather.new()
	w.wind_speed_10m = 0.0
	w.temperature_c = 10.0
	w._gust_z = 0.0
	w.rng.seed = 1
	Weather.current = w
	var bm = make_battle(10, false)
	bm.weather = w
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	bm.drone_team = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2(m(-1500), m(1500)))
	bm.player_units.append(bm.drone_team)
	var d: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(m(-800), m(1500)))
	bm.player_units.append(d)
	d.move_speed = GameConfig.DRONE_CRUISE_SPEED
	d.drone_battery_charge = 0.9
	bm.active_drone = d
	var squad: Unit = bm.enemy_units[0]
	squad.global_position = Vector2(m(squad_x_m), m(1500))
	squad.is_visible = squad_visible
	if ordered:
		bm.set_mortar_squad_fire_order(bm.player_units[0], true)
	return bm


func test_drone_supports_the_order() -> void:
	# Visible squad inside the mortar's range: the drone watches it.
	var bm = drone_battle(true, true, 1000.0)
	var squad: Unit = bm.enemy_units[0]
	var pos: Vector2 = bm._drone_search_target()
	check(bm._drone_pilot_reasoning.get("tier", "") == "Supporting the mortar's order to fire on squads", "Ordered: drone should support it, got %s" % str(bm._drone_pilot_reasoning.get("tier", "")))
	check(pos.distance_to(squad.global_position) < m(50.0), "Drone should be sent to the squad, went to %s" % str(pos))
	cleanup(bm)

	# Visible but beyond the mortar's reach: watching it can't help the order.
	bm = drone_battle(true, true, 20000.0)
	bm._drone_search_target()
	check(bm._drone_pilot_reasoning.get("tier", "") != "Supporting the mortar's order to fire on squads", "A squad beyond the mortar's range must not draw order support")
	cleanup(bm)

	# Not visible now but seen recently and inside range: go back to look.
	bm = drone_battle(true, true, 1000.0)
	bm._update_recent_enemy_contacts()
	bm.enemy_units[0].is_visible = false
	var unseen: Dictionary = bm._squad_fire_order_watch_target()
	check(not unseen.is_empty(), "A recently seen squad in range should still draw the drone")
	var live_score: float = GameConfig.DRONE_SQUAD_FIRE_ORDER_WATCH_PRIORITY
	check(not unseen.is_empty() and unseen.score < live_score, "An unseen squad must score below a live one")
	# ...and a stale sighting must not.
	bm.scenario_elapsed_time += GameConfig.DRONE_CONTACT_BONUS_EXPIRY + 1.0
	check(bm._squad_fire_order_watch_target().is_empty(), "A stale sighting must draw nothing")
	cleanup(bm)

	# Countermanded: back to nothing.
	bm = drone_battle(true, true, 1000.0)
	bm.set_mortar_squad_fire_order(bm.player_units[0], false)
	check(bm._squad_fire_order_watch_target().is_empty(), "Countermanded order must draw no support")
	cleanup(bm)

	# A live enemy mortar still outranks squad support.
	bm = drone_battle(true, true, 1000.0)
	var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(m(1800), m(1500)))
	bm.enemy_units.append(em)
	em.is_visible = true
	bm._drone_search_target()
	check(bm._drone_pilot_reasoning.get("tier", "") != "Supporting the mortar's order to fire on squads", "Mortar tiers must still outrank the squad order (tier was %s)" % str(bm._drone_pilot_reasoning.get("tier", "")))
	cleanup(bm)


## No order: the drone's choice must be exactly what it was before.
func test_drone_default_is_untouched() -> void:
	var bm = drone_battle(false, true, 1000.0)
	check(bm._squad_fire_order_watch_target().is_empty(), "No order, no order-support target")
	bm._drone_search_target()
	check(bm._drone_pilot_reasoning.get("tier", "") != "Supporting the mortar's order to fire on squads", "Without an order the new tier must never appear")
	cleanup(bm)


## The orders card is the player's only way to reach the order. Direct user
## request: it pops up next to the mortar when clicked, ANY click outside it
## dismisses it (no x, no second mortar click needed), and it holds only the
## orders that can be given.
func test_panel_reflects_and_sets_the_order() -> void:
	var bm = make_battle(10, false)
	var mortar: Unit = bm.player_units[0]
	mortar.global_position = Vector2(300, 300)
	var vp := SubViewport.new() # identity canvas transform: screen == world
	root.add_child(vp)
	var area := Rect2(0, 0, 1000, 700)
	var panel := MortarOrdersPanel.new()
	root.add_child(panel)
	panel.setup(bm, vp, area)
	check(not panel.visible, "Panel starts hidden")
	bm.mortar_selected.connect(panel.show_for)

	bm.handle_click(mortar.global_position)
	check(panel.visible, "Clicking the mortar opens the card")
	check(panel.position.x >= mortar.global_position.x + 10.0, "The card pops up beside the mortar, to its right (x %.0f)" % panel.position.x)
	check(absf(panel.position.y + panel.size.y / 2.0 - mortar.global_position.y) < 2.0, "...vertically centred on it")
	check(not panel._order_switch.button_pressed, "Unordered mortar shows the switch off")
	panel._order_switch.button_pressed = true
	check(bm.mortar_squad_fire_ordered(mortar), "Flipping the switch issues the order")
	panel._order_switch.button_pressed = false
	check(not bm.mortar_squad_fire_ordered(mortar), "Flipping it back countermands it")
	bm.set_mortar_squad_fire_order(mortar, true)
	panel._refresh()
	check(panel._order_switch.button_pressed, "An order set elsewhere shows as on")
	check(bm.mortar_squad_fire_ordered(mortar), "Refreshing the card must not disturb the order")

	# Any click outside the card dismisses it, and the order stands.
	panel.hide_panel()
	bm.handle_click(mortar.global_position)
	check(panel.visible and panel._order_switch.button_pressed, "Reopening shows the standing order")
	panel._input(click_at(panel.position + panel.size / 2.0))
	check(panel.visible, "A click inside the card leaves it open")
	panel._input(click_at(Vector2(900, 650)))
	check(not panel.visible, "A click elsewhere on the map dismisses the card")
	check(bm.mortar_squad_fire_ordered(mortar), "Dismissing the card must not change the order")
	# A click on the mortar itself is outside the card too: it dismisses, and the
	# same click must not reopen it.
	await process_frame # a later, separate click (the frame counter only advances between frames)
	await process_frame
	bm.handle_click(mortar.global_position)
	check(panel.visible, "Setup: the card is open again")
	panel._input(click_at(mortar.global_position))
	bm.handle_click(mortar.global_position)
	check(not panel.visible, "Clicking the mortar while the card is open closes it (and does not reopen it)")
	await process_frame
	await process_frame
	bm.handle_click(mortar.global_position)
	check(panel.visible, "A later click on the mortar opens it again")
	# Only mouse clicks dismiss it — not, say, mouse motion.
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(900, 650)
	panel._input(motion)
	check(panel.visible, "Moving the mouse outside must not dismiss the card")
	# ...and a button RELEASE outside isn't a click.
	var release := click_at(Vector2(900, 650))
	release.pressed = false
	panel._input(release)
	check(panel.visible, "Only the press counts, not the release")

	# It follows the mortar...
	mortar.global_position = Vector2(500, 400)
	panel._reposition()
	check(panel.position.x >= 500.0 + 10.0 and absf(panel.position.y + panel.size.y / 2.0 - 400.0) < 2.0, "The card follows the mortar")
	# ...flips to the left with no room on the right...
	mortar.global_position = Vector2(980, 400)
	panel._reposition()
	check(panel.position.x + panel.size.x <= 980.0, "With no room to the right the card sits to the mortar's left")
	# ...and stays inside the map at the edges.
	mortar.global_position = Vector2(300, 5)
	panel._reposition()
	check(area.encloses(Rect2(panel.position, panel.size)), "The card stays inside the map near the top edge")

	# Nothing but the order in it: no status text, no note, no close button.
	var buttons := 0
	var labels := []
	var stack: Array = [panel]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is BaseButton:
			buttons += 1
		elif n is Label:
			labels.append(n.text)
	check(buttons == 1, "The card holds just the one order switch (found %d buttons)" % buttons)
	check(labels.size() == 2, "Only a heading and the order's name (found %s)" % str(labels))

	bm.battle_over = true
	panel._refresh()
	check(not panel.visible, "Card hides when the battle ends")
	panel.free()
	vp.free()
	cleanup(bm)


## Direct user follow-up: "if the mortar is expending ammunition on enemy
## squads, the drone team should not be tracking enemy mortars that are out of
## range, unless they seem likely to come in range soon."
func test_drone_ignores_unreachable_mortars_under_the_order() -> void:
	var reach: float = GameConfig.mortar_max_range(Unit.Team.PLAYER)
	var far_x_m: float = -1000.0 + reach / GameConfig.PIXELS_PER_METER + 6000.0
	var near_x_m: float = -1000.0 + reach / GameConfig.PIXELS_PER_METER + 300.0 # just out of range: a short walk

	# Default (no order): a visible out-of-range mortar is still watched.
	var bm = drone_battle(false, true, 1000.0)
	var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(m(far_x_m), m(1500)))
	bm.enemy_units.append(em)
	em.is_visible = true
	check(not bm._priority_visible_enemy_mortar().is_empty(), "Default: a visible mortar is watched even when out of range")
	check(bm._squad_order_permits_mortar_watch(em.global_position), "Default: the permission check never restricts anything")
	cleanup(bm)

	# Ordered: the far mortar is dropped; the drone supports the order instead.
	bm = drone_battle(true, true, 1000.0)
	em = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(m(far_x_m), m(1500)))
	bm.enemy_units.append(em)
	em.is_visible = true
	check(bm._priority_visible_enemy_mortar().is_empty(), "Ordered: a far, unreachable mortar is not tracked")
	bm._drone_search_target()
	check(bm._drone_pilot_reasoning.get("tier", "") == "Supporting the mortar's order to fire on squads", "Ordered: the drone should be on the squads, not the far mortar (tier was %s)" % str(bm._drone_pilot_reasoning.get("tier", "")))
	# Countermanding restores tracking.
	bm.set_mortar_squad_fire_order(bm.player_units[0], false)
	check(not bm._priority_visible_enemy_mortar().is_empty(), "Countermanded: tracking the mortar resumes")
	cleanup(bm)

	# Ordered, but the mortar is only a short walk out of range: likely to come in range soon.
	bm = drone_battle(true, true, 1000.0)
	em = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(m(near_x_m), m(1500)))
	bm.enemy_units.append(em)
	em.is_visible = true
	check(bm._squad_order_permits_mortar_watch(em.global_position), "Ordered: a mortar a short walk out of range is still worth tracking")
	check(not bm._priority_visible_enemy_mortar().is_empty(), "Ordered: ...and is tracked")
	# One already in range is of course tracked too.
	check(bm._squad_order_permits_mortar_watch(Vector2(m(2000), m(1500))), "Ordered: an in-range mortar is tracked")
	cleanup(bm)

	# Ordered, far away, but the crew has committed to closing on it.
	bm = drone_battle(true, true, 1000.0)
	em = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(m(far_x_m), m(1500)))
	bm.enemy_units.append(em)
	em.is_visible = true
	bm._mortar_move_intent[bm.player_units[0]] = "hunt"
	check(bm._squad_order_permits_mortar_watch(em.global_position), "Ordered: a mortar the crew is already closing on is tracked")
	cleanup(bm)

	# The shared-hunt tier and fresh fire-detection leads obey the same rule.
	bm = drone_battle(true, true, 1000.0)
	em = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(m(far_x_m), m(1500)))
	bm.enemy_units.append(em)
	em.is_visible = false
	bm._last_detected_mortar_fire[em] = {"position": em.global_position, "time": bm.scenario_elapsed_time}
	bm._joint_mortar_hunt_target = em
	bm._drone_search_target()
	check(bm._drone_pilot_reasoning.get("tier", "") != "Joint mortar hunt", "Ordered: a joint hunt on a far mortar must not pull the drone off the squads")
	bm.set_mortar_squad_fire_order(bm.player_units[0], false)
	bm._drone_search_target()
	check(bm._drone_pilot_reasoning.get("tier", "") == "Joint mortar hunt", "Setup/countermanded: the joint hunt is followed as before (tier was %s)" % str(bm._drone_pilot_reasoning.get("tier", "")))
	cleanup(bm)
