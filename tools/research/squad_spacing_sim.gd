extends SceneTree
## Research harness (the folder is ignored by Godot: copy it under scripts/ to run). User, 2026-10-24: "I am highly suspicious about the 'hit on some other
## enemy squad' being unchanged. When you have 100 meter spacing instead of 75, this has to drop." Measures how far apart the enemy's squads really are:
## (1) at the start of the battle, each squad's distance to the nearest other squad of its side; (2) every 30 s of battle time, the same, for squads that are
## active, separately for squads on the move and standing; (3) when our mortar launches a round at a squad, the distance from that target squad to the
## nearest other enemy squad, and how many other enemy squads are within 50 / 75 / 100 / 150 m of it. Over every map and TRIALS seeds (Drone Recon, default
## doctrine). Prints quantiles (metres).
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

func nearest_m(u: Unit, others: Array) -> float:
	var best := INF
	for o in others:
		if o != u:
			best = minf(best, u.global_position.distance_to(o.global_position))
	return best / GameConfig.PIXELS_PER_METER

func quantiles(values: Array) -> String:
	if values.is_empty():
		return "(none)"
	values.sort()
	var n: int = values.size()
	return "n %d: 10%% %.0f, 25%% %.0f, median %.0f, 75%% %.0f m; under 75 m %.0f%%, under 100 m %.0f%%" % [n, values[int(n * 0.1)], values[int(n * 0.25)], values[int(n * 0.5)], values[int(n * 0.75)], 100.0 * values.filter(func(v): return v < 75.0).size() / n, 100.0 * values.filter(func(v): return v < 100.0).size() / n]

func run() -> void:
	var start_nn: Array = []
	var moving_nn: Array = []
	var still_nn: Array = []
	var target_nn: Array = []
	var within := {50.0: 0, 75.0: 0, 100.0: 0, 150.0: 0}
	var targets := 0
	for map_id in GameConfig.MAPS.keys():
		GameConfig.set_active_map(map_id)
		for t in TRIALS:
			seed(1000 + t)
			var bm = TestBattleManagerScript.new()
			root.add_child(bm)
			var log = TestCombatLogScript.new()
			bm.start_battle(doctrine(), log)
			var squads: Array = bm.enemy_units.filter(func(u): return u.kind == Unit.Kind.SQUAD)
			for u in squads:
				start_nn.append(nearest_m(u, squads))
			var next_sample := 30.0
			var seen := {}
			var ticks := 0
			while not bm.battle_over and ticks < MAX_TICKS:
				bm._process(TICK_DELTA)
				ticks += 1
				var live: Array = bm.enemy_units.filter(func(u): return u.kind == Unit.Kind.SQUAD and u.state == Unit.State.ACTIVE)
				if bm.scenario_elapsed_time >= next_sample:
					next_sample = bm.scenario_elapsed_time + SAMPLE_EVERY_S
					if live.size() >= 2:
						for u in live:
							(moving_nn if u.activity == Unit.Activity.MOVING else still_nn).append(nearest_m(u, live))
				for s in bm._pending_mortar_shots:
					if not is_instance_valid(s.mortar) or s.mortar.team != Unit.Team.PLAYER:
						continue
					var k: String = "%.3f|%.3f|%.2f" % [s.impact_point.x, s.impact_point.y, s.impact_time]
					if seen.has(k):
						continue
					seen[k] = true
					if is_instance_valid(s.target) and s.target.kind == Unit.Kind.SQUAD and s.target.team == Unit.Team.ENEMY and live.size() >= 2:
						target_nn.append(nearest_m(s.target, live))
						targets += 1
						for r in within:
							for o in live:
								if o != s.target and s.target.global_position.distance_to(o.global_position) / GameConfig.PIXELS_PER_METER <= r:
									within[r] += 1
			if is_instance_valid(log):
				log.free()
			bm.queue_free()
			await process_frame
	print("nearest other enemy squad, at the start of the battle: " + quantiles(start_nn))
	print("nearest other enemy squad, every 30 s, squads on the move: " + quantiles(moving_nn))
	print("nearest other enemy squad, every 30 s, squads standing: " + quantiles(still_nn))
	print("nearest other enemy squad to the target of a round of ours, at launch: " + quantiles(target_nn))
	for r in within:
		print("   other enemy squads within %.0f m of the target at launch: %.2f per round" % [r, float(within[r]) / maxf(targets, 1)])
	quit()
