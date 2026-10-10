extends SceneTree
## Research harness (the folder is ignored by Godot: copy it under scripts/ to run): how much of a battle does the drone team have a drone on
## station, and how many airframes does it lose? Drone Recon mode, default doctrine, every map, seeds 1000-1000+TRIALS-1. Per battle: the
## share of battle time (while the drone team is in action) with no drone on station; the share of it with none although an airframe was
## available to fly (a battery ready, being swapped, or a bare airframe with a spare battery: the gaps planning could have avoided); the number
## of times it went from a drone to none; the sorties launched; the airframes lost (in all, and to a nearly empty battery); and the
## drone-minutes airborne (the cost of overlap). Time is battle time, not frames: the clock runs at different speeds.
##
## Results (2026-10-10, TRIALS 20 on each of 4 maps; "no drone" = share of battle time with none on station): before the low-charge hazard 4.6%;
## with it (part 1) 8.2% (relieved with no gap 91%, mean gap 0.4 min, 16.2 sorties, 1.5 airframes lost); with the replacement planner
## pulling a partly charged battery into a bare airframe early 9.1% (84%, 0.8 min, 17.7 sorties); the planner as committed, timing the
## launch only, 8.2% (90%, 0.6 min, 16.6 sorties, 1.5 lost). See docs/designs/tactical-commander-doctrine.md.
const TestBattleManagerScript := preload("res://scripts/tests/test_battle_manager.gd")
const TestCombatLogScript := preload("res://scripts/tests/test_combat_log.gd")

const TRIALS := 20
const MAX_TICKS := 30000
const TICK_DELTA := 0.5

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

func blank() -> Dictionary:
	return {"n": 0, "minutes": 0.0, "gap": 0.0, "avoidable": 0.0, "air": 0.0, "drops": 0, "sorties": 0, "lost": 0, "lost_low": 0, "handoffs": 0, "relieved": 0, "handoff_gap_min": 0.0}

func line(name: String, t: Dictionary) -> String:
	var minutes: float = maxf(t.minutes, 1.0)
	var handoffs: float = maxf(float(t.handoffs), 1.0)
	return "%-12s per battle: no drone on station %.1f%% of the time (avoidable %.1f%%), %.1f sorties, %.1f airframes lost (%.2f to a flat battery), %.0f drone-minutes; handoffs %.1f per battle, relieved with no gap %.0f%%, mean gap %.1f min" % [name, 100.0 * t.gap / minutes, 100.0 * t.avoidable / minutes, float(t.sorties) / t.n, float(t.lost) / t.n, float(t.lost_low) / t.n, t.air / t.n, float(t.handoffs) / t.n, 100.0 * float(t.relieved) / handoffs, t.handoff_gap_min / handoffs]

func run() -> void:
	var all := blank()
	for map_id in GameConfig.MAPS.keys():
		GameConfig.set_active_map(map_id)
		var tot := blank()
		for t in TRIALS:
			seed(1000 + t)
			var bm = TestBattleManagerScript.new()
			root.add_child(bm)
			var log = TestCombatLogScript.new()
			bm.start_battle(doctrine(), log)
			var ticks := 0
			var had := false
			var last_time := 0.0
			var prev_active = null
			var departure_time := -1.0
			while not bm.battle_over and ticks < MAX_TICKS:
				bm._process(TICK_DELTA)
				ticks += 1
				var dt: float = (bm.scenario_elapsed_time - last_time) / 60.0
				last_time = bm.scenario_elapsed_time
				var now_active = bm.active_drone
				if prev_active != null and is_instance_valid(prev_active) and now_active != prev_active:
					# the drone that was on station is no longer: relieved at once, or a gap begins
					tot.handoffs += 1
					if now_active != null:
						tot.relieved += 1
					else:
						departure_time = bm.scenario_elapsed_time
				elif departure_time >= 0.0 and now_active != null:
					tot.handoff_gap_min += (bm.scenario_elapsed_time - departure_time) / 60.0
					departure_time = -1.0
				prev_active = now_active
				if bm.drone_team != null and bm.drone_team.state == Unit.State.ACTIVE:
					tot.minutes += dt
					var airborne_now: int = (1 if bm.active_drone != null else 0) + (1 if bm.backup_drone != null else 0) + bm.returning_drones.size()
					tot.air += float(airborne_now) * dt
					if bm.active_drone == null:
						tot.gap += dt
						if not bm._drones_ready.is_empty() or not bm._drones_swapping.is_empty() or (bm._airframes_awaiting_battery > 0 and not bm._battery_pool.is_empty()):
							tot.avoidable += dt
						if had:
							tot.drops += 1
						had = false
					else:
						had = true
			tot.n += 1
			tot.sorties += bm.drone_sorties_launched
			tot.lost += bm._drones_destroyed
			if "_drones_lost_to_low_battery" in bm:
				tot.lost_low += bm._drones_lost_to_low_battery
			if is_instance_valid(log):
				log.free()
			bm.queue_free()
			await process_frame
		print(line(map_id, tot))
		for k in tot:
			all[k] += tot[k]
	print(line("ALL %d" % all.n, all))
	quit()
