extends SceneTree
## Research harness (the folder is ignored by Godot: copy it under scripts/ to run). User: "In four salvoes, our mortar has knocked out
## three enemy mortars. Check what is going on." For every map and TRIALS seeds (Drone Recon, default doctrine) it follows our mortar's
## salvos AT ENEMY MORTAR CREWS (one impact time at a mortar target is one salvo: the rounds of a burst land in the same tick) and,
## once the fourth has landed, counts the enemy's mortar crews that have taken casualties, that are destroyed (whole crew), and that are
## no longer active (destroyed, or left the gun). Also, per salvo number: the distance of its rounds' aim point's error to its target
## (impact point to the target's position at landing), and the rate at which a crew is destroyed or hurt by it.
const TestBattleManagerScript := preload("res://scripts/tests/test_battle_manager.gd")
const TestCombatLogScript := preload("res://scripts/tests/test_combat_log.gd")

const TRIALS := 40
const TICK_DELTA := 0.5
const MAX_TICKS := 9000

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
	var battles := 0
	var with_four := 0
	var hurt_hist := {}      # crews with casualties after the 4th salvo at mortars -> battles
	var dead_hist := {}      # crews destroyed
	var gone_hist := {}      # crews not active
	var by_salvo := {}       # nth salvo at mortars -> {"n", "within10", "within25", "within50", "moving"}
	var detail: Array[String] = []
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
			var seen := {}                    # impact_time key -> true
			var salvo_of := {}                # impact_time key -> salvo number
			var followed := {}                # one entry per round
			var landed_times: Array = []      # [{"time", "n", "d": [m...], "moving": bool}]
			var pending: Array = []           # shots being followed: {"shot", "n"}
			var salvos_seen := 0
			var four_landed := false
			var ticks := 0
			var snap := {}
			while not bm.battle_over and ticks < MAX_TICKS and not four_landed:
				bm._process(TICK_DELTA)
				ticks += 1
				for s in bm._pending_mortar_shots:
					if not (is_instance_valid(s.mortar) and s.mortar.team == Unit.Team.PLAYER):
						continue
					if not (is_instance_valid(s.target) and s.target.kind == Unit.Kind.MORTAR):
						continue
					var key := "%.2f" % s.impact_time
					if not seen.has(key):
						seen[key] = true
						salvos_seen += 1
						salvo_of[key] = salvos_seen
					var shot_key := "%s:%.1f:%.1f" % [key, s.impact_point.x, s.impact_point.y]
					if not followed.has(shot_key):
						followed[shot_key] = true
						pending.append({"shot": s, "n": salvo_of[key], "key": key})
				# pending shots are removed from bm's list when they land: judge them by time
				var still: Array = []
				for p in pending:
					if bm.scenario_elapsed_time >= p.shot.impact_time:
						if is_instance_valid(p.shot.target):
							var d: float = p.shot.impact_point.distance_to(p.shot.target.global_position) / GameConfig.PIXELS_PER_METER
							var b: Dictionary = by_salvo.get(p.n, {"n": 0, "w10": 0, "w25": 0, "w50": 0, "moving": 0})
							b.n += 1
							if d <= 10.0:
								b.w10 += 1
							if d <= 25.0:
								b.w25 += 1
							if d <= 50.0:
								b.w50 += 1
							if p.shot.target.activity == Unit.Activity.MOVING:
								b.moving += 1
							by_salvo[p.n] = b
						if p.n >= 4:
							four_landed = true
					else:
						still.append(p)
				pending = still
			battles += 1
			if four_landed:
				with_four += 1
				var hurt := 0
				var dead := 0
				var gone := 0
				for m in foes:
					if not is_instance_valid(m):
						dead += 1
						gone += 1
						hurt += 1
						continue
					if m.crew_casualties > 0:
						hurt += 1
					if m.state == Unit.State.DESTROYED:
						dead += 1
					if m.state != Unit.State.ACTIVE:
						gone += 1
				hurt_hist[hurt] = int(hurt_hist.get(hurt, 0)) + 1
				dead_hist[dead] = int(dead_hist.get(dead, 0)) + 1
				gone_hist[gone] = int(gone_hist.get(gone, 0)) + 1
				if hurt >= 3 or dead >= 3 or gone >= 3:
					detail.append("%s seed %d: %d enemy mortars; after the 4th salvo at a mortar: %d hurt, %d destroyed, %d not active (t=%.0f s)" % [map_id, 1000 + t, foes.size(), hurt, dead, gone, bm.scenario_elapsed_time])
			if is_instance_valid(log):
				log.free()
			bm.queue_free()
			await process_frame
	print("battles: %d; with four salvos at mortar crews: %d" % [battles, with_four])
	for pair in [["crews with casualties", hurt_hist], ["crews destroyed (whole crew)", dead_hist], ["crews not active (destroyed or left the gun)", gone_hist]]:
		var keys: Array = pair[1].keys()
		keys.sort()
		var line := "after the 4th salvo at a mortar, %s:" % pair[0]
		for k in keys:
			line += " %d: %d battles;" % [k, pair[1][k]]
		print(line)
	for k in [1, 2, 3, 4]:
		if by_salvo.has(k):
			var b: Dictionary = by_salvo[k]
			print("  salvo #%d at a mortar: %d rounds; within 10 m %s, within 25 m %s, within 50 m %s; target on the move %s" % [k, b.n, pct(b.w10, b.n), pct(b.w25, b.n), pct(b.w50, b.n), pct(b.moving, b.n)])
	for d in detail:
		print(d)
	quit()
