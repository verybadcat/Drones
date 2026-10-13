extends SceneTree
## Research harness (the folder is ignored by Godot: copy it under scripts/ to run): how long does ONE friendly squad last when four
## enemy squads stand round it, by what it is standing in (a building, trees, the open) and whether it is dug in. User: "why surrounded
## friendly troops seem to hang on so well. Is that believable in real world terms?"
##
## The rest of both sides is out of the way (withdrawn) and the enemy has no mortar, so this is infantry against infantry only. The enemy
## squads start 250 m from the squad on the four bearings and are otherwise as the game leaves them.
const TestBattleManagerScript := preload("res://scripts/tests/test_battle_manager.gd")
const TestCombatLogScript := preload("res://scripts/tests/test_combat_log.gd")

const TRIALS := 12
const TICK_DELTA := 0.5
const MAX_TICKS := 480 # 4 hours at 30 s of battle time a tick

func _initialize() -> void:
	call_deferred("run")

func m(x: float, y: float = 0.0) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

func place_for(kind: String) -> Dictionary:
	if kind == "building":
		GameConfig.set_active_map("voznesensk")
		GameConfig._build_terrain_grid()
		return {"map": "voznesensk", "pos": GameConfig._building_rects[0].get_center()}
	if kind == "trees":
		GameConfig.set_active_map("pishchane")
		return {"map": "pishchane", "pos": m(-20, 2080)}
	GameConfig.set_active_map("voznesensk")
	GameConfig._build_terrain_grid()
	var rect: Rect2 = GameConfig._building_rects[0]
	for dx in [-90.0, 90.0, -140.0, 140.0]:
		var p: Vector2 = Vector2(rect.position.x if dx < 0.0 else rect.end.x, rect.get_center().y) + Vector2(dx, 0.0) * GameConfig.PIXELS_PER_METER
		if GameConfig.get_terrain_type_at(p) == GameConfig.TerrainType.OPEN:
			return {"map": "voznesensk", "pos": p}
	return {"map": "voznesensk", "pos": Vector2.INF}

func run() -> void:
	for kind in ["building", "trees", "open"]:
		for dug in [false, true]:
			var where := place_for(kind)
			if is_inf(where.pos.x):
				print("%s: no place" % kind)
				continue
			var ended := {"destroyed": 0, "retreating": 0, "surrendered": 0, "withdrawn": 0, "active": 0}
			var minutes_total := 0.0
			var lost_total := 0.0
			var killed_total := 0.0
			var shots_total := 0.0
			var half_gone_total := 0.0
			var half_gone_n := 0
			for t in TRIALS:
				seed(7000 + t)
				GameConfig.set_active_map(where.map)
				if kind == "building" or kind == "open":
					GameConfig._build_terrain_grid()
				var bm = TestBattleManagerScript.new()
				root.add_child(bm)
				var log = TestCombatLogScript.new()
				var doctrine := {
					"squads": [{"position": where.pos, "retreat_threshold": 0.5}],
					"mortar": {"position": GameConfig.CURRENT_MAP.player.mortar_default_position, "shoot_and_scoot": true},
					"spotter": {"position": GameConfig.CURRENT_MAP.player.spotter_default_position},
					"recon_mode": GameConfig.ReconMode.DRONE_TEAM,
				}
				bm.start_battle(doctrine, log)
				var squad: Unit = null
				for u in bm.player_units:
					if u.kind == Unit.Kind.SQUAD and squad == null:
						squad = u
					elif u.kind != Unit.Kind.DRONE:
						u.state = Unit.State.WITHDRAWN
				squad.global_position = where.pos
				if not dug:
					squad.entrenchment = Unit.Entrenchment.NONE
					squad.digging_seconds = 0.0
				squad.dig_anchor = squad.global_position
				var ring := 0
				var bearings := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
				var enemy_total := 0
				for e in bm.enemy_units:
					if e.kind == Unit.Kind.SQUAD and ring < 4:
						e.global_position = where.pos + bearings[ring] * m(250).x
						e.sought_cover = true
						e.has_move_target = false
						e.move_queue.clear()
						e.entrenchment = Unit.Entrenchment.NONE
						e.dig_anchor = e.global_position
						ring += 1
						enemy_total += e.max_pips
					else:
						e.state = Unit.State.WITHDRAWN
				var ticks := 0
				var half_gone_at := -1.0
				while ticks < MAX_TICKS and squad.state == Unit.State.ACTIVE and not bm.battle_over:
					bm._process(TICK_DELTA)
					ticks += 1
					if half_gone_at < 0.0 and squad.pips <= squad.max_pips / 2:
						half_gone_at = bm.scenario_elapsed_time / 60.0
				var key: String = Unit.State.keys()[squad.state].to_lower()
				ended[key if ended.has(key) else "active"] += 1
				minutes_total += bm.scenario_elapsed_time / 60.0
				lost_total += float(squad.max_pips - squad.pips)
				var killed := 0
				for e in bm.enemy_units:
					if e.kind == Unit.Kind.SQUAD and e.state != Unit.State.WITHDRAWN:
						killed += e.max_pips - e.pips
				killed_total += killed
				if half_gone_at >= 0.0:
					half_gone_total += half_gone_at
					half_gone_n += 1
				if is_instance_valid(log):
					log.free()
				bm.queue_free()
				await process_frame
			print("%-8s %-8s: ended %s; mean %.0f min; squad lost %.1f of 9; killed %.1f of the ring's 36; reached half gone in %s" % [
				kind, "dug in" if dug else "not dug", str(ended), minutes_total / TRIALS, lost_total / TRIALS, killed_total / TRIALS,
				("%.0f min on average (%d of %d)" % [half_gone_total / half_gone_n, half_gone_n, TRIALS]) if half_gone_n > 0 else "never"])
	quit()
