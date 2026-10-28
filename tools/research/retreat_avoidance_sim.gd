extends SceneTree
## Research harness (the folder is ignored by Godot: copy it under scripts/ to run). User, 2026-10-28: "Retreating enemies should avoid our squads when the position
## is known. This is similar to how retreating friendlies should avoid enemy squads when the position is known. In both cases, make sure it is really avoided."
## For every map and TRIALS seeds (Drone Recon, default doctrine) it follows each squad from the moment it starts to retreat (state RETREATING) until it is no
## longer retreating, and reads, every tick, its distance to the nearest opposing SQUAD that its own side knows the position of (BattleManager._known_enemy_positions,
## squads only, as the known position, not the true one). Per side it reports: the retreats; the distance to the nearest known squad at the start and the least it came
## to; how many came at least 50 m closer to one than they began; the time spent within 200 m and within 400 m (the engagement range) of one; and the casualties
## a retreating squad took per retreat.
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

func nearest_known_m(bm, u: Unit) -> float:
	var best := INF
	for p in bm._known_enemy_positions(u.team, false, false):
		best = minf(best, u.global_position.distance_to(p))
	return best / GameConfig.PIXELS_PER_METER

func nearest_known_pos(bm, u: Unit) -> Vector2:
	var best := INF
	var at := Vector2.INF
	for p in bm._known_enemy_positions(u.team, false, false):
		var d: float = u.global_position.distance_to(p)
		if d < best:
			best = d
			at = p
	return at

var examples: Array[String] = []

func quantiles(values: Array) -> String:
	if values.is_empty():
		return "(none)"
	values.sort()
	var n: int = values.size()
	return "10%% %.0f, 25%% %.0f, median %.0f, 75%% %.0f m" % [values[int(n * 0.1)], values[int(n * 0.25)], values[int(n * 0.5)], values[int(n * 0.75)]]

func run() -> void:
	# per side: [starts, least distances, approach (start - least), closer-by-50 count, seconds within 200, seconds within 400, retreat seconds, casualties, retreats with a known squad]
	var data := {}
	for side in [Unit.Team.PLAYER, Unit.Team.ENEMY]:
		data[side] = {"n": 0, "known": 0, "start": [], "least": [], "closer": 0, "far": 0, "entered400": 0, "entered200": 0, "inside": 0, "inside_closer": 0, "in200": 0.0, "in400": 0.0, "secs": 0.0, "lost": 0}
	for map_id in GameConfig.MAPS.keys():
		GameConfig.set_active_map(map_id)
		for t in TRIALS:
			seed(1000 + t)
			var bm = TestBattleManagerScript.new()
			root.add_child(bm)
			var log = TestCombatLogScript.new()
			bm.start_battle(doctrine(), log)
			var open := {} # unit -> {start, least, pips_start}
			var ticks := 0
			while not bm.battle_over and ticks < MAX_TICKS:
				bm._process(TICK_DELTA)
				ticks += 1
				for u in bm.player_units + bm.enemy_units:
					if u.kind != Unit.Kind.SQUAD:
						continue
					var d: Dictionary = data[u.team]
					if u.state == Unit.State.RETREATING:
						var near_m: float = nearest_known_m(bm, u)
						if not open.has(u):
							open[u] = {"start": near_m, "least": near_m, "pips": u.pips, "from": u.global_position, "foe_from": nearest_known_pos(bm, u), "t0": bm.scenario_elapsed_time, "lp": u.global_position, "foe_lp": nearest_known_pos(bm, u), "move_leg": u.has_move_target, "visible": u.is_visible}
							d.n += 1
							if not is_inf(near_m):
								d.known += 1
								d.start.append(near_m)
						var rec: Dictionary = open[u]
						if near_m < float(rec.least):
							rec.least = near_m
							rec.lp = u.global_position
							rec.foe_lp = nearest_known_pos(bm, u)
							rec.leg_at_least = u.has_move_target
						rec.until = bm.scenario_elapsed_time
						d.secs += TICK_DELTA
						if near_m <= 200.0:
							d.in200 += TICK_DELTA
						if near_m <= 400.0:
							d.in400 += TICK_DELTA
					elif open.has(u):
						var rec2: Dictionary = open[u]
						if not is_inf(float(rec2.start)):
							d.least.append(float(rec2.least))
							if float(rec2.start) > 400.0:
								d.far += 1
								if float(rec2.least) <= 400.0:
									d.entered400 += 1
								if float(rec2.least) <= 200.0:
									d.entered200 += 1
							else:
								d.inside += 1
								if float(rec2.least) < float(rec2.start) - 50.0:
									d.inside_closer += 1
							if float(rec2.least) < float(rec2.start) - 50.0:
								d.closer += 1
								if examples.size() < 40 and float(rec2.least) <= 400.0:
									var go: Vector2 = (rec2.lp - rec2.from) / GameConfig.PIXELS_PER_METER
									var foe_moved: float = rec2.foe_lp.distance_to(rec2.foe_from) / GameConfig.PIXELS_PER_METER
									examples.append("%s %s: start %.0f m, least %.0f m after %.0f s; went (%.0f, %.0f) m; the squad's known position moved %.0f m; cover leg at the start %s, at the least %s; was visible at the start %s; ended %s" % ["Ukr" if u.team == Unit.Team.PLAYER else "Rus", map_id, rec2.start, rec2.least, rec2.until - rec2.t0, go.x, go.y, foe_moved, str(rec2.move_leg), str(rec2.get("leg_at_least", false)), str(rec2.visible), str(u.state)])
						d.lost += int(rec2.pips) - u.pips
						open.erase(u)
			if is_instance_valid(log):
				log.free()
			bm.queue_free()
			await process_frame
	for side in data:
		var d: Dictionary = data[side]
		print("%s squads: %d retreats (%d with a known opposing squad at the start)" % ["Ukrainian" if side == Unit.Team.PLAYER else "Russian", d.n, d.known])
		print("   nearest known squad at the start: " + quantiles(d.start))
		print("   least distance reached to one: " + quantiles(d.least))
		print("   retreats that came at least 50 m closer to a known squad than they began: %d of %d (%.0f%%)" % [d.closer, d.least.size(), 100.0 * d.closer / maxf(d.least.size(), 1)])
		print("   retreats that began more than 400 m from every known squad (%d): came within 400 m of one %d (%.0f%%), within 200 m %d (%.0f%%); retreats that began within 400 m of one (%d): came at least 50 m closer %d (%.0f%%)" % [d.far, d.entered400, 100.0 * d.entered400 / maxf(d.far, 1), d.entered200, 100.0 * d.entered200 / maxf(d.far, 1), d.inside, d.inside_closer, 100.0 * d.inside_closer / maxf(d.inside, 1)])
		print("   time retreating %.0f s: within 200 m of a known squad %.0f%%, within 400 m %.0f%%; people lost while retreating per retreat %.2f" % [d.secs, 100.0 * d.in200 / maxf(d.secs, 1.0), 100.0 * d.in400 / maxf(d.secs, 1.0), float(d.lost) / maxf(d.n, 1)])
	print("examples of a retreat that came 50 m closer to a known squad and within 400 m of it:")
	for e in examples:
		print("   " + e)
	quit()
