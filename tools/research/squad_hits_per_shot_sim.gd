extends SceneTree
## Research harness (the folder is ignored by Godot: copy it under scripts/ to run). User, 2026-10-23: "What I want is hits on squads per mortar shot at squads."
## For every map and TRIALS seeds (Drone Recon, default doctrine) it follows every mortar round fired at a SQUAD (whichever side fires: the intended target
## is read when the round is launched) to where it lands (BattleManager.shell_landing_log, matched on the impact point) and reports, for each side's mortars:
## the rounds fired at squads, the squads hit per round (a squad that lost at least one person), the people lost by the squads hit per round, the share of
## rounds that hit no squad / one / two / three or more, and the squads of the firing side's own that a round caught.
const TestBattleManagerScript := preload("res://scripts/tests/test_battle_manager.gd")
const TestCombatLogScript := preload("res://scripts/tests/test_combat_log.gd")

const TRIALS := 40
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

func key_of(team: int, impact: Vector2) -> String:
	return "%d|%.3f|%.3f" % [team, impact.x, impact.y]

func run() -> void:
	# per firing side: rounds, squads hit, people lost, histogram of squads hit, own squads caught, rounds that landed and were matched
	var stats := {}
	for side in [Unit.Team.PLAYER, Unit.Team.ENEMY]:
		stats[side] = {"rounds": 0, "landed": 0, "hits": 0, "people": 0, "hist": [0, 0, 0, 0], "own": 0}
	for map_id in GameConfig.MAPS.keys():
		GameConfig.set_active_map(map_id)
		for t in TRIALS:
			seed(1000 + t)
			var bm = TestBattleManagerScript.new()
			root.add_child(bm)
			var log = TestCombatLogScript.new()
			bm.start_battle(doctrine(), log)
			var seen := {}
			var at_squad := {} # key -> true for rounds launched at a squad
			var consumed := 0
			var ticks := 0
			while not bm.battle_over and ticks < MAX_TICKS:
				bm._process(TICK_DELTA)
				ticks += 1
				for s in bm._pending_mortar_shots:
					if not is_instance_valid(s.mortar):
						continue
					var k: String = key_of(s.mortar.team, s.impact_point) + "|%.2f" % s.impact_time
					if seen.has(k):
						continue
					seen[k] = true
					if is_instance_valid(s.target) and s.target.kind == Unit.Kind.SQUAD:
						at_squad[key_of(s.mortar.team, s.impact_point)] = int(s.mortar.team)
						stats[s.mortar.team].rounds += 1
				while consumed < bm.shell_landing_log.size():
					var entry: Dictionary = bm.shell_landing_log[consumed]
					consumed += 1
					var k2: String = key_of(entry.team, entry.impact)
					if not at_squad.has(k2):
						continue
					at_squad.erase(k2)
					var st: Dictionary = stats[entry.team]
					st.landed += 1
					var hit := 0
					for v in entry.victims:
						if v.kind != Unit.Kind.SQUAD or int(v.casualties) <= 0:
							continue
						if v.team == entry.team:
							st.own += 1
						else:
							hit += 1
							st.people += int(v.casualties)
					st.hits += hit
					st.hist[mini(hit, 3)] += 1
			if is_instance_valid(log):
				log.free()
			bm.queue_free()
			await process_frame
	for side in stats:
		var st: Dictionary = stats[side]
		var n: float = maxf(float(st.landed), 1.0)
		var h: Array = st.hist
		print("%s mortars: %d rounds fired at squads (%d seen landing): squads hit per round %.2f, people lost by them per round %.2f; rounds hitting no squad %.0f%%, one %.0f%%, two %.0f%%, three or more %.0f%%; own squads caught %d" % ["Ukrainian" if side == Unit.Team.PLAYER else "Russian", st.rounds, st.landed, float(st.hits) / n, float(st.people) / n, 100.0 * h[0] / n, 100.0 * h[1] / n, 100.0 * h[2] / n, 100.0 * h[3] / n, st.own])
	quit()
