extends SceneTree
## The enemy's formation at the start of the march. User: "There is no law requiring the enemy squads to advance in a line as they do.
## They could be spread out in both the X and Y directions." Rows across the march, at least 75 m between any two squads (the player's
## own preferred spacing), 110 m between rows, alternate rows staggered, the leading rows starting further west, each squad's path
## beginning at the first road waypoint west of where it starts. Up to what fits in one row (seven across the 520 m span) it is one row,
## as before.
##
## Run: godot --headless --path . --script scripts/tests/test_enemy_layout.gd
const TestBattleManagerScript := preload("res://scripts/tests/test_battle_manager.gd")
const TestCombatLogScript := preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var min_gap: float = GameConfig.ENEMY_ADVANCE_MIN_SPACING_M
	for map_id in GameConfig.MAPS.keys():
		GameConfig.set_active_map(map_id)
		var enemy: Dictionary = GameConfig.CURRENT_MAP.enemy
		var span: float = enemy.squad_spread_max_offset_m - enemy.squad_spread_min_offset_m
		var capacity: int = int(floor(span / min_gap)) + 1
		for n in range(1, 16):
			var layout: Array[Vector2] = GameConfig.enemy_squad_layout_m(n)
			check(layout.size() == n, "%s: %d squads laid out (%d)" % [map_id, n, layout.size()])
			var nearest := INF
			var rows := {}
			var in_span := true
			for i in layout.size():
				rows[snappedf(layout[i].x, 0.1)] = true
				# the spread is a preference: a staggered row may stand half a step (at most 130 m for two squads...) beyond it
				if layout[i].y < enemy.squad_spread_min_offset_m - 0.01 or layout[i].y > enemy.squad_spread_max_offset_m + 0.5 * span + 0.01:
					in_span = false
				for j in range(i + 1, layout.size()):
					nearest = minf(nearest, layout[i].distance_to(layout[j]))
			check(in_span, "%s, %d squads: all within the spread across the march (a staggered row half a step over)" % [map_id, n])
			if n > 1:
				check(nearest >= min_gap - 0.01, "%s, %d squads: no two closer than %.0f m (%.1f)" % [map_id, n, min_gap, nearest])
			var expected_rows: int = int(ceil(float(n) / float(capacity)))
			check(rows.size() == expected_rows, "%s, %d squads: %d row(s) (%d)" % [map_id, n, expected_rows, rows.size()])
			if expected_rows == 1:
				check(rows.has(0.0), "%s, %d squads: one row, on the spawn line" % [map_id, n])
			else:
				var xs: Array = rows.keys()
				xs.sort()
				check(xs[xs.size() - 1] == 0.0 and xs[0] < 0.0, "%s, %d squads: the last row on the spawn line, the leading rows further west" % [map_id, n])
				for k in range(1, xs.size()):
					check(absf((xs[k] - xs[k - 1]) - GameConfig.ENEMY_ADVANCE_ROW_DEPTH_M) < 0.2, "%s, %d squads: rows %.0f m apart" % [map_id, n, GameConfig.ENEMY_ADVANCE_ROW_DEPTH_M])

	# the real spawn: nobody closer than the minimum (a little under for rounding of squad positions), every path heads west first
	for map_id in GameConfig.MAPS.keys():
		GameConfig.set_active_map(map_id)
		for seed_value in [1000, 1001, 1002, 1003, 1004]:
			seed(seed_value)
			var bm = TestBattleManagerScript.new()
			root.add_child(bm)
			var log = TestCombatLogScript.new()
			var squads: Array[Dictionary] = []
			for pos in GameConfig.CURRENT_MAP.player.default_squad_positions:
				squads.append({"position": pos, "retreat_threshold": 0.5})
			var doctrine := {
				"squads": squads,
				"mortar": {"position": GameConfig.CURRENT_MAP.player.mortar_default_position, "shoot_and_scoot": true},
				"spotter": {"position": GameConfig.CURRENT_MAP.player.spotter_default_position},
				"recon_mode": GameConfig.ReconMode.DRONE_TEAM,
			}
			bm.start_battle(doctrine, log)
			var foes: Array[Unit] = []
			for e in bm.enemy_units:
				if e.kind == Unit.Kind.SQUAD:
					foes.append(e)
			var nearest := INF
			for i in foes.size():
				check(foes[i].has_move_target and foes[i].move_target.x <= foes[i].global_position.x + 1.0, "%s: squad %d starts out heading west" % [map_id, i])
				for j in range(i + 1, foes.size()):
					nearest = minf(nearest, foes[i].global_position.distance_to(foes[j].global_position))
			if foes.size() > 1:
				check(nearest / GameConfig.PIXELS_PER_METER >= min_gap - 0.5, "%s seed %d, %d squads: nearest two %.1f m apart" % [map_id, seed_value, foes.size(), nearest / GameConfig.PIXELS_PER_METER])
			if is_instance_valid(log):
				log.free()
			bm.queue_free()
			await process_frame

	print("Enemy layout tests: %d failures" % failures)
	quit(1 if failures else 0)
