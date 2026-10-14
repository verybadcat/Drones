extends SceneTree
## Research harness (the folder is ignored by Godot: copy it under scripts/ to run). User: "In four salvoes, our mortar has knocked out
## three enemy mortars." A single round of one salvo was found to catch two enemy crews 11 m and 45 m from it, both walking: the
## relocating mortars had come together. This samples, every 5 s of the first HORIZON_S seconds of every battle (every map, TRIALS
## seeds, Drone Recon, default doctrine), the distance between each pair of the enemy's mortars that are both still in the fight (not
## destroyed or withdrawn), and reports how often a pair is within 25 / 50 / 75 / 100 m (one round catches both with real probability),
## how many battles ever have such a pair, and for how long, with the pair's activity (still / on the move).
const TestBattleManagerScript := preload("res://scripts/tests/test_battle_manager.gd")
const TestCombatLogScript := preload("res://scripts/tests/test_combat_log.gd")

const TRIALS := 16
const TICK_DELTA := 0.5
const HORIZON_S := 1800.0
const SAMPLE_S := 5.0
const BANDS := [25.0, 50.0, 75.0, 100.0]

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
	var battles := 0
	var multi := 0
	var pair_samples := 0
	var in_band := {}
	var battles_with := {}
	var seconds_with := {}
	for b in BANDS:
		in_band[b] = 0
		battles_with[b] = 0
		seconds_with[b] = 0.0
	var close_state := {"both_moving": 0, "one_moving": 0, "both_still": 0}
	var where := {}
	for map_id in GameConfig.MAPS.keys():
		GameConfig.set_active_map(map_id)
		where[map_id] = {"battles": 0, "with75": 0}
		for t in TRIALS:
			seed(1000 + t)
			var bm = TestBattleManagerScript.new()
			root.add_child(bm)
			var log = TestCombatLogScript.new()
			bm.start_battle(doctrine(), log)
			var foes: Array[Unit] = []
			for e in bm.enemy_units:
				if e.kind == Unit.Kind.MORTAR:
					foes.append(e)
			battles += 1
			where[map_id].battles += 1
			if foes.size() > 1:
				multi += 1
			var seen_band := {}
			var next_sample := 0.0
			var ticks := 0
			while not bm.battle_over and bm.scenario_elapsed_time < HORIZON_S and ticks < int(HORIZON_S / TICK_DELTA) + 10:
				bm._process(TICK_DELTA)
				ticks += 1
				if bm.scenario_elapsed_time < next_sample:
					continue
				next_sample = bm.scenario_elapsed_time + SAMPLE_S
				for i in foes.size():
					for j in range(i + 1, foes.size()):
						var a: Unit = foes[i]
						var c: Unit = foes[j]
						if not (is_instance_valid(a) and is_instance_valid(c)):
							continue
						if a.state != Unit.State.ACTIVE or c.state != Unit.State.ACTIVE:
							continue
						pair_samples += 1
						var d: float = a.global_position.distance_to(c.global_position) / GameConfig.PIXELS_PER_METER
						for b in BANDS:
							if d <= b:
								in_band[b] += 1
								seconds_with[b] += SAMPLE_S
								seen_band[b] = true
						if d <= 75.0:
							var am: bool = a.activity == Unit.Activity.MOVING
							var cm: bool = c.activity == Unit.Activity.MOVING
							if am and cm:
								close_state.both_moving += 1
							elif am or cm:
								close_state.one_moving += 1
							else:
								close_state.both_still += 1
			for b in BANDS:
				if seen_band.has(b):
					battles_with[b] += 1
			if seen_band.has(75.0):
				where[map_id].with75 += 1
			if is_instance_valid(log):
				log.free()
			bm.queue_free()
			await process_frame
	print("battles: %d (%d with two or more enemy mortars); pair samples (both in the fight, every %.0f s of the first %.0f min): %d" % [battles, multi, SAMPLE_S, HORIZON_S / 60.0, pair_samples])
	for b in BANDS:
		print("  pair within %3.0f m: %.1f%% of samples, %d battles (%.0f%% of the battles with two or more), %.0f s in all" % [b, 100.0 * in_band[b] / maxf(pair_samples, 1), battles_with[b], 100.0 * battles_with[b] / maxf(multi, 1), seconds_with[b]])
	print("within 75 m: both moving %d, one moving %d, both still %d samples" % [close_state.both_moving, close_state.one_moving, close_state.both_still])
	for map_id in where:
		print("  %s: %d battles, %d with a pair within 75 m" % [map_id, where[map_id].battles, where[map_id].with75])
	quit()
