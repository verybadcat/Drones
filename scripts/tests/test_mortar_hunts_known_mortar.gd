extends SceneTree
## Regression test for a real, repeatedly-reported bug: the player mortar
## structurally never reached the "Destroy enemy mortars" tier, even with a
## known enemy mortar sitting right there — see docs/designs/tactical-
## commander-doctrine.md's 2026-09-09 entry "The mortar structurally never
## reached its own 'destroy enemy mortars' tier" for the full history (three
## separate root causes: _known_enemy_mortar_lead dropping a RETREATING-but-
## visible enemy mortar, no last-known-position memory once a mortar went
## quiet, and shoot-and-scoot's post-fire relocation being uninterruptible
## by hunting for however long the walk took). This was hard to pin down and
## easy to silently regress — measuring it directly here, once, so it can't
## quietly break again.
##
## Run: godot --headless --path . --script res://scripts/tests/test_mortar_hunts_known_mortar.gd

const TestBattleManagerScript := preload("res://scripts/tests/test_battle_manager.gd")
const TestCombatLogScript := preload("res://scripts/tests/test_combat_log.gd")

const TRIALS_PER_MODE := 8
const TICK_DELTA := 0.5
const EARLY_WINDOW_S := 1800.0 # first 30 tactical minutes
# A floor, not today's exact measured value (~4.9% at time of writing) —
# tuning changes are expected to move this around; regressing all the way
# back to (near) zero is what this guards against.
const MIN_HUNT_TIME_FRACTION := 0.02

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize():
	call_deferred("run")

func _build_doctrine(mode: GameConfig.ReconMode, seed_val: int) -> Dictionary:
	var squads: Array[Dictionary] = []
	for pos in GameConfig.CURRENT_MAP.player.default_squad_positions:
		squads.append({"position": pos, "retreat_threshold": 0.30})
	return {
		"squads": squads,
		"mortar": {"position": GameConfig.CURRENT_MAP.player.mortar_default_position, "shoot_and_scoot": true},
		"spotter": {"position": GameConfig.CURRENT_MAP.player.spotter_default_position},
		"recon_mode": mode,
		"seed": seed_val,
	}

func run():
	# Weighted by actual tactical seconds elapsed, not tick count — a
	# single macro-tick can jump through many tactical minutes at once
	# during TIME_SCALE_FAST_FORWARD (no contact yet), so a plain per-tick
	# count would wildly over-weight whichever stretch happens to run at
	# TIME_SCALE_NORMAL instead.
	var known_mortar_seconds := 0.0
	var hunt_seconds := 0.0

	for mode in [GameConfig.ReconMode.SPOTTER, GameConfig.ReconMode.DRONE_TEAM]:
		for trial in range(TRIALS_PER_MODE):
			var bm = TestBattleManagerScript.new()
			root.add_child(bm)
			var log = TestCombatLogScript.new()
			bm.start_battle(_build_doctrine(mode, 2000 + trial), log)

			var mortar: Unit = null
			for u in bm.player_units:
				if u.kind == Unit.Kind.MORTAR:
					mortar = u
			var ticks := 0
			var last_time: float = bm.scenario_elapsed_time
			while not bm.battle_over and bm.scenario_elapsed_time < EARLY_WINDOW_S and ticks < 20000:
				bm._process(TICK_DELTA)
				ticks += 1
				var delta: float = bm.scenario_elapsed_time - last_time
				last_time = bm.scenario_elapsed_time
				if mortar == null or mortar.state != Unit.State.ACTIVE:
					continue
				var any_known_enemy_mortar := false
				for e in bm.enemy_units:
					if e.kind == Unit.Kind.MORTAR and (e.is_visible or e.player_has_been_sighted):
						any_known_enemy_mortar = true
				if not any_known_enemy_mortar:
					continue
				known_mortar_seconds += delta
				var reasoning: Dictionary = bm._mortar_reasoning.get(mortar, {})
				if reasoning.get("tier", "") == "Destroy enemy mortars":
					hunt_seconds += delta
			bm.queue_free()

	var fraction: float = hunt_seconds / max(known_mortar_seconds, 1.0)
	print("Known-enemy-mortar tactical seconds sampled: %.1f" % known_mortar_seconds)
	print("Of which spent in 'Destroy enemy mortars': %.1f (%.1f%%)" % [hunt_seconds, fraction * 100.0])
	check(fraction >= MIN_HUNT_TIME_FRACTION, "The mortar should meaningfully hunt a known enemy mortar during the early battle — got %.1f%%, expected at least %.1f%%" % [fraction * 100.0, MIN_HUNT_TIME_FRACTION * 100.0])

	print("Mortar-hunts-known-mortar test: %d failures" % failures)
	quit(1 if failures else 0)
