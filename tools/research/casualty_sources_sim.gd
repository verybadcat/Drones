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

## Wound types (2026-10-23, "walking, serious, fatal"): everyone lost by the end of each battle, by side and by squad or everyone else (crews, spotters),
## counted from the units' own killed / heavily wounded / walking wounded counts; "left" are wounded a retreating squad left on the field (captured; already
## out of the serious count). Totals over all battles and maps.
var wound_totals := {}

func add_wounds(units: Array) -> void:
	for u in units:
		if u.kind == Unit.Kind.DRONE or u.kind == Unit.Kind.RESUPPLY_RUN:
			continue
		var side := "Ukr" if u.team == Unit.Team.PLAYER else "Rus"
		var group := "squads" if u.kind == Unit.Kind.SQUAD else "crews+spotters"
		var key := side + " " + group
		var row: Array = wound_totals.get(key, [0, 0, 0, 0])
		row[0] += int(u.killed_count)
		row[1] += int(u.heavily_wounded_count)
		row[2] += int(u.walking_wounded_count)
		var left = u.get("wounded_left_behind_count")
		row[3] += int(left) if left != null else 0
		wound_totals[key] = row

func run() -> void:
	var grand := {"squad_ua": 0, "squad_ru": 0, "mortar_ua": 0, "mortar_ru": 0}
	var battles := 0
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
				add_wounds(bm.player_units)
				add_wounds(bm.enemy_units)
				battles += 1
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
	var all_k := 0
	var all_h := 0
	var all_w := 0
	for key in wound_totals:
		var r: Array = wound_totals[key]
		all_k += r[0]
		all_h += r[1]
		all_w += r[2]
		var n: float = maxf(float(r[0] + r[1] + r[2]), 1.0)
		print("WOUNDS %-16s killed %d (%.0f%%), serious %d (%.0f%%), walking %d (%.0f%%); left on the field %d; per battle %.1f / %.1f / %.1f" % [key, r[0], 100.0 * r[0] / n, r[1], 100.0 * r[1] / n, r[2], 100.0 * r[2] / n, r[3], float(r[0]) / battles, float(r[1]) / battles, float(r[2]) / battles])
	var nn: float = maxf(float(all_k + all_h + all_w), 1.0)
	print("WOUNDS ALL: killed %d (%.0f%%), serious %d (%.0f%%), walking %d (%.0f%%) over %d battles; per battle %.1f / %.1f / %.1f" % [all_k, 100.0 * all_k / nn, all_h, 100.0 * all_h / nn, all_w, 100.0 * all_w / nn, battles, float(all_k) / battles, float(all_h) / battles, float(all_w) / battles])
	quit()
