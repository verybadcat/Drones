extends SceneTree
## Research harness (the folder is ignored by Godot: copy it under scripts/ to run). User, 2026-10-24: "DESTINATIONS may need to be close. Don't change that
## yet. But locations during advance likely don't need to be close. I want stats on the impact of advance spacing on casualties." For every map and TRIALS
## seeds (Drone Recon, default doctrine) it reads every mortar round that landed (BattleManager.shell_landing_log) and reports, per battle, the people the
## enemy's squads lost to OUR mortar's rounds and to the enemy's own, split by whether the squad was moving (advancing) or standing when the round landed,
## the number of rounds that caught a moving squad, and the people lost per such round. Run it with the advance spacing at different values
## (GameConfig.ENEMY_ADVANCE_DESIRED_SPACING_M) to see what the spacing does to the casualties of advancing squads.
const TestBattleManagerScript := preload("res://scripts/tests/test_battle_manager.gd")
const TestCombatLogScript := preload("res://scripts/tests/test_combat_log.gd")

const TRIALS := 80
const TICK_DELTA := 0.5
const MAX_TICKS := 30000

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
	# [moving people lost, standing people lost, rounds that caught a moving squad, moving squad-hits, rounds that caught a standing squad, standing squad-hits]
	var ours := [0, 0, 0, 0, 0, 0] # Ukrainian rounds on Russian squads
	var theirs := [0, 0, 0, 0, 0, 0] # Russian rounds on Ukrainian squads
	var battles := 0
	for map_id in GameConfig.MAPS.keys():
		GameConfig.set_active_map(map_id)
		for t in TRIALS:
			seed(1000 + t)
			var bm = TestBattleManagerScript.new()
			root.add_child(bm)
			var log = TestCombatLogScript.new()
			bm.start_battle(doctrine(), log)
			var consumed := 0
			var ticks := 0
			while not bm.battle_over and ticks < MAX_TICKS:
				bm._process(TICK_DELTA)
				ticks += 1
				while consumed < bm.shell_landing_log.size():
					var entry: Dictionary = bm.shell_landing_log[consumed]
					consumed += 1
					var row: Array = ours if entry.team == Unit.Team.PLAYER else theirs
					var caught_moving := false
					var caught_standing := false
					for v in entry.victims:
						if v.kind != Unit.Kind.SQUAD or v.team == entry.team or int(v.casualties) <= 0:
							continue
						if v.moving:
							row[0] += int(v.casualties)
							row[3] += 1
							caught_moving = true
						else:
							row[1] += int(v.casualties)
							row[5] += 1
							caught_standing = true
					if caught_moving:
						row[2] += 1
					if caught_standing:
						row[4] += 1
			battles += 1
			if is_instance_valid(log):
				log.free()
			bm.queue_free()
			await process_frame
	for pair in [["Ukrainian mortar rounds on Russian squads", ours], ["Russian mortar rounds on Ukrainian squads", theirs]]:
		var r: Array = pair[1]
		print("%s, %d battles: people lost per battle: moving %.2f, standing %.2f (moving share %.0f%%); squad-hits per battle: moving %.2f, standing %.2f; people lost per squad-hit: moving %.2f, standing %.2f" % [pair[0], battles, float(r[0]) / battles, float(r[1]) / battles, 100.0 * r[0] / maxf(r[0] + r[1], 1), float(r[3]) / battles, float(r[5]) / battles, float(r[0]) / maxf(r[3], 1), float(r[1]) / maxf(r[5], 1)])
	quit()
