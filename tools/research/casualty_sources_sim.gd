extends SceneTree
## Result of 2026-10-09 (12 battles per map and recon mode, 96 battles, seeds 1000-1011, default doctrine, 3,070 casualties in all): small arms
## caused 71% of casualties and mortar rounds 29% (Ukrainian squads 1,405, Russian squads 763, Ukrainian mortar 291, Russian mortars 611).
## By map and mode the small-arms share ran from 64% (Pervomaiske, drone) to 78% (Svystunivka, spotter). For comparison, artillery and
## mortars caused (Bailey 2004, quoting Bellamy 1986): WWI 45% of Russian and 58% of British casualties on the Western Front; WWII 75% of
## British casualties in North Africa, 51% of Soviet (61% in 1945) and 70% of German on the Eastern Front; Korea 60% of US casualties.
## Research harness (the folder is ignored by Godot: copy it under scripts/ to run): in our own battles, what share of the casualties are
## caused by mortar rounds and what share by small arms? Compares with the historical shares of artillery and mortars (about half to
## three-quarters of battlefield casualties in the industrial wars). Default doctrine, every map, both recon modes.
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
	var grand := {"squad_ua": 0, "squad_ru": 0, "mortar_ua": 0, "mortar_ru": 0}
	for map_id in GameConfig.MAPS.keys():
		GameConfig.set_active_map(map_id)
		for mode in [GameConfig.ReconMode.SPOTTER, GameConfig.ReconMode.DRONE_TEAM]:
			var tot := {"squad_ua": 0, "squad_ru": 0, "mortar_ua": 0, "mortar_ru": 0}
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
				for row in bm.unit_combat_stats.rows.values():
					var key := ""
					if row.kind == Unit.Kind.SQUAD:
						key = "squad_ua" if row.team == Unit.Team.PLAYER else "squad_ru"
					elif row.kind == Unit.Kind.MORTAR:
						key = "mortar_ua" if row.team == Unit.Team.PLAYER else "mortar_ru"
					if key != "":
						tot[key] += int(row.casualties)
				if bm.combat_log != null and is_instance_valid(bm.combat_log):
					bm.combat_log.free()
				bm.queue_free()
				await process_frame
			var all: float = float(tot.squad_ua + tot.squad_ru + tot.mortar_ua + tot.mortar_ru)
			print("%-12s %-10s casualties %d over %d battles: small arms %d (%.0f%%; Ukr %d, Rus %d), mortars %d (%.0f%%; Ukr %d, Rus %d)" % [map_id, "drone" if mode == GameConfig.ReconMode.DRONE_TEAM else "spotter", all, TRIALS, tot.squad_ua + tot.squad_ru, 100.0 * float(tot.squad_ua + tot.squad_ru) / maxf(all, 1.0), tot.squad_ua, tot.squad_ru, tot.mortar_ua + tot.mortar_ru, 100.0 * float(tot.mortar_ua + tot.mortar_ru) / maxf(all, 1.0), tot.mortar_ua, tot.mortar_ru])
			for k in tot:
				grand[k] += tot[k]
	var g: float = float(grand.squad_ua + grand.squad_ru + grand.mortar_ua + grand.mortar_ru)
	print("ALL: casualties %d: small arms %.0f%%, mortars %.0f%% (Ukrainian mortar %d, Russian mortars %d; Ukrainian squads %d, Russian squads %d)" % [g, 100.0 * float(grand.squad_ua + grand.squad_ru) / maxf(g, 1.0), 100.0 * float(grand.mortar_ua + grand.mortar_ru) / maxf(g, 1.0), grand.mortar_ua, grand.mortar_ru, grand.squad_ua, grand.squad_ru])
	quit()
