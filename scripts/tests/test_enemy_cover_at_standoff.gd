extends SceneTree
## Everybody prefers cover, both sides. User, 2026-10-24: "Everybody should prefer cover. Both sides." Our squads already move into available cover whenever
## they have no reason to stand in the open (BattleManager._update_friendly_squad_positioning). The enemy's mirror (BattleManager._enemy_squad_to_cover): a squad
## that has halted at its standoff ring with nothing to shoot at, standing in the open, goes to cover nearby that is inside the ring; a squad already in cover or
## in a fighting position stays.
##
## Run: godot --headless --path . --script scripts/tests/test_enemy_cover_at_standoff.gd
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

func make_battle() -> BattleManager:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	return bm

func enemy_at(bm: BattleManager, pos: Vector2) -> Unit:
	var e: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, pos)
	e.sought_cover = true # off the scripted march
	bm.enemy_units.append(e)
	return e

func run() -> void:
	GameConfig.set_active_map("voznesensk")
	GameConfig._build_terrain_grid()
	var bm := make_battle()
	var probe: Unit = enemy_at(bm, m(2500, 1900))
	var objective: Vector2 = bm._enemy_advance_objective(probe)
	var ring: float = GameConfig.ENEMY_SURROUND_STANDOFF_RADIUS
	# a place in the open, inside the ring (between half of it and all of it from the objective), whose nearest cover is also inside the ring
	var spot := Vector2.INF
	var cover := Vector2.INF
	for radius in [0.9, 0.8, 0.7, 0.6]:
		for step in 72:
			var p: Vector2 = objective + Vector2.from_angle(TAU * float(step) / 72.0) * ring * radius
			if GameConfig.get_terrain_type_at(p) != GameConfig.TerrainType.OPEN:
				continue
			var c: Vector2 = GameConfig.nearest_cover_point(p, 0.0, false, [], [])
			if c == p:
				continue
			var d: float = c.distance_to(objective)
			if d < ring and d >= 0.5 * ring and c.distance_to(p) > 15.0 * GameConfig.PIXELS_PER_METER:
				spot = p
				cover = c
				break
		if not is_inf(spot.x):
			break
	check(not is_inf(spot.x), "setup: a place in the open inside the ring with cover inside it")
	if is_inf(spot.x):
		quit(1)
		return
	bm.enemy_units.erase(probe)
	probe.free()

	# 1. halted in the open at the ring, nothing to shoot at: it goes to cover (which of the nearest cover points it is given is a roll, and one outside the ring is
	# refused, so over many squads: some are sent, and every one that is sent is sent to cover inside the ring)
	var sent := 0
	var all_in_cover := true
	var all_in_ring := true
	var reason_ok := true
	for i in 30:
		var e: Unit = enemy_at(bm, spot)
		bm._update_enemy_squad_advance()
		if e.has_move_target:
			sent += 1
			all_in_cover = all_in_cover and GameConfig.is_in_cover(GameConfig.get_terrain_type_at(e.move_target))
			all_in_ring = all_in_ring and e.move_target.distance_to(objective) < ring
			reason_ok = reason_ok and e.last_order_reason == "Moving into available cover."
		bm.enemy_units.erase(e)
		e.free()
	check(sent >= 10, "a squad halted in the open at its standoff ring is usually sent somewhere (%d of 30)" % sent)
	check(all_in_cover, "...to a place in cover")
	check(all_in_ring, "...inside the ring, so that it stays held there")
	check(reason_ok, "...and says why")

	# 2. already in cover: it stays
	var in_cover: Unit = enemy_at(bm, cover)
	check(GameConfig.is_in_cover(in_cover.terrain_type()), "setup: that cover point is cover")
	bm._update_enemy_squad_advance()
	check(not in_cover.has_move_target, "a squad already in cover stays")

	# 3. in a fighting position in the open: it stays in its hole
	var dug: Unit = enemy_at(bm, spot + m(0, 120))
	if GameConfig.get_terrain_type_at(dug.global_position) == GameConfig.TerrainType.OPEN:
		dug.entrenchment = Unit.Entrenchment.FIGHTING_POSITION
		bm._update_enemy_squad_advance()
		check(not dug.has_move_target, "a squad in a fighting position stays in it")

	print("Enemy cover at the standoff ring tests: %d failures" % failures)
	bm.combat_log.free()
	bm.free()
	quit(1 if failures else 0)
