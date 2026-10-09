extends SceneTree
## Result of 2026-10-09 (12 battles per map and recon mode, 96 battles, default doctrine, no player orders), before and after counter-battery
## rounds were given the same scatter as every other mortar round:
##   before (aimed exactly at the located position): 5.3 replies called per battle, 0.16 found the mortar, 5.0 landed on its old position;
##     the Ukrainian mortar was destroyed in 17 battles (18%), crew lost 1.07 of 4.0 per battle.
##   after (scatter from the aim point, about 3% of the range unobserved): 5.1 replies, 0.15 found the mortar, 4.9 on the old position;
##     destroyed in 12 battles (13%), crew lost 0.98 of 4.0.
## The differences are within the noise of 96 battles. The scatter is real in battle: 97 rounds in a separate probe landed a median 118 m
## from their aim at a median range of 3,962 m (3% of the range is 119 m). The hit count does not fall because the crews have usually moved
## on by the time a reply lands: a round scattered around the old position is as likely to fall near the new one as an exactly aimed one was.
## Research harness (the folder is ignored by Godot: copy it under scripts/ to run): how effective is the enemy's counter-battery fire against the
## Ukrainian mortar? Per battle: counter-battery replies called in on it, replies that found it, replies that landed on its old position, and
## how the mortar ended (destroyed, withdrawn, or still in action) and how much of its crew was lost. Default doctrine, every map, both recon
## modes, seeds 1000-1000+TRIALS-1.
const TestBattleManagerScript := preload("res://scripts/tests/test_battle_manager.gd")
const TestCombatLogScript := preload("res://scripts/tests/test_combat_log.gd")

const TRIALS := 12
const MAX_TICKS := 30000
const TICK_DELTA := 0.5

func _initialize() -> void:
	call_deferred("run")

func doctrine(mode: GameConfig.ReconMode) -> Dictionary:
	var squads: Array[Dictionary] = []
	for pos in GameConfig.CURRENT_MAP.player.default_squad_positions:
		squads.append({"position": pos, "retreat_threshold": 0.5})
	return {
		"squads": squads,
		"mortar": {"position": GameConfig.CURRENT_MAP.player.mortar_default_position, "shoot_and_scoot": true},
		"spotter": {"position": GameConfig.CURRENT_MAP.player.spotter_default_position},
		"recon_mode": mode,
	}

func run() -> void:
	var all := {"n": 0, "called": 0, "found": 0, "missed": 0, "destroyed": 0, "crew_lost": 0, "crew": 0}
	for map_id in GameConfig.MAPS.keys():
		GameConfig.set_active_map(map_id)
		for mode in [GameConfig.ReconMode.SPOTTER, GameConfig.ReconMode.DRONE_TEAM]:
			var tot := {"n": 0, "called": 0, "found": 0, "missed": 0, "destroyed": 0, "crew_lost": 0, "crew": 0}
			for t in TRIALS:
				seed(1000 + t)
				var bm = TestBattleManagerScript.new()
				root.add_child(bm)
				var log = TestCombatLogScript.new()
				bm.start_battle(doctrine(mode), log)
				var ticks := 0
				while not bm.battle_over and ticks < MAX_TICKS:
					bm._process(TICK_DELTA)
					ticks += 1
				tot.n += 1
				for line in log.captured:
					if "Counter-battery fire inbound on Ukrainian Mortar" in line:
						tot.called += 1
					elif "Counter-battery fire found Ukrainian Mortar" in line:
						tot.found += 1
					elif "Counter-battery fire lands near Ukrainian Mortar" in line:
						tot.missed += 1
				for u in bm.player_units:
					if u.kind == Unit.Kind.MORTAR:
						tot.crew += u.max_pips
						tot.crew_lost += u.max_pips - u.pips
						if u.state == Unit.State.DESTROYED:
							tot.destroyed += 1
				if is_instance_valid(log):
					log.free()
				bm.queue_free()
				await process_frame
			print("%-12s %-10s per battle: replies called %.1f, found the mortar %.2f, landed on its old position %.1f; mortar destroyed in %d of %d battles, crew lost %.1f of %.1f" % [map_id, "drone" if mode == GameConfig.ReconMode.DRONE_TEAM else "spotter", float(tot.called) / tot.n, float(tot.found) / tot.n, float(tot.missed) / tot.n, tot.destroyed, tot.n, float(tot.crew_lost) / tot.n, float(tot.crew) / tot.n])
			for k in tot:
				all[k] += tot[k]
	var n: float = float(all.n)
	print("ALL %d battles: replies called %.1f per battle, found the mortar %.2f, landed on the old position %.1f; Ukrainian mortar destroyed in %d battles (%.0f%%), crew lost %.2f of %.1f per battle" % [all.n, all.called / n, all.found / n, all.missed / n, all.destroyed, 100.0 * all.destroyed / n, all.crew_lost / n, all.crew / n])
	quit()
