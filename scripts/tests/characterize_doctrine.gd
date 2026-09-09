extends SceneTree
## Doctrine behavior characterization suite — run BEFORE the planned
## tactical-decisionmaking rewrite (see docs/designs/tactical-commander-
## doctrine.md and the "before-tactical-rewrite" git tag) to capture how
## the CURRENT, hand-authored doctrine rules actually behave in practice,
## across many stochastic trials. This is a baseline-capture-and-compare
## tool, not a pass/fail regression gate: the rewrite is explicitly meant
## to change specific numbers (that's the point of grounding decisions in
## general principles instead of individually-tuned thresholds), so this
## suite records what IS today, not what SHOULD be. Re-run the exact same
## script after the rewrite and diff the two reports by eye.
##
## Uses TestBattleManager/TestUnit (see those files) — thin instrumented
## subclasses that override specific decision points purely to COUNT what
## they did, always delegating to super() for the real behavior, so
## everything measured here is exactly the logic that ships. Drives
## BattleManager directly (not through main.gd/the SubViewport+camera —
## irrelevant to battle outcomes) so trials run as fast as the CPU can
## compute them, entirely synchronously.
##
## Run with:
##   Godot_console.exe --headless --path . --script res://scripts/tests/characterize_doctrine.gd
## Writes docs/designs/pre-rewrite-baseline.json (raw per-metric data) and
## docs/designs/pre-rewrite-baseline.md (human-readable summary).

const TestBattleManagerScript := preload("res://scripts/tests/test_battle_manager.gd")
const TestCombatLogScript := preload("res://scripts/tests/test_combat_log.gd")

const TRIALS_PER_MODE := 100
const MAX_TICKS := 30000
const TICK_DELTA := 0.5
const RETREAT_THRESHOLD := 0.30 # DoctrinePanel's own default slider value

const OUTPUT_JSON := "res://docs/designs/pre-rewrite-baseline.json"
const OUTPUT_MD := "res://docs/designs/pre-rewrite-baseline.md"

## Battle-outcome scoring rubric, fixed by the user (2026-09-08) — the
## concrete operationalization of "win the battle / keep our people alive
## / cause enemy casualties" the planned rewrite is meant to derive
## decisions from. Computed TWICE per trial: once against TRUE ground
## truth (the internal score actual decisions should be evaluated
## against) and once against the PLAYER'S OWN best-guess/estimated
## figures (what would actually justify a displayed verdict label) — the
## two are expected to sometimes disagree, same as the rest of this
## game's AAR already can. Deliberately excludes any "recon asset lost"
## term: per the user, this scores FINAL outcomes only, not intermediate/
## replaceable capability effects — a drone-team casualty is already
## counted as an ordinary friendly death/wounded, same as any squad's.
const SCORE_POSITION_HELD := 20.0
const SCORE_POSITION_LOST := -20.0
const SCORE_FRIENDLY_DEATH := -10.0
const SCORE_ENEMY_DEATH := 5.0
const SCORE_FRIENDLY_CAPTURED := -8.0
const SCORE_ENEMY_CAPTURED := 8.0
const SCORE_FRIENDLY_HEAVILY_WOUNDED := -4.0
const SCORE_ENEMY_HEAVILY_WOUNDED := 2.0
const SCORE_FRIENDLY_WALKING_WOUNDED := -1.0
const SCORE_ENEMY_WALKING_WOUNDED := 0.5
const SCORE_FRIENDLY_MORTAR_LOST := -5.0 # the gun itself, on top of whatever its crew already cost above
const SCORE_ENEMY_MORTAR_OUT := 2.5 # destroyed, or abandoned on ground the player ends up holding


func _score_battle(held: bool, player_killed: int, player_captured: int, player_heavily_wounded: int, player_walking_wounded: int, player_mortar_lost: int, enemy_killed: int, enemy_captured: int, enemy_heavily_wounded: int, enemy_walking_wounded: int, enemy_mortar_out: int) -> float:
	var score := SCORE_POSITION_HELD if held else SCORE_POSITION_LOST
	score += SCORE_FRIENDLY_DEATH * player_killed
	score += SCORE_ENEMY_DEATH * enemy_killed
	score += SCORE_FRIENDLY_CAPTURED * player_captured
	score += SCORE_ENEMY_CAPTURED * enemy_captured
	score += SCORE_FRIENDLY_HEAVILY_WOUNDED * player_heavily_wounded
	score += SCORE_ENEMY_HEAVILY_WOUNDED * enemy_heavily_wounded
	score += SCORE_FRIENDLY_WALKING_WOUNDED * player_walking_wounded
	score += SCORE_ENEMY_WALKING_WOUNDED * enemy_walking_wounded
	score += SCORE_FRIENDLY_MORTAR_LOST * player_mortar_lost
	score += SCORE_ENEMY_MORTAR_OUT * enemy_mortar_out
	return score


## Ground truth: is `mortar` actually destroyed, or abandoned on ground
## the player ends up holding? The "abandoned on held ground" half ties
## to the AAR's own "holding lets you confirm what was left behind"
## mechanic — a withdrawn/retreating crew only counts once the position
## itself is confirmed held, not merely because it happened to flee.
func _mortar_out_true(mortar: Unit, held: bool) -> bool:
	if mortar.state == Unit.State.DESTROYED:
		return true
	return held and (mortar.state == Unit.State.WITHDRAWN or mortar.state == Unit.State.RETREATING)


## The player's own best-guess equivalent, for the displayed-verdict
## score — mirrors _compute_side_stats's own per-unit confirmation logic
## (battle_manager.gd) exactly: a withdrawn/retreating enemy is only
## "confirmed" if the position is held AND it was actually sighted at
## some point; otherwise the honest assumption is that it's still in
## action, same as the rest of the AAR would report.
func _mortar_out_estimated(mortar: Unit, held: bool) -> bool:
	var unrecoverable: bool = mortar.state == Unit.State.WITHDRAWN or mortar.state == Unit.State.RETREATING
	var unit_estimated: bool = (not held) or unrecoverable
	if unit_estimated and not mortar.player_has_been_sighted:
		return false
	var eff_state: Unit.State = mortar.player_known_state if unit_estimated else mortar.state
	return eff_state == Unit.State.DESTROYED or eff_state == Unit.State.WITHDRAWN or eff_state == Unit.State.RETREATING


func _build_doctrine(mode: GameConfig.ReconMode) -> Dictionary:
	var squads: Array[Dictionary] = []
	for pos in GameConfig.PLAYER_DEFAULT_POSITIONS:
		squads.append({"position": pos, "retreat_threshold": RETREAT_THRESHOLD})
	return {
		"squads": squads,
		"mortar": {"position": GameConfig.PLAYER_MORTAR_DEFAULT_POSITION, "shoot_and_scoot": false},
		"spotter": {"position": GameConfig.PLAYER_SPOTTER_DEFAULT_POSITION},
		"recon_mode": mode,
	}


## Mirrors _end_battle's own held/exchange_ratio/verdict logic exactly
## (battle_manager.gd) — those are local variables there, never stored on
## the instance, so this suite recomputes them the same way from the same
## public accessors rather than parsing the AAR text.
func _run_one_trial(mode: GameConfig.ReconMode) -> Dictionary:
	var bm = TestBattleManagerScript.new()
	root.add_child(bm)
	var log = TestCombatLogScript.new()
	bm.start_battle(_build_doctrine(mode), log)

	var ticks := 0
	while not bm.battle_over and ticks < MAX_TICKS:
		bm._process(TICK_DELTA)
		ticks += 1
	var hung: bool = not bm.battle_over

	var player_stats: Dictionary = bm._compute_side_stats(bm.player_units)
	var true_enemy_stats: Dictionary = bm._compute_side_stats(bm.enemy_units)
	var held: bool = bm._has_active_units(bm.player_units)
	var exchange_ratio: float = float(true_enemy_stats.pips_lost) / float(max(player_stats.pips_lost, 1))
	var verdict: String
	if held and exchange_ratio >= 1.5:
		verdict = "SUCCESSFUL DEFENSE"
	elif held:
		verdict = "PYRRHIC DEFENSE"
	elif exchange_ratio >= 2.0:
		verdict = "TACTICAL WITHDRAWAL"
	else:
		verdict = "DEFEAT"

	var player_surrendered := 0
	var player_ever_retreated := 0
	var player_mortar_lost := 0
	for u in bm.player_units:
		if u.state == Unit.State.SURRENDERED:
			player_surrendered += 1
		if u.state == Unit.State.RETREATING or u.state == Unit.State.WITHDRAWN:
			player_ever_retreated += 1
		if u.kind == Unit.Kind.MORTAR and u.state == Unit.State.DESTROYED:
			player_mortar_lost += 1
	var enemy_surrendered := 0
	var enemy_mortar_out_true := 0
	var enemy_mortar_out_estimated := 0
	for u in bm.enemy_units:
		if u.state == Unit.State.SURRENDERED:
			enemy_surrendered += 1
		if u.kind == Unit.Kind.MORTAR:
			if _mortar_out_true(u, held):
				enemy_mortar_out_true += 1
			if _mortar_out_estimated(u, held):
				enemy_mortar_out_estimated += 1

	# The displayed-AAR figure — exactly what _end_battle itself computes
	# as `enemy_stats` (battle_manager.gd) — feeds the estimated score.
	var enemy_stats_estimated: Dictionary = bm._compute_side_stats(bm.enemy_units, not held, true)
	var true_score: float = _score_battle(held, player_stats.killed, player_stats.captured, player_stats.heavily_wounded, player_stats.walking_wounded, player_mortar_lost, true_enemy_stats.killed, true_enemy_stats.captured, true_enemy_stats.heavily_wounded, true_enemy_stats.walking_wounded, enemy_mortar_out_true)
	var estimated_score: float = _score_battle(held, player_stats.killed, player_stats.captured, player_stats.heavily_wounded, player_stats.walking_wounded, player_mortar_lost, enemy_stats_estimated.killed, enemy_stats_estimated.captured, enemy_stats_estimated.heavily_wounded, enemy_stats_estimated.walking_wounded, enemy_mortar_out_estimated)

	var result: Dictionary = {
		"hung": hung,
		"ticks": ticks,
		"duration_scenario_s": bm.scenario_elapsed_time,
		"held": held,
		"verdict": verdict,
		"exchange_ratio": exchange_ratio,
		"player_pips_total": player_stats.pips_total,
		"player_pips_lost": player_stats.pips_lost,
		"player_killed": player_stats.killed,
		"enemy_pips_total": true_enemy_stats.pips_total,
		"enemy_pips_lost": true_enemy_stats.pips_lost,
		"enemy_killed": true_enemy_stats.killed,
		"player_surrendered": player_surrendered,
		"enemy_surrendered": enemy_surrendered,
		"player_ever_retreated": player_ever_retreated,
		"player_mortar_lost": player_mortar_lost,
		"enemy_mortar_out_true": enemy_mortar_out_true,
		"enemy_mortar_out_estimated": enemy_mortar_out_estimated,
		"true_score": true_score,
		"estimated_score": estimated_score,
		"target_picks": bm.target_picks,
		"resupply_spawned": bm.resupply_spawned,
		"resupply_destroyed_in_transit": bm.resupply_destroyed_in_transit,
		"flanking_units_assigned": bm.flanking_units_assigned_total,
		"flanking_arrivals": bm.flanking_arrivals,
		"retreat_avoidance_checks": bm.retreat_avoidance_checks,
		"retreat_avoidance_active": bm.retreat_avoidance_active,
		"mortar_hold_decisions": bm.mortar_hold_decisions,
		"mortar_hold_outcomes": bm.mortar_hold_outcomes,
		"cookoff_rolls": bm.cookoff_rolls,
		"cookoff_occurred": bm.cookoff_occurred,
		"wounded_evac_decisions": bm.wounded_evac_decisions,
		"wounded_abandoned": bm.wounded_abandoned,
		"wounded_carried": bm.wounded_carried,
		"drone_sorties_launched": bm.drone_sorties_launched,
		"drone_lost_to_battery": bm.drone_lost_to_battery,
		"drone_shot_down_by_enemy": bm.drone_shot_down_by_enemy,
	}
	bm.queue_free()
	return result


func _merge_count_dict(into: Dictionary, from: Dictionary) -> void:
	for k in from:
		into[k] = int(into.get(k, 0)) + int(from[k])


func _aggregate(trials: Array[Dictionary]) -> Dictionary:
	var n := trials.size()
	var agg: Dictionary = {
		"trials": n,
		"hung": 0,
		"verdict_counts": {},
		"verdict_score_stats": {}, # verdict -> {count, true_sum/min/max, est_sum/min/max}
		"true_score_sum": 0.0,
		"estimated_score_sum": 0.0,
		"held_count": 0,
		"exchange_ratio_sum": 0.0,
		"duration_sum": 0.0,
		"player_pips_lost_sum": 0,
		"player_pips_total_sum": 0,
		"enemy_pips_lost_sum": 0,
		"enemy_pips_total_sum": 0,
		"player_surrendered_sum": 0,
		"enemy_surrendered_sum": 0,
		"player_ever_retreated_sum": 0,
		"target_picks": {},
		"resupply_spawned": {},
		"resupply_destroyed_in_transit": {},
		"flanking_units_assigned_sum": 0,
		"flanking_arrivals_sum": 0,
		"retreat_avoidance_checks_sum": 0,
		"retreat_avoidance_active_sum": 0,
		"mortar_hold_decisions": {},
		"mortar_hold_outcomes": {},
		"cookoff_rolls_sum": 0,
		"cookoff_occurred_sum": 0,
		"wounded_evac_decisions": {},
		"wounded_abandoned": {},
		"wounded_carried": {},
		"drone_sorties_launched_sum": 0,
		"drone_lost_to_battery_sum": 0,
		"drone_shot_down_by_enemy_sum": 0,
	}
	for t in trials:
		if t.hung:
			agg.hung += 1
		agg.verdict_counts[t.verdict] = int(agg.verdict_counts.get(t.verdict, 0)) + 1
		agg.true_score_sum += t.true_score
		agg.estimated_score_sum += t.estimated_score
		if not agg.verdict_score_stats.has(t.verdict):
			agg.verdict_score_stats[t.verdict] = {"count": 0, "true_sum": 0.0, "true_min": INF, "true_max": -INF, "est_sum": 0.0, "est_min": INF, "est_max": -INF}
		var vs: Dictionary = agg.verdict_score_stats[t.verdict]
		vs.count += 1
		vs.true_sum += t.true_score
		vs.true_min = min(vs.true_min, t.true_score)
		vs.true_max = max(vs.true_max, t.true_score)
		vs.est_sum += t.estimated_score
		vs.est_min = min(vs.est_min, t.estimated_score)
		vs.est_max = max(vs.est_max, t.estimated_score)
		if t.held:
			agg.held_count += 1
		agg.exchange_ratio_sum += t.exchange_ratio
		agg.duration_sum += t.duration_scenario_s
		agg.player_pips_lost_sum += t.player_pips_lost
		agg.player_pips_total_sum += t.player_pips_total
		agg.enemy_pips_lost_sum += t.enemy_pips_lost
		agg.enemy_pips_total_sum += t.enemy_pips_total
		agg.player_surrendered_sum += t.player_surrendered
		agg.enemy_surrendered_sum += t.enemy_surrendered
		agg.player_ever_retreated_sum += t.player_ever_retreated
		_merge_count_dict(agg.target_picks, t.target_picks)
		_merge_count_dict(agg.resupply_spawned, t.resupply_spawned)
		_merge_count_dict(agg.resupply_destroyed_in_transit, t.resupply_destroyed_in_transit)
		agg.flanking_units_assigned_sum += t.flanking_units_assigned
		agg.flanking_arrivals_sum += t.flanking_arrivals
		agg.retreat_avoidance_checks_sum += t.retreat_avoidance_checks
		agg.retreat_avoidance_active_sum += t.retreat_avoidance_active
		_merge_count_dict(agg.mortar_hold_decisions, t.mortar_hold_decisions)
		_merge_count_dict(agg.mortar_hold_outcomes, t.mortar_hold_outcomes)
		agg.cookoff_rolls_sum += t.cookoff_rolls
		agg.cookoff_occurred_sum += t.cookoff_occurred
		_merge_count_dict(agg.wounded_evac_decisions, t.wounded_evac_decisions)
		_merge_count_dict(agg.wounded_abandoned, t.wounded_abandoned)
		_merge_count_dict(agg.wounded_carried, t.wounded_carried)
		agg.drone_sorties_launched_sum += t.drone_sorties_launched
		agg.drone_lost_to_battery_sum += t.drone_lost_to_battery
		agg.drone_shot_down_by_enemy_sum += t.drone_shot_down_by_enemy
	return agg


func _pct(numerator: float, denominator: float) -> String:
	if denominator <= 0.0:
		return "n/a"
	return "%.1f%%" % (100.0 * numerator / denominator)


func _md_for_mode(mode_name: String, agg: Dictionary) -> String:
	var n: float = float(agg.trials)
	var lines: PackedStringArray = []
	lines.append("## %s (%d trials)" % [mode_name, agg.trials])
	if agg.hung > 0:
		lines.append("**WARNING: %d/%d trials hit the %d-tick cap without ending.**" % [agg.hung, agg.trials, MAX_TICKS])
	lines.append("")
	lines.append("### Overall outcome")
	lines.append("- Held the position: %s" % _pct(agg.held_count, n))
	for v in agg.verdict_counts:
		lines.append("- Verdict `%s`: %s" % [v, _pct(agg.verdict_counts[v], n)])
	lines.append("- Average exchange ratio: %.2f" % (agg.exchange_ratio_sum / n))
	lines.append("- Average battle duration: %.1f tactical minutes" % (agg.duration_sum / n / 60.0))
	lines.append("- Average player casualties: %.1f / %.1f (%s)" % [agg.player_pips_lost_sum / n, agg.player_pips_total_sum / n, _pct(agg.player_pips_lost_sum, agg.player_pips_total_sum)])
	lines.append("- Average enemy casualties (true): %.1f / %.1f (%s)" % [agg.enemy_pips_lost_sum / n, agg.enemy_pips_total_sum / n, _pct(agg.enemy_pips_lost_sum, agg.enemy_pips_total_sum)])
	lines.append("")
	lines.append("### Battle-outcome score (see design doc for the fixed rubric)")
	lines.append("Two separate numbers per battle: the TRUE score (ground truth — what an actual decision-making framework should be evaluated against) and the ESTIMATED score (the player's own best-guess figures — what would actually justify a displayed verdict). These are expected to diverge sometimes; that's intentional, not an error.")
	lines.append("- Average true score: %.2f" % (agg.true_score_sum / n))
	lines.append("- Average estimated (best-guess) score: %.2f" % (agg.estimated_score_sum / n))
	lines.append("- By current verdict label (still held+exchange_ratio-based, NOT yet derived from this score):")
	for v in agg.verdict_score_stats:
		var vs: Dictionary = agg.verdict_score_stats[v]
		lines.append("  - `%s` (%d battles): true score avg %.1f (range %.1f to %.1f), estimated score avg %.1f (range %.1f to %.1f)" % [v, vs.count, vs.true_sum / vs.count, vs.true_min, vs.true_max, vs.est_sum / vs.count, vs.est_min, vs.est_max])
	lines.append("")
	lines.append("### Surrender (expected to remain unchanged by the rewrite — see design doc)")
	lines.append("- Player squads surrendered: %.2f per battle on average" % (agg.player_surrendered_sum / n))
	lines.append("- Enemy squads surrendered: %.2f per battle on average" % (agg.enemy_surrendered_sum / n))
	lines.append("")
	lines.append("### Retreat")
	lines.append("- Player units that ever retreated/withdrew: %.2f per battle" % (agg.player_ever_retreated_sum / n))
	lines.append("- Threat-avoidance steering active (of all checks made): %s" % _pct(agg.retreat_avoidance_active_sum, agg.retreat_avoidance_checks_sum))
	lines.append("")
	lines.append("### Targeting (does a squad ever fire on an enemy mortar?)")
	var squad_to_mortar_player: int = int(agg.target_picks.get("player:SQUAD->MORTAR", 0))
	var squad_to_mortar_enemy: int = int(agg.target_picks.get("enemy:SQUAD->MORTAR", 0))
	lines.append("- Player squad-on-enemy-mortar shots: %d total (%.3f per battle)" % [squad_to_mortar_player, squad_to_mortar_player / n])
	lines.append("- Enemy squad-on-player-mortar shots: %d total (%.3f per battle)" % [squad_to_mortar_enemy, squad_to_mortar_enemy / n])
	lines.append("- Full targeting distribution this run (attacker_team:attacker_kind->target_kind -> count):")
	var keys: Array = agg.target_picks.keys()
	keys.sort()
	for k in keys:
		lines.append("  - `%s`: %d" % [k, agg.target_picks[k]])
	lines.append("")
	lines.append("### Mortar crew: hold position vs. abandon the gun when hit")
	for side in ["player", "enemy"]:
		var decisions: int = int(agg.mortar_hold_decisions.get(side, 0))
		var holds: int = int(agg.mortar_hold_outcomes.get(side, 0))
		lines.append("- %s: held %s of %d hit-decisions" % [side.capitalize(), _pct(holds, decisions), decisions])
	lines.append("")
	lines.append("### Mortar ammo cook-off")
	lines.append("- Occurred in %s of %d rolls" % [_pct(agg.cookoff_occurred_sum, agg.cookoff_rolls_sum), agg.cookoff_rolls_sum])
	lines.append("")
	lines.append("### Wounded evacuation (enemy alone can choose to abandon)")
	for side in ["player", "enemy"]:
		var decisions: int = int(agg.wounded_evac_decisions.get(side, 0))
		var abandoned: int = int(agg.wounded_abandoned.get(side, 0))
		var carried: int = int(agg.wounded_carried.get(side, 0))
		lines.append("- %s: %d decisions, carried %s, abandoned %s" % [side.capitalize(), decisions, _pct(carried, decisions), _pct(abandoned, decisions)])
	lines.append("")
	lines.append("### Mortar resupply")
	for side in ["player", "enemy"]:
		var spawned: int = int(agg.resupply_spawned.get(side, 0))
		var destroyed: int = int(agg.resupply_destroyed_in_transit.get(side, 0))
		lines.append("- %s: %d runs spawned, %s destroyed in transit, %s delivered-or-aborted (not distinguished further)" % [side.capitalize(), spawned, _pct(destroyed, spawned), _pct(spawned - destroyed, spawned)])
	lines.append("")
	lines.append("### Enemy flanking maneuver")
	lines.append("- Squads ever assigned the flanking route: %.2f per battle" % (agg.flanking_units_assigned_sum / n))
	lines.append("- Of those, actually reached the flank waypoint and pivoted: %s" % _pct(agg.flanking_arrivals_sum, agg.flanking_units_assigned_sum))
	if mode_name == "DRONE_TEAM":
		lines.append("")
		lines.append("### Drone fleet")
		lines.append("- Sorties launched per battle: %.2f" % (agg.drone_sorties_launched_sum / n))
		lines.append("- Lost to battery exhaustion per battle: %.2f" % (agg.drone_lost_to_battery_sum / n))
		lines.append("- Shot down by the enemy per battle: %.2f" % (agg.drone_shot_down_by_enemy_sum / n))
	lines.append("")
	return "\n".join(lines)


func _initialize() -> void:
	var all_results: Dictionary = {}
	var timestamp: String = Time.get_datetime_string_from_system(true)

	for mode in [GameConfig.ReconMode.SPOTTER, GameConfig.ReconMode.DRONE_TEAM]:
		var mode_name: String = "SPOTTER" if mode == GameConfig.ReconMode.SPOTTER else "DRONE_TEAM"
		print("Running %d trials for %s..." % [TRIALS_PER_MODE, mode_name])
		var trials: Array[Dictionary] = []
		for i in TRIALS_PER_MODE:
			trials.append(_run_one_trial(mode))
			if (i + 1) % 10 == 0:
				print("  %s: %d/%d done" % [mode_name, i + 1, TRIALS_PER_MODE])
		all_results[mode_name] = _aggregate(trials)

	var json_out: Dictionary = {
		"generated_at": timestamp,
		"trials_per_mode": TRIALS_PER_MODE,
		"git_tag": "before-tactical-rewrite",
		"results": all_results,
	}
	var json_file := FileAccess.open(OUTPUT_JSON, FileAccess.WRITE)
	json_file.store_string(JSON.stringify(json_out, "  "))
	json_file.close()

	var md: PackedStringArray = []
	md.append("# Pre-Rewrite Doctrine Baseline")
	md.append("")
	md.append("Generated %s, %d trials per recon mode, tagged `before-tactical-rewrite`." % [timestamp, TRIALS_PER_MODE])
	md.append("")
	md.append("Captured immediately before the planned tactical-decisionmaking rewrite (see the design doc's own revision log) — a baseline for COMPARISON, not a pass/fail gate. The rewrite is explicitly meant to change some of these numbers by grounding decisions in general principles (\"win the battle,\" \"keep our people alive,\" \"cause enemy casualties\") instead of individually-tuned thresholds; a changed number here isn't automatically a regression. Re-run `scripts/tests/characterize_doctrine.gd` after the rewrite and compare by eye.")
	md.append("")
	md.append("Surrender is called out separately in each section below because it's expected to stay outside the new principled framework entirely — once a squad is surrendering, it has already put its own survival above winning, so there's no \"win the battle\" principle left to derive that decision from.")
	md.append("")
	for mode_name in all_results:
		md.append(_md_for_mode(mode_name, all_results[mode_name]))
	var md_file := FileAccess.open(OUTPUT_MD, FileAccess.WRITE)
	md_file.store_string("\n".join(md))
	md_file.close()

	print("Wrote %s and %s" % [OUTPUT_JSON, OUTPUT_MD])
	quit()
