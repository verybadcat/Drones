extends SceneTree
## Research harness (the folder is ignored by Godot: copy it under scripts/ to run). User, after watching a battle: "whether the enemy
## squads are too close together when advancing at the beginning? That's how they took most of their casualties."
## Measures, over every map and TRIALS seeds (Drone Recon, default doctrine): (1) the distance from each ACTIVE enemy squad to its nearest
## fellow squad, at set times from the start of the battle (the squads are walking in at the beginning); (2) what our mortar's rounds
## caught: how many rounds, how many caught an enemy squad, how many caught two or more enemy squads at once, and when the enemy's
## casualties from them came (by minute from the start) and whether the squad was moving when it was hit.
const TestBattleManagerScript := preload("res://scripts/tests/test_battle_manager.gd")
const TestCombatLogScript := preload("res://scripts/tests/test_combat_log.gd")

const TRIALS := 12
const TICK_DELTA := 0.5
const MAX_TICKS := 12000
const SAMPLE_MINUTES := [0, 5, 10, 15, 20, 30, 45, 60]

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

func nearest_gaps_m(bm) -> Array[float]:
	var squads: Array[Unit] = []
	for e in bm.enemy_units:
		if e.kind == Unit.Kind.SQUAD and e.state == Unit.State.ACTIVE:
			squads.append(e)
	var out: Array[float] = []
	for a in squads:
		var best := INF
		for b in squads:
			if a != b:
				best = minf(best, a.global_position.distance_to(b.global_position))
		if not is_inf(best):
			out.append(best / GameConfig.PIXELS_PER_METER)
	return out

func run() -> void:
	var gaps_at := {}
	for m in SAMPLE_MINUTES:
		gaps_at[m] = []
	var squads_per_battle := []
	var rounds := 0
	var rounds_on_squads := 0
	var rounds_on_two_plus := 0
	var cas_total := 0
	var cas_multi := 0
	var cas_moving := 0
	var cas_by_minute := {}
	var battles := 0
	for map_id in GameConfig.MAPS.keys():
		GameConfig.set_active_map(map_id)
		for t in TRIALS:
			seed(1000 + t)
			var bm = TestBattleManagerScript.new()
			root.add_child(bm)
			var log = TestCombatLogScript.new()
			bm.start_battle(doctrine(), log)
			var n := 0
			for e in bm.enemy_units:
				if e.kind == Unit.Kind.SQUAD:
					n += 1
			squads_per_battle.append(n)
			var ticks := 0
			var next_sample := 0
			while not bm.battle_over and ticks < MAX_TICKS and next_sample < SAMPLE_MINUTES.size():
				if bm.scenario_elapsed_time >= float(SAMPLE_MINUTES[next_sample]) * 60.0:
					gaps_at[SAMPLE_MINUTES[next_sample]].append_array(nearest_gaps_m(bm))
					next_sample += 1
				bm._process(TICK_DELTA)
				ticks += 1
			for entry in bm.shell_landing_log:
				if entry.team != Unit.Team.PLAYER:
					continue
				rounds += 1
				var squads_hit := 0
				var round_cas := 0
				for v in entry.victims:
					if v.team == Unit.Team.ENEMY and v.kind == Unit.Kind.SQUAD:
						squads_hit += 1
						round_cas += v.casualties
						if v.moving:
							cas_moving += v.casualties
				if squads_hit >= 1:
					rounds_on_squads += 1
				if squads_hit >= 2:
					rounds_on_two_plus += 1
					cas_multi += round_cas
				cas_total += round_cas
				var minute: int = int(float(entry.time) / 60.0 / 5.0) * 5
				cas_by_minute[minute] = int(cas_by_minute.get(minute, 0)) + round_cas
			battles += 1
			if is_instance_valid(log):
				log.free()
			bm.queue_free()
			await process_frame
	var sizes := squads_per_battle.duplicate()
	sizes.sort()
	print("battles: %d; enemy squads per battle: median %d (min %d, max %d)" % [battles, sizes[sizes.size() / 2], sizes[0], sizes[sizes.size() - 1]])
	print("distance from each enemy squad to its nearest fellow squad, by minutes from the start of the battle (metres):")
	for m in SAMPLE_MINUTES:
		var g: Array = gaps_at[m]
		if g.is_empty():
			continue
		g.sort()
		var below_75 := 0
		var below_50 := 0
		for x in g:
			if x < 75.0:
				below_75 += 1
			if x < 50.0:
				below_50 += 1
		print("  %3d min: median %.0f, lower quartile %.0f, %.0f%% under 75 m, %.0f%% under 50 m (%d squad samples)" % [m, g[g.size() / 2], g[g.size() / 4], 100.0 * below_75 / g.size(), 100.0 * below_50 / g.size(), g.size()])
	print("our mortar's rounds: %d; %d caught an enemy squad; %d caught two or more at once" % [rounds, rounds_on_squads, rounds_on_two_plus])
	print("enemy casualties from them: %d; %d of them (%.0f%%) from rounds that caught two or more squads; %d (%.0f%%) while the squad was moving" % [cas_total, cas_multi, 100.0 * cas_multi / maxf(cas_total, 1), cas_moving, 100.0 * cas_moving / maxf(cas_total, 1)])
	var minutes: Array = cas_by_minute.keys()
	minutes.sort()
	var line := "by five-minute block from the start:"
	for k in minutes:
		line += " %d-%d: %d;" % [k, k + 5, cas_by_minute[k]]
	print(line)
	quit()
