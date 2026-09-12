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
## side, so it is always clear when and where the enemy is shooting.

signal battle_ended(report_text: String)

const FLASH_DURATION: float = 0.3
const CommanderProfile = preload("res://scripts/commander_profile.gd")
const DecisionRecorder = preload("res://scripts/decision_recorder.gd")
const UnitDoctrine = preload("res://scripts/unit_doctrine.gd")
const RiskForecast = preload("res://scripts/risk_forecast.gd")
const UnitCombatStats = preload("res://scripts/unit_combat_stats.gd")
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
				var visible_path := GameConfig.has_aerial_los(unit.global_position, target.global_position)
				var concealment: float = GameConfig.DRONE_CONCEALMENT_MULTIPLIER[target.terrain_type()]
				return maxf(0.0, 1.0 - distance / GameConfig.DRONE_DETECTION_RANGE) * concealment if visible_path else 0.0
			return CombatResolver.hit_probability(unit, target, _drone_directing_mortar_fire(unit))
	return 1.0


func _forecast_target(unit: Unit) -> Unit:
	# Preview only: no _pick_target, randomness, or decision mutation.
	var opposing: Array[Unit] = enemy_units if unit.team == Unit.Team.PLAYER else player_units
	var best: Unit = null
	var best_score := -INF
	for candidate in opposing:
		if not candidate.is_targetable(): continue
		if unit.kind == Unit.Kind.SQUAD:
			if unit.global_position.distance_to(candidate.global_position) > GameConfig.SQUAD_ENGAGEMENT_RANGE: continue
			if not GameConfig.has_direct_los(unit.global_position, candidate.global_position): continue
		elif unit.kind == Unit.Kind.MORTAR:
			if unit.global_position.distance_to(candidate.global_position) > GameConfig.MORTAR_MAX_RANGE: continue
		elif unit.kind != Unit.Kind.DRONE:
			continue
		var score := _enemy_target_value(unit, candidate)
		if score > best_score:
			best = candidate
			best_score = score
	return best


func _risk_forecast(unit: Unit, target: Unit, point: Vector2) -> Dictionary:
	var threats: Array[Dictionary] = []
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
		var max_range: float = GameConfig.MORTAR_MAX_RANGE if enemy.kind == Unit.Kind.MORTAR else GameConfig.SQUAD_ENGAGEMENT_RANGE
		if point.distance_to(known_position) > max_range: continue
		if enemy.kind == Unit.Kind.SQUAD and not GameConfig.has_direct_los(known_position, point): continue
		if enemy.kind == Unit.Kind.MORTAR and GameConfig.is_building_at(known_position): continue
		var probability := CombatResolver.hit_probability(enemy, unit, false, point, known_position) * confidence
		threats.append({"chance": probability, "shots": RiskForecast.shot_count(enemy, RiskForecast.HORIZON_SECONDS, GameConfig.TIME_SCALE_NORMAL, false), "mortar": enemy.kind == Unit.Kind.MORTAR})
	# Incoming fire is already announced to the target's side. The source
	# and other hidden artillery are not exposed by this calculation.
	for strike in _pending_counter_battery:
		if strike.target == unit and strike.impact_time - scenario_elapsed_time <= RiskForecast.HORIZON_SECONDS:
			var chance := clampf(1.0 - point.distance_to(strike.impact_position) / GameConfig.COUNTER_BATTERY_BLAST_RADIUS, 0.0, 1.0)
			threats.append({"chance": chance, "shots": 1, "mortar": true})
	var forecast := RiskForecast.damage_distribution(unit, threats)
	forecast["horizon_seconds"] = RiskForecast.HORIZON_SECONDS
	forecast["known_threats"] = threats.size()
	forecast["goal_probability"] = -1.0
	forecast["goal"] = "Continue the assigned support or movement task (success not forecast)."
	if target != null and unit.kind in [Unit.Kind.SQUAD, Unit.Kind.MORTAR]:
		var shots := RiskForecast.shot_count(unit, RiskForecast.HORIZON_SECONDS, GameConfig.TIME_SCALE_NORMAL, true)
		var hit := CombatResolver.hit_probability(unit, target, _drone_directing_mortar_fire(unit))
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


func _relocate_for_risk(unit: Unit) -> void:
	_risk_holds[unit] = true
	unit.last_order_reason = "Self-risk policy rejected the current exposure; moving to safer cover or withholding fire."
	var known := _known_enemy_positions(unit.team)
	var choices: Array[Vector2] = [unit.global_position,
		GameConfig.nearest_hidden_point(unit.global_position, known, unit.kind == Unit.Kind.MORTAR),
		GameConfig.nearest_cover_point(unit.global_position, 0.0, unit.kind == Unit.Kind.MORTAR, _ally_positions_for(unit), known)]
	var best: Vector2 = unit.global_position
	var best_risk := INF
	for point in choices:
		if unit.kind == Unit.Kind.MORTAR and GameConfig.is_building_at(point): continue
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
			var limit: float = GameConfig.SQUAD_ENGAGEMENT_RANGE if unit.kind == Unit.Kind.SQUAD else GameConfig.MORTAR_MAX_RANGE
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
# User-requested pause (see toggle_pause) — freezes the entire simulation
# exactly where it stands: _process returns immediately, before either
# clock advances or any tick logic runs, so nothing (movement, fire,
# resupply, drone flight, the battle-over check itself) progresses at all
# until resumed. Nothing outside BattleManager's own _process depends on
# per-frame simulation time (see Unit — it has no _process of its own,
# everything is driven centrally from here), so this one early return is
# sufficient to pause the whole battle.
var is_paused: bool = false
# Player-controlled playback speed (see main.gd's speed dropdown) —
# multiplies `delta` at the very top of _process, before it's used for
# anything else (elapsed_time, scenario_delta, all of it), so the entire
# simulation speeds up or slows down uniformly rather than needing every
# individual timing calculation to know about it separately. Orthogonal to
# is_paused, which still freezes everything outright regardless of this
# value — pausing at 4x is exactly as frozen as pausing at 1x.
var playback_speed: float = 1.0
# scenario_elapsed_time at which order_general_retreat() should fire on
# its own, or Vector2.INF's scalar equivalent (INF) if none is scheduled.
# See order_scheduled_retreat/_check_scheduled_retreat — the player's own
# "plan a retreat for later" order (main.gd's slider), distinct from
# order_general_retreat's own immediate button. Re-callable: scheduling a
# new one just overwrites this, so adjusting the slider and re-confirming
# simply reschedules rather than stacking multiple pending retreats.
var scheduled_retreat_time: float = INF
var _fire_flashes: Array[Dictionary] = []
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

# Counter-battery strikes triggered but not yet landed — see
# _resolve_mortar_counter_battery / _resolve_pending_counter_battery.
# {"target": Unit, "impact_position": Vector2, "impact_time": float}
var _pending_counter_battery: Array[Dictionary] = []

# Mortar shots fired but not yet landed — see _launch_mortar_shot /
# _resolve_pending_mortar_shots. {"mortar": Unit, "target": Unit,
# "aim_point": Vector2, "impact_time": float}
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
# Unit; removed once both waves have resolved (a successful wave hands off
# to a real, physical Unit.Kind.RESUPPLY_RUN — see _spawn_resupply_run —
# so this dict's own job ends at the moment a run sets out; delivery/loss
# is tracked on the run itself, not here). Fields: wave_arrival_times/
# warning_times (Array[float], one per GameConfig.MORTAR_RESUPPLY_WAVE_
# COUNT wave), wave_warned/wave_resolved (Array[bool]).
var _mortar_resupply: Dictionary = {}

# Unit (a mortar) -> {"position": Vector2, "time": float} — where and when
# that mortar was last DETECTED firing, via muzzle blast/trajectory rather
# than visual spotting (real counter-battery detection doesn't need to see
# the crew) — see _launch_mortar_shot (records it, every shot, any mortar)
# and _known_friendly_mortar_position (consumes it, as a fallback when the
# mortar isn't currently visible either).
var _last_detected_mortar_fire: Dictionary = {}

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
var _mortar_move_intent: Dictionary = {}

# Unit (a mortar) -> {"tier": String, "detail": String} — the mortar
# decision ladder's own live reasoning trail, mirroring _drone_pilot_
# reasoning/drone_pilot_debug_snapshot for the drone. Written exactly once
# per mortar per tick, on every path including "holding, nothing to do" —
# see _decide_mortar_action and mortar_decision_debug_snapshot.
var _mortar_reasoning: Dictionary = {}

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

# Where the friendly mortar was actually deployed this battle (the
# player's own doctrine choice, wherever in PLAYER_MORTAR_DEPLOYMENT_ZONE
# that was) — captured once in _spawn_player_units and never touched
# again. This is what "safe territory" means for GameConfig.MORTAR_HUNT_
# MAX_RANGE_FROM_HOME: hunting is good, but not unbounded — the crew
# still won't range farther than that from wherever they were actually
# set up, no matter how good the intel on a target is or how far away
# known enemy squads happen to be.
var _friendly_mortar_home_position: Vector2 = Vector2.ZERO

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
var _drones_destroyed: int = 0 # airframes permanently lost (shot down, battery and all) this battle
# The single candidate key (see _sweep_candidates/_flank_watch_candidates)
# the drone is currently committed to flying toward or sitting at, for the
# unified routine-recon pool — see _drone_routine_recon_target. Empty
# string means no commitment yet (battle start).
var _drone_current_destination_key: String = ""
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
# Recorded live, in place, by _drone_search_target itself as it decides —
# NOT a separate re-derivation of that decision, which would risk drifting
# out of sync with the real logic. {"tier": String, "detail": String,
# "target": Vector2} describing whichever branch actually won this tick.
# Read-only introspection for drone_pilot_debug_snapshot (the debug
# overlay/export — see main.gd) — nothing else may ever branch on this.
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
	elapsed_time = 0.0
	scenario_elapsed_time = 0.0
	battle_over = false
	is_paused = false
	_fire_flashes.clear()
	_seconds_since_last_shot = 0.0
	enemy_alerted = false
	player_general_retreat_ordered = false
	enemy_general_retreat_ordered = false
	_last_detected_mortar_fire.clear()
	_mortar_tick_shot.clear()
	_mortar_move_intent.clear()
	_mortar_reasoning.clear()
	_joint_mortar_hunt_target = null
	_joint_mortar_hunt_start_time = 0.0
	_pending_counter_battery.clear()
	_pending_mortar_shots.clear()
	recon_mode = doctrine.get("recon_mode", GameConfig.ReconMode.SPOTTER)
	drone_team = null
	active_drone = null
	backup_drone = null
	returning_drones.clear()
	_drones_ready.clear()
	_drones_swapping.clear()
	_battery_pool.clear()
	_drones_destroyed = 0
	_drone_destination_last_visited.clear()
	_drone_current_destination_key = ""
	_recent_enemy_contacts.clear()
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
		units.append({"team": u.team, "kind": u.kind, "x": u.global_position.x, "y": u.global_position.y, "state": u.state,
			"unit_label": u.unit_label, "pips": u.pips, "max_pips": u.max_pips})
	_history.append({"time": scenario_elapsed_time, "units": units})


## Public accessor for main.gd's BattleHistoryViewer — read-only, recorded
## once per battle, never mutated after the fact.
func battle_history() -> Array[Dictionary]:
	return _history


## Public accessor for main.gd's BattleHistoryViewer — see _history_fire_
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
	if randf() < GameConfig.ENEMY_SQUAD_COUNT_TAIL_CHANCE:
		squads = randi_range(GameConfig.ENEMY_SQUAD_COUNT_MAX + 1, GameConfig.ENEMY_SQUAD_COUNT_TAIL_MAX)
	else:
		squads = randi_range(GameConfig.ENEMY_SQUAD_COUNT_MIN, GameConfig.ENEMY_SQUAD_COUNT_MAX)
	var target_mortars: int = roundi(float(squads) / GameConfig.ENEMY_SQUAD_PER_MORTAR_RATIO)
	var jitter: int = randi_range(-GameConfig.ENEMY_MORTAR_COUNT_JITTER, GameConfig.ENEMY_MORTAR_COUNT_JITTER)
	var mortars: int = clampi(target_mortars + jitter, GameConfig.ENEMY_MORTAR_COUNT_MIN, GameConfig.ENEMY_MORTAR_COUNT_MAX)
	return {"mortars": mortars, "squads": squads}


func _spawn_enemy_units() -> void:
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
		if randf() < GameConfig.ENEMY_FLANK_CHANCE:
			squad.flanking_route_active = true
			squad.flank_waypoint_y = start_pos.y
		enemy_units.append(squad)

	for mortar_pos_m in GameConfig.enemy_mortar_positions_m(force_size.mortars):
		var em := _make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, mortar_pos_m * GameConfig.PIXELS_PER_METER)
		em.shoot_and_scoot = false
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
	return unit


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


## Toggled by the player's own pause control (main.gd) — not gated on
## battle_over the way order_general_retreat is, since pausing an already-
## finished battle is simply a no-op either way (there's nothing left for
## _process to do once battle_over is true regardless of is_paused).
func toggle_pause() -> void:
	is_paused = not is_paused


## The player's "plan a retreat for later" order (main.gd's delay slider),
## distinct from order_general_retreat's own immediate button. Doesn't
## move anyone by itself — it only sets the clock order_general_retreat
## eventually fires from on its own (_check_scheduled_retreat), the same
## way as if the player had pressed the immediate button at that moment.
## What DOES change right away: the mortar's own ammo-conservation math
## (see _scheduled_retreat_ammo_discount) starts weighing whether ammo
## held back "for later" will actually get a chance to be spent before
## that later arrives, and squads read as more willing to pull back from
## a position that's turning bad (see _scheduled_retreat_urgency, used by
## _reposition_for_encirclement) — both scaling up as the scheduled time
## gets closer, not switching on all at once the instant this is called.
## Re-callable: adjusting the slider and confirming again just overwrites
## the pending time rather than stacking a second one.
func order_scheduled_retreat(delay_seconds: float) -> void:
	if battle_over:
		return
	# Rounded to the nearest whole minute — the slider's own delay is
	# already whole minutes, but scenario_elapsed_time it's added to
	# generally isn't, so the raw sum would otherwise land on some odd
	# :MM:SS a player has no reason to care about.
	scheduled_retreat_time = round((scenario_elapsed_time + delay_seconds) / 60.0) * 60.0
	combat_log.add_entry("--- Retreat scheduled for %s ---" % clock_string(scheduled_retreat_time))


## Countermands a pending order_scheduled_retreat — the commander changed
## their mind before the clock ran out. A no-op if nothing is scheduled, or
## if the scheduled retreat already fired (order_general_retreat's own
## player_general_retreat_ordered flag is what actually matters at that
## point; there's no "undoing" an already-ordered withdrawal).
func cancel_scheduled_retreat() -> void:
	if is_inf(scheduled_retreat_time):
		return
	combat_log.add_entry("--- Scheduled retreat (was set for %s) cancelled ---" % clock_string(scheduled_retreat_time))
	scheduled_retreat_time = INF


## Checked every tick (see _process) — fires the exact same order the
## player's own immediate retreat button does, the instant the scheduled
## time actually arrives. `player_general_retreat_ordered` itself is
## order_general_retreat's own guard against firing twice, so this can
## check plainly on time alone without its own separate one-shot flag.
func _check_scheduled_retreat() -> void:
	if is_inf(scheduled_retreat_time) or player_general_retreat_ordered or battle_over:
		return
	if scenario_elapsed_time >= scheduled_retreat_time:
		order_general_retreat()


## 0.0 (no scheduled retreat, or one still comfortably far off) to 1.0
## (imminent or already due) — how much MORE willing a squad should be to
## pull back from a position that's starting to look bad, now that an
## overall withdrawal is already planned rather than being reacted to
## from scratch. See _reposition_for_encirclement's own use of this to
## relax its trigger thresholds — a real unit that knows the whole line
## is pulling out soon doesn't hold a marginal position as stubbornly as
## one with no such order at all.
func _scheduled_retreat_urgency() -> float:
	if is_inf(scheduled_retreat_time):
		return 0.0
	var time_remaining: float = scheduled_retreat_time - scenario_elapsed_time
	if time_remaining <= 0.0:
		return 1.0
	return clamp(1.0 - time_remaining / GameConfig.SCHEDULED_RETREAT_URGENCY_WINDOW_S, 0.0, 1.0)


## 1.0 (no discount — conserve ammo normally) down to 0.0 (spend freely,
## nothing held back) depending on whether this mortar's OWN remaining
## stock could realistically even be fired off, at its own natural reload
## rate, before the scheduled retreat time arrives. Ammo saved "for
## later" that later never comes to use is simply wasted — carried off or
## abandoned at the exact same cost as if it had been fired — so once
## there plainly isn't enough time left to get through what's on hand
## anyway, conservation stops making sense. Comfortably ahead of that
## point (or with no scheduled retreat at all), reads as 1.0: no change
## to ordinary ammo-conservation behavior.
func _scheduled_retreat_ammo_discount(mortar: Unit) -> float:
	if is_inf(scheduled_retreat_time):
		return 1.0
	var time_remaining: float = max(scheduled_retreat_time - scenario_elapsed_time, 0.0)
	var time_needed_to_expend: float = float(mortar.mortar_rounds_remaining) * mortar.reload_time
	if time_needed_to_expend <= 0.0:
		return 1.0
	return clamp(time_remaining / time_needed_to_expend, 0.0, 1.0)


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
			unit.order_retreat(known_enemy_positions, _ally_positions_for(unit) + claimed)
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
## SQUADS only — mortars are deliberately left out. Calling off the infantry
## assault doesn't mean abandoning fire support: a mortar sitting well to
## the rear isn't at risk of being overrun the way forward squads are, and
## a real commander keeps supporting fires going (harassing the enemy,
## covering the withdrawal, still hunting for counter-battery range on the
## opposing mortar) rather than pulling a perfectly good gun out of action
## for no tactical reason. A mortar still retreats on its own if it's
## personally hit (Unit._apply_crew_casualties) — this just means the
## infantry giving up doesn't automatically drag it along too.
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
	var any_ordered := false
	var claimed: Array[Vector2] = []
	for unit in enemy_units:
		if unit.kind == Unit.Kind.SQUAD and unit.state == Unit.State.ACTIVE:
			if randf() < _squad_surrender_chance(unit):
				unit.state = Unit.State.SURRENDERED
				unit.state_changed.emit(unit)
				combat_log.log_squad_surrendered(unit)
				any_ordered = true
				continue
			unit.order_retreat(known_player_positions, _ally_positions_for(unit) + claimed)
			claimed.append(unit.move_target if unit.has_move_target else unit.global_position)
			combat_log.log_ordered_retreat(unit)
			_log_wounded_evacuation_outcome(unit)
			any_ordered = true
	if any_ordered:
		var casualty_percent: float = _compute_side_stats(enemy_units).casualty_percent
		combat_log.add_entry("--- Enemy commander orders a general retreat: the attack has failed (%.0f%% casualties) — mortars continue the fire mission ---" % casualty_percent)


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
	return stats.casualty_percent / 100.0 >= GameConfig.ENEMY_COMMANDER_RETREAT_THRESHOLD


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
## from, or flee one the way it would a real, still-armed contact.
## For the PLAYER side, this deliberately does NOT mean "currently
## is_visible" — it means "what the player's own side actually knows,"
## same standard as Unit.player_known_position/_has_been_sighted (see
## their own doc comments and _update_player_intel). A contact spotted
## moments ago and now merely out of direct line-of-sight hasn't un-
## happened just because the visibility flag flickered off; a retreat or
## cover choice built on strict real-time visibility alone can walk
## straight into (or right past) a threat the player's own side already
## has every reason to remember is there. The ENEMY side has no
## equivalent persistent-memory field (that fog-of-war model is
## deliberately one-directional — see the same doc comments), so it still
## reads plain, real-time is_visible.
func _known_enemy_positions(team: Unit.Team) -> Array[Vector2]:
	var opposing: Array[Unit] = enemy_units if team == Unit.Team.PLAYER else player_units
	var positions: Array[Vector2] = []
	for u in opposing:
		var still_a_threat: bool = u.state == Unit.State.ACTIVE or u.state == Unit.State.RETREATING
		if not still_a_threat:
			continue
		if team == Unit.Team.PLAYER:
			if u.player_has_been_sighted:
				positions.append(u.player_known_position)
		elif u.is_visible:
			positions.append(u.global_position)
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


func _ally_positions_for(unit: Unit) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for u in _ally_units_for(unit):
		out.append(u.global_position)
	return out


## Resolves one shot, logs its consequence, then checks for "bunching"
## spillover: a squad hit while another squad of its own side is crammed
## into the same patch of cover close by (see GameConfig.BUNCHING_RADIUS)
## has a real chance of catching that ally in the same burst/blast too —
## the actual mechanical teeth behind squads spreading out across DIFFERENT
## cover instead of piling into the same one (see Unit.seek_cover /
## GameConfig.nearest_cover_point's avoid_positions).
func _resolve_fire_and_check_bunching(attacker: Unit, target: Unit) -> void:
	var before := UnitCombatStats.before_hit(target)
	unit_combat_stats.register(attacker)
	var target_was_active := target.state == Unit.State.ACTIVE
	var hit := CombatResolver.resolve_fire(attacker, target, _ally_positions_for(target), _known_enemy_positions(target.team), _drone_directing_mortar_fire(attacker))
	unit_combat_stats.damage(attacker, target, before)
	_log_hit_consequence(target, target_was_active)
	if not hit or target.kind != Unit.Kind.SQUAD:
		return
	var spillover := _bunched_ally(target)
	if spillover == null:
		return
	var spillover_was_active := spillover.state == Unit.State.ACTIVE
	var before_spillover := UnitCombatStats.before_hit(spillover)
	spillover.take_hit(attacker.kind == Unit.Kind.MORTAR, _ally_positions_for(spillover), _known_enemy_positions(spillover.team))
	unit_combat_stats.damage(attacker, spillover, before_spillover)
	# A spillover victim is picked purely by proximity to the actual target
	# (see _bunched_ally) — it never had to be individually spotted to get
	# caught in the same burst, so unlike `target` above it may still be
	# unnumbered the first time its name needs to appear in the log.
	_assign_discovery_number(spillover)
	combat_log.log_bunching_spillover(target, spillover)
	_log_hit_consequence(spillover, spillover_was_active)


## True while `attacker`'s shot should get GameConfig.DRONE_DIRECTED_MORTAR_
## ACCURACY_MULTIPLIER's bonus — only the player's own mortar (the enemy
## has no doctrine-level recon choice at all) firing while the doctrine is
## actually DRONE_TEAM AND a friendly drone (active or backup — either one
## airborne means the team's ISR feed is live right now) is actually up.
## Checked fresh at resolution time (mortar shots land ~40 tactical seconds
## after firing — see _launch_mortar_shot/_resolve_pending_mortar_shots),
## the same moment the target's own moving/terrain state is read, not
## frozen at the instant the round left the tube.
func _drone_directing_mortar_fire(attacker: Unit) -> bool:
	if attacker.kind != Unit.Kind.MORTAR or attacker.team != Unit.Team.PLAYER:
		return false
	if recon_mode != GameConfig.ReconMode.DRONE_TEAM:
		return false
	return active_drone != null or backup_drone != null


## A same-side SQUAD close enough to `defender` (see GameConfig.BUNCHING_RADIUS)
## to plausibly catch the same burst/blast — one candidate per shot, rolled
## against GameConfig.BUNCHING_SPILLOVER_CHANCE, first qualifying hit wins.
func _bunched_ally(defender: Unit) -> Unit:
	for ally in _ally_units_for(defender):
		if ally.kind != Unit.Kind.SQUAD:
			continue
		if defender.global_position.distance_to(ally.global_position) > GameConfig.BUNCHING_RADIUS:
			continue
		if randf() < GameConfig.BUNCHING_SPILLOVER_CHANCE:
			return ally
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
## automatically by _update_mortar_resupply_requests for both sides, no
## player click involved for either one. Schedules BOTH waves
## up front (GameConfig.MORTAR_RESUPPLY_WAVE_COUNT — currently 2), each an
## independently-sampled log-normal delay (see GameConfig.
## sample_resupply_delay), with wave 2's delay measured from wave 1's own
## (already random) arrival rather than from this request — "a further 20
## rounds will arrive after approximately another hour" reads as one more
## hour on top of the first, not from the original ask. Both waves are
## scheduled regardless of how either one actually turns out later
## (including a failure) — see _update_mortar_resupply for where each one
## is actually resolved, independently, at its own arrival moment.
## Returns false (no-op) if this mortar isn't eligible: no confirmed
## contact yet, the crew's gone, or a request is already in flight.
func request_mortar_resupply(mortar: Unit) -> bool:
	if mortar.kind != Unit.Kind.MORTAR or mortar.state != Unit.State.ACTIVE:
		return false
	if not _has_sighted_enemy(mortar.team):
		return false
	if _mortar_resupply.has(mortar):
		return false

	var wave_arrival_times: Array[float] = []
	var warning_times: Array[float] = []
	var t: float = scenario_elapsed_time
	for i in GameConfig.MORTAR_RESUPPLY_WAVE_COUNT:
		t += GameConfig.sample_resupply_delay(GameConfig.MORTAR_RESUPPLY_DELAY_MEDIAN, GameConfig.MORTAR_RESUPPLY_DELAY_SIGMA)
		wave_arrival_times.append(t)
		# See GameConfig.MORTAR_RESUPPLY_ETA_WARNING_MEDIAN's own comment —
		# this is a SEPARATELY estimated lead time, not (arrival - 15min)
		# computed with perfect hindsight, so the "roughly 15 minutes"
		# heads-up really can end up wrong once the run actually resolves.
		var lead: float = GameConfig.sample_resupply_delay(GameConfig.MORTAR_RESUPPLY_ETA_WARNING_MEDIAN, GameConfig.MORTAR_RESUPPLY_ETA_WARNING_SIGMA)
		warning_times.append(t - lead)

	_mortar_resupply[mortar] = {
		"wave_arrival_times": wave_arrival_times,
		"warning_times": warning_times,
		"wave_warned": [false, false],
		"wave_resolved": [false, false],
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
## successful wave now hands off to a real, physical run (see
## _spawn_resupply_run) rather than staging rounds at a fixed point —
## unless the mortar itself isn't ACTIVE any more by the time its wave
## comes due, in which case the request quietly lapses (nothing to deliver
## to, and no run should ever be sent chasing a position that's gone).
func _update_mortar_resupply() -> void:
	for m in _mortar_resupply.keys():
		var record: Dictionary = _mortar_resupply[m]
		var arrivals: Array = record.wave_arrival_times
		var warnings: Array = record.warning_times
		var warned: Array = record.wave_warned
		var resolved: Array = record.wave_resolved
		for i in arrivals.size():
			if resolved[i]:
				continue
			if not warned[i] and scenario_elapsed_time >= warnings[i]:
				warned[i] = true
				if _should_narrate_mortar_logistics(m):
					combat_log.log_mortar_resupply_eta_warning(m)
			if scenario_elapsed_time >= arrivals[i]:
				resolved[i] = true
				if m.state != Unit.State.ACTIVE:
					pass # the position is gone — nothing to send a run toward
				elif m.mortar_rounds_remaining >= GameConfig.MORTAR_MAX_AMMO_ON_HAND:
					# The position is already about as stocked as a forward
					# firing point realistically keeps — the run simply never
					# leaves the rear (an ammunition supply point, not an
					# exposed load sitting next to the gun) rather than
					# walking all the way up only to be capped or wasted on
					# arrival. Requests were never gated on ammo level in the
					# first place (see _update_mortar_resupply_requests'
					# own doc comment) specifically so this can be checked
					# late, right before actually committing a physical run
					# to the trip, without ever having blocked the supply
					# chain from starting to move.
					if _should_narrate_mortar_logistics(m):
						combat_log.log_mortar_resupply_held(m)
				elif randf() < GameConfig.MORTAR_RESUPPLY_FAILURE_CHANCE:
					if _should_narrate_mortar_logistics(m):
						combat_log.log_mortar_resupply_failed(m)
				else:
					_spawn_resupply_run(m)
		record.wave_warned = warned
		record.wave_resolved = resolved
		_mortar_resupply[m] = record

	# Clean up once every wave has resolved — a fresh request cycle is only
	# eligible after that (see _update_mortar_resupply_requests).
	for m in _mortar_resupply.keys():
		var record: Dictionary = _mortar_resupply[m]
		var all_resolved := true
		for r in record.wave_resolved:
			if not r:
				all_resolved = false
				break
		if all_resolved:
			_mortar_resupply.erase(m)


## Nobody clicks a button for this on either side — each side's mortar
## requests its own resupply automatically the instant the first
## approaching enemy is spotted (that side's own _has_sighted_enemy flips
## true), not once ammo actually runs low: with a resupply run taking on
## the order of an hour or more to arrive at all, waiting for a real
## shortage before asking would already be too late. Deliberately NOT
## gated on current ammo level for that reason — a real commander gets the
## supply chain moving the moment a fight looks likely, not after the guns
## have gone quiet for want of rounds. `_mortar_resupply.has(m)` is the
## only real throttle: once a full 2-wave cycle resolves and is collected
## (see _update_mortar_resupply's own cleanup), THAT eligibility check
## re-applies — mostly harmless if the mortar barely fired in the
## meantime, but by then it typically has. Symmetric — the player's own
## mortar follows exactly the same rule as the enemy's, since a
## doctrine-driven game already puts unit-level logistics calls like this
## in the same autonomous-AI bucket as everything else a unit decides for
## itself mid-battle.
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
func _update_resupply_run_targets() -> void:
	for m in player_units + enemy_units:
		if _risk_holds.has(m): continue
		if m.kind != Unit.Kind.RESUPPLY_RUN or m.state != Unit.State.ACTIVE:
			continue
		if m.resupply_delivered:
			continue # homeward leg — a fixed destination set once at delivery, not re-tracked
		if m.resupply_target_mortar == null or m.resupply_target_mortar.state != Unit.State.ACTIVE:
			continue # handled by _resolve_resupply_run_arrivals below
		m.move_target = m.resupply_target_mortar.global_position
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
		return _mortar_advance_point(m, target_pos)
	var dest := _friendly_mortar_hunt_point(m, target_pos)
	if dest == m.global_position:
		return m.global_position # no safe route found this tick — try again next tick
	if dest.distance_to(_friendly_mortar_home_position) > GameConfig.MORTAR_HUNT_MAX_RANGE_FROM_HOME:
		return m.global_position # too far from what the crew considers safe territory, trusted lead or not
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
		if u.kind != Unit.Kind.MORTAR or u.state == Unit.State.DESTROYED:
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
	# out-rank a mortar that's still actually in the fight just because it
	# happens to come first in enemy_units. Only falls back to a visible
	# RETREATING one when no ACTIVE mortar is visible at all.
	var retreating_visible: Unit = null
	for u in enemy_units:
		if u.kind != Unit.Kind.MORTAR or not u.is_targetable_state() or not u.is_visible:
			continue
		if u.state == Unit.State.ACTIVE:
			return {"position": u.global_position, "trusted": true, "unit": u}
		if retreating_visible == null:
			retreating_visible = u
	if retreating_visible != null:
		return {"position": retreating_visible.global_position, "trusted": true, "unit": retreating_visible}

	var best_pos := Vector2.INF
	var best_time := -INF
	var best_unit: Unit = null
	for u in enemy_units:
		if u.kind != Unit.Kind.MORTAR or not u.is_targetable_state():
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
		if u.kind != Unit.Kind.MORTAR or not u.is_targetable_state() or is_inf(u.player_known_position.x):
			continue
		if u.player_known_position_time > seen_time:
			seen_time = u.player_known_position_time
			seen_pos = u.player_known_position
			seen_unit = u
	if seen_unit == null:
		return {}
	return {"position": seen_pos, "trusted": false, "unit": seen_unit}


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
	var frontmost_x := -INF
	var min_y := INF
	var max_y := -INF
	var found := false
	for u in player_units:
		if u.kind == Unit.Kind.SQUAD and u.state == Unit.State.ACTIVE:
			found = true
			frontmost_x = max(frontmost_x, u.global_position.x)
			min_y = min(min_y, u.global_position.y)
			max_y = max(max_y, u.global_position.y)
	if not found:
		return false
	var already_ahead: bool = mortar.global_position.x > frontmost_x
	var already_outside_band: bool = mortar.global_position.y < min_y or mortar.global_position.y > max_y
	if dest.x > frontmost_x and not already_ahead:
		return true
	if (dest.y < min_y or dest.y > max_y) and not already_outside_band:
		return true
	return false


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
	var target_distance: float = GameConfig.MORTAR_MAX_RANGE * 0.9 # comfortably in range, not right on the edge

	var valid_candidates: Array[Vector2] = []
	for offset_deg in [0.0, -15.0, 15.0, -30.0, 30.0, -45.0, 45.0]:
		var dir: Vector2 = base_dir.rotated(deg_to_rad(offset_deg))
		var candidate: Vector2 = target_pos - dir * target_distance
		if GameConfig.is_building_at(candidate) or GameConfig.path_crosses_building(mortar.global_position, candidate):
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

	for i in range(_drones_swapping.size() - 1, -1, -1):
		_drones_swapping[i].time_left -= scenario_delta
		if _drones_swapping[i].time_left <= 0.0:
			_drones_ready.append(_drones_swapping[i].charge)
			_drones_swapping.remove_at(i)

	_update_returning_drones()

	if active_drone != null:
		_update_active_drone(scenario_delta) # may send itself home, or (rarely) crash outright — see the sacrifice branch inside

	if backup_drone != null:
		_update_backup_drone(scenario_delta) # may send itself home, or get promoted below

	if active_drone == null and backup_drone != null:
		active_drone = backup_drone
		backup_drone = null

	if active_drone == null and not _drones_ready.is_empty():
		_launch_drone()

	if active_drone != null and backup_drone == null and not _drones_ready.is_empty():
		var watched: Unit = _visible_engageable_mortar()
		if watched != null:
			var time_until_active_rtb: float = _drone_time_until_rtb(active_drone)
			var backup_travel_time: float = drone_team.global_position.distance_to(watched.global_position) / GameConfig.DRONE_CRUISE_SPEED
			if time_until_active_rtb <= backup_travel_time:
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
	var risk := 0.0
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
	var destination: Vector2 = GameConfig.nearest_hidden_point(drone_team.global_position, threats, false)
	if destination == drone_team.global_position:
		return # nowhere better to go this tick — try again next tick if the threat's still closing
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


func _launch_drone() -> void:
	var charge: float = _pop_best_battery(_drones_ready)
	var d := _make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, drone_team.global_position)
	d.drone_battery_charge = max(charge - GameConfig.DRONE_LAUNCH_CHARGE_COST, 0.0) # climb-out to DRONE_ALTITUDE_M isn't free — see GameConfig's own comment
	d.state_changed.connect(_on_drone_state_changed)
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
	d.drone_battery_charge -= scenario_delta / GameConfig.DRONE_FULL_CHARGE_FLIGHT_TIME

	if d.drone_battery_charge <= 0.0:
		_crash_drone(d, _visible_engageable_mortar())
		active_drone = null
		return

	var planned_destination := Vector2.INF
	if unit_doctrine_for(d).risk != "inherit":
		planned_destination = _drone_search_target()
		if not _drone_risk_accepts(d, planned_destination):
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
				d.move_speed = GameConfig.DRONE_CRUISE_SPEED
				d.movement_predictable = false
				return
		_send_drone_home(d)
		active_drone = null
		return

	d.move_target = _drone_search_target() if is_inf(planned_destination.x) else planned_destination
	d.has_move_target = true
	d.move_queue.clear()
	d.move_speed = GameConfig.DRONE_CRUISE_SPEED
	d.movement_predictable = false


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
	d.drone_battery_charge -= scenario_delta / GameConfig.DRONE_FULL_CHARGE_FLIGHT_TIME

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
	d.move_speed = GameConfig.DRONE_CRUISE_SPEED
	d.movement_predictable = false


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
	var distance_home: float = d.global_position.distance_to(drone_team.global_position)
	var time_needed_home: float = distance_home / GameConfig.DRONE_CRUISE_SPEED
	var margin_time: float = GameConfig.DRONE_RTB_SAFETY_MARGIN / GameConfig.DRONE_CRUISE_SPEED
	# Also reserves enough to cover the letdown cost it'll actually be
	# charged the moment it lands (see GameConfig.DRONE_LANDING_CHARGE_COST)
	# — without this, a drone could turn for home with "just enough," fly
	# the whole way back, and land with less charge than it actually has
	# left to give.
	var charge_needed_to_get_home: float = (time_needed_home + margin_time) / GameConfig.DRONE_FULL_CHARGE_FLIGHT_TIME + GameConfig.DRONE_LANDING_CHARGE_COST
	var charge_to_spare: float = d.drone_battery_charge - charge_needed_to_get_home
	return charge_to_spare * GameConfig.DRONE_FULL_CHARGE_FLIGHT_TIME


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
## drone_team) and lands it for real: free the Unit, drop whatever charge
## it landed with (usually just the small safety-margin reserve, though a
## backup sent home early could have much more) into the pool to recharge
## from there, and immediately hand the airframe the best-charged battery
## now available (which might be that very one) for a quick swap — landing
## never means the full ~100-minute recharge for the AIRFRAME; only running
## the whole pool down does that, and even then only to whichever battery
## it draws next.
func _update_returning_drones() -> void:
	for i in range(returning_drones.size() - 1, -1, -1):
		var d: Unit = returning_drones[i]
		if d.has_move_target:
			# Re-aimed every tick at wherever the ground crew currently is,
			# not just wherever it was the instant RTB was ordered — see
			# _update_drone_team_evasion, which can move it mid-flight.
			# Mirrors the mortar resupply run's own "always chase the
			# mortar's current position" tracking for the same reason.
			d.move_target = drone_team.global_position
			continue # still en route
		returning_drones.remove_at(i)
		player_units.erase(d)
		# The letdown back to the ground isn't free either — see GameConfig.
		# DRONE_LANDING_CHARGE_COST; _drone_time_until_rtb already reserves
		# for this so it's not normally a surprise, but clamp at 0 regardless.
		_battery_pool.append(max(d.drone_battery_charge - GameConfig.DRONE_LANDING_CHARGE_COST, 0.0))
		d.queue_free()
		_drones_swapping.append({"time_left": GameConfig.DRONE_BATTERY_SWAP_DURATION, "charge": _pop_best_battery(_battery_pool)})


## How worried the drone team should still be that an as-yet-undiscovered
## enemy mortar exists — see GameConfig.MORTAR_CONFIDENCE_DECAY_TAU/_FLOOR
## for the full reasoning. Two cases: a hard, certain 0.0 once every enemy
## mortar (by kind, regardless of whether it's ever been spotted — the
## same omniscient state read _visible_engageable_mortar and everything
## else here already relies on) is confirmed out of action, matching a
## real commander eventually being told "the enemy mortars are destroyed";
## short of that certainty, a smooth decay from ~1.0 toward FLOOR as real
## tactical time passes with no mortar fire detected anywhere at all
## (_last_detected_mortar_fire — muzzle-flash/trajectory detection, not
## visual spotting, so this already covers a mortar that's never been seen
## even once).
func _mortar_existence_confidence() -> float:
	var any_active_enemy_mortar := false
	var last_fire_time := 0.0 # battle start, if nothing's fired yet at all
	for u in enemy_units:
		if u.kind != Unit.Kind.MORTAR:
			continue
		if u.state == Unit.State.ACTIVE:
			any_active_enemy_mortar = true
		var info: Dictionary = _last_detected_mortar_fire.get(u, {})
		if not info.is_empty():
			last_fire_time = max(last_fire_time, info.time)
	if not any_active_enemy_mortar:
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
		if f.state == Unit.State.ACTIVE:
			nearest = min(nearest, pos.distance_to(f.global_position))
	return nearest


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
	for u in enemy_units:
		if u.state == Unit.State.ACTIVE and u.is_visible:
			_recent_enemy_contacts[u] = {"position": u.global_position, "time": scenario_elapsed_time}
		elif u.kind == Unit.Kind.MORTAR and u.state == Unit.State.ACTIVE:
			var info: Dictionary = _last_detected_mortar_fire.get(u, {})
			if not info.is_empty():
				_recent_enemy_contacts[u] = info


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
	var best_fire_time := -INF
	for u in enemy_units:
		if u.kind != Unit.Kind.MORTAR or u.state != Unit.State.ACTIVE:
			continue
		var info: Dictionary = _last_detected_mortar_fire.get(u, {})
		if info.is_empty():
			continue
		if scenario_elapsed_time - info.time > GameConfig.DRONE_MORTAR_FIRE_LEAD_EXPIRY:
			continue
		if not _in_friendly_mortar_range(info.position):
			continue
		if info.time > best_fire_time:
			best_fire_time = info.time
			lead_pos = info.position
	if not is_inf(lead_pos.x):
		var lead_score: float = GameConfig.TARGET_PRIORITY_MORTAR * GameConfig.TARGET_PRIORITY_MORTAR_LEAD_DISCOUNT
		if lead_score > best_score:
			best_score = lead_score
			best_pos = lead_pos
			var lead_age: float = scenario_elapsed_time - best_fire_time
			_drone_pilot_reasoning = {"tier": "Fresh mortar fire-detection lead", "detail": "Muzzle-flash/trajectory fix on an enemy mortar, %.0fs old, still in friendly mortar range." % lead_age, "target": best_pos}

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
		if not is_inf(joint_pos.x) and GameConfig.TARGET_PRIORITY_MORTAR > best_score:
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

	var best_squad: Unit = null
	var best_squad_score := -1.0
	for u in enemy_units:
		if u.kind == Unit.Kind.SQUAD and u.state == Unit.State.ACTIVE and u.is_visible:
			var score: float = _squad_danger_priority(u)
			if score > best_squad_score:
				best_squad_score = score
				best_squad = u
	if best_squad != null and best_squad_score > best_score:
		best_score = best_squad_score
		best_pos = best_squad.global_position
		_drone_pilot_reasoning = {"tier": "Tracking dangerous squad", "detail": "The most dangerous currently-visible enemy squad, danger score %.1f/%.1f (closer to a friendly unit = higher)." % [best_squad_score, GameConfig.TARGET_PRIORITY_SQUAD_MAX], "target": best_pos}

	var best_retreating: Unit = null
	var best_retreating_dist := INF
	for u in enemy_units:
		if u.state == Unit.State.RETREATING and u.is_visible:
			var d: float = _nearest_active_friendly_distance(u.global_position)
			if d < best_retreating_dist:
				best_retreating_dist = d
				best_retreating = u
	if best_retreating != null:
		# High priority once the fight's effectively over (the enemy's own
		# general retreat) — but while the battle is still actually going,
		# one broken, defanged straggler (a mortar crew that's abandoned its
		# gun counts here too, not as "the mortar priority") is a low-
		# priority distraction next to whatever's still actually fighting.
		var retreating_score: float = GameConfig.TARGET_PRIORITY_RETREATING_ENEMY if enemy_general_retreat_ordered else GameConfig.TARGET_PRIORITY_RETREATING_ENEMY_LOW
		if retreating_score > best_score:
			best_score = retreating_score
			best_pos = best_retreating.global_position
			_drone_pilot_reasoning = {"tier": "Finishing a retreating contact", "detail": "Nearest visible retreating enemy — %s." % ("the fight looks over, worth finishing" if enemy_general_retreat_ordered else "battle still on, so this is a low-priority distraction that still narrowly won"), "target": best_pos}

	var flank_candidates: Array = _flank_watch_candidates()

	var routine_score: float = GameConfig.TARGET_PRIORITY_UNDISCOVERED_MORTAR_SWEEP * _mortar_existence_confidence()
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
	if not flank_candidates.is_empty():
		# Watching the mortar's blind side is a standing duty, independent
		# of how confident anyone is that a second mortar exists — see this
		# function's own doc comment for why these two must NOT be blended
		# into one confidence-scaled number.
		routine_score = max(routine_score, GameConfig.DRONE_FLANK_WATCH_STANDING_PRIORITY)
	if routine_score > best_score or is_inf(best_pos.x):
		var routine_pick: Dictionary = _drone_routine_recon_target(flank_candidates)
		if not routine_pick.is_empty():
			best_pos = routine_pick.point
			var kind: String = "an unwatched gap toward our mortar's flank" if routine_pick.key.begins_with("flank:") else "a general-area sweep cell"
			_drone_pilot_reasoning = {"tier": "Routine background recon", "detail": "No urgent lead — checking %s (candidate value %.2f, mortar-existence confidence %.2f)." % [kind, routine_pick.value, _mortar_existence_confidence()], "target": best_pos}

	# A last, universal guard: every tier above is supposed to only ever
	# offer a real, in-area position (an actual enemy unit's position, a
	# probe already clamped by _flank_watch_candidates, a sweep waypoint
	# that's always been well inside the map), but a live enemy unit is the
	# one case not otherwise clamped here — nothing currently drives one
	# north/south off the map, but should that ever change, this is what
	# keeps the drone from following it into ground that belongs to another
	# unit's sector entirely, regardless of the reason.
	return _clamp_to_drone_operating_area(best_pos)


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
## (main.gd's JSON export of it would otherwise need its own conversion
## pass; keeping the snapshot itself JSON-native avoids that entirely).
func _pos_to_debug_dict(point: Vector2) -> Dictionary:
	return {"x": roundi(point.x / GameConfig.PIXELS_PER_METER), "y": roundi(point.y / GameConfig.PIXELS_PER_METER)}


## A smooth, continuous stand-in for the row bias _sweep_candidates only
## ever evaluates at its own 25 fixed grid waypoints — linearly
## interpolated between GameConfig.DRONE_SEARCH_GRID_ROWS_M's row centers
## (clamped at the map's own north/south edges past the first/last row),
## summing the same squad- and mortar-hunting weights _sweep_candidates
## itself adds together. Used by estimated_enemy_likelihood below to paint
## a full-map gradient for the enemy heat-map overlay (main.gd's "e" key)
## rather than 25 isolated dots — never used by any actual sweep decision,
## which still runs on the real discrete grid.
func _row_bias_at_y(y: float) -> float:
	var rows_m: Array[float] = GameConfig.DRONE_SEARCH_GRID_ROWS_M
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
## waypoints. Read-only, for the enemy heat-map overlay (main.gd's "e"
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
func _point_currently_observed(point: Vector2) -> bool:
	if active_drone != null and active_drone.state == Unit.State.ACTIVE:
		if active_drone.global_position.distance_to(point) <= GameConfig.DRONE_DETECTION_RANGE and GameConfig.has_aerial_los(active_drone.global_position, point):
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


## Read-only introspection into the drone's current reasoning — "what is
## the drone pilot thinking right now, and why" — for the player-
## toggleable debug overlay (see main.gd's DronePilotDebugPanel) and, while
## the battle is paused, for external inspection of exactly what the
## decision logic sees at that frozen moment (main.gd also exports this to
## a JSON file whenever the overlay is on, specifically so it can be
## inspected from outside the running game). Purely descriptive — nothing
## here may ever feed back into an actual decision. {"active": false} if no
## drone is currently airborne to report on (SPOTTER recon mode, or a
## DRONE_TEAM battle between sorties).
func drone_pilot_debug_snapshot() -> Dictionary:
	if active_drone == null:
		return {"active": false}

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


## The single currently-visible, still-ACTIVE, in-range enemy mortar worth
## the backup-drone/self-sacrifice decisions actually acting on — used by
## _update_active_drone/_update_backup_drone/the backup-launch trigger in
## _update_drone_operations, all of which are asking "is there one right
## now we can actually DO something about," not just "is there one worth
## watching" (see _priority_visible_enemy_mortar for that, weaker
## question — _drone_search_target's own top tier). A RETREATING mortar
## has already had its crew abandon the gun for good (Unit.
## _apply_crew_casualties — it will never fire again no matter how well
## it's watched), and one outside
## GameConfig.MORTAR_MAX_RANGE of the friendly mortar can't be engaged
## right now regardless of visibility — sacrificing a drone, or spending a
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
	var fallback: Unit = null
	for u in enemy_units:
		if u.kind != Unit.Kind.MORTAR or u.state != Unit.State.ACTIVE or not u.is_visible:
			continue
		if _is_priority_hunt_target(u):
			return {"unit": u, "priority": true}
		if fallback == null:
			fallback = u
	return {} if fallback == null else {"unit": fallback, "priority": false}


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
			return m.global_position.distance_to(pos) <= GameConfig.MORTAR_MAX_RANGE
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
		if u.state != Unit.State.ACTIVE and u.state != Unit.State.RETREATING:
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
func _sweep_candidates() -> Array:
	var row_count: int = GameConfig.DRONE_SEARCH_GRID_ROWS_M.size()
	var columns_per_row: int = GameConfig.DRONE_SEARCH_GRID_COLUMNS_M.size()
	var waypoints: Array[Vector2] = GameConfig.drone_search_waypoints_px()
	var out: Array = []
	for row_i in row_count:
		for col_i in columns_per_row:
			var idx: int = row_i * columns_per_row + col_i
			var point: Vector2 = waypoints[idx]
			var approach: float = _enemy_approach_likelihood(point)
			var value: float = (GameConfig.DRONE_SWEEP_ROW_WEIGHTS[row_i] + GameConfig.DRONE_MORTAR_HUNT_ROW_WEIGHTS[row_i]) * approach
			if _area_confirmed_clear(point) or _point_currently_observed(point):
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
	var candidates: Array = _sweep_candidates() + flank_candidates
	if candidates.is_empty():
		return {}

	var current: Dictionary = {}
	for c in candidates:
		if c.key == _drone_current_destination_key:
			current = c
			break

	if not current.is_empty():
		var arrived: bool = active_drone.global_position.distance_to(current.point) <= _drone_destination_arrival_radius(current.key)
		if not arrived:
			return current # still en route — keep heading there
		_drone_destination_last_visited[current.key] = scenario_elapsed_time

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
func _mortar_advance_point(mortar: Unit, target_pos: Vector2) -> Vector2:
	var base_dir: Vector2 = (target_pos - mortar.global_position).normalized()
	var target_distance: float = GameConfig.MORTAR_MAX_RANGE * 0.9 # comfortably in range, not right on the edge
	for offset_deg in [0.0, -15.0, 15.0, -30.0, 30.0, -45.0, 45.0]:
		var dir: Vector2 = base_dir.rotated(deg_to_rad(offset_deg))
		var candidate: Vector2 = target_pos - dir * target_distance
		if GameConfig.is_building_at(candidate) or GameConfig.path_crosses_building(mortar.global_position, candidate):
			continue
		return candidate
	return mortar.global_position


## Whether an UNWATCHED (not currently is_visible — that's its own,
## separate "spotted" trigger, checked before this is even called) known
## enemy has actually closed to genuine overrun danger of `m`'s crew.
## Proximity alone isn't the real question — a known enemy unit merely
## being nearby doesn't mean it can actually find this position; it needs
## real line of sight to it, same as any other spotting-adjacent check in
## this file. Without this, a mortar would panic and abandon a perfectly
## good, still-concealed position just because an enemy happened to pass
## within range while blind to it (terrain in the way) — "the self risk
## would be low because we don't think the enemy has scouting on our
## position" is exactly the case this excludes. A stronger, deterministic
## check than waiting on the real (probabilistic, gradual) spot roll:
## genuinely blocked LOS means no route to being found exists right now,
## not just "hasn't happened yet."
func _unwatched_threat_closing(m: Unit) -> bool:
	for pos in _known_enemy_positions(m.team):
		if m.global_position.distance_to(pos) <= GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE and GameConfig.has_direct_los(pos, m.global_position):
			return true
	return false


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
func _decide_mortar_action(m: Unit) -> void:
	var opposing: Array[Unit] = enemy_units if m.team == Unit.Team.PLAYER else player_units

	# Step 0 — resolve this tick's shot exactly once, through the memoized
	# accessor, so every tier below sees the identical answer _tick_fire
	# already acted on (or will act on — a genuinely dry mortar can never
	# actually fire regardless of what _pick_target returns, hence the
	# ammo conjunct here).
	var target: Unit = _mortar_shot_this_tick(m, opposing)
	if _risk_holds.has(m):
		_mortar_reasoning[m] = {"tier": "Self-risk policy", "detail": m.last_order_reason}
		return
	var has_shot: bool = target != null and m.mortar_rounds_remaining > 0
	if has_shot:
		_mortar_reasoning[m] = {"tier": "Target available", "detail": "A target is selected; no new movement order from this decision. Reload and firing gates still apply."}
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
	# spotted/threatened framing when both would apply.
	# Computed once, up front, so every tier below (including out-of-ammo,
	# which used to decide entirely without checking this at all) can
	# react to "something is actually bearing down on me right now" —
	# see _relocate_mortar's own `force_urgent` doc comment for why that
	# distinction matters beyond just which combat-log line narrates it.
	var spotted: bool = m.is_visible
	var threat_closing: bool = not spotted and _unwatched_threat_closing(m)

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
			_issue_mortar_move(m, run.global_position, GameConfig.MORTAR_RELOCATE_SPEED, "linkup")
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
		if _relocate_mortar(m, "out_of_ammo", spotted or threat_closing):
			if _should_narrate_mortar_logistics(m):
				combat_log.log_mortar_relocating_out_of_ammo(m)
			_mortar_reasoning[m] = {"tier": "Preserve self", "detail": "Out of ammunition — relocating."}
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
		if _relocate_mortar(m, "evade"):
			combat_log.log_relocate(m, true)
			_mortar_reasoning[m] = {"tier": "Preserve self", "detail": "Just took counter-battery fire — displacing."}
		else:
			_mortar_reasoning[m] = {"tier": "Preserve self", "detail": "Just took counter-battery fire — wanted to displace, no route this tick."}
		return

	if (spotted or threat_closing) and unit_doctrine_for(m).risk == "inherit":
		# By this point _pick_target has already had every chance to
		# engage (including its own ammo-conservation override for this
		# exact range), so "nothing to shoot" here genuinely means out of
		# ammo, reload not up, or no real target — not one being ignored.
		# Always urgent: reaching this branch at all already means
		# "spotted or a threat has a clear shot from overrun range," the
		# same "current position is compromised" situation counter-
		# battery evasion treats as urgent above.
		if _relocate_mortar(m, "conceal" if spotted else "evade", true):
			if _should_narrate_mortar_logistics(m):
				if spotted:
					combat_log.log_mortar_relocating_for_cover(m)
				else:
					combat_log.log_mortar_relocating_from_threat(m)
			_mortar_reasoning[m] = {"tier": "Preserve self", "detail": "Spotted with nothing to shoot — relocating for cover." if spotted else "A threat with a clear line of sight is closing — relocating."}
		else:
			_mortar_reasoning[m] = {"tier": "Preserve self", "detail": "Wanted to relocate, no route this tick."}
		return

	# Tier 2 — Destroy enemy mortars (the MOVEMENT half only — the
	# targeting half, "an enemy mortar candidate always wins," already
	# lives unconditionally in _pick_target and is reflected in `target`
	# above whenever one's actually in range).
	var fix := _mortar_hunt_fix_for(m)
	if not fix.is_empty():
		if m.global_position.distance_to(fix.position) <= GameConfig.MORTAR_MAX_RANGE:
			if current_intent == "hunt":
				# Now in range — stop closing and get to work, rather than
				# finishing the walk to a farther point computed earlier.
				_clear_mortar_move(m)
			_mortar_reasoning[m] = {"tier": "Destroy enemy mortars", "detail": "In range of a known enemy mortar."}
			return
		var dest := _mortar_hunt_destination_for(m, fix.position, fix.trusted)
		if dest != m.global_position:
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
		_mortar_reasoning[m] = {"tier": "Destroy enemy mortars", "detail": "Wants to close on a known enemy mortar, no acceptable route this tick."}
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


## Public accessor for an out-of-band developer view of live mortar
## decisions, mirroring drone_pilot_debug_snapshot() — see main.gd's
## _write_debug_snapshot for why this is written unconditionally, every
## frame, rather than gated on any on-screen toggle. Deliberately includes
## BOTH sides (an out-of-band developer file, not something the player
## sees — same precedent as battle_history_viewer.gd's own deliberate
## ground-truth omniscience); if a future on-screen panel is ever built
## from this, THAT should stay player-mortars-only, matching _should_
## narrate_mortar_logistics's existing fog-of-war boundary.
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
			"reasoning": reasoning,
		}
	return out


func _process(delta: float) -> void:
	if battle_over or combat_log == null or is_paused:
		return

	delta *= playback_speed
	elapsed_time += delta
	_seconds_since_last_shot += delta

	var scenario_delta: float = delta * _current_time_scale()
	scenario_elapsed_time += scenario_delta

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
	_update_joint_mortar_hunt()
	_update_enemy_squad_advance()
	_update_friendly_squad_positioning()
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
	_update_player_intel()
	_check_enemy_commander_retreat()
	_check_scheduled_retreat()
	_prune_fire_flashes()
	_record_unit_decisions()
	_check_battle_end()
	queue_redraw() # keep fire-tracer fade-out animating smoothly
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
			if not CombatResolver.has_live_observer(target, observers):
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
	if unit.kind == Unit.Kind.MORTAR and GameConfig.is_building_at(unit.global_position):
		return # no overhead clearance to lob a round from inside a building
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
		_record_shot(unit, target)
		_launch_mortar_shot(unit, target)
		unit.fire_timer = unit.reload_time
		# Shoot-and-scoot doctrine: displace after EVERY shot, procedurally,
		# whether or not it's currently spotted — that's the whole point of
		# the doctrine (see design doc). A hold-position mortar does NOT do
		# this — it only relocates reactively, if actually spotted, which
		# _update_friendly_mortar_concealment's per-tick check already
		# covers (including the tick right after firing, if firing is what
		# exposed it) — no separate trigger needed here for that case.
		#
		# A shot AT an enemy mortar is forced urgent — fast (MORTAR_RELOCATE_
		# SPEED_URGENT) and searching farther out (CONCEALMENT_SEARCH_RINGS_
		# URGENT_M) — rather than waiting on Unit.evading_counter_battery,
		# which only gets set reactively once a strike has already landed
		# nearby (_resolve_pending_counter_battery, 1-3 tactical minutes
		# later — too late to inform THIS displacement). Engaging a known
		# enemy mortar directly invites its own side's return fire (mortars
		# are each other's highest-priority target — see
		# _resolve_mortar_counter_battery's own doc comment), and with CB
		# response now a single, higher shared rate for every shot
		# (MORTAR_COUNTER_BATTERY_CHANCE, see its own doc comment) rather
		# than a reduced one for a scooting crew, a normal-speed, narrow-
		# ring displacement right after that specific kind of shot is no
		# longer urgent enough to reliably be clear when the response
		# arrives.
		#
		# Queued, not issued immediately — a real crew doesn't teleport into
		# motion the instant the round is away; see _queue_mortar_
		# displacement / GameConfig.MORTAR_SETUP_TEARDOWN_TIME for the real
		# pack-up delay before this walk actually begins.
		#
		# A hold-position doctrine is a standing preference, not a suicide
		# pact: with GameConfig.MORTAR_DENSITY_FORCE_SCOOT_COUNT or more
		# DIFFERENT enemy mortars already known to be in range (regardless
		# of what's actually being shot at right now), the real per-shot
		# risk of drawing counter-battery from at least one of them is
		# already severe enough to override it — see that constant's own
		# doc comment for the probability math. Player-only, matching this
		# project's "enemy may differ" convention.
		var density_forces_scoot: bool = unit.team == Unit.Team.PLAYER \
			and _known_enemy_mortars_in_range(unit.global_position) >= GameConfig.MORTAR_DENSITY_FORCE_SCOOT_COUNT
		if unit.shoot_and_scoot or density_forces_scoot:
			var forced_urgent := target.kind == Unit.Kind.MORTAR or density_forces_scoot
			var urgent := unit.evading_counter_battery or forced_urgent
			unit.evading_counter_battery = false
			_queue_mortar_displacement(unit, "scoot", urgent)
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
	_resolve_fire_and_check_bunching(unit, target)
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
func _launch_mortar_shot(mortar: Unit, target: Unit) -> void:
	mortar.mortar_rounds_remaining -= 1 # spent the instant it's fired, hit or miss — you don't get the shell back
	var aim_point: Vector2 = _mortar_aim_point(target)
	_pending_mortar_shots.append({
		"mortar": mortar,
		"target": target,
		"aim_point": aim_point,
		"impact_time": scenario_elapsed_time + GameConfig.MORTAR_FLIGHT_TIME,
	})
	_fire_flashes.append({
		"from": mortar.global_position, "to": aim_point, "team": mortar.team, "time": elapsed_time, "is_mortar": true,
	})
	_history_fire_events.append({
		"from": mortar.global_position, "to": aim_point, "team": mortar.team, "time": scenario_elapsed_time, "is_mortar": true,
	})
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


## Resolves any mortar shots whose flight time has elapsed. A target that's
## since been destroyed or reached safety leaves nothing for the shell to
## hit. Otherwise, the shell lands at its aim_point regardless — if the
## target has since moved beyond MORTAR_EVASION_RADIUS from that spot, the
## anticipated position was simply wrong and the shot misses outright, no
## roll needed; a target still nearby gets the normal CombatResolver roll
## (using ITS CURRENT state at impact — cover, movement — same as any other
## hit resolution). Enemy-alert and hit-consequence logging happen here,
## at impact, not at launch — the target doesn't know it's been fired on
## until the shell actually arrives.
func _resolve_pending_mortar_shots() -> void:
	var still_pending: Array[Dictionary] = []
	for shot in _pending_mortar_shots:
		if scenario_elapsed_time < shot.impact_time:
			still_pending.append(shot)
			continue
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

		var drift: float = target.global_position.distance_to(shot.aim_point)
		if drift > GameConfig.MORTAR_EVASION_RADIUS:
			combat_log.log_mortar_shot_evaded(shot.mortar, target)
			continue

		if target.team == Unit.Team.ENEMY and target.kind == Unit.Kind.SQUAD and not enemy_alerted:
			enemy_alerted = true
			_alert_enemy_squads()

		_resolve_fire_and_check_bunching(shot.mortar, target)
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
	var alerted_any := false
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
		alerted_any = true
	if alerted_any:
		combat_log.add_entry("--- Enemy is alerted: squads moving carefully, using cover ---")


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
func _update_enemy_squad_advance() -> void:
	for u in enemy_units:
		if u.kind != Unit.Kind.SQUAD or u.state != Unit.State.ACTIVE or u.has_move_target:
			continue
		if not u.sought_cover:
			continue
		if _pick_target(u, player_units) != null or _risk_holds.has(u):
			continue # something to shoot at right now — stay and fight
		var rush_target := _next_advance_point(u)
		if rush_target == u.global_position:
			continue
		u.last_order_reason = "No target available: advance another bound toward the current objective."
		u.move_target = rush_target
		u.has_move_target = true
		u.move_queue.clear()
		u.move_speed = GameConfig.ENEMY_ADVANCE_SPEED
		u.movement_predictable = false # a deliberate rush, not the road-bound march


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
	return _weighted_advance_point_pick(candidates, GameConfig.ENEMY_ADVANCE_ANGLES_DEG, known_player_positions, friendly_center, other_bearings)


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
	return GameConfig.CURRENT_MAP.village_center


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
	for u in player_units:
		if u.kind != Unit.Kind.SQUAD or u.state != Unit.State.ACTIVE or not u.has_move_target:
			continue
		if u.last_order_reason != "Screen an open approach to the friendly mortar.":
			continue
		if mortar == null or is_inf(threat.x):
			u.has_move_target = false
			u.last_order_reason = "Screening no longer needed; repositioning."
			continue
		u.move_target = mortar.global_position + (threat - mortar.global_position).normalized() * GameConfig.MORTAR_PROTECTIVE_RADIUS

	if mortar == null or is_inf(threat.x):
		return

	var responder: Unit = null
	var best_dist := INF
	for u in player_units:
		if u.kind != Unit.Kind.SQUAD or u.state != Unit.State.ACTIVE or u.has_move_target or at_risk.has(u):
			continue
		if _pick_target(u, enemy_units) != null or _risk_holds.has(u):
			continue
		var d: float = u.global_position.distance_to(mortar.global_position)
		if d < best_dist:
			best_dist = d
			responder = u
	if responder == null:
		return

	var block_point: Vector2 = mortar.global_position + (threat - mortar.global_position).normalized() * GameConfig.MORTAR_PROTECTIVE_RADIUS
	responder.last_order_reason = "Screen an open approach to the friendly mortar."
	responder.move_target = block_point
	responder.has_move_target = true
	responder.move_queue.clear()
	responder.move_speed = GameConfig.REPOSITION_SPEED
	responder.movement_predictable = false
	combat_log.log_squad_blocking_flank(responder)


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
	# All three thresholds relax together toward their own _URGENT values
	# as a scheduled retreat gets closer (see _scheduled_retreat_urgency's
	# own doc comment) — with none scheduled, urgency is 0 and every one
	# of these lerps back to exactly its normal value, unchanged.
	var urgency: float = _scheduled_retreat_urgency()
	var detect_radius: float = lerp(GameConfig.FRIENDLY_ENCIRCLEMENT_DETECT_RADIUS, GameConfig.FRIENDLY_ENCIRCLEMENT_DETECT_RADIUS_URGENT, urgency)
	var min_covered_fraction: float = lerp(GameConfig.FRIENDLY_ENCIRCLEMENT_MIN_COVERED_FRACTION, GameConfig.FRIENDLY_ENCIRCLEMENT_MIN_COVERED_FRACTION_URGENT, urgency)
	var angle_threshold_deg: float = lerp(GameConfig.FRIENDLY_ENCIRCLEMENT_ANGLE_THRESHOLD_DEG, GameConfig.FRIENDLY_ENCIRCLEMENT_ANGLE_THRESHOLD_URGENT_DEG, urgency)

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
	u.last_order_reason = "Known enemies threaten encirclement: consolidate toward friendly units."
	u.move_target = GameConfig.nearest_cover_point(raw_step_destination, 0.0, false, claimed, known_enemies)
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
func _score_advance_candidate(point: Vector2, angle_deg: float, known_player_positions: Array[Vector2], friendly_center: Vector2 = Vector2.INF, other_bearings_deg: Array[float] = []) -> float:
	var score: float = GameConfig.ENEMY_ADVANCE_BASE_WEIGHT
	if GameConfig.is_in_cover(GameConfig.get_terrain_type_at(point)):
		score += GameConfig.ENEMY_ADVANCE_COVER_BONUS
	if not known_player_positions.is_empty():
		var concealed := true
		var exposed_to_fire := false
		for pp in known_player_positions:
			if GameConfig.has_direct_los(point, pp):
				concealed = false
				if point.distance_to(pp) <= GameConfig.SQUAD_ENGAGEMENT_RANGE:
					exposed_to_fire = true
		if concealed:
			score += GameConfig.ENEMY_ADVANCE_CONCEALMENT_BONUS
		if exposed_to_fire:
			score -= GameConfig.ENEMY_ADVANCE_EXPOSURE_PENALTY
	if not is_inf(friendly_center.x) and not other_bearings_deg.is_empty():
		var candidate_bearing: float = rad_to_deg((point - friendly_center).angle())
		var nearest_claimed_gap := 180.0
		for b in other_bearings_deg:
			nearest_claimed_gap = min(nearest_claimed_gap, _angle_diff(candidate_bearing, b))
		score += GameConfig.ENEMY_ADVANCE_ENCIRCLE_BONUS * (nearest_claimed_gap / 180.0)
	score -= abs(angle_deg) * GameConfig.ENEMY_ADVANCE_ANGLE_PENALTY_PER_DEG
	return max(score, 0.1)


## A genuine weighted-random choice among advance-rush candidates (see
## _next_advance_point) — not a deterministic "always the single best
## angle," matching the same real-tactics-isn't-perfectly-rational idiom as
## _weighted_mortar_target_pick.
func _weighted_advance_point_pick(candidates: Array[Vector2], angles_deg: Array[float], known_player_positions: Array[Vector2], friendly_center: Vector2 = Vector2.INF, other_bearings_deg: Array[float] = []) -> Vector2:
	var weights: Array[float] = []
	var total := 0.0
	for i in candidates.size():
		var w: float = _score_advance_candidate(candidates[i], angles_deg[i], known_player_positions, friendly_center, other_bearings_deg)
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
## mortar that could actually reach this position — one beyond
## GameConfig.MORTAR_MAX_RANGE simply can't respond, no matter how
## exposed the firing mortar was. A mortar dug in deep enough to be out
## of both enemy tubes' range trades away some of its own reach for
## genuine counter-battery immunity.
##
## The strike isn't instant: it can only ever target where THIS mortar was
## standing right now, at the moment it fired (captured here, before any
## post-shot scoot hop) — see _resolve_pending_counter_battery for the
## delayed impact that actually checks whether it's still nearby — THAT
## check, not this one, is where shoot-and-scoot's own real protection
## actually lives. GameConfig.COUNTER_BATTERY_DELAY_MIN/MAX (1-3 tactical
## minutes, not a fixed interval) is the FULL detect-to-impact time — real
## counter-battery response varies with how quickly the opposing crew can
## get a fire mission organized — and is split here into the reaction
## portion (detect, compute a solution, lay and fire — no visible flash
## yet, nothing has actually been fired) and GameConfig.MORTAR_FLIGHT_TIME
## (the responding round's own physical flight time, the exact same
## constant every other mortar shot in this file already flies on) for the
## flight portion — carved OUT of the existing total, not stacked on top
## of it, so the overall time-to-possible-impact envelope this constant
## was already tuned around is unchanged. A real, previously-reported
## confusion this fixes: the responding mortar's own muzzle flash used to
## be drawn HERE, at the instant this function runs — the same tick as the
## ORIGINAL shot that triggered it — even though the doc comment (and the
## combat log's own "fire inbound" wording) describes real time passing
## before that crew actually gets its own round off. See
## _resolve_pending_counter_battery for where the flash actually gets
## drawn now: the moment the responding mortar itself fires, not the
## moment it merely decided to.
func _resolve_mortar_counter_battery(firing_mortar: Unit) -> void:
	var opposing: Array[Unit] = player_units if firing_mortar.team == Unit.Team.ENEMY else enemy_units
	var chance: float = GameConfig.MORTAR_COUNTER_BATTERY_CHANCE
	for m in opposing:
		if m.kind != Unit.Kind.MORTAR or m.state != Unit.State.ACTIVE:
			continue
		# A tube that's still slung over a shoulder mid-relocation (or only
		# just set back down) can't turn around and fire a fire mission —
		# see GameConfig.MORTAR_SETUP_TEARDOWN_TIME's own doc comment; the
		# same seconds_stationary floor _mortar_shot_this_tick uses for a
		# mortar's own next shot applies just as physically to firing back.
		if m.seconds_stationary < GameConfig.MORTAR_SETUP_TEARDOWN_TIME:
			continue
		if m.global_position.distance_to(firing_mortar.global_position) > GameConfig.MORTAR_MAX_RANGE:
			continue # out of range — this mortar physically cannot reach back
		if randf() < chance:
			var total_delay: float = randf_range(GameConfig.COUNTER_BATTERY_DELAY_MIN, GameConfig.COUNTER_BATTERY_DELAY_MAX)
			var react_delay: float = max(total_delay - GameConfig.MORTAR_FLIGHT_TIME, 0.0)
			unit_combat_stats.register(m)
			unit_combat_stats.shot(m, true)
			_pending_counter_battery.append({
				"attacker": m,
				"target": firing_mortar,
				"impact_position": firing_mortar.global_position,
				"fire_time": scenario_elapsed_time + react_delay,
				"impact_time": scenario_elapsed_time + total_delay,
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
			strike.fired = true
			_fire_flashes.append({
				"from": responder.global_position, "to": strike.impact_position, "team": responder.team, "time": elapsed_time, "is_mortar": true,
			})
			_history_fire_events.append({
				"from": responder.global_position, "to": strike.impact_position, "team": responder.team, "time": scenario_elapsed_time, "is_mortar": true,
			})
			combat_log.log_counter_battery_incoming(strike.target)
			still_pending.append(strike)
			continue
		if scenario_elapsed_time < strike.impact_time:
			still_pending.append(strike)
			continue
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
		var impact_chance: float = clamp(1.0 - distance / GameConfig.COUNTER_BATTERY_BLAST_RADIUS, 0.0, 1.0)
		if randf() < impact_chance:
			var before := UnitCombatStats.before_hit(target)
			target.take_hit(true, [], _known_enemy_positions(target.team))
			if strike.has("attacker") and is_instance_valid(strike.attacker):
				unit_combat_stats.damage(strike.attacker, target, before)
			combat_log.log_counter_battery(target)
			_log_hit_consequence(target, true)
		else:
			combat_log.log_counter_battery_miss(target)
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
	mortar.evading_counter_battery = false
	var plan: Dictionary = _mortar_relocation_plan(mortar, urgent)
	if plan.is_empty():
		return false
	_issue_mortar_move(mortar, plan.destination, plan.speed, intent)
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
func _mortar_relocation_plan(mortar: Unit, urgent: bool) -> Dictionary:
	var threats := _known_enemy_positions(mortar.team)
	var destination: Vector2 = (
		GameConfig.nearest_hidden_point(mortar.global_position, threats, true, urgent)
		if not threats.is_empty()
		else GameConfig.nearest_cover_point(mortar.global_position, 0.0, true)
	)
	if destination == mortar.global_position:
		return {}
	if mortar.team == Unit.Team.PLAYER and destination.distance_to(_friendly_mortar_home_position) > GameConfig.MORTAR_HUNT_MAX_RANGE_FROM_HOME:
		return {}
	var speed: float = GameConfig.MORTAR_RELOCATE_SPEED_URGENT if urgent else GameConfig.MORTAR_RELOCATE_SPEED
	if GameConfig.get_terrain_type_at(destination) == GameConfig.TerrainType.TREES:
		speed *= GameConfig.MORTAR_RELOCATE_TREES_MULTIPLIER
	return {"destination": destination, "speed": speed}


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
## a pending entry whose mortar already has a move order by the time it's
## ready — a higher-priority trigger (a tier-1 self-preservation evade,
## most sharply) has since claimed this tick's move, and the routine scoot
## it would have overwritten is moot; a fresh _decide_mortar_action pass
## will pick up cleanly from wherever that more urgent move leaves off.
func _resolve_pending_mortar_displacement() -> void:
	for mortar in _pending_mortar_displacement.keys():
		var pending: Dictionary = _pending_mortar_displacement[mortar]
		if scenario_elapsed_time < pending.ready_time:
			continue
		_pending_mortar_displacement.erase(mortar)
		if mortar.state != Unit.State.ACTIVE or mortar.has_move_target:
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
## all. It DOES have a real maximum range (GameConfig.MORTAR_MAX_RANGE) —
## a mortar tube only throws a shell so far, regardless of who's spotting.
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
	var target: Unit = null
	if m.seconds_stationary >= GameConfig.MORTAR_SETUP_TEARDOWN_TIME:
		target = _pick_target(m, opposing)
	_mortar_tick_shot[m] = {"resolved": true, "target": target}
	return target


## Original doctrine keeps the legacy overrides. Other profiles compare
## legal targets on the shared score scale; all choices record their evidence.
func _pick_target(unit: Unit, enemies: Array[Unit]) -> Unit:
	var candidates: Array[Unit] = []
	for e in enemies:
		if not e.is_targetable():
			continue
		if unit.kind == Unit.Kind.SQUAD:
			if unit.global_position.distance_to(e.global_position) > GameConfig.SQUAD_ENGAGEMENT_RANGE:
				continue
			if not GameConfig.has_direct_los(unit.global_position, e.global_position):
				continue
		elif unit.kind == Unit.Kind.MORTAR:
			if unit.global_position.distance_to(e.global_position) > GameConfig.MORTAR_MAX_RANGE:
				continue
		candidates.append(e)
	if _risk_holds.has(unit) and unit.state == Unit.State.ACTIVE:
		return _record_target_choice(unit, candidates, null, "Self-risk policy: displacing or withholding fire.")
	if candidates.is_empty():
		return _record_target_choice(unit, candidates, null, "No eligible visible target.")

	var mortar_candidates: Array[Unit] = candidates.filter(func(c): return c.kind == Unit.Kind.MORTAR and c.state == Unit.State.ACTIVE)
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
		if not enemy_mortar_fix.is_empty() and unit_doctrine_for(unit).targeting in ["inherit", "mortars"] and mortar_candidates.is_empty() and not any_overrun:
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
			# A scheduled retreat (BattleManager.order_scheduled_retreat)
			# means the ammo being preserved here might never get its
			# chance at all — no point holding a shot to wait on an
			# opportunity that likely won't arrive before the crew pulls
			# out. Reads as 1.0 (no change) with no scheduled retreat, or
			# comfortably ahead of one.
			hold_for_pursuit_chance *= _scheduled_retreat_ammo_discount(unit)
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
		if unit.team == Unit.Team.PLAYER and mortar_candidates.is_empty() and not any_overrun:
			var unknown_mortar_hold_chance: float = GameConfig.MORTAR_UNKNOWN_ENEMY_HOLD_FIRE_CHANCE * _mortar_existence_confidence()
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
		# Same "ammo saved for a later that may not come is just wasted"
		# reasoning as the pursuit-hold discount above, applied to
		# ordinary ammo conservation too.
		hold_fire_chance *= _scheduled_retreat_ammo_discount(unit)
		hold_fire_chance = clampf(hold_fire_chance * _profile_weight(unit.team, "conservation"), 0.0, 1.0)
		var ammo_roll: float = 0.5 if profile_for(unit.team).deterministic else randf()
		if ammo_roll < hold_fire_chance:
			return _record_target_choice(unit, candidates, null, "Hold fire to conserve ammunition.", {"hold_probability": hold_fire_chance, "roll_or_cutoff": ammo_roll, "scarcity": scarcity, "resupply_urgency": urgency})
		gate_evidence["ammunition"] = {"hold_probability": hold_fire_chance, "roll_or_cutoff": ammo_roll, "scarcity": scarcity, "resupply_urgency": urgency}
		return _weighted_mortar_target_pick(unit, candidates, gate_evidence)
	if profile_for(unit.team).id != "baseline" or unit_doctrine_for(unit).targeting != "inherit":
		return _weighted_mortar_target_pick(unit, candidates)
	var chosen: Unit = candidates[randi() % candidates.size()]
	return _record_target_choice(unit, candidates, chosen, "Original squad rule: uniform choice among eligible targets.", {"conditional_probability": 1.0 / candidates.size()})


## 0.0 (nothing pending, or the soonest still-unresolved wave is still
## GameConfig.MORTAR_RESUPPLY_URGENCY_HORIZON_MINUTES or more away) to 1.0
## (a real run is already en route — as urgent/certain as it gets short of
## rounds already being in the tube), ramping linearly as the soonest
## still-unresolved wave's actual arrival time approaches. Drives
## _pick_target's own sliding-scale ammo conservation — see GameConfig.
## MORTAR_RESUPPLY_URGENCY_HORIZON_MINUTES's own comment for the full
## reasoning. Also the source for CasualtyDashboard's live "resupply ~Nm
## out" / "resupply run en route" readout (see mortar_resupply_status).
func _mortar_resupply_urgency(mortar: Unit) -> float:
	if _active_resupply_run_for(mortar) != null:
		return 1.0
	var record: Dictionary = _mortar_resupply.get(mortar, {})
	if record.is_empty():
		return 0.0
	var arrivals: Array = record.get("wave_arrival_times", [])
	var resolved: Array = record.get("wave_resolved", [])
	var soonest: float = INF
	for i in arrivals.size():
		if not resolved[i]:
			soonest = min(soonest, float(arrivals[i]))
	if is_inf(soonest):
		return 0.0
	var minutes_left: float = max(soonest - scenario_elapsed_time, 0.0) / 60.0
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


## Public accessor for CasualtyDashboard's live per-mortar readout — never
## reveals the true underlying arrival time as some kind of privileged
## knowledge the player shouldn't have (this IS the player's own mortar's
## status board, not the enemy's), just a friendly summary of the same
## state _mortar_resupply_urgency already computes from.
func mortar_resupply_status(mortar: Unit) -> Dictionary:
	if _active_resupply_run_for(mortar) != null:
		return {"pending": true, "in_transit": true}
	var record: Dictionary = _mortar_resupply.get(mortar, {})
	if record.is_empty():
		return {"pending": false}
	var arrivals: Array = record.get("wave_arrival_times", [])
	var resolved: Array = record.get("wave_resolved", [])
	var soonest: float = INF
	for i in arrivals.size():
		if not resolved[i]:
			soonest = min(soonest, float(arrivals[i]))
	if is_inf(soonest):
		return {"pending": false}
	var minutes_left: float = max(soonest - scenario_elapsed_time, 0.0) / 60.0
	return {"pending": true, "in_transit": false, "minutes_until_next": minutes_left}


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
func _known_enemy_mortars_in_range(pos: Vector2) -> int:
	var count := 0
	for u in enemy_units:
		if u.kind != Unit.Kind.MORTAR:
			continue
		if u.state != Unit.State.ACTIVE and u.state != Unit.State.RETREATING:
			continue
		var known_pos: Vector2
		if u.is_visible:
			known_pos = u.global_position
		elif u.player_has_been_sighted:
			known_pos = u.player_known_position
		elif mortar_ever_detected_firing(u):
			known_pos = _last_detected_mortar_fire[u].position
		else:
			continue
		if known_pos.distance_to(pos) <= GameConfig.MORTAR_MAX_RANGE:
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
		return GameConfig.MORTAR_TARGET_CASUALTY_WEIGHT * casualty_value + GameConfig.MORTAR_TARGET_DANGER_WEIGHT * danger_value
	return 0.0


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


func _check_battle_end() -> void:
	if _all_done_fighting(player_units) or _all_done_fighting(enemy_units) \
			or scenario_elapsed_time >= GameConfig.BATTLE_TIME_LIMIT:
		_end_battle()
	elif _seconds_since_last_shot >= STAGNATION_TIMEOUT and not _anyone_moving():
		combat_log.add_entry("--- Battle stalemated: no movement or fire for %ds ---" % int(STAGNATION_TIMEOUT))
		_end_battle()


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

	var verdict: String
	if held and exchange_ratio >= 1.5:
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

	var lines: PackedStringArray = []
	lines.append("=== AFTER-ACTION REPORT ===")
	lines.append("Verdict: %s" % verdict)
	lines.append("%s held: %s" % [GameConfig.CURRENT_MAP.name, "YES" if held else "NO"])
	var tactical_minutes: int = int(scenario_elapsed_time / 60.0)
	lines.append("Time elapsed: %dh %02dm (0600 to %s)" % [tactical_minutes / 60, tactical_minutes % 60, clock_string().substr(0, 5)])
	# Captured is included right in this line, not a separate conditional
	# one, specifically so killed + heavily wounded + walking wounded +
	# captured always visibly sums to the personnel-lost total on the left —
	# every one of those four is tracked for every personnel kind now (see
	# _compute_side_stats), so this is a real identity, not just usually true.
	lines.append("Player casualties: %d/%d personnel (%.0f%%) — %d killed, %d heavily wounded, %d walking wounded, %d captured" % [
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
		lines.append("Enemy casualties: an estimated %d/%d personnel (~%.0f%%) — the position wasn't held for a battlefield assessment, so this reflects only what was actually scouted during the fight, not the true toll" % [
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
		lines.append("Enemy casualties: %d/%d personnel confirmed on the battlefield (%.0f%%) — %d killed, %d heavily wounded, %d captured, %d more unaccounted for (likely evacuated wounded — the enemy pulls its own ambulatory casualties out even from ground it's about to lose)" % [
			enemy_stats.pips_lost, enemy_stats.pips_total, enemy_stats.casualty_percent,
			enemy_stats.killed, enemy_stats.heavily_wounded, enemy_stats.captured, enemy_stats.evacuated_unknown,
		])
	else:
		lines.append("Enemy casualties: %d/%d confirmed on the battlefield — %d killed, %d heavily wounded, %d captured, %d more unaccounted for (likely evacuated wounded)" % [
			enemy_stats.confirmed_pips_lost, enemy_stats.pips_total,
			enemy_stats.killed, enemy_stats.heavily_wounded, enemy_stats.captured, enemy_stats.evacuated_unknown,
		])
		lines.append("Plus an estimated %d more among units that got away before the position could be swept — not independently confirmed, just what was actually scouted during the fight" % enemy_stats.unconfirmed_pips_lost)
		lines.append("Enemy casualties overall (partly estimated): ~%d/%d personnel (~%.0f%%)" % [
			enemy_stats.pips_lost, enemy_stats.pips_total, enemy_stats.casualty_percent,
		])
	# No separate "exchange ratio" line — it was purely duplicative of the two
	# casualty lines just above; `exchange_ratio` itself stays, still doing
	# real work in the verdict math above (SUCCESSFUL DEFENSE/PYRRHIC
	# DEFENSE/TACTICAL WITHDRAWAL thresholds), just no longer printed.
	if not player_stats.destroyed.is_empty():
		lines.append("Player losses: %s" % ", ".join(player_stats.destroyed))
	if not player_stats.withdrawn.is_empty():
		lines.append("Player withdrew safely: %s" % ", ".join(player_stats.withdrawn))
	if not player_stats.still_retreating.is_empty():
		lines.append("Player still pulling back when the battle ended: %s" % ", ".join(player_stats.still_retreating))
	if not enemy_stats.destroyed.is_empty():
		lines.append("Enemy losses: %s" % ", ".join(enemy_stats.destroyed))
	if not enemy_stats.withdrawn.is_empty():
		lines.append("Enemy withdrew: %s" % ", ".join(enemy_stats.withdrawn))
	if not enemy_stats.still_retreating.is_empty():
		lines.append("Enemy still pulling back when the battle ended: %s" % ", ".join(enemy_stats.still_retreating))
	if not player_stats.surrendered.is_empty():
		lines.append("Player surrendered: %s" % ", ".join(player_stats.surrendered))
	if not enemy_stats.surrendered.is_empty():
		lines.append("Enemy surrendered: %s" % ", ".join(enemy_stats.surrendered))

	# unit_combat_stats.report_lines() used to be appended here too — now
	# that main.gd's own "Damage by unit" tab fetches it fresh on demand
	# (see its own pressed handler), duplicating the whole thing onto the
	# end of this summary as well is just redundant scrolling.
	var report_text := "\n".join(lines)
	battle_ended.emit(report_text)


func _draw() -> void:
	GameConfig.draw_terrain(self)
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


func _draw_arc_tracer(from: Vector2, to: Vector2, color: Color) -> void:
	var apex: Vector2 = (from + to) / 2.0 - Vector2(0.0, from.distance_to(to) * 0.2)
	var points := PackedVector2Array()
	var segments := 12
	for i in segments + 1:
		var t: float = float(i) / float(segments)
		var one_minus_t: float = 1.0 - t
		points.append(from * (one_minus_t * one_minus_t) + apex * (2.0 * one_minus_t * t) + to * (t * t))
	draw_polyline(points, color, 2.0, true)
