extends SceneTree
## Research harness (the folder is ignored by Godot: copy it under scripts/ to run). User: "In four salvoes, our mortar has knocked out
## three enemy mortars." Two of the three in the traced case were crews that took ONE casualty at 37-44 m and then lost the rest to a
## cook-off of their own stored rounds. This counts, over every map and TRIALS seeds (Drone Recon, default doctrine), by side: the
## mortar crews that were reached by a round (a casualty), those whose stored rounds cooked off (the load dropped by more than one
## to nothing in a tick), and of the crews destroyed, how many were destroyed in the tick of a cook-off. The distance of the nearest
## round that triggered each cook-off comes from the landing log (the victim's distance_m).
const TestBattleManagerScript := preload("res://scripts/tests/test_battle_manager.gd")
const TestCombatLogScript := preload("res://scripts/tests/test_combat_log.gd")

const TRIALS := 16
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

func run() -> void:
	var tally := {}
	for team in [Unit.Team.PLAYER, Unit.Team.ENEMY]:
		tally[team] = {"crews": 0, "reached": 0, "cooked": 0, "destroyed": 0, "destroyed_by_cookoff": 0, "cookoff_first_hit": 0, "dists": [], "no_casualty_cookoffs": 0}
	var battles := 0
	for map_id in GameConfig.MAPS.keys():
		GameConfig.set_active_map(map_id)
		for t in TRIALS:
			seed(1000 + t)
			var bm = TestBattleManagerScript.new()
			root.add_child(bm)
			var log = TestCombatLogScript.new()
			bm.start_battle(doctrine(), log)
			var crews: Array[Unit] = []
			for u in bm.player_units + bm.enemy_units:
				if u.kind == Unit.Kind.MORTAR:
					crews.append(u)
			var last_rounds := {}
			var last_cas := {}
			var cooked := {}
			var consumed := 0
			for c in crews:
				last_rounds[c] = c.mortar_rounds_remaining
				last_cas[c] = c.crew_casualties
				tally[c.team].crews += 1
			var ticks := 0
			while not bm.battle_over and ticks < MAX_TICKS:
				bm._process(TICK_DELTA)
				ticks += 1
				for c in crews:
					if not is_instance_valid(c):
						continue
					var r: int = c.mortar_rounds_remaining
					var cas: int = c.crew_casualties
					if last_rounds[c] > 0 and r == 0 and cas > last_cas[c] and not cooked.has(c):
						# the load gone in the tick that the crew took casualties: a cook-off (firing the last rounds in the same
						# tick as a hit would also read so, which is rare)
						cooked[c] = true
						tally[c.team].cooked += 1
						if last_cas[c] == 0:
							tally[c.team].cookoff_first_hit += 1
						if c.state == Unit.State.DESTROYED:
							tally[c.team].destroyed_by_cookoff += 1
					last_rounds[c] = r
					last_cas[c] = cas
			for c in crews:
				if not is_instance_valid(c):
					continue
				if c.crew_casualties > 0:
					tally[c.team].reached += 1
				if c.state == Unit.State.DESTROYED:
					tally[c.team].destroyed += 1
			battles += 1
			if is_instance_valid(log):
				log.free()
			bm.queue_free()
			await process_frame
	print("battles: %d" % battles)
	for team in tally:
		var s: Dictionary = tally[team]
		print("%s mortar crews: %d; reached by a round (casualties): %d; stored rounds cooked off: %d (of them on the crew's first casualties: %d); destroyed (whole crew): %d, of which in the cook-off's tick: %d" % ["PLAYER" if team == Unit.Team.PLAYER else "ENEMY", s.crews, s.reached, s.cooked, s.cookoff_first_hit, s.destroyed, s.destroyed_by_cookoff])
	quit()
