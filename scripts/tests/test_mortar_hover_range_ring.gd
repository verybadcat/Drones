extends SceneTree
## Direct user request: "When I mouse over the mortar, I want it to show the range circle, just as it does during setup." In battle the
## player's mortar shows its range circle (the same drawing the setup token uses, GameConfig.draw_mortar_range_ring) while the mouse is over it.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_hover_range_ring.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(x: float, y: float = 0.0) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

func run() -> void:
	GameConfig.set_active_map("pishchane")
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(500.0, 400.0)); bm.player_units.append(mortar)
	var squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(800.0, 400.0)); bm.player_units.append(squad)
	var enemy_gun: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(1500.0, 400.0)); bm.enemy_units.append(enemy_gun)
	check(not mortar.show_range_ring, "Setup: no ring before the mouse is over it")

	bm.update_hover(Vector2(505.0, 402.0))
	check(mortar.show_range_ring, "With the mouse over the mortar its range circle shows")
	bm.update_hover(Vector2(500.0 + BattleManager.UNIT_CLICK_RADIUS - 1.0, 400.0))
	check(mortar.show_range_ring, "...up to the click radius")
	bm.update_hover(Vector2(500.0 + BattleManager.UNIT_CLICK_RADIUS + 12.0, 400.0))
	check(not mortar.show_range_ring, "...and it goes away when the mouse moves off")
	bm.update_hover(Vector2(505.0, 402.0), false)
	check(not mortar.show_range_ring, "...and is not shown when the mouse is not over the map")

	bm.update_hover(Vector2(800.0, 400.0))
	check(not squad.show_range_ring and not mortar.show_range_ring, "A squad has no range circle, and the mortar's stays off")
	bm.update_hover(Vector2(1500.0, 400.0))
	check(not enemy_gun.show_range_ring, "The enemy's mortar does not show one (this is the player's own mortar's)")

	bm.update_hover(Vector2(500.0, 400.0))
	check(mortar.show_range_ring, "Back over the mortar it shows again")
	mortar.state = Unit.State.DESTROYED
	bm.update_hover(Vector2(500.0, 400.0))
	check(not mortar.show_range_ring, "A mortar that is out of action shows none")
	mortar.state = Unit.State.ACTIVE

	# the circle is the setup circle: same range, same drawing
	check(is_equal_approx(GameConfig.mortar_max_range(Unit.Team.PLAYER), GameConfig.MORTAR_MAX_RANGE_PLAYER), "The circle's radius is the range the setup screen shows")
	bm.combat_log.free()
	bm.free()

	# in a real battle screen: the per-frame hover runs without trouble, and the flag drives a redraw
	var main = load("res://scripts/main.gd").new()
	root.add_child(main)
	await process_frame
	main._show_deployment()
	await process_frame
	main.current_screen.request_start()
	await process_frame
	await process_frame
	var battle: BattleScreen = main.current_screen
	check(battle is BattleScreen and battle.battle_manager != null, "Setup: a battle is running")
	var real_mortar: Unit = null
	for u in battle.battle_manager.player_units:
		if u.kind == Unit.Kind.MORTAR:
			real_mortar = u
	check(real_mortar != null, "Setup: the player's mortar exists")
	if real_mortar != null:
		battle.battle_manager.update_hover(real_mortar.global_position)
		check(real_mortar.show_range_ring, "In a real battle the mortar shows its circle when hovered")
		await process_frame
		await process_frame
		battle.battle_manager.update_hover(real_mortar.global_position + Vector2(300.0, 0.0))
		check(not real_mortar.show_range_ring, "...and not when the mouse is elsewhere")
	print("Mortar hover range ring tests: %d failures" % failures)
	quit(1 if failures else 0)
