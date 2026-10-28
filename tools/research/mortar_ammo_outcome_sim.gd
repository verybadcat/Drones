extends SceneTree
## Research harness (the folder is ignored by Godot: copy it under scripts/ to run). User, 2026-10-23: "In the current battle, the mortar with its 20 rounds
## killed both enemy mortars, then inflicted enough casualties that the enemy retreated. Was I just lucky?" For every map and TRIALS seeds (Drone Recon,
## default doctrine) it runs the battle until our mortar has fired its whole load (MORTAR_STARTING_AMMO) and those rounds have landed (a minute after the
## last), then reports how that went: how many enemy mortars there were and how many were destroyed outright / out of action by then, how many enemy
## squad people were lost, and whether the enemy commander had ordered a general retreat. The share of battles that reach the same outcome as the user's
## (every enemy mortar destroyed, and the enemy retreat ordered) says how lucky that was. A battle in which our mortar is destroyed first is counted apart.
const TestBattleManagerScript := preload("res://scripts/tests/test_battle_manager.gd")
const TestCombatLogScript := preload("res://scripts/tests/test_combat_log.gd")

const TRIALS := 40
const TICK_DELTA := 0.5
const MAX_TICKS := 30000
const AFTER_LAST_ROUND_S := 60.0

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

func pct(n: int, d: int) -> String:
	return "%.0f%%" % (100.0 * n / maxf(d, 1))

func run() -> void:
	var total := 0
	var finished := 0 # our mortar fired its whole load
	var mortar_lost := 0
	var ended_first := 0 # the battle ended before the load was fired
	var by_count := {} # number of enemy mortars -> battles
	var out_by_count := {} # number of enemy mortars -> [battles with every enemy mortar out of action, with every one destroyed outright, with at least two out, with the enemy squads' losses over 10]
	var all_destroyed := 0 # every enemy mortar DESTROYED
	var all_out := 0 # every enemy mortar destroyed or no longer active
	var at_least_two_destroyed := 0
	var with_two_or_more := 0
	var retreat := 0
	var both := 0 # all enemy mortars destroyed and the retreat ordered
	var both_two := 0 # the same, in battles with two or more enemy mortars
	var squad_loss_total := 0.0
	var lost_hist := {} # enemy squad people lost, in tens
	for map_id in GameConfig.MAPS.keys():
		GameConfig.set_active_map(map_id)
		var m_battles := 0
		var m_both := 0
		var m_retreat := 0
		var m_all := 0
		for t in TRIALS:
			seed(1000 + t)
			var bm = TestBattleManagerScript.new()
			root.add_child(bm)
			var log = TestCombatLogScript.new()
			bm.start_battle(doctrine(), log)
			total += 1
			var ours: Unit = null
			for u in bm.player_units:
				if u.kind == Unit.Kind.MORTAR:
					ours = u
			var enemy_mortars: Array[Unit] = []
			var squads_total := 0
			for e in bm.enemy_units:
				if e.kind == Unit.Kind.MORTAR:
					enemy_mortars.append(e)
				elif e.kind == Unit.Kind.SQUAD:
					squads_total += e.max_pips
			var fired_out_at := -1.0
			var ticks := 0
			var done := false
			while not bm.battle_over and ticks < MAX_TICKS and not done:
				bm._process(TICK_DELTA)
				ticks += 1
				if ours == null or not is_instance_valid(ours) or ours.state == Unit.State.DESTROYED:
					break
				if fired_out_at < 0.0 and ours.mortar_rounds_remaining <= 0:
					fired_out_at = bm.scenario_elapsed_time
				if fired_out_at >= 0.0 and bm.scenario_elapsed_time >= fired_out_at + AFTER_LAST_ROUND_S:
					done = true
			if not done:
				if ours == null or not is_instance_valid(ours) or ours.state == Unit.State.DESTROYED:
					mortar_lost += 1
				else:
					ended_first += 1
			else:
				finished += 1
				m_battles += 1
				var n: int = enemy_mortars.size()
				by_count[n] = int(by_count.get(n, 0)) + 1
				var destroyed := 0
				var out := 0
				for c in enemy_mortars:
					if is_instance_valid(c):
						if c.state == Unit.State.DESTROYED:
							destroyed += 1
						if c.state != Unit.State.ACTIVE:
							out += 1
				var squads_now := 0
				for e in bm.enemy_units:
					if e.kind == Unit.Kind.SQUAD:
						squads_now += e.pips
				var lost: int = squads_total - squads_now
				squad_loss_total += lost
				lost_hist[lost / 10] = int(lost_hist.get(lost / 10, 0)) + 1
				var row: Array = out_by_count.get(n, [0, 0, 0, 0])
				if n > 0 and out == n:
					row[0] += 1
				if n > 0 and destroyed == n:
					row[1] += 1
				if out >= 2:
					row[2] += 1
				if lost > 10:
					row[3] += 1
				out_by_count[n] = row
				var all_d: bool = n > 0 and destroyed == n
				if all_d:
					all_destroyed += 1
					m_all += 1
				if n > 0 and out == n:
					all_out += 1
				if n >= 2:
					with_two_or_more += 1
					if destroyed >= 2:
						at_least_two_destroyed += 1
				if bm.enemy_general_retreat_ordered:
					retreat += 1
					m_retreat += 1
				if all_d and bm.enemy_general_retreat_ordered:
					both += 1
					m_both += 1
					if n >= 2:
						both_two += 1
			if is_instance_valid(log):
				log.free()
			bm.queue_free()
			await process_frame
		print("%-12s our mortar fired its load in %d of %d battles; every enemy mortar destroyed in %d, the enemy retreat ordered in %d, both in %d" % [map_id, m_battles, TRIALS, m_all, m_retreat, m_both])
	print("battles %d: our mortar fired its whole load in %d (destroyed first %d, battle ended first %d)" % [total, finished, mortar_lost, ended_first])
	print("enemy mortars per battle (of those): %s" % str(by_count))
	print("by then, every enemy mortar DESTROYED: %s (%d); every one destroyed or out of action: %s; two or more destroyed (battles with 2+ enemy mortars: %d): %s" % [pct(all_destroyed, finished), all_destroyed, pct(all_out, finished), with_two_or_more, pct(at_least_two_destroyed, with_two_or_more)])
	print("enemy general retreat ordered by then: %s (%d)" % [pct(retreat, finished), retreat])
	print("BOTH (every enemy mortar destroyed and the retreat ordered): %s (%d); in battles with 2+ enemy mortars: %d" % [pct(both, finished), both, both_two])
	var keys: Array = out_by_count.keys()
	keys.sort()
	for k in keys:
		var r: Array = out_by_count[k]
		var nb: int = by_count[k]
		print("   with %d enemy mortars (%d battles): every one out of action %d (%.0f%%), every one destroyed outright %d (%.0f%%), at least two out of action %d (%.0f%%), enemy squads lost more than 10 people %d (%.0f%%)" % [k, nb, r[0], 100.0 * r[0] / nb, r[1], 100.0 * r[1] / nb, r[2], 100.0 * r[2] / nb, r[3], 100.0 * r[3] / nb])
	print("enemy squad people lost by then: mean %.1f; by tens: %s" % [squad_loss_total / maxf(finished, 1), str(lost_hist)])
	quit()
