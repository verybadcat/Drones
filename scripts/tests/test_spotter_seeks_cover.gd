extends SceneTree
## Direct user ruling, given while researching real-world spotter detection/concealment distances:
## "Spotter should always seek cover. If set up not in cover, it should immediately move to cover. If it
## later moves, that might take it out of cover, but it would go to new cover." Before this, a spotter had
## no per-tick decision logic of its own at all — it just sat wherever it was deployed for the whole
## battle, so whether it ever ended up in cover depended entirely on where doctrine happened to place it.
##
## Run: godot --headless --path . --script scripts/tests/test_spotter_seeks_cover.gd
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

func cleanup(bm) -> void:
	bm.combat_log.free()
	bm.free()

func run() -> void:
	test_an_exposed_spotter_moves_to_cover()
	test_a_spotter_already_in_cover_stays_put()
	test_a_spotter_already_moving_is_not_interrupted()
	test_a_fallen_back_or_risk_held_spotter_does_not_auto_seek_cover()
	test_it_applies_to_an_enemy_spotter_too()
	print("Spotter seeks-cover tests: %d failures" % failures)
	quit(1 if failures else 0)


## Same real-map search test_fall_back_order.gd's own find_open_spot_with_cover_to_the_east() uses: a real
## point on the actual loaded map, confirmed genuinely in the open, with real cover terrain findable nearby
## — not a hardcoded coordinate that could drift if the map ever changes.
func find_open_spot_with_nearby_cover() -> Vector2:
	var none: Array[Vector2] = []
	var x := -240.0
	while x <= 1200.0:
		var y := 60.0
		while y <= 640.0:
			var p := Vector2(m(x), m(y))
			if not GameConfig.is_in_cover(GameConfig.get_terrain_type_at(p)) and not GameConfig.is_river_at(p):
				var c: Vector2 = GameConfig.nearest_cover_point(p)
				if c != p and p.distance_to(c) < m(400.0):
					return p
			y += 20.0
		x += 20.0
	return Vector2.INF


func test_an_exposed_spotter_moves_to_cover() -> void:
	var spot: Vector2 = find_open_spot_with_nearby_cover()
	check(not is_inf(spot.x), "Setup: the map has an open spot with real cover findable nearby")
	if is_inf(spot.x):
		return
	var bm = make_battle()
	var spotter: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, spot)
	bm.player_units.append(spotter)
	check(not GameConfig.is_in_cover(spotter.terrain_type()), "Setup: genuinely not in cover at the start")
	bm._update_spotter_positioning()
	check(spotter.has_move_target, "It is ordered to move (%s)" % spotter.last_order_reason)
	check(GameConfig.is_in_cover(GameConfig.get_terrain_type_at(spotter.move_target)), "...specifically toward real cover terrain")
	check(spotter.move_speed == GameConfig.REPOSITION_SPEED, "...at an ordinary reposition pace, not a hurried retreat")
	cleanup(bm)


func test_a_spotter_already_in_cover_stays_put() -> void:
	var spot: Vector2 = find_open_spot_with_nearby_cover()
	if is_inf(spot.x):
		return
	var bm = make_battle()
	var cover: Vector2 = GameConfig.nearest_cover_point(spot)
	var spotter: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, cover)
	bm.player_units.append(spotter)
	check(GameConfig.is_in_cover(spotter.terrain_type()), "Setup: genuinely in cover")
	bm._update_spotter_positioning()
	check(not spotter.has_move_target, "Already covered: no move ordered")
	cleanup(bm)


## A spotter mid-walk (a player order, or its own prior cover-seek from an earlier tick) is left alone —
## this only fires for an idle spotter, never interrupting a move already under way.
func test_a_spotter_already_moving_is_not_interrupted() -> void:
	var spot: Vector2 = find_open_spot_with_nearby_cover()
	if is_inf(spot.x):
		return
	var bm = make_battle()
	var spotter: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, spot)
	bm.player_units.append(spotter)
	spotter.move_target = spot + Vector2(m(9999.0), 0) # an arbitrary, unrelated, clearly-not-cover destination
	spotter.has_move_target = true
	bm._update_spotter_positioning()
	check(spotter.move_target == spot + Vector2(m(9999.0), 0), "The existing move order is left exactly as it was")
	cleanup(bm)


func test_a_fallen_back_or_risk_held_spotter_does_not_auto_seek_cover() -> void:
	var spot: Vector2 = find_open_spot_with_nearby_cover()
	if is_inf(spot.x):
		return
	for held_key in ["_fall_back_orders", "_risk_holds"]:
		var bm = make_battle()
		var spotter: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, spot)
		bm.player_units.append(spotter)
		bm.get(held_key)[spotter] = {"line_x": spot.x} if held_key == "_fall_back_orders" else true
		bm._update_spotter_positioning()
		check(not spotter.has_move_target, "An explicit %s outranks the automatic instinct to seek cover" % held_key)
		cleanup(bm)


## "Nothing here assumes a player-only spotter" — this game currently only ever spawns one on the PLAYER
## side, but the mechanism itself reads team-agnostically off player_units + enemy_units.
func test_it_applies_to_an_enemy_spotter_too() -> void:
	var spot: Vector2 = find_open_spot_with_nearby_cover()
	if is_inf(spot.x):
		return
	var bm = make_battle()
	var spotter: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SPOTTER, spot)
	bm.enemy_units.append(spotter)
	bm._update_spotter_positioning()
	check(spotter.has_move_target and GameConfig.is_in_cover(GameConfig.get_terrain_type_at(spotter.move_target)), "An enemy spotter seeks cover exactly the same way")
	cleanup(bm)
