extends SceneTree
const TestBattleManagerScript := preload("res://scripts/tests/test_battle_manager.gd")
const TestCombatLogScript := preload("res://scripts/tests/test_combat_log.gd")
func _initialize():
	call_deferred("run")
func doctrine(mode, retreat := 0.30) -> Dictionary:
	var squads: Array[Dictionary] = []
	for pos in GameConfig.CURRENT_MAP.player.default_squad_positions:
		squads.append({"position": pos, "retreat_threshold": retreat})
	return {"squads": squads, "mortar": {"position": GameConfig.CURRENT_MAP.player.mortar_default_position, "shoot_and_scoot": true},
		"spotter": {"position": GameConfig.CURRENT_MAP.player.spotter_default_position}, "recon_mode": mode}
func run():
	var maps: Array = []
	var a := OS.get_cmdline_user_args()
	var trials := 3
	for s in a:
		if s.begins_with("--maps="): maps = s.substr(7).split(",")
		if s.begins_with("--trials="): trials = int(s.substr(9))
	for map_id in maps:
		GameConfig.set_active_map(map_id)
		var total_ticks := 0
		var total_ms := 0.0
		var held := 0
		var hung := 0
		var t_setup := 0.0
		for t in trials:
			var mode = GameConfig.ReconMode.SPOTTER if t % 2 == 0 else GameConfig.ReconMode.DRONE_TEAM
			var bm = TestBattleManagerScript.new()
			root.add_child(bm)
			var log = TestCombatLogScript.new()
			var t0 := Time.get_ticks_usec()
			bm.start_battle(doctrine(mode), log)
			t_setup += (Time.get_ticks_usec() - t0) / 1000.0
			var ticks := 0
			var t1 := Time.get_ticks_usec()
			var south := 0
			var seen := {}
			var unit_ticks := 0
			var maxy := 0.0
			var minx := 1e9
			while not bm.battle_over and ticks < 12000:
				bm._process(0.5)
				ticks += 1
				for u in bm.enemy_units + bm.player_units:
					if u.kind == Unit.Kind.DRONE: continue
					unit_ticks += 1
					var ym: float = u.global_position.y / GameConfig.PIXELS_PER_METER
					maxy = max(maxy, ym)
					minx = min(minx, u.global_position.x / GameConfig.PIXELS_PER_METER)
					if ym > GameConfig.MAP_HEIGHT_M - 60.0 or ym < 60.0:
						south += 1
						if not seen.has(u):
							seen[u] = true
							if false: print("      first south: tick %d %s state=%s pos=(%.0f,%.0f) reason=%s" % [ticks, u.display_name(), Unit.State.keys()[u.state], u.global_position.x / GameConfig.PIXELS_PER_METER, ym, u.last_order_reason])
			print("   trial %d: ticks=%d unit-ticks south of y=2150: %d (%.1f%%), max y %.0f, min x %.0f" % [t, ticks, south, 100.0 * south / max(unit_ticks, 1), maxy, minx])
			total_ms += (Time.get_ticks_usec() - t1) / 1000.0
			total_ticks += ticks
			if not bm.battle_over: hung += 1
			elif bm._has_active_units(bm.player_units): held += 1
			bm.queue_free()
		print("%-12s trials=%d  ticks=%d  ms/tick=%.2f  setup ms/trial=%.0f  held=%d hung=%d" % [map_id, trials, total_ticks, total_ms / max(total_ticks, 1), t_setup / trials, held, hung])
	quit()
