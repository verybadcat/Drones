extends SceneTree
## Research harness (the folder is ignored by Godot: copy it under scripts/ to run). User, 2026-10-21: "Success of our mortar against enemy mortars seems
## to be about one enemy mortar knocked out per 2-3 salvoes fired. That is suspiciously high." Over every map and TRIALS seeds (Drone Recon, default
## doctrine) it counts our salvos at enemy mortar crews (the rounds of a burst land in one tick: one impact time at a mortar target is a salvo) and every
## time an enemy crew took casualties or went out of action (destroyed, or left the gun / retreating), and for each such event attributes it to a round of
## ours that landed that tick (the nearest, with how many it cost the crew) or to something else (squads' fire, a general retreat). Reports: salvos per
## crew put out of action; how often a hit puts a crew out; by the distance of the nearest round, whether it was the crew's first casualty, and whether
## the crew was on the move; and how many crews were put out by something other than our mortar.
const TestBattleManagerScript := preload("res://scripts/tests/test_battle_manager.gd")
const TestCombatLogScript := preload("res://scripts/tests/test_combat_log.gd")

const TRIALS := 20
const TICK_DELTA := 0.5
const MAX_TICKS := 30000
const BANDS := [10.0, 25.0, 50.0, 100.0]

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

func band_of(d: float) -> int:
	for i in BANDS.size():
		if d <= BANDS[i]:
			return i
	return BANDS.size()

func band_name(i: int) -> String:
	if i == 0:
		return "<=10 m"
	if i < BANDS.size():
		return "%d-%d m" % [int(BANDS[i - 1]), int(BANDS[i])]
	return ">100 m"

func pct(n: int, d: int) -> String:
	return "%.0f%%" % (100.0 * n / maxf(d, 1))

func run() -> void:
	var battles := 0
	var salvos := 0
	var enemy_crews := 0
	var hits := 0                     # crew casualty events from a round of ours
	var out_by_us := 0                # went out of action in the tick of a round of ours
	var out_other := 0                # went out of action with no round of ours landing that tick
	var destroyed_by_us := 0
	var by_band := []                 # [hits, outs] per distance band, hits matched to a round
	for i in BANDS.size() + 1:
		by_band.append([0, 0])
	var first_hit := [0, 0]           # [hits that were the crew's first casualty, of which went out]
	var later_hit := [0, 0]
	var moving_hit := [0, 0]
	var still_hit := [0, 0]
	var out_first_hit := 0
	var out_dist_hist := [0, 0, 0, 0, 0]
	var out_serving_after := {}       # serving count after a knockout by us -> events
	var by_terrain := {}              # terrain the crew stood in -> [hurt, put out]
	for map_id in GameConfig.MAPS.keys():
		GameConfig.set_active_map(map_id)
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
			enemy_crews += foes.size()
			var prev := {}
			for c in foes:
				prev[c] = {"state": c.state, "cas": c.crew_casualties}
			var salvo_keys := {}
			var consumed := 0
			var ticks := 0
			while not bm.battle_over and ticks < MAX_TICKS:
				bm._process(TICK_DELTA)
				ticks += 1
				for s in bm._pending_mortar_shots:
					if is_instance_valid(s.mortar) and s.mortar.team == Unit.Team.PLAYER and is_instance_valid(s.target) and s.target.kind == Unit.Kind.MORTAR:
						var key := "%.2f" % s.impact_time
						if not salvo_keys.has(key):
							salvo_keys[key] = true
							salvos += 1
				var fresh: Array = []
				while consumed < bm.shell_landing_log.size():
					var entry: Dictionary = bm.shell_landing_log[consumed]
					consumed += 1
					if entry.team == Unit.Team.PLAYER:
						fresh.append(entry)
				for c in foes:
					if not is_instance_valid(c):
						continue
					var before: Dictionary = prev[c]
					var delta: int = c.crew_casualties - int(before.cas)
					var went_out: bool = before.state == Unit.State.ACTIVE and c.state != Unit.State.ACTIVE
					if delta > 0 or went_out:
						var best := INF
						var moving := false
						for entry in fresh:
							for v in entry.victims:
								if v.kind == Unit.Kind.MORTAR and v.team == Unit.Team.ENEMY and v.casualties > 0 and v.distance_m < best:
									best = v.distance_m
									moving = v.moving
						var ours: bool = not is_inf(best)
						if delta > 0 and ours:
							hits += 1
							var terr: int = int(GameConfig.get_terrain_type_at(c.global_position))
							var tt: Array = by_terrain.get(terr, [0, 0])
							tt[0] += 1
							if went_out:
								tt[1] += 1
							by_terrain[terr] = tt
							var b: int = band_of(best)
							by_band[b][0] += 1
							var bucket: Array = first_hit if int(before.cas) == 0 else later_hit
							bucket[0] += 1
							var mv: Array = moving_hit if moving else still_hit
							mv[0] += 1
							if went_out:
								by_band[b][1] += 1
								bucket[1] += 1
								mv[1] += 1
						if went_out:
							if ours:
								out_by_us += 1
								if c.state == Unit.State.DESTROYED:
									destroyed_by_us += 1
								var serving: int = c.crew_size - c.crew_casualties
								out_serving_after[serving] = int(out_serving_after.get(serving, 0)) + 1
								out_dist_hist[band_of(best)] += 1
								if int(before.cas) == 0:
									out_first_hit += 1
							else:
								out_other += 1
					prev[c] = {"state": c.state, "cas": c.crew_casualties}
			battles += 1
			if is_instance_valid(log):
				log.free()
			bm.queue_free()
			await process_frame
	print("battles: %d; enemy mortar crews: %d (%.1f a battle); our salvos at enemy mortars: %d (%.1f a battle)" % [battles, enemy_crews, float(enemy_crews) / battles, salvos, float(salvos) / battles])
	print("enemy crews put out of action (destroyed, or left the gun) in the tick of a round of ours: %d (%d destroyed outright); by something else: %d" % [out_by_us, destroyed_by_us, out_other])
	print("salvos per crew put out of action by our mortar: %.1f; per crew put out by anything: %.1f" % [float(salvos) / maxf(out_by_us, 1), float(salvos) / maxf(out_by_us + out_other, 1)])
	print("rounds of ours that cost a crew casualties: %d (%.2f per salvo); of them the crew's first casualty: %d" % [hits, float(hits) / maxf(salvos, 1), first_hit[0]])
	for i in by_band.size():
		print("  nearest round %s: %d crews hurt, %s of them put out of action" % [band_name(i), by_band[i][0], pct(by_band[i][1], by_band[i][0])])
	print("  the crew's first casualty: %d hurt, %s put out; a later one: %d, %s" % [first_hit[0], pct(first_hit[1], first_hit[0]), later_hit[0], pct(later_hit[1], later_hit[0])])
	print("  crew on the move when hit: %d, %s put out; standing still: %d, %s" % [moving_hit[0], pct(moving_hit[1], moving_hit[0]), still_hit[0], pct(still_hit[1], still_hit[0])])
	for terr in by_terrain:
		var tname: String = ["open", "trees", "building"][terr]
		print("  crew standing in %s when hit by a round of ours: %d hurt, %s put out" % [tname, by_terrain[terr][0], pct(by_terrain[terr][1], by_terrain[terr][0])])
	var line := "crews put out by us, by how many were left serving after:"
	var keys: Array = out_serving_after.keys()
	keys.sort()
	for k in keys:
		line += " %d: %d;" % [k, out_serving_after[k]]
	print(line)
	var line2 := "crews put out by us, by the distance of the nearest round:"
	for i in out_dist_hist.size():
		line2 += " %s: %d;" % [band_name(i), out_dist_hist[i]]
	print(line2 + " of them on the crew's first casualty: %d" % out_first_hit)
	quit()
