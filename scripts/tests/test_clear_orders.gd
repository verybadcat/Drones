extends SceneTree
## Direct user request: 'I want to add a "clear orders" button to the top row. This should cancel all
## unit orders. For example, if a squad has fallen back and is not allowed to advance, that would be
## cleared. Or if everybody is retreating, they would no longer be under orders to do so. Of course a
## unit still might decide to retreat anyway. It can be grayed out if there are no orders to clear.'
##
## Run: godot --headless --path . --script scripts/tests/test_clear_orders.gd
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

func make_battle():
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	return bm

func add_unit(bm, kind: Unit.Kind, pos_m: Vector2) -> Unit:
	var u: Unit = bm._make_unit(Unit.Team.PLAYER, kind, Vector2(m(pos_m.x), m(pos_m.y)))
	bm.player_units.append(u)
	return u

func run() -> void:
	test_nothing_to_clear()
	test_a_squad_that_has_fallen_back_is_free_to_advance()
	test_a_squad_on_its_way_back_stops_being_ordered()
	test_a_general_retreat_is_called_off()
	test_a_unit_that_retreats_on_its_own_is_not_touched()
	test_the_mortars_squad_fire_order_is_dropped()
	test_the_button()
	print("Clear orders tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_nothing_to_clear() -> void:
	var bm = make_battle()
	add_unit(bm, Unit.Kind.SQUAD, Vector2(1200, 1500))
	check(not bm.has_orders_to_clear(), "With no orders given there is nothing to clear")
	check(bm.clear_all_orders() == 0, "...and clearing does nothing")
	bm.combat_log.free()
	bm.free()


func test_a_squad_that_has_fallen_back_is_free_to_advance() -> void:
	var bm = make_battle()
	var squad := add_unit(bm, Unit.Kind.SQUAD, Vector2(1200, 1500))
	check(bm.set_fall_back_order(squad, true), "Set-up: the squad is ordered to fall back")
	squad.global_position = bm._fall_back_orders[squad].destination # it arrives
	bm._update_fall_back_orders()
	check(bm.fall_back_holding(squad), "Set-up: it has fallen back and is held there")
	var forward := squad.global_position + Vector2(m(400.0), 0.0)
	check(bm._advances_past_fall_back_line(squad, forward), "Set-up: it may not advance past where it fell back to")
	check(bm.has_orders_to_clear(), "A held squad counts as under orders")
	check(bm.clear_all_orders() == 1, "One unit had an order cleared")
	check(not bm.fall_back_holding(squad) and not bm.fall_back_ordered(squad), "It is no longer held or ordered")
	check(not bm._advances_past_fall_back_line(squad, forward), "...and may advance again")
	check(not bm.has_orders_to_clear(), "Nothing is left to clear (the button grays out)")
	bm.combat_log.free()
	bm.free()


func test_a_squad_on_its_way_back_stops_being_ordered() -> void:
	var bm = make_battle()
	var squad := add_unit(bm, Unit.Kind.SQUAD, Vector2(1200, 1500))
	bm.set_fall_back_order(squad, true)
	check(squad.has_move_target and bm.fall_back_ordered(squad), "Set-up: it is walking back on the order")
	bm.clear_all_orders()
	check(not squad.has_move_target and not bm.fall_back_ordered(squad), "Cleared mid-walk, it stops and is no longer ordered")
	bm._update_fall_back_orders()
	check(not squad.has_move_target, "...and the order does not come back on the next tick")
	bm.combat_log.free()
	bm.free()


func test_a_general_retreat_is_called_off() -> void:
	var bm = make_battle()
	var squad := add_unit(bm, Unit.Kind.SQUAD, Vector2(1200, 1500))
	var mortar := add_unit(bm, Unit.Kind.MORTAR, Vector2(900, 1500))
	mortar.crew_casualties = 1 # a hit crew leaves the gun on a retreat order
	var speed_before: float = squad.retreat_speed
	var gun_before: bool = mortar.mortar_gun_abandoned
	bm.order_general_retreat()
	check(squad.state == Unit.State.RETREATING and mortar.state == Unit.State.RETREATING, "Set-up: everyone is retreating")
	check(mortar.mortar_gun_abandoned, "Set-up: the order made the hit crew abandon the gun")
	check(bm.has_orders_to_clear(), "Retreating on the order counts as under orders")
	check(bm.clear_all_orders() == 2, "Both units had the order cleared")
	check(squad.state == Unit.State.ACTIVE and mortar.state == Unit.State.ACTIVE, "Everybody is back in the fight")
	check(not squad.has_move_target and not mortar.has_move_target, "...and no longer walking off")
	check(mortar.mortar_gun_abandoned == gun_before and is_equal_approx(squad.retreat_speed, speed_before), "What the order changed (the abandoned gun, the retreat speed) is put back")
	check(not bm.player_general_retreat_ordered, "The general retreat is no longer in force")
	check(not bm.has_orders_to_clear(), "Nothing is left to clear")
	bm.order_general_retreat()
	check(squad.state == Unit.State.RETREATING, "A fresh retreat can be ordered afterwards")
	bm.combat_log.free()
	bm.free()


## "Of course a unit still might decide to retreat anyway": one that broke off on its own is not under
## the commander's order and is left as it is; one that already left the field stays gone.
func test_a_unit_that_retreats_on_its_own_is_not_touched() -> void:
	var bm = make_battle()
	var own := add_unit(bm, Unit.Kind.SQUAD, Vector2(1200, 1500))
	own.order_retreat([], [], "Its own casualties.")
	var gone := add_unit(bm, Unit.Kind.SQUAD, Vector2(1200, 1800))
	gone.state = Unit.State.WITHDRAWN
	check(not bm.has_orders_to_clear(), "A unit retreating on its own, or one that has withdrawn, is not under an order")
	var fallen := add_unit(bm, Unit.Kind.SQUAD, Vector2(1200, 2100))
	bm.set_fall_back_order(fallen, true)
	bm.clear_all_orders()
	check(own.state == Unit.State.RETREATING, "The unit that retreated on its own is still retreating")
	check(gone.state == Unit.State.WITHDRAWN, "The withdrawn unit stays withdrawn")
	check(not bm.fall_back_ordered(fallen), "...while the one that was ordered is cleared")
	bm.combat_log.free()
	bm.free()


func test_the_mortars_squad_fire_order_is_dropped() -> void:
	var bm = make_battle()
	var mortar := add_unit(bm, Unit.Kind.MORTAR, Vector2(900, 1500))
	bm.set_mortar_squad_fire_order(mortar, true)
	check(bm.has_orders_to_clear() and bm.mortar_squad_fire_ordered(mortar), "Set-up: the mortar is ordered to expend ammunition on squads")
	bm.clear_all_orders()
	check(not bm.mortar_squad_fire_ordered(mortar), "The order is dropped")
	bm.combat_log.free()
	bm.free()


func test_the_button() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/battle_screen.gd")
	check("Clear Orders" in src and "clear_all_orders" in src, "The top row has a Clear Orders button wired to the order")
	check("clear_orders_button.disabled = not battle_manager.has_orders_to_clear()" in src, "It is grayed out whenever there is nothing to clear")
	check("clear_orders_button.disabled = true" in src, "...and starts grayed out")
