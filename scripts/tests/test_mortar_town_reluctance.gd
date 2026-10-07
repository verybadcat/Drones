extends SceneTree
## Direct user instruction: "Ukrainian mortar should be reluctant to fire at targets inside the city. Say within 50 meters of a building.
## Not the 200 meter exclusion zone. 'Reluctant' doesn't mean they can't. Just that they are less likely to." And: "a mortar inside the city
## would still draw fire. But if there are two squads and one is in it and the other isn't, probably pick the one that is outside."
##
## What this checks, on Voznesensk: a squad within 50 m of a building is worth half to the Ukrainian mortar when choosing; given a squad in the
## town and one outside, the one outside is picked most of the time and the one in town sometimes; with only a squad in town the mortar
## fires on it some of the time, not never and not always; an enemy mortar in town is still fired on every time; the Russian mortar has no
## such reluctance.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_town_reluctance.gd
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


## A point 30 m from a building block and one at least 150 m from any, both in the open and on level-ish ground, east of the town.
func find_points() -> Array:
	var in_town := Vector2.INF
	for z in GameConfig.CURRENT_MAP.terrain_zones:
		if z.type == GameConfig.TerrainType.BUILDING and z.rect.size.x > m(40.0).x and z.rect.position.x > m(600.0).x:
			var p := Vector2(z.rect.position.x - m(30.0).x, z.rect.get_center().y)
			if not GameConfig.is_building_at(p) and GameConfig.near_building(p, 50.0) and not GameConfig.is_in_cover(GameConfig.get_terrain_type_at(p)):
				in_town = p
				break
	if is_inf(in_town.x):
		return []
	for dx in range(-1500, 1500, 100):
		for dy in range(-1500, 1500, 100):
			var q: Vector2 = in_town + m(float(dx), float(dy))
			if q.x < m(600.0).x or q.y < m(100.0).y or q.y > GameConfig.MAP_HEIGHT_PX - m(100.0).y:
				continue
			if not GameConfig.near_building(q, 150.0) and not GameConfig.is_in_cover(GameConfig.get_terrain_type_at(q)) and not GameConfig.mortar_barred_at(q, Unit.Team.PLAYER):
				return [in_town, q]
	return []


func make_scene(bm, points: Array, kinds: Array) -> Unit:
	var mortar_at: Vector2 = points[1] + m(-1500.0)
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, mortar_at)
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = 25
	mortar.seconds_stationary = 1e9
	for i in kinds.size():
		var t: Unit = bm._make_unit(Unit.Team.ENEMY, kinds[i], points[i])
		bm.enemy_units.append(t)
		t.is_visible = true
	var observer: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, points[1] + m(0.0, 120.0))
	bm.player_units.append(observer)
	bm.unit_type_doctrines[Unit.Team.PLAYER] = preload("res://scripts/unit_doctrine.gd").sanitize({})
	bm._update_player_intel()
	return mortar


func run() -> void:
	GameConfig.set_active_map("voznesensk")
	var pts := find_points()
	check(pts.size() == 2, "Setup: a spot beside a building and an open spot far from any")
	if pts.size() < 2:
		quit(1)
		return
	check(GameConfig.near_building(pts[0], 50.0) and not GameConfig.near_building(pts[1], 50.0), "Setup: one is within 50 m of a building, the other is not")

	# 1. value
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var mortar: Unit = make_scene(bm, pts, [Unit.Kind.SQUAD, Unit.Kind.SQUAD])
	var in_town: Unit = bm.enemy_units[0]
	var outside: Unit = bm.enemy_units[1]
	in_town.pips = outside.pips
	var v_in: float = bm._enemy_target_value(mortar, in_town)
	var v_out: float = bm._enemy_target_value(mortar, outside)
	check(v_in < v_out, "A squad in the town is worth less to the Ukrainian mortar than the same squad outside (%.2f against %.2f)" % [v_in, v_out])
	check(absf(v_in - v_out * GameConfig.MORTAR_TOWN_TARGET_VALUE_MULTIPLIER) < 0.6 * v_out, "...about the set fraction of it (%.2f of %.2f)" % [v_in, v_out])

	# 2. choice between the two: the one outside most of the time, the one in town sometimes
	seed(11)
	var picked_in := 0
	var picked_out := 0
	var nothing := 0
	for i in 600:
		var pick: Unit = bm._pick_target(mortar, bm.enemy_units)
		if pick == in_town:
			picked_in += 1
		elif pick == outside:
			picked_out += 1
		else:
			nothing += 1
	check(picked_out > picked_in, "Given a squad in the town and one outside, the one outside is picked more often (%d against %d)" % [picked_out, picked_in])
	check(picked_in > 0, "...but the one in the town is still sometimes fired on (%d)" % picked_in)

	# 3. only a squad in town: fired on some of the time
	bm.enemy_units.clear()
	var lone: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, pts[0])
	bm.enemy_units.append(lone)
	lone.is_visible = true
	bm._update_player_intel()
	var fired_town := 0
	for i in 600:
		if bm._pick_target(mortar, bm.enemy_units) == lone:
			fired_town += 1
	bm.enemy_units.clear()
	var lone_out: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, pts[1])
	bm.enemy_units.append(lone_out)
	lone_out.is_visible = true
	bm._update_player_intel()
	var fired_open := 0
	for i in 600:
		if bm._pick_target(mortar, bm.enemy_units) == lone_out:
			fired_open += 1
	check(fired_open > 0, "Setup: it fires on a lone squad in the open (%d of 600)" % fired_open)
	check(fired_town > 0, "It does fire on a lone squad in the town (%d of 600)" % fired_town)
	check(float(fired_town) < 0.8 * float(fired_open), "...but markedly less often than on one in the open (%d against %d of 600)" % [fired_town, fired_open])

	# 4. an enemy mortar in town is still fired on
	bm.enemy_units.clear()
	var enemy_mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, pts[0])
	bm.enemy_units.append(enemy_mortar)
	enemy_mortar.is_visible = true
	bm._update_player_intel()
	var fired_at_mortar := 0
	for i in 300:
		if bm._pick_target(mortar, bm.enemy_units) == enemy_mortar:
			fired_at_mortar += 1
	check(fired_at_mortar > 0.85 * 300.0, "An enemy mortar in the town still draws fire (%d of 300)" % fired_at_mortar)

	# 5. the Russian mortar has no such reluctance
	check(not bm._mortar_is_reluctant_toward(enemy_mortar, lone), "The Russian mortar is not reluctant about a Ukrainian squad in the town")
	check(bm._mortar_is_reluctant_toward(mortar, lone), "The Ukrainian mortar is, about a squad there")
	check(not bm._mortar_is_reluctant_toward(mortar, enemy_mortar), "...but not about a mortar there")
	bm.combat_log.free()
	bm.free()
	print("Mortar town reluctance tests: %d failures" % failures)
	quit(1 if failures else 0)
