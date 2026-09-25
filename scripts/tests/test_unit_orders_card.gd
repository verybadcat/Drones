extends SceneTree
## The orders card for any unit (was the mortar's alone): every friendly unit gets a
## "Be safe" button — a one-shot order that also dismisses the card — and the mortar
## keeps its "Expend ammo on enemy squads" switch too.
##
## Run: godot --headless --path . --script scripts/tests/test_unit_orders_card.gd
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

## An exposed unit of `kind` at (-200, 1500) m with a known enemy squad 500 m west, and
## an orders card wired to the battle the way main.gd does it.
func make(kind: Unit.Kind, with_enemy: bool = true) -> Dictionary:
	seed(7)
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var u: Unit = bm._make_unit(Unit.Team.PLAYER, kind, Vector2(m(-200), m(1500)))
	bm.player_units.append(u)
	if with_enemy:
		var e: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(m(-700), m(1500)))
		bm.enemy_units.append(e)
		e.is_visible = true
		e.player_has_been_sighted = true
		e.player_known_position = e.global_position
		e.player_known_state = Unit.State.ACTIVE
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
	test_a_squads_card_has_only_the_be_safe_button()
	test_the_mortars_card_has_both()
	test_the_button_gives_the_order_and_dismisses_the_card()
	test_a_refused_order_still_dismisses_the_card()
	test_the_card_can_be_reopened_and_the_order_given_again()
	print("Unit orders card tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_a_squads_card_has_only_the_be_safe_button() -> void:
	for kind in [Unit.Kind.SQUAD, Unit.Kind.SPOTTER, Unit.Kind.DRONE_TEAM]:
		var c := make(kind)
		c.bm.handle_click(c.unit.global_position)
		check(c.panel.visible, "%s: clicking it opens the card" % Unit.Kind.keys()[kind])
		check(not c.panel._fire_row.visible, "%s: the mortar's expend-ammo order is not offered" % Unit.Kind.keys()[kind])
		check(c.panel._be_safe_button.is_visible_in_tree(), "%s: the Be safe button is offered" % Unit.Kind.keys()[kind])
		cleanup(c)


func test_the_mortars_card_has_both() -> void:
	var c := make(Unit.Kind.MORTAR)
	c.bm.handle_click(c.unit.global_position)
	check(c.panel.visible and c.panel._fire_row.visible and c.panel._be_safe_button.is_visible_in_tree(), "The mortar's card offers both orders")
	cleanup(c)


func test_the_button_gives_the_order_and_dismisses_the_card() -> void:
	var c := make(Unit.Kind.SQUAD)
	c.bm.handle_click(c.unit.global_position)
	check(not c.bm.fall_back_ordered(c.unit), "Setup: no order yet")
	c.panel._be_safe_button.pressed.emit()
	check(c.bm.fall_back_ordered(c.unit) and c.unit.has_move_target, "Pressing Be safe orders the unit to fall back")
	check(not c.panel.visible, "...and the card goes away")
	cleanup(c)


## Nowhere safer: the order is refused (the combat log says so) but the card still goes.
func test_a_refused_order_still_dismisses_the_card() -> void:
	var c := make(Unit.Kind.SQUAD, false)
	c.unit.global_position = Vector2(m(300), m(2000)) # already in trees, no enemy known
	c.bm.handle_click(c.unit.global_position)
	c.panel._be_safe_button.pressed.emit()
	check(not c.bm.fall_back_ordered(c.unit), "Setup: the order was refused")
	check(not c.panel.visible, "The card goes away all the same")
	cleanup(c)


func test_the_card_can_be_reopened_and_the_order_given_again() -> void:
	var c := make(Unit.Kind.SQUAD)
	c.bm.handle_click(c.unit.global_position)
	c.panel._be_safe_button.pressed.emit()
	c.unit.global_position = c.bm._fall_back_orders[c.unit].destination
	c.bm._update_fall_back_orders()
	check(not c.bm.fall_back_ordered(c.unit), "Setup: the unit arrived and the order ended")
	c.unit.global_position = Vector2(m(-200), m(1500)) # back in the open
	c.panel._dismissed_frame = -1
	c.bm.handle_click(c.unit.global_position)
	check(c.panel.visible, "Clicking the unit again reopens the card")
	c.panel._be_safe_button.pressed.emit()
	check(c.bm.fall_back_ordered(c.unit) and not c.panel.visible, "...and the order can be given again")
	cleanup(c)
