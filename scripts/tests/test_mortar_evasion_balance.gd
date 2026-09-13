extends SceneTree
## Guards against BOTH directions of a self-preservation-vs-productivity
## failure in BattleManager._mortar_should_relocate_for_safety — the real
## condition for a mortar needing to relocate: not "did I just fire" (an
## event this project tried and failed twice this session — see the
## design doc's own revision log), but "does the enemy currently know my
## position accurately enough to hit it."
##
##   1. UNDER-evasion: a mortar whose position genuinely IS compromised
##      (fired recently, hasn't moved clear since) with a known enemy
##      mortar in range must still relocate, even while otherwise idle —
##      the originally-reported gap ("mortar fired away at enemy mortars
##      multiple times, with no visible scoot at all").
##   2. FALSE-ALARM evasion: a mortar whose position is NOT compromised
##      (never fired, or already moved clear) must NOT relocate just
##      because an enemy mortar happens to exist somewhere in range — the
##      exact refinement that replaced the original (too broad) standing
##      check, which fired for ANY idle mortar regardless of whether its
##      OWN position had ever actually been given away.
##   3. OVER-evasion: a mortar with a persistent, repeatable shot
##      opportunity AND a persistent known threat must still manage to
##      BOTH relocate (not just keep firing forever from a burned
##      position) AND resume firing afterward (not get stuck perpetually
##      evading and never settling back into the fight) — "the mortar is
##      always scooting and never shooting," the mirror image of failure
##      mode 1, and "always shooting, never scooting," the failure mode
##      that motivated replacing the post-shot event trigger entirely.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_evasion_balance.gd
const Orders = preload("res://scripts/unit_doctrine.gd")
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func make_battle():
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	return bm


func test_compromised_idle_mortar_still_evades_a_known_threat() -> void:
	var bm = make_battle()
	var start: Vector2 = GameConfig.CURRENT_MAP.player.mortar_default_position
	bm._friendly_mortar_home_position = start
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, start)
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = 10
	mortar.seconds_stationary = 1e9 # already emplaced — free to fire or relocate right away
	mortar.is_visible = false
	mortar.shoot_and_scoot = true
	# Simulates having fired from right here a moment ago — the actual
	# condition that should matter, not merely being idle.
	bm._last_detected_mortar_fire[mortar] = {"position": start, "time": bm.scenario_elapsed_time}

	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, start + Vector2(400, 0))
	bm.enemy_units.append(enemy)
	enemy.is_visible = false
	enemy.player_has_been_sighted = true
	enemy.player_known_position = enemy.global_position

	bm.unit_type_doctrines[Unit.Team.PLAYER] = Orders.sanitize({})
	bm._decide_mortar_action(mortar)
	# The mortar started STATIONARY, so a genuine relocation goes through
	# the delayed "packing up" queue (_pending_mortar_displacement, real
	# MORTAR_SETUP_TEARDOWN_TIME later — see _queue_mortar_displacement's
	# own doc comment) rather than an immediate move_target — has_move_
	# target only flips true once that delay elapses and _resolve_pending_
	# mortar_displacement actually issues the walk.
	check(bm._pending_mortar_displacement.has(mortar),
		"A mortar whose position was just given away by firing, with a known enemy mortar in range, must still queue a relocation — not hold in place")
	bm.combat_log.free()
	bm.free()


func test_uncompromised_mortar_does_not_needlessly_evade() -> void:
	var bm = make_battle()
	var start: Vector2 = GameConfig.CURRENT_MAP.player.mortar_default_position
	bm._friendly_mortar_home_position = start
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, start)
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = 10
	mortar.seconds_stationary = 1e9
	mortar.is_visible = false
	mortar.shoot_and_scoot = true
	# Deliberately never fired from here — _last_detected_mortar_fire has
	# no entry for this mortar at all, matching a genuinely fresh position
	# the enemy has no reason to know about.

	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, start + Vector2(400, 0))
	bm.enemy_units.append(enemy)
	enemy.is_visible = false
	enemy.player_has_been_sighted = true
	enemy.player_known_position = enemy.global_position

	bm.unit_type_doctrines[Unit.Team.PLAYER] = Orders.sanitize({})
	bm._decide_mortar_action(mortar)
	# Check BOTH an immediate move AND a queued-but-not-yet-departed one —
	# a stationary mortar's relocation goes through the delayed
	# _pending_mortar_displacement queue (see the sibling test's own doc
	# comment), so has_move_target alone would miss a wrongly-queued
	# departure that just hasn't elapsed its pack-up delay yet.
	check(not mortar.has_move_target and not bm._pending_mortar_displacement.has(mortar),
		"A mortar that has never given its position away must NOT relocate (or even queue a relocation) just because an enemy mortar exists somewhere in range — its own position isn't actually known")
	bm.combat_log.free()
	bm.free()


## Full real-battle version of the over-evasion contract: a persistent,
## always-available target (so the mortar always has a reason to WANT to
## keep firing from the same spot) plus a persistently "known" enemy
## mortar (so the safety condition never lapses on its own). Real per-
## frame pacing (BattleManager._current_time_scale multiplies delta by
## 60x under live contact, so a coarse delta here would jump past the
## whole mechanic being tested in a single step — see this same trap
## documented at length in an earlier version of this file's own history).
func test_mortar_with_persistent_target_still_relocates_and_keeps_fighting() -> void:
	seed(20260913) # deterministic — this test's own pass/fail must not depend on which way unseeded rolls (hold-fire, cover-picking, spotting) happen to fall
	var bm = make_battle()
	var start: Vector2 = GameConfig.CURRENT_MAP.player.mortar_default_position
	bm._friendly_mortar_home_position = start
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, start)
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = 30
	mortar.base_hit_chance = 1.0
	mortar.shoot_and_scoot = true

	# The target IS an enemy mortar, kept permanently visible/live — this
	# serves as BOTH the repeatable shot opportunity ("an enemy mortar
	# candidate always wins" — _pick_target's own established rule) AND
	# the "known enemy mortar in range" signal _known_enemy_mortars_in_
	# range reads (its own `is_visible` branch). A separate SQUAD target
	# plus a separately-"known" mortar was tried first and didn't work:
	# any way of marking a second mortar "known" (player_has_been_sighted
	# OR _last_detected_mortar_fire — both feed _mortar_hunt_fix_for/
	# _pick_target's own "hold fire, pursue the known mortar instead"
	# logic) made the mortar perpetually hold or hunt instead of ever
	# engaging the squad — a real mechanic, but an artificial deadlock
	# specific to this test's own deliberately sparse setup. Using the
	# SAME unit for both roles sidesteps that entirely.
	var enemy_mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, start + Vector2(200, 0))
	bm.enemy_units.append(enemy_mortar)
	enemy_mortar.is_visible = true
	enemy_mortar.mortar_rounds_remaining = 0 # never fires back on its own — isolates the player mortar's own behavior
	enemy_mortar.crew_size = 1000 # never actually destroyed mid-test — stays a live, repeatable target throughout

	# Visibility isn't a flag that just stays set — CombatResolver.has_live_
	# observer re-checks LOS every tick and drops it the instant nobody's
	# actually watching (see _refresh_visibility's own doc comment), and a
	# mortar alone fires on spotter-relayed information, not its own direct
	# observation — without a real observer in player_units, nothing can
	# ever establish or maintain visibility on the target at all. A spotter
	# planted right on top of it guarantees a live, sustained sighting.
	var spotter: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, enemy_mortar.global_position)
	bm.player_units.append(spotter)

	bm.unit_type_doctrines[Unit.Team.PLAYER] = Orders.sanitize({})

	# Tracks the mortar's own position at the moment of EACH shot (not just
	# aggregate drift over the whole run, which an unrelated mechanism —
	# e.g. being genuinely visually spotted, a real, separate, already-
	# established tier-1 trigger this artificially close single-mortar-vs-
	# single-mortar setup makes likelier than a real battle would — could
	# satisfy by accident even if the mechanism under test were completely
	# broken and the mortar just kept firing from the exact same spot the
	# whole time). Requiring at least one shot to land meaningfully far
	# from the FIRST shot's own position is a direct, unconfoundable
	# signature of genuine relocation actually happening BETWEEN
	# engagements — the core claim under test.
	var shot_positions: Array[Vector2] = []
	var last_rounds: int = mortar.mortar_rounds_remaining
	var ticks := 0
	while ticks < 6000 and not bm.battle_over:
		bm._process(1.0 / 60.0)
		if is_instance_valid(mortar):
			mortar.is_visible = false # isolates the mechanic under test from that unrelated spotting trigger
			if mortar.mortar_rounds_remaining < last_rounds:
				shot_positions.append(mortar.global_position)
				last_rounds = mortar.mortar_rounds_remaining
		ticks += 1

	check(shot_positions.size() >= 2,
		"The mortar must fire more than once within a generous tick budget (fired %d times) — not get stuck perpetually evading and never settling back into the fight" % shot_positions.size())
	var max_spread_m := 0.0
	for p in shot_positions:
		max_spread_m = max(max_spread_m, shot_positions[0].distance_to(p) / GameConfig.PIXELS_PER_METER)
	check(max_spread_m > GameConfig.COUNTER_BATTERY_BLAST_RADIUS / GameConfig.PIXELS_PER_METER,
		"At least one shot must land meaningfully far (%.0fm) from where the FIRST shot fired — proving genuine relocation happened between engagements, not just firing forever from the same compromised spot" % max_spread_m)
	bm.combat_log.free()
	bm.free()


func run() -> void:
	test_compromised_idle_mortar_still_evades_a_known_threat()
	test_uncompromised_mortar_does_not_needlessly_evade()
	test_mortar_with_persistent_target_still_relocates_and_keeps_fighting()
	print("Mortar evasion-balance tests: %d failures" % failures)
	quit(1 if failures else 0)
