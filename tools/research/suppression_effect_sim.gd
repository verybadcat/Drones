extends SceneTree
## Result of 2026-10-09 (12 battles per map and recon mode, 96 battles, default doctrine, no player orders):
##   before suppression (tag before-suppression): Ukrainian lost 14.2, Russian lost 18.3 per battle (ratio 1.29), score -56.9, 495 min;
##     verdicts: 59 stalemate, 27 defeat, 9 successful defense, 1 pyrrhic defense.
##   with suppression: Ukrainian lost 14.0, Russian lost 19.2 (ratio 1.37), score -50.7, 440 min, squads pinned 5.4 times a battle (4.7 to 6.6
##     by map and mode); verdicts: 48 stalemate, 30 defeat, 16 successful defense, 1 favorable-exchange withdrawal, 1 pyrrhic defense.
## The casualty and score differences are within the noise of 96 battles (about 0.6 casualties of standard error); the shift away from
## stalemates is the clearest change and may also be noise.
## Research harness (the folder is ignored by Godot: copy it under scripts/ to run): how do whole battles come out? Casualties on each side,
## the battle score, the verdicts, how long they last, and (once suppression exists) how often squads are pinned. Run it on the commit
## tagged before-suppression and on the commit that adds suppression, and compare. Default doctrine, every map, both recon modes, seeds
## 1000-1000+TRIALS-1 (the same seeds in both, though the two games diverge as soon as anything differs).
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
	var all := {"n": 0, "ua_lost": 0, "ru_lost": 0, "score": 0.0, "minutes": 0.0, "pins": 0, "held": 0, "stalemate": 0, "ratio_sum": 0.0}
	var verdicts := {}
	for map_id in GameConfig.MAPS.keys():
		GameConfig.set_active_map(map_id)
		for mode in [GameConfig.ReconMode.SPOTTER, GameConfig.ReconMode.DRONE_TEAM]:
			var tot := {"n": 0, "ua_lost": 0, "ru_lost": 0, "score": 0.0, "minutes": 0.0, "pins": 0}
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
				var ua: Dictionary = bm._compute_side_stats(bm.player_units)
				var ru: Dictionary = bm._compute_side_stats(bm.enemy_units)
				tot.n += 1
				tot.ua_lost += int(ua.pips_lost)
				tot.ru_lost += int(ru.pips_lost)
				tot.score += float(bm.battle_result.get("score", 0.0))
				tot.minutes += bm.scenario_elapsed_time / 60.0
				var v: String = str(bm.battle_result.get("verdict", "none"))
				verdicts[v] = verdicts.get(v, 0) + 1
				for line in log.captured:
					if "is pinned down by fire" in line:
						tot.pins += 1
				if is_instance_valid(log):
					log.free()
				bm.queue_free()
				await process_frame
			print("%-12s %-10s per battle: Ukrainian lost %.1f, Russian lost %.1f, score %+.1f, %.0f min, pinned %.1f times" % [map_id, "drone" if mode == GameConfig.ReconMode.DRONE_TEAM else "spotter", float(tot.ua_lost) / tot.n, float(tot.ru_lost) / tot.n, tot.score / tot.n, tot.minutes / tot.n, float(tot.pins) / tot.n])
			for k in tot:
				all[k] += tot[k]
	var n: float = float(all.n)
	print("ALL %d battles: Ukrainian lost %.1f, Russian lost %.1f (ratio %.2f), score %+.1f, %.0f min, pinned %.1f times per battle" % [all.n, all.ua_lost / n, all.ru_lost / n, float(all.ru_lost) / maxf(float(all.ua_lost), 1.0), all.score / n, all.minutes / n, all.pins / n])
	print("verdicts: %s" % str(verdicts))
	quit()
