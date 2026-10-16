extends SceneTree
## Research harness (the folder is ignored by Godot: copy it under scripts/ to run). User: "Yes" to looking into the enemy's assault
## rate, which rose from 3.7 to 8.4 assaults a battle when the mortar cook-off became rarer (2026-10-14). Over every map and TRIALS seeds
## (Drone Recon, default doctrine) it records, for the enemy's squads: every assault roll (one a minute per squad that has a target and
## the numbers), the chance it was rolled at and which of the multipliers applied (two or more volleys on the target in the last two
## minutes; the target silent three minutes after contact; the envelopment; the unsurrounded tenth), the force ratio, the assaults
## taken up and the time of each, and what came of each one two minutes on (the target's people lost, the attacker's, the target out of
## action; the number of enemy squads that joined it).
const TestBattleManagerScript := preload("res://scripts/tests/test_battle_manager.gd")
const TestCombatLogScript := preload("res://scripts/tests/test_combat_log.gd")

const TRIALS := 20
const TICK_DELTA := 0.5
const MAX_TICKS := 30000
const FOLLOW_S := 120.0

class Probe extends "res://scripts/tests/test_battle_manager.gd":
	var rolls: Array = []
	var starts: Array = []
	func _assault_chance_per_minute(u: Unit, t: Unit) -> float:
		var chance: float = super._assault_chance_per_minute(u, t)
		if u.team == Unit.Team.ENEMY:
			var volleys: Array = _volleys_at.get(t, [])
			var recent := 0
			for v in volleys:
				if scenario_elapsed_time - float(v) <= GameConfig.ASSAULT_SUPPRESSION_WINDOW_S:
					recent += 1
			var silent: bool = t.last_volley_at > -1.0e8 and scenario_elapsed_time - t.last_volley_at >= GameConfig.ASSAULT_SILENT_S
			var env: float = _envelopment_of(u, t)
			rolls.append({"t": scenario_elapsed_time, "chance": chance, "pinned_by_fire": recent >= 2, "silent": silent, "env": env, "surrounded": env >= GameConfig.ASSAULT_SURROUND_THRESHOLD - 0.01, "u": u, "target": t})
		return chance

	func _assault_update(u: Unit) -> bool:
		var before: int = int(_assaults_started.get(u.team, 0))
		var result: bool = super._assault_update(u)
		if u.team == Unit.Team.ENEMY and int(_assaults_started.get(u.team, 0)) > before:
			var t: Unit = _nearest_sighted_foe_squad(u, GameConfig.ASSAULT_CONSIDERATION_RANGE_M * GameConfig.PIXELS_PER_METER)
			var mates := 0
			for e in enemy_units:
				if e.kind == Unit.Kind.SQUAD and e.state == Unit.State.ACTIVE and t != null and e.global_position.distance_to(_known_position_by(u, t)) <= GameConfig.ASSAULT_CONSIDERATION_RANGE_M * GameConfig.PIXELS_PER_METER:
					mates += 1
			starts.append({"t": scenario_elapsed_time, "u": u, "target": t, "u_pips": u.pips, "t_pips": t.pips if t != null else 0, "mates": mates, "done": false})
		return result

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
	var rolls := 0
	var rolls_by := {"pinned_by_fire": 0, "silent": 0, "surrounded": 0}
	var chance_sum := 0.0
	var expected_by_bucket := {}
	var starts := 0
	var starts_by := {"pinned_by_fire": 0, "silent": 0, "surrounded": 0}
	var starts_per_battle: Array[int] = []
	var start_minutes: Array[float] = []
	var tgt_loss := 0
	var att_loss := 0
	var tgt_out := 0
	var followed := 0
	var mates_sum := 0
	var distinct_targets_sum := 0
	var our_squads_sum := 0
	for map_id in GameConfig.MAPS.keys():
		GameConfig.set_active_map(map_id)
		for t in TRIALS:
			seed(1000 + t)
			var bm = Probe.new()
			root.add_child(bm)
			var log = TestCombatLogScript.new()
			bm.start_battle(doctrine(), log)
			var ours := 0
			for p in bm.player_units:
				if p.kind == Unit.Kind.SQUAD:
					ours += 1
			our_squads_sum += ours
			var ticks := 0
			while not bm.battle_over and ticks < MAX_TICKS:
				bm._process(TICK_DELTA)
				ticks += 1
				for s in bm.starts:
					if not s.done and bm.scenario_elapsed_time >= s.t + FOLLOW_S:
						s.done = true
						if is_instance_valid(s.target) and is_instance_valid(s.u):
							followed += 1
							tgt_loss += maxi(s.t_pips - s.target.pips, 0)
							att_loss += maxi(s.u_pips - s.u.pips, 0)
							if s.target.state != Unit.State.ACTIVE:
								tgt_out += 1
			battles += 1
			if bm.starts.size() >= 40:
				var pairs := {}
				for s in bm.starts:
					var key := "%s -> %s" % [s.u.display_name(), s.target.display_name() if s.target != null else "?"]
					var rec: Dictionary = pairs.get(key, {"n": 0, "first": s.t, "last": s.t})
					rec.n += 1
					rec.last = s.t
					pairs[key] = rec
				print("LONG: %s seed %d: %d assaults, battle ended at %.0f min (over=%s)" % [map_id, 1000 + t, bm.starts.size(), bm.scenario_elapsed_time / 60.0, bm.battle_over])
				for key in pairs:
					print("   %s: %d times, minute %.0f to %.0f" % [key, pairs[key].n, pairs[key].first / 60.0, pairs[key].last / 60.0])
				for p in bm.player_units:
					if p.kind == Unit.Kind.SQUAD:
						print("   ours: %s state %d pips %d/%d at (%.0f,%.0f) terrain %d entrench %d posture %d" % [p.display_name(), p.state, p.pips, p.max_pips, p.global_position.x / GameConfig.PIXELS_PER_METER, p.global_position.y / GameConfig.PIXELS_PER_METER, GameConfig.get_terrain_type_at(p.global_position), p.entrenchment, p.posture(p.global_position)])
				var live := 0
				for e in bm.enemy_units:
					if e.kind == Unit.Kind.SQUAD and e.state == Unit.State.ACTIVE:
						live += 1
				print("   enemy squads still active: %d; our people %d" % [live, 0])
			rolls += bm.rolls.size()
			for r in bm.rolls:
				chance_sum += r.chance
				for k in rolls_by:
					if r[k]:
						rolls_by[k] += 1
			starts += bm.starts.size()
			starts_per_battle.append(bm.starts.size())
			var targets := {}
			for s in bm.starts:
				start_minutes.append(s.t / 60.0)
				mates_sum += s.mates
				if s.target != null:
					targets[s.target.get_instance_id()] = true
			distinct_targets_sum += targets.size()
			# which multipliers applied at the rolls that succeeded: match each start to the roll just before it by unit and time
			for s in bm.starts:
				for i in range(bm.rolls.size() - 1, -1, -1):
					var r: Dictionary = bm.rolls[i]
					if r.u == s.u and absf(r.t - s.t) < 1.0:
						for k in starts_by:
							if r[k]:
								starts_by[k] += 1
						break
			if is_instance_valid(log):
				log.free()
			bm.queue_free()
			await process_frame
	start_minutes.sort()
	print("battles: %d; our squads per battle %.1f" % [battles, float(our_squads_sum) / battles])
	print("enemy assault rolls per battle: %.1f, mean chance %.3f; rolls with 2+ volleys on the target: %s, target silent: %s, 3/4-circle-or-half held (surrounded): %s" % [float(rolls) / battles, chance_sum / maxf(rolls, 1), pct(rolls_by.pinned_by_fire, rolls), pct(rolls_by.silent, rolls), pct(rolls_by.surrounded, rolls)])
	print("assaults taken up per battle: %.2f; of them rolled with 2+ volleys: %s, target silent: %s, surrounded: %s" % [float(starts) / battles, pct(starts_by.pinned_by_fire, starts), pct(starts_by.silent, starts), pct(starts_by.surrounded, starts)])
	if not start_minutes.is_empty():
		print("assault times (minutes into the battle): first quartile %.0f, median %.0f, third quartile %.0f, latest %.0f" % [start_minutes[start_minutes.size() / 4], start_minutes[start_minutes.size() / 2], start_minutes[start_minutes.size() * 3 / 4], start_minutes[start_minutes.size() - 1]])
	print("distinct squads assaulted per battle: %.2f; enemy squads within reach of the target at the start of an assault: %.1f" % [float(distinct_targets_sum) / battles, float(mates_sum) / maxf(starts, 1)])
	print("two minutes after an assault began (%d followed): target lost %.2f people, attacker lost %.2f, target out of action in %s" % [followed, float(tgt_loss) / maxf(followed, 1), float(att_loss) / maxf(followed, 1), pct(tgt_out, followed)])
	var counts := {}
	for n in starts_per_battle:
		counts[n] = int(counts.get(n, 0)) + 1
	var keys: Array = counts.keys()
	keys.sort()
	var line := "battles by number of assaults:"
	for k in keys:
		line += " %d: %d;" % [k, counts[k]]
	print(line)
	quit()
