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
## "Known" and "prioritizing" were both broadened once already (2026-09-11,
## after MORTAR_MAX_RANGE was extended to real 82mm figures): "known" now
## also counts a muzzle-flash/counter-battery detection, not just visual
## sighting (a mortar duel can resolve entirely through detected-firing
## leads without either side ever visually spotting the other), and
## "prioritizing" now also counts direct engagement via the higher
## "Target available" tier, not just the "Destroy enemy mortars" movement
## tier specifically — a long enough real range means the mortar is very
## often already in range of a known enemy mortar the instant it's
## discovered, with no repositioning ever needed at all. Both are the
## actual mechanism the game uses; the original, narrower measurement just
## went blind once the range change made the faster of the two paths the
## common one, reading a false 0% for underlying behavior that was intact.
##
## Run: godot --headless --path . --script res://scripts/tests/test_mortar_hunts_known_mortar.gd

const TestBattleManagerScript := preload("res://scripts/tests/test_battle_manager.gd")
const TestCombatLogScript := preload("res://scripts/tests/test_combat_log.gd")

const TRIALS_PER_MODE := 8
const TICK_DELTA := 0.5
const EARLY_WINDOW_S := 1800.0 # first 30 tactical minutes
# A floor, not today's exact measured value (~52% at time of writing,
# after both this test's own broadened "known"/"prioritizing" definitions
# and the real-range extension that made direct engagement common — see
# this file's own top doc comment) —
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
				# "Known" has to match what _mortar_hunt_fix_for/_known_enemy_
				# mortar_lead actually treat as a huntable lead — visual
				# sighting OR a muzzle-flash/counter-battery detection (see
				# BattleManager.mortar_ever_detected_firing) — not just
				# visual sighting alone. Checking only is_visible/
				# player_has_been_sighted here undercounts real hunting
				# activity: a mortar duel can resolve entirely through
				# detected-firing leads without either side ever achieving
				# true visual sighting of the other (found directly while
				# investigating why this test read a false 0% after
				# MORTAR_MAX_RANGE was extended — the underlying hunting
				# behavior was intact; this measurement was just blind to
				# the channel that had become dominant).
				var any_known_enemy_mortar := false
				for e in bm.enemy_units:
					if e.kind != Unit.Kind.MORTAR:
						continue
					if e.is_visible or e.player_has_been_sighted or bm.mortar_ever_detected_firing(e):
						any_known_enemy_mortar = true
				if not any_known_enemy_mortar:
					continue
				known_mortar_seconds += delta
				var reasoning: Dictionary = bm._mortar_reasoning.get(mortar, {})
				var tier: String = reasoning.get("tier", "")
				# "Prioritizing destroying enemy mortars" isn't only ever
				# the MOVEMENT tier below — with a long enough real range
				# (see GameConfig.MORTAR_MAX_RANGE's own doc comment), the
				# mortar is very often ALREADY in range of a known enemy
				# mortar the instant it's discovered, resolving straight
				# through the higher, faster "Target available" tier (step
				# 0's own memoized shot, which _pick_target already gives
				# an enemy mortar candidate overriding priority in) instead
				# of ever needing to physically close the distance first.
				# Both are the SAME underlying priority actually being
				# honored — checking only the movement tier undercounts
				# real hunting activity precisely when the range-driven
				# "direct engagement, no repositioning needed" case is
				# common (found directly while investigating a false 0%
				# after MORTAR_MAX_RANGE was extended).
				if tier == "Destroy enemy mortars":
					hunt_seconds += delta
				elif tier == "Target available":
					var current_target: Unit = bm._mortar_shot_this_tick(mortar, bm.enemy_units)
					if current_target != null and current_target.kind == Unit.Kind.MORTAR:
						hunt_seconds += delta
			bm.queue_free()

	var fraction: float = hunt_seconds / max(known_mortar_seconds, 1.0)
	print("Known-enemy-mortar tactical seconds sampled: %.1f" % known_mortar_seconds)
	print("Of which spent in 'Destroy enemy mortars': %.1f (%.1f%%)" % [hunt_seconds, fraction * 100.0])
	check(fraction >= MIN_HUNT_TIME_FRACTION, "The mortar should meaningfully hunt a known enemy mortar during the early battle — got %.1f%%, expected at least %.1f%%" % [fraction * 100.0, MIN_HUNT_TIME_FRACTION * 100.0])

	print("Mortar-hunts-known-mortar test: %d failures" % failures)
	quit(1 if failures else 0)
