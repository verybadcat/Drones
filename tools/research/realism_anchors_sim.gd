extends SceneTree
## Research harness (the folder is ignored by Godot: copy it under scripts/ to run; about 15 minutes): the battle-level real-world anchors that
## are too slow for the test suite. The unit-level ones are scripts/tests/test_realism_anchors.gd; the ledger of every anchor, its source and its
## status is docs/designs/realism-anchors.md. Drone Recon, default doctrine, every map, seeds 1000-1000+TRIALS-1.
##
## 1. The share of all casualties caused by mortars (indirect fire), against small arms. Real wars (Bellamy 1986, via Wikipedia's Artillery
##    article): artillery caused 45-58% of casualties in WWI, 51-75% in WWII, over 60% in Korea. Band to stay in: 45-75%.
##    Last run (2026-10-11, 48 battles): 71%.
## 2. How often our mortar's salvos land within 25 m (the casualty radius) of an enemy mortar, by how many salvos had already been fired at
##    that target. A crew that does not sit still and does not want to be hit: the first salvo (unadjusted, CEP about 135 m at 4 km) should
##    almost never (about 7% for an unmoving target); later salvos, adjusted, would be about 65% for an UNMOVING target at a CEP of 35 m and are
##    expected to be well below that for crews that displace. Last run (2026-10-12, 80 battles, 437 salvos): #1 5%, #2 13%, #3 14%, #4+ 15%.
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

func run() -> void:
	var by_index := {}
	for k in [1, 2, 3, 4]:
		by_index[k] = {"salvos": 0, "hit10": 0, "hit25": 0, "hit40": 0, "rounds": 0, "r25": 0}
	var mort_cas := 0.0
	var small_cas := 0.0
	var lost := {"player": 0.0, "enemy": 0.0}
	var duration := 0.0
	var scraped := 0
	var positioned := 0
	var dry := {"player": 0, "enemy": 0}
	var rounds_left := 0.0
	var squads_seen := 0
	var assaults := {"player": 0, "enemy": 0}
	var battles := 0
	for map_id in GameConfig.MAPS.keys():
		GameConfig.set_active_map(map_id)
		for t in TRIALS:
			seed(1000 + t)
			var bm = TestBattleManagerScript.new()
			root.add_child(bm)
			var log = TestCombatLogScript.new()
			bm.start_battle(doctrine(), log)
			var ticks := 0
			var tracked: Array = []
			var seen := {}
			var salvo_count := {}
			var salvo_keys := {}
			var salvo_result := {}
			while not bm.battle_over and ticks < MAX_TICKS:
				bm._process(TICK_DELTA)
				ticks += 1
				for s in bm._pending_mortar_shots:
					var id: int = s.hash()
					if seen.has(id):
						continue
					seen[id] = true
					if is_instance_valid(s.mortar) and s.mortar.team == Unit.Team.PLAYER and is_instance_valid(s.target) and s.target.kind == Unit.Kind.MORTAR:
						var tid: int = s.target.get_instance_id()
						var key: String = "%d:%d" % [tid, int(s.impact_time / 10.0)]
						if not salvo_keys.has(key):
							salvo_count[tid] = salvo_count.get(tid, 0) + 1
							salvo_keys[key] = mini(salvo_count[tid], 4)
							salvo_result[key] = {"index": salvo_keys[key], "min_d": INF, "rounds": 0, "r25": 0}
						tracked.append({"shot": s, "key": key})
				var still: Array = []
				for tr in tracked:
					var s: Dictionary = tr.shot
					if bm.scenario_elapsed_time >= s.impact_time:
						if is_instance_valid(s.target):
							var d: float = s.impact_point.distance_to(s.target.global_position) / GameConfig.PIXELS_PER_METER
							var res: Dictionary = salvo_result[tr.key]
							res.min_d = minf(res.min_d, d)
							res.rounds += 1
							if d <= 25.0:
								res.r25 += 1
					else:
						still.append(tr)
				tracked = still
			for key in salvo_result:
				var res: Dictionary = salvo_result[key]
				if res.rounds == 0:
					continue
				var b: Dictionary = by_index[res.index]
				b.salvos += 1
				b.rounds += res.rounds
				b.r25 += res.r25
				if res.min_d <= 10.0:
					b.hit10 += 1
				if res.min_d <= 25.0:
					b.hit25 += 1
				if res.min_d <= 40.0:
					b.hit40 += 1
			var snap: Dictionary = bm.general_unit_debug_snapshot()
			for k in snap.keys():
				var v: Dictionary = snap[k]
				var cas: float = v.get("casualties_inflicted", 0)
				if v.get("kind", "") == "MORTAR":
					mort_cas += cas
				elif v.get("kind", "") == "SQUAD":
					small_cas += cas
				if v.get("kind", "") == "SQUAD" or v.get("kind", "") == "MORTAR":
					lost[v.get("team", "player")] += float(v.get("max_pips", 0) - v.get("pips", 0))
				if v.get("entrenchment", "") == "SCRAPE":
					scraped += 1
				elif v.get("entrenchment", "") == "FIGHTING_POSITION":
					positioned += 1
				if v.has("rounds"):
					squads_seen += 1
					rounds_left += float(v.rounds)
					if int(v.rounds) <= 0:
						dry[v.get("team", "player")] += 1
			assaults.player += int(bm._assaults_started.get(Unit.Team.PLAYER, 0))
			assaults.enemy += int(bm._assaults_started.get(Unit.Team.ENEMY, 0))
			duration += bm.scenario_elapsed_time
			battles += 1
			if is_instance_valid(log):
				log.free()
			bm.queue_free()
			await process_frame
	var total: float = mort_cas + small_cas
	print("1. over %d battles: casualties per battle %.1f, of which by mortars %.0f%% (band 45-75%%)" % [battles, total / battles, 100.0 * mort_cas / maxf(total, 1.0)])
	print("   people lost per battle (squads and mortar crews): ours %.1f, theirs %.1f" % [lost.player / battles, lost.enemy / battles])
	print("   battle length %.0f minutes on average; units with a shell scrape at the end %.2f per battle, with a fighting position %.2f" % [duration / battles / 60.0, float(scraped) / battles, float(positioned) / battles])
	print("   squads out of ammunition at the end, per battle: ours %.2f, theirs %.2f; rounds left per squad on average %.0f of %d" % [float(dry.player) / battles, float(dry.enemy) / battles, rounds_left / maxf(squads_seen, 1), Unit.SQUAD_SIZE * GameConfig.SQUAD_ROUNDS_PER_PERSON])
	print("   assaults taken up per battle: ours %.2f, theirs %.2f" % [float(assaults.player) / battles, float(assaults.enemy) / battles])
	print("2. our salvos at enemy mortars, by how many salvos had already been fired at that target:")
	for k in [1, 2, 3, 4]:
		var b: Dictionary = by_index[k]
		print("  salvo #%s%s: %d salvos (%.1f rounds each): at least one round within 10 m %.0f%%, within 25 m %.0f%%, within 40 m %.0f%%" % [str(k), "+" if k == 4 else "", b.salvos, float(b.rounds) / maxf(b.salvos, 1), 100.0 * b.hit10 / maxf(b.salvos, 1), 100.0 * b.hit25 / maxf(b.salvos, 1), 100.0 * b.hit40 / maxf(b.salvos, 1)])
	quit()
