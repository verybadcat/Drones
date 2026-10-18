extends SceneTree
## Research harness (the folder is ignored by Godot: copy it under scripts/ to run). The crew-strength rules of 2026-10-18 (fewer than two cannot fire; two
## cannot move the gun and shoot and hide, then fire everything and leave it if they must go; three move it slower with more rounds aboard). Over every
## map and TRIALS seeds (Drone Recon, default doctrine) it counts, by side: mortar crews that ever had two, or fewer than two, left serving; the last
## stands made (and the rounds fired in them); mortars left abandoned at the end; and the seconds crews spent at three or two serving.
const TestCombatLogScript := preload("res://scripts/tests/test_combat_log.gd")

const TRIALS := 20
const TICK_DELTA := 0.5
const MAX_TICKS := 30000

class Probe extends "res://scripts/tests/test_battle_manager.gd":
	var last_stands: Array = []
	func _stuck_crew_last_stand(m: Unit) -> void:
		var rounds: int = m.mortar_rounds_remaining
		var had_target: bool = _last_stand_target(m) != null
		super._stuck_crew_last_stand(m)
		last_stands.append({"team": m.team, "rounds": rounds - m.mortar_rounds_remaining, "had_rounds": rounds, "had_target": had_target, "time": scenario_elapsed_time})

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
	var tally := {}
	for team in [Unit.Team.PLAYER, Unit.Team.ENEMY]:
		tally[team] = {"crews": 0, "ever_two": 0, "ever_below_two": 0, "last_stands": 0, "last_stand_rounds": 0, "abandoned_end": 0, "destroyed_end": 0, "secs_three": 0.0, "secs_two": 0.0, "rounds_fired_stuck": 0}
	var stalemates := 0
	var dry_stands := {}
	var no_target_stands := {}
	var minutes_total := 0.0
	var battles := 0
	for map_id in GameConfig.MAPS.keys():
		GameConfig.set_active_map(map_id)
		for t in TRIALS:
			seed(1000 + t)
			var bm = Probe.new()
			root.add_child(bm)
			var log = TestCombatLogScript.new()
			bm.start_battle(doctrine(), log)
			var crews: Array[Unit] = []
			for u in bm.player_units + bm.enemy_units:
				if u.kind == Unit.Kind.MORTAR:
					crews.append(u)
			var seen_two := {}
			var seen_below := {}
			for c in crews:
				tally[c.team].crews += 1
			var ticks := 0
			while not bm.battle_over and ticks < MAX_TICKS:
				bm._process(TICK_DELTA)
				ticks += 1
				for c in crews:
					if not is_instance_valid(c) or c.state == Unit.State.DESTROYED:
						continue
					var serving: int = c.crew_size - c.crew_casualties
					if serving == 2 and not c.mortar_gun_abandoned:
						seen_two[c] = true
						tally[c.team].secs_two += TICK_DELTA
					elif serving == 3 and not c.mortar_gun_abandoned:
						tally[c.team].secs_three += TICK_DELTA
					if serving < 2:
						seen_below[c] = true
			for c in crews:
				if seen_two.has(c):
					tally[c.team].ever_two += 1
				if seen_below.has(c):
					tally[c.team].ever_below_two += 1
				if is_instance_valid(c):
					if c.state == Unit.State.DESTROYED:
						tally[c.team].destroyed_end += 1
					elif c.mortar_gun_abandoned:
						tally[c.team].abandoned_end += 1
			for s in bm.last_stands:
				tally[s.team].last_stands += 1
				tally[s.team].last_stand_rounds += s.rounds
				if s.had_rounds <= 0:
					dry_stands[s.team] = int(dry_stands.get(s.team, 0)) + 1
				elif not s.had_target:
					no_target_stands[s.team] = int(no_target_stands.get(s.team, 0)) + 1
			battles += 1
			if bm._ended_by_stalemate:
				stalemates += 1
			minutes_total += bm.scenario_elapsed_time / 60.0
			if is_instance_valid(log):
				log.free()
			bm.queue_free()
			await process_frame
	print("battles: %d; ended as a stalemate (no fire, no movement, no armed mortar, or the time limit with both sides on the field): %d; mean length %.0f minutes" % [battles, stalemates, minutes_total / battles])
	for team in tally:
		var s: Dictionary = tally[team]
		print("%s mortar crews: %d; ever down to two serving: %d; ever below two: %d; last stands: %d (%.1f rounds each); ended with the gun left: %d; destroyed: %d; minutes at three serving: %.0f, at two: %.0f" % ["PLAYER" if team == Unit.Team.PLAYER else "ENEMY", s.crews, s.ever_two, s.ever_below_two, s.last_stands, float(s.last_stand_rounds) / maxf(s.last_stands, 1), s.abandoned_end, s.destroyed_end, s.secs_three / 60.0, s.secs_two / 60.0])
	print("last stands made dry: %s; with rounds but nothing in reach: %s" % [str(dry_stands), str(no_target_stands)])
	quit()
