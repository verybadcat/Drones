extends SceneTree
## Research harness (the folder is ignored by Godot: copy it under scripts/ to run). User, 2026-10-24: "Squads should try to move to cover." How much of the time
## are squads that are standing still actually in cover (trees or a building) or dug in, and how much of the time are they in the open? Every 30 s of battle time
## it reads each ACTIVE squad's activity (moving or standing), the terrain at its centre and its entrenchment, for each side, over every map and TRIALS seeds
## (Drone Recon, default doctrine). Prints the shares.
const TestBattleManagerScript := preload("res://scripts/tests/test_battle_manager.gd")
const TestCombatLogScript := preload("res://scripts/tests/test_combat_log.gd")

const TRIALS := 40
const TICK_DELTA := 0.5
const MAX_TICKS := 30000
const SAMPLE_EVERY_S := 30.0

func _initialize() -> void:
	call_deferred("run")

func doctrine() -> Dictionary:
	var squads: Array[Dictionary] = []
	for pos in GameConfig.CURRENT_MAP.player.default_squad_positions:
		squads.append({"position": pos, "retreat_threshold": 0.5})
	return {
		"squads": squads,
		"mortar": {"position": GameConfig.CURRENT_MAP.player.mortar_default_position, "shoot_and_scoot": true},
		"spotter": {"position": GameConfig.CURRENT_MAP.player.spotter_default_position},
		"recon_mode": GameConfig.ReconMode.DRONE_TEAM,
	}

func run() -> void:
	# key "side|standing/moving" -> [open, trees, building, dug in (a hole), samples]
	var tally := {}
	for map_id in GameConfig.MAPS.keys():
		GameConfig.set_active_map(map_id)
		for t in TRIALS:
			seed(1000 + t)
			var bm = TestBattleManagerScript.new()
			root.add_child(bm)
			var log = TestCombatLogScript.new()
			bm.start_battle(doctrine(), log)
			var next_sample := SAMPLE_EVERY_S
			var ticks := 0
			while not bm.battle_over and ticks < MAX_TICKS:
				bm._process(TICK_DELTA)
				ticks += 1
				if bm.scenario_elapsed_time < next_sample:
					continue
				next_sample = bm.scenario_elapsed_time + SAMPLE_EVERY_S
				for u in bm.player_units + bm.enemy_units:
					if u.kind != Unit.Kind.SQUAD or u.state != Unit.State.ACTIVE:
						continue
					var key: String = ("Ukrainian" if u.team == Unit.Team.PLAYER else "Russian") + (" moving" if u.activity == Unit.Activity.MOVING else " standing")
					var row: Array = tally.get(key, [0, 0, 0, 0, 0])
					var terrain: GameConfig.TerrainType = GameConfig.get_terrain_type_at(u.global_position)
					if terrain == GameConfig.TerrainType.TREES:
						row[1] += 1
					elif terrain == GameConfig.TerrainType.BUILDING:
						row[2] += 1
					else:
						row[0] += 1
					if u.entrenchment != Unit.Entrenchment.NONE:
						row[3] += 1
					row[4] += 1
					tally[key] = row
			if is_instance_valid(log):
				log.free()
			bm.queue_free()
			await process_frame
	var keys: Array = tally.keys()
	keys.sort()
	for k in keys:
		var r: Array = tally[k]
		var n: float = maxf(float(r[4]), 1.0)
		print("%-18s samples %d: in the open %.0f%%, in trees %.0f%%, in a building %.0f%%; with a scrape or a fighting position %.0f%%" % [k, r[4], 100.0 * r[0] / n, 100.0 * r[1] / n, 100.0 * r[2] / n, 100.0 * r[3] / n])
	quit()
