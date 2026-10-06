extends SceneTree
## Direct user request: "Each map needs a region where the Ukrainian mortar cannot go. They will not go within 200 meters
## of populated locations. But I want to examine it individually by map. Make your best guess and shade it somehow so it's
## visible during setup." Each map names its region (CURRENT_MAP.mortar_exclusion_file: the ground within 200 m of a cluster
## of at least five buildings, built by tools/map_pipeline/mortar_exclusion/build.py) and the deployment screen shades it.
##
## What this checks: every map has a real region that is neither empty nor most of the map; every default mortar position
## sits outside it with room to spare; the region bars the player's mortar but not the enemy's; and the player's mortar
## never plans a relocation into it or across it, and is stopped at its edge if an order slips through.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_exclusion_region.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func make_battle():
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	return bm

func m(meters: float) -> float:
	return meters * GameConfig.PIXELS_PER_METER


func test_every_map_has_a_sensible_region() -> void:
	for map_id in GameConfig.MAPS.keys():
		GameConfig.set_active_map(map_id)
		var rects: Array = GameConfig.mortar_exclusion_rects()
		check(not rects.is_empty(), "%s: the map names a mortar-exclusion region and it loads" % map_id)
		var area_m2 := 0.0
		for r in rects:
			area_m2 += r.size.x * r.size.y / (GameConfig.PIXELS_PER_METER * GameConfig.PIXELS_PER_METER)
		var map_m2: float = (GameConfig.MAP_WIDTH_M + GameConfig.WEST_FLANK_WIDTH_M) * GameConfig.MAP_HEIGHT_M
		check(area_m2 > 0.03 * map_m2 and area_m2 < 0.7 * map_m2, "%s: the region is a real part of the map, not nothing and not nearly all of it (%.0f%%)" % [map_id, 100.0 * area_m2 / map_m2])
		# The default mortar position stands outside the region with a margin, so it is a legal place to start.
		var home: Vector2 = GameConfig.CURRENT_MAP.player.mortar_default_position
		var margin_clear := true
		for dx in [-30.0, 0.0, 30.0]:
			for dy in [-30.0, 0.0, 30.0]:
				if GameConfig.mortar_excluded_at(home + Vector2(m(dx), m(dy))):
					margin_clear = false
		check(margin_clear, "%s: the default mortar position is outside the region, with 30 m to spare" % map_id)
		check(not GameConfig.mortar_barred_at(home, Unit.Team.PLAYER), "%s: ...so the player may set the mortar up there" % map_id)
		# Every building in a populated place is inside the region (it is the region's own definition).
		var inside := 0
		var total := 0
		for poly in GameConfig._footprint_polygons():
			total += 1
			var c := Vector2.ZERO
			for v in poly:
				c += v
			c /= float(poly.size())
			if GameConfig.mortar_excluded_at(c):
				inside += 1
		check(float(inside) / float(max(total, 1)) > 0.9, "%s: nearly every building sits inside the region (%d of %d)" % [map_id, inside, total])
	GameConfig.set_active_map("pishchane")


func test_it_bars_the_player_mortar_only() -> void:
	GameConfig.set_active_map("pishchane")
	var rect: Rect2 = GameConfig.mortar_exclusion_rects()[0]
	var inside: Vector2 = rect.get_center()
	# Not inside a building, so only the region itself is under test.
	var found := false
	for r in GameConfig.mortar_exclusion_rects():
		var c: Vector2 = r.get_center()
		if not GameConfig.is_building_at(c):
			inside = c
			found = true
			break
	check(found, "Setup: a point inside the region that is not inside a building")
	check(GameConfig.mortar_excluded_at(inside), "Setup: that point is in the region")
	check(GameConfig.mortar_barred_at(inside, Unit.Team.PLAYER), "The player's mortar may not stand in the region")
	check(not GameConfig.mortar_barred_at(inside, Unit.Team.ENEMY), "The enemy's mortar is not held to it")
	check(GameConfig._load_mortar_exclusion_file("res://assets/maps/does_not_exist.json").is_empty(), "A missing file gives no region instead of an error")


## A spot just outside the region on the village side, plus a point deep inside it, along one row.
func edge_pair() -> Array:
	GameConfig.set_active_map("pishchane")
	var y: float = m(1400.0)
	for xm in range(0, 1700, 5):
		if GameConfig.mortar_excluded_at(Vector2(m(float(xm)), y)):
			return [Vector2(m(float(xm) - 25.0), y), Vector2(m(float(xm) + 150.0), y)]
	return []


func test_player_mortar_never_plans_into_the_region() -> void:
	var pair := edge_pair()
	check(pair.size() == 2, "Setup: found the region's edge on Pishchane")
	if pair.size() < 2:
		return
	var bm = make_battle()
	var start: Vector2 = pair[0]
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, start)
	bm.player_units.append(mortar)
	mortar.seconds_stationary = 1e9
	# Known enemies to the east, so the search for a hidden spot has something to hide from.
	for e in [Vector2(m(1900), m(1300)), Vector2(m(1900), m(1500))]:
		var sq: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, e)
		bm.enemy_units.append(sq)
		sq.is_visible = true
	bm._update_player_intel()
	var planned := 0
	var bad := 0
	for i in 80:
		var plan: Dictionary = bm._mortar_relocation_plan(mortar, true)
		if plan.is_empty():
			continue
		planned += 1
		var dest: Vector2 = plan.destination
		if GameConfig.mortar_excluded_at(dest) or GameConfig.path_enters_mortar_exclusion(start, dest):
			bad += 1
	check(planned >= 20, "Setup: the mortar makes relocation plans here (%d of 80)" % planned)
	check(bad == 0, "None of the player mortar's relocation plans ends in, or walks into, the region (%d of %d do)" % [bad, planned])
	# The same mortar on the enemy's side is free to use that ground: the rule is the Ukrainian crew's.
	bm.combat_log.free()


func test_a_slipped_order_is_stopped_at_the_edge() -> void:
	var pair := edge_pair()
	if pair.size() < 2:
		return
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, pair[0])
	bm.player_units.append(mortar)
	mortar.position = pair[0]
	mortar.move_target = pair[1]
	mortar.has_move_target = true
	mortar.move_speed = 1.0
	for i in 400:
		if not mortar.has_move_target:
			break
		bm._step_toward_target(mortar, 1.0)
	check(not GameConfig.mortar_excluded_at(mortar.position), "An order that would walk the player's mortar into the region leaves it outside")
	check(not mortar.has_move_target, "...and the order is cancelled, not left to push against the edge forever")
	check(mortar.position.distance_to(pair[0]) < m(80.0), "...stopped at the edge, not somewhere else (%.0f m from where it started)" % (mortar.position.distance_to(pair[0]) / GameConfig.PIXELS_PER_METER))
	# An enemy mortar walks the same leg freely.
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, pair[0])
	bm.enemy_units.append(enemy)
	enemy.position = pair[0]
	enemy.move_target = pair[1]
	enemy.has_move_target = true
	enemy.move_speed = 1.0
	for i in 400:
		if not enemy.has_move_target:
			break
		bm._step_toward_target(enemy, 1.0)
	check(enemy.position.distance_to(pair[1]) < m(2.0), "The enemy's mortar is not stopped by it")
	# A crew already inside (it never should be) can walk out.
	var inside: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, pair[1])
	bm.player_units.append(inside)
	inside.position = pair[1]
	inside.move_target = pair[0]
	inside.has_move_target = true
	inside.move_speed = 1.0
	for i in 400:
		if not inside.has_move_target:
			break
		bm._step_toward_target(inside, 1.0)
	check(inside.position.distance_to(pair[0]) < m(2.0), "A crew already inside can still walk out")
	bm.combat_log.free()


func run() -> void:
	test_every_map_has_a_sensible_region()
	test_it_bars_the_player_mortar_only()
	test_player_mortar_never_plans_into_the_region()
	test_a_slipped_order_is_stopped_at_the_edge()
	print("Mortar exclusion region tests: %d failures" % failures)
	quit(1 if failures else 0)
