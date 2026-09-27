extends SceneTree
## Direct user report, live: "drone was going back and forth a lot just now." Confirmed against the user's
## own actual running battle (fast-polling the live debug snapshots, this project's established diagnostic
## method): the drone flipped between "Tracking dangerous squad" and "Routine background recon" with NO
## change in the tracked squad's own visibility at all — a genuine, continuous score crossover, not a
## visibility flicker (see the sibling, independently-confirmed cause and fix in
## test_drone_lost_contact_flicker.gd for the other reported instance of "going back and forth").
##
## Root cause: `_drone_mortar_search_weight`'s own squad-danger discount (`_known_squad_danger_pressure`)
## computes its threat term with the EXACT same "how close to a friendly, as a fraction of SQUAD_DANGER_
## RANGE" ratio that `_squad_danger_priority` itself uses for the SAME squad. So as a tracked squad's own
## danger score drifts DOWN (moving away from a friendly), that very same movement pushes recon's competing
## score UP (less danger left to discount its mortar-search value for) — a real, mathematically-coupled
## seesaw around the crossover point between the two tiers, with nothing to stop an ordinary few meters of
## drift from flipping the choice back and forth. The same "small changes in range... should not cause the
## drone to oscillate" principle this project already had to apply once before, for mortar-target
## selection (2026-09-16) — this is a second, independent instance of the same class, for a different pair
## of tiers.
##
## Fix: handing off FROM an already-committed "Tracking dangerous squad" pick TO recon now requires recon's
## score to clear the same margin `_drone_commitment_has_collapsed` already uses for its own cross-candidate
## handoffs (`GameConfig.DRONE_COMMITMENT_ABANDON_FRACTION`) — acquiring a newly-dangerous squad to track in
## the first place is a genuinely valuable event and stays immediate, unchanged.
##
## Run: godot --headless --path . --script scripts/tests/test_drone_squad_tracking_recon_handoff.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(x: float, y: float) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

## One friendly squad (the "threatened" reference point _squad_danger_priority measures against), the
## drone team, and an airborne drone — no friendly mortar, matching the live battle's own reported state
## (mortar-existence confidence 0.00, both mortars already accounted for).
func make_battle(friendly_pos_m: Vector2):
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	var f: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(friendly_pos_m.x, friendly_pos_m.y))
	bm.player_units.append(f)
	bm.drone_team = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, m(friendly_pos_m.x - 500.0, friendly_pos_m.y))
	bm.player_units.append(bm.drone_team)
	var d: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, m(friendly_pos_m.x, friendly_pos_m.y))
	bm.player_units.append(d)
	d.drone_battery_charge = 0.9
	bm.active_drone = d
	return bm

func cleanup(bm) -> void:
	bm.combat_log.free()
	bm.free()

## The shared ratio both real scores are built from: r = 1 - dist/SQUAD_DANGER_RANGE.
func squad_score_at(r: float) -> float:
	return GameConfig.TARGET_PRIORITY_SQUAD_MAX * r

## Mirrors _drone_mortar_search_weight's own formula exactly, at the confidence floor (no known/suspected
## mortar at all — the live battle's own state) and with `r` as the ONE known squad's danger pressure.
func routine_score_at(r: float) -> float:
	var confidence: float = GameConfig.DRONE_UNKNOWN_MORTAR_RESIDUAL_CONFIDENCE
	return GameConfig.TARGET_PRIORITY_UNDISCOVERED_MORTAR_SWEEP * confidence * (1.0 - GameConfig.DRONE_MORTAR_SEARCH_DANGER_DISCOUNT * r)

func run() -> void:
	test_marginal_crossover_does_not_pull_the_drone_off_a_tracked_squad()
	test_a_genuinely_low_danger_squad_can_still_cede_to_recon()
	test_acquiring_a_newly_dangerous_squad_stays_immediate()
	test_a_slow_walk_through_the_crossover_does_not_flap()
	print("Drone squad-tracking/recon handoff tests: %d failures" % failures)
	quit(1 if failures else 0)


## The exact reported shape: found the real coupled crossover from the actual constants (not hand-computed,
## so this stays correct if they ever change), confirms a small drift PAST it would flip the raw comparison,
## and confirms the fix holds the line anyway once already tracking.
func test_marginal_crossover_does_not_pull_the_drone_off_a_tracked_squad() -> void:
	var lo := 0.0
	var hi := 1.0
	for i in 40:
		var mid: float = (lo + hi) * 0.5
		if squad_score_at(mid) > routine_score_at(mid):
			hi = mid
		else:
			lo = mid
	var r: float = (lo + hi) * 0.5
	check(absf(squad_score_at(r) - routine_score_at(r)) < 0.01, "Setup: found the real coupled crossover point (r=%.4f, squad=%.3f, routine=%.3f)" % [r, squad_score_at(r), routine_score_at(r)])

	var bm = make_battle(Vector2(0, 0))
	var dist_m: float = (1.0 - r) * GameConfig.SQUAD_DANGER_RANGE / GameConfig.PIXELS_PER_METER
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(dist_m, 0))
	bm.enemy_units.append(enemy)
	enemy.is_visible = true
	bm._drone_search_target()
	check(bm._drone_pilot_reasoning.get("tier", "") == "Tracking dangerous squad", "Setup: right at the crossover, tracking wins first (%s)" % str(bm._drone_pilot_reasoning.get("tier", "")))

	# A few real meters farther out — enough that, on the raw numbers, routine would nominally edge ahead
	# (the exact live shape: a slow, ordinary drift crossing the coupled point), but nowhere near the
	# required margin.
	enemy.global_position = m(dist_m + 5.0, 0)
	check(routine_score_at(1.0 - (dist_m + 5.0) * GameConfig.PIXELS_PER_METER / GameConfig.SQUAD_DANGER_RANGE) > squad_score_at(1.0 - (dist_m + 5.0) * GameConfig.PIXELS_PER_METER / GameConfig.SQUAD_DANGER_RANGE), "Setup: the raw (unprotected) comparison really would now favor recon")
	bm._drone_search_target()
	check(bm._drone_pilot_reasoning.get("tier", "") == "Tracking dangerous squad", "A few meters of drift just past the raw crossover must not hand off to recon (%s)" % str(bm._drone_pilot_reasoning.get("tier", "")))
	cleanup(bm)


## Not a "never cede" fix: once the tracked squad's own danger has fallen far enough that recon clears the
## real margin, it still correctly gives way.
func test_a_genuinely_low_danger_squad_can_still_cede_to_recon() -> void:
	var bm = make_battle(Vector2(0, 0))
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(600.0, 0))
	bm.enemy_units.append(enemy)
	enemy.is_visible = true
	bm._drone_search_target()
	check(bm._drone_pilot_reasoning.get("tier", "") == "Tracking dangerous squad", "Setup: close enough to be worth tracking first (%s)" % str(bm._drone_pilot_reasoning.get("tier", "")))
	# Now essentially at the edge of SQUAD_DANGER_RANGE: near-zero danger score, so even the required
	# (margin-scaled) threshold is easily cleared by recon's own floor value.
	enemy.global_position = m(GameConfig.SQUAD_DANGER_RANGE / GameConfig.PIXELS_PER_METER * 0.999, 0)
	bm._drone_search_target()
	check(bm._drone_pilot_reasoning.get("tier", "") != "Tracking dangerous squad", "A squad at essentially zero danger correctly cedes to routine recon (%s)" % str(bm._drone_pilot_reasoning.get("tier", "")))
	cleanup(bm)


## The fix is deliberately asymmetric: ACQUIRING a squad worth tracking (nothing was being tracked before)
## must not be delayed by any margin at all — only relinquishing an existing commitment is protected.
func test_acquiring_a_newly_dangerous_squad_stays_immediate() -> void:
	var bm = make_battle(Vector2(0, 0))
	bm._drone_search_target()
	check(bm._drone_pilot_reasoning.get("tier", "") != "Tracking dangerous squad", "Setup: nothing to track yet")
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(100.0, 0)) # close, clearly dangerous
	bm.enemy_units.append(enemy)
	enemy.is_visible = true
	bm._drone_search_target()
	check(bm._drone_pilot_reasoning.get("tier", "") == "Tracking dangerous squad", "A genuinely dangerous squad is picked up immediately, no margin required to acquire it")
	cleanup(bm)


## The general, top-level guard the user explicitly asked for: not just the exact reported point, but a
## whole slow walk through the coupled crossover region (a squad wandering back and forth a few meters
## around it, the ordinary noise of real movement) must not repeatedly flip the tier back and forth. Same
## reversal-counting methodology as test_drone_no_dithering.gd's own live-report reproduction, applied to
## the TOP-LEVEL _drone_search_target this time, not just the routine-recon pool underneath it — so a
## future tier added anywhere in that same top-level comparison, competing at a similarly close margin
## against an already-committed squad-tracking pick, would be caught here too.
func test_a_slow_walk_through_the_crossover_does_not_flap() -> void:
	var lo := 0.0
	var hi := 1.0
	for i in 40:
		var mid: float = (lo + hi) * 0.5
		if squad_score_at(mid) > routine_score_at(mid):
			hi = mid
		else:
			lo = mid
	var r_cross: float = (lo + hi) * 0.5
	var dist_cross_m: float = (1.0 - r_cross) * GameConfig.SQUAD_DANGER_RANGE / GameConfig.PIXELS_PER_METER

	var bm = make_battle(Vector2(0, 0))
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(dist_cross_m, 0))
	bm.enemy_units.append(enemy)
	enemy.is_visible = true

	var last := ""
	var switches := 0
	for i in 200:
		# A small, slow oscillation around the crossover distance itself (+/- 40m over the walk) — exactly
		# the kind of ordinary back-and-forth drift a real squad's own movement produces near any fixed
		# reference distance, not a contrived worst case.
		var offset_m: float = 40.0 * sin(float(i) * 0.1)
		enemy.global_position = m(dist_cross_m + offset_m, 0)
		bm._drone_search_target()
		var tier: String = bm._drone_pilot_reasoning.get("tier", "")
		if tier != last:
			if last != "":
				switches += 1
			last = tier
	check(switches <= 2, "A slow walk back and forth across the crossover must not repeatedly flip the tier (got %d switches in 200 steps)" % switches)
	cleanup(bm)
