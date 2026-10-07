extends SceneTree
## Direct user request: "Each map needs a region where the Ukrainian mortar cannot go. They will not go within 200 meters of populated
## locations ... shade it somehow so it's visible during setup." Later, the rule changed: "It cannot set up a firing position within the
## red area. Also, it cannot start within it. But it can move through it, for example during a retreat." and "that restriction applies
## only to Ukrainian mortars. Russian ones don't care." Each map names its region (CURRENT_MAP.mortar_exclusion_file: the ground within
## 200 m of a cluster of at least five buildings, built by tools/map_pipeline/mortar_exclusion/build.py) and the deployment screen shades it
## while the mortar is dragged.
##
## What this checks: every map has a real region that is neither empty nor most of the map; every default mortar position sits outside it
## with room to spare; the region bars the player's mortar but not the enemy's; the player's mortar never plans a place to set up inside it;
## it may walk through the region, cannot fire from inside it, and a crew standing in it moves out; and a crew retreating across
## Voznesensk's town reaches the west edge.
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

func m(meters: float, meters_y: float = 0.0) -> Vector2:
	return Vector2(meters, meters_y) * GameConfig.PIXELS_PER_METER


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
				if GameConfig.mortar_excluded_at(home + m(dx, dy)):
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
	var inside: Vector2 = GameConfig.mortar_exclusion_rects()[0].get_center()
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
	check(GameConfig.mortar_barred_at(inside, Unit.Team.PLAYER), "The player's mortar may not set up in the region")
	check(not GameConfig.mortar_barred_at(inside, Unit.Team.ENEMY), "The enemy's mortar is not held to it")
	check(GameConfig._load_mortar_exclusion_file("res://assets/maps/does_not_exist.json").is_empty(), "A missing file gives no region instead of an error")


## A spot just outside the region on the village side, plus a point deep inside it, along one row.
func edge_pair() -> Array:
	GameConfig.set_active_map("pishchane")
	var y: float = m(1400.0).x
	for xm in range(0, 1700, 5):
		if GameConfig.mortar_excluded_at(Vector2(m(float(xm)).x, y)):
			return [Vector2(m(float(xm) - 25.0).x, y), Vector2(m(float(xm) + 150.0).x, y)]
	return []


func test_player_mortar_never_plans_to_set_up_inside_the_region() -> void:
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
	for e in [m(1900, 1300), m(1900, 1500)]:
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
		if GameConfig.mortar_excluded_at(plan.destination):
			bad += 1
	check(planned >= 20, "Setup: the mortar makes relocation plans here (%d of 80)" % planned)
	check(bad == 0, "None of the player mortar's relocation plans ends inside the region (%d of %d do)" % [bad, planned])
	bm.combat_log.free()


## Walks `unit` from `a` to `b` at one pixel a tick; returns how many ticks it spent inside the region.
func walk(bm, unit: Unit, a: Vector2, b: Vector2) -> int:
	unit.position = a
	unit.move_target = b
	unit.move_queue.clear()
	unit.has_move_target = true
	unit.move_speed = 1.0
	var inside := 0
	for i in 4000:
		if not unit.has_move_target:
			break
		bm._step_toward_target(unit, 1.0)
		if GameConfig.mortar_excluded_at(unit.position):
			inside += 1
	return inside


func test_a_crew_may_walk_through_the_region() -> void:
	var pair := edge_pair()
	if pair.size() < 2:
		return
	var y: float = pair[0].y
	var out: Vector2 = pair[1]
	for xm in range(int(pair[1].x / GameConfig.PIXELS_PER_METER), 4000, 5):
		if not GameConfig.mortar_excluded_at(Vector2(m(float(xm)).x, y)):
			out = Vector2(m(float(xm) + 25.0).x, y)
			break
	check(not GameConfig.mortar_excluded_at(out), "Setup: open ground on the far side of the region")
	var bm = make_battle()
	var crew: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, pair[0])
	bm.player_units.append(crew)
	var inside_ticks := walk(bm, crew, pair[0], out)
	check(inside_ticks > 0, "Setup: the walk does go through the region (%d ticks inside)" % inside_ticks)
	check(crew.position.distance_to(out) < m(2.0).x, "The Ukrainian crew walks across the region to the far side (%.0f m short)" % (crew.position.distance_to(out) / GameConfig.PIXELS_PER_METER))
	var russian: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, pair[0])
	bm.enemy_units.append(russian)
	walk(bm, russian, pair[0], out)
	check(russian.position.distance_to(out) < m(2.0).x, "The Russian crew does too")
	bm.combat_log.free()


## Rounds a mortar of `team` standing at `at` fires in one fire tick, with a visible target 1,500 m east and an observer by it.
func rounds_after_one_fire_tick(team: int, at: Vector2) -> int:
	# whether a ready crew actually looses a round on a given tick has a chance in it (hold-fire rolls), so try a handful of fresh
	# batteries and report the most any of them fired: zero then means it never could
	var most := 0
	for attempt in 8:
		most = maxi(most, _fire_once(team, at))
	return most


func _fire_once(team: int, at: Vector2) -> int:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(team, Unit.Kind.MORTAR, at)
	var foe_team: int = Unit.Team.ENEMY if team == Unit.Team.PLAYER else Unit.Team.PLAYER
	var mine: Array = bm.player_units if team == Unit.Team.PLAYER else bm.enemy_units
	var theirs: Array = bm.enemy_units if team == Unit.Team.PLAYER else bm.player_units
	mine.append(mortar)
	mortar.mortar_rounds_remaining = 10
	mortar.seconds_stationary = 1e9
	mortar.fire_timer = 0.0
	mortar.base_hit_chance = 1.0
	var target: Unit = bm._make_unit(foe_team, Unit.Kind.SQUAD, at + m(1500.0))
	theirs.append(target)
	target.is_visible = true
	var observer: Unit = bm._make_unit(team, Unit.Kind.SPOTTER, target.global_position + m(0.0, 150.0))
	mine.append(observer)
	bm.unit_type_doctrines[team] = preload("res://scripts/unit_doctrine.gd").sanitize({})
	bm._update_player_intel()
	var before: int = mortar.mortar_rounds_remaining
	bm._tick_fire(mortar, 1.0, 1000.0, theirs)
	var fired: int = before - mortar.mortar_rounds_remaining
	bm.combat_log.free()
	bm.free()
	return fired


func test_it_cannot_fire_from_inside_the_region() -> void:
	var pair := edge_pair()
	if pair.size() < 2:
		return
	check(rounds_after_one_fire_tick(Unit.Team.PLAYER, pair[0]) > 0, "Setup: the Ukrainian crew fires from open ground here")
	check(rounds_after_one_fire_tick(Unit.Team.PLAYER, pair[1]) == 0, "The Ukrainian crew does not fire from inside the region")
	check(rounds_after_one_fire_tick(Unit.Team.ENEMY, pair[1]) > 0, "The Russian crew fires from the same spot")


func test_a_crew_standing_in_the_region_moves_out() -> void:
	var pair := edge_pair()
	if pair.size() < 2:
		return
	var bm = make_battle()
	var start: Vector2 = pair[1]
	bm._friendly_mortar_home_position = start
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, start)
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = 10
	mortar.seconds_stationary = 1e9
	bm.unit_type_doctrines[Unit.Team.PLAYER] = preload("res://scripts/unit_doctrine.gd").sanitize({})
	bm._decide_mortar_action(mortar)
	check(bm._pending_mortar_displacement.has(mortar) or mortar.has_move_target, "A crew standing in the region with nothing to do sets about moving out")
	bm.combat_log.free()


## "The mortar also has no retreat path": a crew retreating from Voznesensk's default position, across the town to the west edge.
func test_a_retreating_crew_crosses_the_town_to_the_west_edge() -> void:
	GameConfig.set_active_map("voznesensk")
	var bm = make_battle()
	var start: Vector2 = GameConfig.CURRENT_MAP.player.mortar_default_position
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, start)
	bm.player_units.append(mortar)
	bm._set_retreat_profile(mortar, Unit.Team.PLAYER)
	mortar.state = Unit.State.RETREATING
	mortar.has_move_target = false
	var inside := 0
	var ticks := 0
	while ticks < 40000 and mortar.position.x > mortar.retreat_target_x + m(5.0).x:
		bm._tick_movement(5.0)
		if GameConfig.mortar_excluded_at(mortar.position):
			inside += 1
		ticks += 1
	check(mortar.position.x <= mortar.retreat_target_x + m(5.0).x, "The retreating crew reaches the west edge (x %.0f m after %d ticks)" % [mortar.position.x / GameConfig.PIXELS_PER_METER, ticks])
	check(inside > 0, "...and it went through the red area to do it (%d ticks inside): that is allowed" % inside)
	# On a map where the straight run is already clear, nothing changes: it dashes straight.
	GameConfig.set_active_map("svystunivka")
	var bm2 = make_battle()
	var home: Vector2 = GameConfig.CURRENT_MAP.player.mortar_default_position
	var m2: Unit = bm2._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, home)
	bm2.player_units.append(m2)
	bm2._set_retreat_profile(m2, Unit.Team.PLAYER)
	m2.state = Unit.State.RETREATING
	m2.has_move_target = false
	bm2._tick_movement(5.0)
	check(not m2.has_move_target, "A clear straight run west is left as it was (no route issued)")
	bm.combat_log.free()
	bm2.combat_log.free()
	GameConfig.set_active_map("pishchane")


func run() -> void:
	test_every_map_has_a_sensible_region()
	test_it_bars_the_player_mortar_only()
	test_player_mortar_never_plans_to_set_up_inside_the_region()
	test_a_crew_may_walk_through_the_region()
	test_it_cannot_fire_from_inside_the_region()
	test_a_crew_standing_in_the_region_moves_out()
	test_a_retreating_crew_crosses_the_town_to_the_west_edge()
	print("Mortar exclusion region tests: %d failures" % failures)
	quit(1 if failures else 0)
