extends Node2D
class_name BattleManager

## Runs one battle: spawns units per doctrine, marches the enemy down the
## road, resolves spotting and fire each tick, and produces an after-action
## report once both sides are done fighting. Commander profiles configure
## target preferences for both sides; movement retains its existing rules.
##
## No routine per-shot fire log (see CombatLog) — the log only records
## moments that change the picture. Fire IS shown visually, though — every
## shot leaves a brief tracer (see _fire_flashes / _draw), color-coded by
## side, so it is always clear when and where the enemy is shooting. A
## mortar round's actual landing gets its own, longer-lived burst (see
## _mortar_impacts / _draw) — the tracer already shows the shot being
## fired, but a shell's real flight time (GameConfig.MORTAR_FLIGHT_TIME)
## means the round lands well after that tracer has already faded, so a
## separate visual is needed at the real moment of impact.

signal battle_ended(report_text: String)
## Emitted by handle_click when the player clicks a friendly unit that can take
## orders - BattleScreen opens the orders card for it.
signal unit_selected(unit: Unit)

## Printed at the top of every after-action report.
const AFTER_ACTION_REPORT_DISCLAIMER := "This report details higher command's assessment of enemy casualties. It may or may not match reality."

const FLASH_DURATION: float = 0.3
## How long a mortar-impact burst stays on screen — real elapsed seconds,
## same convention as FLASH_DURATION but deliberately longer: a shell
## landing is a real, arresting moment worth lingering on, not a quick
## tracer blink.
const IMPACT_EFFECT_DURATION: float = 1.0
const CommanderProfile = preload("res://scripts/commander_profile.gd")
const DecisionRecorder = preload("res://scripts/decision_recorder.gd")
const UnitDoctrine = preload("res://scripts/unit_doctrine.gd")
const RiskForecast = preload("res://scripts/risk_forecast.gd")
const UnitCombatStats = preload("res://scripts/unit_combat_stats.gd")
const BattleScore = preload("res://scripts/battle_score.gd")

## One of six real recordings plays at random for every mortar round fired
## (see _play_mortar_fire_sound) — a single fixed sound would make a burst
## of 3-4 rounds sound like the exact same shot copy-pasted. Not positional
## (every AudioStreamPlayer here is plain, non-2D) and the same six clips
## play for both sides — distance-based attenuation is still a later step,
## not part of this pass. The six files on disk are already well below the
## quietest of the six original source recordings (see assets/audio/
## mortar_fire's own sourcing note) — MORTAR_FIRE_SOUND_VOLUME_DB below is a
## SEPARATE, further mix-level cut on top of that, applied at playback
## rather than re-baked into the files, specifically so it's a one-constant
## retune (direct user feedback: "I do hear it. But please make it
## quieter.") rather than a whole re-export every time the in-game mix
## needs adjusting.
const MORTAR_FIRE_SOUND_VOLUME_DB: float = -10.0
## Direct user request: "Let's have the enemy mortar be quieter than the
## friendly ones." A further cut on top of MORTAR_FIRE_SOUND_VOLUME_DB,
## applied only when the firing mortar is Unit.Team.ENEMY — see
## _play_mortar_fire_sound.
const ENEMY_MORTAR_FIRE_SOUND_EXTRA_ATTENUATION_DB: float = -10.0
const MORTAR_FIRE_SOUNDS: Array[AudioStream] = [
	preload("res://assets/audio/mortar_fire/mortar_shot_1.wav"),
	preload("res://assets/audio/mortar_fire/mortar_shot_2.wav"),
	preload("res://assets/audio/mortar_fire/mortar_shot_3.wav"),
	preload("res://assets/audio/mortar_fire/mortar_shot_4.wav"),
	preload("res://assets/audio/mortar_fire/mortar_shot_5.wav"),
	preload("res://assets/audio/mortar_fire/mortar_shot_6.wav"),
]
## A real burst fires every one of its rounds within the same tick (see
## _tick_fire's own doc comment — "quick succession" at this timescale means
## literally the same frame), and up to ENEMY_MORTAR_COUNT_MAX separate
## mortars can each be mid-burst at once — a single AudioStreamPlayer would
## cut its own previous shot off every time a second one landed in the same
## tick. A small round-robin pool plays overlapping shots as overlapping
## sounds instead, the ordinary fix for exactly this (a burst of gunfire,
## not one shot at a time). Sized comfortably above the realistic worst case
## (MORTAR_BURST_MAX_SHOTS rounds x a few mortars firing the same tick), not
## the theoretical maximum every mortar on the map bursting at once.
const MORTAR_FIRE_SOUND_POOL_SIZE: int = 12
var _mortar_fire_sound_players: Array[AudioStreamPlayer] = []
var _mortar_fire_sound_pool_index: int = 0
## The quiet sound of squads firing (see GunfireAmbience): one recording, told of every direct-fire shot.
var _gunfire_ambience: GunfireAmbience = null

## A bounded, JSON-native trace of every _play_mortar_fire_sound call — direct
## user request after a real, inconsistent report ("sometimes I hear the
## enemy mortar and sometimes I don't... it may have been because I increased
## the speed during the retreat" — then, once told fast-forward and firing
## are mutually exclusive by construction: "it was not just fast forward.
## Try to give yourself any relevant visibility"). Nothing in the code read
## so far explains an actual missed shot, so this exists to catch whatever
## static reading can't: the exact real-world (Time.get_ticks_msec, not
## scenario time) spacing between calls, whether a pool player was already
## mid-clip when reused (a real, possible cause of an inaudible cut-off —
## see MORTAR_FIRE_SOUND_POOL_SIZE's own doc comment on why bursts need the
## pool at all), the tactical clock's pace and contact status at that exact
## moment (to verify, not just assume, the fast-forward/firing exclusion
## argued from _pick_target/is_targetable — an assumption is not the same as
## a verified fact), and whether playback was skipped outright (the
## _play_mortar_fire_sound's own is_inside_tree() guard, added for the
## synchronous characterize_doctrine.gd harness — worth ruling in or out
## directly rather than assumed impossible in live play). See mortar_audio_
## debug_snapshot(). Capped generously above a realistic single battle's
## total shot count (see MORTAR_DEBUG_HISTORY_LIMIT's own doc comment on why
## a fixed entry count, not tactical time, is the right cap here too).
var _mortar_audio_log: Array = []
const MORTAR_AUDIO_LOG_LIMIT: int = 300

var unit_type_doctrines := {Unit.Team.PLAYER: UnitDoctrine.sanitize({}), Unit.Team.ENEMY: UnitDoctrine.sanitize({})}
var unit_combat_stats = UnitCombatStats.new()
var _risk_holds: Dictionary = {}
var _unit_name_counts: Dictionary = {}
## Next discovery number to hand out, per enemy Unit.Kind — see
## _assign_discovery_number's own doc comment.
var _enemy_discovery_counts: Dictionary = {}
var commander_profiles: Dictionary = {
	Unit.Team.PLAYER: CommanderProfile.preset("baseline"),
	Unit.Team.ENEMY: CommanderProfile.preset("baseline"),
}
var decisions = DecisionRecorder.new()
var battle_seed: int = -1

func unit_doctrine_for(unit: Unit) -> Dictionary:
	return unit_type_doctrines[unit.team][UnitDoctrine.type_key(unit.kind)]


func _type_target_score(unit: Unit, target: Unit) -> float:
	match unit_doctrine_for(unit).targeting:
		"nearest": return 1.0 / (1.0 + unit.global_position.distance_to(target.global_position))
		"weakest": return 1.0 / (1.0 + target.pips)
		"threat": return 0.01 + _target_danger_to_force(unit, target)
		"mortars": return 100.0 if target.kind == Unit.Kind.MORTAR and target.state == Unit.State.ACTIVE else 1.0
		"best_chance":
			if unit.kind == Unit.Kind.DRONE:
				var distance: float = unit.global_position.distance_to(target.global_position)
				var visible_path := GameConfig.has_aerial_los(unit.global_position, target.global_position) and not CombatResolver.hidden_from_drone(unit, target)
				var concealment: float = GameConfig.DRONE_CONCEALMENT_MULTIPLIER[target.terrain_type()]
				return maxf(0.0, 1.0 - distance / GameConfig.DRONE_DETECTION_RANGE) * concealment if visible_path else 0.0
			return CombatResolver.hit_probability(unit, target, _drone_directing_multiplier(unit))
	return 1.0


func _forecast_target(unit: Unit) -> Unit:
	# Preview only: no _pick_target, randomness, or decision mutation.
	var opposing: Array[Unit] = enemy_units if unit.team == Unit.Team.PLAYER else player_units
	var best: Unit = null
	var best_score := -INF
	for candidate in opposing:
		if not candidate.is_targetable(): continue
		if unit.kind == Unit.Kind.SQUAD:
			# See _pick_target's own doc comment — neither weapon can
			# realistically engage a drone at all.
			if candidate.kind == Unit.Kind.DRONE: continue
			if unit.global_position.distance_to(candidate.global_position) > GameConfig.SQUAD_ENGAGEMENT_RANGE: continue
			if not GameConfig.has_direct_los(unit.global_position, candidate.global_position): continue
		elif unit.kind == Unit.Kind.MORTAR:
			if candidate.kind == Unit.Kind.DRONE: continue
			if unit.global_position.distance_to(candidate.global_position) > GameConfig.mortar_max_range(unit.team): continue
		elif unit.kind != Unit.Kind.DRONE:
			continue
		var score := _enemy_target_value(unit, candidate)
		if score > best_score:
			best = candidate
			best_score = score
	return best


func _risk_forecast(unit: Unit, target: Unit, point: Vector2) -> Dictionary:
	var threats: Array[Dictionary] = []
	var direct_fire_positions: Array[Vector2] = [] # where the known squad threats would be firing from, for the crossfire arc
	var opposing: Array[Unit] = enemy_units if unit.team == Unit.Team.PLAYER else player_units
	for enemy in opposing:
		if enemy.kind not in [Unit.Kind.SQUAD, Unit.Kind.MORTAR]: continue
		var known_position: Vector2
		var confidence := 1.0
		if enemy.is_visible:
			if enemy.state not in [Unit.State.ACTIVE, Unit.State.RETREATING]: continue
			known_position = enemy.global_position
		else:
			var lead: Dictionary = _last_detected_mortar_fire.get(enemy, {})
			if enemy.kind != Unit.Kind.MORTAR or lead.is_empty(): continue
			var age: float = scenario_elapsed_time - lead.time
			if age > GameConfig.MORTAR_FIRE_DETECTION_EXPIRY: continue
			known_position = lead.position
			confidence = clampf(1.0 - age / GameConfig.MORTAR_FIRE_DETECTION_EXPIRY, 0.0, 1.0)
		var max_range: float = GameConfig.mortar_max_range(enemy.team) if enemy.kind == Unit.Kind.MORTAR else GameConfig.SQUAD_ENGAGEMENT_RANGE
		if point.distance_to(known_position) > max_range: continue
		if enemy.kind == Unit.Kind.SQUAD and not GameConfig.has_direct_los(known_position, point): continue
		if enemy.kind == Unit.Kind.MORTAR and GameConfig.is_building_at(known_position): continue
		var probability := CombatResolver.hit_probability(enemy, unit, false, point, known_position) * confidence
		threats.append({"chance": probability, "shots": RiskForecast.shot_count(enemy, RiskForecast.HORIZON_SECONDS, GameConfig.TIME_SCALE_NORMAL, false), "mortar": enemy.kind == Unit.Kind.MORTAR})
		if enemy.kind != Unit.Kind.MORTAR:
			direct_fire_positions.append(known_position)
	# Crossfire (direct user design, see CombatResolver.safe_arc_deg/crossfire_multiplier): the more of the circle
	# around `point` the known direct-fire threats cover, the more dangerous each of their shots is. Judged at
	# the point being assessed — so a unit weighing a move sees the crossfire of its DESTINATION — from the same
	# known threats the forecast already counts (nothing hidden is used), and mortar threats are outside it,
	# exactly as in the real fire path (BattleManager._resolve_fire_and_check_bunching).
	var safe_arc: float = CombatResolver.safe_arc_deg(point, direct_fire_positions)
	var crossfire: float = CombatResolver.crossfire_multiplier(safe_arc)
	if crossfire > 1.0:
		for threat in threats:
			if not threat.mortar:
				threat.chance = minf(float(threat.chance) * crossfire, 1.0)
	# Incoming fire is already announced to the target's side. The source
	# and other hidden artillery are not exposed by this calculation.
	for strike in _pending_counter_battery:
		if strike.target == unit and strike.impact_time - scenario_elapsed_time <= RiskForecast.HORIZON_SECONDS:
			var chance := clampf(1.0 - point.distance_to(strike.impact_position) / GameConfig.COUNTER_BATTERY_BLAST_RADIUS, 0.0, 1.0)
			threats.append({"chance": chance, "shots": 1, "mortar": true})
	var forecast := RiskForecast.damage_distribution(unit, threats)
	forecast["horizon_seconds"] = RiskForecast.HORIZON_SECONDS
	forecast["known_threats"] = threats.size()
	forecast["safe_arc_deg"] = safe_arc
	forecast["crossfire_multiplier"] = crossfire
	forecast["goal_probability"] = -1.0
	forecast["goal"] = "Continue the assigned support or movement task (success not forecast)."
	if target != null and unit.kind in [Unit.Kind.SQUAD, Unit.Kind.MORTAR]:
		var shots := RiskForecast.shot_count(unit, RiskForecast.HORIZON_SECONDS, GameConfig.TIME_SCALE_NORMAL, true)
		var hit := CombatResolver.hit_probability(unit, target, _drone_directing_multiplier(unit))
		forecast.goal_probability = 1.0 - pow(1.0 - hit, shots)
		forecast.goal = "Land at least one damaging hit on %s." % target.display_name()
	forecast["assumptions"] = "Next 3 tactical minutes at fixed positions/current posture. Known threats assumed able to focus fire; unseen threats, future movement, morale, splash and cook-offs are not forecast. This estimates elimination by damage, not everyone's death."
	return forecast


func _record_risk(unit: Unit, forecast: Dictionary, accepted: bool) -> void:
	var policy: Dictionary = unit_doctrine_for(unit)
	decisions.record(unit, scenario_elapsed_time, "Self-risk assessment", {
		"choice": "Accept task risk" if accepted else "Reduce exposure / withhold fire",
		"reason": "%s: %s" % [UnitDoctrine.RISK_LABELS[UnitDoctrine.RISK_IDS.find(policy.risk)], forecast.goal],
		"forecast": forecast, "limits": UnitDoctrine.risk_limits(policy.risk)})


func _update_ground_risk_orders() -> void:
	for unit in player_units + enemy_units:
		if unit.state != Unit.State.ACTIVE or unit.kind == Unit.Kind.DRONE: continue
		var risk: String = unit_doctrine_for(unit).risk
		if risk == "inherit": continue
		if _fall_back_orders.has(unit): continue # the commander's order outranks the unit's own risk policy
		if _risk_holds.has(unit) and unit.has_move_target:
			continue # Finish the chosen safety move before reconsidering.
		_risk_holds.erase(unit)
		var target := _forecast_target(unit)
		var forecast := _risk_forecast(unit, target, unit.global_position)
		if unit.has_move_target:
			# Check both the destination and a point en route; no omniscient
			# route search. Use the worst sampled exposure, not their product.
			for point in [unit.global_position.lerp(unit.move_target, 0.5), unit.move_target]:
				var route := _risk_forecast(unit, target, point)
				forecast.loss_probability = maxf(forecast.loss_probability, route.loss_probability)
				forecast.hit_probability = maxf(forecast.hit_probability, route.hit_probability)
		var accepted := UnitDoctrine.accepts(risk, forecast)
		_record_risk(unit, forecast, accepted)
		if accepted: continue
		_relocate_for_risk(unit)


## The places worth considering to be safer than where `unit` stands: where it
## stands now, the nearest point out of sight of every known enemy (the ring search
## in GameConfig.nearest_hidden_point — see its own doc comment on danger_range: a
## mortar crew's own 750m overrun standoff is far tighter than any other unit
## kind's relevant "don't walk toward a known threat" scale, so everyone else uses
## SQUAD_DANGER_RANGE, 1200m, the same mortar-vs-everyone-else split
## _retreat_avoidance_offset's own range_m already uses), and the nearest cover.
## Shared by _relocate_for_risk (a unit whose own risk policy rejected its exposure)
## and _fall_back_destination (the commander's fall-back order), so the two can
## never disagree about what a candidate is.
func _shelter_candidates(unit: Unit, known: Array[Vector2]) -> Array[Vector2]:
	return [unit.global_position, _hidden_point_for(unit, known), _cover_point_for(unit, known, _ally_positions_for(unit))]


## Whether this unit's relocation searches must also keep out of the populated-place region (GameConfig.mortar_exclusion_rects):
## the player's mortar only. Direct user request: "Each map needs a region where the Ukrainian mortar cannot go."
func _keeps_clear_of_populated(unit: Unit) -> bool:
	return unit.kind == Unit.Kind.MORTAR and unit.team == Unit.Team.PLAYER


## GameConfig.nearest_hidden_point as _relocate_for_risk has always called it (its
## pick among the best candidates is deliberately randomised, so two calls can differ).
func _hidden_point_for(unit: Unit, known: Array[Vector2]) -> Vector2:
	var danger_range: float = GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE if unit.kind == Unit.Kind.MORTAR else GameConfig.SQUAD_DANGER_RANGE
	return GameConfig.nearest_hidden_point(unit.global_position, known, unit.kind == Unit.Kind.MORTAR, false, [], Vector2.INF, INF, 0.0, [], [], Vector2.ZERO, Vector2.INF, danger_range, _keeps_clear_of_populated(unit))


## GameConfig.nearest_cover_point, skipping any cover zone that contains one of `avoid`.
func _cover_point_for(unit: Unit, known: Array[Vector2], avoid: Array[Vector2]) -> Vector2:
	return GameConfig.nearest_cover_point(unit.global_position, 0.0, unit.kind == Unit.Kind.MORTAR, avoid, known, [], [], Vector2.ZERO, Vector2.INF, Vector2.INF, _keeps_clear_of_populated(unit))


func _relocate_for_risk(unit: Unit) -> void:
	_risk_holds[unit] = true
	unit.last_order_reason = "Self-risk policy rejected the current exposure; moving to safer cover or withholding fire."
	var known := _known_enemy_positions(unit.team)
	var choices: Array[Vector2] = _shelter_candidates(unit, known)
	var best: Vector2 = unit.global_position
	var best_risk := INF
	for point in choices:
		if unit.kind == Unit.Kind.MORTAR and GameConfig.mortar_barred_at(point, unit.team): continue
		if _advances_past_fall_back_line(unit, point): continue
		var alternative := _risk_forecast(unit, null, point)
		var cost: float = alternative.loss_probability + alternative.hit_probability
		if cost < best_risk:
			best = point
			best_risk = cost
	unit.move_queue.clear()
	if unit.kind == Unit.Kind.MORTAR:
		_clear_mortar_move(unit)
		if best.distance_to(unit.global_position) > Unit.MOVE_ARRIVE_RADIUS:
			_issue_mortar_move(unit, best, GameConfig.MORTAR_RELOCATE_SPEED, "risk")
	else:
		unit.has_move_target = best.distance_to(unit.global_position) > Unit.MOVE_ARRIVE_RADIUS
		unit.move_target = best
		unit.activity = Unit.Activity.MOVING if unit.has_move_target else Unit.Activity.STATIONARY
		unit.move_speed = GameConfig.REPOSITION_SPEED
		unit.movement_predictable = false


func _drone_risk_accepts(drone: Unit, destination: Vector2) -> bool:
	var policy: Dictionary = unit_doctrine_for(drone)
	if policy.risk == "inherit": return true
	var forecast := _risk_forecast(drone, null, destination)
	var battery_seconds: float = maxf(drone.drone_battery_charge - GameConfig.DRONE_LANDING_CHARGE_COST, 0.0) * GameConfig.DRONE_FULL_CHARGE_FLIGHT_TIME
	var outbound: float = drone.global_position.distance_to(destination) / GameConfig.DRONE_CRUISE_SPEED
	var homeward: float = destination.distance_to(drone_team.global_position) / GameConfig.DRONE_CRUISE_SPEED
	forecast.goal = "Reach the observation point and provide 30 seconds of coverage."
	forecast.goal_probability = (1.0 - forecast.loss_probability) if battery_seconds >= outbound + 30.0 else 0.0
	if battery_seconds < outbound + 30.0 + homeward:
		forecast.loss_probability = 1.0
	forecast["battery_seconds"] = battery_seconds
	forecast["task_and_return_seconds"] = outbound + 30.0 + homeward
	var accepted := UnitDoctrine.accepts(policy.risk, forecast)
	_record_risk(drone, forecast, accepted)
	return accepted


func profile_for(team: Unit.Team) -> Dictionary:
	return commander_profiles[team]

func _profile_weight(team: Unit.Team, axis: String) -> float:
	return float(profile_for(team)[axis])

# These components are game heuristics, not predicted casualties or win odds.
func target_score_components(unit: Unit, target: Unit) -> Dictionary:
	if unit_doctrine_for(unit).targeting != "inherit":
		return {unit_doctrine_for(unit).targeting: _type_target_score(unit, target)}
	var profile: Dictionary = profile_for(unit.team)
	if profile.id == "baseline":
		return {"original target value": _enemy_target_value(unit, target)}
	return {
		"pressure": 10.0 * float(target.pips) / maxf(target.max_pips, 1.0) * profile.pressure,
		"protect allies": _target_danger_to_force(unit, target) * profile.protection,
		"counter mortar": 10.0 * profile.counter_mortar if target.kind == Unit.Kind.MORTAR and target.state == Unit.State.ACTIVE else 0.0,
	}

func _record_target_choice(unit: Unit, candidates: Array[Unit], chosen: Unit, reason: String, evidence: Dictionary = {}) -> Unit:
	# Validate the actual selection too: a weighted policy may choose a
	# different target from the opportunity used by the movement forecast.
	if chosen != null and unit.state == Unit.State.ACTIVE and unit_doctrine_for(unit).risk != "inherit":
		var forecast := _risk_forecast(unit, chosen, unit.global_position)
		var accepted := UnitDoctrine.accepts(unit_doctrine_for(unit).risk, forecast)
		_record_risk(unit, forecast, accepted)
		if not accepted:
			chosen = null
			reason = "Self-risk policy rejected this firing opportunity after target selection."
			evidence = evidence.merged({"risk_forecast": forecast})
			_relocate_for_risk(unit)
	var rows: Array[Dictionary] = []
	var opposing: Array[Unit] = enemy_units if unit.team == Unit.Team.PLAYER else player_units
	for target in opposing:
		# Never include hidden targets in a unit's explanation.
		if not target.is_visible:
			continue
		var eligible := candidates.has(target)
		var rejection := ""
		if not target.is_targetable():
			rejection = "No longer targetable"
		elif not eligible:
			var limit: float = GameConfig.SQUAD_ENGAGEMENT_RANGE if unit.kind == Unit.Kind.SQUAD else GameConfig.mortar_max_range(unit.team)
			rejection = "Out of range" if unit.global_position.distance_to(target.global_position) > limit else "Line of sight blocked"
		rows.append({"target": decisions.label_for(target), "eligible": eligible,
			"rejection": rejection, "score": _enemy_target_value(unit, target) if eligible else 0.0,
			"components": target_score_components(unit, target) if eligible else {}})
	var data := {"choice": decisions.label_for(chosen) if chosen != null else "No target selected",
		"reason": reason, "candidates": rows, "evidence": evidence,
		"profile": profile_for(unit.team).duplicate(true), "unit_doctrine": unit_doctrine_for(unit).duplicate(true)}
	decisions.record(unit, scenario_elapsed_time, "Target evaluation", data)
	return chosen


func _record_shot(unit: Unit, target: Unit) -> void:
	unit_combat_stats.register(unit)
	# A deliberate, targeted shot at a visible/engageable enemy mortar is
	# just as much counter-battery fire as the separate reactive "blind
	# return fire at a detected muzzle flash" mechanic below
	# (_resolve_pending_counter_battery) — both are one indirect-fire
	# weapon firing on another, which is exactly what "counter-battery"
	# means. Only counts when the FIRING unit is also a mortar: a squad's
	# rifle fire happening to land on a mortar crew in its engagement
	# range is ordinary contact fire, not a mortar duel.
	var is_counter_battery: bool = unit.kind == Unit.Kind.MORTAR and target.kind == Unit.Kind.MORTAR
	unit_combat_stats.shot(unit, is_counter_battery)
	decisions.record(unit, scenario_elapsed_time, "Shot fired", {
		"choice": decisions.label_for(target), "reason": "Firing gates passed; round fired.",
		"sequence": _history_fire_events.size(),
		"target_evaluation": decisions.latest.get("%d:Target evaluation" % unit.get_instance_id(), {}).duplicate(true)})

func _record_unit_decisions() -> void:
	for unit in player_units + enemy_units:
		var choice: String = Unit.State.keys()[unit.state]
		var reason := "No movement order; observing or waiting for a firing opportunity."
		if unit.has_move_target:
			choice += " / moving"
			reason = unit.last_order_reason if not unit.last_order_reason.is_empty() else "Movement order in progress; this movement path does not yet record its cause."
		if unit.state != Unit.State.ACTIVE:
			reason = "Unit is %s; current state takes precedence over its last active decision." % Unit.State.keys()[unit.state].to_lower()
			if unit.state == Unit.State.RETREATING:
				reason += " " + unit.last_order_reason
		elif unit.kind == Unit.Kind.MORTAR and _mortar_reasoning.has(unit):
			choice = _mortar_reasoning[unit].tier
			reason = _mortar_reasoning[unit].detail
		elif unit.kind == Unit.Kind.DRONE and unit == active_drone:
			choice = _drone_pilot_reasoning.get("tier", "Reconnaissance")
			reason = _drone_pilot_reasoning.get("detail", "No pilot decision recorded yet.")
		decisions.record(unit, scenario_elapsed_time, "Orders / state", {
			"choice": choice, "reason": reason,
			"destination": _pos_to_debug_dict(unit.move_target) if unit.has_move_target else {},
			"position": _pos_to_debug_dict(unit.global_position),
			"pips": unit.pips, "max_pips": unit.max_pips,
			"profile": profile_for(unit.team).duplicate(true),
			"unit_doctrine": unit_doctrine_for(unit).duplicate(true),
			"rounds": unit.mortar_rounds_remaining if unit.kind == Unit.Kind.MORTAR else -1,
			"reload_remaining": maxf(unit.fire_timer, 0.0),
			"retreat_threshold": unit.retreat_threshold if unit.kind == Unit.Kind.SQUAD else -1.0})


# If nobody has fired AND nobody is trying to move for this long, the battle
# has genuinely stalled (e.g. both mortars gone, everyone dug into cover
# with no LOS to anyone) — end it rather than running out the full clock.
const STAGNATION_TIMEOUT: float = 15.0

# How often (in tactical seconds) a post-battle history snapshot is
# recorded — see _record_history_snapshot. Fine enough for smooth-feeling
# scrubbing (a battle running the usual ~150-170 tactical minutes records
# on the order of 2000 frames) without being wasteful — each frame is a
# handful of small values per unit, trivial even at that count.
const HISTORY_SNAPSHOT_INTERVAL_S: float = 5.0

var player_units: Array[Unit] = []
var enemy_units: Array[Unit] = []
var combat_log: CombatLog
# Actual, real (engine) elapsed seconds since the battle started — drives
# only visual/animation timing (fire-tracer fade) and the stagnation
# safeguard, both of which are about what the PLAYER is experiencing, not
# the tactical timeline. See scenario_elapsed_time for that.
var elapsed_time: float = 0.0
# The in-fiction tactical clock — what movement speed, mortar flight time,
# and counter-battery intervals are all measured against. Advances faster
# than elapsed_time by whichever GameConfig.TIME_SCALE_* tier currently
# applies (see _current_time_scale) each tick — see _process. Starts at
# 0600 (see clock_string()).
var scenario_elapsed_time: float = 0.0
var battle_over: bool = false
## Set the instant _check_battle_end's stalemate branch is the one that
## actually ended the battle (as opposed to one side being wiped out, or the
## hard time limit) — see _end_battle's own use of this. Read directly by
## characterize_doctrine.gd too, which recomputes the verdict independently
## from the same public accessors rather than parsing the AAR text.
var _ended_by_stalemate: bool = false
## Set for the one tick a unit (either side) actually dies, cleared at the top of every _process — see
## _on_any_unit_state_changed's own doc comment for why _end_battle reads it.
var _kill_happened_this_tick: bool = false
## The finished battle's score, built once by _end_battle (empty until then):
## {verdict, held, stalemate, rubric_version, score, inputs}. `score` is the
## TRUE-results score the player is shown (user: "the score can go based off
## of the true results"); `inputs` are the plain counts it was computed from —
## exactly what BattleScoreLog stores, so a battle can be re-scored if the
## rubric is ever tuned. See BattleScore. BattleManager only COMPUTES this;
## recording it to disk is BattleReport's job (this class runs in every test and
## must never write history).
var battle_result: Dictionary = {}
# User-requested pause (see toggle_pause) — freezes the entire simulation
# exactly where it stands: _process returns immediately, before either
# clock advances or any tick logic runs, so nothing (movement, fire,
# resupply, drone flight, the battle-over check itself) progresses at all
# until resumed. Nothing outside BattleManager's own _process depends on
# per-frame simulation time (see Unit — it has no _process of its own,
# everything is driven centrally from here), so this one early return is
# sufficient to pause the whole battle.
var is_paused: bool = false
var _fire_flashes: Array[Dictionary] = []
## Real HE impacts — a mortar shell actually landing, whether it hit
## anything or not, distinct from _fire_flashes' own tracer-at-firing-
## time visual. {"position": Vector2, "time": elapsed_time (real seconds,
## same clock _fire_flashes/_prune_fire_flashes already use)}. See
## IMPACT_EFFECT_DURATION's own doc comment for why the two use different
## fade times.
var _mortar_impacts: Array[Dictionary] = []
## Civilians killed and wounded by mortar shells this battle, by whose shell it was: {"player": {killed, heavily_wounded, walking_wounded},
## "enemy": {...}}. Scored by the totals alone (the side that fired makes no difference to the score); the split is for display only.
var civilian_casualties_by_shell: Dictionary = _empty_civilian_tally()
var _seconds_since_last_shot: float = 0.0

# Word travels fast: the moment ANY enemy squad comes under fire, every
# enemy squad still marching breaks for cover and starts moving carefully —
# not just the one that was actually shot at. One-shot per battle.
var enemy_alerted: bool = false

# One-shot flags: has EITHER side's commander ordered a general withdrawal
# yet? The player's is a direct command (order_general_retreat); the
# enemy's is automatic, triggered once their situation looks hopeless (see
# _check_enemy_commander_retreat). Either one puts the whole battle into
# the faster general-retreat tactical-clock tier — see _current_time_scale.
var player_general_retreat_ordered: bool = false
var enemy_general_retreat_ordered: bool = false

# One-shot: has the enemy's own mortar force been pulled back specifically
# because no enemy squad is left fighting any more? See
# _check_enemy_mortar_isolated_retreat's own doc comment — independent of
# enemy_general_retreat_ordered above, since a force can lose every squad
# without ever crossing the whole-force hopeless casualty threshold that
# flag is gated on.
var enemy_mortar_isolated_retreat_ordered: bool = false

# Counter-battery strikes triggered but not yet landed — see
# _resolve_mortar_counter_battery / _resolve_pending_counter_battery.
# {"attacker": Unit, "target": Unit, "aim_position": Vector2 (where the position was located), "impact_position": Vector2 (the aim point until the
# round is fired, then where it will actually land: the aim point plus the same dispersion as any other mortar round), "fire_time", "impact_time", "fired"}
var _pending_counter_battery: Array[Dictionary] = []
## Who has fired DIRECT fire at each unit lately, for the crossfire multiplier (see _crossfire_multiplier_against):
## target -> {shooter -> {"from": Vector2 (where the shooter stood when it fired), "time": float (scenario seconds)}}.
## Mortar rounds are never recorded here (they have no meaningful direction).
var _recent_direct_fire: Dictionary = {}

# Mortar shots fired but not yet landed — see _launch_mortar_shot /
# _resolve_pending_mortar_shots. {"mortar": Unit, "target": Unit,
# "aim_point": Vector2, "impact_point": Vector2, "impact_time": float}
# "aim_point" is where the crew calculated/led the shot; "impact_point" is
# where it actually lands, offset from aim_point by real ballistic
# dispersion (see _mortar_dispersion_offset) — the two differ on every
# shot, not just a missed lead.
var _pending_mortar_shots: Array[Dictionary] = []

# A shoot-and-scoot mortar (Unit) -> {"destination": Vector2, "speed":
# float, "intent": String, "urgent": bool, "ready_time": float} — a
# displacement queued the instant it fired, held until the real-world
# pack-up delay elapses. See _queue_mortar_displacement /
# _resolve_pending_mortar_displacement, and GameConfig.MORTAR_SETUP_
# TEARDOWN_TIME's own doc comment for why this isn't instant.
var _pending_mortar_displacement: Dictionary = {}


# True once a side has EVER sighted the enemy — sticky, not "currently
# visible right now" (see _update_sighting_flags) — "once the enemy is
# sighted, resupply can be requested" is a one-time unlock, not something
# that un-unlocks if contact is lost again later.
var _player_sighted_enemy: bool = false
var _enemy_sighted_enemy: bool = false

# One entry per mortar with an active resupply request — see
# request_mortar_resupply/_update_mortar_resupply. Keyed by the mortar
# Unit; removed the moment the run actually commits (dispatched as a real,
# physical Unit.Kind.RESUPPLY_RUN — see _spawn_resupply_run — or fails
# outright), at which point _update_mortar_resupply immediately requests
# the NEXT one — a continuous pipeline, not a batch. Direct user
# correction after a live-observed bug: a wave whose scheduled transit
# time elapsed while the mortar still had plenty of ammo used to be
# discarded outright (marked resolved with no run ever dispatched),
# effectively delaying real resupply by a full extra cycle instead of
# just waiting for the moment it's actually needed. Fields: arrival_time/
# warning_time (float) — when the run finishes its transit and becomes
# staged, ready to enter the moment ammo is low enough — and warned/staged
# (bool), the second only ever narrated once (see _update_mortar_resupply
# itself for the "arrived but ammo still high" hold behavior this exists
# to describe).
var _mortar_resupply: Dictionary = {}

# Unit (a mortar) -> {"position": Vector2, "time": float} — where and when
# that mortar was last DETECTED firing, via muzzle blast/trajectory rather
# than visual spotting (real counter-battery detection doesn't need to see
# the crew) — see _launch_mortar_shot (records it, every shot, any mortar)
# and _known_friendly_mortar_position (consumes it, as a fallback when the
# mortar isn't currently visible either).
var _last_detected_mortar_fire: Dictionary = {}

# Unit (a mortar) -> {"target": Unit, "shots": int} — tracks "walking fire"
# onto the CURRENT target: `shots` counts how many prior rounds at this
# same target actually got corrected from (see _mortar_fire_observation_
# quality — a shot nobody could observe teaches the crew nothing, so it
# doesn't advance this count). Reset outright the instant `target` changes:
# a correction learned against one aim point says nothing about a
# different one. See _mortar_dispersion_offset, the sole reader/writer.
var _mortar_fire_adjustment: Dictionary = {}

# Unit (a mortar) -> Array[Vector2], a short rolling history of this
# mortar's own last few relocation destinations (both sides) — see
# GameConfig.MORTAR_RECENT_POSITION_MEMORY_COUNT's own doc comment and
# _remember_mortar_position, the sole writer. Read by _mortar_relocation_
# plan and fed into GameConfig.nearest_hidden_point as extra positions to
# avoid, so shoot-and-scoot can't just cycle between the same 2-3 "best"
# hiding spots relative to a static threat picture — confirmed as a real,
# reported symptom by logging actual scoot destinations across several
# full battles before this existed.
var _mortar_recent_positions: Dictionary = {}

# Unit (a mortar) -> bool, whether it has fired at least once since its
# last accepted relocation — see GameConfig.MORTAR_REVERSAL_DIRECTION_
# DOT_THRESHOLD's own doc comment for why this exempts a genuine post-
# fire shoot-and-scoot move from the "don't reverse your last leg"
# discouragement: reversing WITHOUT ever having fired in between is
# indecisive backtracking, but reversing AFTER a real fire mission is
# just the doctrinally-correct next move happening to point back the
# way the crew came. Set true in _launch_mortar_shot, reset false the
# instant a fresh relocation is actually accepted (_remember_mortar_
# position, the same place _mortar_recent_positions itself updates).
var _mortar_fired_since_relocation: Dictionary = {}

# Unit (a mortar) -> float, the farthest distance from _friendly_mortar_
# home_position any relocation has actually put this mortar at DURING THE
# CURRENT danger episode — a high-water mark, never voluntarily given up
# while still compromised. Fed into GameConfig.nearest_hidden_point's own
# min_distance_from_home as a floor on the NEXT relocation, whatever
# triggers it. Exists because none of evade/conceal/scoot share any
# memory of each other: each is purely reactive to wherever the mortar
# currently is and whatever's currently threatening it, so an evade
# reacting to some OTHER, unrelated threat has no idea a scoot already
# put real distance between the crew and the position that got it
# compromised in the first place, and can walk it right back toward that
# danger — confirmed directly (not theorized) by tracing every real
# relocation-search call during an actual oscillating battle: the
# reverse-slope candidate was essentially always rejected as "too far"
# once the mortar had moved on, and the ring search, which has no notion
# of which direction is actually away from where the danger started, was
# the one producing the wandering. Reset to 0.0 (see _decide_mortar_
# action's own reset check) the instant the mortar is no longer
# compromised by ANY of the tier-1 triggers — this is a floor for the
# duration of one continuous escape, not a permanent one-way ratchet that
# would eventually strand the crew at the far edge of its own home leash
# long after the actual threat that caused it has passed.
var _mortar_max_distance_from_home: Dictionary = {}

# Unit (a mortar) -> Unit (the target it can fire on right now, or literally
# absent from this dict if not yet resolved this tick) — memoizes _pick_
# target's own result for a mortar across the several things that ask "does
# this mortar have a shot right now" in the same tick (the resupply-linkup
# check, _tick_fire's own real fire attempt, the mortar decision ladder's
# own tier-1 gate). _pick_target is NOT idempotent — it rolls real
# randomness (the ammo hold-fire chance, the weighted target pick) — so
# without this, the same mortar could get a different answer to different
# callers in the same tick, occasionally flickering between "I have a
# shot, stand and fight" and "nothing to shoot, retreat for safety" like a
# coin flip. See _mortar_shot_this_tick, the only function allowed to read
# or write this. Cleared at the top of every _process tick, before
# anything (including _tick_fire) runs — see _process.
var _mortar_tick_shot: Dictionary = {}

# Unit (a mortar) -> String, one of "scoot"/"evade"/"conceal"/"out_of_ammo"/
# "linkup"/"hunt" — why this mortar currently has an active move order, set
# by _issue_mortar_move and cleared by _clear_mortar_move. The mortar
# decision ladder (_decide_mortar_action) uses this to keep a
# self-preservation walk (scoot/evade/conceal/out_of_ammo/linkup) sticky
# against being overwritten by a lower-tier move (hunt) mid-stride — a real
# bug in the old, per-function architecture this replaces, where hunting
# could silently steal a shoot-and-scoot displacement out from under a
# mortar that had just fired.
## Unit -> true for each friendly mortar the commander has ordered to expend
## ammo on enemy squads (set_mortar_squad_fire_order). Absent = default
## behavior, exactly as before the order existed.
var _mortar_squad_fire_orders: Dictionary = {}
var _mortar_move_intent: Dictionary = {}

# Unit (a mortar) -> {"tier": String, "detail": String} — the mortar
# decision ladder's own live reasoning trail, mirroring _drone_pilot_
# reasoning/drone_pilot_debug_snapshot for the drone. Written exactly once
# per mortar per tick, on every path including "holding, nothing to do" —
# see _decide_mortar_action and mortar_decision_debug_snapshot.
var _mortar_reasoning: Dictionary = {}

# Unit (a mortar) -> Array[Dictionary], a bounded rolling trace of recent
# threat-assessment inputs (position, visibility, closing-threat status) —
# direct user request, after a mortar was destroyed and the only
# visibility into what led up to it was a single frozen final-state
# snapshot: "get yourself enough visibility so that if this happens again
# you can see what happened." See _record_mortar_debug_history and
# mortar_decision_debug_snapshot's own "recent_history" field. Capped by
# entry COUNT, not tactical time, since this project's own time scale
# varies 60-300x — a fixed count gives a consistent amount of recent
# DECISION history regardless of how much tactical time each entry spans.
var _mortar_debug_history: Dictionary = {}
const MORTAR_DEBUG_HISTORY_LIMIT: int = 40

# The single enemy mortar the friendly mortar and the drone/spotter are
# CURRENTLY, JOINTLY committed to running down together, or null if
# nothing's being hunted right now — see _update_joint_mortar_hunt. Exists
# because the mortar's own hunt decision (_decide_mortar_action's tier 2)
# and the drone's own search-target priority (_drone_search_target) used
# to each independently re-derive "is this still worth it" every tick from
# the same raw signals (_known_enemy_mortar_lead) with slightly different
# math (a moving mortar's own range check, a fire-lead's own expiry) — the
# two could and did drift out of agreement mid-hunt, so the mortar kept
# walking toward a position the drone had already stopped bothering to
# watch. A single shared commitment, formed once and consulted by both
# instead of independently re-decided by each, is what actually keeps them
# working the same goal for as long as it's still worth pursuing.
var _joint_mortar_hunt_target: Unit = null
var _joint_mortar_hunt_start_time: float = 0.0

# Sticky picks among several simultaneously-visible ACTIVE enemy mortars —
# see _closest_enemy_mortar's own doc comment for why "closest to our
# mortar, with a switching margin" needs its own remembered state rather
# than being re-derived fresh from scratch every tick. Two SEPARATE sticky
# slots, not one shared: _known_enemy_mortar_lead and
# _priority_visible_enemy_mortar's own fallback branch pick from two
# genuinely different candidate pools (the second explicitly EXCLUDES
# whichever mortar the first already claimed as the priority hunt target)
# — sharing one slot between them would let one function's pick silently
# overwrite the other's memory of what it was tracking.
var _known_enemy_mortar_lead_unit: Unit = null
var _drone_fallback_mortar_watch_unit: Unit = null

# Where the friendly mortar was actually deployed this battle (the
# player's own doctrine choice, wherever in PLAYER_MORTAR_DEPLOYMENT_ZONE
# that was) — captured once in _spawn_player_units and never touched
# again. This is what "safe territory" means for GameConfig.MORTAR_HUNT_
# MAX_RANGE_FROM_HOME: hunting is good, but not unbounded — the crew
# still won't range farther than that from wherever they were actually
# set up, no matter how good the intel on a target is or how far away
# known enemy squads happen to be.
var _friendly_mortar_home_position: Vector2 = Vector2.ZERO
## Where each enemy mortar was deployed (Unit -> Vector2): its "home" for the same leash the friendly
## mortar has (see _mortar_home_position). Set when the enemy force is spawned.
var _enemy_mortar_homes: Dictionary = {}

# Which reconnaissance setup this battle is using (see GameConfig.ReconMode)
# — set from the doctrine dict in start_battle. DRONE_TEAM fields below are
# only ever populated/consumed when this is DRONE_TEAM; harmless no-ops
# otherwise (every function that touches them checks this first).
var recon_mode: GameConfig.ReconMode = GameConfig.ReconMode.SPOTTER

# ReconMode.DRONE_TEAM only. drone_team is the ground crew — a normal
# player_units member, like the spotter it replaces. active_drone is the
# currently-searching sortie, or null if the sky is momentarily empty (a
# shoot-down with no standby ready yet). backup_drone is a SECOND sortie,
# only ever launched while active_drone is watching a live, engageable
# enemy mortar (see _visible_engageable_mortar) — it shadows the same
# target so that if active_drone is lost, coverage continues with zero
# gap (see _update_drone_operations's promotion step), instead of a
# fresh launch having to fly all the way out there from scratch.
# returning_drones is every sortie that's already handed off its role
# (to a replacement, or to backup_drone taking over) but is still
# physically flying home — a plain array since active_drone and
# backup_drone can end up heading home at different times, not just
# one at a time (see _update_returning_drones). Only these ever exist
# as real Units; anything grounded isn't part of the battle at all. See
# _update_drone_operations.
var drone_team: Unit = null
var active_drone: Unit = null
var backup_drone: Unit = null
var returning_drones: Array[Unit] = []

# The fleet is 4 AIRFRAMES (DRONE_FLEET_SIZE) but 8 BATTERIES (that plus
# DRONE_SPARE_BATTERIES). What's actually tracked is each battery's real
# CHARGE LEVEL (0.0-1.0), both airborne (Unit.drone_battery_charge) and on
# the ground here — swap time (GameConfig.DRONE_BATTERY_SWAP_DURATION, a
# few minutes) and recharge time (DRONE_RECHARGE_DURATION, ~100 minutes to
# go from empty to full) are both DERIVED from that level, not separately
# counted down: a battery recharges at a fixed rate, and however much
# charge it's actually missing when it lands determines how long that
# takes, and the ground crew always swaps in whichever battery it has on
# hand with the MOST charge — not necessarily full.
#
# Every airframe not currently flying/inbound is exactly one of:
# _drones_ready (grounded, a battery already installed — its charge level
# is this array's entries) or _drones_swapping (grounded, mid battery-swap,
# entries are {time_left, charge} for the battery going in). Every battery
# not currently installed in a flying/inbound/ready/swapping airframe is an
# entry in _battery_pool, charging up over time. With 8 batteries for 4
# airframes, the pool can never actually run dry (worst case, exactly
# DRONE_SPARE_BATTERIES stay uninstalled at all times) — but its best entry
# can still be well under full, which is exactly what "might launch a drone
# with a partly charged battery" means in practice.
var _drones_ready: Array[float] = [] # charge level of each grounded, battery-installed, ready-to-launch airframe
var _drones_swapping: Array[Dictionary] = [] # [{"time_left": float, "charge": float}] grounded airframes mid battery-swap
var _battery_pool: Array[float] = [] # charge level of every battery not currently installed in any airframe
# Airframes that have landed and are sitting on the ground with NO battery in them yet (the battery went to
# the pool to charge). Direct user report: "The sidebar says there are 7 drones ready. That's impossible as
# the team only has 4 drones" / "It may be inappropriately lumping drones and batteries" — when landing
# stopped swapping a battery straight in, the landed airframe stopped being counted anywhere, so staging
# a battery conjured a "ready" airframe out of nothing and `ready` could climb toward 8 (the battery
# count). A battery can only be staged onto one of THESE; staging turns one into a swapping airframe.
var _airframes_awaiting_battery: int = 0
var _drone_tracked_class: int = -1 # the class (2 = threatens the mortar, 1 = approaching ours, 0 = other) _drone_tracked_squad had at the last pick
var _drone_tracked_since: float = 0.0 # scenario_elapsed_time when _drone_tracked_squad was taken up
var _drone_tracked_squad: Unit = null # the enemy squad "Tracking dangerous squad" is on now — see _drone_squad_to_track's stickiness
var _drones_destroyed: int = 0 # airframes permanently lost (shot down, battery and all) this battle
# The current battle's weather is Weather.current (rolled at deployment, or here
# in start_battle if nothing has been rolled for this battle yet).
var weather: Weather:
	get:
		return Weather.current
var _drone_grounded_for_weather: bool = false # moderate-or-worse rain/snow: nothing launches until it has eased for a while
var _drone_weather_clear_s: float = 0.0
var _drones_lost_to_weather: int = 0 # counted in _drones_destroyed too
var _drones_aborted_by_weather: int = 0
var _drones_recalled_by_rain: int = 0
var _last_precip_label: String = ""
# The single candidate key (see _sweep_candidates/_flank_watch_candidates)
# the drone is currently committed to flying toward or sitting at, for the
# unified routine-recon pool — see _drone_routine_recon_target. Empty
# string means no commitment yet (battle start).
var _drone_current_destination_key: String = ""
# How many sweep cells the drone has reached since the last new mortar
# evidence, and the newest evidence time already accounted for — see
# _drone_mortar_search_weight/_effective_empty_sweeps.
var _empty_sweep_arrivals: int = 0
var _empty_sweep_evidence_stamp: float = -INF
# Candidate key -> scenario_elapsed_time it was last actually arrived at
# (not just picked) — see _drone_routine_recon_target/_drone_destination_
# recency_multiplier. A candidate the drone was just at and saw nothing in
# is temporarily much less worth an immediate return to, decaying back to
# its ordinary weight over GameConfig.DRONE_DESTINATION_RECENTLY_VISITED_
# COOLDOWN_S rather than staying suppressed forever the way a confirmed
# kill does (see _area_confirmed_clear for that permanent case).
var _drone_destination_last_visited: Dictionary = {}
# Enemy Unit -> {"position": Vector2, "time": scenario_elapsed_time} for
# every ACTIVE enemy unit seen live at least once recently — see
# _contact_search_bonus. Real, hard-won evidence that enemy activity
# exists near a given spot, feeding a value bonus into nearby routine-
# recon candidates so a confirmed sighting actually shifts where the
# drone looks next, fading out the same way a mortar fire-detection lead
# does rather than vanishing the instant the unit itself drops out of LOS.
var _recent_enemy_contacts: Dictionary = {}
# Unit -> tactical seconds it has continuously been kept in view only by the
# TREE_SIGHT_LOSS_GRACE_S allowance (see _refresh_visibility).
var _tree_sight_lost_for: Dictionary = {}
# Unit -> scenario time it last came into view and has been in view ever since
# (see GameConfig.DRONE_CONTACT_WATCH_FADE_S).
var _contact_watch_since: Dictionary = {}
# Recorded live, in place, by _drone_search_target itself as it decides —
# NOT a separate re-derivation of that decision, which would risk drifting
# out of sync with the real logic. {"tier": String, "detail": String,
# "target": Vector2} describing whichever branch actually won this tick.
# Read-only introspection for drone_pilot_debug_snapshot (the debug
# overlay/export — see BattleScreen) — nothing else may ever branch on this.
var _drone_pilot_reasoning: Dictionary = {}
# Rounded-to-the-pixel point -> scenario_elapsed_time it was last confirmed
# clear by estimated_enemy_likelihood (the enemy heat-map overlay's own
# read-only estimate, see that function's own doc comment) — purely a
# visualization concept, never consulted by any real decision.
var _heatmap_last_cleared: Dictionary = {}

# Post-battle history — see _record_history_snapshot/battle_history. Each
# entry is {"time": scenario_elapsed_time, "units": [{"team","kind","x","y",
# "state"}, ...]} for every unit (both sides, TRUE ground truth — not
# fog-of-war-limited, per the AAR's own history-review feature) still known
# to player_units/enemy_units at that moment. Deliberately plain data, not
# references to the live Unit nodes — some of those (a destroyed drone, a
# despawned resupply run) won't even exist any more by the time the battle
# ends, so a scrubbable history has to stand on its own rather than
# puppeting nodes whose lifecycle it doesn't control.
var _history: Array[Dictionary] = []
var _history_last_recorded_time: float = -INF

# Every shot fired, for BattleHistoryViewer's "Play" replay — separate from
# the live _fire_flashes above (those fade on real elapsed_time, tuned for
# watching the actual battle; this is keyed on scenario_elapsed_time, the
# same clock the position snapshots above use, since replay scrubs/plays
# through tactical time, not real time). Same shape as a _fire_flashes
# entry minus "time" meaning something different: {"time": scenario_elapsed_
# time, "from", "to", "team", "is_mortar"}. Recorded at the moment of firing
# (a mortar's muzzle flash, not its delayed impact), same as the live flash.
var _history_fire_events: Array[Dictionary] = []


func start_battle(doctrine: Dictionary, p_combat_log: CombatLog) -> void:
	combat_log = p_combat_log
	commander_profiles[Unit.Team.PLAYER] = CommanderProfile.sanitize(doctrine.get("player_profile", {}))
	commander_profiles[Unit.Team.ENEMY] = CommanderProfile.sanitize(doctrine.get("enemy_profile", {}))
	decisions = DecisionRecorder.new()
	unit_type_doctrines[Unit.Team.PLAYER] = UnitDoctrine.sanitize(doctrine.get("player_unit_types", {}))
	unit_type_doctrines[Unit.Team.ENEMY] = UnitDoctrine.sanitize(doctrine.get("enemy_unit_types", {}))
	unit_combat_stats = UnitCombatStats.new()
	_risk_holds.clear()
	_unit_name_counts.clear()
	_enemy_discovery_counts.clear()
	battle_seed = int(doctrine.get("seed", -1))
	if battle_seed >= 0:
		seed(battle_seed)
	# The enemy side's own dice: one dedicated stream, seeded from the battle seed alone — see _enemy_rng
	# for why. The commander's whole-force breaking point (_enemy_situation_hopeless; randomized per battle
	# and never surfaced to the player) is its first draw; _spawn_enemy_units below takes the rest.
	_seed_enemy_rng()
	_enemy_commander_retreat_threshold = _roll_enemy_commander_retreat_threshold()
	elapsed_time = 0.0
	scenario_elapsed_time = 0.0
	battle_over = false
	_ended_by_stalemate = false
	battle_result = {}
	is_paused = false
	_fire_flashes.clear()
	_mortar_impacts.clear()
	civilian_casualties_by_shell = _empty_civilian_tally()
	_seconds_since_last_shot = 0.0
	enemy_alerted = false
	player_general_retreat_ordered = false
	enemy_general_retreat_ordered = false
	enemy_mortar_isolated_retreat_ordered = false
	_last_detected_mortar_fire.clear()
	_mortar_squad_fire_orders.clear()
	_fall_back_orders.clear()
	_fallen_back.clear()
	_retreat_orders.clear()
	_enemy_attacking = true
	_enemy_stance_decided = false
	_enemy_consolidation = Vector2.INF
	_mortar_tick_shot.clear()
	_observed_mortar_track.clear()
	_mortar_move_intent.clear()
	_mortar_reasoning.clear()
	_joint_mortar_hunt_target = null
	_joint_mortar_hunt_start_time = 0.0
	_known_enemy_mortar_lead_unit = null
	_drone_fallback_mortar_watch_unit = null
	_pending_counter_battery.clear()
	_recent_direct_fire.clear()
	_pending_mortar_shots.clear()
	recon_mode = doctrine.get("recon_mode", GameConfig.ReconMode.SPOTTER)
	drone_team = null
	active_drone = null
	backup_drone = null
	returning_drones.clear()
	_drones_ready.clear()
	_drones_swapping.clear()
	_battery_pool.clear()
	_airframes_awaiting_battery = 0
	_drone_tracked_squad = null
	_drone_tracked_since = 0.0
	_drone_tracked_class = -1
	_drones_destroyed = 0
	_drones_lost_to_weather = 0
	_drones_aborted_by_weather = 0
	_drones_recalled_by_rain = 0
	_drone_grounded_for_weather = false
	_drone_weather_clear_s = 0.0
	if Weather.current == null or Weather.current.battle_started:
		Weather.current = Weather.roll(battle_seed + 7919 if battle_seed >= 0 else -1)
	Weather.current.battle_started = true
	_last_precip_label = Weather.current.precip_label()
	combat_log.log_weather_report(Weather.current)
	_drone_destination_last_visited.clear()
	_drone_current_destination_key = ""
	_empty_sweep_arrivals = 0
	_empty_sweep_evidence_stamp = -INF
	_recent_enemy_contacts.clear()
	_lost_contact_checked.clear()
	_contact_watch_since.clear()
	_tree_sight_lost_for.clear()
	GameConfig.prepare_canopy() # pay the one-off raster build before the fight, not mid-tick
	_heatmap_last_cleared.clear()
	_history.clear()
	_history_last_recorded_time = -INF
	_history_fire_events.clear()
	_player_sighted_enemy = false
	_enemy_sighted_enemy = false
	_mortar_resupply.clear()

	for unit in player_units + enemy_units:
		unit.queue_free()
	player_units.clear()
	enemy_units.clear()

	_spawn_player_units(doctrine)
	_spawn_enemy_units()

	queue_redraw()


## HH:MM:SS tactical time-of-day, starting at GameConfig.SCENARIO_START_HOUR
## (0600) and advancing with scenario_elapsed_time.
## `at_time` defaults to the live scenario_elapsed_time, but the history
## viewer (see battle_history/BattleHistoryViewer) needs the clock as it
## read at some earlier recorded moment, not the current one.
func clock_string(at_time: float = scenario_elapsed_time) -> String:
	var total_seconds: int = int(GameConfig.SCENARIO_START_HOUR * 3600.0 + at_time)
	var h: int = (total_seconds / 3600) % 24
	var m: int = (total_seconds / 60) % 60
	var s: int = total_seconds % 60
	return "%02d:%02d:%02d" % [h, m, s]


## One frame of the post-battle history — see _history's own doc comment
## for the exact shape. Called periodically from _process (throttled by
## HISTORY_SNAPSHOT_INTERVAL_S) and once more, unconditionally, right as
## the battle ends, so the final moment is always captured exactly even if
## it falls between two regular intervals.
func _record_history_snapshot() -> void:
	var units: Array[Dictionary] = []
	for u in player_units + enemy_units:
		# unit_label/pips/max_pips added so BattleHistoryViewer can render
		# the same label-and-strength-bar detail the live game shows — see
		# its own _draw_unit doc comment. Terrain (for the cover ring) is
		# deliberately NOT snapshotted here: it never changes over the
		# course of a battle, so the viewer can just look it up fresh from
		# the recorded x/y instead of storing it redundantly every snapshot.
		var entry: Dictionary = {"team": u.team, "kind": u.kind, "x": u.global_position.x, "y": u.global_position.y, "state": u.state,
			"unit_label": u.unit_label, "pips": u.pips, "max_pips": u.max_pips}
		# What the dashboard's mortar row reads (rounds left, crew, resupply) —
		# recorded so replaying the history can show it as it was at each
		# moment, not as it ended.
		if u.kind == Unit.Kind.MORTAR:
			entry["mortar"] = mortar_status_view(u)
		units.append(entry)
	# Likewise the drone fleet row (empty outside the drone-team recon mode,
	# where the row isn't shown at all).
	var snapshot: Dictionary = {"time": scenario_elapsed_time, "units": units}
	snapshot["drone_fleet"] = drone_fleet_status() if recon_mode == GameConfig.ReconMode.DRONE_TEAM else {}
	_history.append(snapshot)


## Everything a mortar's status row needs, as plain data: its state, rounds
## remaining, crew casualties and whether the gun was abandoned, and the
## resupply status. The ONE place that gathers it — CasualtyDashboard reads
## it for the live board, and _record_history_snapshot stores it per moment,
## so the live board and the history replay can never disagree about what a
## mortar's row is made of.
func mortar_status_view(u: Unit) -> Dictionary:
	return {
		"state": u.state,
		"rounds": u.mortar_rounds_remaining,
		"crew_casualties": u.crew_casualties,
		"crew_size": u.crew_size,
		"gun_abandoned": u.mortar_gun_abandoned,
		"resupply": mortar_resupply_status(u),
	}


## Public accessor for BattleReport's BattleHistoryViewer — read-only, recorded
## once per battle, never mutated after the fact.
func battle_history() -> Array[Dictionary]:
	return _history


## Public accessor for BattleReport's BattleHistoryViewer — see _history_fire_
## events' own doc comment for the shape. Read-only, recorded once per
## battle, never mutated after the fact.
func battle_history_fire_events() -> Array[Dictionary]:
	return _history_fire_events


## True once EITHER side's commander has ordered a general withdrawal — not
## just some individual unit routing on its own threshold while the rest of
## the battle carries on. Drives the tactical clock's pace: see
## _current_time_scale. Stays true for the rest of the battle once set;
## nobody un-orders a retreat.
func _general_withdrawal_in_progress() -> bool:
	return player_general_retreat_ordered or enemy_general_retreat_ordered


## True the instant anyone on either side currently sees an enemy — firing
## requires a visible/targetable target, so this covers "actively fighting"
## too, not just "spotted." Drives the tactical clock's pace: see
## _current_time_scale.
func _any_contact() -> bool:
	for u in player_units + enemy_units:
		if u.is_visible:
			return true
	return false


## True whenever a drone is actually up hunting for contact — its own
## flight (movement AND battery drain, both scenario_delta-based just like
## everything else that moves — see _tick_movement/_update_active_drone)
## is genuinely real-world-time-bound: a real Mavic 3's ~36-minute
## endurance doesn't stretch or compress just because nothing else on the
## ground happens to be interesting yet. Without this, an active sortie
## launched during the pre-contact FAST_FORWARD tier (see
## _current_time_scale) burned its ENTIRE flight budget in a handful of
## real seconds — 2143 tactical seconds of endurance at 300x scale is only
## ~7 real seconds, nowhere near enough real time for even a single
## roll_spot chance (spotting runs on real `delta`, not scenario_delta) to
## land before it was already forced to turn for home. Counts active OR
## backup — either one airborne is "a mission in progress" — but not
## returning_drones, whose search is already over regardless of pace.
func _drone_actively_searching() -> bool:
	return recon_mode == GameConfig.ReconMode.DRONE_TEAM and (active_drone != null or backup_drone != null)


## Picks how fast the tactical clock runs this tick — realistic pace the
## moment there's something worth watching closely (live contact, which
## always wins even during a general withdrawal — a fighting retreat is
## still worth watching closely — or a drone actively out hunting for it),
## faster once a general withdrawal is under way and nobody's currently in
## contact, fastest of all when there's nothing happening at all yet (e.g.
## the long road march before first contact with no drone up yet, or a
## single unit's own quiet, isolated retreat) — see GameConfig's
## TIME_SCALE_* constants for the reasoning.
func _current_time_scale() -> float:
	if _any_contact() or _drone_actively_searching():
		return GameConfig.TIME_SCALE_NORMAL
	if _general_withdrawal_in_progress():
		return GameConfig.TIME_SCALE_GENERAL_RETREAT
	return GameConfig.TIME_SCALE_FAST_FORWARD


func _spawn_player_units(doctrine: Dictionary) -> void:
	for squad_doctrine in doctrine.squads:
		var squad := _make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, squad_doctrine.position)
		squad.retreat_threshold = squad_doctrine.retreat_threshold
		_set_retreat_profile(squad, Unit.Team.PLAYER)
		player_units.append(squad)

	var m1 := _make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, doctrine.mortar.position)
	m1.shoot_and_scoot = doctrine.mortar.shoot_and_scoot
	_set_retreat_profile(m1, Unit.Team.PLAYER)
	player_units.append(m1)
	_friendly_mortar_home_position = doctrine.mortar.position

	# `doctrine.spotter.position` is the deployment CHOICE (see
	# GameConfig.CURRENT_MAP.player.spotter_deployment_zone) — reused as-is for the drone
	# team's ground-station position too, regardless of which recon mode was
	# actually picked (see main.gd).
	if recon_mode == GameConfig.ReconMode.DRONE_TEAM:
		drone_team = _make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, doctrine.spotter.position)
		_set_retreat_profile(drone_team, Unit.Team.PLAYER)
		player_units.append(drone_team)
		# A well-prepared team starts H-hour with everything topped off: all
		# DRONE_FLEET_SIZE airframes AND all DRONE_SPARE_BATTERIES spares at
		# full charge — nothing has been flown yet, so nothing's depleted.
		# _launch_drone() below pulls one battery to launch immediately,
		# leaving the rest ready to go, with the spares only coming into play
		# once the first swap actually happens.
		for i in GameConfig.DRONE_FLEET_SIZE:
			_drones_ready.append(1.0)
		for i in GameConfig.DRONE_SPARE_BATTERIES:
			_battery_pool.append(1.0)
		_launch_drone()
	else:
		var spotter := _make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, doctrine.spotter.position)
		_set_retreat_profile(spotter, Unit.Team.PLAYER)
		player_units.append(spotter)


## Everything the enemy side rolls when a battle is set up — the force's size, which squads swing wide,
## each unit's starting fire phase, the commander's breaking point — comes from this ONE dedicated stream,
## not the shared global one. Direct user request: "As much as possible, make the code to generate the
## enemy force independent of everything else that is going on. For example, if the same seed is used on a
## different map or with a different recon choice, it still gives the same enemy force." Before this, the
## force was drawn from the global stream AFTER every player unit (and, in drone-team mode, the first
## drone) had already consumed draws of their own making (`_make_unit` rolls a fire phase per unit) — so
## the number of player squads a map happens to default to, and whether recon is a spotter or a drone team,
## silently shifted every number the enemy force was built from. A stream of its own, seeded from the
## battle seed alone and consumed in a fixed order, cannot be shifted by anything else.
##
## What this does NOT make identical, by construction: where the force starts. Positions are laid out from
## the map's own geometry (spawn line, road, spread range — see GameConfig.enemy_squad_y_offsets_m and
## enemy_mortar_positions_m), so the same force on a different map stands in that map's places. Nor does it
## cover any future case where the force's range is meant to differ by situation — that would, as the user
## put it, "break this" on purpose, and the draws would then need the situation as an input.
var _enemy_rng := RandomNumberGenerator.new()
const ENEMY_RNG_SEED_SALT: int = 1163413837 # "ENEM" — keeps this stream distinct from anything else a future caller might derive from the battle seed


## Seeds `_enemy_rng` from the battle seed alone (hashed with the salt above), so the same seed always
## starts the same stream no matter what else has happened. An unseeded battle (a test or harness that
## never passed one) takes its seed from the global stream instead — one draw, so a caller that seeded the
## global stream itself still gets a reproducible battle.
func _seed_enemy_rng() -> void:
	_enemy_rng.seed = hash(battle_seed + ENEMY_RNG_SEED_SALT) if battle_seed >= 0 else randi()


## The enemy commander's whole-force breaking point for this battle — see GameConfig.ENEMY_COMMANDER_
## RETREAT_THRESHOLD_MIN/MAX and `_enemy_commander_retreat_threshold`. Drawn from the enemy stream (the first
## draw it ever makes) rather than the global one, so it is as independent of the player's setup as the
## force itself.
func _roll_enemy_commander_retreat_threshold() -> float:
	return _enemy_rng.randf_range(GameConfig.ENEMY_COMMANDER_RETREAT_THRESHOLD_MIN, GameConfig.ENEMY_COMMANDER_RETREAT_THRESHOLD_MAX)


## The attacking force's size, rolled once per battle — not always the same
## strength. Squad count is rolled FIRST, a two-piece mixture rather than
## one flat range: ENEMY_SQUAD_COUNT_TAIL_CHANCE (15%) of the time it's
## uniform across a RIGHT TAIL (ENEMY_SQUAD_COUNT_MAX+1..TAIL_MAX, i.e.
## 11-15) instead of the ordinary range — the rest of the time (85%) it's
## uniform across GameConfig.ENEMY_SQUAD_COUNT_MIN..MAX exactly as before,
## every count from 2 to 10 still genuinely equally likely within that
## 85%. A real assault is usually a company-minus-sized probe with an
## occasional much larger one, not a smooth gradient — modeled as a
## mixture of two uniforms rather than widening the single uniform range
## outright, which would have thinned out the ordinary 2-10 band the
## player actually sees most battles just to make room for a rare, much
## bigger one.
##
## Mortar count is then DERIVED from that roll: roughly squads /
## ENEMY_SQUAD_PER_MORTAR_RATIO, jittered by ENEMY_MORTAR_COUNT_JITTER so
## it's approximate rather than a rigid formula, then clamped into its own
## separate, much narrower min/max range. Rolling squads first and
## deriving mortars (rather than the reverse) is deliberate: clamping the
## derived value's own narrow range can still skew ITS distribution
## toward the ends, but that no longer distorts the primary, directly-
## player-visible squad count. The jitter is now wide enough that a real
## mismatch (8 squads, 1 mortar) is an occasional outcome, not a
## theoretical one the old, tighter jitter could never actually produce.
func roll_enemy_force_size() -> Dictionary:
	var squads: int
	if _enemy_rng.randf() < GameConfig.ENEMY_SQUAD_COUNT_TAIL_CHANCE:
		squads = _enemy_rng.randi_range(GameConfig.ENEMY_SQUAD_COUNT_MAX + 1, GameConfig.ENEMY_SQUAD_COUNT_TAIL_MAX)
	else:
		squads = _enemy_rng.randi_range(GameConfig.ENEMY_SQUAD_COUNT_MIN, GameConfig.ENEMY_SQUAD_COUNT_MAX)
	var target_mortars: int = roundi(float(squads) / GameConfig.ENEMY_SQUAD_PER_MORTAR_RATIO)
	var jitter: int = _enemy_rng.randi_range(-GameConfig.ENEMY_MORTAR_COUNT_JITTER, GameConfig.ENEMY_MORTAR_COUNT_JITTER)
	var mortars: int = clampi(target_mortars + jitter, GameConfig.ENEMY_MORTAR_COUNT_MIN, GameConfig.ENEMY_MORTAR_COUNT_MAX)
	return {"mortars": mortars, "squads": squads}


## The retained terrain layer — see _draw and terrain_layer.gd. Behind the
## parent's own drawing (fire flashes) and, being the first child, behind
## every unit.
var _terrain_layer: Node2D = null


func _ready() -> void:
	_terrain_layer = preload("res://scripts/terrain_layer.gd").new()
	_terrain_layer.show_behind_parent = true
	add_child(_terrain_layer)
	move_child(_terrain_layer, 0)
	_build_mortar_fire_sound_pool()
	_gunfire_ambience = GunfireAmbience.new()
	add_child(_gunfire_ambience)


func _build_mortar_fire_sound_pool() -> void:
	for i in MORTAR_FIRE_SOUND_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_mortar_fire_sound_players.append(player)


## One round-robin player from the pool takes this shot's sound — cycling
## through the whole pool (rather than always reusing whichever player is
## currently free) means a shot fired well after the last one still varies
## which player handles it, so a stuck/misbehaving player node can never
## silently claim every shot.
##
## A real, discovered gap: characterize_doctrine.gd drives its whole 200-
## trial loop synchronously from _initialize(), with no idle frame ever
## elapsing before, during, or between trials — so this BattleManager (and
## every AudioStreamPlayer it builds) never actually finishes entering the
## tree in the sense the audio engine requires, even though add_child()
## itself succeeds structurally. _ready() never firing meant an empty pool
## (fixed above via the lazy build); a freshly-built player still can't
## actually play in that same synchronous context, so this skips playback
## entirely rather than erroring — a real no-op only in that harness, since
## normal play always has a live, fully-entered tree before any battle
## logic runs at all.
##
## Direct user request: the enemy's own mortar fire should read as quieter
## than the player's — `ENEMY_MORTAR_FIRE_SOUND_EXTRA_ATTENUATION_DB` on top
## of the shared base level, not a separate volume entirely, so a further
## overall retune still moves both sides together.
##
## Takes the firing `mortar` itself, not just its team — see
## _mortar_audio_log's own doc comment for why: every field logged here
## (real-world timing, whether the pool player was already mid-clip, the
## tactical clock's pace, contact status) needs the FULL calling context,
## and a bare team enum couldn't carry any of it.
func _play_mortar_fire_sound(mortar: Unit) -> void:
	if _mortar_fire_sound_players.is_empty():
		_build_mortar_fire_sound_pool()
	var player: AudioStreamPlayer = _mortar_fire_sound_players[_mortar_fire_sound_pool_index]
	_mortar_fire_sound_pool_index = (_mortar_fire_sound_pool_index + 1) % _mortar_fire_sound_players.size()
	var already_playing: bool = player.playing
	var skipped: bool = not player.is_inside_tree()
	var volume_db: float = MORTAR_FIRE_SOUND_VOLUME_DB
	if mortar.team == Unit.Team.ENEMY:
		volume_db += ENEMY_MORTAR_FIRE_SOUND_EXTRA_ATTENUATION_DB
	_mortar_audio_log.append({
		"mortar": mortar.display_name(),
		"team": "player" if mortar.team == Unit.Team.PLAYER else "enemy",
		"scenario_time": scenario_elapsed_time,
		"real_msec": Time.get_ticks_msec(),
		"volume_db": volume_db,
		"pool_index": _mortar_fire_sound_pool_index,
		"player_was_already_playing": already_playing,
		"skipped_not_in_tree": skipped,
		"time_scale": _current_time_scale(),
		"any_contact": _any_contact(),
	})
	while _mortar_audio_log.size() > MORTAR_AUDIO_LOG_LIMIT:
		_mortar_audio_log.pop_front()
	if skipped:
		return
	player.stream = MORTAR_FIRE_SOUNDS[randi() % MORTAR_FIRE_SOUNDS.size()]
	player.volume_db = volume_db
	player.play()


## Public accessor for mortar-fire audio diagnostics — see _mortar_audio_
## log's own doc comment for why this exists and what each field answers.
## Same conventions as the other debug snapshots: both sides, unconditional,
## written every frame regardless of any on-screen toggle (BattleScreen's own
## _write_debug_snapshot).
func mortar_audio_debug_snapshot() -> Dictionary:
	return {
		"pool_size": _mortar_fire_sound_players.size(),
		"pool_index": _mortar_fire_sound_pool_index,
		"log": _mortar_audio_log,
	}


func _spawn_enemy_units() -> void:
	_enemy_mortar_homes.clear()
	var road_px: Array[Vector2] = GameConfig.road_waypoints_px()
	var force_size: Dictionary = roll_enemy_force_size()
	var squad_y_offsets_m: Array[float] = GameConfig.enemy_squad_y_offsets_m(force_size.squads)
	# A real road march down the winding road (see GameConfig.ROAD_WAYPOINTS_M),
	# not a straight line. Each squad's whole path is the same road shifted by
	# its own fixed y offset — a loose spread advancing near the road, not
	# single file on top of it or on top of each other.
	for i in squad_y_offsets_m.size():
		var y_offset: float = squad_y_offsets_m[i] * GameConfig.PIXELS_PER_METER
		var start_pos := Vector2(GameConfig.CURRENT_MAP.enemy.spawn_x, road_px[0].y + y_offset)
		var squad := _make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, start_pos)
		# _make_unit gave it a fire phase from the GLOBAL stream (right for every other caller); replace
		# it from the enemy stream so this unit's start state doesn't depend on how many units the player
		# side happened to create first. See _enemy_rng.
		squad.fire_timer = _enemy_rng.randf_range(0.0, squad.fire_interval)
		squad.retreat_threshold = GameConfig.ENEMY_RETREAT_THRESHOLD if profile_for(Unit.Team.ENEMY).id == "baseline" else float(profile_for(Unit.Team.ENEMY).retreat_threshold)
		squad.concern_threshold = GameConfig.ENEMY_CONCERN_THRESHOLD
		squad.move_speed = GameConfig.ENEMY_ADVANCE_SPEED
		var path: Array[Vector2] = []
		for wp in road_px:
			path.append(wp + Vector2(0.0, y_offset))
		squad.set_path(path)
		squad.movement_predictable = true # a steady, known march — lead-aimable by mortar fire
		squad.activity = Unit.Activity.MOVING
		_set_retreat_profile(squad, Unit.Team.ENEMY)
		# A real assault doesn't send every element on the same axis — see
		# GameConfig.ENEMY_FLANK_CHANCE. Only takes effect once the squad
		# breaks from this scripted road march (_enemy_advance_objective is
		# never consulted before then); until then it marches with everyone
		# else like normal.
		if _enemy_rng.randf() < GameConfig.ENEMY_FLANK_CHANCE:
			squad.flanking_route_active = true
			squad.flank_waypoint_y = start_pos.y
		enemy_units.append(squad)

	for mortar_pos_m in GameConfig.enemy_mortar_positions_m(force_size.mortars):
		var em := _make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, mortar_pos_m * GameConfig.PIXELS_PER_METER)
		em.fire_timer = _enemy_rng.randf_range(0.0, em.fire_interval) # see the squad loop above
		# Cosmetic only: the field itself is currently vestigial, never read anywhere in the tier ladder
		# (see _mortar_should_relocate_for_safety's own doc comment) — but now that enemy mortars DO get
		# the same post-fire relocation instinct the player's own default doctrine implies, leaving this
		# set to false would actively mislead anyone reading it next.
		em.shoot_and_scoot = true
		_enemy_mortar_homes[em] = em.global_position
		_set_retreat_profile(em, Unit.Team.ENEMY)
		enemy_units.append(em)


func _set_retreat_profile(unit: Unit, team: Unit.Team) -> void:
	if team == Unit.Team.PLAYER:
		unit.retreat_speed = GameConfig.PLAYER_RETREAT_SPEED
		unit.retreat_target_x = GameConfig.PLAYER_SAFE_X
	else:
		unit.retreat_speed = GameConfig.ENEMY_RETREAT_SPEED
		unit.retreat_target_x = GameConfig.ENEMY_SAFE_X


func _make_unit(team: Unit.Team, kind: Unit.Kind, pos: Vector2) -> Unit:
	var unit := Unit.new()
	add_child(unit)
	unit.setup(team, kind, pos)
	if kind == Unit.Kind.DRONE:
		# A fresh Unit is spawned per sortie (see _launch_drone/_launch_
		# backup_drone), but only GameConfig.DRONE_FLEET_SIZE physical
		# airframes ever exist — an ever-incrementing serial would show
		# "Drone 7"/"Drone 8" on screen after enough shoot-downs and
		# relaunches, even though at most 4 are ever in the air or on the
		# ground at once. Reuse the lowest currently-free airframe number
		# instead.
		unit.unit_label += " %d" % _next_drone_number()
	elif team == Unit.Team.ENEMY and (kind == Unit.Kind.SQUAD or kind == Unit.Kind.MORTAR):
		pass # numbered later, in the order the player actually discovers it — see _assign_discovery_number
	else:
		var key := "%d:%d" % [team, kind]
		_unit_name_counts[key] = int(_unit_name_counts.get(key, 0)) + 1
		unit.unit_label += " %d" % _unit_name_counts[key]
	unit_combat_stats.register(unit)
	unit.fire_timer = randf_range(0.0, unit.fire_interval)
	unit.state_changed.connect(_on_any_unit_state_changed)
	return unit


## Direct user report: clicked "Retreat Now," the squads and mortar made it safely off, but the report
## window popped up the instant the player's own spotter was killed mid-retreat — before the player had
## any real chance to see it happen. Tracks whether a KILL (not a withdrawal or surrender) happened this
## tick, on EITHER side, so _end_battle can hold the battle's final frame on screen for a beat before the
## report covers it — see that function's own use of this flag for the actual delay.
func _on_any_unit_state_changed(unit: Unit) -> void:
	if unit.state == Unit.State.DESTROYED:
		_kill_happened_this_tick = true


## See _make_unit's own comment: a real airframe number (1..DRONE_FLEET_
## SIZE), not a monotonic launch serial. "In use" means any Drone Unit
## still in player_units — active, backup, or already turned for home but
## not yet landed/freed (see _update_returning_drones) — since that's
## exactly when its number is still legitimately on screen.
func _next_drone_number() -> int:
	var used: Dictionary = {}
	for u in player_units:
		if u.kind == Unit.Kind.DRONE:
			var parts: PackedStringArray = u.unit_label.split(" ")
			used[int(parts[parts.size() - 1])] = true
	for n in range(1, GameConfig.DRONE_FLEET_SIZE + 1):
		if not used.has(n):
			return n
	return GameConfig.DRONE_FLEET_SIZE + 1 # shouldn't happen; safe fallback


## Enemy squads/mortars are left unnumbered at spawn (see _make_unit) and
## get their real number here instead, the first time the PLAYER actually
## spots one — so "Enemy Squad 1" always means the first one the player
## ever found, never whichever one happened to spawn first in an order the
## player was never shown. Idempotent: only fires once per unit, gated by
## the plain "Squad"/"Mortar" label _make_unit leaves it with — called from
## _refresh_visibility right before that spotting is logged/drawn, so the
## very first "was spotted" line and the very first frame it's drawn on the
## map already show the assigned number, not a stale unnumbered one.
func _assign_discovery_number(unit: Unit) -> void:
	if unit.team != Unit.Team.ENEMY or (unit.kind != Unit.Kind.SQUAD and unit.kind != Unit.Kind.MORTAR):
		return
	if unit.unit_label != ("Squad" if unit.kind == Unit.Kind.SQUAD else "Mortar"):
		return # already numbered
	_enemy_discovery_counts[unit.kind] = int(_enemy_discovery_counts.get(unit.kind, 0)) + 1
	unit.unit_label += " %d" % _enemy_discovery_counts[unit.kind]


## Any enemy squad/mortar the player never once spotted live still needs a
## real number by the time the AAR or the (deliberately omniscient) Damage
## By Unit report names it — see _end_battle and UnitCombatStats' own doc
## comment. These get whatever numbers are left, in roster order, AFTER
## every genuinely player-discovered unit already has its own — there's no
## real "discovery order" for a unit nobody ever found, so this is just
## "next available," not a claim the player found it in this order.
func _number_remaining_undiscovered_enemies() -> void:
	for u in enemy_units:
		_assign_discovery_number(u)


## The commander's general retreat order: everyone still fighting pulls out
## immediately, to the best of their ability — they can still take casualties
## while withdrawing (see CombatResolver's moving-target rule). Not gated on
## a threshold; this is a direct command.
##
## `claimed` tracks where each unit processed so far in THIS order is
## already headed, on top of any other active unit's current position, so
## each successive one prefers a different patch of cover instead of every
## unit independently computing the same "nearest cover point" from a
## similar starting position — see Unit.order_retreat's own avoid_positions
## and _alert_enemy_squads, which needs the identical trick for the exact
## same reason (a whole side breaking at once).
##
## A squad (not the mortar or spotter/drone team — same restriction as the
## enemy commander's own version below) can surrender instead of actually
## attempting the retreat it's just been ordered into — see
## _squad_surrender_chance, which already weighs this far more heavily
## against a Ukrainian squad choosing to surrender to Russian forces than
## the reverse; this is the order actually landing on a friendly squad,
## not just the enemy's mirror of it.
## Polls + clears the one-shot wounded-evacuation flags order_retreat sets
## (see Unit._resolve_wounded_evacuation) and logs whichever one just
## happened — same established pattern as _log_hit_consequence's own
## sought_cover_logged/bolted_for_cover handling. Called right after every
## order_retreat() call site in this file, not just the threshold one,
## since a general-retreat order can trigger this exactly as much as an
## individual squad's own threshold can.
func _log_wounded_evacuation_outcome(unit: Unit) -> void:
	if unit.just_carried_wounded:
		unit.just_carried_wounded = false
		combat_log.log_wounded_carried(unit, unit.heavily_wounded_count)
	elif unit.just_abandoned_wounded:
		unit.just_abandoned_wounded = false
		combat_log.log_wounded_abandoned(unit, unit.wounded_left_behind_count)


## Toggled by the player's own pause control (BattleScreen) — not gated on
## battle_over the way order_general_retreat is, since pausing an already-
## finished battle is simply a no-op either way (there's nothing left for
## _process to do once battle_over is true regardless of is_paused).
func toggle_pause() -> void:
	is_paused = not is_paused


## ---------------------------------------------------------------------------
## The "fall back" order. Direct user request: "I want to be able to give any unit
## an order to 'fall back'. This does NOT have to mean to leave the map. It means the
## unit should evaluate where it might be safer than its current location, and move
## there. The orders can work similarly to the way they already work with the
## mortar." And: "The 'falling back' could even go forward if it thinks that is the
## safest direction." That first version (a search for the safest place anywhere, titled
## "Be safe") did not work well in use — squads told to do it with an enemy closing in
## did not move, and the usual time to give the order is when the area is about to be
## overrun — so the paradigm changed: "Fall back" "requires the unit to move towards the
## edge of the map, unless it is already very close. It does not require the unit to fall
## back off of the map. In general it should move 500-1000 meters, but it could go over
## that, or maybe slightly less if there is an excellent position say 400 meters back, but
## that should be rare. It does not have to be straight back. Just generally towards the
## edge." See _fall_back_destination.
##
## A one-shot order the commander can also countermand: while it stands, the unit
## walks to the position chosen when the order was given (the same choice
## _fall_back_destination would make now), the systems that would otherwise steer
## it stand back (_update_fall_back_orders re-asserts the walk after them every
## tick), and on arrival the order ends and the unit's ordinary behaviour resumes. A
## unit already very close to its edge refuses the order (and says so).
## Player units only: squads, the mortar, the spotter, the drone team.
## ---------------------------------------------------------------------------
var _fall_back_orders: Dictionary = {} # Unit -> {"destination": Vector2, "ordered_at": float}
## Units that have fallen back on order and arrived: Unit -> {"line_x": float}, the x of the
## place they fell back to. "A unit that has just fallen back per order should not then
## advance": from then on nothing may send such a unit forward of that line (a nudge of up
## to FALL_BACK_HOLD_TOLERANCE_M is allowed); sideways and further back are free ("if it
## wants to fall back further, that is ok"). See _advances_past_fall_back_line.
var _fallen_back: Dictionary = {}
## Player units that are retreating BECAUSE the commander ordered a general retreat (as opposed to
## having broken off on their own casualties): Unit -> {"gun_abandoned": bool, "retreat_speed":
## float}, what the unit had before the order changed it, so "Clear Orders" can put it back.
var _retreat_orders: Dictionary = {}
const FALL_BACK_HOLD_TOLERANCE_M: float = 40.0

## "Fall back" candidates (see _fall_back_destination): points this far (metres) out along
## bearings within FALL_BACK_BEARINGS_DEG of the direction of the unit's own map edge,
## plus the nearest cover to waypoints along that direction.
const FALL_BACK_RING_DISTANCES_M: Array[float] = [400.0, 500.0, 600.0, 750.0, 900.0, 1000.0, 1250.0, 1500.0]
const FALL_BACK_BEARINGS_DEG: Array[float] = [-60.0, -45.0, -30.0, -15.0, 0.0, 15.0, 30.0, 45.0, 60.0]
const FALL_BACK_COVER_WAYPOINTS_M: Array[float] = [500.0, 750.0, 1000.0]
const FALL_BACK_HIDDEN_SAMPLES: int = 4
## "It does not have to be straight back, just generally towards the edge": within
## FALL_BACK_PREFERRED_BEARING_DEG (45) of the edge direction costs nothing; between that and
## FALL_BACK_MAX_BEARING_DEG (60) it costs FALL_BACK_BEARING_PENALTY_PER_15_DEG per 15 degrees
## (0.5, about what an excellent position's cover and cleared line of sight are worth
## together, so a terrific spot can win but this is rare). The user: "in all cases it should
## be within a 60 degree angle. Never shallower than that ever" — so nothing past 60 degrees
## is ever used, however good it looks. JUDGMENT for the penalty, as the distance one is.
const FALL_BACK_PREFERRED_BEARING_DEG: float = 45.0
const FALL_BACK_BEARING_PENALTY_PER_15_DEG: float = 0.5
const FALL_BACK_MAX_BEARING_DEG: float = 60.0
## The distance the user asked for: "in general 500-1000 meters, but it could go over that,
## or maybe slightly less if there is an excellent position say 400 meters back, but that
## should be rare." Inside the range costs nothing; short of it costs FALL_BACK_SHORT_PENALTY
## per 100 m (about what a good position's cover and cleared line of sight are worth
## together, so only an excellent one at 400 m wins), beyond it FALL_BACK_LONG_PENALTY.
## JUDGMENT. Never less than FALL_BACK_MIN_MOVE_M unless the edge is nearer than that.
const FALL_BACK_PREFERRED_MIN_M: float = 500.0
const FALL_BACK_PREFERRED_MAX_M: float = 1000.0
const FALL_BACK_SHORT_PENALTY_PER_100M: float = 0.5
const FALL_BACK_LONG_PENALTY_PER_100M: float = 0.15
const FALL_BACK_MIN_MOVE_M: float = 250.0
## A unit this close to its edge (or closer) is "already very close" and does not move.
const FALL_BACK_EDGE_CLOSE_M: float = 200.0
## An enemy squad that is visible and on the move is projected RETREAT_ADVANCE_PROJECTION_TIME
## ahead along its heading; a place within this distance of where it will be is unsafe in
## proportion (FALL_BACK_ADVANCE_WEIGHT at the projected point itself, fading to nothing at
## this range). Its weapon range plus room to spare. JUDGMENT.
const FALL_BACK_ADVANCE_REACH: float = 600.0 * GameConfig.PIXELS_PER_METER
const FALL_BACK_ADVANCE_WEIGHT: float = 2.0
## Weight of the summed closeness of ALL known enemies (each fading to nothing at
## SQUAD_DANGER_RANGE) — a place with enemies on more than one side counts for more.
const FALL_BACK_PRESSURE_WEIGHT: float = 0.5


func set_fall_back_order(unit: Unit, enabled: bool) -> bool:
	if battle_over or unit == null or unit.team != Unit.Team.PLAYER or not (unit.kind in ORDERABLE_KINDS):
		return false
	if not enabled:
		if not _fall_back_orders.has(unit):
			return false
		_fall_back_orders.erase(unit)
		if unit.kind == Unit.Kind.MORTAR:
			_clear_mortar_move(unit)
		else:
			unit.has_move_target = false
			unit.move_queue.clear()
			unit.activity = Unit.Activity.STATIONARY
		combat_log.add_entry("--- %s: order to fall back cancelled ---" % unit.display_name())
		return true
	if unit.state != Unit.State.ACTIVE:
		return false
	if _fall_back_orders.has(unit):
		return true
	var destination: Vector2 = _fall_back_destination(unit)
	if is_inf(destination.x):
		combat_log.add_entry("--- %s ordered to fall back, but is already at the edge of the map ---" % unit.display_name())
		return false
	_fall_back_orders[unit] = {"destination": destination, "ordered_at": scenario_elapsed_time}
	_issue_fall_back_move(unit, destination)
	unit.last_order_reason = "Ordered to fall back toward the map edge."
	combat_log.add_entry("--- %s ordered to fall back ---" % unit.display_name())
	return true


## Player units that are still under an order the commander gave: falling back (on the way or held
## where it fell back to), retreating on the general-retreat order, or a mortar under the squad-fire
## order. "Clear Orders" cancels exactly these; it is grayed out when there are none.
func units_under_orders() -> Array[Unit]:
	var out: Array[Unit] = []
	for unit in player_units:
		if unit.state == Unit.State.ACTIVE and (_fall_back_orders.has(unit) or _fallen_back.has(unit) or _mortar_squad_fire_orders.has(unit)):
			out.append(unit)
		elif unit.state == Unit.State.RETREATING and _retreat_orders.has(unit):
			out.append(unit)
	return out


func has_orders_to_clear() -> bool:
	return not battle_over and not units_under_orders().is_empty()


## The "Clear Orders" button: every order the commander has given is cancelled. A unit that was falling
## back stops where it is and is free to advance again; one that fell back is no longer held; a unit
## retreating on the general-retreat order is back in the fight, with its own decisions its own again
## (it may well decide to retreat anyway, on its casualties or under fire); a mortar's squad-fire order
## is dropped. Units that have already left the field (withdrawn, lost, surrendered) stay gone.
## Returns how many units had an order cleared.
func clear_all_orders() -> int:
	if battle_over:
		return 0
	var cleared: Array[Unit] = units_under_orders()
	for unit in cleared:
		var stops_moving: bool = _fall_back_orders.has(unit)
		var reason_ends: bool = stops_moving or _fallen_back.has(unit)
		if unit.state == Unit.State.RETREATING:
			var before: Dictionary = _retreat_orders[unit]
			unit.state = Unit.State.ACTIVE
			unit.mortar_gun_abandoned = before.gun_abandoned
			unit.retreat_speed = before.retreat_speed
			unit.state_changed.emit(unit)
			stops_moving = true
			reason_ends = true
		if stops_moving:
			if unit.kind == Unit.Kind.MORTAR:
				_clear_mortar_move(unit)
			else:
				unit.has_move_target = false
				unit.move_queue.clear()
				unit.activity = Unit.Activity.STATIONARY
		if reason_ends:
			unit.last_order_reason = "Orders cleared."
	_fall_back_orders.clear()
	_fallen_back.clear()
	_retreat_orders.clear()
	_mortar_squad_fire_orders.clear()
	player_general_retreat_ordered = false
	if not cleared.is_empty():
		combat_log.add_entry("--- Orders cleared (%d unit%s) ---" % [cleared.size(), "" if cleared.size() == 1 else "s"])
	return cleared.size()


## The "Fall Back" button: every player unit that can be ordered to (see set_fall_back_order) is.
## Returns how many now have the order (including any that already did).
func order_all_fall_back() -> int:
	var ordered := 0
	for unit in player_units:
		if unit.state == Unit.State.ACTIVE and unit.kind in ORDERABLE_KINDS and set_fall_back_order(unit, true):
			ordered += 1
	return ordered


func fall_back_ordered(unit: Unit) -> bool:
	return _fall_back_orders.has(unit)


func _issue_fall_back_move(unit: Unit, destination: Vector2) -> void:
	if unit.kind == Unit.Kind.MORTAR:
		_issue_mortar_move(unit, destination, GameConfig.MORTAR_RELOCATE_SPEED_URGENT, "fall_back")
		return
	unit.move_target = destination
	unit.has_move_target = true
	unit.move_queue.clear()
	unit.move_speed = unit.retreat_speed if unit.retreat_speed > 0.0 else GameConfig.REPOSITION_SPEED
	unit.movement_predictable = false


## Where "fall back" sends `unit`: generally toward its own edge of the map, usually
## 500-1000 m, or Vector2.INF if it is already very close to that edge (or no place fits).
## Not a straight run: candidates lie within FALL_BACK_MAX_BEARING_DEG of the edge
## direction — a ring of them at several distances and bearings, plus the nearest cover to
## a few waypoints along the way and a few hidden spots — and the best by _fall_back_score
## (safety: cover, cleared lines of sight, distance from the enemy and from where advancing
## enemies will be) plus penalties for straying from the preferred 500-1000 m
## (_fall_back_distance_penalty) and from within 45 degrees of the edge direction
## (_fall_back_bearing_penalty) wins. A unit nearer its edge than that goes as far as the
## edge allows. Nothing here is ever a retreat off the map: the edge is only the direction.
func _fall_back_destination(unit: Unit) -> Vector2:
	# The unit's own edge: the line a retreat runs to (a spawned unit's retreat_target_x).
	var edge_x: float = GameConfig.PLAYER_SAFE_X if unit.team == Unit.Team.PLAYER else GameConfig.ENEMY_SAFE_X
	var remaining: float = absf(edge_x - unit.global_position.x)
	if remaining < FALL_BACK_EDGE_CLOSE_M * GameConfig.PIXELS_PER_METER:
		return Vector2.INF
	var edge_dir := Vector2(signf(edge_x - unit.global_position.x), 0.0)
	# A drone has no weapon: it is no threat to walk away from.
	var known: Array[Vector2] = _known_enemy_positions(unit.team, false)
	var advancing: Array[Vector2] = _advancing_enemy_projections(unit.team)
	var threats: Array[Vector2] = known.duplicate()
	threats.append_array(advancing)
	var raw: Array[Vector2] = []
	for distance_m in FALL_BACK_RING_DISTANCES_M:
		for bearing in FALL_BACK_BEARINGS_DEG:
			raw.append(unit.global_position + edge_dir.rotated(deg_to_rad(bearing)) * distance_m * GameConfig.PIXELS_PER_METER)
	var allies: Array[Vector2] = _ally_positions_for(unit)
	for distance_m in FALL_BACK_COVER_WAYPOINTS_M:
		var waypoint: Vector2 = unit.global_position + edge_dir * distance_m * GameConfig.PIXELS_PER_METER
		raw.append(GameConfig.nearest_cover_point(waypoint, 0.0, unit.kind == Unit.Kind.MORTAR, allies, threats, [], [], Vector2.ZERO, Vector2.INF, Vector2.INF, _keeps_clear_of_populated(unit)))
	for i in FALL_BACK_HIDDEN_SAMPLES:
		raw.append(_hidden_point_for(unit, threats))
	var min_move: float = minf(FALL_BACK_MIN_MOVE_M * GameConfig.PIXELS_PER_METER, remaining)
	var best := Vector2.INF
	var best_score := INF
	for candidate in raw:
		# Never past the edge itself, whatever the ring said.
		var point := GameConfig.clamp_to_operating_area(candidate)
		point.x = maxf(point.x, edge_x) if edge_dir.x < 0.0 else minf(point.x, edge_x)
		var offset: Vector2 = point - unit.global_position
		if offset.length() < min_move:
			continue
		var bearing: float = rad_to_deg(acos(clampf(offset.normalized().dot(edge_dir), -1.0, 1.0)))
		if bearing > FALL_BACK_MAX_BEARING_DEG + 0.01:
			continue
		if GameConfig.is_river_at(point) or (unit.kind == Unit.Kind.MORTAR and GameConfig.mortar_barred_at(point, unit.team)):
			continue
		var score: float = _fall_back_score(unit, point, known, advancing) \
			+ _fall_back_distance_penalty(offset.length() / GameConfig.PIXELS_PER_METER, remaining / GameConfig.PIXELS_PER_METER) \
			+ _fall_back_bearing_penalty(bearing)
		if score < best_score:
			best_score = score
			best = point
	return best


## What straying from the edge direction costs (see FALL_BACK_PREFERRED_BEARING_DEG):
## `bearing_deg` is the angle between the way to the candidate and the way to the edge.
func _fall_back_bearing_penalty(bearing_deg: float) -> float:
	return FALL_BACK_BEARING_PENALTY_PER_15_DEG * maxf(0.0, bearing_deg - FALL_BACK_PREFERRED_BEARING_DEG) / 15.0


## What straying from the preferred distance costs (see FALL_BACK_PREFERRED_MIN_M):
## `distance_m` is how far the candidate is, `remaining_m` how far the unit's edge is (a
## unit nearer than the preferred minimum is not penalised for being unable to go it).
func _fall_back_distance_penalty(distance_m: float, remaining_m: float) -> float:
	var preferred_min: float = minf(FALL_BACK_PREFERRED_MIN_M, remaining_m)
	if distance_m < preferred_min:
		return FALL_BACK_SHORT_PENALTY_PER_100M * (preferred_min - distance_m) / 100.0
	if distance_m > FALL_BACK_PREFERRED_MAX_M:
		return FALL_BACK_LONG_PENALTY_PER_100M * (distance_m - FALL_BACK_PREFERRED_MAX_M) / 100.0
	return 0.0


## How exposed `unit` would be at `point`; lower is safer. Dominant: the forecast chance
## of being hit or lost from the enemies it can see or has heard (_risk_forecast, x100).
## Then, since most threats are not currently visible: each KNOWN enemy position (last
## seen) that could see the point in range counts a little, standing in the open counts
## something, and closeness to the known enemies counts (SUMMED over all of them, so
## enemies on several sides add up rather than only the nearest mattering). Weighted
## heavily: an enemy squad that is ADVANCING — the forecast and the known positions are
## all where it is now, so an enemy on its way in from beyond weapon range looks harmless
## until it arrives; `advancing` (see _advancing_enemy_projections) are where such squads
## will be, and a place close to one is penalised (FALL_BACK_ADVANCE_WEIGHT, fading out at
## FALL_BACK_ADVANCE_REACH). Distance travelled is not scored here (see
## _fall_back_distance_penalty).
func _fall_back_score(unit: Unit, point: Vector2, known: Array[Vector2], advancing: Array[Vector2] = []) -> float:
	var forecast: Dictionary = _risk_forecast(unit, null, point)
	var score: float = (forecast.loss_probability + forecast.hit_probability) * 100.0
	for p in advancing:
		var d_advance: float = point.distance_to(p)
		score += FALL_BACK_ADVANCE_WEIGHT * clampf(1.0 - d_advance / FALL_BACK_ADVANCE_REACH, 0.0, 1.0)
		score += FALL_BACK_PRESSURE_WEIGHT * clampf(1.0 - d_advance / GameConfig.SQUAD_DANGER_RANGE, 0.0, 1.0)
	for p in known:
		var d: float = point.distance_to(p)
		score += FALL_BACK_PRESSURE_WEIGHT * clampf(1.0 - d / GameConfig.SQUAD_DANGER_RANGE, 0.0, 1.0)
		if d <= GameConfig.SQUAD_ENGAGEMENT_RANGE and GameConfig.has_direct_los(p, point):
			score += 0.5
	if not GameConfig.is_in_cover(GameConfig.get_terrain_type_at(point)):
		score += 0.3
	return score


## Whether `unit` has fallen back on order and may not go forward, and `point` is forward of
## where it fell back to (by more than FALL_BACK_HOLD_TOLERANCE_M). Forward is toward the
## enemy: east for the player. Everything that picks a voluntary destination for a unit —
## cover-seeking, screening the mortar, the risk policy, the mortar hunting an enemy mortar —
## asks this, and _enforce_fall_back_hold cancels whatever slips through.
func _advances_past_fall_back_line(unit: Unit, point: Vector2) -> bool:
	if not _fallen_back.has(unit):
		return false
	var forward: float = 1.0 if unit.team == Unit.Team.PLAYER else -1.0
	return (point.x - _fallen_back[unit].line_x) * forward > FALL_BACK_HOLD_TOLERANCE_M * GameConfig.PIXELS_PER_METER


func fall_back_holding(unit: Unit) -> bool:
	return _fallen_back.has(unit)


## Run after every system that can steer a unit: a unit that has fallen back on order is not
## sent forward of where it fell back to by anything — a move (or the part of a queued route)
## that goes there is cancelled. Moves sideways or further back stand. The hold ends when the
## unit is no longer in action (a retreat, a loss); a fresh order to fall back further
## replaces it on arrival.
func _enforce_fall_back_hold() -> void:
	for unit in _fallen_back.keys():
		if not is_instance_valid(unit) or unit.state != Unit.State.ACTIVE:
			_fallen_back.erase(unit)
			continue
		if _fall_back_orders.has(unit) or not unit.has_move_target:
			continue
		if _advances_past_fall_back_line(unit, unit.move_target):
			if unit.kind == Unit.Kind.MORTAR:
				_clear_mortar_move(unit)
			else:
				unit.has_move_target = false
				unit.move_queue.clear()
				unit.activity = Unit.Activity.STATIONARY
			unit.last_order_reason = "Holding where it fell back to; not advancing."
			continue
		for i in unit.move_queue.size():
			if _advances_past_fall_back_line(unit, unit.move_queue[i]):
				unit.move_queue.resize(i)
				break


## Where each visible, active enemy squad that is on the move will be
## GameConfig.RETREAT_ADVANCE_PROJECTION_TIME from now, along its current heading (the same
## honest projection the retreat routing uses; a squad only known from an old sighting has
## no heading to project, and one already retreating is not advancing).
func _advancing_enemy_projections(team: Unit.Team) -> Array[Vector2]:
	var opposing: Array[Unit] = enemy_units if team == Unit.Team.PLAYER else player_units
	var points: Array[Vector2] = []
	for u in opposing:
		if u.kind != Unit.Kind.SQUAD or u.state != Unit.State.ACTIVE or not u.is_visible:
			continue
		var velocity: Vector2 = _estimate_unit_velocity(u)
		if velocity != Vector2.ZERO:
			points.append(u.global_position + velocity * GameConfig.RETREAT_ADVANCE_PROJECTION_TIME)
	return points


## Run after every system that can steer a unit (so what the next tick's movement
## acts on is this): ends an order whose unit has arrived, is no longer ACTIVE (a
## retreat, a loss) or was called off, and puts the unit back on its way if
## something else re-aimed it in the meantime.
func _update_fall_back_orders() -> void:
	for unit in _fall_back_orders.keys():
		if not is_instance_valid(unit) or unit.state != Unit.State.ACTIVE:
			_fall_back_orders.erase(unit)
			continue
		var destination: Vector2 = _fall_back_orders[unit].destination
		if unit.global_position.distance_to(destination) <= Unit.MOVE_ARRIVE_RADIUS * 1.5:
			_fall_back_orders.erase(unit)
			_fallen_back[unit] = {"line_x": unit.global_position.x}
			if unit.kind == Unit.Kind.MORTAR:
				_clear_mortar_move(unit)
			else:
				unit.has_move_target = false
				unit.move_queue.clear()
			combat_log.add_entry("--- %s has fallen back ---" % unit.display_name())
			continue
		var on_its_way: bool = unit.has_move_target and (unit.move_target.distance_to(destination) < 1.0 \
			or (not unit.move_queue.is_empty() and unit.move_queue[-1].distance_to(destination) < 1.0))
		if not on_its_way:
			_issue_fall_back_move(unit, destination)


## The commander's "expend ammo on enemy squads" order for one friendly
## mortar. It changes ONE thing: when the mortar's only candidates are
## squads, every hold-fire probability that would leave it doing nothing is
## scaled down by GameConfig.MORTAR_SQUAD_FIRE_ORDER_HOLD_FACTOR (see
## _mortar_squad_order_hold_factor). Which target is preferred is untouched
## - enemy mortars keep first priority, and squads keep their existing
## ranking - and with no order the mortar behaves exactly as it always did.
## Countermanded by calling this again with enabled=false. Player mortars
## only; also read by the drone pilot (_squad_fire_order_watch_target).
func set_mortar_squad_fire_order(mortar: Unit, enabled: bool) -> void:
	if battle_over or mortar == null or mortar.kind != Unit.Kind.MORTAR or mortar.team != Unit.Team.PLAYER:
		return
	if enabled == _mortar_squad_fire_orders.has(mortar):
		return
	if enabled:
		_mortar_squad_fire_orders[mortar] = true
		combat_log.add_entry("--- %s ordered to expend ammunition on enemy squads ---" % mortar.display_name())
	else:
		_mortar_squad_fire_orders.erase(mortar)
		combat_log.add_entry("--- %s: order to expend ammunition on enemy squads cancelled ---" % mortar.display_name())


func mortar_squad_fire_ordered(mortar: Unit) -> bool:
	return _mortar_squad_fire_orders.has(mortar)


## Multiplier on a hold-fire probability: 1.0 (no change) unless `mortar`
## holds the squad-fire order AND `squads_only` (no enemy mortar among its
## candidates - an enemy mortar shot is never ammo-gated by this order; it
## is only about "a squad or nothing").
func _mortar_squad_order_hold_factor(mortar: Unit, squads_only: bool = true) -> float:
	if squads_only and _mortar_squad_fire_orders.has(mortar) and mortar.state == Unit.State.ACTIVE:
		return GameConfig.MORTAR_SQUAD_FIRE_ORDER_HOLD_FACTOR
	return 1.0


const UNIT_CLICK_RADIUS: float = 18.0
## The friendly unit kinds a commander can give orders to: everything on the ground.
## (Drones fly a mission of their own and a resupply run is not one of ours to steer.)
const ORDERABLE_KINDS: Array = [Unit.Kind.SQUAD, Unit.Kind.MORTAR, Unit.Kind.SPOTTER, Unit.Kind.DRONE_TEAM]


## Shows the range circle of a mortar while the mouse is over it: the player's own (as the setup screen shows it), and an enemy's while the
## player can see it (an unseen mortar's position is not known, so hovering where it stands shows nothing). `world_pos` is the mouse in map
## space, `mouse_in_map` false when the mouse is over something else (the sidebar), which hides every circle.
func update_hover(world_pos: Vector2, mouse_in_map: bool = true) -> void:
	for u in player_units + enemy_units:
		if u.kind != Unit.Kind.MORTAR:
			continue
		var known: bool = u.team == Unit.Team.PLAYER or u.is_visible
		var hovered: bool = mouse_in_map and known and u.state == Unit.State.ACTIVE and u.global_position.distance_to(world_pos) <= UNIT_CLICK_RADIUS
		if u.show_range_ring != hovered:
			u.show_range_ring = hovered
			u.queue_redraw()


## The friendly mortar (ACTIVE, player) within a small click radius of
## `world_pos`, or null.
func unit_at(world_pos: Vector2) -> Unit:
	var best: Unit = null
	var best_d := UNIT_CLICK_RADIUS
	for u in player_units:
		if u.state != Unit.State.ACTIVE or not (u.kind in ORDERABLE_KINDS):
			continue
		var d: float = u.global_position.distance_to(world_pos)
		if d <= best_d:
			best_d = d
			best = u
	return best


## A left click on a friendly unit that can take orders (a squad, the mortar,
## the spotter, the drone team) opens its orders card.
func handle_click(world_pos: Vector2) -> Unit:
	if battle_over:
		return null
	var u: Unit = unit_at(world_pos)
	if u != null:
		unit_selected.emit(u)
	return u


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		handle_click(get_global_mouse_position())


func order_general_retreat() -> void:
	if battle_over:
		return
	player_general_retreat_ordered = true
	var known_enemy_positions := _known_enemy_positions_for_retreat(Unit.Team.PLAYER)
	var any_ordered := false
	var claimed: Array[Vector2] = []
	# The mortar retreats FIRST, ahead of every squad — a real, previously-
	# reported failure mode: player_units lists squads before the mortar
	# (see _spawn_player_units), so plain iteration order let every squad
	# claim the best nearby safe cover before the mortar ever got a turn,
	# leaving the single highest-priority asset to protect pushed onto
	# whatever was left over — however far or disconnected that happened
	# to be. `claimed` still works exactly as before either way; only the
	# ORDER units draw from it changes.
	var retreat_order: Array[Unit] = player_units.filter(func(u): return u.kind == Unit.Kind.MORTAR) \
		+ player_units.filter(func(u): return u.kind != Unit.Kind.MORTAR)
	for unit in retreat_order:
		if unit.state == Unit.State.ACTIVE:
			if unit.kind == Unit.Kind.SQUAD and randf() < _squad_surrender_chance(unit):
				unit.state = Unit.State.SURRENDERED
				unit.state_changed.emit(unit)
				combat_log.log_squad_surrendered(unit)
				any_ordered = true
				continue
			var before := {"gun_abandoned": unit.mortar_gun_abandoned, "retreat_speed": unit.retreat_speed}
			unit.order_retreat(known_enemy_positions, _ally_positions_for(unit) + claimed, "The commander ordered a general retreat.")
			if unit.state == Unit.State.RETREATING:
				_retreat_orders[unit] = before
			claimed.append(unit.move_target if unit.has_move_target else unit.global_position)
			combat_log.log_ordered_retreat(unit)
			_log_wounded_evacuation_outcome(unit)
			any_ordered = true
			# A resupply run still just a scheduled wave time (see
			# _mortar_resupply/_update_mortar_resupply) hasn't actually left
			# the rear yet — nothing physical to recall, just a request to
			# cancel. A run that's ALREADY a real Unit on the map is left
			# alone; that's a separate, already-in-motion trip, not
			# something this handles (the mortar's own retreat state
			# already keeps _update_mortar_resupply_requests from asking
			# for a fresh one afterward — see that function's own ACTIVE
			# gate).
			if unit.kind == Unit.Kind.MORTAR and _mortar_resupply.has(unit):
				_mortar_resupply.erase(unit)
				if _should_narrate_mortar_logistics(unit):
					combat_log.log_mortar_resupply_cancelled(unit)
	if any_ordered:
		combat_log.add_entry("--- General retreat ordered ---")


## The enemy commander's mirror of the player's own general-retreat button —
## except nobody presses it; it fires automatically once the attack as a
## whole looks hopeless (see _enemy_situation_hopeless). This is a top-down,
## whole-force judgment, distinct from a single squad's own bottom-up
## casualty threshold (Unit._check_retreat) — a squad personally still in
## decent shape can still get pulled back here if the attack overall has
## clearly failed. One-shot per battle, checked every tick.
##
## SQUADS only — mortars are deliberately left out HERE. Calling off the
## infantry assault doesn't mean abandoning fire support while there's
## still an infantry fight to support: a mortar sitting well to the rear
## isn't at risk of being overrun the way forward squads are, and a real
## commander keeps supporting fires going (harassing the enemy, covering
## the withdrawal, still hunting for counter-battery range on the
## opposing mortar) rather than pulling a perfectly good gun out of action
## for no tactical reason — AS LONG AS some squad is still out there
## fighting or withdrawing for the mortar to actually be supporting. Once
## that stops being true — see _check_enemy_mortar_isolated_retreat, this
## function's own companion check — the mortar retreats too. A mortar
## still retreats on its own if it's personally hit (Unit.
## _apply_crew_casualties) regardless of either check — this just means
## the infantry giving up doesn't AUTOMATICALLY drag it along too, not
## that it never will.
##
## The log banner states the actual casualty percentage that triggered
## this — no guessing after the fact why the retreat happened.
##
## Not every squad actually attempts the retreat it's just been ordered
## into — see _squad_surrender_chance. A squad that rolls to surrender
## instead never gets an order_retreat call at all (so it's excluded from
## `claimed`/_ally_positions_for going forward, same as any other unit no
## longer ACTIVE) and counts toward the log banner just as much as one
## that actually pulls back does.
func _check_enemy_commander_retreat() -> void:
	if enemy_general_retreat_ordered or battle_over:
		return
	if not _enemy_situation_hopeless():
		return
	enemy_general_retreat_ordered = true
	var known_player_positions := _known_enemy_positions(Unit.Team.ENEMY)
	var claimed: Array[Vector2] = []
	for unit in enemy_units:
		if unit.kind == Unit.Kind.SQUAD and unit.state == Unit.State.ACTIVE:
			if randf() < _squad_surrender_chance(unit):
				unit.state = Unit.State.SURRENDERED
				unit.state_changed.emit(unit)
				combat_log.log_squad_surrendered(unit)
				continue
			unit.order_retreat(known_player_positions, _ally_positions_for(unit) + claimed, "The enemy commander ordered a general retreat.")
			claimed.append(unit.move_target if unit.has_move_target else unit.global_position)
			combat_log.log_ordered_retreat(unit)
			_log_wounded_evacuation_outcome(unit)
	# No banner for the enemy commander's decision: the player cannot see it. Squads that are
	# seen pulling back are logged one by one above (CombatLog only logs enemies that are seen).


## The companion this function's own doc comment refers to: the squads-
## only exemption above only makes tactical sense while there's an actual
## infantry fight for the mortar to be supporting. Checked independently
## of enemy_general_retreat_ordered/_enemy_situation_hopeless — a real,
## previously-reported gap this closes: enemy squads can also retreat one
## at a time on their own individual casualty threshold (Unit.
## _check_retreat), not just all at once via the top-down hopeless
## trigger above, and a force can lose every squad this gradual way
## without the WHOLE force's casualty percentage ever crossing
## _enemy_commander_retreat_threshold (mortars, undamaged, can keep the
## overall percentage low even once every squad is gone) — in which case
## _check_enemy_commander_retreat would never fire at all, and the mortar
## would otherwise keep fighting alone indefinitely with nothing left to
## support. One-shot per battle, checked every tick, right after the
## function above so a mass retreat that empties the squad roster in one
## pass triggers this the very same tick rather than waiting a full turn
## for the newly-RETREATING squads to register as inactive.
##
## ACTIVE squads specifically, not "any squad still on the field" — a
## RETREATING squad has already broken off and is trying to escape, not
## fighting or covering anyone; it provides no more real screen for the
## mortar than one that's already destroyed or surrendered.
##
## Requires at least one SQUAD to have existed in `enemy_units` at all —
## an enemy force that never fielded any infantry in the first place
## (a mortar-only doctrine, or a test harness scenario built around an
## isolated mortar target) has nothing to have "lost," so there's no real
## isolation event to react to; without this check this fired instantly,
## every single tick one, for any such roster, since "zero ACTIVE squads"
## was trivially true from the very first frame.
func _check_enemy_mortar_isolated_retreat() -> void:
	if enemy_mortar_isolated_retreat_ordered or battle_over:
		return
	var any_squad_ever := false
	for u in enemy_units:
		if u.kind == Unit.Kind.SQUAD:
			any_squad_ever = true
			if u.state == Unit.State.ACTIVE:
				return
	if not any_squad_ever:
		return
	var any_mortar_active := false
	for u in enemy_units:
		if u.kind == Unit.Kind.MORTAR and u.state == Unit.State.ACTIVE:
			any_mortar_active = true
			break
	if not any_mortar_active:
		return
	enemy_mortar_isolated_retreat_ordered = true
	var known_player_positions := _known_enemy_positions(Unit.Team.ENEMY)
	var claimed: Array[Vector2] = []
	for unit in enemy_units:
		if unit.kind == Unit.Kind.MORTAR and unit.state == Unit.State.ACTIVE:
			unit.order_retreat(known_player_positions, _ally_positions_for(unit) + claimed, "No enemy squad left fighting — the mortar pulls back too.")
			claimed.append(unit.move_target if unit.has_move_target else unit.global_position)
			combat_log.log_ordered_retreat(unit)
	# (No banner: the player cannot see the enemy's decision, only mortars it happens to see moving.)


## Whether a squad just ordered to retreat surrenders in place instead —
## a random roll, not a fixed rule (a squad in a bad spot might still try
## its luck; one in a decent spot might still lose its nerve, just less
## often). Works for either side's squads, since either commander's general
## retreat can now trigger this (order_general_retreat /
## _check_enemy_commander_retreat) — "opposing" and "own side" below just
## flip based on `squad.team`.
##
## MULTIPLICATIVE, not additive: how deep in danger the squad already is
## (proximity to the nearest active OPPOSING unit, on the deliberately
## tight GameConfig.SURRENDER_POSITION_RANGE) is the real gate — with no
## genuine proximate threat, the chance is exactly zero, full stop, no
## matter how isolated the squad is. Isolation (proximity to the nearest
## other active SQUAD on its OWN side specifically — a supporting mortar
## well to the rear doesn't help a squad about to be overrun) only
## AMPLIFIES that danger once it's real: "surrounded" is what actually
## pushes a squad over the edge, not merely "alone." No opposing units
## left at all counts as zero danger (not a lucky escape from an
## undefined case); no other own-side squad left anywhere counts as
## maximum isolation.
##
## The result is then scaled by GameConfig.SURRENDER_WILLINGNESS_
## MULTIPLIER_PLAYER/_ENEMY before the shared SURRENDER_MAX_CHANCE cap —
## deliberately NOT the same multiplier for both sides. This is the war in
## Ukraine: credible, extensively documented reporting (UN and Human
## Rights Watch monitoring among it) describes systematic mistreatment of
## Ukrainian POWs in Russian custody. A Ukrainian squad in a hopeless spot
## has real, well-founded reasons the enemy simply doesn't share to keep
## fighting or trying to get out rather than lay down arms — this isn't
## modeled as ordinary, symmetric battlefield reluctance.
func _squad_surrender_chance(squad: Unit) -> float:
	var opposing: Array[Unit] = enemy_units if squad.team == Unit.Team.PLAYER else player_units
	var own_side: Array[Unit] = player_units if squad.team == Unit.Team.PLAYER else enemy_units

	var nearest_opposing_dist := INF
	for o in opposing:
		if o.state == Unit.State.ACTIVE:
			nearest_opposing_dist = min(nearest_opposing_dist, squad.global_position.distance_to(o.global_position))
	var position_badness: float = 0.0 if is_inf(nearest_opposing_dist) \
		else clamp(1.0 - nearest_opposing_dist / GameConfig.SURRENDER_POSITION_RANGE, 0.0, 1.0)

	var nearest_ally_dist := INF
	for u in own_side:
		if u != squad and u.kind == Unit.Kind.SQUAD and u.state == Unit.State.ACTIVE:
			nearest_ally_dist = min(nearest_ally_dist, squad.global_position.distance_to(u.global_position))
	var isolation_badness: float = 1.0 if is_inf(nearest_ally_dist) \
		else clamp(nearest_ally_dist / GameConfig.SURRENDER_ISOLATION_RANGE, 0.0, 1.0)

	var isolation_multiplier: float = GameConfig.SURRENDER_ISOLATION_BASE_FACTOR + GameConfig.SURRENDER_ISOLATION_AMPLIFIER * isolation_badness
	var chance: float = position_badness * isolation_multiplier
	var willingness: float = GameConfig.SURRENDER_WILLINGNESS_MULTIPLIER_PLAYER if squad.team == Unit.Team.PLAYER else GameConfig.SURRENDER_WILLINGNESS_MULTIPLIER_ENEMY
	return clamp(chance * willingness, 0.0, GameConfig.SURRENDER_MAX_CHANCE)


## Judged against the WHOLE enemy force's casualties (pips lost across every
## enemy squad and mortar), not any single unit's own threshold — a
## commander sees the overall picture, not just one squad's casualty count.
func _enemy_situation_hopeless() -> bool:
	var stats := _compute_side_stats(enemy_units)
	return stats.casualty_percent / 100.0 >= _enemy_commander_retreat_threshold


## Currently-visible enemy positions, from `team`'s point of view — "some
## idea where the enemy is" for the spotter's smarter retreat routing (see
## Unit.order_retreat), and for every other threat-avoidance decision that
## consumes this (cover-point selection, the friendly mortar's hunt-route
## concealment, an advancing enemy squad's own concealment/danger scoring —
## see _friendly_mortar_hunt_point, _score_advance_candidate). Only live-
## visible units count, matching the rest of the game's live-visibility
## model — not a permanent memory of everywhere the enemy has ever been
## seen. ACTIVE or RETREATING only — a SURRENDERED unit has laid down its
## arms in place and a WITHDRAWN one has left the field entirely; neither
## poses any actual threat any more, so nothing should route around, hide
## from, or flee one the way it would a real, still-armed contact. This
## deliberately does NOT mean "currently is_visible" for EITHER side — it
## means "what that side's own knowledge actually is," same standard as
## Unit.player_known_position/_has_been_sighted for the player and Unit.
## enemy_known_position/_has_been_sighted for the enemy (see their own doc
## comments and _update_player_intel/_update_enemy_intel). A contact
## spotted moments ago and now merely out of direct line-of-sight hasn't
## un-happened just because the visibility flag flickered off; a retreat
## or cover choice built on strict real-time visibility alone can walk
## straight into (or right past) a threat that side already has every
## reason to remember is there.
##
## Used to be asymmetric — the ENEMY side read plain, real-time is_visible
## with no persistent memory at all, reasoned at the time as "the fog-of-
## war model is deliberately one-directional." Direct user correction,
## after that asymmetry was traced as the actual cause of a real,
## live-reported bug (a friendly mortar abandoning the gun after a single
## light wound, while an enemy mortar with a badly reduced crew never
## registered a nearby threat at all and kept fighting): this project's
## own stated knowledge-locality principle never actually called for a
## ONE-DIRECTIONAL model — an enemy unit forgetting a contact the instant
## line-of-sight breaks isn't "enemy behavior may reasonably differ" (a
## different decision-making style, doctrine, or objective — see this
## project's own established distinction for what that principle actually
## covers), it's a real gap in what the enemy is even capable of knowing
## at all. Now genuinely symmetric.
func _known_enemy_positions(team: Unit.Team, include_drones: bool = true, include_spotters: bool = true) -> Array[Vector2]:
	var opposing: Array[Unit] = enemy_units if team == Unit.Team.PLAYER else player_units
	var positions: Array[Vector2] = []
	for u in opposing:
		var still_a_threat: bool = u.state == Unit.State.ACTIVE or u.state == Unit.State.RETREATING
		if not still_a_threat:
			continue
		if u.kind == Unit.Kind.DRONE and not include_drones:
			continue
		if u.kind == Unit.Kind.SPOTTER and not include_spotters:
			continue
		if team == Unit.Team.PLAYER:
			if u.player_has_been_sighted:
				positions.append(u.player_known_position)
		else:
			if u.enemy_has_been_sighted:
				positions.append(u.enemy_known_position)
	return positions


## _known_enemy_positions plus a projected point for every currently-
## VISIBLE, currently-moving opposing unit — see GameConfig.RETREAT_
## ADVANCE_PROJECTION_TIME's own doc comment for the real gap this closes
## (a retreat route picked by _exclude_dangerous only ever looking at
## where an enemy IS, not where it's clearly headed). Only ever
## extrapolates a unit that's actually visible right now — is_visible,
## not just player_has_been_sighted/player_known_position — since
## _estimate_unit_velocity reads that unit's real, current heading, and a
## unit only known via a stale sighting has no honest heading to read at
## all (this deliberately does NOT peek at a not-currently-visible
## enemy's live velocity; that would be reading information this side
## doesn't actually have). Used specifically for retreat-route safety —
## not swapped in for every _known_enemy_positions call site, since most
## of those want a plain, current snapshot (a threat-range check, a
## target-priority score), not a forward projection.
func _known_enemy_positions_for_retreat(team: Unit.Team) -> Array[Vector2]:
	var positions := _known_enemy_positions(team)
	var opposing: Array[Unit] = enemy_units if team == Unit.Team.PLAYER else player_units
	for u in opposing:
		if u.state != Unit.State.ACTIVE and u.state != Unit.State.RETREATING:
			continue
		if not u.is_visible:
			continue
		var velocity: Vector2 = _estimate_unit_velocity(u)
		if velocity == Vector2.ZERO:
			continue
		positions.append(u.global_position + velocity * GameConfig.RETREAT_ADVANCE_PROJECTION_TIME)
	return positions


## Other ACTIVE units on `unit`'s own side (never `unit` itself) — used both
## to steer a squad's own cover choice away from an ally already there (see
## Unit.seek_cover's avoid_positions) and to find a bunched-up neighbor a
## stray hit might spread to (see _bunched_ally).
func _ally_units_for(unit: Unit) -> Array[Unit]:
	var same_team: Array[Unit] = enemy_units if unit.team == Unit.Team.ENEMY else player_units
	var out: Array[Unit] = []
	for u in same_team:
		if u != unit and u.state == Unit.State.ACTIVE:
			out.append(u)
	return out


## Where `unit`'s allies are, and where the squads among them are going: a squad on its way to a cover patch holds it as much as one standing
## in it, so a second squad choosing cover sees the destination too (two squads walked to the same tree patch and arrived 10 m apart).
func _ally_positions_for(unit: Unit) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for u in _ally_units_for(unit):
		out.append(u.global_position)
		if u.kind == Unit.Kind.SQUAD and u.has_move_target and u.move_target.distance_to(u.global_position) > Unit.MOVE_ARRIVE_RADIUS:
			out.append(u.move_target)
	return out


## Other ACTIVE same-team mortars' own positions — fed into GameConfig.
## nearest_hidden_point/_mortar_advance_point as `bunch_avoid_positions`
## so a mortar relocating or hunting tries hard not to end up close
## enough to a sibling that a single counter-battery strike could catch
## both (see MORTAR_BUNCHING_AVOIDANCE_RADIUS's own doc comment for the
## real cited standard). A sibling's own PENDING destination counts here,
## not just its current position — `_update_mortar_decisions` runs every
## active mortar's own decision once per tick in a fixed order, so
## without this, two mortars deciding to relocate the SAME tick would
## each only see the OTHER's stale pre-decision position and could still
## converge on nearby destinations despite each individually "avoiding"
## the other's old spot. Narrower than _ally_positions_for on purpose —
## a mortar has no real reason to keep its distance from a friendly squad
## the way it does from another mortar (a squad isn't a comparably
## attractive counter-battery target).
func _sibling_mortar_positions(mortar: Unit) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for u in _ally_units_for(mortar):
		if u.kind != Unit.Kind.MORTAR:
			continue
		out.append(u.move_target if u.has_move_target else u.global_position)
	return out


## Raises a squad's suppression by `amount` (to at most 1). Only squads are suppressed. See GameConfig.SUPPRESSION_*.
func _add_suppression(unit: Unit, amount: float) -> void:
	if unit.kind != Unit.Kind.SQUAD or (unit.state != Unit.State.ACTIVE and unit.state != Unit.State.RETREATING):
		return
	unit.suppression = minf(unit.suppression + amount, 1.0)


## A mortar round has landed at `point`: every squad within SUPPRESSION_BLAST_RADIUS_M of it, on either side, is suppressed, more the nearer it
## landed. Whatever the round did to the unit it was aimed at, and whether or not that unit was in range.
func _suppress_from_blast(point: Vector2) -> void:
	var radius_px: float = GameConfig.SUPPRESSION_BLAST_RADIUS_M * GameConfig.PIXELS_PER_METER
	for u in player_units + enemy_units:
		if u.kind != Unit.Kind.SQUAD:
			continue
		var d: float = u.global_position.distance_to(point)
		if d < radius_px:
			_add_suppression(u, GameConfig.SUPPRESSION_BLAST_MAX * (1.0 - d / radius_px))


## Once a tick: suppression fades with tactical time, and a squad becomes pinned at SUPPRESSION_PIN_LEVEL and stays so until it falls below
## SUPPRESSION_RELEASE_LEVEL. The log says so when a squad the player can see (its own, or an enemy that is in sight) is pinned or freed.
func _update_suppression(scenario_delta: float) -> void:
	for u in player_units + enemy_units:
		if u.kind != Unit.Kind.SQUAD:
			continue
		u.suppression = maxf(u.suppression - GameConfig.SUPPRESSION_DECAY_PER_S * scenario_delta, 0.0)
		if u.state != Unit.State.ACTIVE and u.state != Unit.State.RETREATING:
			u.suppression = 0.0
		if not u.pinned and u.suppression >= GameConfig.SUPPRESSION_PIN_LEVEL:
			u.pinned = true
			combat_log.log_pinned(u)
		elif u.pinned and u.suppression < GameConfig.SUPPRESSION_RELEASE_LEVEL:
			u.pinned = false
			combat_log.log_pin_lifted(u)


## Resolves one shot, logs its consequence, then checks for collateral
## damage at the ACTUAL impact point — real distance from where the shot
## really landed, not "is this unit specifically allied with the target,"
## is what determines who else might catch it, and neither real HE
## fragmentation nor a stray round from close-quarters small-arms fire
## checks whose side anyone is on:
##
## - A MORTAR shot's blast doesn't care what it was aimed at — anybody
##   (any kind, either side) within the round's own real burst radius has
##   a real, distance-scaled chance of being caught too (see GameConfig.
##   MORTAR_BLAST_COLLATERAL_MAX_CHANCE's own doc comment for the cited
##   figures behind it).
## - Otherwise (direct/small-arms fire), a squad hit while another squad
##   is crammed into the same patch of cover close by (see GameConfig.
##   BUNCHING_RADIUS) has a smaller, flat, less-common chance of catching
##   the same burst — the actual mechanical teeth behind squads spreading
##   out across DIFFERENT cover instead of piling into the same one (see
##   Unit.seek_cover / GameConfig.nearest_cover_point's avoid_positions).
##   Scoped to squad-on-squad specifically: aimed rifle fire is far more
##   discriminating than an explosive round's fragmentation, and this is
##   about troops crowded together, not any two units that happen to be
##   somewhat close.
##
## `impact_point` is the real landing spot: the target's own current
## position for direct fire (it resolves exactly there), or a mortar
## shell's actual dispersed impact point (_mortar_dispersion_offset off
## _mortar_aim_point), which can differ from the target's own position by
## up to MORTAR_EVASION_RADIUS — a bad lead, real ballistic scatter, or
## both, still lands somewhere real.
func _resolve_fire_and_check_bunching(attacker: Unit, target: Unit, impact_point: Vector2) -> void:
	var before := UnitCombatStats.before_hit(target)
	unit_combat_stats.register(attacker)
	var target_was_active := target.state == Unit.State.ACTIVE
	# This shot counts as the shooter "taking fire" from its direction BEFORE the roll, so a unit being
	# shot at from a second side feels it on that very shot. Mortar rounds are outside the whole mechanism:
	# they do not count toward the arc and their hits are not multiplied by it (direct user ruling).
	var crossfire := 1.0
	if attacker.kind != Unit.Kind.MORTAR:
		_record_direct_fire(attacker, target)
		crossfire = _crossfire_multiplier_against(target)
	if attacker.kind != Unit.Kind.MORTAR and target.kind == Unit.Kind.SQUAD:
		_add_suppression(target, GameConfig.SUPPRESSION_PER_VOLLEY) # every volley aimed at a squad, hit or miss (mortar rounds do it by where they land)
	CombatResolver.resolve_fire(attacker, target, _ally_positions_for(target), _known_enemy_positions(target.team), _drone_directing_multiplier(attacker), target.global_position.distance_to(impact_point), crossfire)
	unit_combat_stats.damage(attacker, target, before)
	_log_hit_consequence(target, target_was_active)
	# Collateral risk is about who else is near the actual impact point,
	# independent of whether the aimed-at unit itself was hit — attacks
	# are aimed at a unit but hit a location, and a round that misses its
	# intended target (they moved, ducked into cover, whatever the reason)
	# still lands somewhere real; anyone else there is exactly as exposed
	# as if the primary shot had landed true.
	var victim: Unit
	var is_blast: bool = attacker.kind == Unit.Kind.MORTAR
	if is_blast:
		victim = _collateral_victim(impact_point, [attacker, target], GameConfig.MORTAR_BLAST_COLLATERAL_SEARCH_RADIUS,
			func(d: float, pos: Vector2) -> float: return CombatResolver.blast_casualty_chance(d, GameConfig.MORTAR_BLAST_COLLATERAL_MAX_CHANCE, GameConfig.get_terrain_type_at(pos)))
	elif target.kind == Unit.Kind.SQUAD:
		victim = _collateral_victim(impact_point, [attacker, target], GameConfig.BUNCHING_RADIUS,
			func(_d: float, _pos: Vector2) -> float: return GameConfig.BUNCHING_SPILLOVER_CHANCE, true)
	else:
		return
	if victim == null:
		return
	var victim_was_active := victim.state == Unit.State.ACTIVE
	var before_victim := UnitCombatStats.before_hit(victim)
	victim.take_hit(is_blast, _ally_positions_for(victim), _known_enemy_positions(victim.team), impact_point.distance_to(victim.global_position))
	unit_combat_stats.damage(attacker, victim, before_victim)
	# A collateral victim is picked purely by proximity to the actual
	# impact point (see _collateral_victim) — it never had to be
	# individually spotted to get caught, so unlike `target` above it may
	# still be unnumbered the first time its name needs to appear in the log.
	_assign_discovery_number(victim)
	if is_blast:
		combat_log.log_blast_collateral(target, victim)
	else:
		combat_log.log_bunching_spillover(target, victim)
	_log_hit_consequence(victim, victim_was_active)


## Notes that `attacker` just fired direct fire at `target`, from where it stands. One entry per shooter (a
## shooter that fires again just refreshes its entry); entries older than GameConfig.CROSSFIRE_MEMORY_S are
## dropped here and ignored on read.
func _record_direct_fire(attacker: Unit, target: Unit) -> void:
	var shooters: Dictionary = _recent_direct_fire.get(target, {})
	shooters[attacker] = {"from": attacker.global_position, "time": scenario_elapsed_time}
	for s in shooters.keys():
		if scenario_elapsed_time - shooters[s].time > GameConfig.CROSSFIRE_MEMORY_S:
			shooters.erase(s)
	_recent_direct_fire[target] = shooters


## The unit's current "safe arc" (largest circular arc, degrees, from which it is not taking direct fire) —
## see CombatResolver.safe_arc_deg. 360 with nobody, or one direction, firing at it.
func _safe_arc_of(target: Unit) -> float:
	var positions: Array[Vector2] = []
	for s in _recent_direct_fire.get(target, {}).values():
		if scenario_elapsed_time - s.time <= GameConfig.CROSSFIRE_MEMORY_S:
			positions.append(s.from)
	return CombatResolver.safe_arc_deg(target.global_position, positions)


## Expected-damage multiplier from crossfire (x1 at a 360 safe arc up to x4 at none) for shots at `target`.
func _crossfire_multiplier_against(target: Unit) -> float:
	return CombatResolver.crossfire_multiplier(_safe_arc_of(target))


## The accuracy multiplier `attacker`'s shot gets from the drone feed: 1.0 (none) except for
## the player's own mortar (the enemy has no doctrine-level recon choice at all) firing while
## the doctrine is actually DRONE_TEAM AND a friendly drone (active or backup — either one
## airborne means the team's ISR feed is live right now) is actually up. Then
## GameConfig.DRONE_DIRECTED_MORTAR_ACCURACY_MULTIPLIER — or, with the drone team itself on the
## move (_drone_team_on_the_move), the smaller ..._MOVING (halfway to a plain spotter's none).
## Checked fresh at resolution time (mortar shots land ~40 tactical seconds
## after firing — see _launch_mortar_shot/_resolve_pending_mortar_shots),
## the same moment the target's own moving/terrain state is read, not
## frozen at the instant the round left the tube.
func _drone_directing_multiplier(attacker: Unit) -> float:
	if attacker.kind != Unit.Kind.MORTAR or attacker.team != Unit.Team.PLAYER:
		return 1.0
	if recon_mode != GameConfig.ReconMode.DRONE_TEAM:
		return 1.0
	if active_drone == null and backup_drone == null:
		return 1.0
	var multiplier: float = GameConfig.DRONE_DIRECTED_MORTAR_ACCURACY_MULTIPLIER_MOVING if _drone_team_on_the_move() else GameConfig.DRONE_DIRECTED_MORTAR_ACCURACY_MULTIPLIER
	# a team with someone down gives a slightly weaker feed: part of the edge over a plain spotter is lost, never more than all of it
	if drone_team != null and drone_team.crew_casualties > 0:
		var kept: float = clampf(1.0 - GameConfig.DRONE_TEAM_CASUALTY_DIRECTING_LOSS * float(drone_team.crew_casualties), 0.0, 1.0)
		multiplier = 1.0 + (multiplier - 1.0) * kept
	return multiplier


## Whether the drone team is itself under way (a move order standing — repositioning, evading, an
## order to fall back), so its drones are being operated on the move: still flown, still
## spotting, but with degraded performance (see GameConfig.DRONE_TEAM_MOVING_*).
func _drone_team_on_the_move() -> bool:
	return recon_mode == GameConfig.ReconMode.DRONE_TEAM and drone_team != null \
		and drone_team.state == Unit.State.ACTIVE and drone_team.has_move_target


## Any unit (either SIDE — real HE fragmentation and even a stray round
## from close-quarters small-arms fire don't check whose side anyone is
## on) within `radius` of `impact_point` — one candidate per shot, nearest
## checked first (a real burst is more likely to catch whoever's actually
## closest), `chance_at(distance)` rolled per candidate until one hits or
## none do. `exclude` keeps the attacker and the already-resolved primary
## target out of the pool. DRONE is always excluded — airborne at
## DRONE_ALTITUDE_M, it's already unreachable by ground fire entirely
## (see CombatResolver.hit_probability's own DRONE branch).
## `only_squads` narrows it further, for the small-arms/bunching case
## specifically — this is about troops crowded together, not any two
## units merely somewhat close to each other. `chance_at` is called with
## both the distance AND the candidate's own position — the blast-
## casualty case needs the latter to read real terrain cover at the
## candidate's own location (see CombatResolver.blast_casualty_chance).
func _collateral_victim(impact_point: Vector2, exclude: Array[Unit], radius: float, chance_at: Callable, only_squads: bool = false) -> Unit:
	var candidates: Array[Unit] = []
	for u in player_units + enemy_units:
		if u in exclude or u.kind == Unit.Kind.DRONE or u.state != Unit.State.ACTIVE:
			continue
		if only_squads and u.kind != Unit.Kind.SQUAD:
			continue
		if impact_point.distance_to(u.global_position) > radius:
			continue
		candidates.append(u)
	candidates.sort_custom(func(a, b): return impact_point.distance_to(a.global_position) < impact_point.distance_to(b.global_position))
	for c in candidates:
		if randf() < chance_at.call(impact_point.distance_to(c.global_position), c.global_position):
			return c
	return null


## Where a resupply run for `mortar` actually enters the map: the true edge
## of the modeled world on `mortar`'s own side — the west edge for the
## player (its rear is west), the east edge for the enemy (its rear is
## east) — at the mortar's own current y, so it heads straight in toward
## the mortar rather than on a diagonal. The map viewport is always wide
## enough to show both true edges at once now (GameConfig.
## CAMERA_VIEWPORT_WIDTH_PX — no panning, unlike an earlier version of this
## game), so there's no "wherever the camera currently happens to be
## showing" to track any more; the edges are simply fixed.
func _resupply_entry_point_for(mortar: Unit) -> Vector2:
	var edge_x: float = -GameConfig.WEST_FLANK_WIDTH_PX if mortar.team == Unit.Team.PLAYER else GameConfig.MAP_WIDTH_PX
	return Vector2(edge_x, mortar.global_position.y)


## The whole resupply pipeline (requests, ETA warnings, arrivals, failures,
## the physical fetch trip) runs identically for both sides' mortars — but
## none of it is something the PLAYER's own side would actually know about
## an opposing crew's ammunition or logistics. Every combat_log call in
## this pipeline is gated on this, and CasualtyDashboard's own enemy mortar
## row shows only "in action," never a round count or resupply status —
## the mechanic is fully real and functional for the enemy either way, it's
## simply never narrated to the player.
func _should_narrate_mortar_logistics(mortar: Unit) -> bool:
	return mortar.team == Unit.Team.PLAYER


## Sticky — see _player_sighted_enemy/_enemy_sighted_enemy's own doc
## comment. Called every tick; only ever flips false to true, never back.
func _update_sighting_flags() -> void:
	if not _player_sighted_enemy and not _known_enemy_positions(Unit.Team.PLAYER).is_empty():
		_player_sighted_enemy = true
	if not _enemy_sighted_enemy and not _known_enemy_positions(Unit.Team.ENEMY).is_empty():
		_enemy_sighted_enemy = true


func _has_sighted_enemy(team: Unit.Team) -> bool:
	return _player_sighted_enemy if team == Unit.Team.PLAYER else _enemy_sighted_enemy


## The one real entry point for "resupply can be requested" — called
## automatically by _update_mortar_resupply_requests the first time (on
## confirmed contact) and then by _update_mortar_resupply itself every
## time afterward, immediately upon the previous run committing (whether
## it actually got through or failed) — a continuous pipeline, one run in
## the system at a time, not a fixed batch. Schedules a single transit
## delay (see GameConfig.sample_resupply_delay) plus a separately-sampled
## ETA-warning lead time. Returns false (no-op) if this mortar isn't
## eligible: no confirmed contact yet, the crew's gone, or a request is
## already in flight.
func request_mortar_resupply(mortar: Unit) -> bool:
	if mortar.kind != Unit.Kind.MORTAR or mortar.state != Unit.State.ACTIVE:
		return false
	if not _has_sighted_enemy(mortar.team):
		return false
	if _mortar_resupply.has(mortar):
		return false

	var arrival_time: float = scenario_elapsed_time + GameConfig.sample_resupply_delay(GameConfig.MORTAR_RESUPPLY_DELAY_MEDIAN, GameConfig.MORTAR_RESUPPLY_DELAY_SIGMA)
	# See GameConfig.MORTAR_RESUPPLY_ETA_WARNING_MEDIAN's own comment —
	# this is a SEPARATELY estimated lead time, not (arrival - 15min)
	# computed with perfect hindsight, so the "roughly 15 minutes"
	# heads-up really can end up wrong once the run actually resolves.
	var lead: float = GameConfig.sample_resupply_delay(GameConfig.MORTAR_RESUPPLY_ETA_WARNING_MEDIAN, GameConfig.MORTAR_RESUPPLY_ETA_WARNING_SIGMA)

	_mortar_resupply[mortar] = {
		"arrival_time": arrival_time,
		"warning_time": arrival_time - lead,
		"warned": false,
		"staged": false,
	}
	if _should_narrate_mortar_logistics(mortar):
		combat_log.log_mortar_resupply_requested(mortar)
	return true


## Ticks every mortar's active resupply request (if any) toward its ETA
## warning and eventual arrival/failure — see request_mortar_resupply for
## how the two wave timings were actually rolled. Runs every tick,
## regardless of whether that mortar itself is doing anything else right
## now (moving, firing, out of ammo) — the resupply pipeline runs in the
## background either way, exactly like a real supply run would. A
## successful transit hands off to a real, physical run (see
## _spawn_resupply_run) rather than staging rounds at a fixed point.
##
## Direct user correction after a live-observed bug: "the resupply run
## was set to arrive, but the mortar still had over 10 rounds. It delayed
## the run by an hour. That's the wrong reaction. What should happen is
## that the run should go into a state of 'waiting offmap'. It should
## remain in that state until the mortar gets down to ten rounds. When
## that happens, the resupply run should immediately enter the map, and
## the next run should be requested." A run whose transit time has
## elapsed while the mortar still has more than MORTAR_RESUPPLY_REORDER_
## POINT on hand now genuinely WAITS (this loop just keeps re-checking it
## every subsequent tick) instead of being discarded outright the instant
## its own scheduled arrival passes — matching what GameConfig.
## MORTAR_RESUPPLY_REORDER_POINT's own doc comment already said the
## design was supposed to do ("a wave held back this way isn't lost...
## it simply never becomes a physical, spottable, targetable RESUPPLY_RUN
## unit"), which the old resolved-regardless code never actually
## delivered on. Whether the convoy gets through is settled when it is
## due to arrive and found out then, in transit (`fails`): a run that
## has reached the ready position is never delayed or lost there (direct
## user correction, 2026-10-07: the old code rolled the 10% at the moment
## a staged run committed, which sent "staged" back to "41 minutes out").
## The instant this run commits (dispatched, or failed in transit) the
## NEXT request goes out immediately: a continuous one-run-at-a-time
## pipeline, not "wait for this one to be used before asking again."
func _update_mortar_resupply() -> void:
	for m in _mortar_resupply.keys():
		var record: Dictionary = _mortar_resupply[m]
		if m.state != Unit.State.ACTIVE:
			_mortar_resupply.erase(m) # the position is gone — nothing to send a run toward
			continue
		if not record.warned and scenario_elapsed_time >= record.warning_time:
			record.warned = true
			if _should_narrate_mortar_logistics(m):
				combat_log.log_mortar_resupply_eta_warning(m)
			_mortar_resupply[m] = record
		if scenario_elapsed_time < record.arrival_time:
			continue # still in transit
		# Whether the convoy got through is found out here, on its scheduled arrival, in transit, and not when a staged run is committed:
		# a run that has reached the ready position is never delayed (direct user report: "I thought resupply was staged and ready.
		# Then it changed to 41 minutes out... Resupply can get delayed when en route. But when staged, it would not get delayed.").
		if not record.has("fails"):
			record["fails"] = randf() < GameConfig.MORTAR_RESUPPLY_FAILURE_CHANCE
			_mortar_resupply[m] = record
		if record.fails:
			# The convoy did not make it: found out in transit, so it never reaches the ready position. The next is already organised.
			_mortar_resupply.erase(m)
			if _should_narrate_mortar_logistics(m):
				combat_log.log_mortar_resupply_failed(m)
			request_mortar_resupply(m)
			continue
		if m.mortar_rounds_remaining > GameConfig.MORTAR_RESUPPLY_REORDER_POINT:
			# Not "is the position already completely full" — see
			# GameConfig.MORTAR_RESUPPLY_REORDER_POINT's own doc comment
			# for the real logistics reasoning. The run is staged, ready,
			# and simply waits here — re-checked every tick from now on —
			# rather than walking all the way up only to be capped or
			# wasted delivering a handful of rounds on arrival.
			if not record.staged:
				record.staged = true
				_mortar_resupply[m] = record
				if _should_narrate_mortar_logistics(m):
					combat_log.log_mortar_resupply_held(m)
			continue
		# Ammo has genuinely drawn down enough — commit the run now. Erased
		# before requesting the next one so request_mortar_resupply's own
		# "already in flight" eligibility check doesn't block it.
		_mortar_resupply.erase(m)
		_spawn_resupply_run(m)
		request_mortar_resupply(m)


## Nobody clicks a button for this on either side — each side's mortar
## requests its own resupply automatically the instant the first
## approaching enemy is spotted (that side's own _has_sighted_enemy flips
## true), not once ammo actually runs low: with a resupply run taking on
## the order of an hour or more to arrive at all, waiting for a real
## shortage before asking would already be too late. Deliberately NOT
## gated on current ammo level for that reason — a real commander gets the
## supply chain moving the moment a fight looks likely, not after the guns
## have gone quiet for want of rounds. This is only ever the BOOTSTRAP —
## `_mortar_resupply.has(m)` is the throttle, and once first contact is
## made it stays true essentially forever: the instant one request
## commits (dispatched or failed), _update_mortar_resupply itself
## immediately requests the next one, so this function's only real job is
## getting that continuous pipeline started in the first place. Symmetric
## — the player's own mortar follows exactly the same rule as the enemy's,
## since a doctrine-driven game already puts unit-level logistics calls
## like this in the same autonomous-AI bucket as everything else a unit
## decides for itself mid-battle.
func _update_mortar_resupply_requests() -> void:
	for m in player_units + enemy_units:
		if m.kind != Unit.Kind.MORTAR or m.state != Unit.State.ACTIVE:
			continue
		if not _has_sighted_enemy(m.team):
			continue
		if _mortar_resupply.has(m):
			continue
		request_mortar_resupply(m)


## Puts a real, physical Unit.Kind.RESUPPLY_RUN on the map, carrying
## GameConfig.MORTAR_RESUPPLY_ROUNDS to `mortar` — this is what a
## successful wave arrival (see _update_mortar_resupply) now actually
## means, replacing the old "rounds appear at a fixed rear point, crew
## walks over" design. The run is a normal member of its side's unit array
## (player_units/enemy_units), so it's spotted, targeted, and fired on by
## exactly the same generic code every other unit already goes through —
## see Unit.is_targetable/BattleManager._refresh_visibility/_pick_target,
## none of which needed a single change for this to work. Its own
## move_target is refreshed every tick (_update_resupply_run_targets), not
## set once here, so it keeps tracking the mortar even if the mortar itself
## moves in the meantime.
func _spawn_resupply_run(mortar: Unit) -> void:
	var run := _make_unit(mortar.team, Unit.Kind.RESUPPLY_RUN, _resupply_entry_point_for(mortar))
	run.resupply_target_mortar = mortar
	run.move_target = mortar.global_position
	run.has_move_target = true
	run.move_speed = GameConfig.MORTAR_RESUPPLY_RUN_SPEED
	run.movement_predictable = false
	run.state_changed.connect(_on_resupply_run_state_changed)
	if mortar.team == Unit.Team.PLAYER:
		player_units.append(run)
	else:
		enemy_units.append(run)
	if _should_narrate_mortar_logistics(mortar):
		combat_log.log_resupply_run_departed(mortar, GameConfig.MORTAR_RESUPPLY_ROUNDS)


## Mirrors _on_drone_state_changed's exact convention: a RESUPPLY_RUN that
## reaches DESTROYED (the ordinary generic take_hit path — max_pips=1 means
## any hit gets it there, see Unit.setup's Kind.RESUPPLY_RUN case) is
## erased from its side's array and freed immediately, same as a downed
## drone — it's a transient logistics element, not part of the permanent
## roster a DESTROYED squad/mortar stays in for the AAR. This is the
## payoff moment for the whole redesign: the mortar it was carrying rounds
## to gets nothing, and the player (or, silently, the enemy) finds out why.
## `not resupply_delivered` guards the narration specifically — a run shot
## down on its own way back out, after already handing off its rounds
## (see Unit.resupply_delivered), already got its own log line at the
## moment of delivery; log_resupply_run_destroyed's own wording ("lost
## before reaching the position") would be flatly wrong to repeat here,
## since it DID reach the position.
func _on_resupply_run_state_changed(unit: Unit) -> void:
	if unit.kind != Unit.Kind.RESUPPLY_RUN or unit.state != Unit.State.DESTROYED:
		return
	if unit.resupply_target_mortar != null and not unit.resupply_delivered and _should_narrate_mortar_logistics(unit):
		combat_log.log_resupply_run_destroyed(unit.resupply_target_mortar)
	var side: Array[Unit] = player_units if unit.team == Unit.Team.PLAYER else enemy_units
	side.erase(unit)
	unit.queue_free()


## The live RESUPPLY_RUN currently servicing `mortar`, or null if none is
## in flight — feeds the dashboard's "resupply run en route" status, the
## resupply-linkup idle check, and _mortar_resupply_urgency. Excludes a run
## that's already delivered and is just driving itself back out to the map
## edge (see Unit.resupply_delivered) — its job for this mortar is done,
## so it shouldn't keep reading as "one's already coming" and block (or
## get walked toward by) a fresh request.
func _active_resupply_run_for(mortar: Unit) -> Unit:
	var side: Array[Unit] = player_units if mortar.team == Unit.Team.PLAYER else enemy_units
	for u in side:
		if u.kind == Unit.Kind.RESUPPLY_RUN and u.state == Unit.State.ACTIVE and u.resupply_target_mortar == mortar and not u.resupply_delivered:
			return u
	return null


## Keeps every in-flight run's destination locked onto its mortar's CURRENT
## position, not wherever the mortar happened to be when the run set out —
## this is the entire mechanism behind the mortar "falling back to meet"
## an inbound run (see _decide_mortar_action's tier-1 linkup case): both sides closing
## distance toward each other's live position naturally converges faster,
## with no extra coordination needed between the two systems. Must run
## before _tick_movement, which is what actually steps the run toward
## whatever move_target says this tick.
## How far from a known enemy squad a resupply run keeps (a little more than a squad's engagement range, so it is never in reach of a
## squad whose position its side knows).
const RESUPPLY_AVOID_RADIUS: float = GameConfig.SQUAD_ENGAGEMENT_RANGE * 1.15

## The positions of the enemy squads `team` currently knows about (its own side's knowledge, last seen if not now).
func _known_squad_positions(team: Unit.Team) -> Array[Vector2]:
	var opposing: Array[Unit] = enemy_units if team == Unit.Team.PLAYER else player_units
	var positions: Array[Vector2] = []
	for u in opposing:
		if u.kind != Unit.Kind.SQUAD or (u.state != Unit.State.ACTIVE and u.state != Unit.State.RETREATING):
			continue
		if team == Unit.Team.PLAYER:
			if u.player_has_been_sighted:
				positions.append(u.player_known_position)
		elif u.enemy_has_been_sighted:
			positions.append(u.enemy_known_position)
	return positions


## Where a resupply run steers this tick on its way to `goal` (the mortar): the goal itself, unless a known enemy squad lies within
## RESUPPLY_AVOID_RADIUS of the straight line there, in which case a point beside that squad, on whichever side leaves more room from the
## others, so the run goes around rather than through its reach. Direct user instruction: "Resupply run should be smart enough to avoid
## enemy squads." Uses only what the run's own side knows. A squad within that radius of the goal itself cannot be avoided by a detour (the
## mortar is already in its reach), and the run then goes straight in. Recomputed each tick like the target itself, so it is dropped the moment
## the way is clear. (And an enemy squad that gets a visible run in range and in sight fires on it like any other target: the run is an
## ordinary visible unit to _pick_target.)
func _resupply_run_destination(run: Unit, goal: Vector2) -> Vector2:
	var threats: Array[Vector2] = _known_squad_positions(run.team)
	var from: Vector2 = run.global_position
	var seg: Vector2 = goal - from
	if threats.is_empty() or seg.length_squared() < 1.0:
		_resupply_detours.erase(run)
		return goal
	# A detour once chosen is kept until the run has reached its point or the way on is clear: choosing afresh each tick flips between
	# "round it" and "straight at it" as the geometry shifts, and the run slips into the squad's reach.
	var detour: Dictionary = _resupply_detours.get(run, {})
	if not detour.is_empty():
		if from.distance_to(detour.point) <= RESUPPLY_DETOUR_ARRIVAL and _resupply_line_depth(from, goal, threats) <= 0.0:
			_resupply_detours.erase(run)
		else:
			return detour.point
	var worst: Vector2 = _resupply_worst_threat(from, goal, threats)
	if is_inf(worst.x):
		return goal
	# Beside the squad at 1.3 times its reach AND half a reach past it along the way, so once the run has rounded that point the line on to
	# the mortar leads away from the squad rather than cutting back across its reach.
	var ahead: Vector2 = seg.normalized() * RESUPPLY_AVOID_RADIUS * 0.5
	var side: Vector2 = seg.normalized().orthogonal() * RESUPPLY_AVOID_RADIUS * 1.3
	var best := Vector2.INF
	var best_room := -INF
	for candidate in [worst + ahead + side, worst + ahead - side]:
		var p: Vector2 = GameConfig.clamp_to_operating_area(candidate)
		var room := INF
		for t in threats:
			room = minf(room, p.distance_to(t))
		if room > best_room:
			best_room = room
			best = p
	_resupply_detours[run] = {"point": best}
	return best


## How far into any known squad's reach the straight line from `from` to `goal` runs (0 if it keeps clear of every one that the goal itself is
## not already inside).
func _resupply_line_depth(from: Vector2, goal: Vector2, threats: Array[Vector2]) -> float:
	var seg: Vector2 = goal - from
	var len2: float = seg.length_squared()
	var worst := 0.0
	for t in threats:
		if goal.distance_to(t) < RESUPPLY_AVOID_RADIUS or len2 < 1.0:
			continue
		var u: float = clampf((t - from).dot(seg) / len2, 0.0, 1.0)
		worst = maxf(worst, RESUPPLY_AVOID_RADIUS - (from + seg * u).distance_to(t))
	return worst


func _resupply_worst_threat(from: Vector2, goal: Vector2, threats: Array[Vector2]) -> Vector2:
	var seg: Vector2 = goal - from
	var len2: float = seg.length_squared()
	var worst := Vector2.INF
	var worst_depth := 0.0
	for t in threats:
		if goal.distance_to(t) < RESUPPLY_AVOID_RADIUS:
			continue
		var u: float = clampf((t - from).dot(seg) / len2, 0.0, 1.0)
		var depth: float = RESUPPLY_AVOID_RADIUS - (from + seg * u).distance_to(t)
		if depth > worst_depth:
			worst_depth = depth
			worst = t
	return worst


const RESUPPLY_DETOUR_ARRIVAL: float = 80.0 * GameConfig.PIXELS_PER_METER
## Run -> {"point": the detour point it is steering for}, while one is in force.
var _resupply_detours: Dictionary = {}


func _update_resupply_run_targets() -> void:
	for m in player_units + enemy_units:
		if _risk_holds.has(m): continue
		if m.kind != Unit.Kind.RESUPPLY_RUN or m.state != Unit.State.ACTIVE:
			continue
		if m.resupply_delivered:
			continue # homeward leg — a fixed destination set once at delivery, not re-tracked
		if m.resupply_target_mortar == null or m.resupply_target_mortar.state != Unit.State.ACTIVE:
			continue # handled by _resolve_resupply_run_arrivals below
		m.move_target = _resupply_run_destination(m, m.resupply_target_mortar.global_position)
		m.has_move_target = true


## Runs after _tick_movement, once this tick's actual stepping is done.
## Four ways a run's trip ends: it physically reaches the mortar (rounds
## delivered, but NOT removed yet — see resupply_delivered's own doc
## comment, it turns around and heads back out to its own side's map edge
## instead); having already delivered, it physically reaches that edge
## (its round trip is genuinely over, removed now); the mortar it was
## heading to stopped being ACTIVE before delivery (destroyed/withdrawn/
## retreating — the run aborts rather than deliver to an empty position or
## chase a unit that's pulling out; once delivered this no longer applies
## at all, the trip home doesn't care what happens to the mortar
## afterward); or (handled entirely elsewhere, by ordinary combat) it gets
## hit and destroyed like any other spotted unit, in which case it's
## simply gone from player_units/enemy_units already by the time this runs
## and needs no special handling here at all.
func _resolve_resupply_run_arrivals() -> void:
	for side in [player_units, enemy_units]:
		var delivering: Array[Unit] = []
		var home: Array[Unit] = []
		var aborted: Array[Unit] = []
		for u in side:
			if u.kind != Unit.Kind.RESUPPLY_RUN or u.state != Unit.State.ACTIVE:
				continue
			if u.resupply_delivered:
				if u.global_position.distance_to(u.move_target) <= GameConfig.MORTAR_RESUPPLY_ARRIVAL_RADIUS:
					home.append(u)
				continue
			var mortar: Unit = u.resupply_target_mortar
			if mortar == null or mortar.state != Unit.State.ACTIVE:
				aborted.append(u)
			elif u.global_position.distance_to(mortar.global_position) <= GameConfig.MORTAR_RESUPPLY_ARRIVAL_RADIUS:
				delivering.append(u)
		for u in delivering:
			var mortar: Unit = u.resupply_target_mortar
			# Capped at delivery too, not just at dispatch (_update_mortar_
			# resupply's own hold-back check): the mortar could have simply
			# not fired much in the transit time between the two, so a run
			# that was a legitimate top-up when it left the rear can still
			# arrive to find the position closer to full than expected.
			# Delivering only what actually fits keeps the same realistic
			# ceiling either way, without wasting the run outright — full
			# credit for the trip, just not more rounds than the position
			# has anywhere to put.
			var delivered: int = clampi(GameConfig.MORTAR_RESUPPLY_ROUNDS, 0, GameConfig.MORTAR_MAX_AMMO_ON_HAND - mortar.mortar_rounds_remaining)
			mortar.mortar_rounds_remaining += delivered
			if _should_narrate_mortar_logistics(mortar):
				combat_log.log_mortar_resupply_delivered(mortar, delivered)
			u.resupply_delivered = true
			u.move_target = _resupply_entry_point_for(mortar)
			u.has_move_target = true
			u.move_queue.clear()
		for u in home:
			side.erase(u)
			u.queue_free()
		for u in aborted:
			var mortar: Unit = u.resupply_target_mortar
			if mortar != null and _should_narrate_mortar_logistics(mortar):
				combat_log.log_resupply_run_aborted(mortar)
			side.erase(u)
			u.queue_free()


## Part of _decide_mortar_action's tier 2 ("destroy enemy mortars") — the
## current best "fix" this mortar's OWN team has on the opposing mortar
## worth hunting, or {} if there's nothing to go on. Two genuinely
## different per-team policies sharing one call site rather than one
## merged body (see the tactical-rewrite doctrine doc's "on merging the
## hunting functions" entry for the full reasoning — 8 real differences,
## and a real merge would either become an unreadable per-team branch or
## silently hand the enemy concealment-aware routing/an infantry-screen
## check it doesn't have today, an actual enemy-behavior change that's out
## of scope):
## - Enemy: _known_friendly_mortar_position() — currently visible OR
##   detected firing recently, NOT a permanent memory of where it used to
##   be — wrapped as always "trusted" (the enemy has no separate
##   trusted/untrusted distinction; a real detection is a real detection).
## - Player: the team's shared joint commitment (_update_joint_mortar_hunt,
##   which runs earlier this same tick) if one is active and still
##   resolves to a real position, else a bare, uncovered fire-detection
##   lead — no active joint commitment at all — as an explicitly untrusted
##   fix (a solo gamble, capped harder in _mortar_hunt_destination_for).
## `unit`, when present, is the specific enemy mortar Unit this fix
## actually points at — carried through so callers that need to match a
## fix against a real, currently-visible unit (see _is_priority_hunt_
## target) can, without re-deriving the same lookup. Absent on the enemy
## branch (_known_friendly_mortar_position has no unit reference to give,
## and nothing currently needs one there).
func _mortar_hunt_fix_for(m: Unit) -> Dictionary:
	if m.team == Unit.Team.ENEMY:
		var pos: Vector2 = _known_friendly_mortar_position()
		return {} if is_inf(pos.x) else {"position": pos, "trusted": true}
	if _joint_mortar_hunt_target != null:
		var known_pos: Vector2 = _joint_mortar_hunt_known_position()
		return {} if is_inf(known_pos.x) else {"position": known_pos, "trusted": true, "unit": _joint_mortar_hunt_target}
	var lead: Dictionary = _known_enemy_mortar_lead()
	if lead.is_empty():
		return {}
	# A trusted lead falls through here whenever the team-wide joint
	# commitment hasn't formed for it — not just "hasn't formed YET," but
	# possibly never will: _update_joint_mortar_hunt declines a trusted
	# lead outright if the resulting hunt point would land outside
	# MORTAR_HUNT_MAX_RANGE_FROM_HOME or read as reckless, among other
	# gates. A trusted, currently-visible enemy mortar doesn't stop being
	# real or worth pursuing just because the drone-escorted TEAM version
	# of the hunt isn't viable — the mortar's own solo pursuit
	# (_mortar_hunt_destination_for) re-applies those exact same safety
	# checks independently anyway, so this can never send it somewhere the
	# joint path itself would have refused; it just stops silently
	# discarding a perfectly good, low-risk (this mortar hasn't been
	# scouted) opportunity to hunt when the team commitment alone can't
	# form. `lead.trusted` is passed through as-is (not hardcoded true or
	# false) so a genuinely untrusted lead still gets the untrusted-only
	# relocate cap in _mortar_hunt_destination_for.
	return {"position": lead.position, "trusted": lead.trusted, "unit": lead.unit}


## The other half of tier 2 — the destination `m` should advance to in
## order to bring `target_pos` (from _mortar_hunt_fix_for) into range.
## Returns `m`'s own current position to mean "no acceptable destination
## this tick." Same two-policies-one-call-site split as _mortar_hunt_fix_
## for, for the same reason:
## - Enemy: just needs to avoid buildings on the way in
##   (_mortar_advance_point) — re-aimed fresh every tick there's still a
##   fix and it's still out of range, so an already-advancing mortar keeps
##   correcting toward the best currently-known position instead of
##   plodding toward a possibly-stale point.
## - Player: additionally needs to stay unseen while closing
##   (_friendly_mortar_hunt_point, unlike the enemy's plain building-
##   avoidance), stay within GameConfig.MORTAR_HUNT_MAX_RANGE_FROM_HOME of
##   wherever the crew was actually deployed, stay behind its own infantry
##   screen (_friendly_mortar_hunt_destination_is_reckless), and — for a
##   bare, untrusted lead specifically — risk at most a modest walk
##   (GameConfig.MORTAR_HUNT_UNTRUSTED_MAX_RELOCATE), since there's no
##   drone coverage backing an uncovered gamble.
func _mortar_hunt_destination_for(m: Unit, target_pos: Vector2, trusted: bool) -> Vector2:
	if m.team == Unit.Team.ENEMY:
		# Direct user report: "Enemy mortar just charged into our rear area. That's crazy." / "It should
		# have the same constraints as the friendly mortar." The enemy's advance had none: only the walk
		# to a point just inside range of the fix. It now keeps the same two the friendly crew does: within
		# the leash of where it was deployed (the extended one: the enemy's fixes are always trusted) and
		# never newly ahead of, or outside the band held by, its own infantry screen.
		var enemy_dest := _mortar_advance_point(m, target_pos)
		if enemy_dest == m.global_position:
			return enemy_dest
		if enemy_dest.distance_to(_mortar_home_position(m)) > GameConfig.mortar_home_leash(m.team, true):
			return m.global_position
		if _friendly_mortar_hunt_destination_is_reckless(m, enemy_dest):
			return m.global_position
		return enemy_dest
	var dest := _friendly_mortar_hunt_point(m, target_pos)
	if dest == m.global_position:
		return m.global_position # no safe route found this tick — try again next tick
	# The leash isn't an absolute wall — see GameConfig.MORTAR_HUNT_
	# EXTENDED_RANGE_FROM_HOME's own doc comment for the real correction
	# behind this (a live, reported bug: a mortar whose only known fix sat
	# just beyond the ordinary leash was permanently refusing every hunt
	# candidate, with no way to ever get a shot at all). A CONFIRMED,
	# currently-trusted target is worth the crew briefly reaching past its
	# ordinary comfort zone for; a bare, unconfirmed last-known position
	# is not — the same real distinction MORTAR_HUNT_UNTRUSTED_MAX_
	# RELOCATE already draws for how big a gamble to risk on this exact
	# same `trusted` flag.
	var leash: float = GameConfig.MORTAR_HUNT_EXTENDED_RANGE_FROM_HOME if trusted else GameConfig.MORTAR_HUNT_MAX_RANGE_FROM_HOME
	if dest.distance_to(_friendly_mortar_home_position) > leash:
		return m.global_position # too far from what the crew considers safe territory even with this allowance
	if _friendly_mortar_hunt_destination_is_reckless(m, dest):
		return m.global_position # would newly put the mortar ahead of, or outside the band held by, its own infantry screen
	if not trusted and m.global_position.distance_to(dest) > GameConfig.MORTAR_HUNT_UNTRUSTED_MAX_RELOCATE:
		return m.global_position # too big a gamble on a lead nobody's actually watching
	return dest


## The best position the enemy currently has on the friendly mortar, or
## Vector2.INF if they have nothing to go on at all. Two sources, live
## visibility preferred: (1) a CURRENTLY visible friendly mortar's actual
## position — most accurate; (2) failing that, wherever it was last
## DETECTED FIRING (see _launch_mortar_shot), as long as that's still
## within MORTAR_FIRE_DETECTION_EXPIRY — real counter-battery detection is
## via the outgoing round's muzzle blast/trajectory, not needing to keep
## the mortar in sight the whole time, so a mortar that hides itself
## perfectly between shots (see _relocate_mortar) doesn't thereby become
## un-huntable — it's still given away every time it actually fires.
func _known_friendly_mortar_position() -> Vector2:
	for u in player_units:
		if u.kind == Unit.Kind.MORTAR and u.state != Unit.State.DESTROYED and u.is_visible:
			return u.global_position
	var best_pos := Vector2.INF
	var best_time := -INF
	for u in player_units:
		# The mirror of the drone's own fire-detection-lead fix: a stale lead has to go by what the
		# ENEMY last found out (enemy_known_state), not this mortar's real, possibly more current ground
		# truth (u.state) — an enemy hunting a lead on our mortar has no more business knowing about an
		# unseen kill than our own drone did about theirs.
		if u.kind != Unit.Kind.MORTAR or u.enemy_known_state == Unit.State.DESTROYED:
			continue
		var info: Dictionary = _last_detected_mortar_fire.get(u, {})
		if info.is_empty():
			continue
		if scenario_elapsed_time - info.time > GameConfig.MORTAR_FIRE_DETECTION_EXPIRY:
			continue
		if info.time > best_time:
			best_time = info.time
			best_pos = info.position
	return best_pos


## The best current fix on the highest-priority known ACTIVE enemy mortar,
## for the friendly mortar's OWN cat-and-mouse hunting (see
## _mortar_hunt_fix_for) — Vector2.INF / not `trusted` at all if
## nothing is known. Mirrors _known_friendly_mortar_position's two sources
## (live visibility first, then the same muzzle-flash fire-detection lead
## used everywhere else), but ALSO reports whether that fix is `trusted`:
## true for a currently live-visible mortar, or for a fire-detection lead
## that a friendly drone is already flying toward (about to cover it, even
## before actually arriving) — either way, real confidence the position is
## still good. A bare, uncovered fire-detection lead is reported untrusted
## and aged out on the much shorter MORTAR_FIRE_DETECTION_EXPIRY window
## instead of DRONE_MORTAR_FIRE_LEAD_EXPIRY, since nothing is keeping it
## current the way a live drone (or eyes) would.
##
## THIRD fallback, once both of those come up empty: Unit.player_known_
## position, the last spot this mortar was actually SEEN (not just heard
## firing), with no expiry at all. Without this, an enemy mortar that goes
## quiet for longer than the short fire-detection window (very common —
## it isn't obligated to fire every reload cycle, and a real one often
## doesn't) was being treated as if it had never been found at all, the
## instant that short window lapsed — silently forfeiting the whole
## ammo-conservation/pursuit mechanism for a target that's still very
## much real and still very much known to exist, just not RECENTLY heard
## from. Reported untrusted (never trusted, regardless of drone coverage)
## since the mortar could genuinely have relocated since — a real crew
## would still send a probing advance on a last-known position, not
## commit the whole team to it the way a live or freshly-detected fix
## earns.
func _known_enemy_mortar_lead() -> Dictionary:
	# ACTIVE or RETREATING, never DESTROYED/WITHDRAWN/SURRENDERED — the same
	# "still a threat, still a real target" standard _known_enemy_positions
	# already applies elsewhere in this file, and the same one Unit.
	# is_targetable() itself allows a shot at. A crew that's pulling its gun
	# back after taking a hit hasn't abandoned it (see order_retreat's own
	# reasoning) and is very much still worth catching — excluding
	# RETREATING here meant a mortar the player had just damaged enough to
	# make it flee immediately became untrackable, the exact tick it
	# actually mattered most.
	#
	# ACTIVE is preferred outright over RETREATING when both are visible —
	# a fleeing crew is a mop-up, not an ongoing threat, and shouldn't
	# out-rank a mortar that's still actually in the fight. Only falls back
	# to a visible RETREATING one when no ACTIVE mortar is visible at all.
	#
	# Among more than one simultaneously-visible ACTIVE mortar, the closest
	# one to our own mortar wins (see _closest_enemy_mortar's own doc
	# comment for the real reasoning and the switching-margin hysteresis)
	# — collected into a list first rather than returned on sight, since
	# picking "whichever happens to come first in enemy_units" was itself
	# the previously-reported bug (the drone tracking the farther of two
	# known mortars purely because of array order).
	var retreating_visible: Unit = null
	var active_visible: Array[Unit] = []
	for u in enemy_units:
		if u.kind != Unit.Kind.MORTAR or not u.is_targetable_state() or not u.is_visible:
			continue
		if u.state == Unit.State.ACTIVE:
			active_visible.append(u)
		elif retreating_visible == null:
			retreating_visible = u
	if not active_visible.is_empty():
		var chosen: Unit = _closest_enemy_mortar(active_visible, _known_enemy_mortar_lead_unit)
		_known_enemy_mortar_lead_unit = chosen
		return {"position": chosen.global_position, "trusted": true, "unit": chosen}
	if retreating_visible != null:
		return {"position": retreating_visible.global_position, "trusted": true, "unit": retreating_visible}

	var best_pos := Vector2.INF
	var best_time := -INF
	var best_unit: Unit = null
	for u in enemy_units:
		# Direct user report: the drone was hunting a mortar off a fire-detection lead; our own mortar
		# killed it with an unseen shot; the drone dropped the lead and went for a squad instead — "the
		# drone team should not have known that we hit the enemy mortar. No one saw it." Ground truth
		# (u.is_targetable_state()) belongs to the LIVE branch above, where is_visible means the player
		# genuinely does know right now; a stale lead has to go by what the player last found out, not
		# what has happened since. See Unit.is_targetable_state_known_to_player's own doc comment.
		if u.kind != Unit.Kind.MORTAR or not u.is_targetable_state_known_to_player():
			continue
		var info: Dictionary = _last_detected_mortar_fire.get(u, {})
		if info.is_empty():
			continue
		if info.time > best_time:
			best_time = info.time
			best_pos = info.position
			best_unit = u

	if best_unit != null:
		var drone_covering_it := false
		for d in [active_drone, backup_drone]:
			if d != null and d.has_move_target and d.move_target.distance_to(best_pos) < 1.0:
				drone_covering_it = true
				break
		var expiry: float = GameConfig.DRONE_MORTAR_FIRE_LEAD_EXPIRY if drone_covering_it else GameConfig.MORTAR_FIRE_DETECTION_EXPIRY
		if scenario_elapsed_time - best_time <= expiry:
			return {"position": best_pos, "trusted": drone_covering_it, "unit": best_unit}

	var seen_pos := Vector2.INF
	var seen_time := -INF
	var seen_unit: Unit = null
	for u in enemy_units:
		if u.kind != Unit.Kind.MORTAR or not u.is_targetable_state_known_to_player() or is_inf(u.player_known_position.x):
			continue
		if u.player_known_position_time > seen_time:
			seen_time = u.player_known_position_time
			seen_pos = u.player_known_position
			seen_unit = u
	if seen_unit == null:
		return {}
	return {"position": seen_pos, "trusted": false, "unit": seen_unit}


## Which of several simultaneously-visible ACTIVE enemy mortars counts as
## "the" one to track — the one closest to our own mortar (the crew that
## will actually have to close on or fire at it), not whichever happens
## to come first in `candidates`. A real, previously-reported bug: with
## more than one enemy mortar spotted at once, the drone was tracking
## whichever came first in enemy_units (spawn order, unrelated to actual
## distance), which could easily be the FARTHER one — a real crew has no
## reason to prefer a farther, harder-to-reach mortar over a nearer one
## it's already better placed to deal with.
##
## Sticky against `sticky` (the caller's own remembered previous pick) via
## GameConfig.MORTAR_LEAD_SWITCH_MARGIN — with two candidates sitting
## nearly equidistant, ordinary tick-to-tick movement could otherwise flip
## which one "wins" back and forth indefinitely, each flip discarding
## whatever hunt/watch progress the previous pick had already made. A
## different candidate only takes over once it's CLEARLY closer (by more
## than the margin), not merely closer by whatever jitter the current tick
## happens to produce — the same "prefer the least-wrong/best option, but
## don't thrash over a marginal difference" principle already established
## elsewhere in this file (see _prefer_retreat_direction's own budget
## logic for the closest analogue). Deliberately takes and returns the
## sticky value rather than reading/writing shared state itself —
## _known_enemy_mortar_lead and _priority_visible_enemy_mortar's own
## fallback branch call this with two DIFFERENT candidate pools (the
## second always excludes whichever mortar the first already claimed) and
## must not silently overwrite each other's memory of what they were each
## tracking.
##
## Falls back to the first candidate when there's no friendly mortar at
## all to measure distance from (nothing to be "closer" to) — matches
## every other friendly-mortar-relative check's own graceful behavior once
## the gun is lost.
func _closest_enemy_mortar(candidates: Array[Unit], sticky: Unit) -> Unit:
	if candidates.size() == 1:
		return candidates[0]
	var fm := _friendly_mortar()
	if fm == null:
		return candidates[0]
	var origin: Vector2 = fm.global_position
	var best: Unit = candidates[0]
	var best_dist: float = origin.distance_to(best.global_position)
	for u in candidates.slice(1):
		var d: float = origin.distance_to(u.global_position)
		if d < best_dist:
			best = u
			best_dist = d
	if sticky != null and sticky != best and candidates.has(sticky):
		var sticky_dist: float = origin.distance_to(sticky.global_position)
		if sticky_dist - best_dist < GameConfig.MORTAR_LEAD_SWITCH_MARGIN:
			return sticky # not clearly closer enough to switch away from the current pick
	return best


## The single position the mortar/drone team's current joint commitment
## (_joint_mortar_hunt_target) is actually built around, or Vector2.INF if
## nothing usable is known about it THIS tick — live position if currently
## visible, else its last DETECTED fire position (same source
## _known_enemy_mortar_lead uses), never the raw omniscient global_position
## directly: the commitment persists by unit IDENTITY across ticks, but the
## actual position acted on stays exactly as fog-of-war-respecting as
## everything else here.
func _joint_mortar_hunt_known_position() -> Vector2:
	if _joint_mortar_hunt_target == null:
		return Vector2.INF
	if _joint_mortar_hunt_target.is_visible:
		return _joint_mortar_hunt_target.global_position
	var info: Dictionary = _last_detected_mortar_fire.get(_joint_mortar_hunt_target, {})
	if not info.is_empty():
		return info.position
	return Vector2.INF


## The player's single mortar, or null if it's been lost — there's only
## ever one (see MAX_MORTARS_PER_SIDE's own comment: "the player fields
## one; the enemy fields two"), so this is just a lookup, not a priority
## decision the way the enemy's multi-mortar equivalents need to be.
func _friendly_mortar() -> Unit:
	for u in player_units:
		if u.kind == Unit.Kind.MORTAR:
			return u
	return null




## Whether a candidate hunt destination would put the mortar somewhere no
## real crew would ever go: newly AHEAD of its own infantry screen, or
## newly outside the vertical band those squads actually occupy, relative
## to where the mortar already is right now — not an absolute "must
## already be within the line" rule. A mortar is fire support — it stays
## BEHIND the friendly squads holding the line and within the vertical
## band they occupy WHILE ADVANCING toward a hunt, but a crew that's
## already outside that footprint (drifted there by an earlier, unrelated
## self-preservation relocation — shoot-and-scoot, evading a threat,
## whatever pushed it there had nothing to do with hunting) isn't thereby
## permanently barred from ever hunting again just because it can't
## un-drift in one step: only a destination that makes its OWN exposure
## worse than it already is gets rejected here. With no active friendly
## squad left at all to judge a "line" against, there's nothing to violate
## — the home-radius cap is left to do the only judging left possible in
## that case.
func _friendly_mortar_hunt_destination_is_reckless(mortar: Unit, dest: Vector2) -> bool:
	# Both sides' crews are held to this (the name is the player's, from when only they were): "ahead" is
	# toward the enemy, east for the player and west for the enemy.
	var forward: float = 1.0 if mortar.team == Unit.Team.PLAYER else -1.0
	var frontmost := -INF # in the forward direction (x * forward)
	var min_y := INF
	var max_y := -INF
	var found := false
	var own_units: Array[Unit] = player_units if mortar.team == Unit.Team.PLAYER else enemy_units
	for u in own_units:
		if u.kind == Unit.Kind.SQUAD and u.state == Unit.State.ACTIVE:
			found = true
			frontmost = max(frontmost, u.global_position.x * forward)
			min_y = min(min_y, u.global_position.y)
			max_y = max(max_y, u.global_position.y)
	if not found:
		return false
	# Direct user report: "Enemy mortar is advancing in front of their squads. It should not." Before, once
	# the crew found itself ALREADY ahead of its own line (or already outside the band it holds) for any
	# reason at all — its squads fell back, died, or simply hadn't caught up yet — the checks below
	# (guarded by `not already_ahead`/`not already_outside_band`) fell through unconditionally, with
	# nothing left to stop a hunt from sending it even FURTHER out, tick after tick, arbitrarily deep past
	# its own infantry. The narrower, actually-intended tolerance (implied by "NEWLY", never a documented
	# "no limit once exposed") was to let an already-exposed crew keep working — including holding its own
	# ground, or heading back toward the line — not to lift the limit entirely. Folding the mortar's own
	# current position into the same bound it is judged against does exactly that: a destination is
	# reckless if it is more exposed, in either dimension, than the crew already is right now — never a new
	# violation, and never a WORSE one, but no cap at all on recovering.
	var frontier: float = max(frontmost, mortar.global_position.x * forward)
	var band_min: float = min(min_y, mortar.global_position.y)
	var band_max: float = max(max_y, mortar.global_position.y)
	if dest.x * forward > frontier:
		return true
	if dest.y < band_min or dest.y > band_max:
		return true
	return false


## Where `m` was deployed: the leash for anything it does on its own account (a hunt, a relocation) is
## measured from here. INF for an enemy mortar this battle has no record of (then nothing is measured).
func _mortar_home_position(m: Unit) -> Vector2:
	if m.team == Unit.Team.PLAYER:
		return _friendly_mortar_home_position
	return _enemy_mortar_homes.get(m, Vector2.INF)


## Forms and maintains the mortar/drone team's SHARED commitment to
## hunting one specific enemy mortar together — consulted by both
## _mortar_hunt_fix_for/_mortar_hunt_destination_for (where to walk) and
## _drone_search_target (where to fly), instead of each independently re-deriving "is this
## still worth it" every tick from the same raw signal
## (_known_enemy_mortar_lead) with slightly different math of its own (a
## moving mortar's own range check here, a fire-lead's own expiry there).
## That's what actually let the mortar keep walking toward a position the
## drone had already quietly stopped bothering to watch — this exists so
## there's one shared decision instead of two that only coincidentally
## agree.
##
## Formed the instant _known_enemy_mortar_lead reports a TRUSTED fix (live,
## or a drone already closing on it) that no active friendly mortar can
## engage yet, AND the resulting hunt destination would still fall within
## GameConfig.MORTAR_HUNT_MAX_RANGE_FROM_HOME of the mortar's own actual
## deployment position — hunting is good, but there are limits, and it's
## not worth the drone committing its own top-priority attention to
## escorting a hunt the mortar will never actually be allowed to complete.
## An untrusted, bare fire-detection lead never forms a commitment at all
## — that stays the mortar's own solo, distance-capped gamble (see below),
## since there's no drone coverage to actually coordinate with.
##
## Held regardless of how _known_enemy_mortar_lead's own trust/expiry
## re-evaluates on LATER ticks — only let go of when the objective itself
## resolves: the target's no longer a real target (not ACTIVE), some
## friendly mortar can now actually engage it (mission handed off to the
## normal engagement tiers), or GameConfig.JOINT_MORTAR_HUNT_MAX_DURATION
## has simply run out on it (a safety valve, not a normal expiry).
func _update_joint_mortar_hunt() -> void:
	if _joint_mortar_hunt_target != null:
		var still_active: bool = _joint_mortar_hunt_target.state == Unit.State.ACTIVE
		var known_pos: Vector2 = _joint_mortar_hunt_known_position()
		var now_engageable: bool = still_active and not is_inf(known_pos.x) and _can_engage_position(known_pos)
		var timed_out: bool = scenario_elapsed_time - _joint_mortar_hunt_start_time > GameConfig.JOINT_MORTAR_HUNT_MAX_DURATION
		if not still_active or now_engageable or timed_out:
			_joint_mortar_hunt_target = null
		else:
			return # commitment holds — nothing more to decide this tick

	var lead: Dictionary = _known_enemy_mortar_lead()
	if lead.is_empty() or not lead.trusted:
		return
	# A RETREATING mortar can still read as a "trusted" lead (it's still
	# visible, just fleeing — see _known_enemy_mortar_lead's own live-
	# visibility branch, which doesn't distinguish ACTIVE from RETREATING),
	# but it's no longer worth the TEAM's shared reconnaissance commitment:
	# a fleeing crew is a mop-up, not an ongoing threat, and tying the
	# drone to it starves attention away from a still-ACTIVE enemy mortar
	# that hasn't even been found yet. The friendly mortar's own solo
	# pursuit of a fleeing target (_mortar_hunt_fix_for, used directly by
	# tier 2 and the drone's own "supporting friendly action" tier) is
	# untouched by this — this only ever gates the escorted, team-wide
	# commitment.
	if lead.unit.state != Unit.State.ACTIVE:
		return
	if _can_engage_position(lead.position):
		return # already in range — no coordination needed, normal engagement tiers take it from here

	var fm := _friendly_mortar()
	if fm == null:
		return
	var dest := _friendly_mortar_hunt_point(fm, lead.position)
	if dest == fm.global_position or dest.distance_to(_friendly_mortar_home_position) > GameConfig.MORTAR_HUNT_MAX_RANGE_FROM_HOME:
		return # outside what the crew considers safe territory — not worth the drone escorting a hunt that will never actually happen
	if _friendly_mortar_hunt_destination_is_reckless(fm, dest):
		return # would newly put the mortar ahead of, or outside the band held by, its own infantry screen

	_joint_mortar_hunt_target = lead.unit
	_joint_mortar_hunt_start_time = scenario_elapsed_time
	combat_log.log_joint_mortar_hunt(lead.unit)


## Like _mortar_advance_point (a point just inside MORTAR_MAX_RANGE of
## `target_pos`, nudged across a handful of angles to avoid buildings), but
## for the friendly mortar's own hunting move: among the same candidate
## angles, prefers one that ISN'T currently visible from any known enemy
## position (_known_enemy_positions) — the whole point of this function
## existing separately is that the enemy's version doesn't need to care
## whether ITS mortar gets spotted closing the distance, and this one very
## much does. A candidate with NO known threat able to see it is also,
## automatically, one no known SQUAD can actually fire on either — squad
## direct fire itself requires has_direct_los (see _pick_target) — so
## "hidden" already is the genuinely safe case, not just a heuristic.
##
## When NONE of the candidates are fully hidden (a known squad screening the
## target can plausibly see every angle around it), this used to fall back
## to whichever building-clear candidate happened to be checked first,
## regardless of how exposed it actually was — which could walk the mortar
## into full view AND direct-fire range of a known enemy squad just because
## that candidate's angle was tried first. Now picks whichever building-clear
## candidate keeps the most distance from its single nearest known threat
## instead — real standoff, not full concealment, but a meaningful, and
## sometimes decisive, difference: standing off far enough still puts it
## outside SQUAD_ENGAGEMENT_RANGE of that threat even without breaking LOS.
##
## The mortar being hunted itself is excluded from the threat list — every
## candidate sits close to it by construction (that's the whole point), so
## treating it as a threat to hide from would reject every angle equally,
## for no real gain: closing to indirect-fire range doesn't require mutual
## line of sight the way direct fire would, and the actual exposure risk
## this guards against is everyone ELSE near the route, not the one target
## the mortar is already committed to engaging.
func _friendly_mortar_hunt_point(mortar: Unit, target_pos: Vector2) -> Vector2:
	var threats := _known_enemy_positions(mortar.team).filter(func(p): return p.distance_to(target_pos) > 1.0)
	var base_dir: Vector2 = (target_pos - mortar.global_position).normalized()
	var target_distance: float = GameConfig.mortar_max_range(mortar.team) * 0.9 # comfortably in range, not right on the edge

	var valid_candidates: Array[Vector2] = []
	for offset_deg in [0.0, -15.0, 15.0, -30.0, 30.0, -45.0, 45.0]:
		var dir: Vector2 = base_dir.rotated(deg_to_rad(offset_deg))
		var candidate: Vector2 = target_pos - dir * target_distance
		if GameConfig.mortar_barred_at(candidate, mortar.team) or GameConfig.mortar_path_barred(mortar.global_position, candidate, mortar.team):
			continue
		valid_candidates.append(candidate)
		var hidden := true
		for threat in threats:
			if GameConfig.has_direct_los(candidate, threat):
				hidden = false
				break
		if hidden:
			return candidate

	if valid_candidates.is_empty():
		return mortar.global_position # no safe-to-walk-to route at all this tick

	var safest: Vector2 = valid_candidates[0]
	var safest_margin := -1.0
	for candidate in valid_candidates:
		var nearest_threat_dist := INF
		for threat in threats:
			nearest_threat_dist = min(nearest_threat_dist, candidate.distance_to(threat))
		if nearest_threat_dist > safest_margin:
			safest_margin = nearest_threat_dist
			safest = candidate
	return safest


## Runs the whole drone-fleet rotation for one tick — ReconMode.DRONE_TEAM
## only, no-op otherwise. Charges every uninstalled battery a little
## (_battery_pool), finishes any battery-swaps whose timer has run out,
## lands anything that's arrived home (see _update_returning_drones),
## updates the currently-searching sortie and, if one exists, the backup
## shadowing it (see _update_active_drone/_update_backup_drone — either may
## send itself home this tick), then:
## 1. If active_drone was just lost (shot down or sent home) and a backup
##    is already on-station, PROMOTE it instantly — zero coverage gap,
##    which is the entire point of having sent it (see the request this
##    implements: "a replacement drone should be sent to ensure continuous
##    coverage").
## 2. Failing that, launch a fresh one from the ready pool as usual.
## 3. Independently, if active_drone is currently watching a live,
##    engageable enemy mortar (see _visible_engageable_mortar) and a ready
##    airframe exists, launch a backup the instant active_drone's own
##    remaining time-before-RTB shrinks to about how long a fresh launch
##    would take to reach that same spot — timed to arrive right as it's
##    actually needed, not the moment tracking starts (which would just
##    burn the backup's own limited flight time sitting there early) and
##    not reactively after active_drone has already had to leave (which
##    would leave a real gap).
func _update_drone_operations(scenario_delta: float) -> void:
	if recon_mode != GameConfig.ReconMode.DRONE_TEAM or drone_team == null:
		return
	if drone_team.state != Unit.State.ACTIVE:
		# Team destroyed or pulled back — nobody left to fly them. Whatever's
		# airborne (searching, backup, or inbound) is abandoned along with the
		# ground station; no further launches for the rest of the battle.
		# Counted as a loss (not literally shot down, but permanently gone
		# either way) rather than just freed, so the fleet total always stays
		# accounted for — every airframe ends the battle as exactly one of
		# airborne, backup, inbound, ready, swapping, or lost.
		for d in [active_drone, backup_drone] + returning_drones:
			if d != null:
				player_units.erase(d)
				d.queue_free()
				_drones_destroyed += 1
		active_drone = null
		backup_drone = null
		returning_drones.clear()
		return

	# Every uninstalled battery just charges, at a fixed rate, all the time —
	# recharge TIME is a consequence of how much of this actually runs before
	# something needs it, not a separately tracked countdown.
	for i in _battery_pool.size():
		_battery_pool[i] = min(1.0, _battery_pool[i] + scenario_delta / GameConfig.DRONE_RECHARGE_DURATION)

	# A battery that's actually FINISHED charging might as well get staged —
	# there's nothing left to gain by leaving it sitting in the pool, and
	# every airframe eventually wants its own fully-charged spare on hand
	# regardless of whether a launch happens to be imminent. Direct user
	# ruling on the flip side of this (see _drone_required_launch_charge and
	# _update_returning_drones' own doc comment for the bug this whole
	# redesign fixes): "if a battery is charged, you can swap it onto a
	# drone even if we don't need to launch yet. What's wrong is swapping a
	# battery that is still charging if we don't need to launch." Looped,
	# not a single `if`, since more than one battery can cross 1.0 the same
	# tick.
	while _stage_best_battery_if_at_least(1.0):
		pass

	for i in range(_drones_swapping.size() - 1, -1, -1):
		_drones_swapping[i].time_left -= scenario_delta
		if _drones_swapping[i].time_left <= 0.0:
			_drones_ready.append(_drones_swapping[i].charge)
			_drones_swapping.remove_at(i)

	# Every drone in the air is flown by this team, so it is operated on the move whenever the team is.
	var on_the_move := _drone_team_on_the_move()
	var crew_down: int = drone_team.crew_casualties if drone_team != null else 0
	for d in [active_drone, backup_drone] + returning_drones:
		if d != null:
			d.drone_operator_moving = on_the_move
			d.drone_operator_casualties = crew_down

	_update_drone_weather(scenario_delta)
	_update_returning_drones(scenario_delta)

	if active_drone != null:
		_update_active_drone(scenario_delta) # may send itself home, or (rarely) crash outright — see the sacrifice branch inside

	if backup_drone != null:
		_update_backup_drone(scenario_delta) # may send itself home, or get promoted below

	if active_drone == null and backup_drone != null:
		active_drone = backup_drone
		backup_drone = null

	# Direct user report: "Drones got themselves into a situation where they are repeatedly launching with
	# very little charge." The old rule launched the instant ANYTHING was staged, however little charge it
	# actually had — with the ground crew now free to stage a still-charging battery early ONLY when a
	# launch is actually wanted (see _stage_best_battery_if_at_least/_drone_required_launch_charge and
	# _update_returning_drones' own doc comment for the full redesign), a genuinely quiet stretch (nothing
	# known worth spotting) holds out for the pool's next FULLY-charged battery instead of grabbing
	# whatever's best right now — while real urgency (known mortar fire) still launches on much less,
	# scaled down for a nearer target, never below GameConfig.DRONE_MIN_LAUNCH_CHARGE_FLOOR ("never launch
	# below 20%", direct user ruling).
	if active_drone == null and not _drone_grounded_for_weather:
		if _drones_ready.is_empty() and _drones_swapping.is_empty():
			var lead: Dictionary = _known_enemy_mortar_lead()
			if not lead.is_empty():
				_stage_best_battery_if_at_least(_drone_required_launch_charge(lead.position))
		if not _drones_ready.is_empty():
			_launch_drone()

	if active_drone != null and backup_drone == null and not _drones_ready.is_empty() and not _drone_grounded_for_weather:
		var watched: Unit = _visible_engageable_mortar()
		if watched != null:
			var time_until_active_rtb: float = _drone_time_until_rtb(active_drone)
			var backup_travel_time: float = drone_team.global_position.distance_to(watched.global_position) / GameConfig.DRONE_CRUISE_SPEED
			if time_until_active_rtb <= backup_travel_time:
				# Deliberately NOT given the same reactive pool-staging the primary launch above gets: this
				# timing check assumes a near-instant launch the moment it trips (bounded only by flight time
				# to arrive, not any ground delay) — a fresh swap-from-pool takes a full DRONE_BATTERY_SWAP_
				# DURATION (a few minutes) to prep, which is longer than the RTB window this check is
				# actually racing against, so reactively staging one here would routinely finish AFTER
				# active_drone has already had to turn for home anyway. Stays limited to a battery that's
				# already sitting staged from the passive "anything fully charged gets staged regardless"
				# pass in _update_drone_operations — a real, pre-existing limitation (a backup mission can
				# only happen if the fleet happened to have a spare already prepped), not something this
				# session's charge-discipline fix is trying to solve.
				_launch_backup_drone(watched)


## The ground crew's own self-preservation, mirroring the mortar's tier-1
## "spotted/threat closing" relocation but for an unarmed rear element that
## never fires and has nothing to hold onto — "would consider evasive
## action, especially if [a threat] appears likely to come very close," not
## a hard trigger the moment anything is merely nearby. Only reconsiders
## while not already mid-relocation (has_move_target) — once moving, it
## just walks there rather than restarting toward a new pick every tick a
## threat happens to still qualify.
##
## A known enemy only counts if it's actually CLOSING — heading roughly
## toward the crew's own current position (_estimate_unit_velocity's
## direction has a positive component toward it), not just happening to sit
## within range while moving away or across. Risk slides with proximity
## (0 at DRONE_TEAM_EVASION_RANGE, 1.0 at zero distance) and the actual
## roll uses risk squared — a threat that's merely inside the watch range
## barely registers, one that's genuinely closed to danger range reliably
## triggers, matching "especially if... very close" rather than an equal
## chance across the whole watch range. Takes the single most dangerous
## known threat, same `max`-across-candidates pattern the mortar's own
## danger scoring uses, not an average.
func _update_drone_team_evasion() -> void:
	if drone_team != null and unit_doctrine_for(drone_team).risk != "inherit": return
	if recon_mode != GameConfig.ReconMode.DRONE_TEAM or drone_team == null:
		return
	if drone_team.state != Unit.State.ACTIVE or drone_team.has_move_target:
		return
	# Direct user report: "The drone team came under mortar fire. Now it is withdrawing. But given that it
	# took no casualties, I don't understand why it is withdrawing. Relocating would be reasonable." Fixed
	# at the source (Unit._apply_crew_casualties now gives a DRONE_TEAM the same "holds position" roll a
	# MORTAR crew already gets, rather than unconditionally retreating over any hit at all) — but a crew
	# that holds still needs to actually MOVE for "relocating" to mean anything. The ordinary risk trigger
	# just below only reacts to a currently VISIBLE, closing ground threat; a mortar shell lands from a
	# tube that is very often neither, so it would otherwise hold in place and never actually reposition.
	# Bypasses that roll outright, the same unconditional-once-triggered treatment _decide_mortar_action's
	# own tier 1 gives a mortar crew for evading_counter_battery — but reads Unit.taking_fire instead of
	# that flag: direct user correction, "Fire at the drone team is not counter battery fire," since a
	# drone team never fires anything and so can never draw an actual counter-battery response.
	var urgent_evasion: bool = drone_team.taking_fire
	var risk := 0.0
	if not urgent_evasion:
		for e in enemy_units:
			var still_a_threat: bool = e.state == Unit.State.ACTIVE or e.state == Unit.State.RETREATING
			if not still_a_threat or not e.is_visible:
				continue
			var to_team: Vector2 = drone_team.global_position - e.global_position
			var dist: float = to_team.length()
			if dist > GameConfig.DRONE_TEAM_EVASION_RANGE:
				continue
			var velocity: Vector2 = _estimate_unit_velocity(e)
			if velocity == Vector2.ZERO or velocity.normalized().dot(to_team.normalized()) <= 0.0:
				continue # stationary, or heading away/across rather than toward the team
			risk = max(risk, clamp(1.0 - dist / GameConfig.DRONE_TEAM_EVASION_RANGE, 0.0, 1.0))
		if risk <= 0.0 or randf() >= risk * risk:
			return
	var threats := _known_enemy_positions(Unit.Team.PLAYER)
	# The trailing explicit defaults here (avoid_buildings through firing_point)
	# exist only so danger_range can be reached positionally (GDScript has no
	# keyword args) — see nearest_hidden_point's own doc comment on why this
	# must be DRONE_TEAM_EVASION_RANGE, not the mortar-scaled default: a real,
	# reported bug ("mortar team seems to be fleeing towards enemy squads")
	# traced to this exact call using the mortar's own much tighter 750m
	# standoff instead of the 1200m scale this team's own trigger above uses.
	var destination: Vector2 = GameConfig.nearest_hidden_point(drone_team.global_position, threats, false, false, [], Vector2.INF, INF, 0.0, [], [], Vector2.ZERO, Vector2.INF, GameConfig.DRONE_TEAM_EVASION_RANGE)
	if destination == drone_team.global_position:
		# Direct user report: cornered by an enemy squad with nowhere left to hide, the team just sat
		# there and did nothing — this exact "try again next tick" used to be the whole plan, but a
		# squad actively closing the distance every tick doesn't leave a better hiding spot to find on a
		# later attempt; it only gets closer. "I know I objected to a drone team retreat earlier. But the
		# recent situation is one where they would have retreated even without casualties, because they
		# had nowhere else to go to escape." Mirrors the mortar's own last-resort flee
		# (_mortar_flee_as_last_resort) when ITS OWN concealment search comes up empty under real
		# pressure — a genuine withdrawal, not silence.
		#
		# Scoped to a real, closing GROUND threat specifically (the `risk` trigger, i.e. `not
		# urgent_evasion`) — NOT a bare taking_fire with nothing actually closing in: a mortar shell can
		# land with no one nearby to physically overrun the crew, so that case keeps retrying next tick
		# as before, same as the mortar's own "only an unarmed observer" exclusion keeps a sighted-but-
		# not-threatened mortar crew in place rather than fleeing over nothing.
		if not urgent_evasion:
			drone_team.taking_fire = false
			drone_team.order_retreat(threats, [], "Cornered: no safe place to relocate to.")
			combat_log.log_ordered_retreat(drone_team)
		return
	drone_team.taking_fire = false
	drone_team.move_target = destination
	drone_team.has_move_target = true
	drone_team.move_queue.clear()
	drone_team.move_speed = GameConfig.REPOSITION_SPEED
	drone_team.movement_predictable = false
	combat_log.log_drone_team_evading(drone_team)


## Removes and returns the single highest-charge battery from `pool`
## (which is always non-empty when this is called on _battery_pool — see
## GameConfig's comment on why 8 batteries for 4 airframes guarantees
## that) — "the team might launch a drone with a partly charged battery"
## means always grabbing the best available, not waiting around for 100%.
func _pop_best_battery(pool: Array[float]) -> float:
	var best_index := 0
	for i in pool.size():
		if pool[i] > pool[best_index]:
			best_index = i
	var charge: float = pool[best_index]
	pool.remove_at(best_index)
	return charge


## If _battery_pool's own best-charged entry is at or above `min_charge`, pops it and starts swapping it
## in (same mechanism a real landing used to trigger unconditionally — see _update_returning_drones' own
## doc comment) — returns whether it actually did. Two callers, two very different bars: the per-tick
## "anything that just finished charging might as well get staged" pass in _update_drone_operations
## (min_charge=1.0 — a full battery has nothing left to gain sitting in the pool) and the reactive
## "we actually want to launch now" checks just below it (min_charge=_drone_required_launch_charge's own,
## distance-scaled, urgency-gated result — pulling a battery that's STILL charging out early is only ever
## justified when a launch is genuinely wanted right now, see the direct user correction on
## _update_returning_drones).
func _stage_best_battery_if_at_least(min_charge: float) -> bool:
	if _battery_pool.is_empty() or _airframes_awaiting_battery <= 0:
		return false # no battery to stage, or no bare airframe on the ground to put one into
	var best_index := 0
	for i in _battery_pool.size():
		if _battery_pool[i] > _battery_pool[best_index]:
			best_index = i
	if _battery_pool[best_index] < min_charge:
		return false
	_airframes_awaiting_battery -= 1
	_drones_swapping.append({"time_left": GameConfig.DRONE_BATTERY_SWAP_DURATION, "charge": _pop_best_battery(_battery_pool)})
	return true


## How much charge a sortie to `target_pos` and back actually costs — the real round trip (climb, the leg
## out, the leg back, the same arrival safety reserve an already-airborne drone's own RTB decision holds
## back — see _drone_time_until_rtb/_drone_arrival_reserve_charge) — clamped to GameConfig.DRONE_MIN_
## LAUNCH_CHARGE_FLOOR at the low end (direct user ruling, "never launch below 20%", regardless of how
## close the target is or how cheap the computed trip comes out) and to 1.0 at the high end (a trip that
## would need more than a full charge to complete safely isn't a trip to launch on speculatively at all —
## same as the "no known target worth spotting" quiet case, which callers pass Vector2.INF for and get
## 1.0 back unchanged).
##
## Direct user framing for the two ends of this scale: "If there is firing that needs spotting, it would
## go ahead and launch with as little as 50% I think" (a fairly typical stand-off distance) "or even less
## if the target is close" — this function IS that sliding scale, not a fixed 50%; a target close enough
## to be cheap to reach costs less than 50% here, and a farther one costs more, both derived from the same
## real flight-cost math everything else in this file already uses rather than a separate guessed number.
func _drone_required_launch_charge(target_pos: Vector2) -> float:
	if is_inf(target_pos.x) or drone_team == null:
		return 1.0
	var round_trip: float = GameConfig.DRONE_LAUNCH_CHARGE_COST + _drone_leg_charge(drone_team.global_position, target_pos) + _drone_leg_charge(target_pos, drone_team.global_position) + _drone_arrival_reserve_charge()
	return clamp(round_trip, GameConfig.DRONE_MIN_LAUNCH_CHARGE_FLOOR, 1.0)


func _launch_drone() -> void:
	var charge: float = _pop_best_battery(_drones_ready)
	var d := _make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, drone_team.global_position)
	d.drone_battery_charge = max(charge - GameConfig.DRONE_LAUNCH_CHARGE_COST, 0.0) # climb-out to DRONE_ALTITUDE_M isn't free — see GameConfig's own comment
	d.state_changed.connect(_on_drone_state_changed)
	d.move_speed = GameConfig.DRONE_CRUISE_SPEED
	d.drone_operator_moving = _drone_team_on_the_move()
	player_units.append(d)
	active_drone = d
	combat_log.log_drone_launched(d)


## A second sortie sent up specifically to shadow whatever active_drone is
## currently watching (see _update_backup_drone) — launched with just
## enough lead time to arrive as active_drone's own RTB gets close (see
## the timing check in _update_drone_operations), not the instant tracking
## starts, so it doesn't burn its own limited flight time sitting on
## station early. Never becomes the search-priority decision-maker itself;
## it just follows along until either promoted (see _update_drone_
## operations) or sent home because it's no longer needed or is running
## low itself.
func _launch_backup_drone(watched: Unit) -> void:
	var charge: float = _pop_best_battery(_drones_ready)
	var d := _make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, drone_team.global_position)
	d.drone_battery_charge = max(charge - GameConfig.DRONE_LAUNCH_CHARGE_COST, 0.0) # climb-out to DRONE_ALTITUDE_M isn't free — see GameConfig's own comment
	d.state_changed.connect(_on_drone_state_changed)
	d.move_speed = GameConfig.DRONE_CRUISE_SPEED
	d.drone_operator_moving = _drone_team_on_the_move()
	player_units.append(d)
	backup_drone = d
	combat_log.log_drone_backup_launched(d, watched)


## Only ever fires for a genuine shoot-down — a routine return-to-base never
## sets DESTROYED (it lands and is freed in _update_returning_drones once it
## arrives), and a sacrificed drone's battery dying is handled directly by
## _crash_drone rather than through this signal, so its log message doesn't
## get mislabeled as a shoot-down. Bumps the permanent loss count (that
## airframe never flies again this battle) and clears whichever slot held
## it — active, backup, or already inbound — so _update_drone_operations's
## own promotion/launch checks pick up the slack next tick.
func _on_drone_state_changed(unit: Unit) -> void:
	if unit.state != Unit.State.DESTROYED:
		return
	if unit == active_drone:
		active_drone = null
	elif unit == backup_drone:
		backup_drone = null
	elif returning_drones.has(unit):
		returning_drones.erase(unit)
	else:
		return
	_drones_destroyed += 1
	combat_log.log_drone_shot_down(unit)


## Depletes this sortie's battery charge (see GameConfig.
## DRONE_FULL_CHARGE_FLIGHT_TIME — the flight-time a full charge is worth)
## and, if there's still enough left to be worth it, re-picks where it
## flies next — every tick, not set once, so it reacts immediately to a
## freshly-spotted mortar or a shoot-and-scoot relocation instead of
## plodding toward a stale point (see _drone_search_target).
##
## Charge hitting zero is checked FIRST, unconditionally, before anything
## else: a drone with no battery left doesn't glide home on fumes, it falls
## (_crash_drone) — full stop, regardless of how it got there. Normally
## that's only actually reachable via the deliberate sacrifice below (a
## drone that chose to keep watching past its safety margin, draining
## further each tick until it's genuinely dry); a real DJI Mavic 3 doesn't
## fly on a truly empty battery either way, and since v72 added a real
## charge cost to LAUNCHING (see GameConfig.DRONE_LAUNCH_CHARGE_COST), an
## already-critically-low battery popped for a fresh sortie could in
## principle hit zero before ever getting a chance to turn for home —
## this catches that case too, not just the sacrifice one.
##
## Short of that, once the remaining charge is only just enough to get home
## (with DRONE_RTB_SAFETY_MARGIN worth to spare), it normally hands off
## search duty and turns for home — UNLESS it's currently watching a live,
## engageable enemy mortar (_visible_engageable_mortar) with no backup
## already on-station to take over: in that specific case it sacrifices
## itself instead, deliberately ignoring the safety margin and continuing
## to watch until the top-of-function check above catches it running dry.
## This is re-evaluated every tick, not decided once — if a backup shows
## up, the mortar dies/retreats/leaves range, or the friendly mortar itself
## is lost partway through (making the target no longer engageable), the
## sacrifice is abandoned immediately and it heads home with whatever's left.
func _update_active_drone(scenario_delta: float) -> void:
	var d := active_drone
	d.drone_battery_charge -= scenario_delta * _drone_drain_per_second(d)

	if d.drone_battery_charge <= 0.0:
		_crash_drone(d, _visible_engageable_mortar())
		active_drone = null
		return

	var planned_destination := Vector2.INF
	if unit_doctrine_for(d).risk != "inherit":
		planned_destination = _drone_search_target()
		if _drone_search_exhausted or not _drone_risk_accepts(d, planned_destination):
			_send_drone_home(d)
			active_drone = null
			return

	if _drone_should_rtb(d):
		if backup_drone == null:
			var watched: Unit = _visible_engageable_mortar()
			if watched != null and _can_engage_position(watched.global_position):
				# Sacrifice continues -- fall through to keep watching,
				# ignoring RTB, until the zero-charge check above ends it.
				d.move_target = _drone_search_target() if is_inf(planned_destination.x) else planned_destination
				d.has_move_target = true
				d.move_queue.clear()
				d.move_speed = _drone_airspeed_toward(d.global_position, d.move_target)
				d.movement_predictable = false
				return
		_send_drone_home(d)
		active_drone = null
		return

	var destination: Vector2 = _drone_search_target() if is_inf(planned_destination.x) else planned_destination
	if _drone_search_exhausted:
		# Nothing left worth flying to that the battery can reach AND come
		# back from — the sortie is over; bring the airframe (and what's left
		# of its charge) home rather than crawl toward a cell it can't afford.
		_send_drone_home(d)
		active_drone = null
		return
	d.move_target = destination
	d.has_move_target = true
	d.move_queue.clear()
	d.move_speed = _drone_airspeed_toward(d.global_position, d.move_target)
	d.movement_predictable = false


## The battery a drone drains per second at the airspeed it is actually
## flying: the plain rate (1 / full-charge flight time) scaled by that speed's
## power factor (GameConfig.drone_power_factor — faster costs more). A drone
## with no real speed yet (just launched) counts as cruise.
func _drone_drain_per_second(d: Unit) -> float:
	# Clamped to the real range of airspeeds (cruise..max): a drone that has
	# not been given a speed yet carries the generic unit default, which is not
	# an airspeed at all and must never be read as one.
	var airspeed: float = clampf(d.move_speed, GameConfig.DRONE_CRUISE_SPEED, GameConfig.DRONE_MAX_AIRSPEED)
	return GameConfig.drone_power_factor(airspeed) / _drone_full_charge_flight_time()


## True for the tick _drone_search_target found routine targets to visit but
## none the drone can afford (see _drone_can_afford_target), with nothing
## more urgent to do — _update_active_drone then sends it home.
var _drone_search_exhausted: bool = false


## Set by _drone_routine_recon_target when it had candidates but the filter
## left none (see _drone_search_target's "Nothing reachable" outcome).
var _drone_routine_pool_unaffordable: bool = false


## The backup never makes its own search decisions or sacrifices itself —
## its only two jobs are shadowing whatever active_drone is currently
## watching (so it's actually in position to be promoted with zero gap,
## not just airborne somewhere) and coming home normally the instant either
## it runs low itself, or its job is done because active_drone has moved on
## / the mortar it was shadowing no longer qualifies (destroyed, retreated,
## or otherwise stopped being what active_drone is watching).
##
## Same zero-charge rule as _update_active_drone: a backup never
## deliberately sacrifices itself, but it can still, in principle, launch
## on an already-critically-low battery (see GameConfig.
## DRONE_LAUNCH_CHARGE_COST) and hit zero before its own RTB check ever
## gets a chance to send it home — that's still a fall, not a graceful
## landing, checked first and unconditionally.
func _update_backup_drone(scenario_delta: float) -> void:
	var d := backup_drone
	d.drone_battery_charge -= scenario_delta * _drone_drain_per_second(d)

	if d.drone_battery_charge <= 0.0:
		_crash_drone(d, _visible_engageable_mortar())
		backup_drone = null
		return

	var watched: Unit = _visible_engageable_mortar()
	if watched == null or _drone_should_rtb(d) or not _drone_risk_accepts(d, watched.global_position):
		_send_drone_home(d)
		backup_drone = null
		return

	d.move_target = watched.global_position
	d.has_move_target = true
	d.move_queue.clear()
	d.move_speed = _drone_airspeed_toward(d.global_position, d.move_target)
	d.movement_predictable = false


## Advances the weather (see Weather.advance) and logs precipitation starting,
## stopping, or changing class.
func _update_weather(scenario_delta: float) -> void:
	if weather == null:
		return
	weather.advance(scenario_delta)
	var label: String = weather.precip_label()
	if label != _last_precip_label:
		combat_log.log_weather_change(_last_precip_label, label)
		_last_precip_label = label


## Flight time a full battery is worth right now — cold cuts it (Weather.
## drone_cold_flight_time_factor).
func _drone_full_charge_flight_time() -> float:
	return GameConfig.DRONE_FULL_CHARGE_FLIGHT_TIME * (weather.drone_cold_flight_time_factor() if weather != null else 1.0)


## Ground speed (px/s) along `dir` for a drone flying at `airspeed` (px/s):
## crabs into the wind at its own flight altitude (Weather.ground_speed).
##
## `with_gusts` false uses the MEAN wind — what a pilot PLANS with (the turn-
## home decision, the return airspeed), as opposed to what the drone actually
## experiences moment to moment while moving.
func _drone_ground_speed(airspeed: float, dir: Vector2, with_gusts: bool = true) -> float:
	if weather == null:
		return airspeed
	var wind_px: Vector2 = weather.wind_velocity_mps(weather.drone_operating_altitude_m(), with_gusts) * GameConfig.PIXELS_PER_METER
	return Weather.ground_speed(airspeed, dir, wind_px)


## The airspeed a drone should fly along `dir` (a unit vector): the one that
## spends the LEAST BATTERY PER GROUND METER — drain rate at that airspeed
## (GameConfig.drone_power_factor) divided by the ground speed it makes good
## in the current wind (crab and all — see _drone_ground_speed). That is the
## user's stated metric ("battery expended per ground meter traveled"), and
## it applies to EVERY leg — outbound, search, and home — not just the
## return: DRONE_CRUISE_SPEED in still air (and in a tailwind, where slower
## isn't considered), rising toward DRONE_MAX_AIRSPEED (Sport mode) as a
## headwind makes the cruise-speed crawl expensive per meter. Picks the
## SLOWEST speed within DRONE_RETURN_ENERGY_TOLERANCE of the best, so a
## windless leg stays at exactly cruise (the true still-air optimum is only
## ~0.15% better). Planned on the MEAN wind, never the instantaneous gust.
func _drone_best_airspeed(dir: Vector2) -> float:
	var cruise: float = GameConfig.DRONE_CRUISE_SPEED
	if weather == null or dir == Vector2.ZERO:
		return cruise
	var candidates: Array[float] = []
	var costs: Array[float] = []
	var best_cost: float = INF
	var speed: float = cruise
	var step: float = GameConfig.DRONE_RETURN_SPEED_STEP_MPS * GameConfig.PIXELS_PER_METER
	while speed <= GameConfig.DRONE_MAX_AIRSPEED + 0.0001:
		var cost: float = GameConfig.drone_power_factor(speed) / _drone_ground_speed(speed, dir, false)
		candidates.append(speed)
		costs.append(cost)
		best_cost = minf(best_cost, cost)
		speed += step
	for i in candidates.size():
		if costs[i] <= best_cost * (1.0 + GameConfig.DRONE_RETURN_ENERGY_TOLERANCE):
			return candidates[i]
	return cruise


## The best airspeed for a drone at `from_pos` heading for `to_pos` (cruise if
## it's already there).
func _drone_airspeed_toward(from_pos: Vector2, to_pos: Vector2) -> float:
	var offset: Vector2 = to_pos - from_pos
	if offset.length() <= 1.0:
		return GameConfig.DRONE_CRUISE_SPEED
	return _drone_best_airspeed(offset.normalized())


## The flight home: the best airspeed from `from_pos` back to the ground crew.
func _drone_return_airspeed(from_pos: Vector2) -> float:
	if drone_team == null:
		return GameConfig.DRONE_CRUISE_SPEED
	return _drone_airspeed_toward(from_pos, drone_team.global_position)


## The battery (as a fraction of a full charge) a drone spends flying the
## straight leg from `from_pos` to `to_pos` at its best airspeed on the mean
## wind — distance x (battery per ground meter). Direction matters: the same
## distance costs far more into a headwind than with a tailwind.
func _drone_leg_charge(from_pos: Vector2, to_pos: Vector2) -> float:
	var distance: float = from_pos.distance_to(to_pos)
	if distance <= 1.0:
		return 0.0
	var dir: Vector2 = (to_pos - from_pos) / distance
	var airspeed: float = _drone_best_airspeed(dir)
	return distance / _drone_ground_speed(airspeed, dir, false) * GameConfig.drone_power_factor(airspeed) / _drone_full_charge_flight_time()


## The charge a drone must keep back once it has finished its business at some
## point and is coming home: the turn-home safety margin plus the letdown cost.
func _drone_arrival_reserve_charge() -> float:
	return GameConfig.DRONE_RTB_SAFETY_MARGIN / GameConfig.DRONE_CRUISE_SPEED / _drone_full_charge_flight_time() + GameConfig.DRONE_LANDING_CHARGE_COST


## Can `d` fly to `point`, and still get home from there with the safety
## reserve intact? The full round trip from where it is now, in the wind as
## it is — a sweep cell a long way upwind that the battery can reach but
## never come back from is not a place to go.
func _drone_can_afford_target(d: Unit, point: Vector2) -> bool:
	if drone_team == null:
		return true
	var needed: float = _drone_leg_charge(d.global_position, point) + _drone_leg_charge(point, drone_team.global_position) + _drone_arrival_reserve_charge()
	return d.drone_battery_charge >= needed


func _drone_detection_range() -> float:
	return GameConfig.DRONE_DETECTION_RANGE * (weather.drone_detection_scale() if weather != null else 1.0)


## Rain/snow at or above Weather.DRONE_BLIND_FROM_MM_H blinds the camera at once: whatever is searching
## is recalled (a flight home, in the same weather) and nothing launches until
## the precipitation has stayed below Weather.DRONE_RESUME_BELOW_MM_H for
## Weather.DRONE_RESUME_AFTER_S. Then, for every airborne drone, the per-minute
## failure chance (Weather.drone_hazard_per_minute: wind, precipitation, cold).
func _update_drone_weather(scenario_delta: float) -> void:
	if weather == null:
		return
	if weather.drone_vision_blocked():
		_drone_grounded_for_weather = true
		_drone_weather_clear_s = 0.0
		var recalled: Array[Unit] = []
		for d in [active_drone, backup_drone]:
			if d != null:
				recalled.append(d)
		active_drone = null
		backup_drone = null
		for d in recalled:
			combat_log.log_drone_recalled_by_rain(d, weather.precip_label())
			_drones_recalled_by_rain += 1
			_send_drone_home(d)
	elif _drone_grounded_for_weather:
		if weather.precip_mm_h < Weather.DRONE_RESUME_BELOW_MM_H:
			_drone_weather_clear_s += scenario_delta
			if _drone_weather_clear_s >= Weather.DRONE_RESUME_AFTER_S:
				_drone_grounded_for_weather = false
				combat_log.log_drones_resume()
		else:
			_drone_weather_clear_s = 0.0

	var altitude: float = weather.drone_operating_altitude_m()
	var failure_chance: float = _drone_failure_chance(scenario_delta, altitude)
	var airborne: Array[Unit] = []
	for d in [active_drone, backup_drone] + returning_drones:
		if d != null:
			airborne.append(d)
	for d in airborne:
		if weather.rng.randf() < failure_chance:
			_weather_fail_drone(d, altitude)


## The chance, over `scenario_delta` tactical seconds, that an airborne drone fails:
## Weather.drone_hazard_per_minute (baseline, wind, cold, rain), multiplied by
## GameConfig.DRONE_TEAM_MOVING_FAILURE_MULTIPLIER while its team is on the move.
func _drone_failure_chance(scenario_delta: float, altitude: float) -> float:
	var hazard: float = weather.drone_hazard_per_minute(altitude)
	if _drone_team_on_the_move():
		hazard *= GameConfig.DRONE_TEAM_MOVING_FAILURE_MULTIPLIER
	return 1.0 - exp(-hazard * scenario_delta / 60.0)


## A weather failure: usually the airframe is lost; a search drone (never one
## in moderate-or-worse rain, which is already flying home) sometimes only
## aborts and heads home instead (Weather.DRONE_ABORT_SHARE).
func _weather_fail_drone(d: Unit, altitude: float) -> void:
	var cause: String = weather.drone_hazard_cause(altitude)
	var was_search: bool = d == active_drone or d == backup_drone
	if was_search and not weather.drone_vision_blocked() and weather.rng.randf() < Weather.DRONE_ABORT_SHARE:
		combat_log.log_drone_weather_abort(d, cause)
		_drones_aborted_by_weather += 1
		if d == active_drone:
			active_drone = null
		else:
			backup_drone = null
		_send_drone_home(d)
		return
	combat_log.log_drone_weather_loss(d, cause)
	if d == active_drone:
		active_drone = null
	elif d == backup_drone:
		backup_drone = null
	else:
		returning_drones.erase(d)
	player_units.erase(d)
	d.queue_free()
	_drones_destroyed += 1
	_drones_lost_to_weather += 1


## True once `d`'s remaining charge is down to just enough to cover the
## trip home plus GameConfig.DRONE_RTB_SAFETY_MARGIN worth of reserve — the
## shared threshold both active_drone (which can choose to ignore it and
## sacrifice itself instead) and backup_drone (which never does) check.
func _drone_should_rtb(d: Unit) -> bool:
	return _drone_time_until_rtb(d) <= 0.0


## How much longer `d` can keep doing whatever it's doing right now (flight
## time, not charge) before it hits its own RTB threshold — the time-domain
## twin of _drone_should_rtb (which is just "is this already <= 0"), used
## by the eager-backup-launch trigger to time a launch against, not just
## test a yes/no. Assumes roughly its current distance from home holds
## steady, which is exactly true while it's station-keeping over a fixed
## target (the case this actually matters for) and a reasonable estimate
## otherwise, re-evaluated fresh every tick regardless.
func _drone_time_until_rtb(d: Unit) -> float:
	# Planned the way a pilot would: on the MEAN wind (not this instant's
	# gust), at the airspeed the flight home will actually use (faster into a
	# headwind — see _drone_best_airspeed), paying that speed's higher battery
	# drain for the whole trip. Also reserves the turn-home safety margin and
	# the letdown cost it'll actually be charged the moment it lands (see
	# GameConfig.DRONE_LANDING_CHARGE_COST) — without this, a drone could turn
	# for home with "just enough," fly the whole way back, and land with less
	# charge than it actually has left to give.
	var charge_needed_to_get_home: float = _drone_leg_charge(d.global_position, drone_team.global_position) + _drone_arrival_reserve_charge()
	var charge_to_spare: float = d.drone_battery_charge - charge_needed_to_get_home
	return charge_to_spare * _drone_full_charge_flight_time()


## Hands off search/shadow duty and turns `d` for a real, simulated flight
## home (added to returning_drones) — rather than simply vanishing, so it
## stays a legal, visible target the whole way back, same as before.
func _send_drone_home(d: Unit) -> void:
	combat_log.log_drone_returning(d)
	d.move_target = drone_team.global_position
	d.has_move_target = true
	d.move_queue.clear()
	d.move_speed = GameConfig.DRONE_CRUISE_SPEED
	d.movement_predictable = true # a direct beeline home now, not an erratic search
	returning_drones.append(d)


## The battery hits zero — the airframe is lost right where it stood, not
## "shot down" (see _on_drone_state_changed's own comment on why this
## bypasses that signal/log path entirely) but gone all the same: no
## landing, no battery to recover, just a permanent loss counted the same
## way. `watched`, if non-null (whatever _visible_engageable_mortar()
## currently returns — usually genuinely what it was sacrificing itself
## over, but this fires the same way regardless of exact cause, see
## _update_active_drone/_update_backup_drone), gets the sacrifice-flavored
## log message; otherwise a plain battery-died one.
func _crash_drone(d: Unit, watched: Unit = null) -> void:
	if watched != null:
		combat_log.log_drone_sacrificed(d, watched)
	else:
		combat_log.log_drone_battery_died(d)
	player_units.erase(d)
	d.queue_free()
	_drones_destroyed += 1


## Every sortie currently flying home (see _send_drone_home) — same generic
## movement system as everything else (_tick_movement, called earlier in
## _process) actually steps each one toward drone_team's position since
## it's ACTIVE with has_move_target set; this just watches for arrival
## (_step_toward_target clears has_move_target the instant one reaches
## drone_team) and lands it for real: free the Unit, and drop whatever
## charge it landed with (usually just the small safety-margin reserve,
## though a backup sent home early could have much more) back into the pool
## to keep charging from there — landing never means the full ~100-minute
## recharge for the AIRFRAME; only running the whole pool down does that,
## and even then only to whichever battery it draws next.
##
## Direct user correction: this used to ALSO immediately pop the pool's own
## best-charged battery into a swap right here, on the theory that the next
## airframe should always have something staged and ready. "If a battery is
## charged, you can swap it onto a drone even if we don't need to launch
## yet. What's wrong is swapping a battery that is still charging if we
## don't need to launch" — a landing is not, on its own, a reason to need
## one: pulling out whatever's currently best (quite possibly still well
## short of full) just freezes its charge in _drones_ready/_drones_swapping
## instead of letting it keep climbing in the pool, for no benefit if
## nothing is actually about to fly. See _update_drone_operations' own
## per-tick "stage anything that's finished charging" pass (_drones_ready
## only ever holds fully-charged batteries now) and _drone_required_launch_
## charge (a still-charging battery is only ever pulled early when a launch
## is genuinely wanted and that battery already clears the bar for it).
func _update_returning_drones(scenario_delta: float) -> void:
	for i in range(returning_drones.size() - 1, -1, -1):
		var d: Unit = returning_drones[i]
		if d.has_move_target:
			# Re-aimed every tick at wherever the ground crew currently is,
			# not just wherever it was the instant RTB was ordered — see
			# _update_drone_team_evasion, which can move it mid-flight.
			# Mirrors the mortar resupply run's own "always chase the
			# mortar's current position" tracking for the same reason.
			d.move_target = drone_team.global_position
			# Flies home at whatever airspeed the wind calls for (Sport mode
			# into a headwind — see _drone_return_airspeed) and pays for it:
			# the flight home DRAINS the battery, faster the faster it flies
			# (GameConfig.drone_power_factor), and a battery that runs dry
			# on the way is a lost airframe, exactly like any other flight
			# (direct user requirement). This used to be free — a returning
			# drone never drained at all, so it could never fail to arrive
			# for lack of charge and always banked its whole turn-home
			# reserve back into the pool.
			d.move_speed = _drone_return_airspeed(d.global_position)
			d.drone_battery_charge -= scenario_delta * GameConfig.drone_power_factor(d.move_speed) / _drone_full_charge_flight_time()
			if d.drone_battery_charge <= 0.0:
				_crash_drone(d)
				returning_drones.remove_at(i)
			continue # still en route
		returning_drones.remove_at(i)
		player_units.erase(d)
		# The letdown back to the ground isn't free either — see GameConfig.
		# DRONE_LANDING_CHARGE_COST; _drone_time_until_rtb already reserves
		# for this so it's not normally a surprise, but clamp at 0 regardless.
		_battery_pool.append(max(d.drone_battery_charge - GameConfig.DRONE_LANDING_CHARGE_COST, 0.0))
		_airframes_awaiting_battery += 1 # the airframe itself is still here, bare, until a battery is staged
		d.queue_free()


## How worried `team`'s side should still be that an as-yet-undiscovered
## OPPOSING mortar exists — see GameConfig.MORTAR_CONFIDENCE_DECAY_TAU/_FLOOR
## for the full reasoning. Two cases: a hard, certain 0.0 once every opposing
## mortar is KNOWN out of action — player_known_state/enemy_known_state, not
## ground truth; direct user correction, reversing this function's own earlier
## reasoning: "It should be based on what friendly units know, not just
## what the drone knows. But a friendly unit would have to know that the
## mortar is destroyed. The info will not magically appear from some other
## channel" — there is no higher-echelon briefing in this game, only what
## a side's own units have actually seen. "Seen withdrawing" (RETREATING)
## is good enough on its own — this does not require having gone on to see
## it actually reach WITHDRAWN. "Seen gun abandoned" also counts on its own,
## independent of state — "if we see the enemy team without the gun, or the
## gun without the team" (player_known_gun_abandoned/enemy_known_gun_abandoned).
## A mortar never sighted at all defaults to *_known_state ACTIVE and
## *_known_gun_abandoned false (Unit.gd's own defaults), which is exactly
## right here: an undiscovered mortar IS the residual risk this function
## exists to estimate, not something already ruled out. Short of every mortar
## being known out of action, a smooth decay from ~1.0 toward FLOOR as real
## tactical time passes with no mortar fire detected anywhere at all
## (_last_detected_mortar_fire — muzzle-flash/trajectory detection, not
## visual spotting, so this already covers a mortar that's never been seen
## even once — itself already knowledge-based, unchanged).
##
## `team` defaults to PLAYER (every pre-existing call site — the drone's own
## routine-recon weighting and the player mortar's own ammo-conservation
## hold — asks about the player's knowledge of the enemy, unchanged).
## Team-parameterized (direct user instruction, re a spotted mortar's
## willingness to fire: "This should apply to both sides") so a mortar's own
## spotted-but-otherwise-unthreatened decision (_decide_mortar_action) can
## ask the same "might an opposing mortar still be out there" question on
## behalf of EITHER side, symmetrically — enemy_known_state/enemy_known_
## gun_abandoned mirror the player-side fields exactly (_update_enemy_intel).
func _mortar_existence_confidence(team: Unit.Team = Unit.Team.PLAYER) -> float:
	var opposing: Array[Unit] = enemy_units if team == Unit.Team.PLAYER else player_units
	var any_known_active_opposing_mortar := false
	var last_fire_time := 0.0 # battle start, if nothing's fired yet at all
	for u in opposing:
		if u.kind != Unit.Kind.MORTAR:
			continue
		var known_state: Unit.State = u.player_known_state if team == Unit.Team.PLAYER else u.enemy_known_state
		var known_gun_abandoned: bool = u.player_known_gun_abandoned if team == Unit.Team.PLAYER else u.enemy_known_gun_abandoned
		if known_state == Unit.State.ACTIVE and not known_gun_abandoned:
			any_known_active_opposing_mortar = true
		var info: Dictionary = _last_detected_mortar_fire.get(u, {})
		if not info.is_empty():
			last_fire_time = max(last_fire_time, info.time)
	if not any_known_active_opposing_mortar:
		return 0.0
	var elapsed: float = scenario_elapsed_time - last_fire_time
	return GameConfig.MORTAR_CONFIDENCE_FLOOR + (1.0 - GameConfig.MORTAR_CONFIDENCE_FLOOR) * exp(-elapsed / GameConfig.MORTAR_CONFIDENCE_DECAY_TAU)


## Distance from `pos` to the nearest ACTIVE unit of `team` (PLAYER, the
## default, unless told otherwise), or INF if none remain — shared by
## _squad_danger_priority (how threatening an advancing enemy is — to the
## drone's own PLAYER side by default, or to whichever side is doing the
## judging when _target_danger_to_force asks on a MORTAR's behalf) and
## _drone_search_target's own tie-break among multiple visible retreating
## enemies (which one's actually closest to being able to fight, or be
## fought, right now).
func _nearest_active_friendly_distance(pos: Vector2, team: Unit.Team = Unit.Team.PLAYER) -> float:
	var units: Array[Unit] = player_units if team == Unit.Team.PLAYER else enemy_units
	var nearest := INF
	for f in units:
		# A drone is not a force an enemy squad "threatens" by being near it: counting it made a squad
		# the drone was itself hovering over read as at contact with a friendly (danger 10/10), so the
		# drone kept tracking whichever squad it was over, however far from our positions.
		if f.state == Unit.State.ACTIVE and f.kind != Unit.Kind.DRONE:
			var d: float = pos.distance_to(f.global_position)
			if f.kind == Unit.Kind.SPOTTER:
				d *= SPOTTER_NEARNESS_DISCOUNT # "the spotter should have only a very minor affect on what to track"
			nearest = min(nearest, d)
	return nearest


## A squad near the spotter counts as this many times farther from our forces than it is, so the
## spotter barely raises a squad's danger (no scenario has both a spotter and a drone team, so this is
## only the light touch the user asked for). JUDGMENT.
const SPOTTER_NEARNESS_DISCOUNT: float = 10.0


## "Approaching" means heading within 60 degrees of straight at the unit (a squad crossing our front
## at right angles is not approaching it, though its heading has a small component toward it).
const DRONE_APPROACH_MIN_COSINE: float = 0.5


## Which visible enemy squad the drone should track, in the user's order of priority: "enemy squads
## that are threatening the mortar would have higher priority than ones that are not. If nothing is
## threatening the mortar, next would be enemy squads that are approaching our squads." (Prompted by
## a live battle: no enemy mortars left, every enemy squad advancing on us, and the drone tracking a
## far-off one instead of the near ones.) Three classes, best first:
##   2  threatens a friendly mortar: within SQUAD_DANGER_RANGE of it and not moving away from it
##   1  approaching our squads: heading toward a friendly squad, or already within
##      SQUAD_ENGAGEMENT_RANGE of one. The drone team counts as a squad here ("a threat to the drone
##      team would however count. It would be similar to a threat to a squad"); an airborne drone
##      never counts as one of our units for judging what threatens what.
##   0  any other visible squad
## Within a class the squad closest to what it threatens wins (to the mortar for class 2, else to our
## ground forces, see _squad_danger_priority). Returns {"unit", "score", "why"}, or {} with no visible
## squad. The score is the ordinary danger score (0 to TARGET_PRIORITY_SQUAD_MAX), raised to the squad's
## nearness to the mortar for class 2, so comparing it with the other tiers is unchanged in kind.
func _drone_squad_to_track() -> Dictionary:
	var mortars: Array[Unit] = []
	var squads: Array[Unit] = [] # our squads, and the drone team: a threat to it counts like a threat to a squad
	for f in player_units:
		if f.state != Unit.State.ACTIVE:
			continue
		if f.kind == Unit.Kind.MORTAR:
			mortars.append(f)
		elif f.kind == Unit.Kind.SQUAD or f.kind == Unit.Kind.DRONE_TEAM:
			squads.append(f)
	var best: Dictionary = {}
	var best_rank := [-1, -1.0]
	var tracked_pick: Dictionary = {} # the squad tracked last time, IF it is still a candidate now
	var tracked_rank := [-1, -1.0]
	for u in enemy_units:
		if u.kind != Unit.Kind.SQUAD or u.state != Unit.State.ACTIVE or not u.is_visible:
			continue
		var velocity: Vector2 = _estimate_unit_velocity(u)
		var score: float = _squad_danger_priority(u)
		var klass := 0
		var why := "The most dangerous currently-visible enemy squad (closer to our units = higher)"
		var threat_proximity := score
		for m in mortars:
			var to_mortar: Vector2 = m.global_position - u.global_position
			var dist: float = to_mortar.length()
			if dist <= GameConfig.SQUAD_DANGER_RANGE and (velocity == Vector2.ZERO or velocity.dot(to_mortar) >= 0.0):
				var proximity: float = GameConfig.TARGET_PRIORITY_SQUAD_MAX * clampf(1.0 - dist / GameConfig.SQUAD_DANGER_RANGE, 0.0, 1.0)
				if klass < 2 or proximity > threat_proximity:
					klass = 2
					threat_proximity = proximity
					why = "An enemy squad threatening the mortar (%.0f m from it)" % (dist / GameConfig.PIXELS_PER_METER)
		if klass < 2:
			for f in squads:
				var to_squad: Vector2 = f.global_position - u.global_position
				if to_squad.length() <= GameConfig.SQUAD_ENGAGEMENT_RANGE or (velocity != Vector2.ZERO and velocity.normalized().dot(to_squad.normalized()) > DRONE_APPROACH_MIN_COSINE):
					klass = 1
					why = "An enemy squad approaching our squads" if f.kind == Unit.Kind.SQUAD else "An enemy squad approaching the drone team"
					break
		var rank := [klass, threat_proximity]
		var pick := {"unit": u, "score": maxf(score, threat_proximity) if klass == 2 else score, "why": why}
		if u == _drone_tracked_squad:
			tracked_pick = pick
			tracked_rank = rank
		if rank[0] > best_rank[0] or (rank[0] == best_rank[0] and rank[1] > best_rank[1]):
			best_rank = rank
			best = pick
	# Direct user report, live: the drone kept "changing its mind between enemy squads 1 and 3" (one far in
	# the north, one far in the south: "it went partway up, then partway down, back and forth"). The pick
	# above is a bare argmax of (class, nearness) every tick, so two squads of about equal danger trade the
	# lead with every few meters of ordinary movement, and the drone swings to follow whichever is ahead
	# this tick. A squad already being tracked keeps the drone unless:
	#   - it is no longer a candidate at all (out of sight, retreating, dead): replaced at once;
	#   - the rival has just come to threaten the friendly mortar and the tracked squad does not: at once;
	#   - the rival is CLEARLY more dangerous in nearness (DRONE_SQUAD_SWITCH_FACTOR/_MARGIN): at once;
	#   - the tracked squad WAS threatening the mortar and no longer is (it moved away): released at once;
	#   - the rival is merely in a higher class (e.g. heading toward our squads now, where the tracked one is
	#     not) — a class is judged from a squad's heading, which can wobble — and the tracked squad has been
	#     held for at least DRONE_SQUAD_MIN_DWELL_S, long enough to actually fly there and look.
	if not tracked_pick.is_empty() and best.unit != _drone_tracked_squad:
		var mortar_threat: bool = best_rank[0] == 2 and tracked_rank[0] < 2
		var clearly_nearer: bool = best_rank[0] >= tracked_rank[0] and best_rank[1] > tracked_rank[1] * GameConfig.DRONE_SQUAD_SWITCH_FACTOR + GameConfig.DRONE_SQUAD_SWITCH_MARGIN
		var class_gain: bool = best_rank[0] > tracked_rank[0]
		var threat_over: bool = _drone_tracked_class == 2 and tracked_rank[0] < 2
		var dwelled: bool = scenario_elapsed_time - _drone_tracked_since >= GameConfig.DRONE_SQUAD_MIN_DWELL_S
		if not (mortar_threat or clearly_nearer or threat_over or (class_gain and dwelled)):
			best = tracked_pick
	var picked: Unit = best.get("unit", null)
	if picked != _drone_tracked_squad:
		_drone_tracked_squad = picked
		_drone_tracked_since = scenario_elapsed_time
	_drone_tracked_class = int(tracked_rank[0]) if (not tracked_pick.is_empty() and picked == tracked_pick.get("unit", null)) else int(best_rank[0])
	return best


## A visible, ACTIVE enemy squad's own target-priority score — see
## GameConfig.TARGET_PRIORITY_SQUAD_MAX/SQUAD_DANGER_RANGE. Danger is
## judged by proximity to the nearest ACTIVE unit of `threatened_team`
## (PLAYER by default, matching the drone's own — always PLAYER-side —
## use of this; _target_danger_to_force passes the assessing unit's own
## team instead, since a mortar judges danger to ITS side, not unconditionally
## the player's) — the closer `u` is to actually being able to fight
## someone, the more it matters, ramping smoothly from 0 at
## SQUAD_DANGER_RANGE up to the max right at contact, rather than a hard
## in-range/out-of-range step.
func _squad_danger_priority(u: Unit, threatened_team: Unit.Team = Unit.Team.PLAYER) -> float:
	var nearest_friendly_dist: float = _nearest_active_friendly_distance(u.global_position, threatened_team)
	if is_inf(nearest_friendly_dist):
		return 0.0
	return GameConfig.TARGET_PRIORITY_SQUAD_MAX * clamp(1.0 - nearest_friendly_dist / GameConfig.SQUAD_DANGER_RANGE, 0.0, 1.0)


## Records every currently-visible ACTIVE enemy unit's position as a real,
## recent contact — see _contact_search_bonus, which is what actually acts
## on this memory. Called once per tick from _drone_search_target. Kept as
## a live position + timestamp per unit (not a permanent list) so a
## contact's influence fades the same way a mortar fire-detection lead
## does (GameConfig.DRONE_CONTACT_BONUS_EXPIRY) rather than persisting
## forever or vanishing the instant the unit itself drops out of LOS.
##
## Also folds in _last_detected_mortar_fire — the "known mortar location"
## half of mortar-hunting, as distinct from _mortar_deployment_likelihood's
## "possible" half. A mortar is essentially never actually SEEN (is_visible
## rarely applies to it — see the doc's own established fire-detection
## pattern), so without this, a real muzzle-flash/trajectory detection
## would only ever inform the single top-priority "fresh lead" tier in
## _drone_search_target and then vanish entirely from the search the
## instant GameConfig.DRONE_MORTAR_FIRE_LEAD_EXPIRY passes — real, hard-won
## intelligence just disappearing rather than continuing to inform the
## broader search at reduced confidence, the same way it would for any
## other kind of contact. _last_detected_mortar_fire already stores
## {"position", "time"} in exactly the shape _recent_enemy_contacts uses,
## so this is a direct merge, not a parallel mechanism.
func _update_recent_enemy_contacts() -> void:
	_note_lost_contacts_checked()
	for u in enemy_units:
		if u.state == Unit.State.ACTIVE and u.is_visible:
			_recent_enemy_contacts[u] = {"position": u.global_position, "time": scenario_elapsed_time}
			if not _contact_watch_since.has(u):
				_contact_watch_since[u] = scenario_elapsed_time
			continue
		_contact_watch_since.erase(u)
		if u.kind == Unit.Kind.MORTAR and u.state == Unit.State.ACTIVE:
			var info: Dictionary = _last_detected_mortar_fire.get(u, {})
			if not info.is_empty():
				_recent_enemy_contacts[u] = info


## Enemy squads the player knew of, that went out of sight and where nothing was seen when the drone
## went to look: Unit -> scenario time it was checked. Such a squad is not chased again for
## LOST_CONTACT_RECHECK_S (or until it is seen again).
var _lost_contact_checked: Dictionary = {}
## A sighting stops being worth flying to when enough time has passed that the squad could be in a
## different part of the map ("Too old would be if enough time has elapsed that the enemy could be in a
## different part of the map"): a third of the map's width, at the enemy's advance pace. The age it comes
## to depends on the map (about 20 minutes on a 5 km one).
const LOST_CONTACT_DIFFERENT_PART_FRACTION: float = 1.0 / 3.0
## Direct user report, live: the drone flying a real, committed leg (routine sweep or flank watch) would
## abruptly reverse toward a squad's last-known position, then reverse right back again seconds later,
## without the squad ever having actually stayed lost — a genuine "going back and forth" the user
## specifically warned might be an old bug resurfacing under a new tier. Root cause, confirmed directly
## against a live, running battle (this codebase's own established diagnostic method): a squad that is
## merely visible for a single tick (a momentary LOS blink through a tree edge, a building corner, or the
## edge of detection range — real, ordinary occurrences, not a malfunction) makes `_lost_squad_contacts`
## stop listing it entirely THAT tick (it is, technically, not lost right then), which in turn makes its
## "lost:%d" key vanish from `_drone_routine_recon_target`'s own candidate pool for that one tick — and
## since `_drone_commitment_has_collapsed`'s sticky-until-arrival protection only ever runs when the
## CURRENT key is still present to compare against, a vanished key skips that whole check and forces a
## completely fresh, unprotected pick, discarding a real, already-committed leg for whatever wins that one
## tick. The instant the squad drops out of sight again (often the very next tick), `player_known_position_
## time` resets to that instant, so it reappears in the pool as if freshly lost all over again — at
## LOST_CONTACT_VALUE_MAX, well above an ordinary sweep cell — legitimately winning the fresh pick outright
## and sending the drone chasing a lead that was never actually a sustained loss of contact to begin with.
## The fix does not try to patch the key-vanishing mechanism itself (a real, working design elsewhere — see
## _drone_routine_recon_target's own doc comment on a flank bearing correctly dropping out once genuinely
## screened) — it addresses the actual, narrower defect: a bare, momentary loss should not be able to
## generate a maximum-value lead in the first place. A real "lost contact" report presumes the observer has
## had a moment to confirm the squad is actually gone, not merely obscured for an instant — the same
## reasoning TREE_SIGHT_LOSS_GRACE_S already applies to a target flickering in and out of trees, generalized
## here to the drone's own reaction to any loss, not just what counts as still "seeing" it.
const LOST_CONTACT_MIN_AGE_S: float = 8.0


func _lost_contact_expiry_s() -> float:
	return GameConfig.MAP_WIDTH_PX * LOST_CONTACT_DIFFERENT_PART_FRACTION / GameConfig.ENEMY_ADVANCE_SPEED
const LOST_CONTACT_RECHECK_S: float = 300.0
## What a place we lost a squad at is worth among the routine-recon candidates (the sweep cells run from
## about 0.3 to 1.1 with a contact bonus): from LOST_CONTACT_VALUE_MIN for a sighting about to expire to
## LOST_CONTACT_VALUE_MAX for a fresh one, plus up to LOST_CONTACT_THREAT_VALUE for one close to our
## forces (nothing beyond LOST_CONTACT_THREAT_RANGE).
const LOST_CONTACT_VALUE_MIN: float = 1.2
const LOST_CONTACT_VALUE_MAX: float = 2.5
const LOST_CONTACT_THREAT_VALUE: float = 1.5
const LOST_CONTACT_THREAT_RANGE: float = 3000.0 * GameConfig.PIXELS_PER_METER


## The lost contacts the drone has now reached and found nothing at: the squad is not where it was.
func _note_lost_contacts_checked() -> void:
	if active_drone == null or not is_instance_valid(active_drone):
		return
	for u in enemy_units:
		if u.kind != Unit.Kind.SQUAD:
			continue
		if u.is_visible:
			_lost_contact_checked.erase(u)
			continue
		if not u.player_has_been_sighted or _lost_contact_checked.has(u):
			continue
		if active_drone.global_position.distance_to(u.player_known_position) <= _drone_detection_range() * 0.5:
			_lost_contact_checked[u] = scenario_elapsed_time


## "We know the area the enemy is in. The drone is not going there. That's wrong." The enemy squads the
## player has seen and lost sight of, still believed active, last seen recently enough (see
## _lost_contact_expiry_s) that they are probably still near where they were: what the drone should go
## and look at. Only what the player knows: the last known position and state, never the squad's true
## one. Not a squad the drone has already been to and found nothing at (_note_lost_contacts_checked)
## until LOST_CONTACT_RECHECK_S has passed. Each entry: {"unit", "position", "age", "freshness" (1 just
## seen, 0 at the expiry)}.
func _lost_squad_contacts() -> Array:
	var out: Array = []
	for u in enemy_units:
		if u.kind != Unit.Kind.SQUAD or u.is_visible or not u.player_has_been_sighted:
			continue
		if u.player_known_state != Unit.State.ACTIVE:
			continue
		var age: float = scenario_elapsed_time - u.player_known_position_time
		if age < LOST_CONTACT_MIN_AGE_S:
			continue
		var expiry: float = _lost_contact_expiry_s()
		if age > expiry:
			continue
		if _lost_contact_checked.has(u) and scenario_elapsed_time - _lost_contact_checked[u] < LOST_CONTACT_RECHECK_S:
			continue
		out.append({"unit": u, "position": u.player_known_position, "age": age, "freshness": clampf(1.0 - age / expiry, 0.0, 1.0)})
	return out


## Direct user report: "Current drone behavior is crazy. We have seen a lot of enemies in the North. It
## should track them." (The live battle: ten enemy squads in sight, a mortar suspected, and the drone
## flying to a sweep cell at the far south-east because it had committed to it, and because a squad far from
## our units is worth nothing to the tracking tier while routine recon, weighted by the suspected mortar,
## is worth dozens.) The enemy force we can see, as candidates in the routine-recon pool: the visible
## ACTIVE squads grouped into clusters (squads within FORCE_CLUSTER_RADIUS of a group's centre), each at
## its centre (only those of at least FORCE_MIN_SQUADS: "a lot of enemies"), worth FORCE_VALUE_BASE plus FORCE_VALUE_PER_SQUAD for each squad in it (at most
## FORCE_VALUE_MAX): well above any grid cell, so the drone watches a force it can see before it goes
## looking anywhere else. Keyed by its lowest squad id, so the choice is stable as the squads move.
func _visible_force_candidates() -> Array:
	var clusters: Array = [] # each: {"units": [Unit], "sum": Vector2}
	for u in enemy_units:
		if u.kind != Unit.Kind.SQUAD or u.state != Unit.State.ACTIVE or not u.is_visible:
			continue
		var placed := false
		for c in clusters:
			if u.global_position.distance_to(c.sum / c.units.size()) <= FORCE_CLUSTER_RADIUS:
				c.units.append(u)
				c.sum += u.global_position
				placed = true
				break
		if not placed:
			clusters.append({"units": [u], "sum": u.global_position})
	var out: Array = []
	for c in clusters:
		if c.units.size() < FORCE_MIN_SQUADS:
			continue # one or two squads in sight, far from anyone, do not outweigh the search for a mortar
		var lowest: int = c.units[0].get_instance_id()
		for u in c.units:
			lowest = mini(lowest, u.get_instance_id())
		out.append({"key": "force:%d" % lowest, "point": c.sum / c.units.size(), "count": c.units.size(),
			"value": minf(FORCE_VALUE_BASE + FORCE_VALUE_PER_SQUAD * c.units.size(), FORCE_VALUE_MAX)})
	return out


const FORCE_CLUSTER_RADIUS: float = 800.0 * GameConfig.PIXELS_PER_METER
## "A lot of enemies": fewer squads than this are not a force worth leaving the mortar search for.
const FORCE_MIN_SQUADS: int = 4
const FORCE_VALUE_BASE: float = 1.5
const FORCE_VALUE_PER_SQUAD: float = 0.25
const FORCE_VALUE_MAX: float = 4.0


## The lost squads as candidates in the drone's routine-recon pool (with the sweep cells and flank gaps),
## so that however the routine search is weighed against the other tiers (it can be worth a lot when a
## mortar is suspected), the places the enemy was last seen are among what it chooses from — and the best
## of them. Worth more than any grid cell, more for a fresher sighting and for one near our forces.
func _lost_contact_candidates() -> Array:
	var out: Array = []
	for c in _lost_squad_contacts():
		var threat: float = clampf(1.0 - _nearest_active_friendly_distance(c.position) / LOST_CONTACT_THREAT_RANGE, 0.0, 1.0)
		out.append({"key": "lost:%d" % c.unit.get_instance_id(), "point": c.position, "unit": c.unit, "age": c.age,
			"value": lerpf(LOST_CONTACT_VALUE_MIN, LOST_CONTACT_VALUE_MAX, c.freshness) + LOST_CONTACT_THREAT_VALUE * threat})
	return out


## How much extra value a routine-recon candidate at `point` gets for being
## near a real, recent enemy contact (_update_recent_enemy_contacts) — a
## spotted squad or mortar rarely operates in isolation, so an actual,
## confirmed sighting is genuine evidence more of the enemy might be
## nearby, and the drone's default search should be drawn OUTWARD around a
## contact rather than treating a sighting as "nothing more to see here."
## This is what replaced the old dedicated vicinity-search circle: instead
## of committing the WHOLE drone to orbiting one exact spot, a contact just
## makes nearby sweep/flank-watch candidates more attractive within the
## SAME shared pool, so it still competes fairly against distance cost and
## recency (and can't cause the same lock-on the circle used to) while
## actually shifting where the general search goes. Tapers with both how
## long ago the contact was made (GameConfig.DRONE_CONTACT_BONUS_EXPIRY)
## and how far `point` is from it (GameConfig.DRONE_CONTACT_BONUS_RADIUS),
## so the closest, freshest ground to a sighting is favored well above the
## far edge of a stale one. Takes the single best-supported contact rather
## than summing every nearby one, to avoid an implausible pile-up of value
## where several separate sightings happen to cluster.
func _contact_search_bonus(point: Vector2) -> float:
	var bonus := 0.0
	for u in _recent_enemy_contacts:
		var info: Dictionary = _recent_enemy_contacts[u]
		var age: float = scenario_elapsed_time - info.time
		if age >= GameConfig.DRONE_CONTACT_BONUS_EXPIRY:
			continue
		var dist: float = point.distance_to(info.position)
		if dist >= GameConfig.DRONE_CONTACT_BONUS_RADIUS:
			continue
		var age_factor: float = 1.0 - age / GameConfig.DRONE_CONTACT_BONUS_EXPIRY
		if _contact_watch_since.has(u):
			var watched_s: float = scenario_elapsed_time - _contact_watch_since[u]
			age_factor *= lerp(1.0, GameConfig.DRONE_CONTACT_WATCH_FLOOR, clamp(watched_s / GameConfig.DRONE_CONTACT_WATCH_FADE_S, 0.0, 1.0))
		var dist_factor: float = 1.0 - dist / GameConfig.DRONE_CONTACT_BONUS_RADIUS
		bonus = max(bonus, GameConfig.DRONE_CONTACT_BONUS_VALUE * age_factor * dist_factor)
	return bonus


## Where the airborne drone flies next, re-evaluated every tick — a genuine
## TARGET PRIORITY comparison (GameConfig.TARGET_PRIORITY_*), not hard-coded
## "mortars always win": whichever candidate scores highest right now wins,
## so a future third target kind only needs its own scoring term, not a
## rewrite of this decision. Candidates, each mapped to an actual position:
## (1) any currently visible, still-ACTIVE enemy mortar at all
## (_priority_visible_enemy_mortar) — deliberately NOT gated on whether
## it's currently engageable (that stricter question is _visible_
## engageable_mortar's own, used only by the backup/self-sacrifice
## decisions): losing contact on a confirmed live mortar just because the
## friendly mortar can't reach it THIS INSTANT would waste the one asset
## actually watching it, and the situation can change (either mortar can
## reposition). One matching some active friendly mortar's own hunt-fix
## (_is_priority_hunt_target — i.e. actually oriented toward engaging it,
## soon or already) scores the full TARGET_PRIORITY_MORTAR and practically
## always wins outright; one nobody has any near-term plan for scores the
## much lower DRONE_NON_PRIORITY_MORTAR_WATCH_VALUE instead, so a real
## squad threat (below) can compete for the drone's attention rather than
## it hanging over every mortar it's ever spotted regardless of whether
## anything's about to be done about it; (2) the freshest in-range fire-
## detection lead on any ACTIVE mortar, discounted somewhat for being a
## stale position rather than a live one, but still real evidence rather
## than speculation; (3) the mortar/drone team's own shared joint hunting
## commitment (_joint_mortar_hunt_target, formed and held by
## _update_joint_mortar_hunt — see its own doc comment), at full mortar
## priority and deliberately NOT range-gated the way (1)/(2) are, since
## its entire purpose is keeping the drone on-station over a target the
## friendly mortar is still walking toward and hasn't reached range of
## yet; (3b) the general case behind (3) — the drone backs up whatever
## important friendly action is actually committed to and in progress
## right now, not just a formally-promoted shared commitment; today's
## only instance is any individual friendly mortar's OWN hunt, live and
## already committed to (_mortar_move_intent == "hunt"), even when it
## never qualified for (3)'s team-wide commitment (that one only ever
## forms for a TRUSTED lead — a mortar acting alone on a bare, untrusted
## one is a real, deliberate solo gamble the drone still needs to
## support, not a plan it's unaware of); (4) the single most dangerous currently-visible ACTIVE enemy
## squad — scored AND flown at that squad's own live position
## (_squad_danger_priority): an active, closing threat is worth keeping
## direct eyes on for its own sake. Whether more enemies might be nearby
## is a SEPARATE question, answered by _contact_search_bonus feeding tier
## (6) below rather than by circling this squad specifically — spreading
## the search outward through the shared pool instead of committing the
## whole drone to orbiting one exact spot, which is what an earlier
## version of this tier did (a fixed-radius circle) before it became
## clear that just meant a real sighting had no visible effect on the
## broader search at all; (5) the nearest currently-visible RETREATING
## enemy (squad, or a mortar crew that's abandoned its gun for good — that counts as
## "retreating," not "the mortar priority," the instant it happens) —
## scored one of two very different ways depending on whether the battle
## is actually still going: high (TARGET_PRIORITY_RETREATING_ENEMY, a real
## kill worth finishing) once the enemy's own general retreat means little
## else is left to search for; low (TARGET_PRIORITY_RETREATING_ENEMY_LOW)
## while the fight is still on, so one broken straggler doesn't distract
## from whatever's still actually fighting; (6) routine background recon
## (_drone_routine_recon_target) — the area sweep grid and the mortar's
## flank-watch merged into ONE shared candidate pool, since both are really
## the same underlying activity (idle patrol with no specific live lead to
## chase) and a single flight can pick up sweep coverage AND a flank check
## in the same trip rather than the two competing to be "the" routine
## choice. Every candidate in that pool also gets a value bump for sitting
## near a real, recent sighting (_contact_search_bonus) — a spotted enemy
## is genuine evidence more of them might be close by, so the pool is what
## actually turns "we found one" into "now check around here more," not a
## dedicated mechanism of its own.
##
## Whether this WHOLE tier is worth doing at all (as opposed to tiers 1-5
## above) is `max` of two independently-judged things, not one blended
## number: the genuine expected value of an as-yet-undiscovered mortar
## (GameConfig.TARGET_PRIORITY_UNDISCOVERED_MORTAR_SWEEP times
## _mortar_existence_confidence(), which naturally decays the longer no
## mortar fire is detected anywhere — deliberately its own, lower-valued
## constant rather than reusing TARGET_PRIORITY_MORTAR: that one prices a
## mortar we can actually act on, seen or committed to; a merely POSSIBLE
## second mortar nobody's found yet is a fundamentally more speculative
## question and shouldn't inherit the same weight, or it could out-bid a
## genuinely dangerous, already-visible squad on pure conjecture) OR a
## fixed standing value whenever the mortar's flank-watch actually has an
## open gap to check right now (GameConfig.DRONE_FLANK_WATCH_STANDING_
## PRIORITY). These have to stay independent: watching the mortar's blind
## side is a standing duty that matters regardless of how confident anyone
## is that a SECOND mortar exists, so it must not fade out just because
## that confidence has — an earlier version of this tier used one blended,
## fully-confidence-scaled score for both, which meant that once
## confidence decayed (as it does in most battles well before they end),
## an already-spotted squad's own tracking priority (tier 4, capped at
## TARGET_PRIORITY_SQUAD_MAX) could out-bid the ENTIRE routine tier
## indefinitely, including flank-watch — the drone would fixate on one
## contact and stop checking the mortar's flanks or sweeping for anything
## new at all. That last term is what lets the drone's default search
## effort shift naturally toward tracking real, visible squads (advancing
## OR retreating) instead of an indefinite mortar-shaped sweep once mortar
## fire hasn't been detected in a long while, or every known enemy mortar
## is confirmed out of action — without ever hard-coding either condition
## directly here. Tier (4)'s own candidate pool empties out on its own once
## the enemy commander orders a general retreat (every ACTIVE squad is
## pulled into RETREATING in that same instant — see
## _check_enemy_commander_retreat) — there's usually nothing left
## "advancing" to search for at that point. The mortar-confidence half of
## tier (6) is ALSO directly discounted (GameConfig.SWEEP_DISCOUNT_DURING_
## ENEMY_RETREAT) the instant that same general retreat is ordered, on top
## of whatever the slower, generic confidence decay has already done — a
## commander who's just called off the attack has little reason left to
## keep searching broadly for new arrivals, and this makes that immediate
## rather than waiting on the same decay curve built for "no mortar fire in
## a while." The flank-watch half is untouched by that discount — an
## unscreened gap toward the mortar is exactly as worth checking whether or
## not the enemy has called a general retreat.
func _drone_search_target() -> Vector2:
	_drone_search_exhausted = false
	_update_recent_enemy_contacts()
	if active_drone != null and unit_doctrine_for(active_drone).targeting != "inherit":
		var chosen := _forecast_target(active_drone)
		if chosen != null:
			_drone_pilot_reasoning = {"tier": "Per-type observation priority", "detail": "%s selected %s." % [unit_doctrine_for(active_drone).targeting, chosen.display_name()], "target": chosen.global_position}
			return _clamp_to_drone_operating_area(chosen.global_position)


	var best_score := -1.0
	var best_pos := Vector2.INF

	var watched_mortar: Dictionary = _priority_visible_enemy_mortar()
	if not watched_mortar.is_empty():
		var watched: Unit = watched_mortar.unit
		best_pos = watched.global_position
		if watched_mortar.priority:
			best_score = GameConfig.TARGET_PRIORITY_MORTAR
			_drone_pilot_reasoning = {"tier": "Live mortar contact", "detail": "Watching a confirmed, currently visible enemy mortar we're actually oriented to engage.", "target": best_pos}
		else:
			best_score = GameConfig.DRONE_NON_PRIORITY_MORTAR_WATCH_VALUE
			_drone_pilot_reasoning = {"tier": "Live mortar contact (no near-term plan)", "detail": "Watching a visible enemy mortar, but nothing's currently oriented to actually engage it — discounted so a real squad threat can compete for attention.", "target": best_pos}

	var lead_pos := Vector2.INF
	var best_lead_time := -INF
	var lead_is_fire_detection := false
	for u in enemy_units:
		# A second, independent occurrence of the same unseen-kill bug (see _known_enemy_mortar_lead's
		# own fix): this tier re-derives its own fire-detection lead straight from enemy_units instead of
		# going through that function, with the identical ground-truth mistake — player_known_state, not
		# the mortar's real, possibly more current state, is what the player actually has to go on.
		if u.kind != Unit.Kind.MORTAR or u.player_known_state != Unit.State.ACTIVE:
			continue
		var candidate_pos := Vector2.INF
		var candidate_time := -INF
		var candidate_is_fire := false
		var info: Dictionary = _last_detected_mortar_fire.get(u, {})
		if not info.is_empty() and scenario_elapsed_time - info.time <= GameConfig.DRONE_MORTAR_FIRE_LEAD_EXPIRY:
			candidate_pos = info.position
			candidate_time = info.time
			candidate_is_fire = true
		# Direct user report: "The drone just briefly saw an enemy mortar. Said mortar then disappeared
		# from view. But even this brief sighting should be enough to cause the drone team to be aware of
		# the mortar's existence and approximate location." A mortar that is merely SEEN, never fired
		# while visible, left no _last_detected_mortar_fire trace at all — this tier used to have nothing
		# to say about it once it went out of sight, even though _known_enemy_mortar_lead's own third
		# fallback (player_known_position, no expiry — "a real crew doesn't forget where a gun was last
		# seen") already exists for exactly this. Only overrides a fire-detection candidate if it is
		# actually fresher; a real muzzle flash is still better evidence than an old sighting.
		if u.player_has_been_sighted and not is_inf(u.player_known_position.x) and u.player_known_position_time > candidate_time:
			candidate_pos = u.player_known_position
			candidate_time = u.player_known_position_time
			candidate_is_fire = false
		if is_inf(candidate_pos.x):
			continue
		if _drone_lead_is_spent(u, candidate_pos, candidate_time):
			continue
		if not _in_friendly_mortar_range(candidate_pos) or not _squad_order_permits_mortar_watch(candidate_pos):
			continue
		if candidate_time > best_lead_time:
			best_lead_time = candidate_time
			lead_pos = candidate_pos
			lead_is_fire_detection = candidate_is_fire
	if not is_inf(lead_pos.x):
		var lead_score: float = GameConfig.TARGET_PRIORITY_MORTAR * GameConfig.TARGET_PRIORITY_MORTAR_LEAD_DISCOUNT
		if lead_score > best_score:
			best_score = lead_score
			best_pos = lead_pos
			var lead_age: float = scenario_elapsed_time - best_lead_time
			if lead_is_fire_detection:
				_drone_pilot_reasoning = {"tier": "Fresh mortar fire-detection lead", "detail": "Muzzle-flash/trajectory fix on an enemy mortar, %.0fs old, still in friendly mortar range." % lead_age, "target": best_pos}
			else:
				_drone_pilot_reasoning = {"tier": "Last-seen mortar position", "detail": "Not currently visible, but was seen %.0fs ago and hasn't been ruled out since — still in friendly mortar range." % lead_age, "target": best_pos}

	# The team's shared joint commitment (_update_joint_mortar_hunt, run
	# earlier this same tick) — full mortar priority, and deliberately NOT
	# gated by _in_friendly_mortar_range the way tiers (1)/(2) above are:
	# the whole reason this commitment exists is to keep the drone right
	# where the friendly mortar needs it WHILE that mortar is still closing
	# the distance and thus still out of range. Losing that coverage mid-
	# hunt, because the ordinary range-gated tiers had nothing to say about
	# a target that isn't in range YET, was the actual bug.
	if _joint_mortar_hunt_target != null:
		var joint_pos: Vector2 = _joint_mortar_hunt_known_position()
		if not is_inf(joint_pos.x) and GameConfig.TARGET_PRIORITY_MORTAR > best_score and _squad_order_permits_mortar_watch(joint_pos):
			best_score = GameConfig.TARGET_PRIORITY_MORTAR
			best_pos = joint_pos
			_drone_pilot_reasoning = {"tier": "Joint mortar hunt", "detail": "Staying on-station over a target the friendly mortar is still closing on but hasn't reached range of yet.", "target": best_pos}

	# The general principle behind the tier just above, not something
	# specific to it: the drone should back up whatever important friendly
	# action is actually in progress right now, not just a shared, formally-
	# promoted commitment. Today the only such action this game models is a
	# mortar's own hunt — including a bare, UNTRUSTED lead the shared joint
	# commitment above deliberately never covers (that one only ever forms
	# for a trusted lead, a real team-wide commitment; an untrusted lead is
	# a solo gamble by design — see _update_joint_mortar_hunt/_mortar_hunt_
	# fix_for's own doc comments) — so this is where that plays out for now.
	# Without it, the drone had no way to know the mortar had committed to
	# one at all: it could keep watching an entirely different known mortar
	# while the crew walked toward this one, exactly the "the drone should
	# have been supporting what the mortar was doing" report this answers.
	# Reads the mortar's OWN live, already-decided intent
	# (_mortar_move_intent, set the instant _decide_mortar_action's tier 2
	# commits to the move) rather than re-deriving a hunt fix independently,
	# so the drone can never end up disagreeing with what the mortar itself
	# actually chose. Should another kind of important, committed friendly
	# action ever get its own state to read this same way, it belongs here
	# too, not as a second copy of this tier.
	for fm in player_units:
		if fm.kind != Unit.Kind.MORTAR or fm.state != Unit.State.ACTIVE:
			continue
		if _mortar_move_intent.get(fm, "") != "hunt":
			continue
		var own_fix: Dictionary = _mortar_hunt_fix_for(fm)
		if own_fix.is_empty() or GameConfig.TARGET_PRIORITY_MORTAR <= best_score:
			continue
		# Direct user report from a live battle: "drone is now chasing fleeing
		# mortar. It should not do that when there are squads." A mortar that is
		# already RETREATING is a mop-up, not the threat this tier exists to back
		# up — the drone's own "a fleeing enemy mortar is a lower priority target
		# than enemy squads" ruling (see the retreating-contact tier below) has to
		# hold here too, or the friendly mortar's own chase of a fleeing gun drags
		# the drone off squads that are still fighting. With no squad left in the
		# fight the chase is all there is to support, as before.
		var hunted: Unit = own_fix.get("unit", null)
		if hunted != null and hunted.state != Unit.State.ACTIVE and _enemy_squads_still_in_the_fight():
			continue
		best_score = GameConfig.TARGET_PRIORITY_MORTAR
		best_pos = own_fix.position
		_drone_pilot_reasoning = {"tier": "Supporting important friendly action", "detail": "The friendly mortar has committed to closing on a known enemy mortar (own lead, not yet a team-wide commitment) — staying on the same target.", "target": best_pos}

	# Once the player has called a general retreat, everything still ACTIVE
	# gets ordered to pull back too (see order_general_retreat — unlike the
	# enemy's own mirror, this one does NOT exempt the mortar), so any
	# mortar-related priority above naturally has nothing left to say: the
	# gun is retreating, not hunting. Real reconnaissance doctrine for a
	# withdrawal is to screen the routes the main body is actually using,
	# not to keep working the fight that's just been called off — the
	# drone should be looking at ground our own people are about to cross,
	# not the position everyone's abandoning.
	var retreat_scout: Dictionary = _retreat_route_scout_target()
	if not retreat_scout.is_empty() and GameConfig.TARGET_PRIORITY_MORTAR > best_score:
		best_score = GameConfig.TARGET_PRIORITY_MORTAR
		best_pos = retreat_scout.position
		_drone_pilot_reasoning = {"tier": "Screening the retreat route", "detail": "General retreat ordered — scouting ahead of %s along its own withdrawal route for anything not yet spotted." % retreat_scout.unit.display_name(), "target": best_pos}

	var squad_pick: Dictionary = _drone_squad_to_track()
	var best_squad: Unit = squad_pick.get("unit", null)
	var best_squad_score: float = squad_pick.get("score", -1.0)
	if best_squad != null and best_squad_score > best_score:
		best_score = best_squad_score
		best_pos = best_squad.global_position
		_drone_pilot_reasoning = {"tier": "Tracking dangerous squad", "detail": "%s, danger score %.1f/%.1f." % [squad_pick.why, best_squad_score, GameConfig.TARGET_PRIORITY_SQUAD_MAX], "target": best_pos}

	# The commander's "expend ammo on enemy squads" order for the mortar
	# (set_mortar_squad_fire_order): the drone backs it up by watching the
	# squads the mortar could actually shell. Only present when an order is
	# in force, so without one this changes nothing. Beats the sweep and the
	# ordinary dangerous-squad tier, but stays below every mortar tier.
	var ordered_watch: Dictionary = _squad_fire_order_watch_target()
	if not ordered_watch.is_empty() and ordered_watch.score > best_score:
		best_score = ordered_watch.score
		best_pos = ordered_watch.position
		_drone_pilot_reasoning = {"tier": "Supporting the mortar's order to fire on squads", "detail": ordered_watch.detail, "target": best_pos}

	var best_retreating: Unit = null
	var best_retreating_dist := INF
	for u in enemy_units:
		if u.state == Unit.State.RETREATING and u.is_visible:
			var d: float = _nearest_active_friendly_distance(u.global_position)
			if d < best_retreating_dist:
				best_retreating_dist = d
				best_retreating = u
	if best_retreating != null:
		# High priority once the enemy force as a whole is running — its own
		# general retreat, or a lot of squads fleeing at the same time
		# (_enemy_force_is_fleeing) — but while the battle is still actually
		# going, one broken, defanged straggler (a mortar crew that's abandoned
		# its gun, or fled off the map as a last resort — see BattleManager.
		# _mortar_flee_as_last_resort — counts here too, not as "the mortar
		# priority") is a low-priority distraction next to whatever's still
		# actually fighting or still out there to be found.
		var force_fleeing: bool = _enemy_force_is_fleeing()
		var retreating_score: float = GameConfig.TARGET_PRIORITY_RETREATING_ENEMY if force_fleeing else GameConfig.TARGET_PRIORITY_RETREATING_ENEMY_LOW
		# Direct user correction: "a fleeing enemy mortar should be a lower
		# priority target than enemy squads... at least than squads that
		# are not fleeing." The comment above already stated that exact
		# intent, but the flat TARGET_PRIORITY_RETREATING_ENEMY_LOW
		# constant was still just compared against best_squad_score's
		# own continuous, distance-based scale (0 to TARGET_PRIORITY_SQUAD_
		# MAX) — a real, currently-visible, still-ACTIVE squad merely
		# distant from any friendly (score under 2) could still lose the
		# comparison to a fleeing straggler, backwards from the stated
		# principle. Capped so a real active squad — whatever its own
		# individual danger score happens to be right now — always wins
		# while the fight is still on: best_score already reflects
		# best_squad_score (or something higher) by this point whenever
		# best_squad is non-null, so capping to it can only ever prevent
		# this tier from winning, never help it.
		if not force_fleeing and best_squad != null:
			retreating_score = min(retreating_score, best_score)
		# Later, same principle for a fleeing SQUAD (user: "As with a fleeing
		# mortar, a fleeing enemy squad should be a low priority target for the
		# drone"; live case: nothing else was visible, and the drone sat on one
		# fleeing squad with 22% battery while two active squads it could not
		# see were still out there). A low-priority contact is now also only
		# worth a flight the battery can afford, and below routine search.
		if not force_fleeing and not _drone_can_afford_target(active_drone, best_retreating.global_position):
			retreating_score = -1.0
		if retreating_score > best_score:
			best_score = retreating_score
			best_pos = best_retreating.global_position
			_drone_pilot_reasoning = {"tier": "Finishing a retreating contact", "detail": "Nearest visible retreating enemy — %s." % ("the fight looks over, worth finishing" if force_fleeing else "battle still on, so this is a low-priority distraction that only wins when there is nothing else to do"), "target": best_pos}

	var flank_candidates: Array = _flank_watch_candidates()

	var routine_score: float = GameConfig.TARGET_PRIORITY_UNDISCOVERED_MORTAR_SWEEP * _drone_mortar_search_weight()
	if enemy_general_retreat_ordered:
		# The enemy commander has already called off the attack — the whole
		# reason to blindly sweep wide (a fresh SQUAD might be arriving) is
		# gone, and even the standing worry about an undiscovered mortar is
		# heavily discounted: if one really is still covering the withdrawal
		# (see _check_enemy_commander_retreat's "mortars continue the fire
		# mission"), it'll show up live or via a fresh lead and win via tier
		# (1)/(2) above regardless of this discount, unconditionally. What's
		# actually left to weigh the sweep against here is real, already-
		# broken kills in progress (tier 4) — those should win.
		routine_score *= GameConfig.SWEEP_DISCOUNT_DURING_ENEMY_RETREAT
	var sweep_only_score: float = routine_score
	if not flank_candidates.is_empty():
		# Watching the mortar's blind side is a standing duty, independent
		# of how confident anyone is that a second mortar exists — see this
		# function's own doc comment for why these two must NOT be blended
		# into one confidence-scaled number. Its strength does depend on
		# whether any known enemy squad is actually near enough to the
		# mortar to flank it — see _flank_watch_standing_priority.
		routine_score = max(routine_score, _flank_watch_standing_priority())
	if routine_score > best_score or is_inf(best_pos.x):
		var routine_pick: Dictionary = _drone_routine_recon_target(flank_candidates)
		# The standing flank-watch priority is earned only by an actual flank
		# check. When the pool's best pick is a far general-area sweep cell,
		# the tier is worth only the speculative sweep's own score — else a
		# known squad close to our mortar or forces (score up to 10) lost to
		# a long flight across the map, the live-reported "flying to a faraway
		# squad past close and dangerous ones".
		var pick_score: float = routine_score
		if not routine_pick.is_empty() and not routine_pick.key.begins_with("flank:"):
			pick_score = sweep_only_score
		# Direct user report, live: the drone "going back and forth" between actively tracking a squad and
		# routine recon with no visibility change involved at all — confirmed directly: _drone_mortar_
		# search_weight's own squad-danger discount (_known_squad_danger_pressure) shares the EXACT same
		# "how close to a friendly" ratio _squad_danger_priority itself uses, so as a tracked squad's own
		# danger score drifts down (moving away from a friendly), that very same movement pushes recon's
		# competing score UP (less danger left to discount it for) — a real, mathematically-coupled seesaw
		# around the crossover point between the two, with nothing to stop an ordinary few meters of drift
		# from flipping the choice back and forth. The same "small changes... should not cause the drone to
		# oscillate" principle already established for mortar-target selection, applied here via the same
		# margin _drone_commitment_has_collapsed already uses for its own cross-candidate handoffs — scoped
		# to this one coupled pair; acquiring a newly-dangerous squad to track in the first place is a
		# genuinely valuable event and stays immediate, unchanged.
		var required_score: float = best_score
		if _drone_pilot_reasoning.get("tier", "") == "Tracking dangerous squad":
			required_score = best_score / GameConfig.DRONE_COMMITMENT_ABANDON_FRACTION
		if not routine_pick.is_empty() and (pick_score > required_score or is_inf(best_pos.x)):
			best_pos = routine_pick.point
			var kind: String = "an unwatched gap toward our mortar's flank" if routine_pick.key.begins_with("flank:") else "a general-area sweep cell"
			_drone_pilot_reasoning = {"tier": "Routine background recon", "detail": "No urgent lead — checking %s (candidate value %.2f, mortar-existence confidence %.2f)." % [kind, routine_pick.value, _mortar_existence_confidence()], "target": best_pos}
			if routine_pick.key.begins_with("force:"):
				_drone_pilot_reasoning = {"tier": "Watching the enemy force", "detail": "%d enemy squad%s in sight here: tracking them rather than searching elsewhere." % [routine_pick.count, "" if routine_pick.count == 1 else "s"], "target": best_pos}
			if routine_pick.key.begins_with("look:"):
				_drone_pilot_reasoning = {"tier": "Looking around an empty mortar lead", "detail": "The spot of the last mortar fix was watched and is empty: checking the ground around it, where the crew can have moved to.", "target": best_pos}
			if routine_pick.key.begins_with("lost:"):
				_drone_pilot_reasoning = {"tier": "Regaining contact with a lost squad", "detail": "%s was last seen %.0f s ago near here and has not been found since: going to look." % [routine_pick.unit.display_name(), routine_pick.age], "target": best_pos}

	# Routine recon had places to go but the battery can't afford any of them
	# (each too far, or too far upwind, to reach AND get home from), and
	# nothing more urgent claimed the drone: nothing reachable is worth flying to.
	if is_inf(best_pos.x) and _drone_routine_pool_unaffordable:
		_drone_search_exhausted = true
		_drone_pilot_reasoning = {"tier": "Nothing reachable", "detail": "Every routine target is too far — or too far upwind — for the battery to reach and still get home from. Heading home.", "target": active_drone.global_position}
		return active_drone.global_position

	# A last, universal guard: every tier above is supposed to only ever
	# offer a real, in-area position (an actual enemy unit's position, a
	# probe already clamped by _flank_watch_candidates, a sweep waypoint
	# that's always been well inside the map), but a live enemy unit is the
	# one case not otherwise clamped here — nothing currently drives one
	# north/south off the map, but should that ever change, this is what
	# keeps the drone from following it into ground that belongs to another
	# unit's sector entirely, regardless of the reason.
	return _clamp_to_drone_operating_area(best_pos)


## Whether the drone team may spend attention on an enemy mortar last known
## at `pos`. Always true unless a friendly mortar holds the "expend ammo on
## enemy squads" order (set_mortar_squad_fire_order): the commander has then
## said the mortar's job is squads, so a mortar it can't reach is not worth
## the drone's time - unless it seems likely to come into range soon. That
## means either within reach already, or within reach after the crew walks for
## GameConfig.DRONE_SQUAD_FIRE_ORDER_MORTAR_SOON_S at its relocation pace, or
## the crew has already committed to closing on it (intent "hunt" - it IS on
## its way into range).
func _squad_order_permits_mortar_watch(pos: Vector2) -> bool:
	if _mortar_squad_fire_orders.is_empty():
		return true
	for m in _mortar_squad_fire_orders:
		if m.state != Unit.State.ACTIVE:
			continue
		if _mortar_move_intent.get(m, "") == "hunt":
			return true
		var soon_reach: float = GameConfig.mortar_max_range(m.team) + GameConfig.MORTAR_RELOCATE_SPEED * GameConfig.DRONE_SQUAD_FIRE_ORDER_MORTAR_SOON_S
		if m.global_position.distance_to(pos) <= soon_reach:
			return true
	return false


## Whether the enemy FORCE is running, as opposed to one straggler: its own general
## retreat, or a lot of squads fleeing at the same time — at least
## GameConfig.DRONE_MASS_FLIGHT_MIN_SQUADS of them, and at least
## GameConfig.DRONE_MASS_FLIGHT_FRACTION of the squads the drone team knows to be on
## the field (fleeing or active). Judged from the player's own knowledge (each
## squad's last SEEN state, Unit.player_known_state), not the omniscient one: the
## drone cannot tell that squads it has not seen are fleeing.
func _enemy_force_is_fleeing() -> bool:
	if enemy_general_retreat_ordered:
		return true
	var fleeing := 0
	var on_field := 0
	for u in enemy_units:
		if u.kind != Unit.Kind.SQUAD or not u.player_has_been_sighted:
			continue
		if u.player_known_state == Unit.State.RETREATING:
			fleeing += 1
			on_field += 1
		elif u.player_known_state == Unit.State.ACTIVE:
			on_field += 1
	return fleeing >= GameConfig.DRONE_MASS_FLIGHT_MIN_SQUADS and float(fleeing) >= GameConfig.DRONE_MASS_FLIGHT_FRACTION * float(on_field)


## Whether any enemy squad is still in the fight as far as the drone team
## knows: ACTIVE, and either in view now or seen within
## GameConfig.DRONE_CONTACT_BONUS_EXPIRY (the same "still worth acting on"
## horizon _update_recent_enemy_contacts already uses). A retreating, withdrawn,
## destroyed or never-seen squad does not count.
func _enemy_squads_still_in_the_fight() -> bool:
	for u in enemy_units:
		if u.kind != Unit.Kind.SQUAD:
			continue
		# Currently visible is its own, unconditional fast path — real, current truth, no different from
		# every other live-sighting check in this file.
		if u.is_visible:
			if u.state == Unit.State.ACTIVE:
				return true
			continue
		# Knowledge audit (2026-09-27): this used to fall through to u.state (ground truth) despite the
		# doc comment above already promising "as far as the drone team knows" — a squad the player last
		# actually observed active and in contact (_recent_enemy_contacts, itself only ever recorded while
		# genuinely state == ACTIVE and is_visible — see _update_recent_enemy_contacts — never omniscient)
		# must still count even if it has since been destroyed or withdrawn unseen.
		var info: Dictionary = _recent_enemy_contacts.get(u, {})
		if not info.is_empty() and scenario_elapsed_time - info.time <= GameConfig.DRONE_CONTACT_BONUS_EXPIRY:
			return true
	return false


## The drone's contribution to a "fire on squads" mortar order: the best
## enemy squad to watch so the ordered mortar has targets. {} when no
## friendly mortar holds the order (the default) or no squad qualifies.
## Considers only squads inside the ordered mortar's range - watching one it
## cannot reach helps nobody. A squad visible right now scores at least
## DRONE_SQUAD_FIRE_ORDER_WATCH_PRIORITY (more if its own danger score is
## higher, though that scale tops out far below); one not visible now but
## seen within DRONE_CONTACT_BONUS_EXPIRY scores that times
## DRONE_SQUAD_FIRE_ORDER_UNSEEN_FACTOR, so the drone goes back to look
## for it when nothing is in view but never prefers it to a live one.
## Kept below TARGET_PRIORITY_MORTAR: hunting mortars still comes first,
## as it does for the mortar itself.
func _squad_fire_order_watch_target() -> Dictionary:
	var best: Dictionary = {}
	for m in _mortar_squad_fire_orders:
		if m.state != Unit.State.ACTIVE:
			continue
		var reach: float = GameConfig.mortar_max_range(m.team)
		for u in enemy_units:
			if u.kind != Unit.Kind.SQUAD:
				continue
			var score := -1.0
			var pos := Vector2.INF
			var detail := ""
			if u.is_visible:
				# Currently visible is its own, unconditional fast path — see _enemy_squads_still_in_the_
				# fight's own comment on why this can't wait on player_has_been_sighted/player_known_state.
				if u.state != Unit.State.ACTIVE:
					continue
				if m.global_position.distance_to(u.global_position) > reach:
					continue
				score = max(_squad_danger_priority(u), GameConfig.DRONE_SQUAD_FIRE_ORDER_WATCH_PRIORITY)
				pos = u.global_position
				detail = "%s is ordered to expend ammunition on enemy squads - watching %s, inside its range." % [m.display_name(), u.display_name()]
			else:
				# Knowledge audit (2026-09-27): the same gap _enemy_squads_still_in_the_fight had — see its
				# own comment on why _recent_enemy_contacts alone (never omniscient) is enough here.
				var info: Dictionary = _recent_enemy_contacts.get(u, {})
				if info.is_empty() or scenario_elapsed_time - info.time > GameConfig.DRONE_CONTACT_BONUS_EXPIRY:
					continue
				if m.global_position.distance_to(info.position) > reach:
					continue
				score = GameConfig.DRONE_SQUAD_FIRE_ORDER_WATCH_PRIORITY * GameConfig.DRONE_SQUAD_FIRE_ORDER_UNSEEN_FACTOR
				pos = info.position
				detail = "%s is ordered to expend ammunition on enemy squads - going back to look for %s, last seen inside its range." % [m.display_name(), u.display_name()]
			if best.is_empty() or score > best.score:
				best = {"score": score, "position": pos, "detail": detail}
	return best


## The retreating (or still-catching-up-to-its-own-retreat-order) player
## unit with the LONGEST remaining walk to its own current destination —
## the one most exposed for the longest, and so the most worth clearing a
## path for. Excludes RESUPPLY_RUN (not a combat unit anyone's escorting)
## and DRONE (already airborne, not walking a ground route at all).
## Vector2.INF/no unit if no general retreat is in progress, or every
## remaining unit has either arrived already or never got a move order at
## all (nothing left to screen).
##
## The scouted point is partway along that unit's OWN remaining route
## (DRONE_RETREAT_SCOUT_LOOKAHEAD_FRACTION of the way to its move_target),
## not the unit's current position — its own visibility already covers
## where it's standing right now as it walks through; the point of sending
## the drone ahead is to get eyes on the ground it hasn't reached yet
## before it gets there, the way a real reconnaissance element screening a
## withdrawal covers the routes the main body is using rather than
## trailing behind it.
func _retreat_route_scout_target() -> Dictionary:
	if not player_general_retreat_ordered:
		return {}
	var best_unit: Unit = null
	var best_remaining := -1.0
	for u in player_units:
		if u.kind == Unit.Kind.RESUPPLY_RUN or u.kind == Unit.Kind.DRONE:
			continue
		if u.state != Unit.State.RETREATING and u.state != Unit.State.ACTIVE:
			continue
		if not u.has_move_target:
			continue
		var remaining: float = u.global_position.distance_to(u.move_target)
		if remaining > best_remaining:
			best_remaining = remaining
			best_unit = u
	if best_unit == null:
		return {}
	var lookahead: Vector2 = best_unit.global_position.lerp(best_unit.move_target, GameConfig.DRONE_RETREAT_SCOUT_LOOKAHEAD_FRACTION)
	return {"position": lookahead, "unit": best_unit}


## `point` as a plain, JSON-safe {"x","y"} dict in whole meters — used only
## by drone_pilot_debug_snapshot, which must not return raw Vector2 values
## (BattleScreen's JSON export of it would otherwise need its own conversion
## pass; keeping the snapshot itself JSON-native avoids that entirely).
func _pos_to_debug_dict(point: Vector2) -> Dictionary:
	return {"x": roundi(point.x / GameConfig.PIXELS_PER_METER), "y": roundi(point.y / GameConfig.PIXELS_PER_METER)}


## A smooth, continuous stand-in for the row bias _sweep_candidates only
## ever evaluates at its own 25 fixed grid waypoints — linearly
## interpolated between GameConfig.DRONE_SEARCH_GRID_ROWS_M's row centers
## (clamped at the map's own north/south edges past the first/last row),
## summing the same squad- and mortar-hunting weights _sweep_candidates
## itself adds together. Used by estimated_enemy_likelihood below to paint
## a full-map gradient for the enemy heat-map overlay (BattleScreen's "e" key)
## rather than 25 isolated dots — never used by any actual sweep decision,
## which still runs on the real discrete grid.
func _row_bias_at_y(y: float) -> float:
	var rows_m: Array[float] = GameConfig.drone_search_rows_m()
	var weights: Array[float] = []
	for i in rows_m.size():
		weights.append(GameConfig.DRONE_SWEEP_ROW_WEIGHTS[i] + GameConfig.DRONE_MORTAR_HUNT_ROW_WEIGHTS[i])
	var y_m: float = y / GameConfig.PIXELS_PER_METER
	if y_m <= rows_m[0]:
		return weights[0]
	var last: int = rows_m.size() - 1
	if y_m >= rows_m[last]:
		return weights[last]
	for i in last:
		if y_m >= rows_m[i] and y_m <= rows_m[i + 1]:
			var t: float = (y_m - rows_m[i]) / (rows_m[i + 1] - rows_m[i])
			return lerp(weights[i], weights[i + 1], t)
	return weights[0] # unreachable given the two clamps above


## The commander's combined, continuous estimate of how likely the enemy
## is to matter near `point` right now — the same ingredients
## _sweep_candidates itself scores a cell with (off-road/road row bias,
## east-approach likelihood, real recent-contact evidence), just evaluated
## smoothly across the whole map instead of only at the 25 fixed sweep
## waypoints. Read-only, for the enemy heat-map overlay (BattleScreen's "e"
## key, independent of the drone-pilot debug overlay's "d" key) — never
## drives any actual decision itself, the same way drone_pilot_debug_
## snapshot doesn't.
##
## Three cases, matching three different kinds of knowledge:
## 1. A real, live contact right here (_contact_search_bonus > 0) wins
##    outright, even over "currently observed" — that observation is
##    exactly HOW we know about it, so this reads as maximally hot rather
##    than being zeroed out as "confirmed empty."
## 2. Genuinely confirmed empty (currently observed, nothing there) drops
##    straight to zero — we know the enemy isn't here — but the ground is
##    also stamped as recently cleared (_heatmap_last_cleared), so once
##    whatever was watching it moves on, the doctrinal guess doesn't
##    instantly snap back to full value: a real enemy squad moves far
##    slower than the drone does, so it's unlikely (not impossible) to
##    already be back the moment we stop looking. _heatmap_recently_
##    cleared_multiplier ramps that discount back to 1.0 over however
##    long a real infiltrator would actually need to walk there from the
##    nearest enemy position we know about.
## 3. Otherwise, the ordinary doctrinal guess (row/approach bias, itself
##    discounted if this ground was recently cleared) plus whatever
##    _contact_search_bonus still lingers from a sighting that's since
##    fallen out of view — which is what keeps a recently-lost contact's
##    own area "hot" for a while rather than going cold the instant it's
##    no longer directly observed.
func estimated_enemy_likelihood(point: Vector2) -> float:
	var contact_bonus: float = _contact_search_bonus(point)
	var key := Vector2(roundi(point.x), roundi(point.y))

	if _point_currently_observed(point):
		if contact_bonus > 0.0:
			return contact_bonus
		_heatmap_last_cleared[key] = scenario_elapsed_time
		return 0.0

	var baseline: float = _row_bias_at_y(point.y) * _enemy_approach_likelihood(point)
	baseline *= _heatmap_recently_cleared_multiplier(key)
	return baseline + contact_bonus


## Down to HEATMAP_RECENTLY_CLEARED_MIN_MULTIPLIER (not zero: "unlikely,
## not impossible") the instant `key` is confirmed clear, ramping back up
## linearly as that confirmation goes stale. Same decaying-discount shape
## as _drone_destination_recency_multiplier, but a genuinely separate
## concept and constant: that one is about search EFFICIENCY (don't
## immediately re-check the same spot), this one is about physical
## PLAUSIBILITY (an enemy squad moves far slower than the drone, so it
## can't have already walked back into ground just cleared).
##
## The cooldown itself is DISTANCE-scaled, not a flat window: how long
## full suspicion takes to rebuild is however long it would take someone
## on foot, at GameConfig.HEATMAP_INFILTRATION_SPEED, to walk here from
## the nearest enemy position we actually know about right now
## (_known_enemy_positions — the same fog-of-war-respecting set every
## other "what do we actually know" computation in this file uses). A
## flat few minutes was fine for one grid cell's own width, but wrong
## once a WIDE area gets cleared at once: a point a kilometer from
## anything ever seen doesn't deserve the same few-minute clock as one
## right next to a known contact. No known enemy anywhere at all means an
## effectively infinite cooldown — nothing to infiltrate FROM yet — so
## this stays at the MIN multiplier until real contact is made somewhere.
##
## A point with no record of ever being confirmed clear is treated as if
## it HAD been cleared at scenario time zero, not as an automatic 1.0 —
## the enemy doesn't teleport, so the doctrinal positional guess
## (_row_bias_at_y/_enemy_approach_likelihood) shouldn't read as fully
## trusted from the very first tick of the battle either, before anyone
## on either side has had any real time to move anywhere at all.
func _heatmap_recently_cleared_multiplier(key: Vector2) -> float:
	var last_cleared: float = _heatmap_last_cleared.get(key, 0.0)
	var elapsed: float = scenario_elapsed_time - last_cleared

	var nearest_threat_dist := INF
	for p in _known_enemy_positions(Unit.Team.PLAYER):
		nearest_threat_dist = min(nearest_threat_dist, key.distance_to(p))
	var cooldown: float = nearest_threat_dist / GameConfig.HEATMAP_INFILTRATION_SPEED

	if elapsed >= cooldown:
		return 1.0
	var t: float = elapsed / cooldown
	return lerp(GameConfig.HEATMAP_RECENTLY_CLEARED_MIN_MULTIPLIER, 1.0, t)


## Whether the active drone's own camera covers `point` right now — within
## its (weather- and altitude-scaled) detection range with a clear aerial line.
func _drone_currently_sees(point: Vector2) -> bool:
	if active_drone == null or active_drone.state != Unit.State.ACTIVE:
		return false
	return active_drone.global_position.distance_to(point) <= _drone_detection_range() and GameConfig.has_aerial_los(active_drone.global_position, point)


## Whether any currently-ACTIVE friendly asset — a ground unit's ordinary
## detection range and line of sight, or the airborne drone's own wider
## aerial sensor — could plausibly see `point` right now. Used only to
## suppress the heat-map's own "possible enemy location" guess over
## ground we're actually watching; a real commander doesn't keep worrying
## about a stretch of ground their own people can currently see is empty.
## Deliberately uses each observer's ORDINARY detection range (not the
## shorter range CombatResolver.effective_detection_range would apply
## against a target hidden in cover) — this is "would we likely have
## noticed an enemy here by now," a debug approximation, not a claim that
## every conceivable hiding spot within some radius is provably clear.
func _point_currently_observed(point: Vector2, count_drone_camera: bool = true) -> bool:
	if count_drone_camera and _drone_currently_sees(point):
		return true
	for u in player_units:
		if u.state != Unit.State.ACTIVE:
			continue
		if u.kind != Unit.Kind.SQUAD and u.kind != Unit.Kind.MORTAR and u.kind != Unit.Kind.SPOTTER:
			continue
		var range: float = GameConfig.DETECTION_BASE_RANGE
		if u.kind == Unit.Kind.SPOTTER:
			range += GameConfig.SPOTTER_DETECTION_RANGE_BONUS
		if u.elevation() > GameConfig.elevation_m(point) + GameConfig.ELEVATION_ADVANTAGE_THRESHOLD_M:
			range += GameConfig.DETECTION_ELEVATION_BONUS
		if u.global_position.distance_to(point) <= range and GameConfig.has_direct_los(u.global_position, point):
			return true
	return false


## Whether the drone has already flown to this mortar lead (a muzzle-flash fix or a last-seen position) and watched the spot for
## DRONE_LEAD_EMPTY_DWELL_S with the mortar not in view: then the lead is spent, and the drone goes back to searching (the ground
## around a fresh contact still draws it, see _contact_search_bonus) instead of hovering over an empty spot until the lead expires.
## Direct user report, live: "the drone is hovering over a spot the enemy mortar fired from. But no enemy mortar is visible on
## screen." The crew had fired and moved off 290 m into a wood, where a mortar in cover is only noticed inside 250 m. A NEWER fix or
## sighting of the same mortar is a new lead and counts again. Uses only what the player's side has (the lead, and whether the mortar is
## in view right now).
func _drone_lead_is_spent(mortar: Unit, lead_pos: Vector2, lead_time: float) -> bool:
	if _drone_checked_leads.get(mortar, -INF) >= lead_time:
		return true
	if active_drone == null or active_drone.state != Unit.State.ACTIVE or mortar.is_visible 			or active_drone.global_position.distance_to(lead_pos) > DRONE_SWEEP_WAYPOINT_RADIUS:
		_drone_lead_arrival.erase(mortar)
		return false
	var arrival: Dictionary = _drone_lead_arrival.get(mortar, {})
	if arrival.is_empty() or arrival.lead != lead_time:
		arrival = {"lead": lead_time, "since": scenario_elapsed_time}
		_drone_lead_arrival[mortar] = arrival
	if scenario_elapsed_time - arrival.since >= DRONE_LEAD_EMPTY_DWELL_S:
		_drone_checked_leads[mortar] = lead_time
		_drone_lead_searches[mortar] = {"center": lead_pos, "lead": lead_time, "created": scenario_elapsed_time}
		return true
	return false


## The places around a spent mortar lead the drone still means to look, as candidates in the routine-recon pool (with the sweep cells, flank
## gaps and lost squads): four points of a diamond LEAD_SEARCH_RADIUS out. A point stops being offered once the drone has been to it; the
## whole search lapses after LEAD_SEARCH_LIFETIME_S, or the moment a newer fix or sighting of that mortar gives a new lead.
func _lead_search_candidates() -> Array:
	var out: Array = []
	for mortar in _drone_lead_searches.keys():
		var search: Dictionary = _drone_lead_searches[mortar]
		var newest: float = _last_detected_mortar_fire.get(mortar, {}).get("time", -INF)
		if is_instance_valid(mortar) and mortar.player_has_been_sighted:
			newest = maxf(newest, mortar.player_known_position_time)
		if scenario_elapsed_time - search.created > LEAD_SEARCH_LIFETIME_S or newest > search.lead:
			_drone_lead_searches.erase(mortar)
			continue
		var directions: Array[Vector2] = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]
		for k in directions.size():
			var key := "look:%d:%d" % [mortar.get_instance_id(), k]
			if _drone_destination_last_visited.get(key, -INF) >= search.created:
				continue
			out.append({"key": key, "point": _clamp_to_drone_operating_area(search.center + directions[k] * LEAD_SEARCH_RADIUS), "value": LEAD_SEARCH_VALUE})
	return out


## Read-only introspection into the drone's current reasoning — "what is
## the drone pilot thinking right now, and why" — for the player-
## toggleable debug overlay (see BattleScreen's DronePilotDebugPanel) and, while
## the battle is paused, for external inspection of exactly what the
## decision logic sees at that frozen moment (BattleScreen also exports this to
## a JSON file whenever the overlay is on, specifically so it can be
## inspected from outside the running game). Purely descriptive — nothing
## here may ever feed back into an actual decision. {"active": false} if no
## drone is currently airborne to report on (SPOTTER recon mode, or a
## DRONE_TEAM battle between sorties).
func drone_pilot_debug_snapshot() -> Dictionary:
	if active_drone == null:
		# Direct live user question, diagnosing a "repeatedly launching with very little charge" report:
		# nothing here previously exposed battery-pool state while grounded (only ever returned
		# {"active": false}) — drone_fleet_status() already has it (ready/spare counts and each pool's own
		# best charge), just not reachable without a drone actually airborne.
		return {"active": false, "fleet": drone_fleet_status()}

	var contacts: Array = []
	for u in _recent_enemy_contacts:
		var info: Dictionary = _recent_enemy_contacts[u]
		var entry: Dictionary = _pos_to_debug_dict(info.position)
		entry["age_s"] = roundi(scenario_elapsed_time - info.time)
		contacts.append(entry)
	contacts.sort_custom(func(a, b): return a.age_s < b.age_s)

	# The same candidate pool _drone_routine_recon_target itself competes
	# over — sorted purely for this readout, not re-used for any decision.
	var candidates: Array = _sweep_candidates() + _flank_watch_candidates()
	candidates.sort_custom(func(a, b): return a.value > b.value)
	var top_candidates: Array = []
	for i in min(5, candidates.size()):
		var c: Dictionary = _pos_to_debug_dict(candidates[i].point)
		c["key"] = candidates[i].key
		c["value"] = snappedf(candidates[i].value, 0.01)
		top_candidates.append(c)

	var reasoning: Dictionary = _drone_pilot_reasoning.duplicate()
	if reasoning.has("target"):
		reasoning["target"] = _pos_to_debug_dict(reasoning["target"])

	return {
		"active": true,
		"drone_position": _pos_to_debug_dict(active_drone.global_position),
		"drone_battery_charge": snappedf(active_drone.drone_battery_charge, 0.01),
		"drone_airspeed_mps": snappedf(active_drone.move_speed / GameConfig.PIXELS_PER_METER, 0.1),
		"mortar_existence_confidence": snappedf(_mortar_existence_confidence(), 0.01),
		"current_reasoning": reasoning,
		"recent_enemy_contacts": contacts,
		"top_search_candidates": top_candidates,
	}


## The rectangle a drone's own destination must stay within — see
## GameConfig.clamp_to_operating_area's own doc comment for the shared
## reasoning (the same bound every other projected-candidate search in
## the game now uses, e.g. GameConfig.nearest_hidden_point's ring search).
func _clamp_to_drone_operating_area(point: Vector2) -> Vector2:
	return GameConfig.clamp_to_operating_area(point)


## Where the drone checks for an enemy flanking around toward the mortar's
## blind side — the drone's own contribution to spotting the kind of
## approach _update_friendly_squad_positioning exists to answer, ideally
## before it's close enough to force that response at all. Vector2.INF (no
## flank worth watching right now) if the mortar isn't ACTIVE, or if every
## compass bearing around it is already either screened by an ACTIVE
## friendly squad (_lane_is_screened — that lane already has real coverage)
## or sitting on/near an already-known enemy position (already covered by a
## higher-priority tier above — no point in redundantly re-watching it).
## Feeds into the shared routine-recon pool (_drone_routine_recon_target)
## alongside _sweep_candidates — see that function's own doc comment for
## why the two were merged, and for _contact_search_bonus, applied here
## too: a squad recently seen moving toward one of these bearings is
## exactly the "sneaking up on the mortar" case this check exists for.
## Base value is also discounted by _flank_watch_plausibility — see that
## function's own doc comment for why this is a TIME gate (implausible this
## early, regardless of direction) rather than the same permanent
## directional bias _sweep_candidates uses.
func _flank_watch_candidates() -> Array:
	var mortar := _friendly_active_mortar()
	if mortar == null:
		return []

	var screening_squads: Array[Unit] = []
	for u in player_units:
		if u.kind == Unit.Kind.SQUAD and u.state == Unit.State.ACTIVE:
			screening_squads.append(u)
	var known_enemies := _known_enemy_positions(Unit.Team.PLAYER)

	var out: Array = []
	for bearing_deg in GameConfig.DRONE_FLANK_WATCH_BEARINGS_DEG:
		# The true bearing direction, unclamped — screening/already-known
		# both reason about real compass geometry around the mortar, not
		# about where the drone can physically go.
		var probe: Vector2 = mortar.global_position + Vector2.RIGHT.rotated(deg_to_rad(bearing_deg)) * GameConfig.MORTAR_FLANK_THREAT_RADIUS
		if _lane_is_screened(probe, mortar.global_position, screening_squads):
			continue
		var already_known := false
		for e in known_enemies:
			if e.distance_to(probe) <= GameConfig.DRONE_FLANK_WATCH_ARRIVE_RADIUS:
				already_known = true
				break
		if already_known:
			continue
		# But MORTAR_FLANK_THREAT_RADIUS (1500m) is large enough relative to
		# the map's own height that a mortar anywhere near the north or
		# south edge sends a straight-line bearing probe off the map
		# entirely — another unit's sector this recon asset has no business
		# in, unlike the west flank, which is real, modeled ground. Fly to
		# the boundary instead of off it; the bearing itself, and whether
		# it's worth checking at all, is still judged on the true direction.
		var flight_point: Vector2 = _clamp_to_drone_operating_area(probe)
		var value: float = GameConfig.DRONE_FLANK_WATCH_BASE_VALUE * _flank_watch_plausibility(probe) + _contact_search_bonus(probe)
		out.append({"key": "flank:%d" % int(bearing_deg), "point": flight_point, "value": value})
	return out


## How strongly the flank-watch standing duty competes with squad tracking
## right now — GameConfig.DRONE_FLANK_WATCH_STANDING_PRIORITY when a known
## enemy squad is close enough to the friendly mortar to plausibly flank it
## (within GameConfig.DRONE_FLANK_WATCH_FADE_START), fading linearly down
## to GameConfig.DRONE_FLANK_WATCH_FLOOR_PRIORITY once the nearest one is
## GameConfig.DRONE_FLANK_WATCH_FADE_END or farther. Direct user report,
## from a live battle: "the drone is too far afield... it seems to do very
## little squad watching" — with the mortar parked at the map edge and every
## known enemy squad 2km+ away, the flat 30.0 standing priority (above any
## squad's tracking ceiling of TARGET_PRIORITY_SQUAD_MAX) kept sending the
## drone out to probe the mortar's empty flanks while the actual fight was
## elsewhere. "Known" means sighted at some point (its last-known position
## counts, same as everything else the player's side reasons from); with no
## known enemy squad at all the full priority stays, since nothing else is
## competing for the drone's attention anyway and unknown enemies are
## exactly what the watch exists to find.
func _flank_watch_standing_priority() -> float:
	var mortar := _friendly_active_mortar()
	if mortar == null:
		return GameConfig.DRONE_FLANK_WATCH_STANDING_PRIORITY
	var nearest := INF
	for u in enemy_units:
		# Knowledge audit (2026-09-27): u.state was ground truth alongside player_has_been_sighted — a
		# squad last known ACTIVE must keep counting as a reason to watch the flank even if it has since
		# been destroyed or withdrawn unseen.
		if u.kind == Unit.Kind.SQUAD and u.player_has_been_sighted and u.player_known_state == Unit.State.ACTIVE:
			nearest = min(nearest, mortar.global_position.distance_to(u.player_known_position))
	if is_inf(nearest):
		return GameConfig.DRONE_FLANK_WATCH_STANDING_PRIORITY
	var t: float = clamp((nearest - GameConfig.DRONE_FLANK_WATCH_FADE_START) / (GameConfig.DRONE_FLANK_WATCH_FADE_END - GameConfig.DRONE_FLANK_WATCH_FADE_START), 0.0, 1.0)
	return lerp(GameConfig.DRONE_FLANK_WATCH_STANDING_PRIORITY, GameConfig.DRONE_FLANK_WATCH_FLOOR_PRIORITY, t)


## The single currently-visible, still-ACTIVE, in-range enemy mortar worth
## the backup-drone/self-sacrifice decisions actually acting on — used by
## _update_active_drone/_update_backup_drone/the backup-launch trigger in
## _update_drone_operations, all of which are asking "is there one right
## now we can actually DO something about," not just "is there one worth
## watching" (see _priority_visible_enemy_mortar for that, weaker
## question — _drone_search_target's own top tier). A RETREATING mortar
## has already had its crew abandon the gun for good (Unit.
## _apply_crew_casualties — it will never fire again no matter how well
## it's watched), and one outside the friendly mortar's own real range
## (GameConfig.mortar_max_range) can't be engaged right now regardless of
## visibility — sacrificing a drone, or spending a
## backup's own limited flight time, over either just wastes an asset that
## could instead find (or wait for) a mortar actually worth acting on.
func _visible_engageable_mortar() -> Unit:
	for u in enemy_units:
		if u.kind == Unit.Kind.MORTAR and u.state == Unit.State.ACTIVE and u.is_visible and _in_friendly_mortar_range(u.global_position):
			return u
	return null


## Whether some ACTIVE friendly mortar's own hunt-fix (_mortar_hunt_fix_
## for — the exact same resolver _pick_target's pursuit-preference and
## _decide_mortar_action's tier 2 movement both already use) currently
## points at `target` specifically — i.e., is this THE enemy mortar the
## friendly force is actually oriented toward, not just any enemy mortar
## that happens to be visible. Checks every active friendly mortar, not
## just one, so with more than one fielded on our own side, a lead either
## of them is individually pursuing still counts.
func _is_priority_hunt_target(target: Unit) -> bool:
	for m in player_units:
		if m.kind != Unit.Kind.MORTAR or m.state != Unit.State.ACTIVE:
			continue
		var fix: Dictionary = _mortar_hunt_fix_for(m)
		if fix.get("unit", null) == target:
			return true
	return false


## Any currently visible, still-ACTIVE enemy mortar at all — unlike
## _visible_engageable_mortar, NOT gated on whether it's currently in
## range of friendly fire, since simply maintaining contact on a
## confirmed, live mortar has real value on its own even before it's
## reachable (an early-warning asset that wandered off the moment
## engaging it wasn't IMMEDIATELY feasible was a real, previously-fixed
## bug — the range-gate in _visible_engageable_mortar only ever belonged
## to the backup/self-sacrifice decisions, which really do need "can we
## act on this right now," not to this much more basic "should we keep
## watching it").
##
## What IS gated here: when more than one is visible at once, one that
## matches _is_priority_hunt_target — a mortar the friendly force is
## actually oriented toward engaging, soon or already — is preferred
## outright over one nobody has any near-term plan for, and the returned
## `priority` flag tells _drone_search_target's own top tier which value
## to score it at (GameConfig.TARGET_PRIORITY_MORTAR vs the much lower
## DRONE_NON_PRIORITY_MORTAR_WATCH_VALUE). A visible mortar with no
## current plan still falls back to being returned (never {} while ANY
## are visible) — general awareness still beats losing contact outright,
## it just no longer unconditionally outranks a real squad threat.
func _priority_visible_enemy_mortar() -> Dictionary:
	# Collected rather than returned on sight, same reasoning as
	# _known_enemy_mortar_lead's own fix — "whichever comes first in
	# enemy_units" is spawn order, not distance, and was the actual bug
	# behind the drone tracking the farther of two known mortars.
	var fallback_candidates: Array[Unit] = []
	for u in enemy_units:
		if u.kind != Unit.Kind.MORTAR or u.state != Unit.State.ACTIVE or not u.is_visible:
			continue
		if not _squad_order_permits_mortar_watch(u.global_position):
			continue # squad-fire order in force and this mortar is out of reach, and not coming into it
		if _is_priority_hunt_target(u):
			return {"unit": u, "priority": true}
		fallback_candidates.append(u)
	if fallback_candidates.is_empty():
		return {}
	var chosen: Unit = _closest_enemy_mortar(fallback_candidates, _drone_fallback_mortar_watch_unit)
	_drone_fallback_mortar_watch_unit = chosen
	return {"unit": chosen, "priority": false}


## THE single point of truth for "can any friendly asset actually strike
## `pos` right now" — currently just the friendly mortar's own range, but
## deliberately factored out as the one place to extend if other ways to
## hit an enemy mortar are ever added (a squad's direct fire, artillery,
## whatever) — the self-sacrifice decision in _update_active_drone is
## supposed to key off "can we act on this," not "does a friendly mortar
## happen to exist," so it must not go stale the day a second way to fire
## shows up. Unlike _in_friendly_mortar_range (which this powers), this
## does NOT treat "no active friendly mortar at all" as "sure, don't
## exclude it" — a real engagement decision needs the strict, honest
## answer: with nothing able to fire, the answer is simply no.
func _can_engage_position(pos: Vector2) -> bool:
	for m in player_units:
		if m.kind == Unit.Kind.MORTAR and m.state == Unit.State.ACTIVE:
			return m.global_position.distance_to(pos) <= GameConfig.mortar_max_range(m.team)
	return false


## Whether `pos` is within the friendly mortar's actual reach right now —
## used to keep the drone from wasting search time parking on an enemy
## mortar (or its last-known firing spot) that the friendly mortar
## physically cannot act on, even though it's otherwise the highest-priority
## kind of target. More LENIENT than _can_engage_position on purpose: with
## no ACTIVE friendly mortar at all there's no reference point to judge
## range from, so mere TRACKING isn't excluded in that case — general
## awareness of where enemy mortars are still has some value even with
## nothing (yet) able to act on it, unlike the strict engageability
## question _can_engage_position answers for deciding whether a drone
## should actually sacrifice itself over one.
func _in_friendly_mortar_range(pos: Vector2) -> bool:
	for m in player_units:
		if m.kind == Unit.Kind.MORTAR and m.state == Unit.State.ACTIVE:
			return _can_engage_position(pos)
	return true


## No mortar lead at all yet: search the whole contested area
## (GameConfig.DRONE_SEARCH_GRID_COLUMNS_M/ROWS_M — the map's full height,
## not just the road's own narrow band a mortar would never actually sit
## on), but not uniformly — see _sweep_candidates, which
## focuses this on the rows closest to the road (the enemy's own, openly
## visible approach — real activity concentrates near it, not evenly
## across the whole map) far more often than the map's own far edges,
## without ever ruling the edges out completely. Deliberately does NOT aim
## at the enemy's actual (fixed) mortar emplacements — the drone has no
## more prior knowledge of exactly where they are than the player does;
## the road's existence is public knowledge (it's drawn on the map), not
## secret intelligence, so weighting toward it isn't the same thing as
## knowing exact coordinates. Advances to a freshly re-rolled point once
## close enough to the current one rather than flying to and sitting at a
## single fixed spot — genuine progressive search coverage, not parking
## somewhere and stopping.
##
## Scaled down from an earlier version's 500m: with the grid's own
## individual legs only ~750-850m long (see GameConfig's own reasoning for
## why they're that short rather than a handful of full-width rows), a
## 500m arrival radius would let the drone "arrive" over half of every leg
## early, cutting each one badly short — this stays a comfortably smaller
## fraction of a leg's own length instead.
const DRONE_SWEEP_WAYPOINT_RADIUS: float = 200.0 * GameConfig.PIXELS_PER_METER
## How long the drone watches a mortar lead's spot, nothing in view, before the lead counts as checked and spent (tactical seconds).
const DRONE_LEAD_EMPTY_DWELL_S: float = 60.0
## Mortar lead (the unit) -> {"lead": the lead's time, "since": when the drone first came within DRONE_SWEEP_WAYPOINT_RADIUS of it}.
var _drone_lead_arrival: Dictionary = {}
## Mortar lead (the unit) -> the time of the newest lead the drone has flown to and found empty.
var _drone_checked_leads: Dictionary = {}
## Mortar lead (the unit) -> {"center": the spent lead's position, "lead": its time, "created": when it was spent}: the places the drone
## still means to look around it (see _lead_search_candidates).
var _drone_lead_searches: Dictionary = {}
## "If the drone doesn't see the mortar, it would look around a bit" (user): the four points of a diamond this far from a spent lead. A
## mortar in cover is noticed within 250 m (GameConfig.MORTAR_HIDDEN_DETECTION_RANGE), and a crew that fired and moved had a few hundred
## metres to go, so points ~300 m out cover the ground it can have reached.
const LEAD_SEARCH_RADIUS: float = 300.0 * GameConfig.PIXELS_PER_METER
const LEAD_SEARCH_VALUE: float = 2.0
const LEAD_SEARCH_LIFETIME_S: float = 240.0

## True once some enemy unit confirmed no longer any kind of threat
## (DESTROYED/WITHDRAWN/SURRENDERED — the same boundary _known_enemy_
## positions itself draws for "still a threat") has its own last-known
## position within GameConfig.DRONE_SWEEP_CLEARED_RADIUS_M of `point` — the
## enemy is now KNOWN not to be there, so a sweep waypoint landing on it is
## much less worth the trip (see _sweep_candidates). Uses the
## real, omniscient unit state rather than requiring THIS drone to have
## personally witnessed the kill — the same simplification
## _mortar_existence_confidence already relies on ("a real commander
## eventually being told the enemy mortars are destroyed").
func _area_confirmed_clear(point: Vector2) -> bool:
	var radius: float = GameConfig.DRONE_SWEEP_CLEARED_RADIUS_M * GameConfig.PIXELS_PER_METER
	for u in enemy_units:
		# Knowledge audit (2026-09-27): "the enemy is already known not to be there" (see
		# _sweep_candidates' own doc comment on this function) has to mean player_known_state — a unit
		# that died or pulled out unseen must not silently mark the ground around it as cleared. A
		# never-sighted unit's player_known_state defaults to ACTIVE, so it correctly never qualifies here.
		if u.player_known_state != Unit.State.ACTIVE and u.player_known_state != Unit.State.RETREATING:
			if point.distance_to(u.global_position) <= radius:
				return true
	return false


## The commander's own default assumption about where the enemy is likely
## to be found, absent any actual contact — deliberately NOT a function of
## elapsed tactical time. A commander has no way of knowing exactly when
## the enemy's advance actually began, so "more tactical time has passed,
## therefore they must be further in" would assume knowledge that isn't
## actually available (see this project's own knowledge-locality
## principle — a decision should only use what the commander could
## plausibly know). What IS ordinary, standing knowledge regardless of
## timing: this is defended ground, and the enemy's own start line and only
## approach road sit at the map's eastern edge (GameConfig.CURRENT_MAP.enemy.spawn_x)
## — so absent evidence otherwise, ground closer to that edge is simply
## more likely to matter than ground toward the friendly rear. A smooth
## gradient across the map's own width (GameConfig.
## ENEMY_APPROACH_LIKELIHOOD_MIN at the west edge up to _MAX at the east),
## not a hard cutoff — "much more likely," not "certain." Real evidence
## (an actual sighting) overrides this on its own merits via
## _contact_search_bonus, ADDED on top of whatever this returns rather
## than replacing it — a confirmed contact deep in the west should still
## win outright even though this function alone would rate that ground low.
func _enemy_approach_likelihood(point: Vector2) -> float:
	var t: float = clamp(point.x / GameConfig.MAP_WIDTH_PX, 0.0, 1.0)
	return lerp(GameConfig.ENEMY_APPROACH_LIKELIHOOD_MIN, GameConfig.ENEMY_APPROACH_LIKELIHOOD_MAX, t)


## A TIME-gated discount for flank-watch candidates specifically — not the
## same idea as _enemy_approach_likelihood above, and deliberately not
## reused for it. Flank-watch stays direction-agnostic for the whole battle
## (see _flank_watch_candidates' own doc comment) so it can still catch a
## genuine flanking maneuver, including through the west flank, late in a
## fight — a permanent directional bias there, the same way sweep has one,
## would defeat that purpose. But in the battle's opening minutes, a bearing
## point the enemy could not physically have marched to yet from their own
## known start line is not worth the drone's attention regardless of which
## way it points — this is public, doctrinal knowledge (where the enemy
## started, roughly how fast infantry advances), not a secret peek at their
## actual position, in the same spirit as _enemy_approach_likelihood's own
## static prior. Modeled as straight-line time-to-reach from
## GameConfig.CURRENT_MAP.enemy.spawn_x at GameConfig.ENEMY_ADVANCE_SPEED — a
## deliberately generous (fast) lower bound, since an actual flanking route
## would only take longer, not less time, than marching straight there.
## Ramps linearly from DRONE_FLANK_WATCH_EARLY_DISCOUNT_MIN up to 1.0 as
## scenario_elapsed_time reaches that travel time, so a bearing near the
## enemy's own spawn edge is treated as plausible almost immediately, while
## one deep in the friendly rear stays discounted for longer — exactly the
## asymmetry the reported bug was missing.
func _flank_watch_plausibility(point: Vector2) -> float:
	var distance_from_enemy_start: float = absf(GameConfig.CURRENT_MAP.enemy.spawn_x - point.x)
	var travel_time: float = distance_from_enemy_start / GameConfig.ENEMY_ADVANCE_SPEED
	if travel_time <= 0.0:
		return 1.0
	var t: float = clamp(scenario_elapsed_time / travel_time, 0.0, 1.0)
	return lerp(GameConfig.DRONE_FLANK_WATCH_EARLY_DISCOUNT_MIN, 1.0, t)


## The 25-cell sweep grid as candidates for the shared routine-recon pool
## (_drone_routine_recon_target) — one candidate per cell, valued by
## GameConfig.DRONE_SWEEP_ROW_WEIGHTS (bias toward the rows nearest the
## road — real activity concentrates near the enemy's own known approach,
## without ever claiming exact prior knowledge of where they'll actually
## be) and discounted wherever _area_confirmed_clear says the enemy is
## already known not to be there (permanent — a specific unit died or
## pulled out there for good; the TEMPORARY "I was just here" discount is
## handled generically for the whole merged pool by
## _drone_destination_recency_multiplier, not per-mechanism any more).
## Deliberately does NOT divide by the row's column count the way the old
## sweep-only picker did — that division only mattered for building a
## PROBABILITY distribution over sweep cells alone; now that recency and
## distance cost are handled by one shared formula across sweep AND
## flank-watch candidates together, each row's own weight can stand as a
## genuine per-cell value directly. Also weighted by _enemy_approach_
## likelihood — a SEPARATE, column/x-axis bias toward the enemy's own
## known approach edge, independent of the row/y-axis bias above.
## GameConfig.DRONE_MORTAR_HUNT_ROW_WEIGHTS contributes its own, ADDED
## value on the same column bias — a genuinely separate reason a cell
## might be worth checking (a possible mortar position, not just squad
## activity near the road) rather than folding the two concerns into one
## row-weight array. Finally picks up _contact_search_bonus, added rather
## than multiplied so a real, recent sighting (including a mortar fire-
## detection — see _update_recent_enemy_contacts) is worth more than
## either doctrinal bias alone says regardless of where it happens to be,
## which is what makes a discovered enemy actually widen the search around
## it instead of only being remembered as the one exact spot
## _area_confirmed_clear will eventually mark clear. Also discounted
## wherever _point_currently_observed says some OTHER friendly asset (a
## squad, the mortar, the spotter) can already see this ground right now
## — the same real-time "we know it's empty" fact the enemy heat-map
## overlay shows, applied here to the actual decision instead of just the
## visualization. This is what stops the drone from wastefully flying out
## to re-check ground immediately around the player's own dug-in units at
## the start of a battle, which they can already see is clear themselves;
## by the time the routine-recon tier is even being evaluated, any REAL
## live enemy nearby would already have been claimed by a higher-priority
## tier (squad-tracking/mortar-live) in _drone_search_target, so treating
## "currently observed" as "confirmed empty" here is safe, not just
## convenient. Reuses DRONE_SWEEP_CLEARED_WEIGHT_MULTIPLIER rather than a
## separate constant — both represent the same thing (real evidence this
## spot isn't worth the trip), just from a permanent-kill source versus a
## live-observation source.
func _sweep_candidates(committed_key: String = "") -> Array:
	var row_count: int = GameConfig.drone_search_rows_m().size()
	var columns_per_row: int = GameConfig.DRONE_SEARCH_GRID_COLUMNS_M.size()
	var waypoints: Array[Vector2] = GameConfig.drone_search_waypoints_px()
	# The mortar-hunt half of each cell's value shrinks with the same weighing
	# as the tier-level sweep score (see _drone_mortar_search_weight).
	var mortar_hunt_scale: float = _drone_mortar_search_weight()
	var out: Array = []
	for row_i in row_count:
		for col_i in columns_per_row:
			var idx: int = row_i * columns_per_row + col_i
			var point: Vector2 = waypoints[idx]
			var approach: float = _enemy_approach_likelihood(point)
			var value: float = (GameConfig.DRONE_SWEEP_ROW_WEIGHTS[row_i] + GameConfig.DRONE_MORTAR_HUNT_ROW_WEIGHTS[row_i] * mortar_hunt_scale) * approach
			# The drone's OWN camera doesn't count against the cell it is
			# currently flying to (committed_key): approaching a destination
			# brings it into view long before the drone arrives, and reading
			# that as "already looked, not worth it" collapsed the commitment
			# mid-flight — the drone then turned for the next-best cell, which
			# recovered full value the moment it was out of view, and the
			# pair dithered back and forth (live report: "going back and forth
			# for no good reason"). Ground units' views still count.
			if _area_confirmed_clear(point) or _point_currently_observed(point, "sweep:%d" % idx != committed_key):
				value *= GameConfig.DRONE_SWEEP_CLEARED_WEIGHT_MULTIPLIER
			value += _contact_search_bonus(point)
			out.append({"key": "sweep:%d" % idx, "point": point, "value": value})
	return out


## 1.0 with no record of this candidate at all, or once GameConfig.
## DRONE_DESTINATION_RECENTLY_VISITED_COOLDOWN_S has fully passed since the
## drone last actually arrived there — down to DRONE_DESTINATION_RECENTLY_
## VISITED_MIN_WEIGHT_MULTIPLIER the instant it just left, ramping back up
## linearly as the memory of "I already looked here" goes stale. A softer,
## decaying version of _area_confirmed_clear's permanent penalty: this is
## "probably still not worth an immediate repeat trip," not "definitively
## ruled out." Shared across both sweep and flank-watch candidates now that
## they compete in one pool.
func _drone_destination_recency_multiplier(key: String) -> float:
	if not _drone_destination_last_visited.has(key):
		return 1.0
	var elapsed: float = scenario_elapsed_time - _drone_destination_last_visited[key]
	if elapsed >= GameConfig.DRONE_DESTINATION_RECENTLY_VISITED_COOLDOWN_S:
		return 1.0
	var t: float = elapsed / GameConfig.DRONE_DESTINATION_RECENTLY_VISITED_COOLDOWN_S
	return lerp(GameConfig.DRONE_DESTINATION_RECENTLY_VISITED_MIN_WEIGHT_MULTIPLIER, 1.0, t)


## How far "arrived" means for a given routine-recon candidate — sweep
## cells and flank-watch bearings kept their own, separately-tuned arrival
## radii even after being merged into one pool, since they represent
## different real distances (a sweep leg vs. a close-in compass check).
func _drone_destination_arrival_radius(key: String) -> float:
	return GameConfig.DRONE_FLANK_WATCH_ARRIVE_RADIUS if key.begins_with("flank:") else DRONE_SWEEP_WAYPOINT_RADIUS


## Whether the destination the drone is still flying to has lost most of its
## reason for being: its score (value x recency - distance cost, exactly
## _pick_best_drone_destination's own) has fallen below
## GameConfig.DRONE_COMMITMENT_ABANDON_FRACTION of the best alternative's.
## Sticky-until-arrival exists to stop dithering between comparable options,
## not to hold a drone to a target whose value collapsed after it set out —
## live report: a sweep cell picked while an enemy mortar was still alive kept
## pulling the drone across the map, past close dangerous squads, long after
## that mortar was destroyed and the cell was worth almost nothing. The wide
## margin (and the abandoned cell staying excluded from the next pick) keeps
## an ordinary fluctuation in values from flipping the choice back and forth.
func _drone_commitment_has_collapsed(current: Dictionary, candidates: Array) -> bool:
	var alternative := _pick_best_drone_destination(candidates)
	if alternative.is_empty():
		return false
	var alt_score: float = _drone_candidate_score(alternative)
	if alt_score <= 0.0:
		return false
	return _drone_candidate_score(current) < GameConfig.DRONE_COMMITMENT_ABANDON_FRACTION * alt_score


func _drone_candidate_score(c: Dictionary) -> float:
	var distance_cost: float = active_drone.global_position.distance_to(c.point) * GameConfig.DRONE_DESTINATION_DISTANCE_COST_PER_PX
	return c.value * _drone_destination_recency_multiplier(c.key) - distance_cost


## The genuine argmax over whatever routine-recon candidates are currently
## on offer — value discounted by recency, discounted further by distance
## (GameConfig.DRONE_DESTINATION_DISTANCE_COST_PER_PX), so a nearby, modest
## opportunity can beat a slightly better one that's much further out.
## Deliberately excludes `_drone_current_destination_key`: a candidate the
## drone has just arrived at and is sitting on has a zero distance cost
## that can otherwise out-weigh every real competitor even at that
## candidate's own steepest recency discount (a candidate right under the
## drone always beats a real but distant alternative on pure arithmetic) —
## without this exclusion, the drone would lock onto wherever it happens to
## already be for a long time instead of the deliberate, brief "just left"
## discount this is supposed to be. Only called on arrival (or when the
## current commitment stops qualifying), not every tick — see
## _drone_routine_recon_target for the sticky-until-arrival wrapper that
## keeps this from re-running (and re-excluding whatever's currently
## committed) mid-flight.
func _pick_best_drone_destination(candidates: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -INF
	for c in candidates:
		if c.key == _drone_current_destination_key:
			continue
		var recency: float = _drone_destination_recency_multiplier(c.key)
		var distance_cost: float = active_drone.global_position.distance_to(c.point) * GameConfig.DRONE_DESTINATION_DISTANCE_COST_PER_PX
		var score: float = c.value * recency - distance_cost
		if score > best_score:
			best_score = score
			best = c
	return best


## The newest moment the friendly side got any real evidence an enemy
## mortar exists: a muzzle-flash/trajectory fire detection, or actually
## sighting one (Unit.player_known_position_time). -INF if none ever.
func _latest_mortar_evidence_time() -> float:
	var latest := -INF
	for info in _last_detected_mortar_fire.values():
		latest = max(latest, info.time)
	for u in enemy_units:
		if u.kind == Unit.Kind.MORTAR and u.player_has_been_sighted:
			latest = max(latest, u.player_known_position_time)
	return latest


## Empty sweep visits since the last new mortar evidence — zero the moment
## fresh evidence appears, even before the next arrival is counted.
func _effective_empty_sweeps() -> int:
	return 0 if _latest_mortar_evidence_time() > _empty_sweep_evidence_stamp else _empty_sweep_arrivals


## 0.0 to 1.0 — how much the friendly side's KNOWN enemy squads currently
## threaten it, for weighing speculative mortar searching against them (see
## _drone_mortar_search_weight). The worse of two measures per squad: how
## close it is to ANY active friendly unit (the same scale as
## _squad_danger_priority), and how close it is to the friendly MORTAR or
## DRONE TEAM, weighted up by GameConfig.DRONE_REAR_ASSET_THREAT_WEIGHT —
## unarmed or exposed rear assets are exactly what a squad slipping around
## the flank goes after. A squad we can't currently see still counts, at its
## LAST-KNOWN position, fading linearly to nothing over GameConfig.DRONE_
## CONTACT_BONUS_EXPIRY (the same window a contact stays worth searching
## around): the player knows it's out there, just not where it is now.
func _known_squad_danger_pressure() -> float:
	var rear_assets: Array[Unit] = []
	for u in player_units:
		if u.state == Unit.State.ACTIVE and (u.kind == Unit.Kind.MORTAR or u.kind == Unit.Kind.DRONE_TEAM):
			rear_assets.append(u)
	var pressure := 0.0
	for e in enemy_units:
		# Knowledge audit (2026-09-27): the function's own name is "known" pressure; e.state was ground
		# truth. Same fix as the others.
		if e.kind != Unit.Kind.SQUAD or not e.player_has_been_sighted or e.player_known_state != Unit.State.ACTIVE:
			continue
		var pos: Vector2 = e.global_position
		var fade := 1.0
		if not e.is_visible:
			pos = e.player_known_position
			fade = clamp(1.0 - (scenario_elapsed_time - e.player_known_position_time) / GameConfig.DRONE_CONTACT_BONUS_EXPIRY, 0.0, 1.0)
			if fade <= 0.0:
				continue
		var threat: float = clamp(1.0 - _nearest_active_friendly_distance(pos) / GameConfig.SQUAD_DANGER_RANGE, 0.0, 1.0)
		for asset in rear_assets:
			threat = max(threat, clamp(GameConfig.DRONE_REAR_ASSET_THREAT_WEIGHT * (1.0 - pos.distance_to(asset.global_position) / GameConfig.MORTAR_FLANK_THREAT_RADIUS), 0.0, 1.0))
		pressure = max(pressure, threat * fade)
	return pressure


## How much the drone's speculative search for an enemy mortar should count
## right now, 0.0 to 1.0: the estimated odds one is still out there
## (_mortar_existence_confidence, never treated as a certain zero — see
## GameConfig.DRONE_UNKNOWN_MORTAR_RESIDUAL_CONFIDENCE), worn down by every
## sweep cell already checked without finding anything new
## (DRONE_EMPTY_SWEEP_CONFIDENCE_FACTOR), and discounted by how dangerous
## the known enemy squads currently are (_known_squad_danger_pressure).
## Exactly the existing confidence, unchanged, early in a battle with no
## known squad danger and no empty sweeps yet.
func _drone_mortar_search_weight() -> float:
	var residual: float = GameConfig.DRONE_UNKNOWN_MORTAR_RESIDUAL_CONFIDENCE
	var confidence: float = max(_mortar_existence_confidence(), residual)
	confidence = max(confidence * pow(GameConfig.DRONE_EMPTY_SWEEP_CONFIDENCE_FACTOR, _effective_empty_sweeps()), residual)
	return confidence * (1.0 - GameConfig.DRONE_MORTAR_SEARCH_DANGER_DISCOUNT * _known_squad_danger_pressure())


## Where the drone flies for ROUTINE background recon — the merged sweep
## grid + flank-watch candidate pool, unified because both are really the
## same underlying activity (idle patrol with no specific live lead to
## chase yet) and a single flight is allowed to pick up sweep coverage AND
## a flank check together instead of the two mechanisms competing to be
## "the" routine choice (see _drone_search_target's own tier-6 doc comment
## for the outer picture). Sticky exactly like the two separate mechanisms
## this replaces used to be: keeps heading to the SAME committed candidate
## every tick until the drone actually arrives, or that candidate stops
## qualifying (e.g. a flank bearing gets screened mid-flight) — only THEN
## is a fresh pick actually made, via _pick_best_drone_destination, which
## excludes the just-left candidate so the recency discount alone (easily
## beaten by a zero-distance-cost candidate sitting right under the drone,
## see that function's own doc comment) isn't the only thing keeping the
## drone moving on. Takes flank_candidates already computed by the caller
## (_drone_search_target needs them anyway, to judge whether this whole
## tier is worth entering in the first place) rather than recomputing them.
func _drone_routine_recon_target(flank_candidates: Array) -> Dictionary:
	_drone_routine_pool_unaffordable = false
	var candidates: Array = _sweep_candidates(_drone_current_destination_key) + flank_candidates + _lost_contact_candidates() + _visible_force_candidates() + _lead_search_candidates()
	if candidates.is_empty():
		return {}
	# Only places the drone can actually reach AND get home from, on the
	# battery it has, in the wind as it is (user: skip sweep targets that are
	# "too far upwind for the battery it has" — the key metric being battery
	# per ground meter, see _drone_leg_charge). A committed destination that
	# has become unaffordable drops out like any other.
	var affordable: Array = candidates.filter(func(c): return _drone_can_afford_target(active_drone, c.point))
	if affordable.is_empty():
		_drone_routine_pool_unaffordable = true
		return {}
	candidates = affordable

	var current: Dictionary = {}
	for c in candidates:
		if c.key == _drone_current_destination_key:
			current = c
			break

	# Watching a force in sight: stay with it (and follow it as it moves) for as long as it is in sight,
	# rather than treating arriving as a visit and leaving for the next cell.
	if not current.is_empty() and current.key.begins_with("force:"):
		return current

	if not current.is_empty():
		var arrived: bool = active_drone.global_position.distance_to(current.point) <= _drone_destination_arrival_radius(current.key)
		if not arrived:
			if not _drone_commitment_has_collapsed(current, candidates):
				return current # still en route — keep heading there
			# Dropped mid-flight: not a visit, so no recency stamp and no
			# empty-sweep count — the drone never looked there.
		else:
			_drone_destination_last_visited[current.key] = scenario_elapsed_time
			if current.key.begins_with("sweep:"):
				_empty_sweep_arrivals = _effective_empty_sweeps() + 1
				_empty_sweep_evidence_stamp = _latest_mortar_evidence_time()

	var pick := _pick_best_drone_destination(candidates)
	if pick.is_empty():
		return current if not current.is_empty() else {}
	_drone_current_destination_key = pick.key
	return pick


## A point just inside MORTAR_MAX_RANGE of `target_pos`, along the direct
## line from `mortar` — nudged to a handful of nearby angles if the direct
## line would put the mortar in or through a building, which it can never
## do. Returns `mortar`'s own current position (a no-op move) if no angle
## works.
##
## Also tries hard to avoid landing within MORTAR_BUNCHING_AVOIDANCE_
## RADIUS of a sibling mortar's own current or pending position (see
## _sibling_mortar_positions's own doc comment) — a real, previously-
## reported gap: multiple enemy mortars hunting the SAME known player
## mortar had nothing stopping their advance points from converging near
## each other. The first angle that's building-clear AND sibling-clear
## wins outright; if none is, falls back to whichever building-clear
## angle keeps the MOST distance from the nearest sibling, rather than
## just the first one tried in priority order — still a real hunt move,
## the best one actually available, not a freeze.
##
## Clamped to the map's real operating area — a real, separate,
## previously-undiscovered bug found while tracing the bunching fix
## above: `target_pos - dir * target_distance` can land well past the
## actual map edge (confirmed directly: x=1074 against a real ~1000
## boundary) since, unlike GameConfig.clamp_to_operating_area's own
## callers, this function never clamped its candidates at all. Harmless
## as long as `target_pos` and `mortar` both sit well inside the map (the
## common case), but the bunching fix's own step-aside candidates
## routinely start from wherever a mortar happens to already be — which
## can be right at the edge — making this a real, reachable bug, not a
## theoretical one.
func _mortar_advance_point(mortar: Unit, target_pos: Vector2) -> Vector2:
	var base_dir: Vector2 = (target_pos - mortar.global_position).normalized()
	var target_distance: float = GameConfig.mortar_max_range(mortar.team) * 0.9 # comfortably in range, not right on the edge
	var siblings: Array[Vector2] = _sibling_mortar_positions(mortar)
	var best: Vector2 = mortar.global_position
	var best_score := -1.0
	# Direct, live-confirmed bug: with only the original ±45° spread, every
	# one of these candidates sits on an arc at the SAME fixed distance
	# from the SAME shared target_pos — when several mortars converge on
	# one known target (a real, common case: the enemy usually has more
	# tubes than the player has mortars to hunt) from broadly similar
	# directions, clamp_to_operating_area can clip every single candidate
	# to the exact same boundary point, collapsing what should have been a
	# real spread into literal 0m separation — reproduced directly with a
	# disposable smoke test (four mortars, one shared target, all four
	# landing on the identical clamped point). Widened to ±90° so a
	# genuinely different, in-bounds alternative exists far more often.
	# Also switched from "first to clear the radius wins, else track
	# whichever clears the most" to the same graduated
	# GameConfig.mortar_bunch_score_factor scoring every other mortar
	# relocation search already uses — picking the single best-SCORING
	# candidate (ties broken toward the smaller, more direct offset by
	# iteration order) is strictly more informative than a binary
	# clear-or-not split, and keeps this function's own behavior
	# consistent with the rest of the bunching-avoidance mechanism.
	for offset_deg in [0.0, -15.0, 15.0, -30.0, 30.0, -45.0, 45.0, -60.0, 60.0, -75.0, 75.0, -90.0, 90.0]:
		var dir: Vector2 = base_dir.rotated(deg_to_rad(offset_deg))
		var candidate: Vector2 = GameConfig.clamp_to_operating_area(target_pos - dir * target_distance)
		if GameConfig.mortar_barred_at(candidate, mortar.team) or GameConfig.mortar_path_barred(mortar.global_position, candidate, mortar.team):
			continue
		var nearest_sibling_dist := INF
		for p in siblings:
			nearest_sibling_dist = min(nearest_sibling_dist, candidate.distance_to(p))
		var score: float = GameConfig.mortar_bunch_score_factor(nearest_sibling_dist) if nearest_sibling_dist < INF else 1.0
		if score > best_score:
			best_score = score
			best = candidate
	return best


## Whether `m`'s own side already has good reason to think an OPPOSING mortar
## could actually reach this exact position with counter-battery fire right
## now — a known-ACTIVE (or RETREATING; still armed and in place until it's
## actually seen abandoned/withdrawn — same bar _known_enemy_mortars_in_range
## already uses) opposing mortar whose best-known position (a live sighting,
## the last confirmed sighting, or a muzzle-flash/trajectory detection) is
## within ITS OWN mortar_max_range of `m`. Team-symmetric mirror of
## _known_enemy_mortars_in_range's own logic (that one only ever answers for
## the player, feeding a different, density-based relocation urgency) — used
## here as the concrete, long-range half of "is there actually an opposing
## unit that could answer a sighting of `m`," alongside _unwatched_threat_
## closing's own close-range check just below, for BOTH sides now (direct
## user instruction, re a spotted mortar's willingness to fire: "This should
## apply to both sides"). See GameConfig.MORTAR_SPOTTED_UNKNOWN_THREAT_
## RELOCATE_CHANCE's own doc comment for what happens when this is false.
func _known_opposing_mortar_in_range(m: Unit) -> bool:
	var opposing: Array[Unit] = enemy_units if m.team == Unit.Team.PLAYER else player_units
	for u in opposing:
		if u.kind != Unit.Kind.MORTAR:
			continue
		var known_state: Unit.State = u.player_known_state if m.team == Unit.Team.PLAYER else u.enemy_known_state
		if known_state != Unit.State.ACTIVE and known_state != Unit.State.RETREATING:
			continue
		var known_pos: Vector2
		if u.is_visible:
			known_pos = u.global_position
		elif (u.player_has_been_sighted if m.team == Unit.Team.PLAYER else u.enemy_has_been_sighted):
			known_pos = u.player_known_position if m.team == Unit.Team.PLAYER else u.enemy_known_position
		elif mortar_ever_detected_firing(u):
			known_pos = _last_detected_mortar_fire[u].position
		else:
			continue
		if known_pos.distance_to(m.global_position) <= GameConfig.mortar_max_range(u.team):
			return true
	return false


## Whether an UNWATCHED (not currently is_visible — that's its own,
## separate "spotted" trigger, checked before this is even called) known
## enemy has actually closed to genuine overrun danger of `m`'s crew.
##
## Used to require genuine direct line of sight on top of proximity — a
## real, previously-reported failure mode found once enemy squads got a
## genuine "run the mortar down directly" pursuit (see BattleManager.
## _chasing_mortar_in_hot_pursuit): a squad closing from behind a fold in
## the ground or a treeline could be well inside real danger range without
## ever registering as LOS-clear, so the crew never started running until
## it was already too late. Direct user correction, after exactly that
## got a mortar destroyed: "It's enough if you know they are there, or
## even if you recently knew they were there" — see MORTAR_CREW_OVERRUN_
## DANGER_RANGE's own doc comment for the re-checked doctrine reasoning
## (FM 7-90's own local-security network exists to give warning of an
## approaching force BEFORE it's actually in the open in front of you, not
## only once it is). Proximity to a genuinely KNOWN position (see
## _known_enemy_positions — sighted at some point, not omniscient ground
## truth) is enough on its own now: a real crew doesn't need to physically
## see a closing threat to justify displacing before it arrives.
func _unwatched_threat_closing(m: Unit) -> bool:
	return _nearby_opposing_unit_within(m, GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE, false)


## Shared by _unwatched_threat_closing above (known positions only — its own
## doc comment explains why that's enough for the not-yet-spotted case) and
## _decide_mortar_action's own spotted-but-otherwise-unthreatened check
## (`include_live = true`), which cannot afford the same one-tick lag: a
## squad that becomes visible and closes to danger range on the very same
## tick the mortar itself is first spotted must count immediately, not only
## once _update_player_intel/_update_enemy_intel catch up later that same
## _process() call (they run AFTER _update_mortar_decisions — see that
## function's own doc comment). A live sighting is not omniscience, it's
## exactly what this side can see this instant — the same "while a unit is
## currently is_visible, ground truth IS knowledge" exception the rest of
## this file's knowledge-locality work already carves out everywhere else.
## Not a drone or a spotter either way: neither can overrun a crew (an unarmed observer, whichever kind —
## direct user ruling: "If the enemy has not seen the spotter, the spotter should have no effect on their
## actions [and even once seen,] this is good reason for the mortar to take evasive action, but not to
## leave the map" — the same category the drone was already carved out of this exact overrun-danger check
## for, not a new exception), so one nearby is no reason to run.
func _nearby_opposing_unit_within(m: Unit, danger_range: float, include_live: bool) -> bool:
	for pos in _known_enemy_positions(m.team, false, false):
		if m.global_position.distance_to(pos) <= danger_range:
			return true
	if not include_live:
		return false
	var opposing: Array[Unit] = enemy_units if m.team == Unit.Team.PLAYER else player_units
	for u in opposing:
		if u.kind == Unit.Kind.DRONE or u.kind == Unit.Kind.SPOTTER or not u.is_visible:
			continue
		if u.state != Unit.State.ACTIVE and u.state != Unit.State.RETREATING:
			continue
		if m.global_position.distance_to(u.global_position) <= danger_range:
			return true
	return false


## Whether the only thing troubling `m`'s crew is an UNARMED observer — a drone or a spotter, either kind
## or both together, nothing else — with no ground threat within overrun range and no counter-battery fire
## landing on it. That is a reason to conceal the crew, never to leave the map. Direct user ruling: "If
## [the enemy] have seen the spotter, this is good reason for the mortar to take evasive action, but not to
## leave the map. Instead, the mortar should assume its location is known and move in a way that makes it
## hard for friendly artillery to hit it, similar to what it would do if seen by a drone" — a lone forward
## observer can no more physically overrun or assault a crew than an aircraft can, so it earns the exact
## same treatment this function already gave a drone, not a new, separate mechanism. (Symmetric already:
## whichever side `m` belongs to, `opposing` is the other side's own units, so this applies unchanged
## whenever either side ever fields a SPOTTER.)
func _mortar_troubled_only_by_unarmed_observers(m: Unit) -> bool:
	if not m.is_visible or m.evading_counter_battery or _unwatched_threat_closing(m):
		return false
	var opposing: Array[Unit] = enemy_units if m.team == Unit.Team.PLAYER else player_units
	var unarmed_observers: Array[Unit] = []
	var others: Array[Unit] = []
	for u in opposing:
		if u.kind == Unit.Kind.DRONE or u.kind == Unit.Kind.SPOTTER:
			unarmed_observers.append(u)
		else:
			others.append(u)
	# Judged at the same, retained range the crew's own is_visible flag is kept at: a drone just beyond the ordinary range of a mortar in cover
	# (250 m) but inside 1.5 times it still has the crew spotted, and treating that as "nobody is watching, yet it is spotted" made a mortar that
	# only a drone could see flee the map as a last resort (a live battle, 2026-10-07: the drone's distance crossed 250 m on the last sample).
	return CombatResolver.has_live_observer(m, unarmed_observers, false, true) and not CombatResolver.has_live_observer(m, others, false, true)


## Whether `m`'s own side has, in turn, spotted the drone or spotter that has them in sight — "It might be
## aware of drone-only sighting. It depends if it has seen the drone or not," generalized the same way
## _mortar_troubled_only_by_unarmed_observers was: a spotter, like a drone, belongs to the OTHER team, so
## its own is_visible flag already means exactly this: the side watching `m` can see it back. The same
## live, fog-of-war-correct fact every other spotted/unspotted check in this file already reads, not a
## fresh detection roll — and, like every other piece of shared battlefield knowledge in this game
## (_known_enemy_positions and the like), one team member spotting it is the whole side knowing about it,
## not a private fact only the exact unit that saw it gets to act on. Only meaningful when
## _mortar_troubled_only_by_unarmed_observers(m) is already true (nothing else has `m` in sight); undefined
## otherwise.
func _mortar_has_seen_an_unarmed_observer(m: Unit) -> bool:
	var opposing: Array[Unit] = enemy_units if m.team == Unit.Team.PLAYER else player_units
	for u in opposing:
		if (u.kind == Unit.Kind.DRONE or u.kind == Unit.Kind.SPOTTER) and u.is_visible:
			return true
	return false


## A mortar crew that a drone (or spotter) has in view, and knows it, does not hide: concealment from an aircraft overhead is
## unlikely to work, and the rounds it draws take MORTAR_FLIGHT_TIME to land, so what keeps it alive is NOT BEING WHERE THEY ARE AIMED:
## it keeps moving, changing direction at random intervals (EVASION_TURN_MIN_S to EVASION_TURN_MAX_S), for as long as it is watched and EVASION_HOLD_S after. Direct user
## instruction: "A mortar that a drone has spotted should not conceal itself unless it can do so effectively. This seems unlikely. Rather, it
## should act in a way that makes it least likely to be hit. This might mean taking cover. It also might mean continually moving in
## unpredictable directions. It's a reasonable research question which is better." The answer, from the game's own numbers (see the
## doctrine log's entry of 2026-10-07): moving, if it turns often enough; straight-line movement and cover alone do not save a crew from
## fire that a drone is walking onto it. A crew that moves cannot fire (it must sit MORTAR_SETUP_TEARDOWN_TIME first), which is the price.
##
## How often it turns was first set at 4 s, which is far too often (user: "Our mortar could hit it by shooting at its current position."):
## a crew turning that often never gets 40 m from where it stands in the 40 s a round is in the air. Now a random time between
## EVASION_TURN_MIN_S and EVASION_TURN_MAX_S: against a shooter who leads along its heading, aims at where it stands, or aims along its
## recent movement, the best worst case is 15-30 s (tools/research/mortar_evasion_interval_sim.gd), so a change is nearly always due
## while a round is in flight, yet it moves far enough in between to be somewhere else when the round lands.
const EVASION_TURN_MIN_S: float = 15.0
const EVASION_TURN_MAX_S: float = 30.0
## Mortar -> the last time a counter-battery near-miss or hit sent it relocating (kept for the flee reason; see _mortar_flee_as_last_resort).
var _mortar_counter_battery_time: Dictionary = {}
const EVASION_LEG: float = 100.0 * GameConfig.PIXELS_PER_METER # each leg's target, never reached (the heading changes first: 30 s at 2.6 m/s is 78 m)
const EVASION_HOLD_S: float = 90.0
const EVASION_WANDER: float = 300.0 * GameConfig.PIXELS_PER_METER # how far from where it began it may stray before heading back
const EVASION_HEADING_TRIES: int = 12
## Mortar -> {"until": time the evasion lapses, "next_turn": time of the next heading change, "origin": where it began}.
var _mortar_evasion: Dictionary = {}

## What an observer can see of how an enemy mortar moves: mortar -> {"anchor": where it was last looked at, "heading": the direction it
## was then going, "turns": [the times it was seen to change direction]}. Kept only while it is in sight, from its visible positions
## alone, so it is the watching side's knowledge, not the crew's orders.
var _observed_mortar_track: Dictionary = {}


## Updates _observed_mortar_track from every mortar currently in sight of the other side. A direction change is a heading, taken over at
## least OBSERVED_STEP_M of movement, more than OBSERVED_EVASIVE_TURN_DEGREES from the last one.
func _update_observed_movement() -> void:
	for side in [player_units, enemy_units]:
		for u in side:
			if u.kind != Unit.Kind.MORTAR:
				continue
			var tr: Dictionary = _observed_mortar_track.get(u, {})
			var turns: Array = tr.get("turns", [])
			while not turns.is_empty() and scenario_elapsed_time - turns[0] > GameConfig.OBSERVED_EVASIVE_WINDOW_S:
				turns.pop_front()
			if u.state != Unit.State.ACTIVE or not u.is_visible:
				_observed_mortar_track[u] = {"turns": turns} # out of sight: the thread of its movement is lost
				continue
			if not tr.has("anchor"):
				_observed_mortar_track[u] = {"anchor": u.global_position, "turns": turns}
				continue
			if u.global_position.distance_to(tr.anchor) >= GameConfig.OBSERVED_STEP_M * GameConfig.PIXELS_PER_METER:
				var heading: float = (u.global_position - tr.anchor).angle()
				if tr.has("heading") and absf(angle_difference(heading, tr.heading)) > deg_to_rad(GameConfig.OBSERVED_EVASIVE_TURN_DEGREES):
					turns.append(scenario_elapsed_time)
				tr["heading"] = heading
				tr["anchor"] = u.global_position
			tr["turns"] = turns
			_observed_mortar_track[u] = tr


## Whether the side that can see `u` has seen it change direction enough, recently enough, to call it dodging (see
## GameConfig.MORTAR_EVASIVE_TARGET_VALUE_MULTIPLIER). Only what an observer could see: positions while in sight.
func _mortar_looks_evasive(u: Unit) -> bool:
	if u.kind != Unit.Kind.MORTAR or u.state != Unit.State.ACTIVE or not u.is_visible:
		return false
	var turns: Array = _observed_mortar_track.get(u, {}).get("turns", [])
	var recent := 0
	for t in turns:
		if scenario_elapsed_time - t <= GameConfig.OBSERVED_EVASIVE_WINDOW_S:
			recent += 1
	return recent >= GameConfig.OBSERVED_EVASIVE_TURNS


## Whether a remembered mortar fix (from _mortar_hunt_fix_for) is on a mortar that looks evasive: its own unit if the fix names one, else the
## opposing mortar standing at the fixed position.
func _mortar_fix_is_evasive(shooter: Unit, fix: Dictionary) -> bool:
	var named = fix.get("unit")
	if named is Unit and is_instance_valid(named):
		return _mortar_looks_evasive(named)
	var opposing: Array[Unit] = enemy_units if shooter.team == Unit.Team.PLAYER else player_units
	for o in opposing:
		if o.kind == Unit.Kind.MORTAR and o.global_position.distance_to(fix.position) <= 40.0 * GameConfig.PIXELS_PER_METER:
			return _mortar_looks_evasive(o)
	return false

## Whether `m` is being watched only by an unarmed observer and has seen it (the case this applies to).
func _mortar_observed_by_drone_and_aware(m: Unit) -> bool:
	return m.state == Unit.State.ACTIVE and m.is_visible and _mortar_troubled_only_by_unarmed_observers(m) and _mortar_has_seen_an_unarmed_observer(m)


## One tick of the evasive manoeuvre for `m`; true if it is evading this tick (the caller returns), false if it is not (or an armed threat
## has taken over: then the ordinary ladder decides).
func _mortar_evasion_step(m: Unit) -> bool:
	var st: Dictionary = _mortar_evasion.get(m, {})
	if _mortar_observed_by_drone_and_aware(m):
		if st.is_empty():
			st = {"next_turn": -INF, "origin": m.global_position}
		st["until"] = scenario_elapsed_time + EVASION_HOLD_S
		_mortar_evasion[m] = st
	if st.is_empty():
		return false
	if scenario_elapsed_time > st.until or m.state != Unit.State.ACTIVE or _unwatched_threat_closing(m):
		_mortar_evasion.erase(m)
		if _mortar_move_intent.get(m, "") == "evade_observed":
			_clear_mortar_move(m)
		return false
	if scenario_elapsed_time >= st.next_turn or not m.has_move_target:
		var heading: Vector2 = _pick_evasive_heading(m, st.origin)
		if heading != Vector2.ZERO:
			_issue_mortar_move(m, m.global_position + heading * EVASION_LEG, GameConfig.MORTAR_RELOCATE_SPEED_URGENT, "evade_observed")
			m.movement_predictable = false
		st["next_turn"] = scenario_elapsed_time + randf_range(EVASION_TURN_MIN_S, EVASION_TURN_MAX_S)
		_mortar_evasion[m] = st
	_mortar_reasoning[m] = {"tier": "Preserve self", "detail": "Seen by a drone, which concealment would not beat: moving unpredictably so the rounds, 40 s in the air, land where it no longer is."}
	return true


## A fresh random heading for an evasive leg: any direction where the next stretch is ground it may stand on (not a building, the river, the
## edge of the map, or for the Ukrainian crew the red area), not toward the nearest known ground threat, and heading back toward where the
## manoeuvre began once it has strayed EVASION_WANDER. Vector2.ZERO if nothing qualifies (it then stands).
func _pick_evasive_heading(m: Unit, origin: Vector2) -> Vector2:
	var pos: Vector2 = m.global_position
	var threats: Array[Vector2] = _known_enemy_positions(m.team, false, false)
	var nearest_threat := Vector2.INF
	for t in threats:
		if is_inf(nearest_threat.x) or pos.distance_to(t) < pos.distance_to(nearest_threat):
			nearest_threat = t
	var strayed: bool = pos.distance_to(origin) > EVASION_WANDER
	for i in EVASION_HEADING_TRIES:
		var angle: float = randf() * TAU
		if strayed:
			angle = (origin - pos).angle() + randf_range(-1.0, 1.0)
		var dir := Vector2(cos(angle), sin(angle))
		var ahead: Vector2 = pos + dir * EVASION_LEG * 0.75
		if ahead != GameConfig.clamp_to_operating_area(ahead):
			continue
		if GameConfig.mortar_barred_at(ahead, m.team) or GameConfig.is_river_at(ahead) or GameConfig.path_crosses_building(pos, ahead):
			continue
		if not is_inf(nearest_threat.x) and pos.distance_to(nearest_threat) < 1500.0 * GameConfig.PIXELS_PER_METER:
			if dir.dot((nearest_threat - pos).normalized()) > 0.64:
				continue # not toward it (within about 50 degrees)
		return dir
	return Vector2.ZERO


## Whether `m`'s crew is aware, right now, that it has been seen: spotted by anything other than an
## unarmed observer (a drone or a spotter) always counts; spotted only by one of those counts only if the
## crew's own side has seen it too (see _mortar_has_seen_an_unarmed_observer's own doc comment) — a real
## crew doesn't necessarily know an aircraft overhead, or a hidden forward observer, is watching it the way
## it knows a nearby squad has eyes on it, but if it HAS clocked the observer, it has every reason to
## assume it's been made.
func _mortar_aware_of_being_spotted(m: Unit) -> bool:
	if not m.is_visible:
		return false
	if not _mortar_troubled_only_by_unarmed_observers(m):
		return true
	return _mortar_has_seen_an_unarmed_observer(m)


## The single authoritative per-mortar-per-tick decision, replacing what
## used to be five independent functions racing to claim a mortar's move
## order via an informal has_move_target mutex (_update_resupply_linkup,
## _update_enemy_mortar_positioning, _update_friendly_mortar_hunting,
## _update_mortar_safety_relocation, _update_mortar_threat_response — all
## deleted). Tiered by the user's own explicitly stated priority order:
## preserve self > destroy enemy mortars > destroy dangerous squads >
## destroy other squads. Runs AFTER _tick_fire each tick, not before — a
## mortar that took a shot this tick has that already reflected in
## `has_shot` below and stands fast; only if it didn't fire this tick does
## any of this apply. Applies to BOTH sides identically (only the player's
## own move is narrated in the combat log — see _should_narrate_mortar_
## logistics's fog-of-war reasoning — but the decision logic itself is
## symmetric).
##
## Tiers 3 and 4 ("destroy dangerous/other squads") are target-SELECTION,
## not movement — a mortar never chases a squad (MORTAR_MAX_RANGE already
## dwarfs SQUAD_DANGER_RANGE, and _friendly_mortar_hunt_destination_is_
## reckless exists specifically to keep the crew behind its own infantry
## screen). Their outcome is already fully reflected in `has_shot`/
## `target` below via _pick_target's own weighting (_enemy_target_value)
## and ammo-conservation override — nothing left to decide here for them.
## Tier 2 actually outranks 3/4 there too now: _pick_target itself can
## choose to hold an available squad shot in favor of a known, far more
## valuable opportunity when it's safe to pursue (unspotted, nothing close
## enough to force the shot) — see its own doc comment. When that happens
## `has_shot` below is correctly false and this tier's own movement logic
## picks up the pursuit, exactly as if nothing had been available to
## shoot at all.
## Direct user report: "Even a mortar that has been spotted would have some willingness to fire if there
## is no indication of an opposing unit that can fire at it, such as an opposing mortar, or a nearby
## opposing squad. This should apply to both sides. The mortar's willingness to fire might be less than
## normal if it thinks there MIGHT be an opposing unit that can fire at it." Being merely SEEN used to be
## treated as danger on its own — a drone loitering overhead (unarmed, cannot itself fire back) produced
## the exact same flee-for-cover response as a squad closing in with a clear shot. This splits that: a
## CONCRETE indication (a known-ACTIVE opposing mortar within ITS OWN range — _known_opposing_mortar_in_
## range — or an opposing unit within genuine overrun-danger range, live or previously known —
## _nearby_opposing_unit_within, the same bar _unwatched_threat_closing already uses for the not-yet-
## spotted case) still returns true unconditionally, exactly as before; short of that, only a residual,
## decaying SUSPICION that an opposing mortar simply hasn't been located yet (_mortar_existence_confidence,
## team-parameterized) gives any reason at all to still seek cover, and at well below the concrete case's
## certainty (see GameConfig.MORTAR_SPOTTED_UNKNOWN_THREAT_RELOCATE_CHANCE's own doc comment). Neither
## indication at all returns false: a spotted crew with nothing suggesting anyone can hit it stays and
## keeps working the gun. False outright, with no roll at all, when `m` isn't actually visible — this is
## specifically about being SEEN, not about a threat closing unseen (that's `threat_closing`, computed
## separately by the caller from the same `_nearby_opposing_unit_within`/`_unwatched_threat_closing` pair).
func _mortar_spotted_danger(m: Unit) -> bool:
	if not m.is_visible:
		return false
	if _known_opposing_mortar_in_range(m) or _nearby_opposing_unit_within(m, GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE, true):
		return true
	var caution: float = GameConfig.MORTAR_SPOTTED_UNKNOWN_THREAT_RELOCATE_CHANCE * _mortar_existence_confidence(m.team)
	var caution_roll: float = 0.5 if profile_for(m.team).deterministic else randf()
	return caution_roll < caution


func _decide_mortar_action(m: Unit) -> void:
	_record_mortar_debug_history(m)
	var opposing: Array[Unit] = enemy_units if m.team == Unit.Team.PLAYER else player_units

	# Step 0 — resolve this tick's shot exactly once, through the memoized
	# accessor, so every tier below sees the identical answer _tick_fire
	# already acted on (or will act on — a genuinely dry mortar can never
	# actually fire regardless of what _pick_target returns, hence the
	# ammo conjunct here).
	var target: Unit = _mortar_shot_this_tick(m, opposing)
	if _fall_back_orders.has(m):
		_mortar_reasoning[m] = {"tier": "Commander's order", "detail": "Falling back toward the map edge, as ordered."}
		return
	if _risk_holds.has(m):
		_mortar_reasoning[m] = {"tier": "Self-risk policy", "detail": m.last_order_reason}
		return
	# Direct user report from a live battle: "why is the mortar falling back? It
	# looks like it has a good shot at the enemy mortar" and, once it did fire,
	# "it took way too long." A dry crew walks either to meet an inbound resupply
	# run ("linkup") or to a better spot ("out_of_ammo"); when the run delivers,
	# the reason for that walk is gone — but it stayed sticky (step 0b below) and
	# carried on to its stale destination, and a mortar under way never has a shot
	# (a crew must sit stationary MORTAR_SETUP_TEARDOWN_TIME before it can fire,
	# see _mortar_shot_this_tick), so with 20 fresh rounds and a visible enemy
	# mortar in range it kept walking away until it arrived and set up. Once
	# ammunition is back the no-ammunition walks end and the ladder decides afresh
	# (a shot, or — if the crew is still in danger — the ordinary tier-1
	# evade/conceal). Survival walks (evade, conceal) are not affected.
	if m.has_move_target and m.mortar_rounds_remaining > 0 and _mortar_move_intent.get(m, "") in ["out_of_ammo", "linkup"]:
		_clear_mortar_move(m)
	var has_shot: bool = target != null and m.mortar_rounds_remaining > 0

	# Computed here, before has_shot gets a say, so an available shot can
	# never itself block the one check that's supposed to outrank it — see
	# `overrun_danger`'s own doc comment immediately below for the live bug
	# this fixes. Tier 1's own later use of these two names further down
	# reuses this same computation rather than re-deriving it.
	var spotted: bool = m.is_visible
	var threat_closing: bool = not spotted and _unwatched_threat_closing(m)
	var spotted_danger: bool = _mortar_spotted_danger(m)
	# Direct, live-reported bug: "Mortar just let an enemy squad get
	# adjacent to it. It should not." Root cause: has_shot used to return
	# early UNCONDITIONALLY once any target was selected, with no check at
	# all for whether the crew itself was in real danger — meaning the
	# moment a closing enemy squad became a valid, in-range target, the
	# crew locked into "just keep firing" for the rest of the engagement,
	# with no self-preservation check ever run again, backwards from this
	# function's own stated priority order (preserve self outranks
	# destroying squads, not the other way around). `spotted_danger`/
	# `threat_closing` are exactly the same real-danger signals tier 1
	# already uses below to decide whether to flee; `overrun_danger` lets
	# has_shot defer to that same logic instead of silently overriding it.
	var overrun_danger: bool = (spotted_danger or threat_closing) and unit_doctrine_for(m).risk == "inherit"
	if has_shot and not overrun_danger:
		# Even with a valid shot lined up, a crew sitting critically close
		# to a sibling is one HE round away from losing both tubes (see
		# MORTAR_BUNCHING_CRITICAL_RADIUS's own doc comment) — preserve-
		# self outranks any targeting tier per the user's own stated
		# priority order, so a genuine dispersal option beats holding this
		# shot. A real, previously-reported gap: has_shot can stay true
		# for the mortar's entire ~30-second reload window whenever a
		# valid target keeps re-selecting, which is most ticks — meaning
		# this early return, unmodified, was the dominant reason multiple
		# independently-hunting mortars that converged near each other
		# then sat bunched indefinitely, never once reaching either the
		# tier-2 hunt step-aside or the idle-tier dispersal check below
		# (confirmed directly via a live trace: five enemy mortars stuck
		# 5-20m apart for many consecutive ticks, every one reporting
		# "target is selected" the whole time).
		#
		# Reactive, not a gate on target selection itself: if no better
		# spot actually exists this tick (boxed in), _mortar_advance_
		# point's own no-op fallback means `adjusted == m.global_position`
		# and the crew simply keeps the shot — a real crew doesn't go
		# silent forever just because the ideal dispersal spot isn't
		# available (the same "movement must never be starved to zero"
		# principle already established for the search itself).
		var bunch_siblings := _sibling_mortar_positions(m)
		var critically_bunched := false
		for p in bunch_siblings:
			if m.global_position.distance_to(p) < GameConfig.MORTAR_BUNCHING_CRITICAL_RADIUS:
				critically_bunched = true
				break
		if critically_bunched:
			var adjusted := _mortar_advance_point(m, target.global_position)
			if adjusted.distance_to(m.global_position) > 1.0:
				var speed: float = GameConfig.MORTAR_RELOCATE_SPEED if m.team == Unit.Team.PLAYER else GameConfig.REPOSITION_SPEED
				_issue_mortar_move(m, adjusted, speed, "disperse")
				_mortar_reasoning[m] = {"tier": "Preserve self", "detail": "Holding a valid shot, but too close to a sibling mortar — stepping clear first."}
				return
		_mortar_reasoning[m] = {"tier": "Target available", "detail": "A target is selected; no new movement order from this decision. Reload and firing gates still apply."}
		return
	# has_shot and overrun_danger both true: fall through to tier 1 below
	# exactly as if no shot had been available this tick at all — the
	# spotted/threat_closing branch there is what actually issues the
	# relocation order.

	# The Ukrainian crew will not set up a firing position within 200 m of a populated place (GameConfig.mortar_excluded_at), and cannot fire
	# from one (_tick_fire). One that is standing in the region with nothing to do (a fall-back run ended there, say) walks out to a legal
	# spot rather than sitting where it can do nothing.
	if _keeps_clear_of_populated(m) and not m.has_move_target and GameConfig.mortar_excluded_at(m.global_position):
		# Think about the places it could go (concealment, standoff, reach, leash) and what the walk there costs (_best_setup_position). The
		# ordinary relocation search looks only 75-160 m around, which deep in a town never reaches open ground (user: "it is now staying in
		# town even though it has ammo. It should move to some place it can fire."), so it is the fallback, then the nearest legal point.
		var choice: Dictionary = _best_setup_position(m, m.global_position, 1800.0)
		if not choice.is_empty():
			var legs: Array = choice.legs
			_issue_mortar_move(m, legs[0], GameConfig.MORTAR_RELOCATE_SPEED, "conceal")
			for i in range(1, legs.size()):
				m.move_queue.append(legs[i])
			_mortar_reasoning[m] = {"tier": "Preserve self", "detail": "Standing in a populated area, where the crew will not set up: walking out to the best place it can fire from (concealment, standoff, reach, and the walk there weighed)."}
			return
		if _relocate_mortar(m, "conceal", true):
			_mortar_reasoning[m] = {"tier": "Preserve self", "detail": "Standing in a populated area, where the crew will not set up: moving out to a firing position."}
			return
		var nearest: Vector2 = GameConfig.nearest_legal_setup_point(m.global_position, m.team)
		if nearest != m.global_position:
			_issue_mortar_move(m, nearest, GameConfig.MORTAR_RELOCATE_SPEED, "conceal")
			_mortar_reasoning[m] = {"tier": "Preserve self", "detail": "Standing in a populated area, where the crew will not set up: walking out to the nearest place it can fire from."}
			return

	# Watched by a drone and knows it: keep moving unpredictably rather than hide (see _mortar_evasion_step).
	if _mortar_evasion_step(m):
		return

	# Step 0b — an in-progress EMERGENCY self-preservation walk isn't
	# interruptible by a lower tier (hunting): evade/conceal/out_of_ammo/
	# linkup are all real, immediate necessities (a closing threat, being
	# spotted, no ammo to fight with at all), not something a known-mortar
	# opportunity should ever pull the crew off of mid-stride. This also
	# stops an is_visible blink or a _pick_target coin-flip from restarting
	# the whole ladder mid-walk — the mortar's own version of the
	# sticky-until-arrival commitment the drone rewrite needed for the
	# same reason.
	#
	# "scoot" is deliberately NOT on this list. Shoot-and-scoot's post-fire
	# reposition is a routine precaution, not an emergency — and unlike the
	# others, a single scoot leg can legitimately take several minutes of
	# tactical time to walk (real m/s speeds over real distances), which
	# was silently locking tier 2 hunting out for that whole stretch even
	# when a known, low-risk enemy mortar opportunity was sitting right
	# there — backwards from what "destroy enemy mortars" outranking a
	# mere precaution actually means. Falling through here still can't
	# actually disrupt the walk itself: every tier below only ever
	# OVERWRITES move_target when it finds something more important to do
	# (a fresh evade/conceal reason, or a viable hunt destination) — with
	# nothing more important going on, the ladder just reports "Holding"
	# and the scoot already under way keeps walking untouched via
	# _tick_movement, exactly as before.
	var current_intent: String = _mortar_move_intent.get(m, "")
	if m.has_move_target and current_intent in ["evade", "conceal", "out_of_ammo", "linkup"]:
		_mortar_reasoning[m] = {"tier": "Preserve self", "detail": "Continuing a displacement already under way (%s)." % current_intent}
		return

	# Tier 1 — Preserve self. Precedence among sub-reasons matches the
	# functions this replaces: out-of-ammo framing wins over a merely
	# spotted/threatened framing when both would apply. `spotted`/
	# `threat_closing` were already computed above, before has_shot.

	if m.mortar_rounds_remaining <= 0:
		var run := _active_resupply_run_for(m)
		if run != null and not m.evading_counter_battery and not spotted and not threat_closing and m.global_position.distance_to(run.global_position) > GameConfig.MORTAR_RESUPPLY_LINKUP_TRIGGER_RANGE:
			# A real doctrinal linkup, not a new coordination mechanism —
			# the run's own move_target already tracks the mortar live
			# either way (_update_resupply_run_targets), so closing from
			# both sides converges faster with zero extra coordination.
			# Skipped while evading counter-battery OR a threat is
			# actually closing in: survival beats logistics, matching
			# this trigger's old precedence — a crew that can't fire back
			# anyway has no reason to walk TOWARD a linkup instead of
			# AWAY from what's actually bearing down on it.
			# Meet it where the crew can fire from once it has the rounds: not in the red area or a building (user: "Mortar moved into the
			# town to meet the resupply run. Probably a bad move in the first place as this means it can't fire when it gets the ammo.")
			var meeting: Vector2 = run.global_position
			var legs: Array = []
			if _keeps_clear_of_populated(m):
				var choice: Dictionary = _best_setup_position(m, run.global_position, SETUP_LINKUP_RADIUS_M)
				if choice.is_empty():
					meeting = GameConfig.legal_meeting_point(m.global_position, run.global_position, m.team)
				else:
					meeting = choice.point
					legs = choice.legs
			_issue_mortar_move(m, meeting if legs.is_empty() else legs[0], GameConfig.MORTAR_RELOCATE_SPEED, "linkup")
			for i in range(1, legs.size()):
				m.move_queue.append(legs[i])
			_mortar_reasoning[m] = {"tier": "Preserve self", "detail": "Out of ammunition — closing on an inbound resupply run."}
			return
		# With no rounds to trade for standing and fighting, there is no
		# reason left to prefer a slower, better-hidden spot over actually
		# getting clear — see _relocate_mortar's own `force_urgent` doc
		# comment. A dry mortar being closed in on is exactly the same
		# "my current position is compromised" situation counter-battery
		# evasion already treats as urgent; this used to only ever get
		# the ordinary, unhurried relocation regardless of how close a
		# threat with a clear shot already was.
		if _relocate_mortar(m, "out_of_ammo", spotted or threat_closing) and _mortar_relocation_actually_helps(m):
			if _should_narrate_mortar_logistics(m):
				combat_log.log_mortar_relocating_out_of_ammo(m)
			_mortar_reasoning[m] = {"tier": "Preserve self", "detail": "Out of ammunition — relocating."}
		elif spotted or threat_closing:
			_mortar_flee_as_last_resort(m)
		else:
			_mortar_reasoning[m] = {"tier": "Preserve self", "detail": "Out of ammunition — wanted to relocate, no route this tick."}
		return

	if m.evading_counter_battery and unit_doctrine_for(m).risk == "inherit":
		# A near-miss/hit just landed (_resolve_pending_counter_battery) —
		# previously this flag only ever modified the SPEED of whatever
		# relocation happened to run next, and could sit set indefinitely
		# on a hold-position mortar (always true for the enemy) that never
		# got one. Now it's a first-class reason to displace on its own —
		# "they've found us" is exactly what "preserve self" as the top
		# goal means.
		if _relocate_mortar(m, "evade") and _mortar_relocation_actually_helps(m):
			combat_log.log_relocate(m, true)
			_mortar_reasoning[m] = {"tier": "Preserve self", "detail": "Just took counter-battery fire — displacing."}
		else:
			_mortar_flee_as_last_resort(m)
		return

	if (spotted_danger or threat_closing) and unit_doctrine_for(m).risk == "inherit":
		# By this point _pick_target has already had every chance to
		# engage (including its own ammo-conservation override for this
		# exact range), so "nothing to shoot" here genuinely means out of
		# ammo, reload not up, or no real target — not one being ignored.
		# Always urgent: reaching this branch at all already means
		# "an opposing unit is known to be able to hit this position, or
		# one is closing in from overrun range," the same "current
		# position is compromised" situation counter-battery evasion
		# treats as urgent above — not merely having been seen by
		# something with no way to answer (see `spotted_danger`'s own
		# doc comment above).
		if _relocate_mortar(m, "conceal" if spotted else "evade", true) and _mortar_relocation_actually_helps(m):
			if _should_narrate_mortar_logistics(m):
				if spotted:
					combat_log.log_mortar_relocating_for_cover(m)
				else:
					combat_log.log_mortar_relocating_from_threat(m)
			_mortar_reasoning[m] = {"tier": "Preserve self", "detail": "Spotted with nothing to shoot — relocating for cover." if spotted else "A threat with a clear line of sight is closing — relocating."}
		else:
			_mortar_flee_as_last_resort(m)
		return

	# The actual, real-world condition for needing to displace: could the
	# enemy plausibly hit this position right now — see
	# _mortar_should_relocate_for_safety's own doc comment for the full
	# two-part reasoning (recent detection, not yet cleared + a real enemy
	# mortar actually in range). Deliberately NOT "did I just fire"
	# (event-based triggers here have twice produced an opposite failure
	# this session — see the design doc's own revision log for both
	# directions) and reached here (tier 1, ranked above tier 2 hunting)
	# regardless of whether `has_shot` was true or false THIS tick, since
	# _mortar_shot_this_tick itself already refuses to look for a target
	# at all while this condition holds — so reaching this branch always
	# means there was never a shot to weigh against relocating in the
	# first place.
	if _mortar_should_relocate_for_safety(m):
		# `urgent` here means "bypass MORTAR_VOLUNTARY_RELOCATION_COOLDOWN
		# and search faster/farther" (see _relocate_mortar's own doc
		# comment) — a real, previously-reported live regression found
		# `m.shoot_and_scoot` folded into this: seconds_stationary resets
		# to 0 every tick a unit is actively MOVING (_tick_movement), so
		# the cooldown check is the ONLY thing stopping this tier from
		# recomputing a fresh, randomly-redrawn destination every SINGLE
		# tick for as long as _mortar_should_relocate_for_safety holds —
		# which, since that condition no longer requires a KNOWN threat,
		# can now be true continuously for many consecutive ticks. Folding
		# a steady-state doctrine PREFERENCE into `urgent` bypassed that
		# cooldown for the entire duration, reproducing — under a doctrine
		# choice as ordinary as "shoot and scoot" — the exact tick-by-tick
		# churn MORTAR_VOLUNTARY_RELOCATION_COOLDOWN was built to prevent
		# in the first place (see that constant's own doc comment).
		# Density-only, matching the original, already-correct formula:
		# `m.shoot_and_scoot` doesn't currently affect this tier at all —
		# a real, deliberate gap, not silently patched over. Doctrine
		# still matters for WHETHER this tier fires at all (see
		# _mortar_should_relocate_for_safety) — it just can't also control
		# this cooldown-bypass without reopening this exact bug.
		var known_in_range: int = _known_enemy_mortars_in_range(m.global_position, m.team)
		var urgent: bool = known_in_range >= GameConfig.MORTAR_DENSITY_FORCE_SCOOT_COUNT
		if current_intent == "scoot" and m.has_move_target:
			# A real, previously-reported live regression, deeper than the
			# doctrine-vs-urgent one fixed above: this branch used to call
			# _relocate_mortar every SINGLE tick this tier was reached,
			# with no check for whether the crew was already displacing
			# for this EXACT same reason — the comment below ("already
			# moving for some OTHER reason") was never actually enforced
			# in code. Whenever `urgent` reads true for ANY reason
			# (density alone is enough — MORTAR_DENSITY_FORCE_SCOOT_COUNT
			# known mortars, nothing to do with doctrine), that repeated
			# call bypasses MORTAR_VOLUNTARY_RELOCATION_COOLDOWN every
			# tick just like the doctrine-driven version did, reproducing
			# the identical churn through a path the previous fix never
			# touched. Sticky against itself now, same pattern already
			# used one tier up for evade/conceal/out_of_ammo/linkup — a
			# scoot already under way for this reason just keeps walking.
			_mortar_reasoning[m] = {"tier": "Preserve self", "detail": "Continuing a displacement already under way (scoot)."}
		elif m.has_move_target:
			# Already moving for some other reason (a hunt, most likely) —
			# redirect toward safety immediately rather than queuing a
			# fresh "packing up" delay the crew doesn't need: it's already
			# on its feet.
			if _relocate_mortar(m, "scoot", urgent):
				_mortar_reasoning[m] = {"tier": "Preserve self", "detail": "Position compromised — redirecting toward safety."}
			else:
				_mortar_reasoning[m] = {"tier": "Preserve self", "detail": "Position compromised — no better direction to redirect toward, continuing current move."}
		else:
			# Only narrated (and only actually queued) on the tick this is
			# FIRST noticed — _pending_mortar_displacement already tracks
			# "already handled," so every later tick spent waiting out the
			# real pack-up delay just quietly confirms the same reasoning
			# instead of re-queuing (which would reset the delay right back
			# to the exact bug this whole redesign exists to fix) or
			# re-logging the same line every tick until it actually departs.
			if not _pending_mortar_displacement.has(m):
				_queue_mortar_displacement(m, "scoot", urgent)
				if _pending_mortar_displacement.has(m):
					combat_log.log_mortar_relocating_from_density(m)
			if _pending_mortar_displacement.has(m):
				_mortar_reasoning[m] = {"tier": "Preserve self", "detail": "Position compromised by recent fire, with an enemy mortar able to reach it — preparing to relocate."}
			else:
				_mortar_reasoning[m] = {"tier": "Preserve self", "detail": "Position compromised — wanted to relocate, no route this tick."}
		return

	# Reached only when NONE of the tier-1 self-preservation triggers
	# above applied this tick — the mortar isn't currently compromised by
	# anything. Resets _mortar_max_distance_from_home's own high-water
	# mark here, not on a timer or once "safe enough": the floor exists
	# only to stop ONE continuous escape from being undone by a
	# differently-triggered relocation mid-episode, not to permanently
	# ratchet the mortar outward for the rest of the battle once the
	# actual danger that caused it has passed.
	if m.team == Unit.Team.PLAYER:
		_mortar_max_distance_from_home.erase(m)

	# Tier 2 — Destroy enemy mortars (the MOVEMENT half only — the
	# targeting half, "an enemy mortar candidate always wins," already
	# lives unconditionally in _pick_target and is reflected in `target`
	# above whenever one's actually in range).
	var fix := _mortar_hunt_fix_for(m)
	if not fix.is_empty():
		if m.global_position.distance_to(fix.position) <= GameConfig.mortar_max_range(m.team):
			# Checked every tick a mortar finds itself in range, regardless
			# of HOW it got here or whether it's currently moving — a
			# real, previously-reported gap: this used to only ever check
			# bunching (via _mortar_advance_point's own destination
			# search) while actively closing on a deliberate hunt-walk
			# (current_intent == "hunt"), but a mortar very often crosses
			# into range as a pure SIDE EFFECT of an unrelated relocation
			# (a routine "spotted, seek concealment" hop that happens to
			# land it within range of the known target) — confirmed
			# directly via a live trace: mortars showing this exact tier's
			# own "in range" reasoning while their stored intent was still
			# "conceal" from an entirely separate tier-1 trigger, meaning
			# the old `current_intent == "hunt"` gate never even evaluated
			# for them at all. Multiple mortars can each independently
			# wander into range near each other this way and then simply
			# hold, indefinitely, with zero bunching consideration ever
			# applied — real, sustained clustering (measured directly:
			# up to 14 real seconds), not the brief mid-transit path
			# crossings a much smaller share of raw "close" measurements
			# turn out to be.
			var siblings := _sibling_mortar_positions(m)
			var too_close := false
			for p in siblings:
				if m.global_position.distance_to(p) < GameConfig.MORTAR_BUNCHING_CRITICAL_RADIUS:
					too_close = true
					break
			if too_close:
				var adjusted := _mortar_advance_point(m, fix.position)
				if adjusted.distance_to(m.global_position) > 1.0:
					var speed: float = GameConfig.MORTAR_RELOCATE_SPEED if m.team == Unit.Team.PLAYER else GameConfig.REPOSITION_SPEED
					_issue_mortar_move(m, adjusted, speed, "hunt")
					_mortar_reasoning[m] = {"tier": "Destroy enemy mortars", "detail": "In range, but stepping clear of a nearby sibling mortar first."}
					return
			if current_intent == "hunt":
				# Now in range — stop closing and get to work, rather than
				# finishing the walk to a farther point computed earlier.
				_clear_mortar_move(m)
			_mortar_reasoning[m] = {"tier": "Destroy enemy mortars", "detail": "In range of a known enemy mortar."}
			return
		var dest := _mortar_hunt_destination_for(m, fix.position, fix.trusted)
		if dest != m.global_position and not _advances_past_fall_back_line(m, dest):
			var was_already_hunting: bool = current_intent == "hunt"
			var speed: float = GameConfig.MORTAR_RELOCATE_SPEED if m.team == Unit.Team.PLAYER else GameConfig.REPOSITION_SPEED
			_issue_mortar_move(m, dest, speed, "hunt")
			# Silent for the enemy, matching _update_enemy_mortar_
			# positioning's own original behavior — only the player's own
			# hunt is ever narrated.
			if not was_already_hunting and m.team == Unit.Team.PLAYER:
				combat_log.log_mortar_hunting(m, fix.trusted)
			_mortar_reasoning[m] = {"tier": "Destroy enemy mortars", "detail": "Closing on a known enemy mortar position."}
			return
		# A real, reported bug: this used to `return` here unconditionally,
		# permanently trapping the mortar in this exact branch for as long
		# as `fix` stays non-empty — which, per _known_enemy_mortar_lead's
		# own third fallback (a last-SEEN position, no expiry at all), can
		# be the rest of the battle. Confirmed directly via the game's own
		# live debug snapshot during actual play: a player mortar frozen
		# in place for real minutes, reporting this exact "no acceptable
		# route" reasoning every single tick, because the known fix sat
		# far enough past MORTAR_HUNT_MAX_RANGE_FROM_HOME that NO angle
		# _friendly_mortar_hunt_point tries could ever satisfy the home
		# leash — a geometric relationship that never changes tick to
		# tick, so retrying identically forever never helps. Falls
		# through to the idle "Holding" tier below instead — genuinely
		# more honest (the mortar isn't accomplishing anything by
		# pretending to still be working the approach) and gives that
		# tier's own bunching-dispersal check (if this mortar has
		# siblings) a chance it could never get while stuck here.
		_mortar_reasoning[m] = {"tier": "Destroy enemy mortars", "detail": "Wants to close on a known enemy mortar, no acceptable route this tick."}

	# A mortar with genuinely nothing to shoot, hunt, or displace for is not
	# actually "done" if it's sitting critically close to a sibling — a
	# real, previously-reported gap: the bunching step-aside above only
	# ever runs inside tier 2's own "in range of a known enemy mortar"
	# path, so a mortar that reaches this catch-all (no known fix at all
	# yet, or one that's mostly holding a selected target — see the
	# has_shot early return at the very top, which this tier never even
	# gets a chance to react to) could sit bunched indefinitely with zero
	# corrective pressure. Confirmed directly via a live trace: a 12-tick
	# sustained episode where the bunched mortars spent its first ~10
	# ticks alternating between this exact "nothing worth shooting" state
	# and "target selected" (has_shot) — never once reaching tier 2 at
	# all — only correcting once a fix finally became known. Routine
	# standing dispersion, not an emergency, so deliberately NOT added to
	# step 0b's sticky list — same reasoning already established for
	# "scoot" there.
	var idle_siblings := _sibling_mortar_positions(m)
	for p in idle_siblings:
		if m.global_position.distance_to(p) < GameConfig.MORTAR_BUNCHING_CRITICAL_RADIUS:
			if _relocate_mortar(m, "disperse"):
				_mortar_reasoning[m] = {"tier": "Holding", "detail": "Nothing worth shooting or hunting, but too close to a sibling mortar — dispersing."}
			else:
				_mortar_reasoning[m] = {"tier": "Holding", "detail": "Too close to a sibling mortar, but no better dispersal spot this tick."}
			return

	_mortar_reasoning[m] = {"tier": "Holding", "detail": "Nothing worth shooting, moving for, or relocating away from right now."}


## Iterates every ACTIVE mortar on both sides and hands each one to
## _decide_mortar_action — the single call site _process now uses in place
## of the five separate functions that used to run at different points in
## the tick (see _decide_mortar_action's own doc comment for the full
## list). Runs where _update_mortar_safety_relocation/_update_mortar_
## threat_response used to, after _tick_fire — deliberately AFTER the two
## mortar-hunting functions used to run too (they ran before _tick_fire),
## which fixes a real, previously-undiscovered bug: hunting never checked
## has_move_target before overwriting a mortar's move order, so it could
## silently steal a shoot-and-scoot displacement out from under a mortar
## that had just fired, defeating the whole point of scooting. Moving
## hunting to run after _tick_fire (and gating it, via step 0b above, the
## same way every other tier already was) closes that gap.
func _update_mortar_decisions() -> void:
	for m in player_units + enemy_units:
		if m.kind != Unit.Kind.MORTAR:
			continue
		if m.state != Unit.State.ACTIVE:
			# Otherwise _mortar_reasoning[m] would simply freeze at whatever
			# it last said while still ACTIVE (e.g. "Target available") —
			# misleading in the Decision Inspector for a crew that's since
			# retreated or been destroyed, well past the point that
			# reasoning was ever accurate.
			if _mortar_reasoning.has(m):
				_mortar_reasoning[m] = {"tier": "Preserve self", "detail": "No longer in action (%s)." % Unit.State.keys()[m.state].to_lower()}
			continue
		_decide_mortar_action(m)


## See _mortar_debug_history's own doc comment for why this exists.
## Recorded unconditionally at the very top of _decide_mortar_action,
## before any tier or early return, so it captures every tick regardless
## of which path the decision ladder actually takes that tick (including
## "had a shot, stood and fought" ticks — the full picture of what a
## crew was doing right up to the moment something happened to it, not
## just the self-preservation-relevant ticks).
func _record_mortar_debug_history(m: Unit) -> void:
	var nearest_known_m: float = INF
	for p in _known_enemy_positions(m.team):
		nearest_known_m = min(nearest_known_m, m.global_position.distance_to(p) / GameConfig.PIXELS_PER_METER)
	var entry: Dictionary = {
		"t": snappedf(scenario_elapsed_time, 0.1),
		"position": _pos_to_debug_dict(m.global_position),
		"is_visible": m.is_visible,
		"threat_closing": (not m.is_visible) and _unwatched_threat_closing(m),
	}
	if not is_inf(nearest_known_m):
		entry["nearest_known_enemy_m"] = snappedf(nearest_known_m, 1.0)
	var history: Array = _mortar_debug_history.get(m, [])
	history.append(entry)
	while history.size() > MORTAR_DEBUG_HISTORY_LIMIT:
		history.pop_front()
	_mortar_debug_history[m] = history


## Public accessor for an out-of-band developer view of live mortar
## decisions, mirroring drone_pilot_debug_snapshot() — see BattleScreen's
## _write_debug_snapshot for why this is written unconditionally, every
## frame, rather than gated on any on-screen toggle. Deliberately includes
## BOTH sides (an out-of-band developer file, not something the player
## sees — same precedent as battle_history_viewer.gd's own deliberate
## ground-truth omniscience); if a future on-screen panel is ever built
## from this, THAT should stay player-mortars-only, matching _should_
## narrate_mortar_logistics's existing fog-of-war boundary.
func weather_debug_snapshot() -> Dictionary:
	if weather == null:
		return {"weather": "none"}
	var out: Dictionary = weather.debug_snapshot()
	out["drones_grounded_for_weather"] = _drone_grounded_for_weather
	out["drones_lost_to_weather"] = _drones_lost_to_weather
	out["drones_aborted_by_weather"] = _drones_aborted_by_weather
	out["drones_recalled_by_rain"] = _drones_recalled_by_rain
	return out


func mortar_decision_debug_snapshot() -> Dictionary:
	var out: Dictionary = {}
	for m in player_units + enemy_units:
		if m.kind != Unit.Kind.MORTAR:
			continue
		var reasoning: Dictionary = _mortar_reasoning.get(m, {"tier": "N/A", "detail": "no decision recorded yet"})
		out[m.display_name()] = {
			"team": "player" if m.team == Unit.Team.PLAYER else "enemy",
			"position": _pos_to_debug_dict(m.global_position),
			"rounds_remaining": m.mortar_rounds_remaining,
			"state": Unit.State.keys()[m.state],
			"move_intent": _mortar_move_intent.get(m, "none"),
			"orders": {"fire_on_squads": _mortar_squad_fire_orders.has(m), "fall_back": _fall_back_orders.has(m)},
			"reasoning": reasoning,
			"recent_history": _mortar_debug_history.get(m, []),
		}
	return out


## Out-of-band developer view of EVERY unit on BOTH sides — position,
## state, current move order, and (for a RETREATING unit) why — the same
## "read it directly, don't guess from a screenshot" visibility the mortar
## and drone snapshots already give, generalized to the whole battle. This
## is what a general-retreat investigation actually needs and the other
## two snapshots don't cover at all: which cover point (if any) a specific
## unit is currently walking to, not just its own kind's own narrower
## slice of the decision space. Same conventions as mortar_decision_debug_
## snapshot: both sides, unconditional, written every frame regardless of
## any on-screen toggle (see BattleScreen's own _write_debug_snapshot).
func general_unit_debug_snapshot() -> Dictionary:
	var out: Dictionary = {}
	for u in player_units + enemy_units:
		var entry: Dictionary = {
			"team": "player" if u.team == Unit.Team.PLAYER else "enemy",
			"kind": Unit.Kind.keys()[u.kind],
			"state": Unit.State.keys()[u.state],
			"position": _pos_to_debug_dict(u.global_position),
			"has_move_target": u.has_move_target,
			"last_order_reason": u.last_order_reason,
			"pips": u.pips,
			"max_pips": u.max_pips,
			"fall_back_ordered": _fall_back_orders.has(u),
		}
		if u.kind == Unit.Kind.SQUAD:
			entry["suppression"] = snappedf(u.suppression, 0.01)
			entry["pinned"] = u.pinned
		var combat_row: Dictionary = unit_combat_stats.rows.get(u.get_instance_id(), {})
		if not combat_row.is_empty():
			entry["shots_fired"] = combat_row.shots
			entry["hits_scored"] = combat_row.hits
			entry["casualties_inflicted"] = combat_row.casualties
		if u.has_move_target:
			entry["move_target"] = _pos_to_debug_dict(u.move_target)
		# A real, previously-reported gap this exact field was added to
		# close: a retreat decision reasons about what the PLAYER actually
		# knew about an enemy (player_has_been_sighted/player_known_
		# position — see _known_enemy_positions's own "if team == PLAYER:
		# ... player_known_position" branch), a frozen last-sighting
		# snapshot that can differ substantially from this same unit's own
		# live global_position above once contact is lost — ground truth
		# alone can't explain (or rule out) a retreat decision at all.
		if u.team == Unit.Team.ENEMY:
			entry["is_visible"] = u.is_visible
			entry["player_has_been_sighted"] = u.player_has_been_sighted
			if u.player_has_been_sighted:
				entry["player_known_position"] = _pos_to_debug_dict(u.player_known_position)
			# Direct live user question: several enemy squads far from the known player squads were showing
			# "No target available: advance another bound toward the current objective" and not obviously
			# closing the gap. Nothing previously exposed WHICH objective ("advance by bounds" resolves to
			# one of: an enemy flanking waypoint, the known friendly mortar, a known friendly squad,
			# a consolidation point, the village, or a push west — see _enemy_advance_objective) a given
			# squad was actually chasing, so a wide flanking swing (a real, previously-confirmed feature,
			# see GameConfig.ENEMY_FLANK_CHANCE) was indistinguishable from a squad genuinely stuck.
			if u.kind == Unit.Kind.SQUAD and u.state == Unit.State.ACTIVE:
				entry["flanking_route_active"] = u.flanking_route_active
				entry["advance_objective"] = _pos_to_debug_dict(_enemy_advance_objective(u))
				entry["enemy_attack_stance"] = _enemy_attack_stance()
		else:
			# For a friendly unit is_visible means the ENEMY currently sees
			# it — what an enemy mortar needs before it can fire at it.
			entry["visible_to_enemy"] = u.is_visible
		out[u.display_name()] = entry
	return out


func _process(delta: float) -> void:
	if battle_over or combat_log == null or is_paused:
		return

	_kill_happened_this_tick = false
	elapsed_time += delta
	_seconds_since_last_shot += delta

	var scenario_delta: float = delta * _current_time_scale()
	scenario_elapsed_time += scenario_delta
	_update_weather(scenario_delta)

	# Cleared here, before anything (including _tick_fire, later this same
	# tick) can populate it — see _mortar_tick_shot's own doc comment.
	_mortar_tick_shot.clear()

	if scenario_elapsed_time - _history_last_recorded_time >= HISTORY_SNAPSHOT_INTERVAL_S:
		_history_last_recorded_time = scenario_elapsed_time
		_record_history_snapshot()

	_update_sighting_flags()
	_update_mortar_resupply()
	_update_mortar_resupply_requests()
	_update_resupply_run_targets()

	_tick_movement(scenario_delta)
	_resolve_resupply_run_arrivals()
	_update_spotting(scenario_delta)
	_update_observed_movement()
	_update_joint_mortar_hunt()
	_update_enemy_squad_advance()
	_update_friendly_squad_positioning()
	_update_spotter_positioning()
	_update_ground_risk_orders()
	_update_drone_operations(scenario_delta)
	_update_drone_team_evasion()

	for unit in player_units:
		_tick_fire(unit, delta, scenario_delta, enemy_units)
	for unit in enemy_units:
		_tick_fire(unit, delta, scenario_delta, player_units)

	_update_mortar_decisions()
	_resolve_pending_counter_battery()
	_resolve_pending_mortar_shots()
	_resolve_pending_mortar_displacement()
	_update_suppression(scenario_delta)
	_update_player_intel()
	_update_enemy_intel()
	_check_enemy_commander_retreat()
	_check_enemy_mortar_isolated_retreat()
	_update_fall_back_orders()
	_enforce_fall_back_hold()
	_prune_fire_flashes()
	_record_unit_decisions()
	_check_battle_end()
	queue_redraw() # keep fire-tracer and mortar-impact fade-outs animating smoothly
	for unit in player_units + enemy_units:
		unit.queue_redraw() # cover ring must track position/terrain live


## Any unit with an active move_target (the enemy's road march, either side
## bolting for cover, or a retreat's first leg to cover — see
## Unit.order_retreat) walks straight toward it and stops on arrival. A
## RETREATING unit with no move_target left is on its final leg: the
## straight pull to its own side's safe line, marked WITHDRAWN on arrival —
## no longer part of the fight, but its casualties still count in the AAR.
##
## Takes `scenario_delta`, not the actual/engine delta — move_speed values
## are real m/s (see GameConfig), so movement must be paced against the
## tactical clock they're realistic relative to, not real elapsed play time.
func _tick_movement(scenario_delta: float) -> void:
	for unit in player_units + enemy_units:
		if unit.kind == Unit.Kind.RESUPPLY_RUN and not unit.resupply_delivered and unit.resupply_target_mortar != null and unit.resupply_target_mortar.state == Unit.State.ACTIVE:
			# Direct user report, seen in the post-battle replay: a resupply
			# run appeared to drive right past a mortar that was actively
			# relocating (shoot-and-scoot/evade/hunt — NOT retreating, which
			# already aborts the run outright below in
			# _resolve_resupply_run_arrivals) without ever delivering, with
			# an extreme play-speed override (Godot's own debug time-scale,
			# stacked on top of this game's own TIME_SCALE_FAST_FORWARD tier)
			# confirmed active at the time.
			#
			# Root cause, confirmed with a synthetic stress test: _update_
			# resupply_run_targets (below _tick_movement in _process) sets
			# this run's move_target from the mortar's position BEFORE this
			# tick's own movement runs. Under an ordinary scenario_delta that
			# staleness is trivial (well under MORTAR_RESUPPLY_ARRIVAL_RADIUS)
			# and the run's real speed advantage (7 m/s vs. a relocating
			# mortar's 2.2 m/s, see MORTAR_RESUPPLY_RUN_SPEED/MORTAR_RELOCATE_
			# SPEED) converges it in. But at a large enough single-tick
			# scenario_delta, the mortar's OWN per-tick displacement can
			# exceed the arrival radius outright — and since the run is
			# always chasing LAST tick's already-stale position, it can
			# perpetually trail just outside arrival range even though it's
			# genuinely faster than what it's chasing, tick after tick,
			# indefinitely (verified: a synthetic run at a fixed 40-tactical-
			# second-per-tick step, well within reach of an 8x Godot debug
			# time-scale stacked on FAST_FORWARD's 300x, never delivered in
			# 500 simulated ticks despite the speed advantage).
			#
			# Fixed here rather than in _update_resupply_run_targets itself:
			# this unit's mortar is always EARLIER in this same player_units/
			# enemy_units array (a RESUPPLY_RUN can only be spawned — see
			# _spawn_resupply_run — targeting a mortar that already exists,
			# and is always appended after it), so by the time this loop
			# reaches the run's own turn, its mortar has already taken
			# *this* tick's step. Retargeting right here, immediately before
			# the run takes its own step, means it always aims at the
			# mortar's truest, current-this-tick position — not a snapshot
			# from before either of them moved — closing the staleness
			# window entirely rather than just shrinking it.
			unit.move_target = _resupply_run_destination(unit, unit.resupply_target_mortar.global_position)
			unit.has_move_target = true
		if unit.state == Unit.State.RETREATING:
			if unit.has_move_target:
				_step_toward_target(unit, scenario_delta)
			else:
				_step_retreat(unit, scenario_delta)
		elif unit.state == Unit.State.ACTIVE and unit.has_move_target:
			_step_toward_target(unit, scenario_delta)
		if unit.activity == Unit.Activity.MOVING:
			unit.seconds_stationary = 0.0
		else:
			unit.seconds_stationary += scenario_delta


## A DRONE flies over the river freely (it's airborne — see GameConfig.
## has_aerial_los's own reasoning for why the river never blocks it);
## every ground unit routes via the one bridge instead. Checked fresh
## every tick rather than once at order time, since a unit re-ordered
## mid-crossing (a fresh cover pick, a hunt retarget) must still route
## correctly rather than being allowed to cut straight across just
## because its ORIGINAL order happened to already be past the bank.
## `unit.move_queue.push_front` puts the real destination right after the
## bridge leg — the existing move_queue pop in _step_toward_target's own
## arrival branch then continues on to it with no further special casing.
func _river_route(unit: Unit) -> void:
	if unit.kind == Unit.Kind.DRONE:
		return
	if GameConfig.is_river_at(unit.move_target):
		# The destination itself is unreachable — inside the river, not
		# just across it. Some other system (a cover pick, a rally point)
		# chose it with no idea the river exists there; confirmed directly
		# this used to happen with a per-squad-shifted road waypoint that
		# landed inside the river for any off-road spread offset (see
		# ROAD_WAYPOINTS_M's own comment) — the fix there removed that
		# specific case, but this general guard stays, since nothing else
		# checks the river before choosing a destination either. Redirect
		# to the crossing itself and leave whatever's already queued
		# BEHIND it alone — pushing the unreachable point back onto the
		# queue would just reproduce the same "arrive, re-target something
		# inside the river" loop this function exists to prevent.
		unit.move_target = GameConfig.nearest_river_crossing(unit.position, unit.move_target)
		return
	if not GameConfig.path_crosses_river(unit.position, unit.move_target):
		return
	var crossing: Vector2 = GameConfig.nearest_river_crossing(unit.position, unit.move_target)
	if unit.move_target.distance_to(crossing) <= Unit.MOVE_ARRIVE_RADIUS:
		return # already routed to the crossing itself
	unit.move_queue.push_front(unit.move_target)
	unit.move_target = crossing


func _step_toward_target(unit: Unit, scenario_delta: float) -> void:
	_river_route(unit)
	unit.activity = Unit.Activity.MOVING
	var to_target: Vector2 = unit.move_target - unit.position
	var dist: float = to_target.length()
	var step: float = unit.move_speed * scenario_delta
	if unit.kind == Unit.Kind.DRONE and dist > 0.001:
		step = _drone_ground_speed(unit.move_speed, to_target / dist) * scenario_delta
	if step >= dist or dist <= Unit.MOVE_ARRIVE_RADIUS:
		unit.position = unit.move_target
		if not unit.move_queue.is_empty():
			unit.move_target = unit.move_queue.pop_front()
			# has_move_target stays true — next leg of the path starts next tick.
		else:
			unit.has_move_target = false
			unit.activity = Unit.Activity.STATIONARY
	else:
		unit.position += to_target.normalized() * step


## The player's mortar crew retreating to the west edge is routed AROUND buildings, through the streets, when the straight dash would
## run into one: the route (GameConfig.mortar_route_to_x) is queued as ordinary legs and the straight dash resumes where the way is
## clear. It may cross the populated-place region (a retreat is a move, not setting up). Without it a dash across Voznesensk's dense
## blocks stalls: the crew stood at x = 430 m for 40,000 ticks. False (nothing issued) for any other crew (the enemy's retreat is left as
## it was), a clear straight run, or a crew boxed in with no route.
func _route_mortar_retreat_around_buildings(m: Unit) -> bool:
	if m.team != Unit.Team.PLAYER:
		return false
	if not GameConfig.path_crosses_building(m.position, Vector2(m.retreat_target_x, m.position.y)):
		return false
	var route: Array[Vector2] = GameConfig.mortar_route_to_x(m.position, m.retreat_target_x)
	if route.is_empty():
		return false
	m.move_queue.clear()
	m.move_target = route[0]
	for i in range(1, route.size()):
		m.move_queue.append(route[i])
	m.has_move_target = true
	m.move_speed = m.retreat_speed
	return true


## The final leg is a dash toward the safe line's x, primarily along x but
## bending in y away from the nearest known threat along the way (see
## _retreat_avoidance_offset) rather than a compass-straight line
## regardless of what's known to be out there. For a MORTAR, that line can
## also happen to run straight through a building (the village is a real
## obstacle now, not a rare edge case at this map's real scale). Since a
## mortar can never enter one, it sidesteps vertically, away from whatever
## building is blocking it, until clear, then the normal dash resumes on
## its own — see _sidestep_building.
func _step_retreat(unit: Unit, scenario_delta: float) -> void:
	if unit.kind == Unit.Kind.MORTAR and _route_mortar_retreat_around_buildings(unit):
		_step_toward_target(unit, scenario_delta)
		return
	unit.activity = Unit.Activity.MOVING
	var dir_x: float = -1.0 if unit.team == Unit.Team.PLAYER else 1.0
	var next_pos: Vector2 = unit.position + Vector2(dir_x * unit.retreat_speed * scenario_delta, 0.0)

	if unit.zigzagging:
		unit._zigzag_timer -= scenario_delta
		if unit._zigzag_timer <= 0.0:
			unit._zigzag_timer = randf_range(GameConfig.ZIGZAG_JINK_MIN_INTERVAL, GameConfig.ZIGZAG_JINK_MAX_INTERVAL)
			var lateral_sign: float = 1.0 if randf() < 0.5 else -1.0
			unit._zigzag_lateral_velocity = lateral_sign * unit.retreat_speed * GameConfig.ZIGZAG_LATERAL_SPEED_FRACTION
		next_pos.y += unit._zigzag_lateral_velocity * scenario_delta

	# Bend away from the nearest known threat rather than dashing straight
	# through/past it — see GameConfig.RETREAT_THREAT_STEER_FRACTION.
	next_pos.y += _retreat_avoidance_offset(unit) * unit.retreat_speed * GameConfig.RETREAT_THREAT_STEER_FRACTION * scenario_delta

	# Direct user report: a drone team's dashboard read "withdrawing" but the unit itself was nowhere to be
	# found — found at y well above the top of the map (a raw y of -485 against a [0, MAP_HEIGHT_PX] map).
	# A previous fix bounded the ONE-TIME cover-seeking first leg a retreat can take
	# (order_retreat's SPOTTER/DRONE_TEAM branch, via safest_cover_point's own reference_point), but this
	# function is the ORDINARY, EVERY-TICK straight-line retreat that leg hands off to — both the zigzag
	# jink above and _retreat_avoidance_offset's own continuous steering nudge y with no bound at all,
	# tick after tick, for as long as a retreat actually takes. A threat sitting persistently to one side
	# (steering always the same way) or an unlucky zigzag streak can accumulate real drift over a long
	# retreat with nothing ever pulling it back, eventually running the unit off the top or bottom of the
	# map outright — the same class of bug the earlier fix addressed for the first leg, but never reached
	# this one, since it is a structurally separate code path.
	#
	# Y ONLY, deliberately NOT GameConfig.clamp_to_operating_area (a direct user report caught this: "Enemy
	# is retreating but failed to exit the map" — confirmed via the live debug snapshot, EVERY enemy unit on
	# the field stuck in RETREATING at exactly x=MAP_WIDTH_PX). clamp_to_operating_area's own x range is
	# [-WEST_FLANK_WIDTH_PX, MAP_WIDTH_PX] — it has a deliberate west-side buffer wide enough to contain
	# PLAYER_SAFE_X, but no matching east-side buffer, because none of its OTHER callers (cover-seeking
	# searches) ever need to reach past the map's own east edge. GameConfig.ENEMY_SAFE_X, this function's
	# own retreat_target_x for the enemy side, is deliberately set PAST that edge (spawn_x + 150m, the same
	# "don't end literally on the boundary" reasoning PLAYER_SAFE_X already documents) — clamping x here
	# walled the enemy side off from ever reaching its own exit line at all, leaving every retreating enemy
	# unit stuck forever at x=MAP_WIDTH_PX, RETREATING, never WITHDRAWN. x was never actually the source of
	# the ORIGINAL y-drift bug this clamp was added for — only y needs bounding here.
	next_pos.y = clamp(next_pos.y, 0.0, GameConfig.MAP_HEIGHT_PX)

	if unit.kind == Unit.Kind.MORTAR and GameConfig.is_building_at(next_pos):
		_sidestep_building(unit, scenario_delta, next_pos)
		return

	# Only reachable by a unit that's already on the FAR side of the river
	# from its own safe line (an enemy squad that fought its way across and
	# is now being pushed back, most likely) — every unit's OWN side is
	# already on the correct side of the crossing by construction, so a
	# normal retreat never needs this. Same idea as _sidestep_building —
	# hold x, steer y toward the one gap — but toward a known fixed point
	# rather than just "away from center," since there's no way around a
	# full-height river except straight through its single crossing.
	if GameConfig.is_river_at(next_pos):
		_sidestep_river(unit, scenario_delta)
		return

	unit.position = next_pos
	var reached: bool = (unit.position.x <= unit.retreat_target_x) if unit.team == Unit.Team.PLAYER else (unit.position.x >= unit.retreat_target_x)
	if reached:
		unit.position.x = unit.retreat_target_x
		unit.state = Unit.State.WITHDRAWN
		unit.queue_redraw()
		combat_log.log_withdrawn(unit)


## Signed lateral steering strength for _step_retreat's final dash: 0.0
## with no known threat close enough to react to; otherwise the sign
## points away from the nearest one's own y (positive = steer toward
## higher y), scaled up to 1.0 as that threat gets closer — a threat
## right on top of the retreat line demands a sharper correction than one
## just barely within range. Same danger-range framing _still_under_
## pressure already uses (mortar crew vs. everyone else), since it's
## asking the same underlying question: is this threat close enough to
## actually matter right now.
func _retreat_avoidance_offset(unit: Unit) -> float:
	var range_m: float = GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE if unit.kind == Unit.Kind.MORTAR else GameConfig.SQUAD_DANGER_RANGE
	var nearest_dist: float = INF
	var nearest_threat: Vector2 = Vector2.INF
	for p in _known_enemy_positions(unit.team):
		var d: float = unit.global_position.distance_to(p)
		if d < nearest_dist:
			nearest_dist = d
			nearest_threat = p
	if nearest_dist > range_m:
		return 0.0
	var urgency: float = clamp(1.0 - nearest_dist / range_m, 0.0, 1.0)
	var away_sign: float = 1.0 if unit.global_position.y >= nearest_threat.y else -1.0
	return away_sign * urgency


func _sidestep_building(unit: Unit, scenario_delta: float, blocked_pos: Vector2) -> void:
	var building_center_y: float = unit.position.y
	for zone in GameConfig.CURRENT_MAP.terrain_zones:
		if zone.type == GameConfig.TerrainType.BUILDING and zone.rect.has_point(blocked_pos):
			building_center_y = zone.rect.position.y + zone.rect.size.y / 2.0
			break
	var dir_y: float = -1.0 if unit.position.y <= building_center_y else 1.0
	unit.position.y += dir_y * unit.retreat_speed * scenario_delta


## Unlike _sidestep_building (a compact, localized obstacle a unit can go
## AROUND with a Y-only nudge), a river/canal spans a whole band across
## much of the map — perpendicular movement only actually escapes it if
## aimed at the one real crossing, and which axis that even is depends on
## which way the river happens to run on this particular map (vertical
## for Moshchun, roughly horizontal for Pervomaiske's canal — see
## GameConfig.CURRENT_MAP's own doc comment). Walking straight toward the
## known crossing point in both x and y at once sidesteps needing to
## detect the river's own local orientation at all.
func _sidestep_river(unit: Unit, scenario_delta: float) -> void:
	var crossing: Vector2 = GameConfig.CURRENT_MAP.river.crossing_point_m * GameConfig.PIXELS_PER_METER
	var to_crossing: Vector2 = crossing - unit.position
	if to_crossing.length() > 1.0:
		unit.position += to_crossing.normalized() * unit.retreat_speed * scenario_delta


## Takes scenario_delta (tactical seconds), not real elapsed_time — every
## other rate-based system in _process (movement, ammo, resupply timing)
## is calibrated in tactical time, and CombatResolver.SPOT_CHANCE_PER_
## SECOND is no exception, despite the generic parameter name. Passing
## real delta here instead was a genuine bug this project shipped with for
## a while: at TIME_SCALE_NORMAL (60x) alone, a target sitting in plain,
## point-blank view for a real 10 seconds — 30 tactical MINUTES — could
## still go entirely unspotted, since the roll only accumulated real-world
## seconds' worth of chance while tactical time (and the observer's own
## movement) raced ahead 60x faster. Confirmed empirically before fixing:
## a drone and mortar placed exactly on top of each other, in the open,
## went unspotted for that same 30 simulated minutes in a real trial.
func _update_spotting(scenario_delta: float) -> void:
	_refresh_visibility(player_units, enemy_units, scenario_delta)
	_refresh_visibility(enemy_units, player_units, scenario_delta)


## Visibility is live, not permanent: a target already visible stays that
## way only as long as some observer currently has line of sight to it
## (checked every tick, hard cutoff, no chance roll — see
## CombatResolver.has_live_observer); the instant nobody does, it goes
## invisible again, even if it was seen a moment ago. A target not currently
## visible has a chance each tick to be freshly noticed (CombatResolver.
## roll_spot — the existing probabilistic, concealment-aware roll).
##
## The friendly (player) mortar goes through exactly this same roll, same
## as any other unit — it tries to avoid being seen (siting, cover,
## shoot-and-scoot relocation, all already modeled) via CombatResolver's
## own mortar-specific hidden/exposed concealment treatment
## (GameConfig.MORTAR_HIDDEN_DETECTION_RANGE/MORTAR_EXPOSED_CONCEALMENT_
## MULTIPLIER), but if an enemy genuinely gets within range with clear LOS
## to it, it CAN and does get spotted and directly engaged, exactly like
## any other unit would be. Counter-battery detection (muzzle blast/
## trajectory, see _launch_mortar_shot's _last_detected_mortar_fire and
## _known_friendly_mortar_position) is a separate, complementary channel
## for a last-known position even without a current visual sighting — not
## the only way to ever find it.
func _refresh_visibility(observers: Array[Unit], targets: Array[Unit], scenario_delta: float) -> void:
	for target in targets:
		if target.state == Unit.State.DESTROYED or target.state == Unit.State.SURRENDERED:
			continue
		if target.is_visible:
			# `retained` (true here — see has_live_observer's own doc comment): a target already in view
			# doesn't lose that the instant it drifts a few meters past the range it took to first notice
			# it — real tracking has more inertia than first acquisition. Direct user report: "Enemy
			# squads were just flashing visibility at our retreating squads when the enemies fired... once
			# a unit has been spotted, let's have it stay spotted up to 150% of the range." Building/hill
			# LOS is untouched by this and still drops a target at once, per that same instruction.
			if CombatResolver.has_live_observer(target, observers, false, true):
				_tree_sight_lost_for.erase(target)
			else:
				# Someone would still see it but for the woods in between:
				# give that TREE_SIGHT_LOSS_GRACE_S of continuous failure
				# first, so a squad slipping in and out of a tree line
				# doesn't flash in and out of view. Any other reason to
				# lose it (building, hill, range) drops it at once, range
				# already widened by `retained` above.
				var lost_to_trees: bool = CombatResolver.has_live_observer(target, observers, true, true)
				var failing_for: float = _tree_sight_lost_for.get(target, 0.0) + scenario_delta
				if lost_to_trees and failing_for < GameConfig.TREE_SIGHT_LOSS_GRACE_S:
					_tree_sight_lost_for[target] = failing_for
				else:
					_tree_sight_lost_for.erase(target)
					target.is_visible = false
					target.queue_redraw()
					combat_log.log_lost_contact(target)
			continue
		for observer in observers:
			if observer.state != Unit.State.ACTIVE:
				continue
			if CombatResolver.roll_spot(observer, target, scenario_delta):
				target.is_visible = true
				if target.team == Unit.Team.ENEMY:
					_assign_discovery_number(target) # before queue_redraw/log_spotted, so both already show the real number
				target.queue_redraw()
				combat_log.log_spotted(target)
				break


## Snapshots what the player's own side actually knows about each enemy
## unit's condition right now — see Unit.player_known_pips/_known_state/
## _has_been_sighted's own doc comment. Only updates while a unit is
## is_visible; once visibility is lost the snapshot simply stays wherever
## it last was, the same way a real commander's last report doesn't
## un-happen just because contact was lost afterward. Run every tick, after
## this tick's own combat resolution — a unit that gets destroyed or
## surrendered this same tick, while still visible the instant before, is
## correctly captured (the visibility-clearing check in _refresh_visibility
## already skips DESTROYED/SURRENDERED targets rather than dropping their
## is_visible flag, so it's still true here).
func _update_player_intel() -> void:
	for u in enemy_units:
		if u.is_visible:
			u.player_has_been_sighted = true
			u.player_known_pips = u.pips
			u.player_known_state = u.state
			u.player_known_position = u.global_position
			u.player_known_position_time = scenario_elapsed_time
			if u.kind == Unit.Kind.MORTAR and u.mortar_gun_abandoned:
				u.player_known_gun_abandoned = true # once actually seen abandoned, never un-known again


## The exact mirror of _update_player_intel above, for the enemy's own
## knowledge of the player's units — see Unit.enemy_has_been_sighted's own
## doc comment for why this needed to exist at all. Same "run every tick,
## after this tick's own combat resolution" timing, same reasoning for why
## a unit destroyed the same tick it was last seen is still correctly
## captured.
func _update_enemy_intel() -> void:
	for u in player_units:
		if u.is_visible:
			u.enemy_has_been_sighted = true
			u.enemy_known_pips = u.pips
			u.enemy_known_state = u.state
			u.enemy_known_position = u.global_position
			u.enemy_known_position_time = scenario_elapsed_time
			if u.kind == Unit.Kind.MORTAR and u.mortar_gun_abandoned:
				u.enemy_known_gun_abandoned = true # once actually seen abandoned, never un-known again


## `scenario_delta` (tactical seconds) drives a MORTAR's reload timer — a
## realistic lay-load-fire cycle is a real-world-time thing (see Unit.
## reload_time), not tied to how much actual play-session time you spend
## watching. Everything else (squad fire_interval, the has_move_target/
## building gates below) stays on `delta` (actual/engine seconds) — those
## were never part of this ask, just the mortar's own cycle was.
##
## A RETREATING unit has, in general, disengaged — but a genuine fighting
## withdrawal doesn't mean walking past an enemy unarmed. A SQUAD (both
## sides identically) that's still within its own normal engagement range
## and line of sight — exactly what _pick_target below would already
## consider a legal target if this unit were standing its ground — fires
## back even while pulling out, rather than presenting a free target the
## instant it starts moving away. A retreating MORTAR fires the same way,
## UNLESS its crew left the gun behind (Unit.mortar_gun_abandoned — always
## true after a hit decisive enough to retreat over; otherwise decided once,
## at the moment retreat starts, by Unit._mortar_gun_abandoned_on_unhit_
## retreat), in which case there's nothing left to fire with regardless of
## how close anyone gets.
func _tick_fire(unit: Unit, delta: float, scenario_delta: float, enemies: Array[Unit]) -> void:
	if unit.state == Unit.State.ACTIVE and _risk_holds.has(unit): return
	if unit.kind == Unit.Kind.SPOTTER or unit.kind == Unit.Kind.DRONE_TEAM or unit.kind == Unit.Kind.DRONE:
		return # pure reconnaissance — extends detection only, never fires (see roll_spot)
	if unit.kind == Unit.Kind.RESUPPLY_RUN:
		return # unarmed logistics detail — never fires back
	if unit.state == Unit.State.DESTROYED or unit.state == Unit.State.WITHDRAWN or unit.state == Unit.State.SURRENDERED:
		return # gone, already safe, or has laid down arms — none of these ever fire again
	var fighting_withdrawal := false
	if unit.state == Unit.State.RETREATING:
		if unit.kind == Unit.Kind.MORTAR and unit.mortar_gun_abandoned:
			return # gun left behind — nothing left to fire with
		fighting_withdrawal = true # still subject to the normal _pick_target range/LOS check below — this only lifts the "too busy moving" block, not the range one
	if unit.has_move_target and not fighting_withdrawal and unit.kind != Unit.Kind.MORTAR:
		return # moving with intent (road march, diving for cover) — too busy to fire.
		# Without this, "immediately head for cover" was true mechanically
		# (seek_cover() redirects movement right away) but invisible in
		# practice: the unit kept trading fire the whole way there, so a
		# dash for cover looked identical to just standing and fighting. A
		# fighting withdrawal is a deliberate exception to that: it's
		# already conceding the fight (retreating, not choosing to stand),
		# and only fires at all because _pick_target finds something close
		# enough that walking past unarmed wouldn't be realistic. A MORTAR
		# gets its own, broader exception below — see the has_move_target
		# check right before _launch_mortar_shot.
	if unit.kind == Unit.Kind.MORTAR and GameConfig.mortar_barred_at(unit.global_position, unit.team):
		return # no overhead clearance to lob a round from inside a building; and the Ukrainian crew will not set up in a populated area
	if unit.kind == Unit.Kind.MORTAR and unit.mortar_rounds_remaining <= 0:
		return # out of ammunition — see _spawn_resupply_run for how it eventually gets more

	unit.fire_timer -= scenario_delta if unit.kind == Unit.Kind.MORTAR else delta
	if unit.fire_timer > 0.0:
		return

	var target := _mortar_shot_this_tick(unit, enemies) if unit.kind == Unit.Kind.MORTAR else _pick_target(unit, enemies)
	if target == null:
		unit.fire_timer = unit.fire_interval
		return

	if unit.kind == Unit.Kind.MORTAR:
		if unit.has_move_target:
			# A real, in-range, ammo-available target just turned up while
			# this mortar was mid-relocation (shoot-and-scoot, a threat-
			# response displacement, a hunt toward a suspected enemy
			# mortar — any of them) — stop and take the shot rather than
			# walking past it, the same "stop and get to work" idiom
			# _decide_mortar_action's own tier 2 already uses once back in
			# range of a hunted enemy mortar.
			# Unlike a squad on the march, a mortar crew mid-relocation
			# hasn't abandoned the gun (that's what RETREATING means) —
			# it's just walking it somewhere else, and a real crew sets the
			# tube down and fires rather than passing up a shot dead to
			# rights. Deliberately uniform across every reason the mortar
			# might currently be moving, including an urgent counter-
			# battery evasion already in progress — a finer "is THIS
			# specific walk safety-critical" distinction is real but out of
			# scope for this fix; see the tactical-rewrite doctrine doc.
			_clear_mortar_move(unit)
		# Burst fire: fire _mortar_burst_shot_count's committed number of
		# rounds at the same target in quick succession (all within this
		# one tick — at these tactical timescales that's already "quick
		# succession," and every existing per-shot mechanism, real
		# ballistic dispersion, counter-battery detection, ammo
		# consumption, still applies independently to each round; a bigger
		# burst is a proportionally bigger counter-battery risk, not a free
		# one). Stops early if ammo runs out mid-burst — the loop's own
		# guard, not a separate check, since _launch_mortar_shot already
		# spends a round every call.
		for _shot_index in _mortar_burst_shot_count(unit, target):
			if unit.mortar_rounds_remaining <= 0:
				break
			_record_shot(unit, target)
			_launch_mortar_shot(unit, target)
		unit.fire_timer = unit.reload_time
		# No post-shot scoot-queueing here anymore — see _mortar_shot_
		# this_tick and _decide_mortar_action's own "relocate for safety"
		# tier-1 check for why: this used to queue a displacement after
		# EVERY shot on a real, previously-reported failure mode — a real
		# crew doesn't reset its own 30-second packing-up clock every time
		# it fires again, but _queue_mortar_displacement's own overwrite
		# semantics did exactly that (a fresh call always replaces the
		# pending entry outright), so a mortar reloading and re-engaging
		# faster than that 30s window (routine, given reload_time defaults
		# to the SAME 30s) could perpetually re-queue its own departure
		# and never actually leave — "always shooting, never scooting."
		# The real condition for needing to displace was never "did I just
		# fire" anyway — it's "does the enemy now know where I am well
		# enough to hit me," which persists (and is checked fresh every
		# tick, with no resettable timer to game) independent of exactly
		# how many more shots happen to land in the meantime.
		return

	_record_shot(unit, target)

	# SQUAD: direct fire resolves immediately, unlike a mortar's lobbed
	# shell — see _launch_mortar_shot for that delayed path.
	#
	# A squad's muzzle flash gives it away immediately. Like any visibility,
	# this can be lost again later once nobody has eyes on it.
	if not unit.is_visible:
		unit.is_visible = true
		unit.queue_redraw()
		combat_log.log_revealed_by_fire(unit)

	# Coming under fire alerts the whole enemy side, not just the unit being
	# shot at — every enemy squad still marching breaks for cover too.
	if target.team == Unit.Team.ENEMY and target.kind == Unit.Kind.SQUAD and not enemy_alerted:
		enemy_alerted = true
		_alert_enemy_squads()

	_fire_flashes.append({
		"from": unit.global_position, "to": target.global_position, "team": unit.team,
		"time": elapsed_time, "is_mortar": false,
	})
	_history_fire_events.append({
		"from": unit.global_position, "to": target.global_position, "team": unit.team,
		"time": scenario_elapsed_time, "is_mortar": false,
	})
	_seconds_since_last_shot = 0.0
	if _gunfire_ambience != null:
		_gunfire_ambience.report_shot(unit.team)
	_resolve_fire_and_check_bunching(unit, target, target.global_position)
	unit.fire_timer = unit.fire_interval


## A mortar's shell doesn't land the instant it fires — see
## GameConfig.MORTAR_FLIGHT_TIME (40 tactical seconds). This schedules the
## impact rather than resolving it now; see _resolve_pending_mortar_shots
## for what happens when it actually lands, including the enemy-alert and
## hit-consequence logging that used to happen right here for a mortar shot
## — that has to wait for impact too, not fire.
##
## Counter-battery is still triggered at the moment of firing, though (real
## counter-battery radar tracks the outgoing round, not its impact).
## Everything that must happen the instant ANY mortar round leaves ANY tube:
## the on-screen muzzle flash, the replay history record, and the shot's
## sound. Both real firing paths (_launch_mortar_shot for ordinary fire and
## _resolve_pending_counter_battery for a reply) go through this, so a new
## per-shot effect can never again be added to one and forgotten in the
## other — that exact duplication left every counter-battery reply silent
## (see the 2026-09-24 doctrine-doc entry). A third firing path should call
## this too.
func _announce_mortar_shot(mortar: Unit, to: Vector2) -> void:
	_fire_flashes.append({
		"from": mortar.global_position, "to": to, "team": mortar.team, "time": elapsed_time, "is_mortar": true,
	})
	_history_fire_events.append({
		"from": mortar.global_position, "to": to, "team": mortar.team, "time": scenario_elapsed_time, "is_mortar": true,
	})
	_play_mortar_fire_sound(mortar)


func _launch_mortar_shot(mortar: Unit, target: Unit) -> void:
	mortar.mortar_rounds_remaining -= 1 # spent the instant it's fired, hit or miss — you don't get the shell back
	# See _mortar_relocation_plan's own doc comment on MORTAR_REVERSAL_
	# DIRECTION_DOT_THRESHOLD — a real fire mission between two
	# relocations means the crew's next move is a genuine, fresh
	# shoot-and-scoot decision, not indecisive backtracking, so it's
	# exempt from the "don't reverse your own last leg" discouragement
	# even if the doctrinally-correct scoot direction happens to point
	# back the way it came.
	_mortar_fired_since_relocation[mortar] = true
	var aim_point: Vector2 = _mortar_aim_point(target)
	var impact_point: Vector2 = aim_point + _mortar_dispersion_offset(mortar, target, aim_point)
	_pending_mortar_shots.append({
		"mortar": mortar,
		"target": target,
		"aim_point": aim_point,
		"impact_point": impact_point,
		"impact_time": scenario_elapsed_time + GameConfig.MORTAR_FLIGHT_TIME,
	})
	_announce_mortar_shot(mortar, aim_point)
	_seconds_since_last_shot = 0.0
	# Firing is detectable (muzzle blast/trajectory) independent of whether
	# the mortar is otherwise visually spotted — see
	# _known_friendly_mortar_position, which the enemy's counter-battery-range
	# chase (_mortar_hunt_fix_for) relies on for exactly this case.
	_last_detected_mortar_fire[mortar] = {"position": mortar.global_position, "time": scenario_elapsed_time}
	_resolve_mortar_counter_battery(mortar)


## Where the mortar aims, given what it knows about the target RIGHT NOW —
## "the anticipated enemy position, as communicated by the spotter or
## squad." ANY target currently moving with a known heading gets LED: aim
## at where it's going, not where it stands, using its current
## speed/direction extrapolated across the shell's whole flight time — this
## covers the enemy's steady road march, a unit walking a cover leg toward
## a specific point, AND a retreat's final straight dash at constant speed
## toward the safe line (BattleManager._step_retreat has a fixed, known
## heading — retreating is not "erratic," it's a determined, predictable
## line, and a mortar crew watching it for even a moment can lead it).
##
## What Unit.movement_predictable actually governs is a SEPARATE thing —
## the RESOLVE_FIRE hit-chance penalty for erratic movement (see
## CombatResolver), i.e. how much to trust that this extrapolation will
## still be right in 40 seconds. A retreating unit's heading is knowable
## right now (so it gets led) even though it might still change course, or
## juke sideways under fire (see Unit.zigzagging) — that uncertainty is
## what the accuracy penalty and MORTAR_EVASION_RADIUS model, not whether
## to attempt the lead at all.
func _mortar_aim_point(target: Unit) -> Vector2:
	if target.activity != Unit.Activity.MOVING:
		return target.global_position
	var velocity: Vector2 = _estimate_unit_velocity(target)
	if velocity == Vector2.ZERO:
		return target.global_position
	return target.global_position + velocity * GameConfig.MORTAR_FLIGHT_TIME


## A unit's current real-world velocity vector — its own move_target at its
## own move_speed if it has one, or a retreat's final, un-pathed leg at
## retreat_speed (direction fixed by team — see _step_retreat) if it's on
## that instead. Vector2.ZERO if neither applies (stationary, or between
## path waypoints with no target currently set). Shared by anything that
## needs to know where a unit is actually heading right now: _mortar_aim_
## point's own lead calculation, and the drone team's evasion check (does a
## known threat's current heading actually point toward it, not just happen
## to be nearby).
func _estimate_unit_velocity(u: Unit) -> Vector2:
	if u.has_move_target:
		var to_target: Vector2 = u.move_target - u.global_position
		if to_target.length() > 0.01:
			return to_target.normalized() * u.move_speed
		return Vector2.ZERO
	if u.state == Unit.State.RETREATING:
		var dir_x: float = -1.0 if u.team == Unit.Team.PLAYER else 1.0
		return Vector2(dir_x * u.retreat_speed, 0.0)
	return Vector2.ZERO


## How well `mortar`'s own side can currently see where rounds aimed at
## `target` are actually landing — real fire-adjustment doctrine requires
## someone watching the fall of shot, not just knowing the target exists
## (that's already covered elsewhere: a mortar can fire indirectly at a
## known-but-unseen contact, but nobody can WALK rounds onto it without
## eyes on the impact). Approximated as "can any of my own side's units
## currently see the target itself" (CombatResolver.has_live_observer) —
## the impact point sits at or near the target, so a live observer on the
## target effectively also sees the splash. Best-available quality wins:
## a drone overhead beats a spotter, which beats an ordinary unit's own
## eyes, which beats nobody at all.
func _mortar_fire_observation_quality(mortar: Unit, target: Unit) -> String:
	var allies: Array[Unit] = _ally_units_for(mortar)
	var drones: Array[Unit] = []
	var spotters: Array[Unit] = []
	for u in allies:
		if u.kind == Unit.Kind.DRONE:
			drones.append(u)
		elif u.kind == Unit.Kind.SPOTTER:
			spotters.append(u)
	if CombatResolver.has_live_observer(target, drones):
		# Between a stationary team's feed and a spotter's when the team is on the move.
		return "drone_moving" if _drone_team_on_the_move() else "drone"
	if CombatResolver.has_live_observer(target, spotters):
		return "spotter"
	if CombatResolver.has_live_observer(target, allies):
		return "squad"
	return "none"


## The real distance between a calculated aim_point and where the round
## actually lands — see GameConfig.MORTAR_DISPERSION_* for the cited
## real-world grounding (unadjusted CEP scaling with range; convergence
## toward a floor as "walked fire" gets corrected shot over shot). Sampled
## as a circular Gaussian (CEP = 1.1774 * sigma is the standard CEP-to-
## standard-deviation conversion for a circular normal distribution) rather
## than a uniform disc, so most rounds cluster well inside the CEP with a
## long tail of wider misses, matching how real dispersion actually
## behaves.
##
## Also the sole place that advances (or resets) _mortar_fire_adjustment:
## called exactly once per shot, at launch, so "how many prior rounds have
## been corrected from" only ever grows once per real round fired.
func _mortar_dispersion_offset(mortar: Unit, target: Unit, aim_point: Vector2) -> Vector2:
	var range_to_target: float = mortar.global_position.distance_to(aim_point)
	var base_cep: float = max(GameConfig.MORTAR_DISPERSION_UNADJUSTED_FLOOR, GameConfig.MORTAR_DISPERSION_CEP_FRACTION_OF_RANGE * range_to_target)

	var adjustment: Dictionary = _mortar_fire_adjustment.get(mortar, {})
	if adjustment.get("target") != target:
		adjustment = {"target": target, "shots": 0}
		if weather != null:
			# The crew's wind correction for this whole fire mission (see Weather.crew_wind_estimate_px).
			adjustment["wind_assumed"] = weather.crew_wind_estimate_px(GameConfig.MORTAR_FLIGHT_TIME)
	var shots_corrected_from: int = adjustment.get("shots", 0)

	var quality: String = _mortar_fire_observation_quality(mortar, target)
	var decay: float
	var floor_dist: float
	match quality:
		"drone":
			decay = GameConfig.MORTAR_DISPERSION_DRONE_DECAY
			floor_dist = GameConfig.MORTAR_DISPERSION_DRONE_FLOOR
		"drone_moving":
			decay = GameConfig.MORTAR_DISPERSION_DRONE_MOVING_DECAY
			floor_dist = GameConfig.MORTAR_DISPERSION_DRONE_MOVING_FLOOR
		"spotter":
			decay = GameConfig.MORTAR_DISPERSION_SPOTTER_DECAY
			floor_dist = GameConfig.MORTAR_DISPERSION_SPOTTER_FLOOR
		"squad":
			decay = GameConfig.MORTAR_DISPERSION_SQUAD_DECAY
			floor_dist = GameConfig.MORTAR_DISPERSION_SQUAD_FLOOR
		_: # "none" — unobserved/predicted fire never converges, ever
			decay = 1.0
			floor_dist = base_cep

	if quality != "none":
		adjustment.shots = shots_corrected_from + 1
	_mortar_fire_adjustment[mortar] = adjustment

	var effective_floor: float = min(floor_dist, base_cep) # a converged shot is never worse than a fresh unadjusted one
	var cep: float = effective_floor + (base_cep - effective_floor) * pow(decay, shots_corrected_from)
	var sigma: float = cep / 1.1774
	var wind_bias := Vector2.ZERO
	if weather != null:
		# What the crew's correction leaves uncorrected — its estimate error, plus
		# any change in the wind since it was made — fading with the same
		# observed-fire convergence that tightens the scatter above (fastest under
		# a drone, never under unobserved fire).
		var drift_now: Vector2 = weather.mortar_wind_drift_px(GameConfig.MORTAR_FLIGHT_TIME)
		wind_bias = (drift_now - adjustment.get("wind_assumed", drift_now)) * pow(decay, shots_corrected_from)
	return Vector2(randfn(0.0, sigma), randfn(0.0, sigma)) + wind_bias


static func _empty_civilian_tally() -> Dictionary:
	return {
		"player": {"killed": 0, "heavily_wounded": 0, "walking_wounded": 0},
		"enemy": {"killed": 0, "heavily_wounded": 0, "walking_wounded": 0},
	}


## A shell has landed at `point`: any civilians it killed or wounded are added to the tally of the side that fired it (see
## GameConfig.civilian_casualties_at). Every landed shell is assessed, whatever it did to its target.
func _assess_civilian_casualties(point: Vector2, firing_team: Unit.Team) -> void:
	var hurt: Dictionary = GameConfig.civilian_casualties_at(point)
	var tally: Dictionary = civilian_casualties_by_shell["player" if firing_team == Unit.Team.PLAYER else "enemy"]
	for key in hurt:
		tally[key] += hurt[key]


## Resolves any mortar shots whose flight time has elapsed. A target that's
## since been destroyed or reached safety leaves nothing for the shell to
## hit. Otherwise, the shell lands at its impact_point regardless — set at
## launch time (_mortar_dispersion_offset), already accounting for both a
## bad lead AND real ballistic scatter — if the target has since moved (or
## the shot simply scattered) beyond MORTAR_EVASION_RADIUS from that spot,
## the shot misses outright, no roll needed; a target still nearby gets the
## normal CombatResolver roll (using ITS CURRENT state at impact — cover,
## movement — same as any other hit resolution). Enemy-alert and hit-
## consequence logging happen here, at impact, not at launch — the target
## doesn't know it's been fired on until the shell actually arrives.
func _resolve_pending_mortar_shots() -> void:
	var still_pending: Array[Dictionary] = []
	for shot in _pending_mortar_shots:
		if scenario_elapsed_time < shot.impact_time:
			still_pending.append(shot)
			continue
		# The round physically lands here regardless of what happens to
		# the target in the meantime (fled, died, was never real to begin
		# with) — a real shell doesn't un-fire itself, so the visual goes
		# up unconditionally, before any of the below can skip the rest
		# of this resolution.
		_mortar_impacts.append({"position": shot.impact_point, "time": elapsed_time})
		_assess_civilian_casualties(shot.impact_point, shot.mortar.team)
		_suppress_from_blast(shot.impact_point)
		# Checked on the raw Variant, BEFORE assigning to a typed `Unit`
		# variable — assigning an already-freed instance to a typed var is
		# itself what throws "Trying to assign invalid previously freed
		# instance," so is_instance_valid has to run first, not after.
		if not is_instance_valid(shot.target):
			continue # the target (a drone, almost certainly — see BattleManager's queue_free calls) has since landed/been freed; nothing left there to hit
		var target: Unit = shot.target
		if target.state == Unit.State.DESTROYED or target.state == Unit.State.WITHDRAWN or target.state == Unit.State.SURRENDERED:
			continue # nothing left there to hit

		if target.state == Unit.State.RETREATING:
			target.zigzagging = true # once you know you're under a barrage, keep juking — see Unit.zigzagging

		var drift: float = target.global_position.distance_to(shot.impact_point)
		if drift > GameConfig.MORTAR_EVASION_RADIUS:
			combat_log.log_mortar_shot_evaded(shot.mortar, target)
			continue

		if target.team == Unit.Team.ENEMY and target.kind == Unit.Kind.SQUAD and not enemy_alerted:
			enemy_alerted = true
			_alert_enemy_squads()

		_resolve_fire_and_check_bunching(shot.mortar, target, shot.impact_point)
	_pending_mortar_shots = still_pending


## Word travels fast: break every still-marching enemy squad off its road
## march and send it toward cover — but NOT via the plain, purely-proximity
## "nearest cover point" reflex (Unit.seek_cover) every other bolt-for-cover
## reaction in this game uses. All of them break at once here, which used to
## be exactly the scenario most likely to pile several squads into the same
## nearest patch of cover: several squads that are all still fairly close
## together (same road march) each independently reaching for whichever
## patch of cover is nearest THEM specifically tends to be the same one or
## two patches nearest the whole group, not a real spread — the direct cause
## of squads visibly bunching up (in the village or anywhere else) the
## moment contact was first made, cover goal fully met but at the total
## expense of ever surrounding anything or pressing toward the mortar.
##
## Routed through _next_advance_point instead — the same multi-goal
## weighted scoring the ongoing advance-by-bounds already uses (cover,
## concealment/exposure, and spreading out around the known friendly
## cluster or the objective itself — see _score_advance_candidate) — so
## this first break for cover is already weighing "surround" and "hunt the
## mortar" against "get to cover," not just solving for cover alone and
## leaving the other two goals to some later tick that may never come once
## a squad's already settled in.
func _alert_enemy_squads() -> void:
	var claimed_bearings: Array[float] = []
	var pivot: Vector2 = _encirclement_pivot()
	for u in enemy_units:
		if u.kind != Unit.Kind.SQUAD or u.state != Unit.State.ACTIVE or u.sought_cover:
			continue
		u.sought_cover = true
		u.sought_cover_logged = true # logged once, right here, not via _log_hit_consequence
		var target: Vector2 = _next_advance_point(u, INF, claimed_bearings)
		if target != u.global_position:
			u.move_target = target
			u.last_order_reason = "First contact: leave the march route and advance using cover and spacing."
			u.has_move_target = true
			u.move_queue.clear()
			u.move_speed = GameConfig.REPOSITION_SPEED
			u.movement_predictable = false
			if not is_inf(pivot.x):
				claimed_bearings.append(rad_to_deg((target - pivot).angle()))
		combat_log.log_seeking_cover(u)
	# (No banner for the enemy being alerted: the player cannot see that, only squads it sees seeking cover.)


## An enemy squad that's broken off to cover doesn't just sit there for the
## rest of the battle — this is a real assault, not a one-shot road march.
## Once it's idle (arrived, not already moving) and has nothing worth
## shooting at right now (_pick_target comes up empty — plenty of range/LOS
## for the mortar and squad-vs-squad checks to still say no), it resumes
## closing on the village in a bounded rush (ENEMY_ADVANCE_RUSH_DISTANCE),
## then stops again to reassess — advance-by-bounds, not one long blind
## sprint. Without this, a squad that breaks for cover once — now easy,
## with cover scattered across the whole map rather than concentrated near
## the village — could end up stalled out of engagement range permanently,
## with nothing on either side able to close the distance again: a genuine
## dead end that the stagnation timeout would eventually (correctly) end
## the battle over, but only after the assault had quietly stopped being a
## real assault.
##
## Only applies to squads that have already broken from the initial road
## march (sought_cover) — one still on that scripted path is handled by its
## own multi-waypoint set_path already.
##
## Real, deliberate force allocation for the mortar hunt, not "every
## eligible squad chases at once" — a direct live report: ten enemy squads
## all converged on the mortar simultaneously, running past three friendly
## squads in their path, when "the enemy might send 2-3 to chase the
## mortar. But the rest would fight the friendly squads." An unarmed-for-
## close-defense mortar crew doesn't need more than a couple of squads to
## run it down — piling on more than that is combat power wasted on a
## soft target instead of the numerically superior threat actually in
## front of them. `_mortar_hunt_assignments` computes the cap once per
## tick for the whole side; only the assigned squads actually execute the
## hunt below, everyone else falls through to the ordinary division-of-
## labor/advance-by-bounds logic exactly as if they were never in range.
func _mortar_hunt_assignments() -> Dictionary:
	var cap: int = _mortar_hunt_cap()
	var eligible: Array[Unit] = []
	for u in enemy_units:
		if u.kind != Unit.Kind.SQUAD or u.state != Unit.State.ACTIVE or not u.sought_cover:
			continue
		if _chasing_mortar_in_hot_pursuit(u):
			eligible.append(u)
	var assigned: Dictionary = {}
	if eligible.size() <= cap:
		for u in eligible:
			assigned[u] = true
		return assigned
	# More eligible squads than the cap allows — the CLOSEST ones actually
	# stand a chance of catching it; the rest are better used elsewhere.
	var mortar_pos: Vector2 = _known_friendly_mortar_position()
	eligible.sort_custom(func(a, b): return a.global_position.distance_to(mortar_pos) < b.global_position.distance_to(mortar_pos))
	for i in cap:
		assigned[eligible[i]] = true
	return assigned


## How many enemy squads may run down the friendly mortar at once right now:
## the fixed GameConfig.MORTAR_HUNT_SQUAD_CAP, unless the enemy outnumbers the
## friendly squads still in action by more than GameConfig.MORTAR_HUNT_
## SUPERIORITY_RATIO to 1 — then every squad beyond that ratio is spare and may
## chase too. With no friendly squad in action, that is all of them.
func _mortar_hunt_cap() -> int:
	var enemy_squads := 0
	for u in enemy_units:
		if u.kind == Unit.Kind.SQUAD and u.state == Unit.State.ACTIVE:
			enemy_squads += 1
	var needed_against_squads: int = ceili(GameConfig.MORTAR_HUNT_SUPERIORITY_RATIO * float(_friendly_squads_in_action()))
	return maxi(GameConfig.MORTAR_HUNT_SQUAD_CAP, enemy_squads - needed_against_squads)


## Friendly squads still in the fight: ACTIVE ones. A squad that is retreating,
## withdrawn, destroyed or captured is not "in action" (it may still be a
## target of opportunity, but it is not what the enemy has to be held back for).
func _friendly_squads_in_action() -> int:
	var n := 0
	for u in player_units:
		if u.kind == Unit.Kind.SQUAD and u.state == Unit.State.ACTIVE:
			n += 1
	return n


## True once an enemy squad has walked its whole scripted march (Unit.set_path): nothing left to
## walk to and nothing queued. A squad that has not yet broken from the march and is in this state
## has simply arrived.
func _march_route_is_finished(u: Unit) -> bool:
	return not u.has_move_target and u.move_queue.is_empty()


func _update_enemy_squad_advance() -> void:
	_update_enemy_attack_stance()
	var hunt_assignments := _mortar_hunt_assignments()
	var spotter_hunter := _spotter_hunt_candidate()
	for u in enemy_units:
		if u.kind != Unit.Kind.SQUAD or u.state != Unit.State.ACTIVE:
			continue
		if u == spotter_hunter:
			# Checked here, BEFORE the still-marching gate just below, and unconditionally breaks the
			# squad off its scripted route exactly like _alert_enemy_squads already does for real contact —
			# direct user report, a second time, of a squad marching straight past a known, dealable
			# spotter without ever reacting: the still-marching gate used to skip this whole tier outright,
			# so nothing here ever got a chance to redirect it. _spotter_hunt_candidate's own filtering
			# (risk holds, already engaging a real squad, range) already ran before this squad could ever
			# be chosen, so nothing further needs rechecking here.
			if not u.sought_cover:
				u.sought_cover = true
				u.sought_cover_logged = true
			_chase_spotter_directly(u)
			continue
		if not u.sought_cover:
			if not _march_route_is_finished(u):
				continue # still on the scripted road march
			# Direct user report: "the enemy is not advancing, for no good reason that I can see."
			# Traced to the live battle's own snapshot: 14 enemy squads sat in a line at the end of the
			# road (its last waypoint) with no move order, all reading "Following the assigned march
			# route", 1400 m from the friendly squads, which had fallen back. This tier only ran for a
			# squad that had broken from the march, and the ONLY thing that breaks a squad from it is
			# contact (fire given or taken, see _alert_enemy_squads / Unit.take_hit) — so a march that
			# finished with nobody in range was a dead end: nothing ever ordered the assault on. A march
			# that has run its course is the same decision, made without a shot: press on toward the
			# objective by bounds, exactly as a squad that broke from the road does.
			u.sought_cover = true
			u.sought_cover_logged = true # nothing to log: it did not break for cover, it finished its march
			u.last_order_reason = "Reached the end of the march route without contact: press on toward the objective."
		if _risk_holds.has(u):
			continue # an explicit risk-avoidance hold outranks everything below
		if u.pinned:
			u.last_order_reason = "Pinned down by fire: not starting a new advance until it eases."
			continue
		# Direct user correction: "Mortar should be a primary target for
		# the enemy forces. They should chase it when they get close. In
		# the latest battle, they were dancing back and forth, but not
		# really chasing." Traced directly: _next_advance_point's own
		# bent-angle, cover/encirclement-scored candidates and its
		# ENEMY_SURROUND_STANDOFF_RADIUS stop distance are the right model
		# for closing on a STATIC objective (the village) under fire, not
		# for running down a MOVING, actively evading one — each fresh
		# bound is aimed at wherever the mortar happened to be when this
		# tier last got a turn (only once has_move_target clears), so a
		# mortar that keeps relocating between reassessments produces
		# exactly the reported "dancing": a short bent leg toward a
		# already-stale point, arrive, reassess, repeat, with no
		# guarantee of ever converging. Checked BEFORE the has_move_target
		# gate below (bypassing it entirely) so a squad already close on a
		# known, active mortar keeps re-aiming at its CURRENT position
		# every tick — the same "re-aims every tick" idiom already
		# established and accepted for actual mortar-hunts-mortar
		# pursuit — instead of committing to a single bent leg and only
		# reconsidering once it finishes.
		#
		# Checked BEFORE the "something to shoot at right now" bail-out
		# below too — a second, live-reported bug: "once it was adjacent,
		# the enemy squad let the mortar get away... unless the enemy squad
		# is under some sort of pressure, which it was not." Root cause:
		# `_pick_target(u, player_units) != null` used to short-circuit
		# this whole tier the instant the squad had ANY valid shot —
		# including a shot at some other, unrelated player unit merely
		# passing through LOS, or a marginal shot at the mortar itself
		# right as it started to displace — freezing the squad in place
		# for as long as that shot kept re-qualifying, tick after tick,
		# while an unpursued mortar simply walked out of contact.
		# _chase_mortar_directly already stops advancing and correctly
		# yields to ordinary _pick_target-driven fighting the instant the
		# mortar itself is within real engagement range, so reordering
		# these two checks changes nothing once genuinely in range — it
		# only stops the squad from settling for a lesser target, or a
		# fleeting shot, while a known, high-value, actively-fleeing
		# mortar is still there to be run down.
		#
		# The target below is now named directly in last_order_reason
		# rather than left implicit — a direct live follow-up right after
		# this fix landed: "shooting at the mortar might make sense. But
		# I'm not sure it was." There was no way to check, before or after
		# the fact: general_unit_debug_snapshot() already exposes
		# last_order_reason for every unit, but this branch never wrote
		# one, so a squad sitting still here showed nothing beyond
		# whatever stale reason its last real move order left behind.
		# Reuses the exact target this same call already resolves — no
		# second _pick_target call, so this adds no new risk from its own
		# internal randomness (the baseline squad path's uniform choice
		# among candidates) disagreeing with whatever _tick_fire itself
		# acts on this same tick.
		# Division of labor, added after a direct live report: ten enemy
		# squads all converging on the mortar in hot pursuit, running past
		# friendly squads actively in their path, rather than some of them
		# peeling off to actually fight what was right in front of them —
		# "it would be reasonable to have division of labor, with some
		# enemy squads chasing the mortar and others fighting against the
		# friendly squads." Real infantry doesn't turn its back on a live
		# firefight it's already IN to run past the enemy toward a
		# different objective — that's what the hot-pursuit reordering
		# above (fixing the OPPOSITE bug, a squad ignoring the mortar for
		# any stray shot) went too far in the other direction on. The
		# distinction that actually matters: a real, currently-engageable
		# PLAYER SQUAD specifically (an armed threat that can shoot back)
		# is genuine contact worth finishing, not just "something,
		# anything, technically shootable" the way the previous fix's own
		# bug treated an incidental spotter/other unit. Checked before hot
		# pursuit, using the SAME _pick_target call hot pursuit's own
		# fallback below would otherwise make separately — this is what
		# produces the actual division of labor: whichever squads happen
		# to have a real opposing squad in their own range/LOS stay and
		# fight it, while squads with a clear path (no friendly squad
		# actually contesting them specifically) press on toward the
		# mortar — with no need for any new cross-squad coordination.
		var shootable: Unit = _pick_target(u, player_units)
		if shootable != null and shootable.kind == Unit.Kind.SQUAD:
			u.last_order_reason = "Staying to fight %s (in range and line of sight) instead of continuing to close." % shootable.display_name()
			continue

		if hunt_assignments.has(u):
			_chase_mortar_directly(u)
			continue
		if shootable != null:
			u.last_order_reason = "Staying to fight %s (in range and line of sight) instead of continuing to close." % shootable.display_name()
			continue # something to shoot at right now, and not mid-chase on a known mortar — stay and fight
		if u.has_move_target:
			continue
		var consolidating: bool = not _friendly_mortar_is_active() and not _enemy_attack_stance() and not _known_friendly_squad_positions().is_empty()
		var rush_target := _consolidation_step(u) if consolidating else _next_advance_point(u)
		if rush_target == u.global_position:
			if consolidating:
				u.last_order_reason = "Gathered: not enough of an advantage to attack, so waiting clear of the friendly squads."
			continue
		u.last_order_reason = "Falling back to the gathering point, clear of the friendly squads." if consolidating else "No target available: advance another bound toward the current objective."
		u.move_target = rush_target
		u.has_move_target = true
		u.move_queue.clear()
		u.move_speed = GameConfig.ENEMY_ADVANCE_SPEED
		u.movement_predictable = false # a deliberate rush, not the road-bound march


## True once `u` is close enough to a known, ACTIVE friendly mortar that
## running it down directly outranks the ordinary measured, bent-angle
## advance-by-bounds toward it as an objective. Same range this codebase
## already uses elsewhere for "close enough to react to at all"
## (SQUAD_DANGER_RANGE — see _retreat_avoidance_offset's own use of it),
## reused here rather than inventing a new number: a squad this close to
## a fleeing high-value target should already be actively running it
## down, not still treating it as a distant objective to bound toward.
## Excludes a squad still executing its own wide flanking route
## (flanking_route_active) — see _enemy_advance_objective's own doc
## comment: it hasn't actually arrived at the point where the mortar
## becomes its real objective yet, so it isn't "in the chase" at all.
func _chasing_mortar_in_hot_pursuit(u: Unit) -> bool:
	if u.flanking_route_active:
		return false
	if not _friendly_mortar_is_active():
		return false
	var mortar_pos: Vector2 = _known_friendly_mortar_position()
	if is_inf(mortar_pos.x):
		return false
	return u.global_position.distance_to(mortar_pos) <= GameConfig.SQUAD_DANGER_RANGE


## The actual "run it down" step: aims directly at the mortar's own
## CURRENT known position every tick (no bent angle, no cover/
## encirclement scoring, no ENEMY_SURROUND_STANDOFF_RADIUS stop distance
## — those all serve a measured siege of a static objective, not a hot
## pursuit) and keeps re-aiming as it moves. Stops advancing once within
## real engagement range (SQUAD_ENGAGEMENT_RANGE) — close enough to
## actually fight it, at which point _pick_target's own normal targeting
## takes over; no reason to walk any closer than that.
func _chase_mortar_directly(u: Unit) -> void:
	var mortar_pos: Vector2 = _known_friendly_mortar_position()
	if u.global_position.distance_to(mortar_pos) <= GameConfig.SQUAD_ENGAGEMENT_RANGE:
		u.has_move_target = false
		return
	if u.has_move_target and u.move_target.distance_to(mortar_pos) < Unit.MOVE_ARRIVE_RADIUS:
		return # already aimed at essentially the right spot — no need to reissue the identical order every tick
	u.last_order_reason = "Closing directly on a known enemy mortar — hot pursuit."
	u.move_target = mortar_pos
	u.has_move_target = true
	u.move_queue.clear()
	u.move_speed = GameConfig.ENEMY_ADVANCE_SPEED
	u.movement_predictable = false


## Cheap, RNG-free approximation of "_pick_target(u, player_units) would return a real, armed SQUAD" —
## used only to rank spotter-hunt candidates (see _spotter_hunt_candidate) BEFORE the real per-squad
## _pick_target call further down in _update_enemy_squad_advance runs. Deliberately not a second call to
## the real thing: _pick_target's own baseline path makes a random uniform pick among multiple qualifying
## candidates, so calling it twice per squad per tick would silently double-draw that randomness for every
## squad, every tick — a real, previously-diagnosed class of bug this session (see the RNG-sequence-drift
## regression in test_mortar_evasion_balance.gd, docs/designs/tactical-commander-doctrine.md's 2026-09-29
## entry). Mirrors _pick_target's own SQUAD-kind gate exactly (SQUAD_ENGAGEMENT_RANGE + has_direct_los) —
## the DRONE/is_targetable exclusions _pick_target also applies are irrelevant against a live player SQUAD.
func _squad_already_engaging_a_real_squad(u: Unit) -> bool:
	for p in player_units:
		if p.kind != Unit.Kind.SQUAD or p.state != Unit.State.ACTIVE:
			continue
		if u.global_position.distance_to(p.global_position) <= GameConfig.SQUAD_ENGAGEMENT_RANGE and GameConfig.has_direct_los(u.global_position, p.global_position):
			return true
	return false


## The single enemy squad — never more than one — that should break off to deal with a known friendly
## spotter this tick, or null if none should. Direct user ruling, given after a live report that an enemy
## mortar was shelling a known spotter while a nearby enemy squad did nothing about it: "If the spotter's
## position is known, near enemy squads, and easy to reach, ONE nearby squad should act to deal with it.
## However, if the enemy sees the spotter from far off, or if they are engaging friendly squads, they might
## choose not to." This supersedes the earlier, broader "any squad, however far, treats a known spotter as
## its unconditional #1 objective" design (see this same file's revision history) — the user's own framing
## here is explicitly proximity- and availability-gated, not a blanket priority swap.
##
## "Near enough... easy to reach": GameConfig.SQUAD_DANGER_RANGE (1200m) — the same "close enough to react
## to at all" scale _chasing_mortar_in_hot_pursuit already reuses for a known mortar, rather than inventing
## a new number. "Engaging friendly squads": _squad_already_engaging_a_real_squad excludes a candidate
## outright, so the caller's own real _pick_target-driven "stay and fight" branch — checked first, before
## this is ever consulted — always wins for whichever squad it actually applies to.
##
## Direct user report, a second time — "The squad just kept moving": a squad still executing its scripted
## road march (not u.sought_cover) used to be excluded from candidacy here, and _update_enemy_squad_
## advance's own loop skips a still-marching squad entirely before it ever reaches this tier at all — so a
## squad marching straight past a known, dealable spotter never even considered it, exactly like the report
## describes. Not required here any more; the caller breaks the chosen squad off its march the same way
## _alert_enemy_squads already does for real contact (see its own call site for that bookkeeping).
func _spotter_hunt_candidate() -> Unit:
	var candidates: Array[Unit] = []
	for u in enemy_units:
		if u.kind != Unit.Kind.SQUAD or u.state != Unit.State.ACTIVE:
			continue
		if _risk_holds.has(u) or _squad_already_engaging_a_real_squad(u):
			continue
		var spotter_pos: Vector2 = _known_friendly_spotter_position(u)
		if is_inf(spotter_pos.x) or u.global_position.distance_to(spotter_pos) > GameConfig.SQUAD_DANGER_RANGE:
			continue
		candidates.append(u)
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(a, b): return a.global_position.distance_to(_known_friendly_spotter_position(a)) < b.global_position.distance_to(_known_friendly_spotter_position(b)))
	return candidates[0]


## The actual "deal with it" step for whichever squad _spotter_hunt_candidate names — an exact mirror of
## _chase_mortar_directly (aim straight at the current known position, no bent-angle/cover scoring, stop
## once within real engagement range and hand off to ordinary _pick_target-driven fighting).
func _chase_spotter_directly(u: Unit) -> void:
	var spotter_pos: Vector2 = _known_friendly_spotter_position(u)
	if u.global_position.distance_to(spotter_pos) <= GameConfig.SQUAD_ENGAGEMENT_RANGE:
		u.has_move_target = false
		return
	if u.has_move_target and u.move_target.distance_to(spotter_pos) < Unit.MOVE_ARRIVE_RADIUS:
		return # already aimed at essentially the right spot — no need to reissue the identical order every tick
	u.last_order_reason = "Closing directly on a known friendly spotter."
	u.move_target = spotter_pos
	u.has_move_target = true
	u.move_queue.clear()
	u.move_speed = GameConfig.ENEMY_ADVANCE_SPEED
	u.movement_predictable = false


## A bounded step toward the current objective from `u`'s current position
## — the next leg of an advance-by-rushes, not the whole remaining distance
## in one go. Not a blind straight line either: several candidate
## directions bending off the direct line (GameConfig.ENEMY_ADVANCE_ANGLES_
## DEG) are each scored for cover/concealment/exposure/encirclement
## (_score_advance_candidate) and picked via a weighted-random roll
## (_weighted_advance_point_pick) — a real squad usually avoids a straight
## dash across open ground, or into a defender's engagement range, in favor
## of terrain or a wider bend around whatever it already knows is watching
## or where the rest of its own side already stands, but "usually" isn't
## "always": the literal straight line stays a reachable, if lower-weight,
## candidate throughout.
##
## Stops advancing once within GameConfig.ENEMY_SURROUND_STANDOFF_RADIUS of
## the objective rather than trying to walk onto its exact position —
## several squads each stopping on that ring, from whatever bearing their
## own approach happened to settle on, is what actually surrounds the
## objective instead of all of them piling onto the same spot.
##
## `max_step` overrides the normal bounded ENEMY_ADVANCE_RUSH_DISTANCE —
## used by _alert_enemy_squads to let the initial break-for-cover scatter
## cover most/all of the remaining distance to the standoff ring in one
## decisive move (`INF`), rather than the slow, tick-by-tick reassessment
## the ordinary advance-by-bounds uses once already under way. Without that,
## several squads that all come under fire at once (and may well find a
## target and stop moving again within a tick or two) would barely separate
## at all before locking into whatever tight starting cluster they began
## in — the direct cause of squads visibly bunching up the moment contact
## was first made.
##
## `extra_bearings_deg` — additional already-claimed bearings (relative to
## the SAME friendly_center this call resolves to; see _alert_enemy_squads)
## folded into the encirclement scoring on top of every other currently
## ACTIVE enemy squad's own actual position. Needed because several squads
## alerted in the same event are processed one at a time, in the same tick,
## before any of them has actually moved (see _tick_movement) — without
## this, each one's own "where do my allies already stand" check would only
## ever see everyone's stale, still-bunched starting positions, never the
## bearings its allies-in-this-same-event just claimed a moment ago in this
## very loop.
func _next_advance_point(u: Unit, max_step: float = GameConfig.ENEMY_ADVANCE_RUSH_DISTANCE, extra_bearings_deg: Array[float] = []) -> Vector2:
	var objective: Vector2 = _enemy_advance_objective(u)
	var to_objective: Vector2 = objective - u.global_position
	var distance_to_objective: float = to_objective.length()
	if distance_to_objective < GameConfig.ENEMY_SURROUND_STANDOFF_RADIUS:
		return u.global_position # already close enough — hold this bearing rather than close in further
	# Capped against the STANDOFF distance too, not just the full remaining
	# distance — otherwise a squad already within one rush of the objective
	# would overshoot clean through the standoff ring in a single bound,
	# defeating the whole point of stopping there instead of at the literal
	# objective.
	var rush: float = min(distance_to_objective - GameConfig.ENEMY_SURROUND_STANDOFF_RADIUS, max_step)
	var known_player_positions := _known_enemy_positions(Unit.Team.ENEMY)
	# Prefer spreading out around the actual known friendly cluster — real
	# encirclement, once there's an actual contact to surround — but with
	# nothing sighted yet, spreading around the objective itself instead is
	# what keeps several squads converging on the same mortar/village from
	# stacking on the exact same bearing to it in the first place.
	var friendly_center: Vector2 = _known_position_centroid(known_player_positions)
	if is_inf(friendly_center.x):
		friendly_center = objective
	var other_bearings: Array[float] = extra_bearings_deg.duplicate()
	for other in enemy_units:
		if other == u or other.kind != Unit.Kind.SQUAD or other.state != Unit.State.ACTIVE:
			continue
		other_bearings.append(rad_to_deg((other.global_position - friendly_center).angle()))
	# Clamped to the map's real operating area — see GameConfig.clamp_to_
	# operating_area's own doc comment. `rush` is UNCAPPED (max_step=INF)
	# for a squad's very first alert-triggered break from the march (see
	# _alert_enemy_squads), which can legitimately be the squad's entire
	# remaining distance to a far-off objective (a flanking route's own
	# waypoint deep in the west flank, hundreds of meters off). Rotating
	# that large a radius across the full spread of ENEMY_ADVANCE_ANGLES_
	# DEG can easily land a candidate well outside the map — confirmed
	# directly: an off-map y (negative, no such place exists) got weighted-
	# picked and sent a squad walking toward a point that was never on the
	# battlefield at all.
	var candidates: Array[Vector2] = []
	for angle_deg in GameConfig.ENEMY_ADVANCE_ANGLES_DEG:
		candidates.append(GameConfig.clamp_to_operating_area(u.global_position + to_objective.normalized().rotated(deg_to_rad(angle_deg)) * rush))
	# Direct user report, live: "enemy squads 2 and 6 are not attacking the friendly squads. I see no rational
	# explanation." Far from the objective, cover/concealment/encirclement buy nothing (no fight to use cover
	# in, nobody to hide from or surround), yet they outweighed the straight line, so squads wandered sideways
	# ~1200 m out. See _advance_tactical_pressure. The alert-time scatter (max_step INF) happens at contact and
	# keeps full weight.
	var pressure: float = 1.0 if is_inf(max_step) else _advance_tactical_pressure(distance_to_objective)
	return _weighted_advance_point_pick(candidates, GameConfig.ENEMY_ADVANCE_ANGLES_DEG, known_player_positions, friendly_center, other_bearings, pressure)


## How much the fight-related terms of an advance bound's scoring (cover, concealment, encirclement) count for
## a squad `distance` from its objective: nothing beyond GameConfig.ENEMY_ADVANCE_TACTICAL_RANGE (there is no
## fight yet, so the squad just closes the distance), everything at the standoff ring, a straight ramp between.
func _advance_tactical_pressure(distance: float) -> float:
	var ring: float = GameConfig.ENEMY_SURROUND_STANDOFF_RADIUS
	return clampf((GameConfig.ENEMY_ADVANCE_TACTICAL_RANGE - distance) / (GameConfig.ENEMY_ADVANCE_TACTICAL_RANGE - ring), 0.0, 1.0)


## The pivot _next_advance_point uses for its own encirclement scoring —
## the known friendly cluster's centroid once there's an actual contact, or
## the current advance objective itself before then. Exposed separately so
## _alert_enemy_squads can convert a chosen target back into a bearing
## around the SAME pivot _next_advance_point itself used to pick it.
func _encirclement_pivot() -> Vector2:
	var pivot: Vector2 = _known_position_centroid(_known_enemy_positions(Unit.Team.ENEMY))
	if is_inf(pivot.x):
		pivot = _enemy_advance_objective()
	return pivot


## The centroid of `positions`, or Vector2.INF if there are none — used to
## judge a candidate's bearing "around" the known friendly cluster for
## encirclement scoring, same "nothing to actually be dangerous to/around"
## neutral-when-empty convention used elsewhere in this file.
func _known_position_centroid(positions: Array[Vector2]) -> Vector2:
	if positions.is_empty():
		return Vector2.INF
	var sum := Vector2.ZERO
	for p in positions:
		sum += p
	return sum / positions.size()


## The minimum absolute angular distance between two bearings in degrees,
## correctly wrapped (e.g. 350° and 10° are 20° apart, not 340°) — always in
## [0, 180].
func _angle_diff(a_deg: float, b_deg: float) -> float:
	var d: float = fmod(abs(a_deg - b_deg), 360.0)
	return min(d, 360.0 - d)


## The enemy's current objective for advance-by-bounds: the friendly
## mortar's own current position, if it's genuinely ACTIVE and the enemy
## actually has a fix on it (see _known_friendly_mortar_position) — "in
## particular in order to reach the mortar." A stale/expired or nonexistent
## fix, or a mortar that's already destroyed/withdrawn/retreating, isn't a
## real objective to route toward; the enemy falls back to the village
## itself — "an advantageous battle for the village" instead of chasing a
## gun that's no longer a target worth flanking for.
##
## `u` (optional — omitted by _encirclement_pivot, which needs a shared
## per-batch reference point rather than any one squad's own route) lets a
## squad with flanking_route_active set (see GameConfig.ENEMY_FLANK_CHANCE)
## route through GameConfig.CURRENT_MAP.enemy.flank_waypoint_x first — a wide swing
## through the west flank — before falling through to the normal mortar/
## village objective once it arrives, now approaching from the west
## instead of head-on. Every existing candidate/scoring mechanism in
## _next_advance_point is completely objective-agnostic, so this is the
## only change needed to give a flanking squad a genuine envelopment route.
func _enemy_advance_objective(u: Unit = null) -> Vector2:
	if u != null and u.flanking_route_active:
		var waypoint := Vector2(GameConfig.CURRENT_MAP.enemy.flank_waypoint_x, u.flank_waypoint_y)
		if u.global_position.distance_to(waypoint) > GameConfig.CURRENT_MAP.enemy.flank_waypoint_arrival_radius:
			return waypoint
		u.flanking_route_active = false # arrived — falls through to the normal objective from here on, permanently
	var mortar_pos := _known_friendly_mortar_position()
	if not is_inf(mortar_pos.x) and _friendly_mortar_is_active():
		return mortar_pos
	# Direct user report from a live battle: "With no friendly squads left in
	# action, the enemy squads should definitely be hunting our mortar. In the
	# current battle, they are not." The fix above expires after
	# MORTAR_FIRE_DETECTION_EXPIRY, so a mortar that had gone quiet (out of
	# ammunition) left the enemy with no objective but the village — where its
	# squads already were — and they sat there. With nothing else in the field to
	# fight, a real force goes and looks where the gun was last known to be (the
	# same probing advance _known_enemy_mortar_lead already gives the player's own
	# side): the freshest of where it was last seen or last heard firing, no
	# expiry. Only with no friendly squad in action: while there is one, the
	# assault's objective stays the village as before.
	if _friendly_mortar_is_active() and _friendly_squads_in_action() == 0:
		var last_known := _last_known_friendly_mortar_position()
		if not is_inf(last_known.x):
			return last_known
	# Direct user report: "At this point, the enemy has chased our mortar off of the map. They now know
	# the approximate location of our squads. With no more mortar for our side, I would expect them to
	# attack our squads." (The live battle: three enemy squads stood at the west edge of the map, where
	# the mortar had fled, "advancing" on that edge, while our squads were 1300 m behind them and known.)
	# With no friendly mortar left in action, our squads are what is left to fight, and the enemy squads
	# go for the ones they know of, by where they were last seen. While the mortar is in action it stays
	# the objective, as before — an active mortar (even one with no concrete fix on it yet, the two tiers
	# just above) still means "the crew is still out there doing its job," which outranks both of the
	# checks below the same way, not just the squad one.
	if not _friendly_mortar_is_active():
		# ... but attacking a known SQUAD only with a real numerical advantage ("I am realizing that's not
		# true if the enemy squads don't think they have a significant numerical advantage. If numbers are
		# less than 2:1 in their favor, it would be reasonable for them to consolidate somewhere on the
		# map, avoiding the friendly squads, and allowing a stalemate to happen."): see _enemy_attack_
		# stance. Without it they gather at the consolidation point (_enemy_consolidation_point).
		var squad_pos: Vector2 = _known_friendly_squad_objective(u)
		if not is_inf(squad_pos.x):
			if _enemy_attack_stance():
				return squad_pos
			return _enemy_consolidation_point()
	# Direct user request: "Yes, push West" — when asked whether squads that have closed on the
	# village (300 m out, GameConfig.ENEMY_SURROUND_STANDOFF_RADIUS) with the friendly force fallen back
	# and unseen should then go looking for it, rather than stop there for good. The village is only
	# the first objective: a squad that has reached it (a latch, like flanking_route_active's) goes on
	# west, on its own line, toward the defenders' side of the map (GameConfig.PLAYER_SAFE_X, the line
	# they fall back to), bound by bound, until something is seen — after which the tiers above and
	# in _update_enemy_squad_advance (a mortar fix, a shot, contact) take over as they always do.
	var village: Vector2 = GameConfig.CURRENT_MAP.village_center
	if u != null:
		if not u.village_reached and u.global_position.distance_to(village) <= GameConfig.ENEMY_SURROUND_STANDOFF_RADIUS * ENEMY_VILLAGE_REACHED_SLACK:
			u.village_reached = true
		if u.village_reached and _friendly_force_still_in_the_field():
			# Direct user report, live: "Right now, enemy squads are headed towards the bottom left corner. This is not rational. They know
			# where at least some of our squads are. They have a general idea where they last saw the mortar. None of this is the bottom left
			# corner." The blind push west along the squad's own line is for when nothing is known; with something known, go for it: the
			# nearest of where the mortar was last seen or heard (no expiry) and, if the force has the numbers to attack (_enemy_attack_stance),
			# where the nearest known friendly squad was last seen; with squads known but no stance to attack them, gather (as above).
			var known_target := Vector2.INF
			var last_mortar := _last_known_friendly_mortar_position()
			if not is_inf(last_mortar.x):
				known_target = last_mortar
			var known_squad := _known_friendly_squad_objective(u)
			if not is_inf(known_squad.x) and _enemy_attack_stance():
				if is_inf(known_target.x) or u.global_position.distance_to(known_squad) < u.global_position.distance_to(known_target):
					known_target = known_squad
			if not is_inf(known_target.x):
				return known_target
			if not is_inf(known_squad.x):
				return _enemy_consolidation_point()
			return Vector2(GameConfig.PLAYER_SAFE_X, u.global_position.y)
	return village


## Whether the enemy squads, with our mortar gone, have the numbers to attack our squads: their strength
## (the pips of their ACTIVE squads) against what they know of ours (the pips they last saw on the
## friendly squads they know of, still believed active), at least ENEMY_ATTACK_ADVANTAGE_RATIO (2:1). With
## hysteresis, so a ratio hovering at 2 does not flip them between attacking and gathering every tick: an
## attack that has begun is kept up until the ratio falls below ENEMY_ATTACK_KEEP_RATIO. True with no
## friendly squad known (nothing to be outnumbered by: the objective logic then falls through to the
## village and the push west). The stance is recomputed once per tick (see _update_enemy_squad_advance).
func _enemy_attack_stance() -> bool:
	return _enemy_attacking


func _update_enemy_attack_stance() -> void:
	var mine := 0.0
	for e in enemy_units:
		if e.kind == Unit.Kind.SQUAD and e.state == Unit.State.ACTIVE:
			mine += float(e.pips)
	var theirs := 0.0
	var known := 0
	for f in player_units:
		if f.kind == Unit.Kind.SQUAD and f.state == Unit.State.ACTIVE and f.enemy_has_been_sighted and f.enemy_known_state == Unit.State.ACTIVE:
			theirs += float(f.enemy_known_pips if f.enemy_known_pips > 0 else f.max_pips)
			known += 1
	if known == 0:
		_enemy_attacking = true
		_enemy_stance_decided = false
		return
	var ratio: float = mine / maxf(theirs, 1.0)
	# The first decision is made at the full 2:1; the lower keep ratio only holds an attack already begun.
	_enemy_attacking = ratio >= (ENEMY_ATTACK_KEEP_RATIO if _enemy_attacking and _enemy_stance_decided else ENEMY_ATTACK_ADVANTAGE_RATIO)
	_enemy_stance_decided = true


var _enemy_attacking: bool = true
var _enemy_stance_decided: bool = false
var _enemy_consolidation: Vector2 = Vector2.INF
## This battle's own roll of GameConfig.ENEMY_COMMANDER_RETREAT_THRESHOLD_MIN/MAX (see start_battle,
## rolled AFTER the battle's own seed is applied, for reproducibility) — the enemy commander's actual
## breaking point for this fight, used by _enemy_situation_hopeless. Direct user request: randomize it
## per battle rather than one fixed number every time, and keep it secret — nothing ever logs or displays
## this value to the player, only the consequence (squads pulling back) once it's crossed. Defaults to the
## OLD fixed 0.4 so any test/usage that constructs a BattleManager without calling start_battle keeps its
## previous, deterministic behavior.
var _enemy_commander_retreat_threshold: float = 0.4
## "Less than 2:1 in their favor": below this they gather instead of attacking.
const ENEMY_ATTACK_ADVANTAGE_RATIO: float = 2.0
const ENEMY_ATTACK_KEEP_RATIO: float = 1.6
## How far from every friendly squad they know of the enemy gathers (beyond SQUAD_DANGER_RANGE, so out of
## the reach of a squad's own fire and the range they react to). JUDGMENT.
const ENEMY_CONSOLIDATION_STANDOFF: float = 1500.0 * GameConfig.PIXELS_PER_METER
## How close to the point counts as gathered.
const ENEMY_CONSOLIDATION_ARRIVE_RADIUS: float = 300.0 * GameConfig.PIXELS_PER_METER
## Direct user report: "When the enemy squads consolidate around a position, they should have a bit more
## separation from each other than what they are currently doing." Before this, _consolidation_score had no
## term at all for another consolidating squad — only for the friendly squads being avoided — so every
## squad steered toward the exact same shared point with nothing pushing them apart, and ended up standing
## on top of one another. How far apart consolidated squads try to stay from each other. Deliberately much
## tighter than ENEMY_CONSOLIDATION_STANDOFF (which is about staying clear of an armed friendly squad's own
## fire) — this is just "don't stand on top of each other while waiting," not a defensive dispersal against
## a specific weapon; up to ENEMY_SQUAD_COUNT_MAX (10) squads still have to fit within a reasonably sized
## gathering area around one shared point. JUDGMENT.
const ENEMY_CONSOLIDATION_SQUAD_SPACING: float = 200.0 * GameConfig.PIXELS_PER_METER
## The max penalty (at zero separation, decaying to none at ENEMY_CONSOLIDATION_SQUAD_SPACING) for standing
## close to another consolidating squad — half of the friendly-squad-avoidance term's own weight just below
## in _consolidation_score: real separation from a fellow squad matters less than staying clear of an armed
## threat, but should still be a genuine, felt preference, not a token nudge.
const ENEMY_CONSOLIDATION_SPACING_WEIGHT: float = GameConfig.ENEMY_ADVANCE_RUSH_DISTANCE
## Direct user follow-up: "Also, they should prefer to consolidate where there is cover." A flat,
## distance-equivalent bonus (comparable to a single advance bound) for a candidate settling spot that's
## actually in cover terrain — see GameConfig.ENEMY_ADVANCE_COVER_BONUS for the equivalent, differently-
## scaled preference already applied to the ordinary advance-by-bounds.
const ENEMY_CONSOLIDATION_COVER_BONUS: float = GameConfig.ENEMY_ADVANCE_RUSH_DISTANCE * 0.75


## Where the enemy squads gather when they will not attack: the centre of their own squads, moved away from
## the friendly squads they know of if that is within ENEMY_CONSOLIDATION_STANDOFF of any, and kept once
## chosen (it is only moved if our squads come to within the standoff of it). A place to wait, not to
## fight from: nothing here makes it a defensive position.
func _enemy_consolidation_point() -> Vector2:
	var known: Array[Vector2] = _known_friendly_squad_positions()
	if not is_inf(_enemy_consolidation.x):
		var still_clear := true
		for p in known:
			if p.distance_to(_enemy_consolidation) < ENEMY_CONSOLIDATION_STANDOFF:
				still_clear = false
				break
		if still_clear:
			return _enemy_consolidation
	var sum := Vector2.ZERO
	var n := 0
	for e in enemy_units:
		if e.kind == Unit.Kind.SQUAD and e.state == Unit.State.ACTIVE:
			sum += e.global_position
			n += 1
	var point: Vector2 = sum / float(n) if n > 0 else Vector2(GameConfig.ENEMY_SAFE_X, GameConfig.MAP_HEIGHT_PX * 0.5)
	if not known.is_empty():
		var centre: Vector2 = _known_position_centroid(known)
		for i in 6:
			var nearest := INF
			for p in known:
				nearest = minf(nearest, point.distance_to(p))
			if nearest >= ENEMY_CONSOLIDATION_STANDOFF:
				break
			var away: Vector2 = (point - centre).normalized() if point.distance_to(centre) > 1.0 else Vector2.RIGHT
			point = GameConfig.clamp_to_operating_area(point + away * (ENEMY_CONSOLIDATION_STANDOFF - nearest + 100.0 * GameConfig.PIXELS_PER_METER))
	point = _consolidation_point_seeking_cover(point, known)
	_enemy_consolidation = point
	return point


## Direct user follow-up: "Also, they should prefer to consolidate where there is cover." A ring search
## (same idiom as GameConfig's own concealment searches) around the raw computed point for the nearest spot
## that's actually in cover terrain, still kept clear of every known friendly squad by ENEMY_CONSOLIDATION_
## STANDOFF — reusing _consolidation_score's own distance-plus-friendly-avoidance shape (siblings omitted:
## nothing has actually converged on this exact point yet the first time it's chosen) so "how far from the
## raw point" and "how close to a friendly squad" are weighed the same way here as everywhere else this
## point is used. Falls back to the raw point unchanged if nothing in cover turns up nearby, or if it's
## already in cover — a real gathering spot doesn't NEED cover to exist, this is a preference, not a
## requirement. Only ever runs when the point is first chosen or re-chosen (see _enemy_consolidation's own
## "kept once chosen" caching above), not every tick.
func _consolidation_point_seeking_cover(point: Vector2, known: Array[Vector2]) -> Vector2:
	if GameConfig.is_in_cover(GameConfig.get_terrain_type_at(point)):
		return point
	var best: Vector2 = point
	var best_score: float = _consolidation_score(point, point, known)
	for radius_m in [300.0, 600.0, 900.0, 1200.0]:
		for angle_deg in range(0, 360, 30):
			var candidate: Vector2 = GameConfig.clamp_to_operating_area(point + Vector2.RIGHT.rotated(deg_to_rad(angle_deg)) * radius_m * GameConfig.PIXELS_PER_METER)
			if not GameConfig.is_in_cover(GameConfig.get_terrain_type_at(candidate)):
				continue
			var score: float = _consolidation_score(candidate, point, known)
			if score < best_score:
				best_score = score
				best = candidate
	return best


## The friendly squads the enemy knows of, where it last saw them.
func _known_friendly_squad_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for f in player_units:
		if f.kind == Unit.Kind.SQUAD and f.state == Unit.State.ACTIVE and f.enemy_has_been_sighted and f.enemy_known_state == Unit.State.ACTIVE:
			out.append(f.enemy_known_position)
	return out


## Other ACTIVE enemy squads' own positions — or their pending destination, if `_update_enemy_squad_advance`
## already decided one for them earlier this same tick (same reasoning as _sibling_mortar_positions: that
## function processes every squad in a fixed order each tick, so without this, two squads consolidating the
## same tick would each only see the other's stale pre-decision position and could still converge on nearby
## spots despite each individually "avoiding" the other's old one). Fed into _consolidation_score so squads
## settling near the shared gathering point spread out from EACH OTHER, not just from the friendly squads
## they're keeping clear of. Direct user report: "When the enemy squads consolidate around a position, they
## should have a bit more separation from each other than what they are currently doing."
func _sibling_consolidating_squad_positions(u: Unit) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for o in enemy_units:
		if o == u or o.kind != Unit.Kind.SQUAD or o.state != Unit.State.ACTIVE:
			continue
		out.append(o.move_target if o.has_move_target else o.global_position)
	return out


## One bound of an enemy squad toward the consolidation point that keeps clear of the friendly squads it
## knows of ("far-advanced enemies would try to navigate back ... avoiding the friendly squads"): among
## bounds at a spread of angles off the straight line, the one that leaves it nearest the point once the
## nearness of each known friendly squad (inside ENEMY_CONSOLIDATION_STANDOFF) and each other consolidating
## squad (inside ENEMY_CONSOLIDATION_SQUAD_SPACING) is counted against it, and cover is credited toward it.
## Returns the squad's own position when it is gathered, or no bound improves on staying.
##
## Direct user report: "When the enemy squads consolidate around a position, they should have a bit more
## separation from each other than what they are currently doing." A squad already within ARRIVE_RADIUS of
## the shared point used to stop unconditionally right there, with no separation check at all — the common
## case for a group that was already bunched together BEFORE deciding to consolidate at all (their own
## centroid, where _enemy_consolidation_point starts from, sits right among them). Now "arrived" also
## requires not still crowding a sibling; if it is, one more bound is taken to step clear. `to_goal` is
## degenerate in exactly that case (already essentially at the goal), so the bound direction falls back to
## straight away from the nearest sibling instead of toward a goal there's no real distance left to aim at.
func _consolidation_step(u: Unit) -> Vector2:
	var target: Vector2 = _enemy_consolidation_point()
	var dist: float = target.distance_to(u.global_position)
	var siblings: Array[Vector2] = _sibling_consolidating_squad_positions(u)
	if dist <= ENEMY_CONSOLIDATION_ARRIVE_RADIUS and not _too_close_to_a_sibling(u.global_position, siblings):
		return u.global_position
	var known: Array[Vector2] = _known_friendly_squad_positions()
	var goal: Vector2 = _consolidation_goal(u.global_position, target, known)
	var to_goal: Vector2 = goal - u.global_position
	var to_goal_len: float = to_goal.length()
	var has_real_goal: bool = to_goal_len > 1.0
	var bound_dir: Vector2 = to_goal.normalized() if has_real_goal else _direction_away_from_nearest(u.global_position, siblings)
	var step: float = minf(to_goal_len, GameConfig.ENEMY_ADVANCE_RUSH_DISTANCE) if has_real_goal else GameConfig.ENEMY_ADVANCE_RUSH_DISTANCE
	# The normal ±120-degree sweep off `to_goal` (below) is meaningless once there's no real goal distance
	# left to aim it from — `bound_dir` there is only "away from the nearest sibling," a direction with no
	# relationship to where any known friendly squad is, so a narrow sweep around it could easily miss every
	# candidate that's actually clear of them. A real, previously-reported failure, caught by this project's
	# own test suite: a squad already gathered but still crowding a sibling could end up moving MEASURABLY
	# closer to a friendly squad while only trying to create separation. The full circle lets the scoring
	# (which already penalizes both) actually find a direction that's good on both counts.
	var angles_deg: Array[float] = GameConfig.ENEMY_ADVANCE_ANGLES_DEG
	if not has_real_goal:
		angles_deg = []
		for a in range(0, 360, 30):
			angles_deg.append(float(a))
	var best: Vector2 = u.global_position
	var best_score: float = _consolidation_score(u.global_position, goal, known, siblings)
	for angle_deg in angles_deg:
		var p: Vector2 = GameConfig.clamp_to_operating_area(u.global_position + bound_dir.rotated(deg_to_rad(angle_deg)) * step)
		var score: float = _consolidation_score(p, goal, known, siblings)
		if score < best_score:
			best_score = score
			best = p
	return best


## True if `pos` is closer than ENEMY_CONSOLIDATION_SQUAD_SPACING to any position in `siblings`.
func _too_close_to_a_sibling(pos: Vector2, siblings: Array[Vector2]) -> bool:
	for s in siblings:
		if pos.distance_to(s) < ENEMY_CONSOLIDATION_SQUAD_SPACING:
			return true
	return false


## Straight away from whichever of `positions` is nearest to `from` — the natural bound direction for
## stepping clear of a crowded neighbor when there's no remaining goal distance left to aim a bound at (see
## _consolidation_step's own doc comment). Vector2.RIGHT if `positions` is empty or `from` already coincides
## exactly with the nearest one (a real, if arbitrary, direction beats a zero vector, which would leave
## `.rotated()` unable to spread the search across any angle at all).
func _direction_away_from_nearest(from: Vector2, positions: Array[Vector2]) -> Vector2:
	var nearest := Vector2.INF
	var nearest_dist := INF
	for p in positions:
		var d: float = from.distance_to(p)
		if d < nearest_dist:
			nearest_dist = d
			nearest = p
	if is_inf(nearest.x) or nearest_dist < 1.0:
		return Vector2.RIGHT
	return (from - nearest).normalized()


## Where a bound toward the consolidation point is really aimed: the point itself, unless the straight line
## there runs within the standoff of a friendly squad the enemy knows of. Then a way point around them, on
## whichever side (across the line) is shorter, out beyond the group by the standoff — a squad that has
## advanced past our squads has to go round them, and a step-by-step choice alone cannot (walking round
## costs it distance to the point before it gains any). Recomputed each bound, so it drops out once the
## way round is clear.
func _consolidation_goal(from: Vector2, target: Vector2, known: Array[Vector2]) -> Vector2:
	if known.is_empty():
		return target
	var blocked := false
	for k in known:
		if Geometry2D.get_closest_point_to_segment(k, from, target).distance_to(k) < ENEMY_CONSOLIDATION_STANDOFF:
			blocked = true
			break
	if not blocked:
		return target
	var centre: Vector2 = _known_position_centroid(known)
	var radius := 0.0
	for k in known:
		radius = maxf(radius, k.distance_to(centre))
	var line: Vector2 = (target - from).normalized()
	var perp: Vector2 = line.orthogonal()
	var reach: float = radius + ENEMY_CONSOLIDATION_STANDOFF + 100.0 * GameConfig.PIXELS_PER_METER
	var best: Vector2 = target
	var best_len := INF
	for side in [-1.0, 1.0]:
		var wp: Vector2 = GameConfig.clamp_to_operating_area(centre + perp * side * reach)
		var length: float = from.distance_to(wp) + wp.distance_to(target)
		if length < best_len:
			best_len = length
			best = wp
	return best


## Lower is better: the distance still to go, plus the nearness of the friendly squads (a full
## ENEMY_ADVANCE_RUSH_DISTANCE-worth for standing on one, fading to nothing at the standoff), plus the
## nearness of another consolidating squad (ENEMY_CONSOLIDATION_SPACING_WEIGHT's worth for standing right
## on one, fading to nothing at ENEMY_CONSOLIDATION_SQUAD_SPACING — a real but gentler preference than the
## friendly-squad term, since this is about not crowding a friend, not staying clear of an armed threat),
## minus a flat bonus for actually landing in cover (direct user follow-up: "they should prefer to
## consolidate where there is cover").
func _consolidation_score(p: Vector2, target: Vector2, known: Array[Vector2], siblings: Array[Vector2] = []) -> float:
	var score: float = p.distance_to(target)
	for k in known:
		score += 2.0 * GameConfig.ENEMY_ADVANCE_RUSH_DISTANCE * clampf(1.0 - p.distance_to(k) / ENEMY_CONSOLIDATION_STANDOFF, 0.0, 1.0)
	for s in siblings:
		score += ENEMY_CONSOLIDATION_SPACING_WEIGHT * clampf(1.0 - p.distance_to(s) / ENEMY_CONSOLIDATION_SQUAD_SPACING, 0.0, 1.0)
	if GameConfig.is_in_cover(GameConfig.get_terrain_type_at(p)):
		score -= ENEMY_CONSOLIDATION_COVER_BONUS
	return score


## Where the enemy last saw the friendly squads it knows of (still believed ACTIVE): the one nearest `u`,
## or, with no `u` (the shared pivot), their centroid; Vector2.INF if it knows of none. What the enemy
## knows, not where they are: enemy_known_position, from an actual sighting.
func _known_friendly_squad_objective(u: Unit = null) -> Vector2:
	var positions: Array[Vector2] = []
	for s in player_units:
		if s.kind == Unit.Kind.SQUAD and s.enemy_has_been_sighted and s.enemy_known_state == Unit.State.ACTIVE and s.state == Unit.State.ACTIVE:
			positions.append(s.enemy_known_position)
	if positions.is_empty():
		return Vector2.INF
	if u == null:
		return _known_position_centroid(positions)
	var best: Vector2 = positions[0]
	for p in positions:
		if u.global_position.distance_to(p) < u.global_position.distance_to(best):
			best = p
	return best


## The exact mirror of _known_friendly_squad_objective, for a known SPOTTER instead of a squad. Consulted
## by _spotter_hunt_candidate/_chase_spotter_directly (see their own doc comments for the current ruling on
## when and how a squad acts on this) rather than _enemy_advance_objective — an earlier version of this
## feature put the spotter there as a blanket, distance-independent #1 objective for every squad; a later,
## more specific user ruling replaced that with a proximity- and availability-gated single-squad response
## instead (see docs/designs/tactical-commander-doctrine.md's 2026-09-29 entries for both). Kept as its own
## separate function from _known_friendly_squad_objective (not folded together) since a spotter needs none
## of that function's _enemy_attack_stance numerical-advantage gating — an unarmed, undefended observer
## isn't a fight that needs the numbers an armed squad would.
func _known_friendly_spotter_position(u: Unit = null) -> Vector2:
	var positions: Array[Vector2] = []
	for s in player_units:
		if s.kind == Unit.Kind.SPOTTER and s.enemy_has_been_sighted and s.enemy_known_state == Unit.State.ACTIVE and s.state == Unit.State.ACTIVE:
			positions.append(s.enemy_known_position)
	if positions.is_empty():
		return Vector2.INF
	if u == null:
		return _known_position_centroid(positions)
	var best: Vector2 = positions[0]
	for p in positions:
		if u.global_position.distance_to(p) < u.global_position.distance_to(best):
			best = p
	return best


## Slack on "reached the village": squads stop at the standoff ring, so allow a little beyond it.
const ENEMY_VILLAGE_REACHED_SLACK: float = 1.25


## Anything of the friendly side still active that is worth pushing on after (a squad, or the mortar).
func _friendly_force_still_in_the_field() -> bool:
	return _friendly_squads_in_action() > 0 or _friendly_mortar_is_active()


## The freshest place the enemy has any fix on the friendly mortar — where it
## was last seen, or where it was last detected firing — with no expiry, or
## Vector2.INF if it has never been seen or heard. (_known_friendly_mortar_
## position is the current fix, which lapses after MORTAR_FIRE_DETECTION_EXPIRY.)
func _last_known_friendly_mortar_position() -> Vector2:
	var best_pos := Vector2.INF
	var best_time := -INF
	for u in player_units:
		if u.kind != Unit.Kind.MORTAR or u.state == Unit.State.DESTROYED:
			continue
		if u.enemy_has_been_sighted and u.enemy_known_position_time > best_time:
			best_time = u.enemy_known_position_time
			best_pos = u.enemy_known_position
		var info: Dictionary = _last_detected_mortar_fire.get(u, {})
		if not info.is_empty() and info.time > best_time:
			best_time = info.time
			best_pos = info.position
	return best_pos


func _friendly_mortar_is_active() -> bool:
	for u in player_units:
		if u.kind == Unit.Kind.MORTAR and u.state == Unit.State.ACTIVE:
			return true
	return false


## The friendly-side counterpart to _update_enemy_squad_advance: an idle,
## ACTIVE player squad with nothing worth shooting at right now (same idle
## gate — a squad already fighting stands and fights, it doesn't reposition
## out from under a live engagement) watches for three things and answers
## the first that applies, in priority order:
##
## (1) SELF-PRESERVATION — see _reposition_for_encirclement. A squad that's
## actually at risk of being surrounded pulls back toward its own side's
## center of mass instead of standing to be overrun. It's marked in
## `at_risk` so the pass below never reassigns it to go plug a gap
## elsewhere — it's already got its own problem to solve.
##
## (2) SEEK COVER — a general standing preference, not conditioned on any
## specific detected threat: a squad not already in cover, with nothing
## else going on, moves to the nearest one. Standing in the open should
## need an actual reason (already covered by (1)/(3) or the idle-gate
## exclusions above), not the other way around.
##
## (3) MORTAR PROTECTION — for the single nearest known enemy SQUAD still
## actively pressing the fight (not RETREATING — see
## _nearest_unscreened_mortar_threat) that has an open, unscreened lane to
## the friendly mortar's own actual position (see
## _nearest_unscreened_mortar_threat/_lane_is_screened), the nearest
## still-idle, not-already-at-risk squad moves out to MORTAR_PROTECTIVE_
## RADIUS from the mortar, on the bearing toward that threat — directly
## interposing itself between the two. Only the single closest open lane is
## answered per tick, one squad at a time, rather than every idle squad
## reshuffling at once for threats that may resolve themselves before
## anyone arrives. Checked last/separately below since it needs a squad
## that's ALSO not already sent to seek cover this same tick.
##
## Deliberately never narrates *why* a squad moves for mortar protection
## specifically (no "the mortar's position is known" log) — that would hand
## the player intel about the enemy's own knowledge state it wouldn't
## otherwise have, the same fog-of-war line drawn around the enemy's mortar
## ammo/resupply status. Ordinary cover-seeking has no such concern (it's
## about the squad's OWN position, not the enemy's), so it's narrated
## normally.
## A spotter's whole value is staying unseen — it carries no weapon and never fires a shot (see
## _tick_fire's own SPOTTER/DRONE_TEAM/DRONE early return). Direct user ruling, given after research into
## real-world detection ranges: "Spotter should always seek cover. If set up not in cover, it should
## immediately move to cover. If it later moves, that might take it out of cover, but it would go to new
## cover." Mirrors _update_friendly_squad_positioning's own "cover whenever possible" idiom below (same
## GameConfig.nearest_cover_point call, same REPOSITION_SPEED) stripped of everything specific to an armed,
## fighting squad — no encirclement response, no "has a live target, stand and fight" exception, since a
## spotter never has either. Unlike that function, this applies to BOTH teams: nothing currently spawns an
## enemy spotter, but nothing here assumes a player-only one either.
func _update_spotter_positioning() -> void:
	for u in player_units + enemy_units:
		if u.kind != Unit.Kind.SPOTTER or u.state != Unit.State.ACTIVE or u.has_move_target:
			continue
		if _fall_back_orders.has(u) or _risk_holds.has(u):
			continue # an explicit order/hold outranks the automatic instinct to seek cover
		if GameConfig.is_in_cover(u.terrain_type()):
			continue
		var cover_dest: Vector2 = GameConfig.nearest_cover_point(u.global_position)
		if cover_dest == u.global_position:
			continue # nothing better nearby this tick
		u.last_order_reason = "Moving into available cover."
		u.move_target = cover_dest
		u.has_move_target = true
		u.move_queue.clear()
		u.move_speed = GameConfig.REPOSITION_SPEED
		u.movement_predictable = false


const SCREEN_REASON: String = "Screen an open approach to the friendly mortar."
## How far apart squads sent to screen the same approach are placed, side by side across it. Direct user guidance: "I would discourage squads
## from taking up positions within 50 meters of each other for sure." A squad stops within MOVE_ARRIVE_RADIUS (25 m) of its point, so the
## points are spaced a good deal wider than that minimum.
const SCREEN_SQUAD_SPACING: float = 70.0 * GameConfig.PIXELS_PER_METER

## The squads currently on their way to, or standing at, a screening point, in a fixed order.
func _screening_squads() -> Array[Unit]:
	var out: Array[Unit] = []
	for u in player_units:
		if u.kind == Unit.Kind.SQUAD and u.state == Unit.State.ACTIVE and u.has_move_target and u.last_order_reason == SCREEN_REASON:
			out.append(u)
	out.sort_custom(func(a, b): return a.get_instance_id() < b.get_instance_id())
	return out


## Where the `slot`-th of `count` squads screening the approach from `threat` to `mortar` goes: the point MORTAR_PROTECTIVE_RADIUS from the
## mortar toward the threat, shifted sideways by SCREEN_SQUAD_SPACING per slot, centred on the line, so a lone squad takes the line itself.
func _screen_point(mortar: Unit, threat: Vector2, slot: int, count: int) -> Vector2:
	var dir: Vector2 = (threat - mortar.global_position).normalized()
	var base: Vector2 = mortar.global_position + dir * GameConfig.MORTAR_PROTECTIVE_RADIUS
	return base + dir.orthogonal() * (float(slot) - float(count - 1) * 0.5) * SCREEN_SQUAD_SPACING


func _update_friendly_squad_positioning() -> void:
	var known_enemies := _known_enemy_positions(Unit.Team.PLAYER)
	var at_risk: Dictionary = {}
	# Several squads can go idle-and-uncovered in the very same tick (e.g.
	# right after a lull ends, or at battle start) and this loop processes
	# all of them in one pass — without tracking what's already been
	# claimed THIS pass, each one independently asks "what's the nearest
	# cover to ME" from ally positions that haven't moved yet, and reliably
	# picks the same single nearby zone. Same bunching order_general_
	# retreat's own `claimed` accumulator already exists to prevent for a
	# mass retreat; this tier needed the identical treatment.
	var claimed: Array[Vector2] = []
	for u in player_units:
		if u.kind != Unit.Kind.SQUAD or u.state != Unit.State.ACTIVE or u.has_move_target:
			continue
		if _fall_back_orders.has(u):
			continue # ordered to fall back: not this loop's to steer
		if _pick_target(u, enemy_units) != null or _risk_holds.has(u):
			continue # something to shoot at right now — stand and fight
		var encirclement_dest := _reposition_for_encirclement(u, known_enemies, _ally_positions_for(u) + claimed)
		if encirclement_dest != u.global_position:
			at_risk[u] = true
			claimed.append(encirclement_dest)
			continue
		# General principle, not conditioned on a specific detected threat:
		# a squad wants to be in cover whenever possible, and standing in
		# the open needs an actual reason (already moving, mid-encirclement
		# response, has a live target, screening something specific — all
		# already excluded above), not the other way around. The enemy's
		# own mirror of this (_alert_enemy_squads) only ever triggers
		# reactively, once someone's actually been shot at — fine for an
		# attacking force already closing the distance, but a defending
		# squad shouldn't wait for first contact (or even a detected
		# threat at all) before getting off open ground; real infantry
		# occupying a position uses available cover from the moment it's
		# there, not just once something's spotted approaching.
		if GameConfig.is_in_cover(u.terrain_type()):
			continue
		var cover_dest: Vector2 = GameConfig.nearest_cover_point(u.global_position, 0.0, false, _ally_positions_for(u) + claimed, known_enemies)
		if cover_dest == u.global_position:
			continue # nothing better nearby this tick
		if _advances_past_fall_back_line(u, cover_dest):
			continue # it has fallen back on order: cover ahead of that line is not for it
		u.last_order_reason = "Moving into available cover."
		u.move_target = cover_dest
		u.has_move_target = true
		u.move_queue.clear()
		u.move_speed = GameConfig.REPOSITION_SPEED
		u.movement_predictable = false
		at_risk[u] = true
		claimed.append(cover_dest)
		combat_log.log_seeking_cover(u)

	var mortar := _friendly_active_mortar()
	var threat: Vector2 = _nearest_unscreened_mortar_threat(mortar, enemy_units) if mortar != null else Vector2.INF

	# A real, previously-reported failure mode: a squad already MID-WALK to
	# screen the mortar used to be completely excluded from reconsideration
	# (the responder-selection loop below only ever looks at squads with
	# has_move_target == false) until it physically arrived — so if the
	# mortar itself moved on (its own routine business, or turning back
	# after the earlier home-leash/resupply-bias fixes finally gave it a
	# sensible destination), the squad kept walking toward a stale block
	# point long after the reason for going there had evaporated. Every
	# tick, ANY squad currently tagged as screening gets its own move
	# target freshly re-aimed at the mortar's CURRENT position (or
	# released outright if nothing is unscreened anymore) — the same
	# "re-aim every tick rather than commit to a stale destination" idiom
	# already established for the enemy mortar's own hunting movement, not
	# a new pattern invented just for this.
	#
	# A SECOND, previously-undiscovered variant of the same bug: this used
	# to return immediately above once the mortar itself stopped being
	# ACTIVE (retreating, withdrawn, or destroyed) — skipping this very
	# release loop and leaving any squad already mid-walk to screen it
	# frozen at wherever the mortar happened to be the instant it stopped
	# being ACTIVE, with nothing ever telling it to reposition back. A
	# mortar that's already pulling out of the fight needs no more
	# screening than one with no threat left to screen against — both are
	# "nothing left to do here," so both release the same way.
	var screening: Array[Unit] = _screening_squads()
	for u in screening:
		if mortar == null or is_inf(threat.x):
			u.has_move_target = false
			u.last_order_reason = "Screening no longer needed; repositioning."
			continue
		u.move_target = _screen_point(mortar, threat, screening.find(u), screening.size())

	if mortar == null or is_inf(threat.x):
		return
	var responder: Unit = null
	var best_dist := INF
	for u in player_units:
		if u.kind != Unit.Kind.SQUAD or u.state != Unit.State.ACTIVE or u.has_move_target or at_risk.has(u):
			continue
		if _pick_target(u, enemy_units) != null or _risk_holds.has(u) or _fallen_back.has(u):
			continue # (a squad that has fallen back on order does not go forward to screen)
		var d: float = u.global_position.distance_to(mortar.global_position)
		if d < best_dist:
			best_dist = d
			responder = u
	if responder == null:
		return

	# Its own place along the screen, beside any squad already sent (see _screen_point): not the same coordinate as the others.
	var with_responder: Array[Unit] = _screening_squads()
	with_responder.append(responder)
	with_responder.sort_custom(func(a, b): return a.get_instance_id() < b.get_instance_id())
	var block_point: Vector2 = _screen_point(mortar, threat, with_responder.find(responder), with_responder.size())
	responder.last_order_reason = SCREEN_REASON
	responder.move_target = block_point
	responder.has_move_target = true
	responder.move_queue.clear()
	responder.move_speed = GameConfig.REPOSITION_SPEED
	responder.movement_predictable = false
	combat_log.log_squad_blocking_flank(responder)


## How much of the capped step toward the rally point the cover chosen must actually cover (see _reposition_for_encirclement).
const ENCIRCLEMENT_MIN_PROGRESS_FRACTION: float = 0.3

## Issues the actual repositioning move and returns its destination if `u`
## is genuinely at risk of being surrounded: known enemies within
## FRIENDLY_ENCIRCLEMENT_DETECT_RADIUS span at least FRIENDLY_ENCIRCLEMENT_
## ANGLE_THRESHOLD_DEG of arc around it, AND at least FRIENDLY_ENCIRCLEMENT_
## MIN_COVERED_FRACTION of them are already dug into real cover —
## "surrounded by enemies under cover," the specific hopeless case, not
## just "outnumbered from two sides" by contacts still caught in the open.
## Pulls back toward the center of mass of the rest of this squad's own
## side's OTHER SQUADS — a real, previously-reported failure mode: this
## used to average in every other ACTIVE unit regardless of role,
## including the mortar and spotter/drone team, so a mortar off doing its
## own business well away from the front (shoot-and-scoot, evading,
## resupply linkup — none of it about this squad's own fight) could drag
## the whole rally point away from an otherwise perfectly good hilltop
## position, and every squad reading the same "surrounded" signal in the
## same tick would follow it there together. A rally point is about
## consolidating with other infantry that can actually stand and fight
## alongside this squad — a small, easily-displaced crew-served weapon
## team isn't that, any more than the ground spotter or drone team are.
## Falls back to the mortar's own position only once there's truly no
## other squad left to rally toward at all (a lone final squad, or none
## active) — better than nothing, not a default anchor. Returns
## `u.global_position` unchanged (nearest_cover_point's own no-op
## convention) if it doesn't act, so a caller can tell "did this fire"
## from the return value alone without a separate bool.
##
## `claimed`: cover this same tick's earlier squads (in THIS function or
## the ordinary cover-seeking tier right above it in the caller's loop)
## already chose, or already occupy — several squads can all read
## "surrounded" in the very same tick from a shared, only slowly-changing
## enemy picture, and every one of them independently averaging roughly
## the same allies' positions naturally lands on roughly the same rally
## point; without this, they all then also pick the SAME nearest cover to
## it, consolidating for safety into exactly the single bunched-up target
## this function's own destination logic (below) already exists to avoid
## for any one squad individually. Same `claimed`-accumulator treatment
## order_general_retreat and the cover-seeking tier above already use for
## the identical multiple-squads-same-tick problem.
func _reposition_for_encirclement(u: Unit, known_enemies: Array[Vector2], claimed: Array[Vector2]) -> Vector2:
	var detect_radius: float = GameConfig.FRIENDLY_ENCIRCLEMENT_DETECT_RADIUS
	var min_covered_fraction: float = GameConfig.FRIENDLY_ENCIRCLEMENT_MIN_COVERED_FRACTION
	var angle_threshold_deg: float = GameConfig.FRIENDLY_ENCIRCLEMENT_ANGLE_THRESHOLD_DEG

	var nearby: Array[Vector2] = []
	for p in known_enemies:
		if u.global_position.distance_to(p) <= detect_radius:
			nearby.append(p)
	if nearby.size() < 2:
		return u.global_position

	var covered := 0
	for p in nearby:
		if GameConfig.is_in_cover(GameConfig.get_terrain_type_at(p)):
			covered += 1
	if float(covered) / float(nearby.size()) < min_covered_fraction:
		return u.global_position

	var angles: Array[float] = []
	for p in nearby:
		angles.append(rad_to_deg((p - u.global_position).angle()))
	angles.sort()
	var max_gap := 0.0
	for i in angles.size():
		var a: float = angles[i]
		var b: float = angles[(i + 1) % angles.size()]
		var gap: float = (b - a) if i < angles.size() - 1 else (b + 360.0 - a)
		max_gap = max(max_gap, gap)
	if 360.0 - max_gap < angle_threshold_deg:
		return u.global_position

	var allies: Array = _ally_units_for(u).filter(func(a): return a.kind == Unit.Kind.SQUAD)
	var rally_point: Vector2
	if allies.is_empty():
		var mortar := _friendly_active_mortar()
		if mortar == null:
			return u.global_position
		rally_point = mortar.global_position
	else:
		var sum := Vector2.ZERO
		for a in allies:
			sum += a.global_position
		rally_point = sum / allies.size()

	var to_rally: Vector2 = rally_point - u.global_position
	if to_rally.length() < 10.0:
		return u.global_position
	var step: float = min(to_rally.length(), GameConfig.FRIENDLY_REPOSITION_RUSH_DISTANCE)
	# The rally point itself is a bare geometric average of ally positions
	# (or just the mortar's own spot) — real ground, but with no notion of
	# terrain at all. Consolidating for safety and ending up bunched
	# together in the open is worse than not consolidating: a single round
	# can now catch several units at once (see _bunched_ally's own
	# splash-spread reasoning elsewhere in this file), the exact opposite
	# of what this function exists to prevent. Redirect the capped step
	# toward whatever real cover is nearest to it instead of walking
	# straight to open ground just because that's where the average
	# happened to land — same "look for actual cover, not just a bare
	# point" treatment _relocate_for_risk/_relocate_mortar already give
	# every other safety-driven move in this file. `claimed` (see this
	# function's own doc comment) keeps that spreading-out real across
	# MULTIPLE squads consolidating in the same tick, not just within one
	# squad's own candidate list. Falls back to the raw point if genuinely
	# nothing better is nearby (nearest_cover_point's own no-candidates
	# convention).
	var raw_step_destination: Vector2 = u.global_position + to_rally.normalized() * step
	var cover_destination: Vector2 = GameConfig.nearest_cover_point(raw_step_destination, 0.0, false, claimed, known_enemies)
	# The cover it settles on has to be a real step toward the rally point. Direct user report, live: "Friendly squad 3 is oscillating
	# uselessly": the cover search throws out any zone near a known enemy and picks a random point in a random one of the nearest, and with
	# the enemy between the squad and its friends what is left can be BEHIND it, so each arrival chose a new spot a few dozen metres away,
	# sometimes farther from the rally point than before (reproduced: a squad 1,074 m out went 1,166, 1,159, 1,157, 1,144, 1,148, 1,159,
	# 1,162). No cover that gets it closer means nowhere safe to consolidate to: it stays where it is.
	if cover_destination.distance_to(rally_point) > u.global_position.distance_to(rally_point) - step * ENCIRCLEMENT_MIN_PROGRESS_FRACTION:
		return u.global_position
	u.last_order_reason = "Known enemies threaten encirclement: consolidate toward friendly units."
	u.move_target = cover_destination
	u.has_move_target = true
	u.move_queue.clear()
	u.move_speed = GameConfig.REPOSITION_SPEED
	u.movement_predictable = false
	combat_log.log_squad_consolidating(u)
	return u.move_target


func _friendly_active_mortar() -> Unit:
	for u in player_units:
		if u.kind == Unit.Kind.MORTAR and u.state == Unit.State.ACTIVE:
			return u
	return null


## The nearest enemy SQUAD (from the player's own full knowledge of its own
## mortar's position — not the enemy's possibly-stale fix on it) that's
## still actively pressing the fight — RETREATING is deliberately excluded,
## same as _target_danger_to_force/_mortar_target_value's own squad-danger
## exclusion elsewhere: a squad already pulling out of the fight isn't
## preparing to overrun anything, so it isn't a flank threat worth pulling
## a squad out of position for. Within MORTAR_FLANK_THREAT_RADIUS of
## `mortar` and with no ACTIVE friendly squad currently screening the
## direct line between the two (_lane_is_screened) — an open lane worth a
## squad breaking off to plug. Vector2.INF if every nearby threat already
## has a squad in the way, or nothing close enough is still actually a
## threat.
func _nearest_unscreened_mortar_threat(mortar: Unit, opposing: Array[Unit]) -> Vector2:
	var screening_squads: Array[Unit] = []
	for u in player_units:
		if u.kind == Unit.Kind.SQUAD and u.state == Unit.State.ACTIVE:
			screening_squads.append(u)

	var best := Vector2.INF
	var best_dist := INF
	for e in opposing:
		if e.kind != Unit.Kind.SQUAD or e.state != Unit.State.ACTIVE or not e.is_visible:
			continue
		var p: Vector2 = e.global_position
		var dist: float = p.distance_to(mortar.global_position)
		if dist > GameConfig.MORTAR_FLANK_THREAT_RADIUS:
			continue
		if _lane_is_screened(p, mortar.global_position, screening_squads):
			continue
		if dist < best_dist:
			best_dist = dist
			best = p
	return best


## True if some squad in `squads` already sits within MORTAR_FLANK_CORRIDOR_
## WIDTH of the straight line from `from` to `to`, somewhere between the two
## endpoints (not off past either end) — close enough that anything walking
## that line would have to pass through, or at least within engagement
## range of, that squad first.
func _lane_is_screened(from: Vector2, to: Vector2, squads: Array[Unit]) -> bool:
	var lane: Vector2 = to - from
	var lane_len: float = lane.length()
	if lane_len < 1.0:
		return true
	var lane_dir: Vector2 = lane / lane_len
	for s in squads:
		var rel: Vector2 = s.global_position - from
		var t: float = rel.dot(lane_dir)
		if t < 0.0 or t > lane_len:
			continue # projects outside the segment — not actually between them
		var closest: Vector2 = from + lane_dir * t
		if s.global_position.distance_to(closest) <= GameConfig.MORTAR_FLANK_CORRIDOR_WIDTH:
			return true
	return false


## How much `point` is worth as the next advance leg at `angle_deg` off the
## direct line — see GameConfig.ENEMY_ADVANCE_COVER_BONUS/_CONCEALMENT_
## BONUS/_ENCIRCLE_BONUS/_ANGLE_PENALTY_PER_DEG for the rationale and
## relative weight behind each term; they're deliberately similar
## magnitudes so no one goal structurally dominates the others.
##
## Concealment/exposure are judged against EVERY currently-known player
## position, not just the nearest — a spot only counts as truly hidden if
## none of them can see it; with no known player position at all both are a
## neutral 0, same as the mortar danger-scoring's "nothing to actually be
## dangerous to" case.
##
## ENCIRCLE rewards a candidate whose bearing (relative to `friendly_center`
## — the known friendly cluster's own centroid) is angularly far from every
## OTHER active enemy squad's own current bearing around that same center —
## the actual mechanism behind squads settling on different sides of a
## shared objective instead of all crowding the one patch of cover nearest
## the direct line to it. Neutral 0 with no known friendly cluster yet, or
## with no other squad to differ from (nothing to spread out relative to).
func _score_advance_candidate(point: Vector2, angle_deg: float, known_player_positions: Array[Vector2], friendly_center: Vector2 = Vector2.INF, other_bearings_deg: Array[float] = [], tactical_pressure: float = 1.0) -> float:
	var score: float = GameConfig.ENEMY_ADVANCE_BASE_WEIGHT
	if GameConfig.is_in_cover(GameConfig.get_terrain_type_at(point)):
		score += GameConfig.ENEMY_ADVANCE_COVER_BONUS * tactical_pressure
	if not known_player_positions.is_empty():
		var concealed := true
		var exposed_to_fire := false
		for pp in known_player_positions:
			if GameConfig.has_direct_los(point, pp):
				concealed = false
				if point.distance_to(pp) <= GameConfig.SQUAD_ENGAGEMENT_RANGE:
					exposed_to_fire = true
		if concealed:
			score += GameConfig.ENEMY_ADVANCE_CONCEALMENT_BONUS * tactical_pressure
		if exposed_to_fire:
			score -= GameConfig.ENEMY_ADVANCE_EXPOSURE_PENALTY
	if not is_inf(friendly_center.x) and not other_bearings_deg.is_empty():
		var candidate_bearing: float = rad_to_deg((point - friendly_center).angle())
		var nearest_claimed_gap := 180.0
		for b in other_bearings_deg:
			nearest_claimed_gap = min(nearest_claimed_gap, _angle_diff(candidate_bearing, b))
		score += GameConfig.ENEMY_ADVANCE_ENCIRCLE_BONUS * (nearest_claimed_gap / 180.0) * tactical_pressure
	score -= abs(angle_deg) * GameConfig.ENEMY_ADVANCE_ANGLE_PENALTY_PER_DEG
	score = max(score, 0.1)
	# A wide bend (or a step backward) is only worth rolling when there is a fight to bend around: the 0.1
	# floor above would otherwise keep each of the six widest candidates alive at ~5% apiece however far the
	# squad is from anything, which alone is roughly a one-in-three chance of a wasted or backward bound.
	if absf(angle_deg) > GameConfig.ENEMY_ADVANCE_WIDE_BEND_DEG:
		score *= tactical_pressure
	return score


## A genuine weighted-random choice among advance-rush candidates (see
## _next_advance_point) — not a deterministic "always the single best
## angle," matching the same real-tactics-isn't-perfectly-rational idiom as
## _weighted_mortar_target_pick.
func _weighted_advance_point_pick(candidates: Array[Vector2], angles_deg: Array[float], known_player_positions: Array[Vector2], friendly_center: Vector2 = Vector2.INF, other_bearings_deg: Array[float] = [], tactical_pressure: float = 1.0) -> Vector2:
	var weights: Array[float] = []
	var total := 0.0
	for i in candidates.size():
		var w: float = _score_advance_candidate(candidates[i], angles_deg[i], known_player_positions, friendly_center, other_bearings_deg, tactical_pressure)
		weights.append(w)
		total += w
	var roll: float = randf() * total
	var cumulative := 0.0
	for i in candidates.size():
		cumulative += weights[i]
		if roll <= cumulative:
			return candidates[i]
	return candidates[candidates.size() - 1]


## Firing gives the OPPOSING mortar(s) — and only the opposing mortar, not
## every enemy unit — a chance to notice and shoot back, at one shared
## rate (GameConfig.MORTAR_COUNTER_BATTERY_CHANCE — see its own doc
## comment for why this ISN'T split by the firing mortar's own shoot-and-
## scoot doctrine: a responding crew reacts to a detected firing
## signature, not a prediction of what this specific target will do
## next). Mortars are a high-priority target for each other. This isn't
## abstract: the return fire has to physically come from an opposing
## mortar that could actually reach this position — one beyond its own
## side's real range (GameConfig.mortar_max_range) simply can't respond,
## no matter how exposed the firing mortar was. A mortar dug in deep
## enough to be out of both enemy tubes' range trades away some of its
## own reach for genuine counter-battery immunity.
##
## The strike isn't instant: it can only ever target where THIS mortar was
## standing right now, at the moment it fired (captured here, before any
## post-shot scoot hop) — see _resolve_pending_counter_battery for the
## delayed impact that actually checks whether it's still nearby — THAT
## check, not this one, is where shoot-and-scoot's own real protection
## actually lives.
##
## The reaction delay before the response even fires (before
## GameConfig.MORTAR_FLIGHT_TIME even starts) is composed from real
## component times, not one directly-stored random range — see
## GameConfig.COUNTER_BATTERY_LOCATE_TIME_MIN's own doc comment for the
## full real-world reasoning behind each piece and why LOCATE and SETUP
## run in parallel (max), not stacked (+):
##   react_delay = max(locate_time, setup_remaining) + lay_time
## A responder still mid-relocation (seconds_stationary below
## MORTAR_SETUP_TEARDOWN_TIME) no longer skips responding entirely the way
## it used to — a real, previously-reported gap this fixes: it now still
## answers, just with whatever setup time it genuinely has left to finish
## factored into the delay like everything else, exactly the way a moving
## crew would in reality rather than being unable to fire back at all
## until it happened to already be standing still.
func _resolve_mortar_counter_battery(firing_mortar: Unit) -> void:
	var opposing: Array[Unit] = player_units if firing_mortar.team == Unit.Team.ENEMY else enemy_units
	var chance: float = GameConfig.MORTAR_COUNTER_BATTERY_CHANCE
	# Direct user report: the history showed counter-battery fire landing on two mortars "at the same
	# time." Root cause: nothing here ever checked whether a candidate responder was already mid-mission —
	# a single tube can be committed to at most one fire mission at once, the same way ordinary fire is
	# already gated (a crew can't lay a fresh round while another is still in flight from an earlier call
	# for fire). One real tube, once already tasked, cannot ALSO pick up a second, independent call for
	# fire before the first is resolved (fired and landed) — see _resolve_pending_counter_battery for where
	# a committed strike actually leaves this set.
	var already_committed: Dictionary = {}
	for strike in _pending_counter_battery:
		already_committed[strike.attacker.get_instance_id()] = true
	for m in opposing:
		if m.kind != Unit.Kind.MORTAR or m.state != Unit.State.ACTIVE:
			continue
		if already_committed.has(m.get_instance_id()):
			continue # already answering an earlier call for fire — one mission at a time, same as ordinary fire
		if m.mortar_rounds_remaining <= 0:
			continue # nothing left to trade for a reply — a dry tube cannot credibly commit to counter-battery either
		if m.global_position.distance_to(firing_mortar.global_position) > GameConfig.mortar_max_range(m.team):
			continue # out of range — this mortar physically cannot reach back
		if randf() < chance:
			var locate_time: float = randf_range(GameConfig.COUNTER_BATTERY_LOCATE_TIME_MIN, GameConfig.COUNTER_BATTERY_LOCATE_TIME_MAX)
			var setup_remaining: float = max(GameConfig.MORTAR_SETUP_TEARDOWN_TIME - m.seconds_stationary, 0.0)
			var lay_time: float = randf_range(GameConfig.COUNTER_BATTERY_LAY_TIME_MIN, GameConfig.COUNTER_BATTERY_LAY_TIME_MAX)
			var react_delay: float = max(locate_time, setup_remaining) + lay_time
			unit_combat_stats.register(m)
			unit_combat_stats.shot(m, true)
			_pending_counter_battery.append({
				"attacker": m,
				"target": firing_mortar,
				"aim_position": firing_mortar.global_position, # the located position (exact for now: see the design log on how good locating is)
				"impact_position": firing_mortar.global_position,
				"fire_time": scenario_elapsed_time + react_delay,
				"impact_time": scenario_elapsed_time + react_delay + GameConfig.MORTAR_FLIGHT_TIME,
				"fired": false,
			})
			# A mortar's muzzle flash/trajectory can give it away here even
			# if nobody has actually laid eyes on it — a real detection
			# channel distinct from visual spotting (see _refresh_
			# visibility's own doc comment), so it may still be unnumbered
			# the first time its name needs to appear in this log line.
			# Assigned now, at detection, not deferred to the responding
			# mortar's own later fire_time — the ORIGINAL mortar's muzzle
			# flash (this shot, not the reply) is what gives it away, and
			# that already happened, this instant, regardless of whether
			# or when a response actually fires back.
			_assign_discovery_number(firing_mortar)
			break # one incoming strike per shot is enough, even with two enemy mortars


## Resolves any counter-battery strikes whose reaction time or flight time
## (see _resolve_mortar_counter_battery's own doc comment for the split)
## has elapsed. A strike goes through two stages here: first `fired`
## flips true and the responding mortar's own muzzle flash/tracer/combat-
## log line actually appear, at fire_time — the moment it fires, not the
## moment it merely decided to (or, if that crew was knocked out before
## it got the chance, the mission is simply dropped, nothing fires at
## all); then, once flight time also elapses, the target is only hit if
## it's still within the blast radius of where it fired from — a hold-
## position mortar never moves, so it's always caught; a shoot-and-scoot
## mortar has usually relocated well clear by the time this lands, and
## even if it's still nearby the odds are reduced, not certain.
func _resolve_pending_counter_battery() -> void:
	var still_pending: Array[Dictionary] = []
	for strike in _pending_counter_battery:
		if not strike.fired:
			if scenario_elapsed_time < strike.fire_time:
				still_pending.append(strike)
				continue
			var responder: Unit = strike.attacker
			if not is_instance_valid(responder) or responder.state != Unit.State.ACTIVE:
				continue # the responding crew was knocked out before it could actually fire — mission aborted, nothing lands
			if responder.mortar_rounds_remaining <= 0:
				continue # ran dry (an ordinary shot, most likely) before this call for fire came due — mission aborted, nothing lands
			# Direct user report: "I think enemy mortars are firing while moving... They should have the
			# same restrictions as friendly mortars in this regard." Then, on "spotted": "'not spotted'
			# should be 'not aware that it has been spotted'. If a drone sees it, it may not be aware of
			# that." — refined once more: "It might be aware of drone-only sighting. It depends if it has
			# seen the drone or not." (see _mortar_aware_of_being_spotted). react_delay above already
			# accounts for a crew still finishing setup WHEN THE STRIKE WAS CALLED IN (setup_remaining),
			# but that is only a one-time snapshot — if the crew is ordered to relocate again for some
			# other reason before fire_time actually arrives, it used to fire anyway, exactly on schedule,
			# moving or not. Held to the same standard ordinary fire uses (_mortar_shot_this_tick):
			# stationary long enough to have a round laid, aware of being spotted, or facing an unwatched
			# threat closing in right now — the same team-agnostic tier-1 danger signals
			# _decide_mortar_action itself uses, not the player-only _mortar_should_relocate_for_safety.
			# Simply waits, tick after tick, rather than cancelling the mission or resetting the delay —
			# a real crew that's mid-relocation when the moment comes fires the instant it actually stops.
			var responder_endangered: bool = _mortar_aware_of_being_spotted(responder) or _unwatched_threat_closing(responder)
			if responder.seconds_stationary < GameConfig.MORTAR_SETUP_TEARDOWN_TIME or responder_endangered:
				still_pending.append(strike)
				continue
			strike.fired = true
			# Direct user report: the history showed no ammunition expenditure for friendly counter-battery
			# fire. Root cause: a counter-battery reply never went through _launch_mortar_shot (the only
			# other place mortar_rounds_remaining is ever decremented) — it built and fired its own strike
			# entirely outside the ordinary ammo bookkeeping. Spent here, at the moment it actually fires
			# (not when the mission was first called in at _resolve_mortar_counter_battery) — matching
			# ordinary fire's own "spent the instant it's fired, hit or miss" rule exactly.
			responder.mortar_rounds_remaining -= 1
			# The round scatters from the aim point exactly as every other mortar round does (direct user ruling: the variation of where
			# a shot lands from its aim point "should apply in the same way to every mortar shot, regardless of whether or not it is a
			# counter battery shot"): range, how well the fall of shot is observed, and the wind, through the one shared function.
			var aim: Vector2 = strike.get("aim_position", strike.impact_position)
			strike["aim_position"] = aim
			strike["impact_position"] = aim + _mortar_dispersion_offset(responder, strike.target, aim)
			_announce_mortar_shot(responder, aim)
			combat_log.log_counter_battery_incoming(strike.target)
			# The responder's own muzzle blast/trajectory gives ITS position
			# away too, exactly like any other shot — recorded here so
			# _mortar_should_relocate_for_safety picks this up on its own,
			# real next tick, the same unified way as any other fired-from
			# position (no separate scoot-triggering needed here anymore;
			# an earlier version of this fix called _queue_mortar_
			# displacement directly, which is now handled generally instead
			# of duplicated per firing path).
			_last_detected_mortar_fire[responder] = {"position": responder.global_position, "time": scenario_elapsed_time}
			still_pending.append(strike)
			continue
		if scenario_elapsed_time < strike.impact_time:
			still_pending.append(strike)
			continue
		# See _resolve_pending_mortar_shots' own identical comment — the
		# round lands here regardless of the target's own state by now.
		_mortar_impacts.append({"position": strike.impact_position, "time": elapsed_time})
		_assess_civilian_casualties(strike.impact_position, strike.attacker.team)
		_suppress_from_blast(strike.impact_position)
		var target: Unit = strike.target
		if target.state != Unit.State.ACTIVE:
			continue # withdrawn/destroyed since the strike was called in — nothing to hit
		var distance: float = target.global_position.distance_to(strike.impact_position)
		if distance > GameConfig.COUNTER_BATTERY_BLAST_RADIUS:
			combat_log.log_counter_battery_miss(target)
			continue
		# Close enough for shells to actually land near them, hit or not —
		# the crew now knows they've been found and relocates accordingly
		# next time (farther, faster — see Unit.evading_counter_battery).
		target.evading_counter_battery = true
		# COUNTER_BATTERY_BLAST_RADIUS above is still the real hard cutoff
		# for whether a strike can reach the target AT ALL (scope
		# deliberately unchanged here — that constant's "beyond this, the
		# old position is safe" meaning is now load-bearing for several
		# other mortar-relocation mechanics; widening it is a separate,
		# larger design question this doesn't attempt). Within it, the
		# actual chance uses the same real, cover-aware exponential
		# falloff as an ordinary blast's collateral chance (see
		# CombatResolver.blast_casualty_chance's own doc comment) instead
		# of a flat linear ramp to a hard, certain zero right at the
		# boundary — a crew that's displaced most of the way to safety but
		# hasn't fully cleared it faces a real, low, nonzero risk, not
		# either "basically as exposed as if it never moved" (small
		# distances, old linear model) or "impossible" (right at the edge,
		# old linear model) — max_chance=1.0 since a target still THIS
		# close to a landing round has no reason to be less vulnerable
		# than an ordinary bystander caught in the same blast.
		var impact_chance: float = CombatResolver.blast_casualty_chance(distance, 1.0, GameConfig.get_terrain_type_at(target.global_position))
		if randf() < impact_chance:
			var before := UnitCombatStats.before_hit(target)
			target.take_hit(true, [], _known_enemy_positions(target.team), distance)
			if strike.has("attacker") and is_instance_valid(strike.attacker):
				unit_combat_stats.damage(strike.attacker, target, before)
			combat_log.log_counter_battery(target)
			_log_hit_consequence(target, true)
		else:
			combat_log.log_counter_battery_miss(target)
		# The shell physically lands at strike.impact_position regardless
		# of whether it actually caught `target` — real HE fragmentation
		# from that landing spot can still catch some OTHER nearby unit,
		# either side, exactly like an ordinary mortar shot's own
		# collateral check (see _resolve_fire_and_check_bunching's own doc
		# comment for the shared reasoning and cited figures).
		if strike.has("attacker") and is_instance_valid(strike.attacker):
			var collateral_victim := _collateral_victim(strike.impact_position, [strike.attacker, target], GameConfig.MORTAR_BLAST_COLLATERAL_SEARCH_RADIUS,
				func(d: float, pos: Vector2) -> float: return CombatResolver.blast_casualty_chance(d, GameConfig.MORTAR_BLAST_COLLATERAL_MAX_CHANCE, GameConfig.get_terrain_type_at(pos)))
			if collateral_victim != null:
				var collateral_was_active := collateral_victim.state == Unit.State.ACTIVE
				var before_collateral := UnitCombatStats.before_hit(collateral_victim)
				collateral_victim.take_hit(true, _ally_positions_for(collateral_victim), _known_enemy_positions(collateral_victim.team), strike.impact_position.distance_to(collateral_victim.global_position))
				unit_combat_stats.damage(strike.attacker, collateral_victim, before_collateral)
				_assign_discovery_number(collateral_victim)
				combat_log.log_blast_collateral(target, collateral_victim)
				_log_hit_consequence(collateral_victim, collateral_was_active)
	_pending_counter_battery = still_pending


## The single writer of a mortar's own move order — every relocation call
## site (shoot-and-scoot, threat-response, out-of-ammo safety, resupply
## linkup, mortar-hunting) used to repeat the same five-line block, which is
## exactly the kind of duplication that let shoot-and-scoot silently drift
## out of sync with the actual mutex logic. `intent` is recorded in
## _mortar_move_intent so the mortar decision ladder can tell a self-
## preservation walk apart from a mere hunt and keep the former sticky
## against the latter — see that dict's own doc comment. Deliberately does
## NOT touch `activity` — that stays owned by _tick_movement/
## _step_toward_target, which _mortar_aim_point branches on; setting it
## here would start leading a mortar that hasn't actually taken a step yet.
func _issue_mortar_move(m: Unit, dest: Vector2, speed: float, intent: String) -> void:
	m.move_target = dest
	m.has_move_target = true
	m.move_queue.clear()
	m.move_speed = speed
	m.movement_predictable = false
	_mortar_move_intent[m] = intent


## The "now in range/now have a real reason to stand and fight — stop and
## get to work" idiom, previously duplicated in both mortar-hunting
## functions and now also used by _tick_fire's own interrupt-to-fire path.
func _clear_mortar_move(m: Unit) -> void:
	m.has_move_target = false
	m.move_queue.clear() # a stale queued waypoint (an edge-run's later legs) must not outlive the order it belonged to
	m.activity = Unit.Activity.STATIONARY
	_mortar_move_intent.erase(m)


## Relocates `mortar` to wherever it now considers desirable — the nearest
## point with no direct line of sight from any currently-known enemy (real
## concealment, not just reduced spot-chance cover), or, with no known
## threat to hide from, simply the nearest cover: displacing is a standing
## procedure for a shoot-and-scoot crew regardless of whether a threat is
## currently visible, not a purely reactive move. Walks there — real speed,
## real distance, real travel time, no separate cooldown bolted on top (see
## Unit.reload_time) — faster and farther if the crew has actually taken
## counter-battery fire recently (Unit.evading_counter_battery, consumed
## here) OR `force_urgent` is true, slower moving into trees than open
## ground. Returns false (no-op) if there's nowhere better to go right
## now. `intent` is recorded via _issue_mortar_move (see that function's
## own doc comment) so the mortar decision ladder knows WHY this walk is
## happening.
##
## `force_urgent`: the caller's own way of saying "my current position is
## already compromised" for a reason OTHER than counter-battery fire —
## being genuinely spotted, or an unwatched threat closing to overrun
## range with a clear shot (see _decide_mortar_action's own tier ladder).
## Urgent searches FARTHER out (GameConfig.CONCEALMENT_SEARCH_RINGS_
## URGENT_M) and moves FASTER (MORTAR_RELOCATE_SPEED_URGENT) — exactly
## the response "the ground right around me is no longer safe, whatever
## found me here can probably still reach nearby candidates too" calls
## for, the same reasoning already established for counter-battery.
## Without this, a mortar with a threat already bearing down on it (most
## sharply: one that's completely out of ammunition, with no reason left
## to trade concealment quality for speed at all) used to get exactly the
## same unhurried, nearby-ring relocation as one just doing routine
## shoot-and-scoot housekeeping with nothing actually threatening it —
## occasionally not fast or far enough to actually get clear.
func _relocate_mortar(mortar: Unit, intent: String, force_urgent: bool = false) -> bool:
	var urgent: bool = mortar.evading_counter_battery or force_urgent
	if mortar.evading_counter_battery:
		_mortar_counter_battery_time[mortar] = scenario_elapsed_time # remembered: the flag is consumed just below, and a later flee reports it
	mortar.evading_counter_battery = false
	# A real, reported oscillation, confirmed by tracing the FRIENDLY
	# mortar's own out-of-ammo relocations directly: unspotted and
	# unthreatened (force_urgent false), that tier calls this function
	# again on literally every tick has_move_target reads false — which,
	# given each short relocation leg only takes a tick or two to walk at
	# this project's own tactical time scale, meant a fresh relocation
	# was being considered again before the crew had even finished
	# settling into the last one. With no real threat forcing genuine
	# progress, most reachable candidates score similarly, and the
	# search's own weighted-random pick among top-scoring candidates
	# (deliberate — see nearest_hidden_point's own doc comment on why a
	# crew that always ran to the single best spot would itself be a
	# predictable pattern) then wanders among several comparably-good
	# local optima instead of settling — confirmed directly: the crew
	# revisited the same handful of points 50-100m apart repeatedly, even
	# reversing its own immediately-prior leg twice, over about 30
	# real-world seconds. The existing recently-visited exclusion
	# (MORTAR_RECENT_POSITION_EXCLUSION_RADIUS) doesn't catch this at
	# all — it's deliberately small (20m, not the 150m an earlier version
	# used) specifically so it doesn't starve the search on this
	# project's own short 75-160m ring scale (see that constant's own
	# doc comment), well under the 50-100m distances this pattern
	# actually revisits at.
	#
	# GameConfig.MORTAR_VOLUNTARY_RELOCATION_COOLDOWN (180 tactical
	# seconds, its own dedicated constant — see that constant's own doc
	# comment for why reusing the much-shorter MORTAR_SETUP_TEARDOWN_TIME
	# was tried first and measured as barely different from no gate at
	# all) is the minimum dwell time before a NON-URGENT relocation
	# reconsiders moving at all. A genuinely urgent one (spotted, a real
	# threat closing, just took counter-battery fire) is untouched:
	# survival is never throttled by how recently the crew last moved.
	if not urgent and mortar.seconds_stationary < GameConfig.MORTAR_VOLUNTARY_RELOCATION_COOLDOWN:
		return false
	# See MORTAR_BUNCHING_SATISFIED_RADIUS's own doc comment — a real,
	# reported regression: with nothing actually urgent driving this
	# relocation, don't even search for one if every known sibling is
	# already well clear. Without this, a routine (non-urgent) relocation
	# call re-fires every time this mortar finishes its current leg
	# (out of ammo with nothing to shoot is checked EVERY tick), and once
	# the search's own bunching term is scored against the real 300m
	# doctrinal target, "improve my distance from a sibling that's ALSO
	# constantly moving" almost always looks technically achievable,
	# producing exactly the erratic short-hop churn this guards against.
	if not urgent:
		var siblings := _sibling_mortar_positions(mortar)
		if not siblings.is_empty():
			var already_dispersed := true
			for p in siblings:
				if mortar.global_position.distance_to(p) < GameConfig.MORTAR_BUNCHING_SATISFIED_RADIUS:
					already_dispersed = false
					break
			if already_dispersed:
				return false
	var plan: Dictionary = _mortar_relocation_plan(mortar, urgent)
	if plan.is_empty():
		return false
	_issue_mortar_move(mortar, plan.destination, plan.speed, intent)
	return true


## A genuine last resort, reached only when the crew is already under
## real, urgent pressure (spotted, an unwatched threat closing, or just
## hit by counter-battery fire — every call site here is already inside
## one of those branches) AND _relocate_mortar's own leashed, concealment-
## seeking search has ALREADY come up completely empty. Direct user
## request: "Let's allow the mortar to run away off the left edge of the
## map. But if it does, let's consider it to have retreated from the
## battle. It is safe but can no longer participate. So it should only do
## that if there is no reasonable alternative. For example, an enemy
## squad may be chasing it so it can't stay on the map."
##
## Deliberately reuses Unit.order_retreat completely unchanged rather
## than inventing a separate mechanism: fleeing off the map is a genuine
## one-way retreat, exactly like a general retreat's own RETREATING
## state, and gets every one of today's own retreat fixes for free (skip
## an unnecessary cover detour if the straight run to the edge is
## already clear, never detour backward once already past the safe line,
## the real total-trip-aware cover search if a detour genuinely is
## needed first). Once this returns, `m.state != ACTIVE`, so
## _update_mortar_decisions stops processing this crew from the very
## next tick on — permanently out of the fight, matching "can no longer
## participate" exactly.
##
## Direct user clarification: the full off-map commitment is only for a
## crew already CLOSE to its own edge — "If enemy squads are chasing the
## mortar, but it is still far from the map edge, it should act to preserve
## itself. This self preservation may well involve retreating towards the
## map edge. However, full retreat off of the map is not yet required at
## that point." Farther than GameConfig.MORTAR_FLEE_COMMIT_DISTANCE from the
## edge, this instead issues an ordinary, still-ACTIVE fall-back leg toward
## it (_mortar_edge_run_destination) and returns, so the decision ladder
## re-evaluates on arrival: a real hiding place may have turned up by then
## (the ordinary relocation gets first refusal every time), and if the
## threat is still there and the crew is now close enough, THEN this
## commits. An edge-run leg that can't be laid out at all (every candidate
## blocked) falls back to the old immediate commitment rather than leaving
## the crew with nothing to do.
func _mortar_flee_as_last_resort(m: Unit) -> void:
	# Seen by an unarmed observer (a drone, a spotter) and nothing else: hiding is worth trying (the
	# caller already did), but running for the edge is not — stay put.
	if _mortar_troubled_only_by_unarmed_observers(m):
		_mortar_reasoning[m] = {"tier": "Preserve self", "detail": "Only a drone or spotter has sighted us — no place to hide, but not leaving the map over it."}
		return
	if absf(m.retreat_target_x - m.global_position.x) > GameConfig.MORTAR_FLEE_COMMIT_DISTANCE:
		var legs: Array[Vector2] = _mortar_edge_run_legs(m)
		if not legs.is_empty():
			var detail := "Nowhere safe to conceal — falling back toward the map edge, not yet committed to leaving."
			if m.team == Unit.Team.PLAYER and _mortar_reasoning.get(m, {}).get("detail", "") != detail:
				combat_log.log_mortar_falling_back_toward_edge(m)
			# At the mortar's own retreat_speed, not the faster relocation
			# speed: direct user requirement that the movement take the same
			# time it always has, only without the RETREATING state — and
			# every leg queued at once (move_queue) so it's one continuous
			# run, never a stop-and-reconsider between legs while chased.
			_issue_mortar_move(m, legs[0], m.retreat_speed, "evade")
			for i in range(1, legs.size()):
				m.move_queue.append(legs[i])
			_mortar_reasoning[m] = {"tier": "Preserve self", "detail": detail}
			return
	# Why, for the debug snapshots (see Unit.order_retreat's `reason`): the
	# conditions that got the ladder here.
	var why: PackedStringArray = []
	if m.mortar_rounds_remaining <= 0:
		why.append("out of ammunition")
	if m.is_visible:
		why.append("spotted")
	if m.evading_counter_battery:
		why.append("under counter-battery fire")
	if why.is_empty():
		why.append("a threat closing")
	# Who had it in sight, and whether counter-battery fire had found it lately, so "why did it flee" can be answered from the snapshot.
	var seen_by: PackedStringArray = []
	var opposing_units: Array[Unit] = enemy_units if m.team == Unit.Team.PLAYER else player_units
	for u in opposing_units:
		var one: Array[Unit] = [u]
		if u.state == Unit.State.ACTIVE and CombatResolver.has_live_observer(m, one, false, true):
			seen_by.append(u.display_name() + (" (unarmed)" if u.kind == Unit.Kind.DRONE or u.kind == Unit.Kind.SPOTTER else " (armed)"))
	if not seen_by.is_empty():
		why.append("in sight of " + ", ".join(seen_by))
	if scenario_elapsed_time - float(_mortar_counter_battery_time.get(m, -INF)) < 120.0:
		why.append("counter-battery fire in the last two minutes")
	m.order_retreat(_known_enemy_positions_for_retreat(m.team), [], "Fled off the map as a last resort: %s, and no safe place to relocate to." % ", ".join(why))
	if m.team == Unit.Team.PLAYER:
		combat_log.log_mortar_fled_off_map(m)
	_mortar_reasoning[m] = {"tier": "Preserve self", "detail": "No safe relocation option remained nearby — fleeing off the map."}


## The whole fall-back run toward `m`'s own edge, as a chain of waypoints
## (GameConfig.MORTAR_EDGE_RUN_LEG apart) ending once the crew is inside
## GameConfig.MORTAR_FLEE_COMMIT_DISTANCE of it — the zone where a crew
## still being chased commits to the off-map retreat instead. Each leg is
## bent sideways away from the nearest known threat by the same steering
## _step_retreat's own final dash uses (_retreat_avoidance_offset), so a
## chaser off to one side pushes the run the other way instead of running
## parallel to it. A mortar can never enter a building and shouldn't be
## routed through the river outside its crossing, so for each leg the bent
## candidate is tried first, then a few plain lateral alternatives, taking
## the first that's clear. A leg none of them could lay out ends the chain
## there; an empty result (not even the first leg) makes the caller commit
## to the off-map retreat instead.
func _mortar_edge_run_legs(m: Unit) -> Array[Vector2]:
	var dir_x: float = -1.0 if m.team == Unit.Team.PLAYER else 1.0
	var steer: float = _retreat_avoidance_offset(m) * GameConfig.RETREAT_THREAT_STEER_FRACTION
	var legs: Array[Vector2] = []
	var from: Vector2 = m.global_position
	while absf(m.retreat_target_x - from.x) > GameConfig.MORTAR_FLEE_COMMIT_DISTANCE and legs.size() < 20:
		var leg: float = minf(GameConfig.MORTAR_EDGE_RUN_LEG, absf(m.retreat_target_x - from.x))
		var next: Vector2 = Vector2.INF
		for y_offset in [steer * leg, 0.0, leg * 0.5, -leg * 0.5, leg, -leg]:
			var candidate: Vector2 = GameConfig.clamp_to_operating_area(Vector2(from.x + dir_x * leg, from.y + y_offset))
			if GameConfig.is_building_at(candidate):
				continue
			if GameConfig.path_crosses_building(from, candidate) or GameConfig.path_crosses_river(from, candidate):
				continue
			next = candidate
			break
		if next == Vector2.INF or absf(m.retreat_target_x - next.x) >= absf(m.retreat_target_x - from.x) - 1.0:
			break # blocked, or the operating-area clamp stopped it actually getting closer
		legs.append(next)
		from = next
	return legs


## Whether the relocation _relocate_mortar just issued (m.move_target,
## still fresh — this must be called immediately after a successful
## _relocate_mortar call, before anything else can overwrite it) actually
## achieves real concealment, not just "some candidate was found." Direct,
## live-caught correction, the proactive-decision counterpart to the same
## fix in Unit.order_retreat (see that function's own doc comment for the
## full incident): _relocate_mortar's own underlying search never returns
## "nothing" (same "movement must never be starved to zero" principle as
## every relocation search in this project) — it always hands back SOME
## point, even one still fully exposed to the exact threat that triggered
## the relocation. Treating "a candidate was found" as "the crew is now
## safe" let a mortar keep accepting these hollow relocations indefinitely
## instead of ever concluding there was genuinely nowhere left to hide and
## fleeing off the map, exactly as _mortar_flee_as_last_resort already
## exists to do. Every call site below now requires this to ALSO be true
## before accepting a `_relocate_mortar` success, falling through to
## _mortar_flee_as_last_resort exactly as if _relocate_mortar itself had
## returned false.
func _mortar_relocation_actually_helps(m: Unit) -> bool:
	for p in _known_enemy_positions(m.team):
		if GameConfig.has_direct_los(p, m.move_target):
			return false
	return true


## The destination/speed-picking half of _relocate_mortar, split out so
## _queue_mortar_displacement (below) can compute the SAME plan without
## issuing it immediately — see that function's own doc comment for why.
## Empty Dictionary means "nowhere better to go right now."
##
## A real, previously-reported failure mode: this used to search purely
## outward from the mortar's OWN current position with no notion of
## "home" at all, so a string of successive safety scoots — pure
## nearest-hidden-point geometry, each one individually reasonable —
## could drift the crew further and further from the actual defensible
## position over the course of a battle, eventually ending up isolated
## somewhere far off (a previously-reported case: "leaving the hill,
## going North"), at which point _update_friendly_squad_positioning's
## own mortar-screening logic (see _nearest_unscreened_mortar_threat)
## would send a squad chasing after it too — the "everyone follows the
## mortar" symptom is a direct downstream consequence of the mortar's
## OWN destination never having a leash in the first place. Now rejects
## (returns {}, causing a hold in place rather than a bad move) any
## candidate beyond GameConfig.MORTAR_HUNT_MAX_RANGE_FROM_HOME of
## _friendly_mortar_home_position — the SAME cap, and the SAME real
## reasoning, already established for hunting (a real crew won't range
## indefinitely far from where it was actually deployed), applied here
## too: self-preservation is not a reason to abandon supporting distance
## of the position it exists to help defend, any more than chasing an
## enemy mortar is. Player-only — there's no tracked home position for
## the enemy's own mortar(s) at all to check against.
## Where a Ukrainian mortar crew that has to move in order to set up should go. Direct user instruction: "The crew would think about
## different places it could go and form an idea about what would be tactically good. Distance should also be a consideration."
## It looks at places in rings around `center` out to `radius` (and `center` itself), keeps those it may set up at (not a building, the red
## area or the river), gives each a value (see _setup_position_value) less what the walk there costs, and takes the best that it can
## actually walk to (a route exists, or a straight line crosses no building). Returns {"point": p, "legs": [...]} (legs: the waypoints to
## walk, ending at the point), or {} if there is nowhere.
const SETUP_RING_RADII_M: Array[float] = [0.0, 150.0, 350.0, 600.0, 900.0, 1300.0, 1800.0]
const SETUP_ANGLES_PER_RING: int = 14
const SETUP_FINALISTS: int = 6
const SETUP_HIDDEN_WEIGHT: float = 1.5 # a place no known enemy can see, against one they all can
const SETUP_COVER_WEIGHT: float = 0.4 # standing in trees
const SETUP_STANDOFF_WEIGHT: float = 1.0 # distance from the nearest known enemy, up to the overrun range's worth
const SETUP_OVERRUN_PENALTY: float = 2.0 # inside the range at which a crew is overrun
const SETUP_IN_RANGE_WEIGHT: float = 0.8 # able to reach the nearest known enemy with its rounds, but not so close it is overrun
const SETUP_LEASH_PENALTY: float = 3.0 # beyond how far from home the crew is allowed to stray
const SETUP_DISTANCE_COST_PER_KM: float = 1.0 # a kilometre's walk costs two-thirds of what concealment from every known enemy is worth
const SETUP_KNOWN_ENEMIES_CONSIDERED: int = 5
const SETUP_LINKUP_RADIUS_M: float = 350.0 # how far from an inbound run's position the crew will look for a better place to take delivery

func _best_setup_position(m: Unit, center: Vector2, radius_m: float) -> Dictionary:
	var known: Array[Vector2] = _known_enemy_positions(m.team)
	known.sort_custom(func(a, b): return a.distance_to(m.global_position) < b.distance_to(m.global_position))
	if known.size() > SETUP_KNOWN_ENEMIES_CONSIDERED:
		known.resize(SETUP_KNOWN_ENEMIES_CONSIDERED)
	var home: Vector2 = _mortar_home_position(m)
	var leash: float = GameConfig.mortar_home_leash(m.team) if not is_inf(home.x) else INF
	var scored: Array = []
	for radius in SETUP_RING_RADII_M:
		if radius > radius_m:
			break
		var count: int = 1 if radius == 0.0 else SETUP_ANGLES_PER_RING
		for k in count:
			var angle: float = TAU * float(k) / float(count)
			var p: Vector2 = GameConfig.clamp_to_operating_area(center + Vector2(cos(angle), sin(angle)) * radius * GameConfig.PIXELS_PER_METER)
			if GameConfig.mortar_barred_at(p, m.team) or GameConfig.is_river_at(p):
				continue
			scored.append({"point": p, "value": _setup_position_value(m, p, known, home, leash)})
	scored.sort_custom(func(a, b): return a.value > b.value)
	for i in mini(scored.size(), SETUP_FINALISTS):
		var p: Vector2 = scored[i].point
		var legs: Array[Vector2] = GameConfig.mortar_route_to_point(m.global_position, p)
		if legs.is_empty():
			if GameConfig.path_crosses_building(m.global_position, p):
				continue # no way to walk there
			legs.append(p)
		return {"point": p, "legs": legs, "value": scored[i].value}
	return {}


## How good `p` is as a place for `m` to set up, less the walk there from where it stands: concealment from the known enemies (the
## fraction that cannot see it), cover, standoff from the nearest one (and a heavy penalty inside the range it overruns a crew), whether
## its rounds reach the nearest one, and staying within its leash of home. With no known enemy the first and last three terms
## carry no information and only cover, leash and distance count.
func _setup_position_value(m: Unit, p: Vector2, known: Array[Vector2], home: Vector2, leash: float) -> float:
	var value := 0.0
	if not known.is_empty():
		var hidden := 0
		var nearest := INF
		for e in known:
			if not GameConfig.has_direct_los(p, e):
				hidden += 1
			nearest = minf(nearest, p.distance_to(e))
		value += SETUP_HIDDEN_WEIGHT * float(hidden) / float(known.size())
		value += SETUP_STANDOFF_WEIGHT * clampf(nearest / GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE, 0.0, 1.0)
		if nearest < GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE:
			value -= SETUP_OVERRUN_PENALTY
		elif nearest <= GameConfig.mortar_max_range(m.team) * 0.9:
			value += SETUP_IN_RANGE_WEIGHT
	if GameConfig.is_in_cover(GameConfig.get_terrain_type_at(p)):
		value += SETUP_COVER_WEIGHT
	if not is_inf(home.x) and p.distance_to(home) > leash:
		value -= SETUP_LEASH_PENALTY
	value -= SETUP_DISTANCE_COST_PER_KM * m.global_position.distance_to(p) / GameConfig.PIXELS_PER_METER / 1000.0
	return value


func _mortar_relocation_plan(mortar: Unit, urgent: bool) -> Dictionary:
	var threats := _known_enemy_positions(mortar.team)
	var recent: Array[Vector2] = []
	recent.assign(_mortar_recent_positions.get(mortar, []))
	# The home-range leash is now enforced INSIDE the search itself (see
	# GameConfig.nearest_hidden_point's own doc comment) so a candidate
	# beyond it is never proposed in the first place — checking only the
	# final result used to let a search that's oblivious to home (the
	# reverse-slope candidate especially, anchored to threat bearing, not
	# position) repeatedly fail outright near the leash's own edge and
	# later settle for whatever different, often much closer, candidate a
	# later tick happened to find instead. Enemy has no tracked home
	# position at all, so it gets no cap here, same as before.
	# Enemy mortars used to get no leash here ("Enemy has no tracked home position at all"), and one
	# hiding from our fire wandered clear across the map into our rear: "Enemy mortar just charged into
	# our rear area. That's crazy." ("It should have the same constraints as the friendly mortar.") Each
	# is now held to the same leash from where it was deployed (_enemy_mortar_homes).
	var home_position: Vector2 = _mortar_home_position(mortar)
	var home_leash: float = GameConfig.mortar_home_leash(mortar.team) if not is_inf(home_position.x) else INF
	# See _mortar_max_distance_from_home's own doc comment — a floor, not
	# just a ceiling: whatever the best distance from home a PRIOR
	# relocation this same danger episode already achieved, don't let a
	# fresh, differently-triggered search (evade reacting to some other
	# threat, most commonly) walk the crew back toward the position that
	# got it compromised in the first place.
	var min_distance_from_home: float = _mortar_max_distance_from_home.get(mortar, 0.0) if mortar.team == Unit.Team.PLAYER else 0.0
	# See _sibling_mortar_positions's own doc comment — try hard not to
	# converge on another same-team mortar's position or destination.
	# Threaded through BOTH branches below — a real, empirically-confirmed
	# mistake in an earlier version of this fix assumed the no-known-
	# threats fallback (nearest_cover_point) was a rare edge case not
	# worth the trouble, but it's actually the COMMON path for exactly
	# the scenario this feature exists to fix: "spotted with nothing to
	# shoot" fires whenever the PLAYER has found this mortar, regardless
	# of whether the mortar has any idea where the player's own units
	# are — under drone-heavy player doctrine that's routinely true, so
	# `threats` (known PLAYER positions, from the enemy's own point of
	# view) is very often empty right when concealment-seeking matters
	# most. A SECOND mistake found the same way: nearest_cover_point's
	# own `avoid_positions` (passed here in an earlier version) only
	# excludes a whole cover zone that literally CONTAINS a sibling's
	# position — no help at all when a sibling isn't standing inside any
	# mapped cover zone, which a mortar squeezed against the map edge
	# with sparse cover very often isn't. Passed as its own dedicated
	# `bunch_avoid_positions` parameter instead (a real, radius-based
	# check — see its own doc comment), leaving the zone-based
	# `avoid_positions` slot for whatever else might use it.
	var siblings: Array[Vector2] = _sibling_mortar_positions(mortar)
	# See GameConfig.MORTAR_NO_REVERSAL_RADIUS's own doc comment — the
	# WHOLE remembered history, passed to BOTH branches. Confirmed
	# directly via a live trace that this project's own enemy mortars
	# route through the ring search (nearest_hidden_point) essentially
	# every time, not the no-known-threats fallback (nearest_cover_
	# point) — `threats` (this side's own knowledge of the opposing
	# side) is very rarely actually empty once real contact has been
	# made, unlike the narrower case an earlier version of this
	# reasoning assumed. Safe from the historical search-starvation
	# failure mode at either function's own reachable scale — see
	# _ring_search_hidden_point's own doc comment for why.
	# See GameConfig.MORTAR_REVERSAL_DIRECTION_DOT_THRESHOLD's own doc
	# comment — the direction of the immediately-prior COMPLETED leg
	# (second-to-last remembered destination to the last one), so a
	# fresh candidate that undoes it outright gets discouraged even if
	# it doesn't happen to land near any single remembered point.
	# Exempted whenever the crew has fired at least once since that
	# prior leg — a real fire mission in between means the next move is
	# a genuine, fresh shoot-and-scoot decision, not backtracking, per
	# the user's own direct correction.
	var travel_direction: Vector2 = Vector2.ZERO
	if recent.size() >= 2 and not _mortar_fired_since_relocation.get(mortar, false):
		var raw_direction: Vector2 = recent[-1] - recent[-2]
		if raw_direction.length() > 1.0:
			travel_direction = raw_direction.normalized()
	# See GameConfig.nearest_hidden_point's own doc comment on
	# `firing_point` — direct user correction: "the top priority of
	# scooting is not being close to the point you fired from." Whatever
	# tier actually triggered THIS relocation, if this crew's own firing
	# signature is still live (mortar_recently_detected_firing), a fresh
	# destination should also want real distance from that exact
	# coordinate, not just from wherever it happens to be standing right
	# now — the two can differ by up to COUNTER_BATTERY_BLAST_RADIUS
	# itself (see _mortar_should_relocate_for_safety's own stopping
	# condition), and a ring-search candidate merely far from `from` can
	# still land close to the actual firing point if `from` had already
	# drifted back toward it. Applies to either team uniformly — this is
	# the same shared search both sides already route through, and a real
	# crew of either side wants distance from where it just gave itself
	# away regardless of which side it's on.
	var firing_point: Vector2 = Vector2.INF
	if mortar_recently_detected_firing(mortar):
		firing_point = _last_detected_mortar_fire[mortar].position
	var destination: Vector2 = (
		GameConfig.nearest_hidden_point(mortar.global_position, threats, true, urgent, recent, home_position, home_leash, min_distance_from_home, siblings, recent, travel_direction, firing_point, GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE, _keeps_clear_of_populated(mortar))
		if not threats.is_empty()
		else GameConfig.nearest_cover_point(mortar.global_position, 0.0, true, [], [], siblings, recent, travel_direction, firing_point, Vector2.INF, _keeps_clear_of_populated(mortar))
	)
	if destination == mortar.global_position:
		return {}
	# Kept as a safety net — should no longer normally trigger now that
	# the search itself respects the leash, but nearest_cover_point's own
	# path (the no-known-threats branch above) has no leash awareness at
	# all, so this still matters for that case.
	if not is_inf(home_position.x) and destination.distance_to(home_position) > home_leash:
		return {}
	var speed: float = GameConfig.MORTAR_RELOCATE_SPEED_URGENT if urgent else GameConfig.MORTAR_RELOCATE_SPEED
	if GameConfig.get_terrain_type_at(destination) == GameConfig.TerrainType.TREES:
		speed *= GameConfig.MORTAR_RELOCATE_TREES_MULTIPLIER
	_remember_mortar_position(mortar, destination)
	if mortar.team == Unit.Team.PLAYER:
		var achieved: float = destination.distance_to(home_position)
		_mortar_max_distance_from_home[mortar] = max(_mortar_max_distance_from_home.get(mortar, 0.0), achieved)
	return {"destination": destination, "speed": speed}


## See GameConfig.MORTAR_RECENT_POSITION_MEMORY_COUNT's own doc comment —
## a short, rolling memory of this mortar's own last few relocation
## destinations, fed back into nearest_hidden_point so it doesn't keep
## finding its way back onto a position the crew only just vacated. Oldest
## entry drops off once a new one pushes the list past the cap; recorded
## here (the single place a relocation plan is actually accepted) rather
## than at the call site so a rejected plan (home-range cap, no threats)
## never pollutes the history with a destination that was never really used.
func _remember_mortar_position(mortar: Unit, destination: Vector2) -> void:
	var history: Array[Vector2] = []
	history.assign(_mortar_recent_positions.get(mortar, []))
	history.append(destination)
	while history.size() > GameConfig.MORTAR_RECENT_POSITION_MEMORY_COUNT:
		history.pop_front()
	_mortar_recent_positions[mortar] = history
	# See _mortar_fired_since_relocation's own doc comment — a fresh leg
	# is starting, so whatever fire mission (if any) happened during the
	# PREVIOUS leg no longer exempts the NEXT one.
	_mortar_fired_since_relocation[mortar] = false


## A shoot-and-scoot crew doesn't vanish from its firing position the
## instant the round is away — breaking the tube down and shouldering it
## takes real time before the crew is actually walking anywhere (see
## GameConfig.MORTAR_SETUP_TEARDOWN_TIME's own doc comment). The
## destination/speed are decided NOW, off the threat picture at the moment
## of firing (matching _relocate_mortar's own immediate behavior for every
## other trigger) — only the ACT of setting out is delayed. See
## _resolve_pending_mortar_displacement for where that delay actually
## elapses and the real move order gets issued. `_pending_mortar_
## displacement` is keyed by mortar, so a fresh shot before this one
## resolves simply replaces it outright — a crew that's already fired
## again clearly wasn't still standing around packing up the old plan.
func _queue_mortar_displacement(mortar: Unit, intent: String, urgent: bool) -> void:
	var plan: Dictionary = _mortar_relocation_plan(mortar, urgent)
	if plan.is_empty():
		return
	_pending_mortar_displacement[mortar] = {
		"destination": plan.destination, "speed": plan.speed, "intent": intent,
		"urgent": urgent, "ready_time": scenario_elapsed_time + GameConfig.MORTAR_SETUP_TEARDOWN_TIME,
	}


## The other half of _queue_mortar_displacement's delay. Skips (and drops)
## a pending entry only when a GENUINELY higher-priority tier-1 self-
## preservation move (the same sticky-intent list _decide_mortar_action's
## own step 0b uses — evade/conceal/out_of_ammo/linkup) has since claimed
## this tick's move; the routine scoot it would have overwritten really is
## moot then, and a fresh _decide_mortar_action pass picks up cleanly from
## wherever that more urgent move leaves off.
##
## A real, previously-reported failure mode: this used to drop the pending
## scoot for ANY current move order at all, `has_move_target` alone, with
## no check on what actually set it — so a mortar that kept re-engaging
## known enemy mortars (tier 2, "hunt" — LOWER priority than the
## self-preservation this scoot itself represents) could pick up a fresh
## hunt order in the 30-second window before the scoot was ever due to
## start, silently starving it every single time and leaving the crew
## standing in plain sight after every shot despite a shoot-and-scoot
## doctrine that should have moved it. Only the tier-1 sticky intents
## actually outrank a routine scoot; anything else (a mere hunt, most
## sharply) gets overwritten by the scoot instead of blocking it.
func _resolve_pending_mortar_displacement() -> void:
	for mortar in _pending_mortar_displacement.keys():
		var pending: Dictionary = _pending_mortar_displacement[mortar]
		if scenario_elapsed_time < pending.ready_time:
			continue
		_pending_mortar_displacement.erase(mortar)
		if mortar.state != Unit.State.ACTIVE or _fall_back_orders.has(mortar):
			continue
		if mortar.has_move_target and _mortar_move_intent.get(mortar, "") in ["evade", "conceal", "out_of_ammo", "linkup"]:
			continue
		_issue_mortar_move(mortar, pending.destination, pending.speed, pending.intent)
		combat_log.log_relocate(mortar, pending.urgent)


func _log_hit_consequence(unit: Unit, was_active_before: bool) -> void:
	if unit.ammo_cooked_off:
		unit.ammo_cooked_off = false
		combat_log.log_mortar_ammo_cookoff(unit)
	if unit.state == Unit.State.DESTROYED:
		combat_log.log_destroyed(unit)
	elif unit.state == Unit.State.RETREATING and was_active_before:
		if unit.kind == Unit.Kind.MORTAR or unit.kind == Unit.Kind.DRONE_TEAM:
			combat_log.log_crew_abandoned(unit)
		else:
			combat_log.log_threshold_retreat(unit)
			_log_wounded_evacuation_outcome(unit)
	if unit.reported_issue and not unit.reported_issue_logged:
		unit.reported_issue_logged = true
		combat_log.log_reports_issue(unit)
	if unit.sought_cover and not unit.sought_cover_logged:
		unit.sought_cover_logged = true
		combat_log.log_seeking_cover(unit)
	if unit.bolted_for_cover:
		unit.bolted_for_cover = false
		combat_log.log_bolts_for_cover(unit)


## A SQUAD can only fire at a target within its own engagement range AND
## with its own actual line of sight — a building between attacker and
## target blocks it outright, not just "harder to hit" (that's what the
## cover multiplier is for).
##
## A MORTAR has no LOS requirement of its own — it fires on spotter-relayed
## information, so e.is_targetable() (a LIVE fact — see _refresh_visibility,
## maintained every tick by whether some friendly currently has line of
## sight, not a permanent flag) already covers whether anyone can see it at
## all. It DOES have a real maximum range (GameConfig.mortar_max_range,
## split by side — see its own doc comment) — a mortar tube only throws a
## shell so far, regardless of who's spotting.
##
## Mortars are the highest-value target on the battlefield for both sides —
## if one is a legal target at all, it's always preferred over a squad or
## the spotter, for either a squad's direct fire or another mortar's own
## targeting. Only an ACTIVE mortar earns that priority, though — one that's
## already been hit has had its crew abandon the gun (see
## Unit._apply_crew_casualties), so a RETREATING mortar is just fleeing
## survivors, no more of a threat than any other routed unit.
##
## Among non-mortar candidates, a SQUAD's own direct fire still just picks
## uniformly at random (a rifle squad isn't out here doing fire-support
## math) — but a MORTAR's choice among them is a genuine weighted pick via
## _enemy_target_value, not uniform: a fuller unit is a juicier target
## (more casualties per hit — see Unit.take_hit's own from_mortar
## scaling), and a target currently dangerous to the mortar's own side
## matters too, whether or not it happens to also be full-strength. Both
## real considerations, weighted rather than either one deciding outright
## — a damaged-but-threatening squad can still outweigh an
## undamaged-but-harmless one.
##
## _pick_target itself is NOT idempotent for a mortar — it rolls real
## randomness (the ammo hold-fire chance, the weighted target pick among
## squads) — so calling it directly more than once for the same mortar in
## the same tick can get two different answers. _mortar_shot_this_tick,
## immediately below, is the memoizing wrapper every mortar-relevant call
## site should go through instead; only that function and _tick_fire
## (which populates the cache when it actually resolves a shot) are
## expected to call this directly for a mortar.


## The one place anything asks "does this mortar have a shot RIGHT NOW" —
## every mortar-relevant caller (the resupply-linkup check, the mortar
## decision ladder's own tier-1 gate) routes through here instead of
## calling _pick_target directly, so the same tick's answer is consistent
## everywhere it's asked. Returns the cached result from _mortar_tick_shot
## if _tick_fire already resolved one THIS tick (the common case — most
## ticks a mortar's fire_timer hasn't reached zero yet, so _tick_fire
## returns before ever reaching _pick_target, and there is nothing to
## reuse); otherwise computes it now, lazily, and caches it for whoever
## else asks later in the same tick. See _mortar_tick_shot's own doc
## comment for why this must be cleared at the top of _process, before
## _tick_fire runs, not merely read here.
func _mortar_shot_this_tick(m: Unit, opposing: Array[Unit]) -> Unit:
	var cached: Dictionary = _mortar_tick_shot.get(m, {})
	if cached.get("resolved", false):
		return cached.target
	# A crew that's only just stopped moving hasn't actually finished
	# emplacing yet — see GameConfig.MORTAR_SETUP_TEARDOWN_TIME's own doc
	# comment. seconds_stationary already tracks exactly this (reset to 0
	# the instant Unit.activity last read MOVING — see _tick_movement), so
	# a mortar that's never moved at all (seconds_stationary starts at a
	# huge default) is never held back by this on its very first shot.
	#
	# A mortar whose CURRENT position is already compromised (see
	# _mortar_should_relocate_for_safety's own doc comment) doesn't get to
	# just keep firing from there regardless — a real crew that knows it's
	# been found stops trading shots and displaces first. This is the
	# actual fix for "always shooting, never scooting": the old model
	# tried to queue a displacement AFTER firing, which a fast enough
	# reload cycle could perpetually re-trigger and reset before it ever
	# actually departed. Gating the NEXT shot instead — no new shot is
	# even attempted while a real displacement is owed — means there's no
	# timer to reset in the first place.
	var target: Unit = null
	if m.seconds_stationary >= GameConfig.MORTAR_SETUP_TEARDOWN_TIME and not _mortar_should_relocate_for_safety(m):
		target = _pick_target(m, opposing)
	_mortar_tick_shot[m] = {"resolved": true, "target": target}
	return target


## True if a real enemy mortar could plausibly still hit `m` at its CURRENT
## position — the actual reason a mortar should feel compelled to relocate,
## replacing every event-based stand-in this project has tried before it
## ("did I just fire," "how many enemy mortars exist somewhere on the
## map"). Two real conditions, both required:
##
## 1. `m` gave its own position away recently (mortar_recently_detected_
##    firing — the same muzzle-blast/trajectory detection channel
##    _known_friendly_mortar_position and the opposing side's own hunting
##    already rely on, not a new concept) AND hasn't since put real
##    distance between itself and where that happened. Distance, not just
##    time, matters: a crew that displaces even a little is no longer
##    standing where a return shot is aimed, regardless of how much of
##    the detection's own relevance window (MORTAR_FIRE_DETECTION_EXPIRY)
##    is left — reusing COUNTER_BATTERY_BLAST_RADIUS here isn't a
##    coincidence, it's the SAME "close enough to the firing spot to
##    still be caught" real distance _resolve_pending_counter_battery's
##    own impact check already uses.
## 2. At least GameConfig.MORTAR_STANDING_THREAT_COUNT REAL enemy mortars
##    (see _enemy_mortars_in_range — ground truth, not "known") are
##    actually within striking reach.
##
## Direct user correction, after a live incident (a mortar hit shortly
## after firing): "Right after firing, getting away from firing point
## should be top priority if there are enemy mortars... only nearby enemy
## squads should [outrank it], or the edge of the map." An EARLIER version
## of this additionally required the mortars in condition 2 to be KNOWN
## (detected/sighted) before bothering at all, and even then only
## overrode a deliberate hold-position doctrine once density compounded
## past GameConfig.MORTAR_DENSITY_FORCE_SCOOT_COUNT — reasonable-sounding,
## but backwards from how real shoot-and-scoot doctrine actually works:
## the whole point is that a crew can never be sure whether it was
## detected, so the mere fact the enemy fields mortars capable of
## reaching this position at all is itself the reason to assume
## counter-battery risk, not proof a specific tube spotted this one.
## Doctrine no longer gates whether this fires at all — and, despite an
## older version of this comment claiming otherwise, `m.shoot_and_scoot`
## itself no longer reads anywhere in the current tier ladder either (see
## _decide_mortar_action's own call site, whose comment says so directly);
## it is currently a vestigial field, set at spawn but never consulted.
##
## Direct user correction, later, after a live report of an enemy mortar
## being wiped out with uncanny speed and consistency by walking-fire
## (see _mortar_dispersion_offset's own convergence, which requires the
## target to keep sitting still to benefit an attacker's fire correction):
## "Also, enemy mortars did not scoot after shooting" — this used to be
## PLAYER-only, matching every other doctrine-aware mortar check's "enemy
## may differ" scope, but a stationary target never breaks a
## walking-fire correction once started, and the enemy fields mortars for
## the friendly side to feel exactly the same counter-battery risk from —
## there is no real reason left for this one to stay asymmetric once
## reported. Both sides now feel it identically.
func _mortar_should_relocate_for_safety(m: Unit) -> bool:
	if unit_doctrine_for(m).risk != "inherit":
		return false
	if not mortar_recently_detected_firing(m):
		return false
	var last_fire: Dictionary = _last_detected_mortar_fire[m]
	if m.global_position.distance_to(last_fire.position) >= GameConfig.COUNTER_BATTERY_BLAST_RADIUS:
		return false # already put real distance between itself and where it was last given away
	return _enemy_mortars_in_range(m.global_position, m.team) >= GameConfig.MORTAR_STANDING_THREAT_COUNT


## Ground truth, not "known" — see _known_enemy_mortars_in_range's own doc
## comment for that distinction and why it still matters separately (it
## drives how URGENTLY a compromised crew responds, not whether it
## bothers at all — see _decide_mortar_action's own call site). Used only
## by _mortar_should_relocate_for_safety's own baseline gate: real
## shoot-and-scoot doctrine assumes counter-battery risk from the mere
## fact the enemy fields mortars able to reach this position, not from
## confirmation a specific tube detected this one — a crew never gets
## that confirmation in real life either. `team` is the mortar's OWN team
## (whichever side is asking "can the other guy reach me here") — counts
## the OPPOSING side's mortars, at the opposing side's own max range.
func _enemy_mortars_in_range(pos: Vector2, team: Unit.Team = Unit.Team.PLAYER) -> int:
	var opposing_team: Unit.Team = Unit.Team.ENEMY if team == Unit.Team.PLAYER else Unit.Team.PLAYER
	var opposing: Array[Unit] = enemy_units if team == Unit.Team.PLAYER else player_units
	var count := 0
	var range_px: float = GameConfig.mortar_max_range(opposing_team)
	for u in opposing:
		if u.kind == Unit.Kind.MORTAR and u.state == Unit.State.ACTIVE and pos.distance_to(u.global_position) <= range_px:
			count += 1
	return count


## Original doctrine keeps the legacy overrides. Other profiles compare
## legal targets on the shared score scale; all choices record their evidence.
func _pick_target(unit: Unit, enemies: Array[Unit]) -> Unit:
	var candidates: Array[Unit] = []
	for e in enemies:
		if not e.is_targetable():
			continue
		# Neither a mortar's plunging HE round nor a rifleman's aimed fire
		# can realistically engage a small quadcopter loitering at
		# DRONE_ALTITUDE_M (300m) — a mortar has no way to aim at or fuze
		# against a moving aerial point target at all, and ordinary small
		# arms (no shotgun loads or fire-control optics in this era) are
		# reported as fundamentally unable to track and hit something this
		# small and fast even at short range, altitude aside (see the
		# design doc's own revision-log entry for the real-world sourcing
		# behind this — a live bug report: enemy mortars were seen firing
		# HE rounds at a drone hundreds of meters away).
		if e.kind == Unit.Kind.DRONE:
			continue
		# Direct user report: "Enemy mortars were still shooting at our spotter when enemy squads were
		# nearby, and friendly squads were not. Instead, the enemy should have tasked an enemy squad with
		# that, as the squad could have done it easily." Reuses the exact same availability check
		# _spotter_hunt_candidate already makes for whether a squad WILL go deal with a known spotter
		# (near enough, free, not already fighting a real squad) rather than a separate, looser proximity
		# check that could drift out of sync with what that tier actually does. A squad engaging the
		# spotter directly (this function's own SQUAD branch, a few lines below) is exactly the desired
		# outcome and is untouched — this only stops a MORTAR from also spending a shell on an unarmed
		# target ground forces are already free and positioned to deal with.
		if e.kind == Unit.Kind.SPOTTER and unit.kind == Unit.Kind.MORTAR and unit.team == Unit.Team.ENEMY and _spotter_hunt_candidate() != null:
			continue
		if unit.kind == Unit.Kind.SQUAD:
			if unit.global_position.distance_to(e.global_position) > GameConfig.SQUAD_ENGAGEMENT_RANGE:
				continue
			if not GameConfig.has_direct_los(unit.global_position, e.global_position):
				continue
		elif unit.kind == Unit.Kind.MORTAR:
			if unit.global_position.distance_to(e.global_position) > GameConfig.mortar_max_range(unit.team):
				continue
		candidates.append(e)
	if _risk_holds.has(unit) and unit.state == Unit.State.ACTIVE:
		return _record_target_choice(unit, candidates, null, "Self-risk policy: displacing or withholding fire.")
	if candidates.is_empty():
		return _record_target_choice(unit, candidates, null, "No eligible visible target.")

	var mortar_candidates: Array[Unit] = candidates.filter(func(c): return c.kind == Unit.Kind.MORTAR and c.state == Unit.State.ACTIVE)
	# A mortar choosing among targets does not count an enemy mortar it has watched dodging as one to be shot at first: see
	# GameConfig.MORTAR_EVASIVE_TARGET_VALUE_MULTIPLIER. It stays a candidate (at a fraction of its value), but another mortar, or a squad,
	# is chosen ahead of it.
	var evasive_mortars: Array[Unit] = []
	if unit.kind == Unit.Kind.MORTAR:
		evasive_mortars = mortar_candidates.filter(func(c): return _mortar_looks_evasive(c))
		if not evasive_mortars.is_empty():
			mortar_candidates = mortar_candidates.filter(func(c): return not evasive_mortars.has(c))
	if not mortar_candidates.is_empty() and profile_for(unit.team).id == "baseline" and unit_doctrine_for(unit).targeting == "inherit":
		var chosen: Unit = mortar_candidates[randi() % mortar_candidates.size()]
		return _record_target_choice(unit, candidates, chosen, "Original rule: active mortars override other targets; uniform choice among mortars.", {"conditional_probability": 1.0 / mortar_candidates.size()})
	if unit.kind == Unit.Kind.MORTAR:
		var gate_evidence: Dictionary = {}
		# Limited ammunition means a real choice, not just "shoot whatever's
		# best" — but "ammo is not a consideration when shooting at an enemy
		# mortar, that shot should be taken; it's only a consideration when
		# shooting at squads" is exactly why this only runs once mortar_
		# candidates (above) is already known empty. A genuine sliding-scale
		# PROBABILITY of holding fire on a squad target, not a hard
		# threshold — "five shots remaining should never be a magical
		# number" — combining how scarce ammo already is
		# (_mortar_ammo_scarcity) with how soon resupply is actually
		# expected (_mortar_resupply_urgency): a full load never hesitates
		# regardless of urgency, an empty-handed mortar with nothing coming
		# holds almost every time, and relief expected soon makes firing
		# more attractive even while genuinely low. See GameConfig.
		# MORTAR_RESUPPLY_URGENCY_HORIZON_MINUTES for the full reasoning.
		#
		# A candidate this close is a physical threat to the crew right now —
		# self-preservation (tier 1) always wins regardless of ammo,
		# danger-to-the-force, or any hunting opportunity below. Computed
		# once, up front, since it now gates more than just the final
		# override at the bottom of this branch. Requires actual line of
		# sight back to the crew's own position, same as _unwatched_threat_
		# closing — a nearby candidate that can't actually see this mortar
		# isn't genuinely closing in on it, whatever else it might be doing.
		var any_overrun := false
		for c in candidates:
			if unit.global_position.distance_to(c.global_position) <= GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE and GameConfig.has_direct_los(c.global_position, unit.global_position):
				any_overrun = true
				break

		var enemy_mortar_fix: Dictionary = _mortar_hunt_fix_for(unit)

		# This isn't mortar-hunting-specific logic — it's the general
		# principle that a known, more valuable target worth maneuvering
		# for can be worth forgoing a lesser one already in hand, gated on
		# it actually being safe to try: nothing close enough to force a
		# shot regardless (any_overrun, above). Deliberately NOT gated on
		# unit.is_visible (whether THIS crew has been spotted) — being
		# spotted doesn't make the enemy mortar any less worth pursuing,
		# and holding fire here doesn't strand an exposed crew doing
		# nothing: if the hold leaves this mortar with no shot,
		# _decide_mortar_action's own tier 1 ("Spotted... relocating for
		# cover") reacts to that exact same spotted state on this exact
		# same tick regardless of whether a shot was taken this tick. A
		# genuine value comparison, not a hard rule: the chance of holding
		# this shot scales with how much more the known opportunity is
		# actually worth than the best candidate available right now, both
		# read off the exact same _enemy_target_value scale everything
		# else here uses. TARGET_PRIORITY_MORTAR so thoroughly outweighs
		# any single squad's own value that this reliably (not absolutely)
		# favors the pursuit whenever a fix is live and safe to chase —
		# that falls naturally out of the value gap already encoded in
		# GameConfig, not a special case bolted on for this one target
		# kind. The only reason today's only such opportunity happens to
		# be an enemy mortar is that mortars are the only kind anything
		# currently tracks a remembered, out-of-reach fix on at all.
		if not enemy_mortar_fix.is_empty() and unit_doctrine_for(unit).targeting in ["inherit", "mortars"] and mortar_candidates.is_empty() and not any_overrun and not _mortar_fix_is_evasive(unit, enemy_mortar_fix):
			# A remembered position, not a live Unit — its value is
			# discounted by how much this side actually trusts the fix, a
			# confidence axis _enemy_target_value has no notion of (that
			# function only ever sees real, currently-known units).
			var known_target_value: float = GameConfig.TARGET_PRIORITY_MORTAR * (1.0 if enemy_mortar_fix.trusted else GameConfig.TARGET_PRIORITY_MORTAR_LEAD_DISCOUNT)
			if profile_for(unit.team).id != "baseline":
				known_target_value = (10.0 * _profile_weight(unit.team, "counter_mortar") + 10.0 * _profile_weight(unit.team, "pressure")) * (1.0 if enemy_mortar_fix.trusted else GameConfig.TARGET_PRIORITY_MORTAR_LEAD_DISCOUNT)
			var best_available_value := 0.0
			for c in candidates:
				best_available_value = max(best_available_value, _enemy_target_value(unit, c))
			var hold_for_pursuit_chance: float = known_target_value / (known_target_value + best_available_value)
			hold_for_pursuit_chance *= _mortar_squad_order_hold_factor(unit)
			var pursuit_roll: float = 0.5 if profile_for(unit.team).deterministic else randf()
			gate_evidence["pursuit"] = {"hold_probability": hold_for_pursuit_chance, "roll_or_cutoff": pursuit_roll}
			if pursuit_roll < hold_for_pursuit_chance:
				return _record_target_choice(unit, candidates, null, "Hold this shot to pursue a remembered mortar opportunity.", {"hold_probability": hold_for_pursuit_chance, "roll_or_cutoff": pursuit_roll, "known_opportunity_value": known_target_value, "best_available_value": best_available_value, "trusted_fix": enemy_mortar_fix.trusted})

		# Firing on a mere squad reveals this position — and finding ONE
		# enemy mortar (a live candidate excluded via mortar_candidates
		# above, or a remembered fix/lead — enemy_mortar_fix) does NOT mean
		# the picture is complete: this side can field up to ENEMY_MORTAR_
		# COUNT_MAX mortars at once (see roll_enemy_force_size), so a known
		# fix on ONE of them says nothing about whether a completely
		# different one is still sitting there unaccounted for. Deliberately
		# NOT gated on enemy_mortar_fix.is_empty() for exactly that reason —
		# an earlier version of this hold was, and stopped applying the
		# instant ANY lead existed at all, even a stale one on an unrelated
		# mortar, which is why a mortar still got caught blind by a SECOND,
		# genuinely undiscovered one despite this hold already being in
		# place. See GameConfig.MORTAR_UNKNOWN_ENEMY_HOLD_FIRE_CHANCE's own
		# doc comment for why this scales with _mortar_existence_confidence()
		# rather than a flat timer, and why it's player-only for now.
		if unit.team == Unit.Team.PLAYER and mortar_candidates.is_empty() and evasive_mortars.is_empty() and not any_overrun:
			var unknown_mortar_hold_chance: float = GameConfig.MORTAR_UNKNOWN_ENEMY_HOLD_FIRE_CHANCE * _mortar_existence_confidence()
			unknown_mortar_hold_chance *= _mortar_squad_order_hold_factor(unit)
			var unknown_mortar_roll: float = 0.5 if profile_for(unit.team).deterministic else randf()
			gate_evidence["unknown_enemy_mortar"] = {"hold_probability": unknown_mortar_hold_chance, "roll_or_cutoff": unknown_mortar_roll, "mortar_existence_confidence": _mortar_existence_confidence()}
			if unknown_mortar_roll < unknown_mortar_hold_chance:
				return _record_target_choice(unit, candidates, null, "Holding fire — haven't ruled out another enemy mortar yet; still assessing before revealing this position.", gate_evidence)

		# A known enemy mortar's own claim on ammo conservation is handled
		# entirely by the value-based pursuit hold above now, not by a flat
		# reserved-rounds count here — a fixed reserve (formerly a few
		# rounds, trusted vs. untrusted) is an arbitrary number with no real
		# relationship to how much the opportunity is actually worth,
		# exactly the kind of "five shots remaining should never be a
		# magical number" case the rest of this ammo model deliberately
		# avoids elsewhere. General ammo scarcity below is about the
		# mortar's own dwindling supply overall, independent of any specific
		# known target.
		var scarcity: float = _mortar_ammo_scarcity(unit)
		var urgency: float = _mortar_resupply_urgency(unit)
		var hold_fire_chance: float = scarcity * (1.0 - urgency)
		# Tier 3 of the mortar decision ladder ("destroy dangerous squads")
		# — a genuinely different axis from the overrun-range override just
		# below (that one measures danger to the CREW, distance to the
		# mortar itself; this one measures danger to the FORCE, via
		# _target_danger_to_force's own distance-to-nearest-friendly). Only
		# gated on having a round to fire, same reasoning as the overrun
		# override below — this only overrides the CHOICE to hold fire.
		if hold_fire_chance > 0.0 and unit.mortar_rounds_remaining > 0:
			var best_danger := 0.0
			for c in candidates:
				best_danger = max(best_danger, _target_danger_to_force(unit, c))
			hold_fire_chance *= 1.0 - GameConfig.MORTAR_DANGER_HOLD_FIRE_OVERRIDE * (best_danger / GameConfig.TARGET_PRIORITY_SQUAD_MAX)
		# Conserving ammo for later stops making sense the instant "later"
		# might not come — a squad closing to within genuine overrun range
		# is reason enough to take the shot regardless of how scarce ammo
		# is or how far off resupply might be. Gated on actually HAVING a
		# round left — this only overrides the CHOICE to hold fire, not
		# the hard fact of having nothing to fire; without this guard a
		# truly empty mortar being approached would still read back as
		# "has a shot" to anything calling _pick_target directly (e.g.
		# _decide_mortar_action's own step 0 "is there something to
		# shoot" check), when _tick_fire's own separate, earlier
		# mortar_rounds_remaining <= 0 gate means it could never actually
		# fire regardless of what this function returns.
		if hold_fire_chance > 0.0 and unit.mortar_rounds_remaining > 0 and any_overrun:
			hold_fire_chance = 0.0
		# The commander's squad-fire order (set_mortar_squad_fire_order) - only
		# when this shot would be at squads; an enemy mortar candidate is never
		# ammo-gated by the order.
		hold_fire_chance *= _mortar_squad_order_hold_factor(unit, mortar_candidates.is_empty())
		hold_fire_chance = clampf(hold_fire_chance * _profile_weight(unit.team, "conservation"), 0.0, 1.0)
		var ammo_roll: float = 0.5 if profile_for(unit.team).deterministic else randf()
		if ammo_roll < hold_fire_chance:
			return _record_target_choice(unit, candidates, null, "Hold fire to conserve ammunition.", {"hold_probability": hold_fire_chance, "roll_or_cutoff": ammo_roll, "scarcity": scarcity, "resupply_urgency": urgency})
		gate_evidence["ammunition"] = {"hold_probability": hold_fire_chance, "roll_or_cutoff": ammo_roll, "scarcity": scarcity, "resupply_urgency": urgency}
		var picked: Unit = _weighted_mortar_target_pick(unit, candidates, gate_evidence)
		if picked != null and evasive_mortars.has(picked) and not any_overrun:
			var dodge_roll: float = 0.5 if profile_for(unit.team).deterministic else randf()
			gate_evidence["target_dodging"] = {"hold_probability": GameConfig.MORTAR_EVASIVE_HOLD_FIRE_CHANCE, "roll_or_cutoff": dodge_roll}
			if dodge_roll < GameConfig.MORTAR_EVASIVE_HOLD_FIRE_CHANCE:
				return _record_target_choice(unit, candidates, null, "Holding fire: the mortar has been seen moving unpredictably, so a round 40 s in the air would land where it no longer is.", gate_evidence)
		return _apply_town_reluctance(unit, candidates, picked, any_overrun, gate_evidence)
	if profile_for(unit.team).id != "baseline" or unit_doctrine_for(unit).targeting != "inherit":
		return _weighted_mortar_target_pick(unit, candidates)
	var chosen: Unit = candidates[randi() % candidates.size()]
	return _record_target_choice(unit, candidates, chosen, "Original squad rule: uniform choice among eligible targets.", {"conditional_probability": 1.0 / candidates.size()})


## 0.0 (nothing pending, or the pending run's own transit is still
## GameConfig.MORTAR_RESUPPLY_URGENCY_HORIZON_MINUTES or more away) to 1.0
## (a real run is already en route, OR one has finished transit and is
## staged waiting for ammo to draw down — either way, as certain as it
## gets short of rounds already being in the tube), ramping linearly as
## the pending run's own transit time elapses. Drives _pick_target's own
## sliding-scale ammo conservation — see GameConfig.MORTAR_RESUPPLY_
## URGENCY_HORIZON_MINUTES's own comment for the full reasoning. Also the
## source for CasualtyDashboard's live resupply readout (see
## mortar_resupply_status).
func _mortar_resupply_urgency(mortar: Unit) -> float:
	if _active_resupply_run_for(mortar) != null:
		return 1.0
	var record: Dictionary = _mortar_resupply.get(mortar, {})
	if record.is_empty():
		return 0.0
	var minutes_left: float = max(record.arrival_time - scenario_elapsed_time, 0.0) / 60.0
	return clamp(1.0 - minutes_left / GameConfig.MORTAR_RESUPPLY_URGENCY_HORIZON_MINUTES, 0.0, 1.0)


## How much this mortar's own remaining ammo, on its own (independent of
## any resupply timing), argues for holding back a squad shot — see
## GameConfig.MORTAR_RESUPPLY_URGENCY_HORIZON_MINUTES's own comment for the
## full reasoning. 0.0 at a full GameConfig.MORTAR_STARTING_AMMO load
## (spend freely), ramping linearly to 1.0 as rounds approach zero. A known
## enemy mortar's own claim on ammo is handled separately, by the
## value-based pursuit hold in _pick_target — this is only ever about the
## mortar's own dwindling supply in general, independent of any specific
## known target.
func _mortar_ammo_scarcity(mortar: Unit) -> float:
	return clamp(1.0 - float(mortar.mortar_rounds_remaining) / float(GameConfig.MORTAR_STARTING_AMMO), 0.0, 1.0)


## How many rounds `mortar` commits to firing at `target` in this burst
## before its reload/displace cycle — see GameConfig.MORTAR_BURST_MAX_
## SHOTS/_CLOSE_RANGE for the outer ceiling and its close-range exception.
## Direct user requirement, four real factors combined:
## - Range: closer favors a bigger burst, sliding from 0 at max range to 1
##   at zero range — reversed from every other mortar range check in this
##   file (those all gate on "too far," this one rewards "close").
## - Ammo willingness: reuses the EXACT scarcity/resupply-urgency composite
##   _pick_target's own hold-fire chance already computes (see
##   GameConfig.MORTAR_RESUPPLY_URGENCY_HORIZON_MINUTES's doc comment) —
##   "resupply expected soon should read like having more ammo" is already
##   precisely what that composite means, so this reuses it rather than
##   inventing a second, parallel notion of the same thing.
## Range and ammo willingness are averaged: a mortar with full ammo at long
## range fires a middling burst, one with little ammo up close likewise.
## Mapped to an integer via probabilistic rounding (this project's own
## "no magic thresholds" convention — see MORTAR_RESUPPLY_DELAY's sampled
## distribution for the same idea) rather than a hard round(), so a score
## of e.g. 2.4 fires 3 shots 40% of the time instead of 2 shots always.
func _mortar_burst_shot_count(mortar: Unit, target: Unit) -> int:
	var range_to_target: float = mortar.global_position.distance_to(target.global_position)
	var range_score: float = clamp(1.0 - range_to_target / GameConfig.mortar_max_range(mortar.team), 0.0, 1.0)
	var ammo_willingness: float = 1.0 - _mortar_ammo_scarcity(mortar) * (1.0 - _mortar_resupply_urgency(mortar))
	var score: float = clamp((range_score + ammo_willingness) / 2.0, 0.0, 1.0)

	var max_shots: int = GameConfig.MORTAR_BURST_CLOSE_RANGE_MAX_SHOTS if range_to_target < GameConfig.MORTAR_BURST_CLOSE_RANGE else GameConfig.MORTAR_BURST_MAX_SHOTS
	var raw: float = 1.0 + score * float(max_shots - 1)
	var shots: int = int(floor(raw))
	if randf() < raw - float(shots):
		shots += 1
	return clampi(shots, 1, max_shots)


## Public accessor for CasualtyDashboard's live per-mortar readout — never
## reveals the true underlying arrival time as some kind of privileged
## knowledge the player shouldn't have (this IS the player's own mortar's
## status board, not the enemy's), just a friendly summary of the same
## state _mortar_resupply_urgency already computes from.
func mortar_resupply_status(mortar: Unit) -> Dictionary:
	if _active_resupply_run_for(mortar) != null:
		return {"pending": true, "in_transit": true, "staged": false}
	var record: Dictionary = _mortar_resupply.get(mortar, {})
	if record.is_empty():
		return {"pending": false}
	if record.get("staged", false):
		# Transit is done and the run is genuinely just waiting, off-map,
		# for ammo to draw down to GameConfig.MORTAR_RESUPPLY_REORDER_
		# POINT — distinct from "in transit," so the player isn't told a
		# truck is 0 minutes out when it's actually parked at the ready.
		return {"pending": true, "in_transit": false, "staged": true}
	var minutes_left: float = max(record.arrival_time - scenario_elapsed_time, 0.0) / 60.0
	return {"pending": true, "in_transit": false, "staged": false, "minutes_until_next": minutes_left}


## Public accessor for CasualtyDashboard's enemy mortar row: true if
## `mortar` has fired recently enough (GameConfig.MORTAR_FIRE_DETECTION_
## EXPIRY) that muzzle-flash/trajectory detection alone — the same
## mechanism the enemy's own counter-battery chase already relies on (see
## _known_friendly_mortar_position) — would tell the player's side it's
## currently in action, even with no visual sighting at all. Firing gives
## away THAT a mortar is active and roughly where from, not its remaining
## strength or exact condition with anything like a visual sighting's
## confidence, so this only ever unlocks the coarse "it's in action" fact
## in the dashboard, never casualty detail — see
## CasualtyDashboard._enemy_mortar_status_text.
func mortar_recently_detected_firing(mortar: Unit) -> bool:
	var info: Dictionary = _last_detected_mortar_fire.get(mortar, {})
	if info.is_empty():
		return false
	return scenario_elapsed_time - info.time <= GameConfig.MORTAR_FIRE_DETECTION_EXPIRY


## Public accessor for CasualtyDashboard's enemy mortar row: true the
## instant a mortar has EVER been detected firing, permanently, unlike
## mortar_recently_detected_firing's own EXPIRY-windowed version above —
## this is "do we know this specific mortar exists at all," not "is it
## still fresh enough to read as currently active." A stale detection
## still means the player's side has learned this mortar is real, even
## once too old to say anything about whether it's still in action right
## now.
func mortar_ever_detected_firing(mortar: Unit) -> bool:
	return not _last_detected_mortar_fire.get(mortar, {}).is_empty()


## Minutes since `mortar` was last detected firing, for the same "detected
## firing" dashboard case above — INF if it's never been detected at all
## (callers should already have checked mortar_recently_detected_firing).
func mortar_minutes_since_detected_firing(mortar: Unit) -> float:
	var info: Dictionary = _last_detected_mortar_fire.get(mortar, {})
	if info.is_empty():
		return INF
	return (scenario_elapsed_time - info.time) / 60.0


## How many DISTINCT enemy mortars this side actually knows exist and are
## still a live threat, within striking range of `pos` — visual sighting,
## a lingering last-known position from one, or a muzzle-flash/trajectory
## detection lead, the same "known" bar _known_enemy_mortar_lead already
## uses, never omniscient ground truth. Position resolved by the
## strongest signal actually available for that mortar (live position
## while visible; its last confirmed sighting; failing that, where it was
## standing the last time it was detected firing) — see GameConfig.
## MORTAR_DENSITY_FORCE_SCOOT_COUNT's own doc comment for why this count
## specifically (not just "is there a known enemy mortar at all") is what
## should be driving how urgently a crew needs to keep displacing.
##
## `team` is the mortar's OWN team (whichever side is asking "how many of the other guy's mortars do I
## know about"); default preserves every existing PLAYER-perspective call site. Direct user report, given
## alongside the same live incident that made _mortar_should_relocate_for_safety symmetric: enemy mortars
## get the identical density-driven urgency a friendly crew already had, using the ENEMY's OWN knowledge
## of PLAYER mortars (enemy_known_state/enemy_has_been_sighted/enemy_known_position) rather than checking
## what the PLAYER happens to know — the original, PLAYER-only version was actively checking the wrong
## side's knowledge for that direction, not merely omitting a feature.
func _known_enemy_mortars_in_range(pos: Vector2, team: Unit.Team = Unit.Team.PLAYER) -> int:
	var opposing: Array[Unit] = enemy_units if team == Unit.Team.PLAYER else player_units
	var count := 0
	for u in opposing:
		if u.kind != Unit.Kind.MORTAR:
			continue
		# Knowledge audit (2026-09-27): this function's own doc comment already promises "never omniscient
		# ground truth" — u.state was exactly that. A mortar the other side still believes ACTIVE or
		# RETREATING must keep counting even if it has since been destroyed unseen; a never-known one is
		# excluded by the branches below regardless (the known-state field defaults to ACTIVE, but none of
		# is_visible / has-been-sighted / mortar_ever_detected_firing will be true for it).
		var known_state: Unit.State = u.player_known_state if team == Unit.Team.PLAYER else u.enemy_known_state
		if known_state != Unit.State.ACTIVE and known_state != Unit.State.RETREATING:
			continue
		var has_been_sighted: bool = u.player_has_been_sighted if team == Unit.Team.PLAYER else u.enemy_has_been_sighted
		var known_position: Vector2 = u.player_known_position if team == Unit.Team.PLAYER else u.enemy_known_position
		var known_pos: Vector2
		if u.is_visible:
			known_pos = u.global_position
		elif has_been_sighted:
			known_pos = known_position
		elif mortar_ever_detected_firing(u):
			known_pos = _last_detected_mortar_fire[u].position
		else:
			continue
		if known_pos.distance_to(pos) <= GameConfig.mortar_max_range(u.team):
			count += 1
	return count


## How dangerous `target` is to `unit`'s OWN side right now, from a
## MORTAR's perspective — zero for anything that isn't a squad currently
## ACTIVE (a spotter, an already-fleeing mortar crew, or a squad that's
## itself RETREATING poses no real danger to anyone — it's pulling out,
## not fighting, so proximity to a friendly alone shouldn't read as a
## threat; matches the same state == ACTIVE gate _drone_search_target
## already applies to its own squad-danger scoring), otherwise
## _squad_danger_priority judged against `assessing_unit`'s OWN side (not
## unconditionally the player's — an enemy mortar weighing this cares
## about danger to the ENEMY side). Extracted as its own function so
## _enemy_target_value's target-ranking use and _pick_target's own ammo-
## conservation override (GameConfig.MORTAR_DANGER_HOLD_FIRE_OVERRIDE)
## can never drift apart on what "dangerous" means — in particular, so the
## override can never be fooled into reading a RETREATING squad as a
## reason to burn ammo, the same trap _enemy_target_value is already built
## to avoid.
func _target_danger_to_force(assessing_unit: Unit, target: Unit) -> float:
	var is_active_squad: bool = target.kind == Unit.Kind.SQUAD and target.state == Unit.State.ACTIVE
	return _squad_danger_priority(target, assessing_unit.team) if is_active_squad else 0.0


## How much destroying/neutralizing `target` is actually worth, from
## `assessing_unit`'s own side's perspective — a general notion any
## friendly unit's decisionmaking can weigh options against, not a
## mortar-specific one bolted onto one particular behavior. An ACTIVE
## mortar is worth taking out almost on sight, a fixed high value
## (GameConfig.TARGET_PRIORITY_MORTAR) essentially regardless of its own
## remaining strength — a crew-served indirect-fire weapon's worth isn't
## really about how many of its crew are still standing, unlike a rifle
## squad's. A SQUAD's value instead combines what it would actually cost
## to lose (casualty_value, its own current pip count — more people
## actually there to hit) with how much danger it currently poses to
## assessing_unit's own side (_target_danger_to_force) — a damaged-but-
## threatening squad can still outweigh an undamaged-but-harmless one.
## Both squad terms land on roughly the same 0-10ish scale by construction
## (max pips 9, TARGET_PRIORITY_SQUAD_MAX 10), so equal weights
## (GameConfig.MORTAR_TARGET_CASUALTY_WEIGHT/_DANGER_WEIGHT) already
## balance them without needing wildly different magnitudes. Everything
## else (spotter, drone team, drone, resupply run — nothing currently
## weighs engaging any of them this way) reads as 0, not because they're
## worthless in reality, just because nothing needs an opinion on them yet.
func _enemy_target_value(assessing_unit: Unit, target: Unit) -> float:
	var value: float = _enemy_target_value_unscaled(assessing_unit, target)
	if assessing_unit.kind == Unit.Kind.MORTAR and _mortar_looks_evasive(target):
		value *= GameConfig.MORTAR_EVASIVE_TARGET_VALUE_MULTIPLIER # a mortar seen dodging is worth a fraction: see its constant
	return value


func _enemy_target_value_unscaled(assessing_unit: Unit, target: Unit) -> float:
	if unit_doctrine_for(assessing_unit).targeting != "inherit":
		return _type_target_score(assessing_unit, target)
	if profile_for(assessing_unit.team).id != "baseline":
		var score := 0.0
		for value in target_score_components(assessing_unit, target).values():
			score += float(value)
		return maxf(score, 0.1)
	if target.kind == Unit.Kind.MORTAR and target.state == Unit.State.ACTIVE:
		return GameConfig.TARGET_PRIORITY_MORTAR
	if target.kind == Unit.Kind.SQUAD:
		var casualty_value: float = float(target.pips)
		var danger_value: float = _target_danger_to_force(assessing_unit, target)
		var value: float = GameConfig.MORTAR_TARGET_CASUALTY_WEIGHT * casualty_value + GameConfig.MORTAR_TARGET_DANGER_WEIGHT * danger_value
		if _mortar_is_reluctant_toward(assessing_unit, target):
			value *= GameConfig.MORTAR_TOWN_TARGET_VALUE_MULTIPLIER # two squads, one in the town: probably the one outside
		return value
	return 0.0


## Whether `shooter` (the Ukrainian mortar) is reluctant to fire at `target`: a squad within GameConfig.MORTAR_TOWN_RADIUS_M of a building.
func _mortar_is_reluctant_toward(shooter: Unit, target: Unit) -> bool:
	return shooter.kind == Unit.Kind.MORTAR and shooter.team == Unit.Team.PLAYER and target.kind == Unit.Kind.SQUAD 		and GameConfig.near_building(target.global_position, GameConfig.MORTAR_TOWN_RADIUS_M)


## The Ukrainian mortar's reluctance to fire into a town, as a held-back shot: when the target it picked is a squad in a town, the round is
## held MORTAR_TOWN_HOLD_FIRE_CHANCE of the time, less as that squad is a danger to our own people (a squad about to overrun them is shot at
## regardless), and never when the crew itself is in overrun danger. Reluctant, not forbidden.
func _apply_town_reluctance(unit: Unit, candidates: Array[Unit], picked: Unit, overrun: bool, evidence: Dictionary) -> Unit:
	if picked == null or overrun or not _mortar_is_reluctant_toward(unit, picked):
		return picked
	var danger_share: float = clampf(_target_danger_to_force(unit, picked) / GameConfig.TARGET_PRIORITY_SQUAD_MAX, 0.0, 1.0)
	var hold: float = GameConfig.MORTAR_TOWN_HOLD_FIRE_CHANCE * (1.0 - danger_share)
	var roll: float = 0.5 if profile_for(unit.team).deterministic else randf()
	if roll < hold:
		return _record_target_choice(unit, candidates, null, "Reluctant to fire into the town: the target is within %d m of a building." % int(GameConfig.MORTAR_TOWN_RADIUS_M), evidence.merged({"town_hold_probability": hold, "roll_or_cutoff": roll}))
	return picked


## A genuine weighted-random choice among `candidates` — not a
## deterministic "always the single best one" — real fire-mission
## targeting isn't perfectly rational, and this keeps the mortar's target
## choice from being trivially predictable the way always picking the
## objective maximum would be. The actual draw weight is each candidate's
## own _enemy_target_value SQUARED, not the bare score: a clearly
## standout threat should dominate the roll much more reliably than
## "best odds of several comparable options" (a linear weight let a
## target scoring nearly twice any rival still lose the roll more often
## than not — see the 2026-09-10 "very dangerous, should have been
## getting a lot of attention" report, where a 13.57 lost to a 9.38 on a
## 24% linear share). Squaring keeps this a genuine weighted-random
## choice, not a hard "always pick the max" rule, while making a real
## standout win far more often than an also-ran does. Every candidate's
## value is guaranteed positive (a targetable unit always has at least 1
## pip), so no separate floor is needed to keep every weight meaningfully
## positive.
func _weighted_mortar_target_pick(unit: Unit, candidates: Array[Unit], evidence: Dictionary = {}) -> Unit:
	var weights: Array[float] = []
	var total := 0.0
	for c in candidates:
		var w: float = _enemy_target_value(unit, c)
		var squared: float = w * w
		weights.append(squared)
		total += squared
	if profile_for(unit.team).deterministic or unit_doctrine_for(unit).targeting != "inherit":
		var best := 0
		for i in weights.size():
			if weights[i] > weights[best]:
				best = i
		return _record_target_choice(unit, candidates, candidates[best], "Highest target score; ties use stable candidate order.", evidence)
	var roll: float = randf() * total
	var cumulative := 0.0
	for i in candidates.size():
		cumulative += weights[i]
		if roll <= cumulative:
			return _record_target_choice(unit, candidates, candidates[i], "Weighted random target choice; a lower score can win.", evidence.merged({"conditional_probability": weights[i] / total if total > 0.0 else 1.0, "weighted_roll": roll, "total_weight": total}))
	return _record_target_choice(unit, candidates, candidates[candidates.size() - 1], "Weighted target choice: numerical fallback.", evidence)


func _prune_fire_flashes() -> void:
	_fire_flashes = _fire_flashes.filter(func(f): return elapsed_time - f.time <= FLASH_DURATION)
	_mortar_impacts = _mortar_impacts.filter(func(m): return elapsed_time - m.time <= IMPACT_EFFECT_DURATION)


func _check_battle_end() -> void:
	if _all_done_fighting(player_units) or _all_done_fighting(enemy_units):
		_end_battle()
	elif scenario_elapsed_time >= GameConfig.BATTLE_TIME_LIMIT:
		# Direct user report from a live battle that ran to the limit with both
		# sides still on the field: "should have been scored as a stalemate. It
		# says Position held." Running out the clock with each side still
		# holding ground decided nothing — neither held nor lost, the same
		# ruling as the stagnation timeout below. A side that is already
		# broken (nobody ACTIVE — all withdrawn, destroyed or still pulling
		# out) is a different story: the fight WAS decided, and the ordinary
		# held/lost verdict stands.
		if _has_active_units(player_units) and _has_active_units(enemy_units):
			combat_log.add_entry("--- Time limit reached with neither side driven from the field: stalemate ---")
			_ended_by_stalemate = true
		_end_battle()
	elif _seconds_since_last_shot >= STAGNATION_TIMEOUT and not _anyone_moving() and not _any_armed_mortar_remains():
		combat_log.add_entry("--- Battle stalemated: no movement or fire for %ds ---" % int(STAGNATION_TIMEOUT))
		_ended_by_stalemate = true
		_end_battle()


## Direct user correction, from a real battle: "the stalemate code must have
## triggered... does the enemy still have a mortar? If the enemy has a
## mortar, the stalemate should not trigger." STAGNATION_TIMEOUT's own doc
## comment already assumed this ("e.g. both mortars gone") without the code
## actually checking it — an ACTIVE mortar with rounds left can sit
## perfectly still, holding fire (no target, conserving ammo, waiting out an
## unknown-enemy-mortar hold), for far longer than 15 real seconds without
## anything about the battle actually being decided: it can still fire the
## instant a target or the hold-fire roll changes. True for either side, not
## just the enemy — a player mortar with ammo left has the same standing.
##
## Direct user correction, from a later real battle that ended in a stalemate
## with the player's mortar ACTIVE but out of ammunition: "The player has a
## mortar. It is currently out of ammo, but that's not a reason to let
## stalemate happen." A dry crew that is still in the fight is waiting on its
## resupply, which is a continuous pipeline (see request_mortar_resupply /
## _update_mortar_resupply: one run always on order for an ACTIVE mortar, and
## the next requested the instant a run commits, even a failed one), so it WILL
## fire again — nothing about the battle is decided. Such a mortar therefore
## counts as still in the fight while a resupply is on order (`_mortar_resupply`
## has it). One with no resupply coming at all (contact never made, so nothing
## was ever requested) is not.
func _any_armed_mortar_remains() -> bool:
	for u in player_units + enemy_units:
		if u.kind == Unit.Kind.MORTAR and u.state == Unit.State.ACTIVE and (u.mortar_rounds_remaining > 0 or _mortar_resupply.has(u)):
			return true
	return false


## True if any unit on either side is currently trying to move — mid-retreat
## (either leg) or ACTIVE with a move_target (road march, diving for cover).
## Used to detect a genuine stalemate: if nobody is moving and nobody has
## fired in a while, nothing is ever going to change before the time limit,
## so there is no reason to make the player sit through the rest of it.
##
## DRONE excluded: it's ALWAYS "moving with intent" while airborne (see
## _update_active_drone, re-picking a search target every tick) — background
## reconnaissance, not the kind of tactical movement that means the ground
## battle is still developing. Without this, an idle drone alone would keep
## the stalemate timeout from ever firing.
func _anyone_moving() -> bool:
	for u in player_units + enemy_units:
		if u.kind == Unit.Kind.DRONE:
			continue
		if u.state == Unit.State.RETREATING:
			return true
		if u.state == Unit.State.ACTIVE and u.has_move_target:
			return true
	return false


## True once nobody in `units` is still ACTIVE or mid-RETREAT — everyone left
## is either WITHDRAWN or DESTROYED. Battle end waits for this so a retreat
## actually finishes before the report is generated.
##
## DRONE excluded, same reasoning as _anyone_moving — a lone flying camera
## shouldn't be able to keep a side's fight "not done."
func _all_done_fighting(units: Array[Unit]) -> bool:
	for u in units:
		if u.kind == Unit.Kind.DRONE:
			continue
		if u.state == Unit.State.ACTIVE or u.state == Unit.State.RETREATING:
			return false
	return true


## DRONE excluded — a surviving drone alone shouldn't count as "the village
## is held," any more than it should block _all_done_fighting above.
func _has_active_units(units: Array[Unit]) -> bool:
	for u in units:
		if u.kind == Unit.Kind.DRONE:
			continue
		if u.state == Unit.State.ACTIVE:
			return true
	return false


## Display name for a WITHDRAWN/RETREATING unit in the AAR — a mortar or
## drone team whose crew took casualties before abandoning their position
## gets that noted, since "withdrew safely" alone would hide that its crew
## was hurt.
func _crew_survivor_label(u: Unit) -> String:
	if u.crew_casualties > 0 and (u.kind == Unit.Kind.MORTAR or u.kind == Unit.Kind.DRONE_TEAM):
		var what := "gun abandoned" if u.kind == Unit.Kind.MORTAR else "operations abandoned"
		return "%s (%d/%d crew casualties: %d killed, %d heavily wounded, %d walking wounded, %s)" % [
			u.display_name(), u.crew_casualties, u.crew_size, u.killed_count, u.heavily_wounded_count, u.walking_wounded_count, what
		]
	return u.display_name()


## Public entry point for UI (see CasualtyDashboard) to read live casualty
## stats for one side. The player's own side is always the true figures —
## it's the player's own command, always fully known. The enemy side is
## always the fog-of-war ESTIMATE (see _compute_side_stats's own `estimated`
## doc comment) — a live commander only knows what's actually been scouted,
## never the true totals in real time. The AAR at battle's end is NOT
## necessarily the same numbers this returns for the enemy side — see
## _end_battle, which may upgrade to the true figures once the fighting is
## over, depending on whether the position was held for a proper battlefield
## assessment.
func casualty_stats(team: Unit.Team) -> Dictionary:
	if team == Unit.Team.PLAYER:
		return _compute_side_stats(player_units)
	return _compute_side_stats(enemy_units, true, true)


## Public read for UI (see CasualtyDashboard) — a snapshot of the drone
## fleet's rotation state, for the same "just as prominent as casualties"
## treatment the mortar already gets. Only meaningful when recon_mode is
## DRONE_TEAM; harmless (all-zero/inactive) otherwise.
func drone_fleet_status() -> Dictionary:
	return {
		"team_active": drone_team != null and drone_team.state == Unit.State.ACTIVE,
		"team_state": drone_team.state if drone_team else Unit.State.DESTROYED,
		"team_crew_casualties": drone_team.crew_casualties if drone_team else 0,
		"team_crew_size": drone_team.crew_size if drone_team else 0,
		"airborne": active_drone != null,
		"airborne_charge": active_drone.drone_battery_charge if active_drone else -1.0,
		"backup": backup_drone != null,
		"backup_charge": backup_drone.drone_battery_charge if backup_drone else -1.0,
		"inbound": returning_drones.size(),
		"ready": _drones_ready.size(),
		"ready_best_charge": _drones_ready.max() if not _drones_ready.is_empty() else -1.0,
		"swapping": _drones_swapping.size(),
		"awaiting_battery": _airframes_awaiting_battery,
		"spare_batteries": _battery_pool.size(),
		"spare_best_charge": _battery_pool.max() if not _battery_pool.is_empty() else -1.0,
		"destroyed": _drones_destroyed,
	}


## `is_enemy_side` MUST be true for either fog-of-war behavior below to
## apply at all — the player's own side is always fully known regardless of
## `estimated`/unit state, full stop (they command it directly; a friendly
## unit that retreats doesn't become a mystery to its own commander). Every
## caller computing the player's own stats leaves this at its default
## (false) precisely so that's true unconditionally. Only pass true when
## actually computing the OPPOSING side's assessment.
##
## `estimated` — true for the PLAYER's own live fog-of-war view of the
## ENEMY side (see Unit.player_has_been_sighted/_known_pips/_known_state
## and _update_player_intel): the enemy's true condition is only as good as
## what's actually been scouted, live or in the AAR — see _end_battle's own
## reasoning for when the AAR still gets the true figures anyway (holding
## the position for a battlefield sweep). A unit never sighted at all
## doesn't contribute to pips_total either, not just pips_lost — the
## enemy's own total order of battle (how many personnel it fields at all)
## is exactly the kind of fact real fog of war withholds until it's
## actually been scouted, the same as any individual unit's condition; a
## unit sighted at some point and later lost track of still counts, since
## its existence was genuinely confirmed even if its current state wasn't.
##
## Even when the OVERALL call is the confirmed one (`estimated = false`,
## `is_enemy_side = true` — the position was held), a unit's OWN casualties
## are only ever assessable if it's something actually LEFT BEHIND to
## examine: a DESTROYED unit's remains, or a SURRENDERED one's personnel,
## already in hand. A WITHDRAWN or still-RETREATING unit took whatever it
## had — dead, wounded, and everyone still standing — with it when it left;
## holding the ground it fought over doesn't recover casualties that
## physically aren't there any more. Real battle-damage-assessment practice
## backs this up directly: even a body count on ground you've actually
## seized is understood as an UNDERCOUNT of true enemy dead, specifically
## because a retreating force removes its own fallen whenever it gets the
## chance — the ones truly left behind are the ones from a unit that had no
## chance to save anyone, i.e. one actually destroyed in place. So each
## ENEMY unit gets its OWN recoverability check (`unrecoverable`) on top of
## the overall `estimated` flag: DESTROYED/SURRENDERED units use the true
## figures (they're right there to count); WITHDRAWN/RETREATING units fall
## back to the same last-known snapshot the live dashboard already uses,
## no matter how the overall call was made. Either way, the detailed
## killed/heavily-wounded/walking-wounded breakdown is skipped for any unit
## that isn't itself recoverable — knowing a unit pulled back is something
## observation alone can support, but the exact mix of who among them died
## vs. was carried off isn't, and there's no aftermath left to go examine.
##
## `is_enemy_side` adds one more layer even for a unit that IS recoverable:
## a squad's casualties usually accumulate hit by hit, not all in one
## moment, and its WALKING wounded — ambulatory almost by definition — are
## exactly the casualties a losing side can and does evacuate under their
## own power even from a position it's about to lose, unlike its dead or
## its immobile heavily wounded. So even standing on ground a destroyed
## enemy unit fought over, "how many of its walking wounded actually got
## out" isn't something examining the position answers — they're tallied
## separately as `evacuated_unknown`, a real, counted personnel loss whose
## fate just isn't known, rather than asserted as "walking wounded left
## behind" with a confidence a real assessment wouldn't have.
func _compute_side_stats(units: Array[Unit], estimated: bool = false, is_enemy_side: bool = false) -> Dictionary:
	var pips_total := 0
	var pips_lost := 0
	# `pips_lost` splits into these two — every unit's own contribution
	# lands in exactly one, per that UNIT's own unit_estimated verdict, not
	# the overall call's. This is what lets a single "held the position"
	# AAR call honestly report a mix — some units fully confirmed on the
	# battlefield, others (ones that got away) still just an estimate —
	# instead of one blended number implying more certainty than the
	# assessment actually has. Always 100%/0% split for the player's own
	# side (confirmed) and the live dashboard's enemy read (unconfirmed).
	var confirmed_pips_lost := 0
	var unconfirmed_pips_lost := 0
	var killed := 0
	var heavily_wounded := 0
	var walking_wounded := 0
	var evacuated_unknown := 0
	var captured := 0
	var destroyed: PackedStringArray = []
	var withdrawn: PackedStringArray = []
	var still_retreating: PackedStringArray = []
	var surrendered: PackedStringArray = []
	for u in units:
		# A drone is equipment, not personnel — losing one doesn't hurt the
		# 3-person crew, so it never counts toward the human casualty tally
		# (it still shows up below if destroyed, just not in the pip count).
		# A resupply run is excluded for a different reason: it's a
		# transient logistics element spawned and resolved mid-battle (see
		# _update_resupply_run_targets/_resolve_resupply_run_arrivals), not
		# part of the original order of battle — counting it here would
		# make the AAR's personnel baseline drift depending on whether a
		# run happened to be alive at the moment stats were computed.
		#
		# For an ESTIMATED enemy-side view specifically, a unit never once
		# sighted doesn't even count toward the TOTAL — "how many personnel
		# does the enemy have" is itself something the player has to have
		# actually scouted, not a fact handed over for free just because
		# BattleManager itself is omniscient. A unit sighted at some point
		# and later lost track of (retreated, withdrawn) still counts —
		# its existence was genuinely confirmed, even if its current
		# condition wasn't; this only ever excludes one nobody has ever
		# actually seen at all.
		var counts_toward_known_total: bool = not (estimated and is_enemy_side) or u.player_has_been_sighted
		if u.kind != Unit.Kind.DRONE and u.kind != Unit.Kind.RESUPPLY_RUN and counts_toward_known_total:
			pips_total += u.max_pips
		# Only ever relevant for the ENEMY side — the player's own units are
		# always fully known regardless of state; a friendly mortar crew
		# that retreats or withdraws doesn't become a mystery to its own
		# commander. Without this gate, is_enemy_side defaulting false on
		# the player's own _compute_side_stats(player_units) call still let
		# a RETREATING/WITHDRAWN friendly unit fall through as "unrecoverable
		# and never sighted" (player_has_been_sighted is only ever populated
		# for enemy_units — see _update_player_intel — so it reads false for
		# every player unit too) and get silently skipped from pips_lost
		# entirely: a real, reported bug (a mortar crew took 3 casualties
		# and retreated, logged in the combat log, yet the aggregate still
		# read "0/34 personnel lost").
		var unrecoverable: bool = is_enemy_side and (u.state == Unit.State.WITHDRAWN or u.state == Unit.State.RETREATING)
		var unit_estimated: bool = estimated or unrecoverable
		if unit_estimated and not u.player_has_been_sighted:
			continue # never actually confirmed — assumed still active and undamaged
		var eff_state: Unit.State = u.player_known_state if unit_estimated else u.state
		var eff_pips: int = u.player_known_pips if unit_estimated else u.pips
		if u.kind != Unit.Kind.DRONE and u.kind != Unit.Kind.RESUPPLY_RUN:
			var lost_here: int = u.max_pips - eff_pips
			pips_lost += lost_here
			if unit_estimated:
				unconfirmed_pips_lost += lost_here
			else:
				confirmed_pips_lost += lost_here
			if not unit_estimated:
				# killed_count/heavily_wounded_count/walking_wounded_count/
				# wounded_left_behind_count are populated for every personnel
				# kind (SQUAD's graduated split, and a flat killed_count
				# increment for SPOTTER/MORTAR/DRONE_TEAM crew — see
				# Unit.take_hit/_apply_crew_casualties), so summing them
				# unconditionally here is what keeps this always reconciling
				# exactly with pips_lost above, not just for squads.
				killed += u.killed_count
				heavily_wounded += u.heavily_wounded_count
				if is_enemy_side:
					evacuated_unknown += u.walking_wounded_count
				else:
					walking_wounded += u.walking_wounded_count
				captured += u.wounded_left_behind_count
			# Captured is captured regardless of the reason: an individually
			# abandoned HEAVILY_WOUNDED soldier (wounded_left_behind_count
			# above) and a whole squad's remaining personnel at the moment
			# it surrenders are the same fact from the losing side's own
			# accounting — no longer available to the fight, alive, in the
			# other side's hands. A SURRENDERED unit's own `pips` were never
			# reduced by combat (state changes, pips doesn't), so they're
			# folded in here as an explicit extra loss — bringing pips_lost
			# up to the unit's full max_pips (whatever it had already lost
			# to killed/wounded, plus everyone captured at the surrender
			# itself) — not left sitting there uncounted as if those people
			# were still an active part of the fight.
			if eff_state == Unit.State.SURRENDERED:
				pips_lost += eff_pips
				if unit_estimated:
					unconfirmed_pips_lost += eff_pips
				else:
					confirmed_pips_lost += eff_pips
					captured += eff_pips
		match eff_state:
			Unit.State.DESTROYED:
				if u.kind == Unit.Kind.MORTAR or u.kind == Unit.Kind.DRONE_TEAM:
					if unit_estimated:
						destroyed.append("%s (destroyed — crew losses unconfirmed)" % u.display_name())
					elif is_enemy_side:
						destroyed.append("%s (%d/%d crew casualties: %d killed, %d heavily wounded, %d unaccounted for)" % [
							u.display_name(), u.crew_casualties, u.crew_size, u.killed_count, u.heavily_wounded_count, u.walking_wounded_count
						])
					else:
						destroyed.append("%s (%d/%d crew casualties: %d killed, %d heavily wounded, %d walking wounded)" % [
							u.display_name(), u.crew_casualties, u.crew_size, u.killed_count, u.heavily_wounded_count, u.walking_wounded_count
						])
				else:
					destroyed.append(u.display_name())
			Unit.State.WITHDRAWN:
				withdrawn.append(u.display_name() if unit_estimated else _crew_survivor_label(u))
			Unit.State.RETREATING:
				still_retreating.append(u.display_name() if unit_estimated else _crew_survivor_label(u))
			Unit.State.SURRENDERED:
				# Its remaining `pips` are already folded into `captured`
				# (and `pips_lost`) above — this line just names WHICH unit
				# they came from and how many, as narrative detail on top of
				# the aggregate count, not a second place that count lives.
				surrendered.append("%s (%d personnel)" % [u.display_name(), eff_pips])
	var casualty_percent: float = (float(pips_lost) / float(pips_total) * 100.0) if pips_total > 0 else 0.0
	return {
		"pips_total": pips_total,
		"pips_lost": pips_lost,
		"confirmed_pips_lost": confirmed_pips_lost,
		"unconfirmed_pips_lost": unconfirmed_pips_lost,
		"casualty_percent": casualty_percent,
		"killed": killed,
		"heavily_wounded": heavily_wounded,
		"walking_wounded": walking_wounded,
		"evacuated_unknown": evacuated_unknown,
		"captured": captured,
		"destroyed": destroyed,
		"withdrawn": withdrawn,
		"still_retreating": still_retreating,
		"surrendered": surrendered,
		"estimated": estimated,
	}


## Holding is judged, not just won/lost: a defense that gives up the village
## but bleeds the attacker badly enough — inflicting casualties, then pulling
## out clean — can still be reported as a success, and a defense that
## technically holds but guts every squad is not a clean win either. See
## design doc for the reasoning. "Held" means the player still had at least
## one unit actively fighting (not retreating/withdrawn/destroyed) the moment
## the battle ended — ordering a general retreat gives up the position even
## before the withdrawal physically finishes.
## The score inputs and the score for a finished battle — see BattleScore.
## Built entirely from TRUE ground-truth casualty counts, by side: our own
## (always fully known) and `true_enemy_stats` (pure ground truth, NOT the
## fog-of-war-limited figures the report displays). Each side's casualties
## come from the VICTIMS' own counts, so they count whatever caused them —
## friendly fire against the player, an enemy's own fire on itself in the
## player's favor. A stalemate scores neither +20 nor -20 for the position.
func _build_battle_result(verdict: String, held: bool, player_stats: Dictionary, true_enemy_stats: Dictionary) -> Dictionary:
	var player_mortar_lost := 0
	for u in player_units:
		if u.kind == Unit.Kind.MORTAR and u.state == Unit.State.DESTROYED:
			player_mortar_lost += 1
	var enemy_mortar_out := 0
	for u in enemy_units:
		if u.kind == Unit.Kind.MORTAR and BattleScore.enemy_mortar_out(u, held):
			enemy_mortar_out += 1
	var inputs: Dictionary = {
		"position": BattleScore.position_key(held, _ended_by_stalemate),
		"player_killed": player_stats.killed,
		"player_captured": player_stats.captured,
		"player_heavily_wounded": player_stats.heavily_wounded,
		"player_walking_wounded": player_stats.walking_wounded,
		"player_mortar_lost": player_mortar_lost,
		"enemy_killed": true_enemy_stats.killed,
		"enemy_captured": true_enemy_stats.captured,
		"enemy_heavily_wounded": true_enemy_stats.heavily_wounded,
		"enemy_walking_wounded": true_enemy_stats.walking_wounded,
		"enemy_mortar_out": enemy_mortar_out,
		# civilians, whoever's shell it was (the score does not care), then the split by firing side, for display only
		"civilian_killed": civilian_casualties_by_shell.player.killed + civilian_casualties_by_shell.enemy.killed,
		"civilian_heavily_wounded": civilian_casualties_by_shell.player.heavily_wounded + civilian_casualties_by_shell.enemy.heavily_wounded,
		"civilian_walking_wounded": civilian_casualties_by_shell.player.walking_wounded + civilian_casualties_by_shell.enemy.walking_wounded,
		"civilian_by_shell": civilian_casualties_by_shell.duplicate(true),
	}
	return {
		"verdict": verdict,
		"held": held,
		"stalemate": _ended_by_stalemate,
		"rubric_version": BattleScore.RUBRIC_VERSION,
		"score": BattleScore.score(inputs),
		"inputs": inputs,
	}


## Real (wall-clock) seconds the battle's final frame stays on screen, unobscured, before the report
## window covers it — but only when the battle just ended on a kill (see _end_battle's own use of this).
const BATTLE_END_KILL_PAUSE_S: float = 0.75


func _end_battle() -> void:
	battle_over = true
	_number_remaining_undiscovered_enemies() # anything the AAR/Damage-by-unit report names but the player never actually spotted still needs a real number
	_record_history_snapshot() # the final moment, exactly, regardless of where the regular interval last landed

	var player_stats := _compute_side_stats(player_units)
	# The verdict itself is always judged on the TRUE outcome — win/loss
	# scoring has to be fair regardless of what the player actually got to
	# see, the same way the enemy's own AI plays with full knowledge of its
	# own mortar's ammo even though the player never sees it (v75). Deliberately
	# NOT `is_enemy_side` — that flag only affects what gets DISPLAYED (see
	# `enemy_stats` below), and scoring must never be built on top of it.
	var true_enemy_stats := _compute_side_stats(enemy_units)
	var held: bool = _has_active_units(player_units)
	var exchange_ratio: float = float(true_enemy_stats.pips_lost) / float(max(player_stats.pips_lost, 1))

	# Direct user correction, from a real battle that ended via the stalemate
	# timeout (_ended_by_stalemate): "I'm thinking that when that happens,
	# the verdict should be 'STALEMATE'. It can then talk about losses...
	# Don't say that the position was held, or that it was lost. Neither is
	# true." A stalemate is neither side's forces being wiped out or driven
	# off — held/exchange_ratio still describe the actual casualty picture
	# correctly (a real, possibly favorable exchange, still worth reporting
	# below), but "held"/"lost" as a RESULT is a claim about how the fight
	# was decided, and a stalemate was never decided at all — checked first,
	# ahead of the ordinary held/exchange_ratio branching, so it can never be
	# read back as a defense or a defeat.
	var verdict: String
	if _ended_by_stalemate:
		verdict = "STALEMATE"
	elif held and exchange_ratio >= 1.5:
		verdict = "SUCCESSFUL DEFENSE"
	elif held:
		verdict = "PYRRHIC DEFENSE"
	elif exchange_ratio >= 2.0:
		verdict = "TACTICAL WITHDRAWAL — favorable exchange"
	else:
		verdict = "DEFEAT"

	# A commander only gets the TRUE enemy toll by actually holding the
	# ground afterward for a real battlefield assessment — bodies, abandoned
	# equipment, prisoners, physically found and counted. A drone doesn't
	# change that: it's a live sensor, not a way to walk a battlefield the
	# side has just given up — once the position is lost, a withdrawn
	# drone (and everyone else) is going home with whatever it already
	# scouted, the same as a spotter would. Recon mode already shapes how
	# GOOD that live-scouted picture is (a drone's wider coverage means more
	# actually got confirmed along the way — see _compute_side_stats's own
	# `estimated` doc comment), it just doesn't independently unlock the
	# true figures the way holding the ground does. Even holding doesn't
	# unlock EVERYTHING, though — see _compute_side_stats's own
	# `is_enemy_side` doc comment: an enemy unit's walking wounded are
	# exactly the casualties a losing side can, and does, evacuate under
	# their own power even from a position it's about to lose. A fresh
	# computation, not a reuse of `true_enemy_stats` above — that one has to
	# stay pure ground truth for scoring, this one is deliberately not.
	var enemy_stats := _compute_side_stats(enemy_units, not held, true)
	battle_result = _build_battle_result(verdict, held, player_stats, true_enemy_stats)

	var lines: PackedStringArray = []
	lines.append("=== AFTER-ACTION REPORT ===")
	# Direct user request: say up top that the enemy casualty figures below are
	# higher command's assessment, not ground truth (the score, by contrast, is
	# computed from the true results).
	lines.append(AFTER_ACTION_REPORT_DISCLAIMER)
	lines.append("")
	lines.append(BattleScore.verdict_line(verdict))
	if _ended_by_stalemate:
		lines.append("%s: stalemate — neither side broke contact before the fight was called" % GameConfig.CURRENT_MAP.name)
	else:
		lines.append("%s held: %s" % [GameConfig.CURRENT_MAP.name, "YES" if held else "NO"])
	# Direct user request: the AAR should not mention the score at all — "It is how things look to
	# in-world command, not to a player." The score itself (BattleScore, computed from the TRUE results,
	# not this report's own possibly-estimated enemy figures) still exists, still gets recorded to the
	# durable history, and is still shown to the player — just on the Score tab (see BattleReport), never
	# folded into the in-world narrative.
	if weather != null:
		var weather_line: String = "Weather: %s, %d °C" % [weather.wind_label().replace("Wind", "wind"), roundi(weather.temperature_c)]
		if weather.is_precipitating():
			weather_line += ", %s" % weather.precip_label().to_lower()
		lines.append(weather_line)
		if _drones_recalled_by_rain > 0 or _drones_lost_to_weather > 0 or _drones_aborted_by_weather > 0:
			lines.append("Drones and weather: %d recalled by rain, %d lost, %d aborted" % [_drones_recalled_by_rain, _drones_lost_to_weather, _drones_aborted_by_weather])
	var tactical_minutes: int = int(scenario_elapsed_time / 60.0)
	lines.append("Time elapsed: %dh %02dm (0600 to %s)" % [tactical_minutes / 60, tactical_minutes % 60, clock_string().substr(0, 5)])
	# Captured is included right in this line, not a separate conditional
	# one, specifically so killed + heavily wounded + walking wounded +
	# captured always visibly sums to the personnel-lost total on the left —
	# every one of those four is tracked for every personnel kind now (see
	# _compute_side_stats), so this is a real identity, not just usually true.
	#
	# "Ukrainian"/"Russian" from here down (this report and its own losses/withdrew/surrendered lines
	# below), not "Player"/"Enemy" — direct user request making the Ukraine-vs-Russia setting explicit.
	# Unit.display_name() got the same treatment for the combat log; the on-map unit label itself
	# (Unit._draw, drawing unit_label directly) deliberately did NOT — "Don't put it onto the unit names
	# on the map. It makes them too long."
	lines.append("Ukrainian casualties: %d/%d personnel (%.0f%%) — %d killed, %d heavily wounded, %d walking wounded, %d captured" % [
		player_stats.pips_lost, player_stats.pips_total, player_stats.casualty_percent,
		player_stats.killed, player_stats.heavily_wounded, player_stats.walking_wounded, player_stats.captured,
	])
	# Three distinct cases, not two — "held the position" doesn't mean every
	# enemy unit's own fate got confirmed (see _compute_side_stats's own
	# confirmed_pips_lost/unconfirmed_pips_lost doc comment): some may have
	# been destroyed/captured right there (fully assessable), others may
	# have gotten away with everything they had (only as good as what was
	# actually scouted, exactly like the "position not held" case below).
	# Blending those into one number would imply a precision the assessment
	# doesn't actually have — so a real mix gets its own, explicit wording
	# rather than being silently folded into either the pure-estimate or
	# pure-confirmed line.
	if enemy_stats.estimated:
		lines.append("Russian casualties: an estimated %d/%d personnel (~%.0f%%) — the position wasn't held for a battlefield assessment, so this reflects only what was actually scouted during the fight, not the true toll" % [
			enemy_stats.pips_lost, enemy_stats.pips_total, enemy_stats.casualty_percent,
		])
	elif enemy_stats.unconfirmed_pips_lost == 0:
		# No "walking wounded" line here, unlike the player's own casualties
		# above — a losing side evacuates its own ambulatory wounded under
		# their own power even from a position it's about to lose, so
		# holding the ground afterward doesn't actually answer what became
		# of them; `evacuated_unknown` is a real, counted personnel loss,
		# just not one this assessment can characterize any further (see
		# _compute_side_stats's own `is_enemy_side` doc comment).
		lines.append("Russian casualties: %d/%d personnel confirmed on the battlefield (%.0f%%) — %d killed, %d heavily wounded, %d captured, %d more unaccounted for (likely evacuated wounded — the enemy pulls its own ambulatory casualties out even from ground it's about to lose)" % [
			enemy_stats.pips_lost, enemy_stats.pips_total, enemy_stats.casualty_percent,
			enemy_stats.killed, enemy_stats.heavily_wounded, enemy_stats.captured, enemy_stats.evacuated_unknown,
		])
	else:
		lines.append("Russian casualties: %d/%d confirmed on the battlefield — %d killed, %d heavily wounded, %d captured, %d more unaccounted for (likely evacuated wounded)" % [
			enemy_stats.confirmed_pips_lost, enemy_stats.pips_total,
			enemy_stats.killed, enemy_stats.heavily_wounded, enemy_stats.captured, enemy_stats.evacuated_unknown,
		])
		lines.append("Plus an estimated %d more among units that got away before the position could be swept — not independently confirmed, just what was actually scouted during the fight" % enemy_stats.unconfirmed_pips_lost)
		lines.append("Russian casualties overall (partly estimated): ~%d/%d personnel (~%.0f%%)" % [
			enemy_stats.pips_lost, enemy_stats.pips_total, enemy_stats.casualty_percent,
		])
	# No separate "exchange ratio" line — it was purely duplicative of the two
	# casualty lines just above; `exchange_ratio` itself stays, still doing
	# real work in the verdict math above (SUCCESSFUL DEFENSE/PYRRHIC
	# DEFENSE/TACTICAL WITHDRAWAL thresholds), just no longer printed.
	if not player_stats.destroyed.is_empty():
		lines.append("Ukrainian losses: %s" % ", ".join(player_stats.destroyed))
	if not player_stats.withdrawn.is_empty():
		lines.append("Ukrainian forces withdrew safely: %s" % ", ".join(player_stats.withdrawn))
	if not player_stats.still_retreating.is_empty():
		lines.append("Ukrainian forces still pulling back when the battle ended: %s" % ", ".join(player_stats.still_retreating))
	if not enemy_stats.destroyed.is_empty():
		lines.append("Russian losses: %s" % ", ".join(enemy_stats.destroyed))
	if not enemy_stats.withdrawn.is_empty():
		lines.append("Russian forces withdrew: %s" % ", ".join(enemy_stats.withdrawn))
	if not enemy_stats.still_retreating.is_empty():
		lines.append("Russian forces still pulling back when the battle ended: %s" % ", ".join(enemy_stats.still_retreating))
	if not player_stats.surrendered.is_empty():
		lines.append("Ukrainian forces surrendered: %s" % ", ".join(player_stats.surrendered))
	if not enemy_stats.surrendered.is_empty():
		lines.append("Russian forces surrendered: %s" % ", ".join(enemy_stats.surrendered))

	# unit_combat_stats.report_lines() used to be appended here too — now
	# that BattleReport's own "Damage by unit" tab fetches it fresh on demand
	# (see its own pressed handler), duplicating the whole thing onto the
	# end of this summary as well is just redundant scrolling.
	var report_text := "\n".join(lines)
	# Direct user report: clicked "Retreat Now," the squads and mortar made it safely off, but the report
	# popped up the instant the player's own spotter was killed mid-retreat — the player never actually
	# saw it happen, since the window covers the map immediately on battle_ended. A kill is the one kind of
	# battle-ending moment worth a beat to actually register (a peaceful mass withdrawal already happens
	# gradually, in full view, over many prior ticks — this is the one board-flip case where "the moment"
	# is a single, otherwise-invisible tick, not a fresh player_units count as the withdrawal is). Real
	# (wall-clock) time, deliberately not tactical time — the battle itself is already over (battle_over is
	# already true, above), so there is no tactical clock left running to measure this against.
	if _kill_happened_this_tick:
		await get_tree().create_timer(BATTLE_END_KILL_PAUSE_S).timeout
	battle_ended.emit(report_text)


## The terrain itself is NOT drawn here — this node redraws every frame
## (fire tracers and impact fade-outs animate), and rebuilding the whole
## map's contours, buildings and tree patches each time cost ~10ms a frame
## on the older maps and ~67ms on a real-data one. It lives in a retained
## child layer instead (see _ready and terrain_layer.gd), drawn once and
## shown behind everything this function draws.
func _draw() -> void:
	for flash in _fire_flashes:
		var age: float = elapsed_time - flash.time
		if age > FLASH_DURATION:
			continue
		var alpha: float = 1.0 - (age / FLASH_DURATION)
		var color: Color = Color(1.0, 0.85, 0.2, alpha) if flash.team == Unit.Team.ENEMY else Color(0.3, 0.85, 1.0, alpha)
		if flash.is_mortar:
			# Lobbed, not straight — a mortar shell arcs over whatever's
			# between it and the target, so the tracer should never look
			# like it punched through a wall to get there.
			_draw_arc_tracer(flash.from, flash.to, color)
		else:
			draw_line(flash.from, flash.to, color, 2.0)
		draw_circle(flash.from, 5.0, Color(1.0, 1.0, 0.6, alpha))
	for impact in _mortar_impacts:
		var age: float = elapsed_time - impact.time
		if age > IMPACT_EFFECT_DURATION:
			continue
		_draw_mortar_impact(impact.position, age / IMPACT_EFFECT_DURATION)


## A real HE round's actual landing — deliberately a real, if brief,
## explosion rather than just a marker dot: a bright core flash that
## burns out fast (real HE detonates and is gone almost instantly) plus
## a slower-fading, outward-expanding double ring standing in for the
## blast/smoke that lingers a moment longer, matching this project's own
## established minimalist procedural-drawing style everywhere else (no
## image assets, just shapes) — see _draw_arc_tracer's own identical
## approach for the fire tracer. `t` is 0.0 the instant the round lands
## and 1.0 at the end of IMPACT_EFFECT_DURATION.
func _draw_mortar_impact(position: Vector2, t: float) -> void:
	var core_alpha: float = clampf(1.0 - t * 3.0, 0.0, 1.0) # real HE core flash burns out within the first third
	if core_alpha > 0.0:
		draw_circle(position, 9.6, Color(1.0, 0.95, 0.7, core_alpha))
		draw_circle(position, 4.8, Color(1.0, 1.0, 1.0, core_alpha))
	var ring_alpha: float = 1.0 - t
	var ring_radius: float = 6.4 + t * 16.0
	draw_arc(position, ring_radius, 0.0, TAU, 24, Color(0.35, 0.3, 0.25, ring_alpha * 0.8), 2.0, true)
	draw_arc(position, ring_radius * 0.65, 0.0, TAU, 24, Color(0.15, 0.12, 0.1, ring_alpha * 0.6), 2.0, true)


func _draw_arc_tracer(from: Vector2, to: Vector2, color: Color) -> void:
	var apex: Vector2 = (from + to) / 2.0 - Vector2(0.0, from.distance_to(to) * 0.2)
	var points := PackedVector2Array()
	var segments := 12
	for i in segments + 1:
		var t: float = float(i) / float(segments)
		var one_minus_t: float = 1.0 - t
		points.append(from * (one_minus_t * one_minus_t) + apex * (2.0 * one_minus_t * t) + to * (t * t))
	draw_polyline(points, color, 2.0, true)
