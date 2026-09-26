extends SceneTree
## Direct user request: "I want to get rid of 'schedule retreat' and the slider. Instead have a
## 'fall back' button. That orders all units to fall back."
##
## Run: godot --headless --path . --script scripts/tests/test_fall_back_all_button.gd
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

func run() -> void:
	test_the_button_orders_every_unit_that_can_be_ordered()
	test_scheduled_retreat_is_gone()
	print("Fall back (all units) tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_the_button_orders_every_unit_that_can_be_ordered() -> void:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var ordered_kinds := [Unit.Kind.SQUAD, Unit.Kind.SQUAD, Unit.Kind.MORTAR, Unit.Kind.SPOTTER, Unit.Kind.DRONE_TEAM]
	var units: Array[Unit] = []
	var y := 600.0
	for kind in ordered_kinds:
		var u: Unit = bm._make_unit(Unit.Team.PLAYER, kind, Vector2(m(1500.0), m(y)))
		bm.player_units.append(u)
		units.append(u)
		y += 300.0
	var destroyed: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(m(1500.0), m(2400.0)))
	destroyed.state = Unit.State.DESTROYED
	bm.player_units.append(destroyed)
	var drone: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(m(1500.0), m(2700.0)))
	bm.player_units.append(drone)
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(m(3000.0), m(1000.0)))
	bm.enemy_units.append(enemy)
	var count: int = bm.order_all_fall_back()
	check(count == units.size(), "Every unit that can be ordered is (%d of %d)" % [count, units.size()])
	for u in units:
		check(bm.fall_back_ordered(u), "%s has the order to fall back" % u.display_name())
		check(u.has_move_target and u.move_target.x < u.global_position.x, "...and is moving west, toward its edge")
	check(not bm.fall_back_ordered(destroyed), "A destroyed unit is not ordered")
	check(not bm.fall_back_ordered(drone), "A drone (not an orderable kind) is not ordered")
	check(not bm.fall_back_ordered(enemy), "The enemy is never ordered")
	check(bm.order_all_fall_back() == units.size(), "Pressing it again leaves the same units under the order")
	bm.combat_log.free()
	bm.free()


func test_scheduled_retreat_is_gone() -> void:
	var bm := BattleManager.new()
	check(not bm.has_method("order_scheduled_retreat") and not bm.has_method("cancel_scheduled_retreat") and not ("scheduled_retreat_time" in bm), "The battle has no scheduled retreat any more")
	bm.free()
	var src := FileAccess.get_file_as_string("res://scripts/battle_screen.gd")
	check("Fall Back" in src and "order_all_fall_back" in src, "The battle screen has the Fall Back button, wired to the order")
	for gone in ["Schedule Retreat", "HSlider", "scheduled_retreat", "Retreat in:"]:
		check(not (gone in src), "The battle screen no longer has '%s'" % gone)
	check("Retreat Now" in src, "The immediate retreat button is still there")
