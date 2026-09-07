extends Node2D
class_name BattleManager
## Runs one battle: spawns units per doctrine, marches the enemy down the
## road, resolves spotting and fire each tick, and produces an after-action
## report once both sides are done fighting. Enemy doctrine is fixed/
## hardcoded here — deliberately NOT a mirrored doctrine-interpreting engine
## (see design doc).
##
## No routine per-shot fire log (see CombatLog) — the log only records
## moments that change the picture. Fire IS shown visually, though — every
## shot leaves a brief tracer (see _fire_flashes / _draw), color-coded by
## side, so it is always clear when and where the enemy is shooting.

signal battle_ended(report_text: String)

const FLASH_DURATION: float = 0.3

# If nobody has fired AND nobody is trying to move for this long, the battle
# has genuinely stalled (e.g. both mortars gone, everyone dug into cover
# with no LOS to anyone) — end it rather than running out the full clock.
const STAGNATION_TIMEOUT: float = 15.0

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

# Where each side's resupply runs actually deliver rounds to — the
# player's own choice from deployment, the enemy's own algorithmic pick
# (see GameConfig.choose_enemy_resupply_point). Set once in start_battle.
var _player_resupply_point: Vector2 = Vector2.ZERO
var _enemy_resupply_point: Vector2 = Vector2.ZERO

# True once a side has EVER sighted the enemy — sticky, not "currently
# visible right now" (see _update_sighting_flags) — "once the enemy is
# sighted, resupply can be requested" is a one-time unlock, not something
# that un-unlocks if contact is lost again later.
var _player_sighted_enemy: bool = false
var _enemy_sighted_enemy: bool = false

# One entry per mortar with an active resupply request — see
# request_mortar_resupply/_update_mortar_resupply. Keyed by the mortar
# Unit; removed once both waves have resolved AND any arrived rounds have
# actually been collected (rounds_waiting back to 0), so a fresh request
# can be made later. Fields: wave_arrival_times/warning_times (Array[float],
# one per GameConfig.MORTAR_RESUPPLY_WAVE_COUNT wave), wave_warned/
# wave_resolved (Array[bool]), rounds_waiting (int — arrived, not yet
# physically picked up from the resupply point).
var _mortar_resupply: Dictionary = {}

# Mortars currently physically traveling to collect ready rounds — see
# _update_mortar_resupply_fetch. Keyed by mortar Unit; {"phase": "to_point"
# or "returning", "origin": Vector2 — where it was standing when the trip
# started, so it has somewhere sensible to come back to}.
var _mortar_resupply_trip: Dictionary = {}

# Unit (a mortar) -> {"position": Vector2, "time": float} — where and when
# that mortar was last DETECTED firing, via muzzle blast/trajectory rather
# than visual spotting (real counter-battery detection doesn't need to see
# the crew) — see _launch_mortar_shot (records it, every shot, any mortar)
# and _known_friendly_mortar_position (consumes it, as a fallback when the
# mortar isn't currently visible either).
var _last_detected_mortar_fire: Dictionary = {}

# The single enemy mortar the friendly mortar and the drone/spotter are
# CURRENTLY, JOINTLY committed to running down together, or null if
# nothing's being hunted right now — see _update_joint_mortar_hunt. Exists
# because the mortar's own hunt decision (_update_friendly_mortar_hunting)
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
var _drone_sweep_index: int = 0 # which road waypoint the blind search patrol is currently headed for — see _drone_sweep_target
var _drone_vicinity_search_angle: float = 0.0 # current angle around a spotted squad the drone is circling to — see _drone_vicinity_search_point
var _drone_flank_watch_point: Vector2 = Vector2.INF # current unscreened bearing around the mortar the drone is checking — see _drone_flank_watch_target


func start_battle(doctrine: Dictionary, p_combat_log: CombatLog) -> void:
	combat_log = p_combat_log
	elapsed_time = 0.0
	scenario_elapsed_time = 0.0
	battle_over = false
	_fire_flashes.clear()
	_seconds_since_last_shot = 0.0
	enemy_alerted = false
	player_general_retreat_ordered = false
	enemy_general_retreat_ordered = false
	_last_detected_mortar_fire.clear()
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
	_drone_sweep_index = _weighted_random_sweep_index()
	_drone_vicinity_search_angle = 0.0
	_drone_flank_watch_point = Vector2.INF
	_player_sighted_enemy = false
	_enemy_sighted_enemy = false
	_mortar_resupply.clear()
	_mortar_resupply_trip.clear()
	_player_resupply_point = doctrine.get("resupply_point", GameConfig.PLAYER_RESUPPLY_DEFAULT_POSITION)
	_enemy_resupply_point = GameConfig.choose_enemy_resupply_point()

	for unit in player_units + enemy_units:
		unit.queue_free()
	player_units.clear()
	enemy_units.clear()

	_spawn_player_units(doctrine)
	_spawn_enemy_units()

	queue_redraw()


## HH:MM:SS tactical time-of-day, starting at GameConfig.SCENARIO_START_HOUR
## (0600) and advancing with scenario_elapsed_time.
func clock_string() -> String:
	var total_seconds: int = int(GameConfig.SCENARIO_START_HOUR * 3600.0 + scenario_elapsed_time)
	var h: int = (total_seconds / 3600) % 24
	var m: int = (total_seconds / 60) % 60
	var s: int = total_seconds % 60
	return "%02d:%02d:%02d" % [h, m, s]


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
	# GameConfig.PLAYER_SPOTTER_DEPLOYMENT_ZONE) — reused as-is for the drone
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


func _spawn_enemy_units() -> void:
	var road_px: Array[Vector2] = GameConfig.road_waypoints_px()
	# A real road march down the winding road (see GameConfig.ROAD_WAYPOINTS_M),
	# not a straight line. Each squad's whole path is the same road shifted by
	# its own fixed y offset — a loose spread advancing near the road, not
	# single file on top of it or on top of each other.
	for i in GameConfig.ENEMY_SQUAD_Y_OFFSETS_M.size():
		var y_offset: float = GameConfig.ENEMY_SQUAD_Y_OFFSETS_M[i] * GameConfig.PIXELS_PER_METER
		var start_pos := Vector2(GameConfig.ENEMY_SPAWN_X, road_px[0].y + y_offset)
		var squad := _make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, start_pos)
		squad.retreat_threshold = GameConfig.ENEMY_RETREAT_THRESHOLD
		squad.concern_threshold = GameConfig.ENEMY_CONCERN_THRESHOLD
		squad.move_speed = GameConfig.ENEMY_ADVANCE_SPEED
		var path: Array[Vector2] = []
		for wp in road_px:
			path.append(wp + Vector2(0.0, y_offset))
		squad.set_path(path)
		squad.movement_predictable = true # a steady, known march — lead-aimable by mortar fire
		squad.activity = Unit.Activity.MOVING
		_set_retreat_profile(squad, Unit.Team.ENEMY)
		enemy_units.append(squad)

	for mortar_pos_m in GameConfig.ENEMY_MORTAR_POSITIONS_M:
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
	unit.fire_timer = randf_range(0.0, unit.fire_interval)
	return unit


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


func order_general_retreat() -> void:
	if battle_over:
		return
	player_general_retreat_ordered = true
	var known_enemy_positions := _known_enemy_positions(Unit.Team.PLAYER)
	var any_ordered := false
	var claimed: Array[Vector2] = []
	for unit in player_units:
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
func _known_enemy_positions(team: Unit.Team) -> Array[Vector2]:
	var opposing: Array[Unit] = enemy_units if team == Unit.Team.PLAYER else player_units
	var positions: Array[Vector2] = []
	for u in opposing:
		var still_a_threat: bool = u.state == Unit.State.ACTIVE or u.state == Unit.State.RETREATING
		if still_a_threat and u.is_visible:
			positions.append(u.global_position)
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
	var target_was_active := target.state == Unit.State.ACTIVE
	var hit := CombatResolver.resolve_fire(attacker, target, _ally_positions_for(target), _known_enemy_positions(target.team), _drone_directing_mortar_fire(attacker))
	_log_hit_consequence(target, target_was_active)
	if not hit or target.kind != Unit.Kind.SQUAD:
		return
	var spillover := _bunched_ally(target)
	if spillover == null:
		return
	var spillover_was_active := spillover.state == Unit.State.ACTIVE
	spillover.take_hit(attacker.kind == Unit.Kind.MORTAR, _ally_positions_for(spillover), _known_enemy_positions(spillover.team))
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


## Where a resupply run for `team`'s mortars actually delivers rounds —
## see _player_resupply_point/_enemy_resupply_point's own doc comment.
func _resupply_point_for(team: Unit.Team) -> Vector2:
	return _player_resupply_point if team == Unit.Team.PLAYER else _enemy_resupply_point


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
		"rounds_waiting": 0,
	}
	if _should_narrate_mortar_logistics(mortar):
		combat_log.log_mortar_resupply_requested(mortar)
	return true


## Ticks every mortar's active resupply request (if any) toward its ETA
## warning and eventual arrival/failure — see request_mortar_resupply for
## how the two wave timings were actually rolled. Runs every tick,
## regardless of whether that mortar itself is doing anything else right
## now (moving, firing, out of ammo) — the resupply pipeline runs in the
## background either way, exactly like a real supply run would.
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
				if randf() < GameConfig.MORTAR_RESUPPLY_FAILURE_CHANCE:
					if _should_narrate_mortar_logistics(m):
						combat_log.log_mortar_resupply_failed(m)
				else:
					record.rounds_waiting = int(record.rounds_waiting) + GameConfig.MORTAR_RESUPPLY_ROUNDS
					if _should_narrate_mortar_logistics(m):
						combat_log.log_mortar_resupply_arrived(m, GameConfig.MORTAR_RESUPPLY_ROUNDS)
		record.wave_warned = warned
		record.wave_resolved = resolved
		_mortar_resupply[m] = record

	# Clean up once every wave has resolved AND anything that arrived has
	# actually been collected (see _update_mortar_resupply_fetch) — only
	# then is this mortar eligible for a brand new request.
	for m in _mortar_resupply.keys():
		var record: Dictionary = _mortar_resupply[m]
		var all_resolved := true
		for r in record.wave_resolved:
			if not r:
				all_resolved = false
				break
		if all_resolved and int(record.rounds_waiting) <= 0:
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


## Sends `m` on its way to physically collect `rounds_waiting` rounds
## sitting at its side's resupply point — a resupply point is a logistics
## location, not something that teleports ammo onto the gun (see
## GameConfig.PLAYER_RESUPPLY_DEPLOYMENT_ZONE's own comment). Reuses
## MORTAR_RELOCATE_SPEED for the trip. No return leg is scheduled: there is
## nothing wrong with firing from the resupply point itself once loaded (see
## _advance_mortar_resupply_trip) — the mortar only moves on from there for
## an actual reason of its own (shoot-and-scoot's own _relocate_mortar after
## a shot, or an enemy fix on its position), not because a fetch trip always
## has to end with a trip back.
func _start_mortar_resupply_trip(m: Unit) -> void:
	_mortar_resupply_trip[m] = true
	m.move_target = _resupply_point_for(m.team)
	m.has_move_target = true
	m.move_queue.clear()
	m.move_speed = GameConfig.MORTAR_RELOCATE_SPEED
	m.movement_predictable = false
	if _should_narrate_mortar_logistics(m):
		combat_log.log_mortar_resupply_departing(m)


## Advances a mortar already en route (see _start_mortar_resupply_trip) —
## no-op while still moving (the ordinary move system is already stepping
## it there); once arrival is detected (has_move_target clears), collects
## the waiting rounds and ends the trip right there at the resupply point,
## letting the mortar's normal AI take back over from wherever it's
## actually standing rather than forcing a trip back to wherever it started.
func _advance_mortar_resupply_trip(m: Unit) -> void:
	if m.has_move_target:
		return
	var record: Dictionary = _mortar_resupply.get(m, {})
	var rounds: int = int(record.get("rounds_waiting", 0))
	m.mortar_rounds_remaining += rounds
	if not record.is_empty():
		record.rounds_waiting = 0
		_mortar_resupply[m] = record
	if _should_narrate_mortar_logistics(m):
		combat_log.log_mortar_resupply_collected(m, rounds)
	_mortar_resupply_trip.erase(m)


## True when `mortar` isn't currently spotted by the opposing side — the bar
## for setting out on a fetch trip while completely dry. Trekking to a
## fixed, standing resupply point while under an enemy's eye is exactly the
## kind of exposure a real crew would rather wait out than walk into,
## especially with nothing to shoot back with if it goes wrong.
func _safe_to_fetch_resupply(mortar: Unit) -> bool:
	return not mortar.is_visible


## Decides when a mortar with ready-and-waiting rounds actually breaks off
## to go collect them — not the instant they arrive, since abandoning a
## live fire mission just to top off is exactly the kind of thing "mortar
## teams need to be smart about" the request calls out. Goes once it's
## already idle (no target worth engaging right now) so an active hunt or
## fire mission already claiming its movement this tick (see
## _update_friendly_mortar_hunting/_update_enemy_mortar_positioning, both of
## which run earlier) isn't interrupted for a top-up that can wait. A
## completely dry mortar can't wait for "idle" to naturally arrive (it has
## nothing to fire regardless — see _tick_fire's own ammo gate) but still
## only goes once it's safe to do so (see _safe_to_fetch_resupply) — being
## out of ammo is a reason to want to go, not a reason to walk into the open
## while spotted.
func _update_mortar_resupply_fetch() -> void:
	for m in player_units + enemy_units:
		if m.kind != Unit.Kind.MORTAR or m.state != Unit.State.ACTIVE:
			continue
		if _mortar_resupply_trip.has(m):
			_advance_mortar_resupply_trip(m)
			continue
		var record: Dictionary = _mortar_resupply.get(m, {})
		var rounds_waiting: int = int(record.get("rounds_waiting", 0))
		if rounds_waiting <= 0:
			continue
		var out_of_ammo: bool = m.mortar_rounds_remaining <= 0
		if not out_of_ammo and m.has_move_target:
			continue # already busy with something else this tick
		var opposing: Array[Unit] = enemy_units if m.team == Unit.Team.PLAYER else player_units
		var idle: bool = _pick_target(m, opposing) == null
		if idle or (out_of_ammo and _safe_to_fetch_resupply(m)):
			_start_mortar_resupply_trip(m)


## The enemy actively hunts for counter-battery range on the friendly
## mortar now that range is a real, physical requirement (see
## _resolve_mortar_counter_battery) — a player who digs in far enough to
## the rear to be out of range of both enemy tubes doesn't get permanent
## immunity, just a head start; once the enemy has a fix on that mortar and
## it's out of range, they close the distance toward it (to just inside
## MORTAR_MAX_RANGE, not all the way to it) rather than sitting uselessly
## out of reach forever. "Has a fix on it" — see
## _known_friendly_mortar_position — means currently visible OR detected
## firing recently, NOT a permanent memory of where it used to be.
##
## HIGH PRIORITY: unlike most movement decisions in this game (made once,
## then left alone until arrival), this re-aims every single tick there's a
## fix on the friendly mortar and it's still out of range — not just when
## idle — so a mortar already advancing keeps correcting toward the best
## currently-known position instead of plodding on toward a possibly-stale
## point, and stops the INSTANT it comes into range rather than finishing
## out a march to a farther point computed earlier.
func _update_enemy_mortar_positioning() -> void:
	var target_pos: Vector2 = _known_friendly_mortar_position()
	if is_inf(target_pos.x):
		return
	for m in enemy_units:
		if m.kind != Unit.Kind.MORTAR or m.state != Unit.State.ACTIVE:
			continue
		if m.global_position.distance_to(target_pos) <= GameConfig.MORTAR_MAX_RANGE:
			if m.has_move_target:
				# Now in range — stop closing and get to work, rather than
				# finishing the walk to a farther point computed earlier.
				m.has_move_target = false
				m.activity = Unit.Activity.STATIONARY
			continue
		var target := _mortar_advance_point(m, target_pos)
		if target == m.global_position:
			continue # no safe route found this tick — try again next tick
		m.move_target = target
		m.has_move_target = true
		m.move_queue.clear()
		m.move_speed = GameConfig.REPOSITION_SPEED
		m.movement_predictable = false


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
## _update_friendly_mortar_hunting) — Vector2.INF / not `trusted` at all if
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
func _known_enemy_mortar_lead() -> Dictionary:
	for u in enemy_units:
		if u.kind == Unit.Kind.MORTAR and u.state == Unit.State.ACTIVE and u.is_visible:
			return {"position": u.global_position, "trusted": true, "unit": u}

	var best_pos := Vector2.INF
	var best_time := -INF
	var best_unit: Unit = null
	for u in enemy_units:
		if u.kind != Unit.Kind.MORTAR or u.state != Unit.State.ACTIVE:
			continue
		var info: Dictionary = _last_detected_mortar_fire.get(u, {})
		if info.is_empty():
			continue
		if info.time > best_time:
			best_time = info.time
			best_pos = info.position
			best_unit = u
	if best_unit == null:
		return {}

	var drone_covering_it := false
	for d in [active_drone, backup_drone]:
		if d != null and d.has_move_target and d.move_target.distance_to(best_pos) < 1.0:
			drone_covering_it = true
			break

	var expiry: float = GameConfig.DRONE_MORTAR_FIRE_LEAD_EXPIRY if drone_covering_it else GameConfig.MORTAR_FIRE_DETECTION_EXPIRY
	if scenario_elapsed_time - best_time > expiry:
		return {}

	return {"position": best_pos, "trusted": drone_covering_it, "unit": best_unit}


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
## real crew would ever go: AHEAD of its own infantry screen. A mortar is
## fire support — it stays BEHIND the friendly squads holding the line,
## never advances past the frontmost one (`dest.x` beyond the highest x
## among active friendly squads — "in front of" the line) and never drifts
## outside the vertical band those squads actually occupy either (above
## the northmost or below the southmost one) — either way, wandering out
## from under its own infantry's protection is reckless regardless of how
## good the intel on the target is, or how far MORTAR_HUNT_MAX_RANGE_FROM_
## HOME would otherwise allow. With no active friendly squad left at all
## to judge a "line" against, there's nothing to violate — the home-radius
## cap is left to do the only judging left possible in that case.
func _friendly_mortar_hunt_destination_is_reckless(dest: Vector2) -> bool:
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
	return dest.x > frontmost_x or dest.y < min_y or dest.y > max_y


## Forms and maintains the mortar/drone team's SHARED commitment to
## hunting one specific enemy mortar together — consulted by both
## _update_friendly_mortar_hunting (where to walk) and _drone_search_target
## (where to fly), instead of each independently re-deriving "is this
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
	if _can_engage_position(lead.position):
		return # already in range — no coordination needed, normal engagement tiers take it from here

	var fm := _friendly_mortar()
	if fm == null:
		return
	var dest := _friendly_mortar_hunt_point(fm, lead.position)
	if dest == fm.global_position or dest.distance_to(_friendly_mortar_home_position) > GameConfig.MORTAR_HUNT_MAX_RANGE_FROM_HOME:
		return # outside what the crew considers safe territory — not worth the drone escorting a hunt that will never actually happen
	if _friendly_mortar_hunt_destination_is_reckless(dest):
		return # would put the mortar ahead of, or outside the band held by, its own infantry screen

	_joint_mortar_hunt_target = lead.unit
	_joint_mortar_hunt_start_time = scenario_elapsed_time
	combat_log.log_joint_mortar_hunt(lead.unit)


## The friendly mirror of _update_enemy_mortar_positioning — closing the
## distance on a known enemy mortar to bring it into range, re-aiming every
## tick there's still a fix and it's still out of range, same as that
## function — but with two things the enemy's simpler version doesn't need
## to weigh: unlike the enemy just running down a fix on us, this crew
## still very much does NOT want to be spotted while doing it (see
## _friendly_mortar_hunt_point, chosen with that in mind, unlike
## _mortar_advance_point's plain building-avoidance), and a TRUSTED lead is
## no longer decided here at all — it's the team's shared joint commitment
## (_update_joint_mortar_hunt, which runs first each tick) that this just
## walks toward for as long as that commitment holds, unconditional on
## distance from the CURRENT position (same as the enemy's own
## unconditional chase) — but every candidate destination, trusted or not,
## still has to fall within GameConfig.MORTAR_HUNT_MAX_RANGE_FROM_HOME of
## home, AND still has to stay behind its own infantry screen (see
## _friendly_mortar_hunt_destination_is_reckless — never ahead of the
## frontmost friendly squad, never outside the band those squads actually
## occupy), full stop; _update_joint_mortar_hunt already screens for both
## before a commitment ever forms, but a fresh, still-untrusted lead never
## gets that upfront check, so both are re-verified here too. Only a bare,
## uncovered fire-detection lead — no active joint commitment at all — is
## still this function's OWN call to make: a solo gamble, worth at most a
## modest walk (MORTAR_HUNT_UNTRUSTED_MAX_RELOCATE), since there's no drone
## coverage backing it up.
func _update_friendly_mortar_hunting() -> void:
	var target_pos: Vector2
	var trusted: bool

	if _joint_mortar_hunt_target != null:
		target_pos = _joint_mortar_hunt_known_position()
		if is_inf(target_pos.x):
			return # the commitment holds, but nothing usable is known this exact tick
		trusted = true
	else:
		var lead: Dictionary = _known_enemy_mortar_lead()
		if lead.is_empty() or lead.trusted:
			return # a trusted lead is entirely the joint commitment's business, handled above
		target_pos = lead.position
		trusted = false

	for m in player_units:
		if m.kind != Unit.Kind.MORTAR or m.state != Unit.State.ACTIVE:
			continue
		if m.global_position.distance_to(target_pos) <= GameConfig.MORTAR_MAX_RANGE:
			if m.has_move_target:
				# Now in range — stop closing and get to work, rather than
				# finishing the walk to a farther point computed earlier.
				m.has_move_target = false
				m.activity = Unit.Activity.STATIONARY
			continue

		var dest := _friendly_mortar_hunt_point(m, target_pos)
		if dest == m.global_position:
			continue # no safe route found this tick — try again next tick
		if dest.distance_to(_friendly_mortar_home_position) > GameConfig.MORTAR_HUNT_MAX_RANGE_FROM_HOME:
			continue # too far from what the crew considers safe territory, trusted lead or not
		if _friendly_mortar_hunt_destination_is_reckless(dest):
			continue # would put the mortar ahead of, or outside the band held by, its own infantry screen
		if not trusted and m.global_position.distance_to(dest) > GameConfig.MORTAR_HUNT_UNTRUSTED_MAX_RELOCATE:
			continue # too big a gamble on a lead nobody's actually watching

		var was_already_hunting := m.has_move_target
		m.move_target = dest
		m.has_move_target = true
		m.move_queue.clear()
		m.move_speed = GameConfig.MORTAR_RELOCATE_SPEED
		m.movement_predictable = false
		if not was_already_hunting:
			combat_log.log_mortar_hunting(m, trusted)


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

	if _drone_should_rtb(d):
		if backup_drone == null:
			var watched: Unit = _visible_engageable_mortar()
			if watched != null and _can_engage_position(watched.global_position):
				# Sacrifice continues -- fall through to keep watching,
				# ignoring RTB, until the zero-charge check above ends it.
				d.move_target = _drone_search_target()
				d.has_move_target = true
				d.move_queue.clear()
				d.move_speed = GameConfig.DRONE_CRUISE_SPEED
				d.movement_predictable = false
				return
		_send_drone_home(d)
		active_drone = null
		return

	d.move_target = _drone_search_target()
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
	if watched == null or _drone_should_rtb(d):
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
## judging when _mortar_target_value asks on a MORTAR's behalf) and
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
## use of this; _mortar_target_value passes the firing mortar's own team
## instead, since a mortar judges danger to ITS side, not unconditionally
## the player's) — the closer `u` is to actually being able to fight
## someone, the more it matters, ramping smoothly from 0 at
## SQUAD_DANGER_RANGE up to the max right at contact, rather than a hard
## in-range/out-of-range step.
func _squad_danger_priority(u: Unit, threatened_team: Unit.Team = Unit.Team.PLAYER) -> float:
	var nearest_friendly_dist: float = _nearest_active_friendly_distance(u.global_position, threatened_team)
	if is_inf(nearest_friendly_dist):
		return 0.0
	return GameConfig.TARGET_PRIORITY_SQUAD_MAX * clamp(1.0 - nearest_friendly_dist / GameConfig.SQUAD_DANGER_RANGE, 0.0, 1.0)


## Where the drone actually flies once a visible squad is the highest
## priority thing going — NOT that squad's own exact position. A spotted
## squad is rarely alone; working the ground around it (are there more
## squads nearby? a mortar sitting just off to one side?) is worth more
## than parking directly overhead the one unit already confirmed. Circles
## `center` at GameConfig.DRONE_VICINITY_SEARCH_RADIUS, advancing to the
## next point around the circle once close enough — same
## arrival-then-advance shape as _drone_sweep_target, just anchored to a
## live contact instead of a fixed map grid. Re-centers on `center` fresh
## every call, so if the squad itself moves (or a different, now more
## dangerous squad takes over the tier), the circle follows without
## needing to be reset.
func _drone_vicinity_search_point(center: Vector2) -> Vector2:
	var candidate := center + Vector2.RIGHT.rotated(_drone_vicinity_search_angle) * GameConfig.DRONE_VICINITY_SEARCH_RADIUS
	if active_drone.global_position.distance_to(candidate) <= GameConfig.DRONE_VICINITY_SEARCH_ARRIVAL_RADIUS:
		_drone_vicinity_search_angle = wrapf(_drone_vicinity_search_angle + deg_to_rad(GameConfig.DRONE_VICINITY_SEARCH_ANGLE_STEP_DEG), 0.0, TAU)
		candidate = center + Vector2.RIGHT.rotated(_drone_vicinity_search_angle) * GameConfig.DRONE_VICINITY_SEARCH_RADIUS
	return candidate


## Where the airborne drone flies next, re-evaluated every tick — a genuine
## TARGET PRIORITY comparison (GameConfig.TARGET_PRIORITY_*), not hard-coded
## "mortars always win": whichever candidate scores highest right now wins,
## so a future third target kind only needs its own scoring term, not a
## rewrite of this decision. Candidates, each mapped to an actual position:
## (1) any currently visible, still-ACTIVE enemy mortar at all
## (_visible_active_enemy_mortar) — deliberately NOT gated on whether it's
## currently engageable (that stricter question is _visible_engageable_
## mortar's own, used only by the backup/self-sacrifice decisions): losing
## contact on a confirmed live mortar just because the friendly mortar
## can't reach it THIS INSTANT would waste the one asset actually watching
## it, and the situation can change (either mortar can reposition).
## Practically always the winner when one exists, since TARGET_PRIORITY_
## MORTAR sits far above anything else; (2) the freshest in-range fire-
## detection lead on any ACTIVE mortar, discounted somewhat for being a
## stale position rather than a live one, but still real evidence rather
## than speculation; (3) the mortar/drone team's own shared joint hunting
## commitment (_joint_mortar_hunt_target, formed and held by
## _update_joint_mortar_hunt — see its own doc comment), at full mortar
## priority and deliberately NOT range-gated the way (1)/(2) are, since
## its entire purpose is keeping the drone on-station over a target the
## friendly mortar is still walking toward and hasn't reached range of
## yet; (4) the single most dangerous currently-visible ACTIVE enemy
## squad — scored at that squad's own position (_squad_danger_priority),
## but actually FLOWN at a point circling it instead
## (_drone_vicinity_search_point): a spotted squad rarely travels alone,
## so working the surrounding ground for more of them (or whatever's
## supporting them) beats parking directly overhead the one already
## confirmed; (5) the nearest currently-visible RETREATING enemy (squad,
## or a mortar crew that's abandoned its gun for good — that counts as
## "retreating," not "the mortar priority," the instant it happens) —
## scored one of two very different ways depending on whether the battle
## is actually still going: high (TARGET_PRIORITY_RETREATING_ENEMY, a real
## kill worth finishing) once the enemy's own general retreat means little
## else is left to search for; low (TARGET_PRIORITY_RETREATING_ENEMY_LOW)
## while the fight is still on, so one broken straggler doesn't distract
## from whatever's still actually fighting; (6) the ongoing area
## sweep (_drone_sweep_target), valued as the genuine expected value of
## what it might still find — TARGET_PRIORITY_MORTAR times
## _mortar_existence_confidence(). That last term is what lets the drone's
## default search effort shift naturally toward tracking real, visible
## squads (advancing OR retreating) instead of an indefinite mortar-shaped
## sweep once mortar fire hasn't been detected in a long while, or every
## known enemy mortar is confirmed out of action — without ever
## hard-coding either condition directly here. Tier (4)'s own candidate
## pool empties out on its own once the enemy commander orders a general
## retreat (every ACTIVE squad is pulled into RETREATING in that same
## instant — see _check_enemy_commander_retreat) — there's usually nothing
## left "advancing" to search for at that point. Tier (6) is ALSO directly
## discounted (GameConfig.SWEEP_DISCOUNT_DURING_ENEMY_RETREAT) the instant
## that same general retreat is ordered, on top of whatever the slower,
## generic confidence decay has already done — a commander who's just
## called off the attack has little reason left to keep searching broadly
## for new arrivals, and this makes that immediate rather than waiting on
## the same decay curve built for "no mortar fire in a while."
func _drone_search_target() -> Vector2:
	var best_score := -1.0
	var best_pos := Vector2.INF

	var watched: Unit = _visible_active_enemy_mortar()
	if watched != null:
		best_score = GameConfig.TARGET_PRIORITY_MORTAR
		best_pos = watched.global_position

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

	var flank_watch_pos: Vector2 = _drone_flank_watch_target()
	if not is_inf(flank_watch_pos.x) and GameConfig.TARGET_PRIORITY_FLANK_WATCH > best_score:
		best_score = GameConfig.TARGET_PRIORITY_FLANK_WATCH
		best_pos = flank_watch_pos

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
		best_pos = _drone_vicinity_search_point(best_squad.global_position)

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

	var sweep_score: float = GameConfig.TARGET_PRIORITY_MORTAR * _mortar_existence_confidence()
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
		sweep_score *= GameConfig.SWEEP_DISCOUNT_DURING_ENEMY_RETREAT
	if sweep_score > best_score or is_inf(best_pos.x):
		best_pos = _drone_sweep_target()

	return best_pos


## Where the drone checks for an enemy flanking around toward the mortar's
## blind side — the drone's own contribution to spotting the kind of
## approach _update_friendly_squad_positioning exists to answer, ideally
## before it's close enough to force that response at all. Vector2.INF (no
## flank worth watching right now) if the mortar isn't ACTIVE, or if every
## compass bearing around it is already either screened by an ACTIVE
## friendly squad (_lane_is_screened — that lane already has real coverage)
## or sitting on/near an already-known enemy position (already covered by a
## higher-priority tier above — no point in redundantly re-watching it).
##
## Sticky like _drone_sweep_target's own waypoint: keeps heading to the
## SAME point once picked, rather than re-rolling every tick, until either
## the drone actually arrives (DRONE_FLANK_WATCH_ARRIVE_RADIUS) or that
## bearing stops qualifying (a squad now screens it, or something's been
## spotted there since) — otherwise a bearing that briefly loses and
## re-wins the weighted pick against its neighbors would have the drone
## flitting between them instead of committing to actually checking one.
func _drone_flank_watch_target() -> Vector2:
	var mortar := _friendly_active_mortar()
	if mortar == null:
		return Vector2.INF

	var screening_squads: Array[Unit] = []
	for u in player_units:
		if u.kind == Unit.Kind.SQUAD and u.state == Unit.State.ACTIVE:
			screening_squads.append(u)
	var known_enemies := _known_enemy_positions(Unit.Team.PLAYER)

	var qualifying: Array[Vector2] = []
	for bearing_deg in GameConfig.DRONE_FLANK_WATCH_BEARINGS_DEG:
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
		qualifying.append(probe)

	if qualifying.is_empty():
		return Vector2.INF

	var current_still_qualifies: bool = qualifying.any(func(p): return p.distance_to(_drone_flank_watch_point) < 1.0)
	if not current_still_qualifies or active_drone.global_position.distance_to(_drone_flank_watch_point) <= GameConfig.DRONE_FLANK_WATCH_ARRIVE_RADIUS:
		_drone_flank_watch_point = qualifying[randi() % qualifying.size()]
	return _drone_flank_watch_point


## The single currently-visible, still-ACTIVE, in-range enemy mortar worth
## the backup-drone/self-sacrifice decisions actually acting on — used by
## _update_active_drone/_update_backup_drone/the backup-launch trigger in
## _update_drone_operations, all of which are asking "is there one right
## now we can actually DO something about," not just "is there one worth
## watching" (see _visible_active_enemy_mortar for that, weaker, question
## — _drone_search_target's own top tier). A RETREATING mortar has already
## had its crew abandon the gun for good (Unit._apply_crew_casualties — it
## will never fire again no matter how well it's watched), and one outside
## GameConfig.MORTAR_MAX_RANGE of the friendly mortar can't be engaged
## right now regardless of visibility — sacrificing a drone, or spending a
## backup's own limited flight time, over either just wastes an asset that
## could instead find (or wait for) a mortar actually worth acting on.
func _visible_engageable_mortar() -> Unit:
	for u in enemy_units:
		if u.kind == Unit.Kind.MORTAR and u.state == Unit.State.ACTIVE and u.is_visible and _in_friendly_mortar_range(u.global_position):
			return u
	return null


## Any currently visible, still-ACTIVE enemy mortar at all — unlike
## _visible_engageable_mortar, NOT gated on whether it's currently in
## range of friendly fire. This is _drone_search_target's own top tier:
## the question there is simply "is this worth the drone's attention,"
## and a live enemy mortar always is, regardless of whether it happens to
## be engageable this exact instant — the friendly mortar can reposition
## too, and simply maintaining contact on a confirmed, live mortar has
## real value on its own (an early-warning asset that's found the enemy's
## fire support and then wandered off the moment engaging it wasn't
## IMMEDIATELY feasible was the actual bug this fixes: the range-gate in
## _visible_engageable_mortar only ever belonged to the backup/self-
## sacrifice decisions above, which really do need "can we act on this
## right now," not to the much more basic "should we keep watching it."
func _visible_active_enemy_mortar() -> Unit:
	for u in enemy_units:
		if u.kind == Unit.Kind.MORTAR and u.state == Unit.State.ACTIVE and u.is_visible:
			return u
	return null


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
## on), but not uniformly — see _weighted_random_sweep_index, which
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
## much less worth the trip (see _weighted_random_sweep_index). Uses the
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


## A grid index chosen with GameConfig.DRONE_SWEEP_ROW_WEIGHTS bias toward
## the rows nearest the road (see _drone_sweep_target's own reasoning),
## further reduced per-waypoint wherever _area_confirmed_clear says the
## enemy is already known not to be — shared by the initial pick at battle
## start (see start_battle) and every subsequent re-roll on arrival, so
## "where the drone starts" and "where it keeps going" are the same
## underlying bias instead of two separate, potentially inconsistent
## mechanisms. A genuine weighted-random pick across all 25 cells at once,
## not row-then-uniform-column as before — with nothing confirmed clear
## this reduces to exactly the same distribution (each cell in a row gets
## an equal share of that row's own weight), so this is a generalization,
## not a behavior change, for the common case where nothing's confirmed
## clear yet.
func _weighted_random_sweep_index() -> int:
	var row_count: int = GameConfig.DRONE_SEARCH_GRID_ROWS_M.size()
	var columns_per_row: int = GameConfig.DRONE_SEARCH_GRID_COLUMNS_M.size()
	var waypoints: Array[Vector2] = GameConfig.drone_search_waypoints_px()
	var weights: Array[float] = []
	var total := 0.0
	for row_i in row_count:
		for col_i in columns_per_row:
			var idx: int = row_i * columns_per_row + col_i
			var w: float = GameConfig.DRONE_SWEEP_ROW_WEIGHTS[row_i] / float(columns_per_row)
			if _area_confirmed_clear(waypoints[idx]):
				w *= GameConfig.DRONE_SWEEP_CLEARED_WEIGHT_MULTIPLIER
			weights.append(w)
			total += w
	var roll: float = randf() * total
	var cumulative := 0.0
	for i in weights.size():
		cumulative += weights[i]
		if roll <= cumulative:
			return i
	return weights.size() - 1


func _drone_sweep_target() -> Vector2:
	var waypoints: Array[Vector2] = GameConfig.drone_search_waypoints_px()
	if active_drone.global_position.distance_to(waypoints[_drone_sweep_index]) <= DRONE_SWEEP_WAYPOINT_RADIUS:
		_drone_sweep_index = _weighted_random_sweep_index()
	return waypoints[_drone_sweep_index]


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


## "Friendly mortar should always try to stay where it won't be seen" — the
## reactive half of that: the instant it's actually spotted while just
## sitting there between shots with NOTHING worth shooting at (is_visible,
## a live fact — see _refresh_visibility, and not already moving for some
## other reason), it relocates via _relocate_mortar. The other half — a
## shoot-and-scoot mortar displacing after EVERY shot as standing
## procedure, whether spotted or not — is handled separately in _tick_fire,
## since that's doctrine-driven, not purely reactive; a hold-position
## mortar relies on THIS check alone, so it stays put unless something
## actually threatens it.
##
## Being spotted alone does NOT mean flee — if it currently HAS a target
## (including an enemy mortar that's wandered into range), it stands and
## fights rather than running from a fight it can win; concealment is the
## fallback when it's exposed with nothing to show for it, not an automatic
## reflex to being seen.
##
## Runs AFTER _tick_fire each tick, not before — a mortar that's ready to
## fire right now gets that shot off first; only if it DIDN'T fire this
## tick and is sitting there exposed does this apply.
func _update_friendly_mortar_concealment() -> void:
	for m in player_units:
		if m.kind != Unit.Kind.MORTAR or m.state != Unit.State.ACTIVE or m.has_move_target:
			continue
		if not m.is_visible:
			continue
		if _pick_target(m, enemy_units) != null:
			continue # something worth shooting at — stand and fight rather than flee
		if _relocate_mortar(m):
			combat_log.log_mortar_relocating_for_cover(m)


## A mortar with zero rounds left can't shoot back — standing its ground
## serves no purpose while it waits for resupply, and it's still exactly as
## vulnerable as an armed one would be. Applies to BOTH sides identically
## (unlike _update_friendly_mortar_concealment above, this isn't gated on
## being currently spotted — being defenseless is reason enough on its own
## to seek better concealment, not just a reaction to being seen), though
## only the player's own move is narrated (see _should_narrate_mortar_
## logistics's fog-of-war reasoning — the enemy's move happens exactly the
## same way, just silently, same as its resupply fetch trips already do).
##
## Runs before _update_friendly_mortar_concealment so an out-of-ammo mortar
## that's ALSO currently spotted gets the more specific "out of ammo"
## framing rather than the generic "spotted" one — both would pick the same
## destination via _relocate_mortar regardless, this only decides which log
## message describes it. Naturally defers to a fetch trip already claimed
## this tick (_update_mortar_resupply_fetch runs earlier) via the same
## has_move_target check every other reactive relocation here uses.
func _update_mortar_safety_relocation() -> void:
	for m in player_units + enemy_units:
		if m.kind != Unit.Kind.MORTAR or m.state != Unit.State.ACTIVE or m.has_move_target:
			continue
		if m.mortar_rounds_remaining > 0:
			continue
		if _relocate_mortar(m):
			if _should_narrate_mortar_logistics(m):
				combat_log.log_mortar_relocating_out_of_ammo(m)


func _process(delta: float) -> void:
	if battle_over or combat_log == null:
		return

	elapsed_time += delta
	_seconds_since_last_shot += delta

	var scenario_delta: float = delta * _current_time_scale()
	scenario_elapsed_time += scenario_delta

	_update_sighting_flags()
	_update_mortar_resupply()
	_update_mortar_resupply_requests()

	_tick_movement(scenario_delta)
	_update_spotting(delta)
	_update_enemy_mortar_positioning()
	_update_joint_mortar_hunt()
	_update_friendly_mortar_hunting()
	_update_mortar_resupply_fetch()
	_update_enemy_squad_advance()
	_update_friendly_squad_positioning()
	_update_drone_operations(scenario_delta)

	for unit in player_units:
		_tick_fire(unit, delta, scenario_delta, enemy_units)
	for unit in enemy_units:
		_tick_fire(unit, delta, scenario_delta, player_units)

	_update_mortar_safety_relocation()
	_update_friendly_mortar_concealment()
	_resolve_pending_counter_battery()
	_resolve_pending_mortar_shots()
	_update_player_intel()
	_check_enemy_commander_retreat()
	_prune_fire_flashes()
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


func _step_toward_target(unit: Unit, scenario_delta: float) -> void:
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


## The final leg is a straight dash at constant y toward the safe line — for
## a MORTAR, that line can happen to run straight through a building (the
## village is a real obstacle now, not a rare edge case at this map's real
## scale). Since a mortar can never enter one, it sidesteps vertically,
## away from whatever building is blocking it, until clear, then the normal
## x-only dash resumes on its own — see _sidestep_building.
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

	if unit.kind == Unit.Kind.MORTAR and GameConfig.is_building_at(next_pos):
		_sidestep_building(unit, scenario_delta, next_pos)
		return

	unit.position = next_pos
	var reached: bool = (unit.position.x <= unit.retreat_target_x) if unit.team == Unit.Team.PLAYER else (unit.position.x >= unit.retreat_target_x)
	if reached:
		unit.position.x = unit.retreat_target_x
		unit.state = Unit.State.WITHDRAWN
		unit.queue_redraw()
		combat_log.log_withdrawn(unit)


func _sidestep_building(unit: Unit, scenario_delta: float, blocked_pos: Vector2) -> void:
	var building_center_y: float = unit.position.y
	for zone in GameConfig.TERRAIN_ZONES:
		if zone.type == GameConfig.TerrainType.BUILDING and zone.rect.has_point(blocked_pos):
			building_center_y = zone.rect.position.y + zone.rect.size.y / 2.0
			break
	var dir_y: float = -1.0 if unit.position.y <= building_center_y else 1.0
	unit.position.y += dir_y * unit.retreat_speed * scenario_delta


func _update_spotting(delta: float) -> void:
	_refresh_visibility(player_units, enemy_units, delta)
	_refresh_visibility(enemy_units, player_units, delta)


## Visibility is live, not permanent: a target already visible stays that
## way only as long as some observer currently has line of sight to it
## (checked every tick, hard cutoff, no chance roll — see
## CombatResolver.has_live_observer); the instant nobody does, it goes
## invisible again, even if it was seen a moment ago. A target not currently
## visible has a chance each tick to be freshly noticed (CombatResolver.
## roll_spot — the existing probabilistic, concealment-aware roll).
##
## The one exception: the friendly (player) mortar is never visually
## spotted by this at all, categorically — a well-sited, camouflaged crew
## on a reverse slope isn't something rifle squads happen to notice by
## scanning the horizon. The ONLY way the enemy ever gets a fix on it is by
## detecting it actually firing (real counter-battery detection, via
## muzzle blast/trajectory rather than eyesight — see _launch_mortar_shot's
## _last_detected_mortar_fire and _known_friendly_mortar_position, which
## the enemy's counter-battery-range chase already relies on for exactly
## this case).
func _refresh_visibility(observers: Array[Unit], targets: Array[Unit], delta: float) -> void:
	for target in targets:
		if target.state == Unit.State.DESTROYED or target.state == Unit.State.SURRENDERED:
			continue
		if target.kind == Unit.Kind.MORTAR and target.team == Unit.Team.PLAYER:
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
			if CombatResolver.roll_spot(observer, target, delta):
				target.is_visible = true
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


## `scenario_delta` (tactical seconds) drives a MORTAR's reload timer — a
## realistic lay-load-fire cycle is a real-world-time thing (see Unit.
## reload_time), not tied to how much actual play-session time you spend
## watching. Everything else (squad fire_interval, the has_move_target/
## building gates below) stays on `delta` (actual/engine seconds) — those
## were never part of this ask, just the mortar's own cycle was.
func _tick_fire(unit: Unit, delta: float, scenario_delta: float, enemies: Array[Unit]) -> void:
	if unit.kind == Unit.Kind.SPOTTER or unit.kind == Unit.Kind.DRONE_TEAM or unit.kind == Unit.Kind.DRONE:
		return # pure reconnaissance — extends detection only, never fires (see roll_spot)
	if unit.state != Unit.State.ACTIVE:
		return # destroyed/withdrawn/retreating units don't fire
	if unit.has_move_target:
		return # moving with intent (road march, diving for cover) — too busy to fire.
		# Without this, "immediately head for cover" was true mechanically
		# (seek_cover() redirects movement right away) but invisible in
		# practice: the unit kept trading fire the whole way there, so a
		# dash for cover looked identical to just standing and fighting.
	if unit.kind == Unit.Kind.MORTAR and GameConfig.is_building_at(unit.global_position):
		return # no overhead clearance to lob a round from inside a building
	if unit.kind == Unit.Kind.MORTAR and unit.mortar_rounds_remaining <= 0:
		return # out of ammunition — see _update_mortar_resupply_fetch for how it eventually gets more

	unit.fire_timer -= scenario_delta if unit.kind == Unit.Kind.MORTAR else delta
	if unit.fire_timer > 0.0:
		return

	var target := _pick_target(unit, enemies)
	if target == null:
		unit.fire_timer = unit.fire_interval
		return

	if unit.kind == Unit.Kind.MORTAR:
		_launch_mortar_shot(unit, target)
		unit.fire_timer = unit.reload_time
		# Shoot-and-scoot doctrine: displace after EVERY shot, procedurally,
		# whether or not it's currently spotted — that's the whole point of
		# the doctrine (see design doc). A hold-position mortar does NOT do
		# this — it only relocates reactively, if actually spotted, which
		# _update_friendly_mortar_concealment's per-tick check already
		# covers (including the tick right after firing, if firing is what
		# exposed it) — no separate trigger needed here for that case.
		if unit.shoot_and_scoot:
			var urgent := unit.evading_counter_battery
			if _relocate_mortar(unit):
				combat_log.log_relocate(unit, urgent)
		return

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
	_seconds_since_last_shot = 0.0
	# Firing is detectable (muzzle blast/trajectory) independent of whether
	# the mortar is otherwise visually spotted — see
	# _known_friendly_mortar_position, which the enemy's counter-battery-range
	# chase (_update_enemy_mortar_positioning) relies on for exactly this case.
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
	var velocity := Vector2.ZERO
	if target.has_move_target:
		var to_target: Vector2 = target.move_target - target.global_position
		if to_target.length() > 0.01:
			velocity = to_target.normalized() * target.move_speed
	elif target.state == Unit.State.RETREATING:
		# The final leg: no move_target, just a straight dash at constant y
		# toward the safe line (see _step_retreat) — direction is fixed by
		# team, so this heading is exactly known even with no move_target.
		var dir_x: float = -1.0 if target.team == Unit.Team.PLAYER else 1.0
		velocity = Vector2(dir_x * target.retreat_speed, 0.0)
	if velocity == Vector2.ZERO:
		return target.global_position
	return target.global_position + velocity * GameConfig.MORTAR_FLIGHT_TIME


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
		if _pick_target(u, player_units) != null:
			continue # something to shoot at right now — stay and fight
		var rush_target := _next_advance_point(u)
		if rush_target == u.global_position:
			continue
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
	var objective: Vector2 = _enemy_advance_objective()
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
	var candidates: Array[Vector2] = []
	for angle_deg in GameConfig.ENEMY_ADVANCE_ANGLES_DEG:
		candidates.append(u.global_position + to_objective.normalized().rotated(deg_to_rad(angle_deg)) * rush)
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
func _enemy_advance_objective() -> Vector2:
	var mortar_pos := _known_friendly_mortar_position()
	if not is_inf(mortar_pos.x) and _friendly_mortar_is_active():
		return mortar_pos
	return GameConfig.VILLAGE_CENTER


func _friendly_mortar_is_active() -> bool:
	for u in player_units:
		if u.kind == Unit.Kind.MORTAR and u.state == Unit.State.ACTIVE:
			return true
	return false


## The friendly-side counterpart to _update_enemy_squad_advance: an idle,
## ACTIVE player squad with nothing worth shooting at right now (same idle
## gate — a squad already fighting stands and fights, it doesn't reposition
## out from under a live engagement) watches for two things and answers
## either, in priority order:
##
## (1) SELF-PRESERVATION — see _reposition_for_encirclement. A squad that's
## actually at risk of being surrounded pulls back toward its own side's
## center of mass instead of standing to be overrun. It's marked in
## `at_risk` so the pass below never reassigns it to go plug a gap
## elsewhere — it's already got its own problem to solve.
##
## (2) MORTAR PROTECTION — for the single nearest known enemy that has an
## open, unscreened lane to the friendly mortar's own actual position (see
## _nearest_unscreened_mortar_threat/_lane_is_screened), the nearest
## still-idle, not-already-at-risk squad moves out to MORTAR_PROTECTIVE_
## RADIUS from the mortar, on the bearing toward that threat — directly
## interposing itself between the two. Only the single closest open lane is
## answered per tick, one squad at a time, rather than every idle squad
## reshuffling at once for threats that may resolve themselves before
## anyone arrives.
##
## Deliberately never narrates *why* a squad moves (no "the mortar's
## position is known" log) — that would hand the player intel about the
## enemy's own knowledge state it wouldn't otherwise have, the same
## fog-of-war line drawn around the enemy's mortar ammo/resupply status.
func _update_friendly_squad_positioning() -> void:
	var known_enemies := _known_enemy_positions(Unit.Team.PLAYER)
	var at_risk: Dictionary = {}
	for u in player_units:
		if u.kind != Unit.Kind.SQUAD or u.state != Unit.State.ACTIVE or u.has_move_target:
			continue
		if _pick_target(u, enemy_units) != null:
			continue # something to shoot at right now — stand and fight
		if _reposition_for_encirclement(u, known_enemies):
			at_risk[u] = true

	var mortar := _friendly_active_mortar()
	if mortar == null:
		return
	var threat := _nearest_unscreened_mortar_threat(mortar, known_enemies)
	if is_inf(threat.x):
		return

	var responder: Unit = null
	var best_dist := INF
	for u in player_units:
		if u.kind != Unit.Kind.SQUAD or u.state != Unit.State.ACTIVE or u.has_move_target or at_risk.has(u):
			continue
		if _pick_target(u, enemy_units) != null:
			continue
		var d: float = u.global_position.distance_to(mortar.global_position)
		if d < best_dist:
			best_dist = d
			responder = u
	if responder == null:
		return

	var block_point: Vector2 = mortar.global_position + (threat - mortar.global_position).normalized() * GameConfig.MORTAR_PROTECTIVE_RADIUS
	responder.move_target = block_point
	responder.has_move_target = true
	responder.move_queue.clear()
	responder.move_speed = GameConfig.REPOSITION_SPEED
	responder.movement_predictable = false
	combat_log.log_squad_blocking_flank(responder)


## True (and issues the actual repositioning move) if `u` is genuinely at
## risk of being surrounded: known enemies within FRIENDLY_ENCIRCLEMENT_
## DETECT_RADIUS span at least FRIENDLY_ENCIRCLEMENT_ANGLE_THRESHOLD_DEG of
## arc around it, AND at least FRIENDLY_ENCIRCLEMENT_MIN_COVERED_FRACTION of
## them are already dug into real cover — "surrounded by enemies under
## cover," the specific hopeless case, not just "outnumbered from two
## sides" by contacts still caught in the open. Pulls back toward the
## center of mass of the rest of this squad's own side (every other ACTIVE
## unit, not just squads — the mortar and spotter/drone team count too) by
## a bounded step, or toward the mortar alone if it's the only one left.
func _reposition_for_encirclement(u: Unit, known_enemies: Array[Vector2]) -> bool:
	var nearby: Array[Vector2] = []
	for p in known_enemies:
		if u.global_position.distance_to(p) <= GameConfig.FRIENDLY_ENCIRCLEMENT_DETECT_RADIUS:
			nearby.append(p)
	if nearby.size() < 2:
		return false

	var covered := 0
	for p in nearby:
		if GameConfig.is_in_cover(GameConfig.get_terrain_type_at(p)):
			covered += 1
	if float(covered) / float(nearby.size()) < GameConfig.FRIENDLY_ENCIRCLEMENT_MIN_COVERED_FRACTION:
		return false

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
	if 360.0 - max_gap < GameConfig.FRIENDLY_ENCIRCLEMENT_ANGLE_THRESHOLD_DEG:
		return false

	var allies := _ally_units_for(u)
	var rally_point: Vector2
	if allies.is_empty():
		var mortar := _friendly_active_mortar()
		if mortar == null:
			return false
		rally_point = mortar.global_position
	else:
		var sum := Vector2.ZERO
		for a in allies:
			sum += a.global_position
		rally_point = sum / allies.size()

	var to_rally: Vector2 = rally_point - u.global_position
	if to_rally.length() < 10.0:
		return false
	var step: float = min(to_rally.length(), GameConfig.FRIENDLY_REPOSITION_RUSH_DISTANCE)
	u.move_target = u.global_position + to_rally.normalized() * step
	u.has_move_target = true
	u.move_queue.clear()
	u.move_speed = GameConfig.REPOSITION_SPEED
	u.movement_predictable = false
	combat_log.log_squad_consolidating(u)
	return true


func _friendly_active_mortar() -> Unit:
	for u in player_units:
		if u.kind == Unit.Kind.MORTAR and u.state == Unit.State.ACTIVE:
			return u
	return null


## The nearest known enemy (from the player's own full knowledge of its own
## mortar's position — not the enemy's possibly-stale fix on it) within
## MORTAR_FLANK_THREAT_RADIUS of `mortar` that has no ACTIVE friendly squad
## currently screening the direct line between the two (_lane_is_screened)
## — an open lane worth a squad breaking off to plug. Vector2.INF if every
## nearby threat already has a squad in the way, or nothing is close enough
## to be a real threat yet.
func _nearest_unscreened_mortar_threat(mortar: Unit, known_enemies: Array[Vector2]) -> Vector2:
	var screening_squads: Array[Unit] = []
	for u in player_units:
		if u.kind == Unit.Kind.SQUAD and u.state == Unit.State.ACTIVE:
			screening_squads.append(u)

	var best := Vector2.INF
	var best_dist := INF
	for p in known_enemies:
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
## every enemy unit — a chance to notice and shoot back. Shoot-and-scoot
## keeps that chance low; holding position in one spot raises it a lot.
## Mortars are a high-priority target for each other. This isn't abstract:
## the return fire has to physically come from an opposing mortar that
## could actually reach this position — one beyond GameConfig.MORTAR_MAX_RANGE
## simply can't respond, no matter how exposed the firing mortar was. A
## mortar dug in deep enough to be out of both enemy tubes' range trades
## away some of its own reach for genuine counter-battery immunity.
##
## The strike isn't instant: it can only ever target where THIS mortar was
## standing right now, at the moment it fired (captured here, before any
## post-shot scoot hop) — see _resolve_pending_counter_battery for the
## delayed impact that actually checks whether it's still nearby. The delay
## itself is random — GameConfig.COUNTER_BATTERY_DELAY_MIN/MAX, 1-3 tactical
## minutes — not a fixed interval; real counter-battery response time varies
## with how quickly the opposing crew can get a fire mission organized.
func _resolve_mortar_counter_battery(firing_mortar: Unit) -> void:
	var opposing: Array[Unit] = player_units if firing_mortar.team == Unit.Team.ENEMY else enemy_units
	var chance: float = GameConfig.MORTAR_COUNTER_BATTERY_SCOOT_CHANCE if firing_mortar.shoot_and_scoot else GameConfig.MORTAR_COUNTER_BATTERY_HOLD_CHANCE
	for m in opposing:
		if m.kind != Unit.Kind.MORTAR or m.state != Unit.State.ACTIVE:
			continue
		if m.global_position.distance_to(firing_mortar.global_position) > GameConfig.MORTAR_MAX_RANGE:
			continue # out of range — this mortar physically cannot reach back
		if randf() < chance:
			var delay: float = randf_range(GameConfig.COUNTER_BATTERY_DELAY_MIN, GameConfig.COUNTER_BATTERY_DELAY_MAX)
			_pending_counter_battery.append({
				"target": firing_mortar,
				"impact_position": firing_mortar.global_position,
				"impact_time": scenario_elapsed_time + delay,
			})
			combat_log.log_counter_battery_incoming(firing_mortar)
			break # one incoming strike per shot is enough, even with two enemy mortars


## Resolves any counter-battery strikes whose delay has elapsed. The target
## is only hit if it's still within the blast radius of where it fired from
## — a hold-position mortar never moves, so it's always caught; a
## shoot-and-scoot mortar has usually relocated well clear by the time this
## lands, and even if it's still nearby the odds are reduced, not certain.
func _resolve_pending_counter_battery() -> void:
	var still_pending: Array[Dictionary] = []
	for strike in _pending_counter_battery:
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
			target.take_hit(true, [], _known_enemy_positions(target.team))
			combat_log.log_counter_battery(target)
			_log_hit_consequence(target, true)
		else:
			combat_log.log_counter_battery_miss(target)
	_pending_counter_battery = still_pending


## Relocates `mortar` to wherever it now considers desirable — the nearest
## point with no direct line of sight from any currently-known enemy (real
## concealment, not just reduced spot-chance cover), or, with no known
## threat to hide from, simply the nearest cover: displacing is a standing
## procedure for a shoot-and-scoot crew regardless of whether a threat is
## currently visible, not a purely reactive move. Walks there — real speed,
## real distance, real travel time, no separate cooldown bolted on top (see
## Unit.reload_time) — faster and farther if the crew has actually taken
## counter-battery fire recently (Unit.evading_counter_battery, consumed
## here), slower moving into trees than open ground. Returns false (no-op)
## if there's nowhere better to go right now.
func _relocate_mortar(mortar: Unit) -> bool:
	var urgent: bool = mortar.evading_counter_battery
	mortar.evading_counter_battery = false
	var threats := _known_enemy_positions(mortar.team)
	var destination: Vector2 = (
		GameConfig.nearest_hidden_point(mortar.global_position, threats, true, urgent)
		if not threats.is_empty()
		else GameConfig.nearest_cover_point(mortar.global_position, 0.0, true)
	)
	if destination == mortar.global_position:
		return false

	var speed: float = GameConfig.MORTAR_RELOCATE_SPEED_URGENT if urgent else GameConfig.MORTAR_RELOCATE_SPEED
	if GameConfig.get_terrain_type_at(destination) == GameConfig.TerrainType.TREES:
		speed *= GameConfig.MORTAR_RELOCATE_TREES_MULTIPLIER

	mortar.move_target = destination
	mortar.has_move_target = true
	mortar.move_queue.clear()
	mortar.move_speed = speed
	mortar.movement_predictable = false
	return true


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
## _mortar_target_value, not uniform: a fuller unit is a juicier target
## (more casualties per hit — see Unit.take_hit's own from_mortar
## scaling), and a target currently dangerous to the mortar's own side
## matters too, whether or not it happens to also be full-strength. Both
## real considerations, weighted rather than either one deciding outright
## — a damaged-but-threatening squad can still outweigh an
## undamaged-but-harmless one.
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
	if candidates.is_empty():
		return null

	var mortar_candidates: Array[Unit] = candidates.filter(func(c): return c.kind == Unit.Kind.MORTAR and c.state == Unit.State.ACTIVE)
	if not mortar_candidates.is_empty():
		return mortar_candidates[randi() % mortar_candidates.size()]
	if unit.kind == Unit.Kind.MORTAR:
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
		var scarcity: float = _mortar_ammo_scarcity(unit)
		var urgency: float = _mortar_resupply_urgency(unit)
		var hold_fire_chance: float = scarcity * (1.0 - urgency)
		if randf() < hold_fire_chance:
			return null
		return _weighted_mortar_target_pick(unit, candidates)
	return candidates[randi() % candidates.size()]


## 0.0 (nothing pending, or the soonest still-unresolved wave is still
## GameConfig.MORTAR_RESUPPLY_URGENCY_HORIZON_MINUTES or more away) to 1.0
## (rounds already sitting at the resupply point, awaiting pickup — as
## urgent/certain as it gets short of already being in the tube), ramping
## linearly as the soonest still-unresolved wave's actual arrival time
## approaches. Drives _pick_target's own sliding-scale ammo conservation —
## see GameConfig.MORTAR_RESUPPLY_URGENCY_HORIZON_MINUTES's own comment for
## the full reasoning. Also the source for CasualtyDashboard's live
## "resupply ~Nm out" / "ready for pickup" readout (see mortar_resupply_status).
func _mortar_resupply_urgency(mortar: Unit) -> float:
	var record: Dictionary = _mortar_resupply.get(mortar, {})
	if record.is_empty():
		return 0.0
	if int(record.get("rounds_waiting", 0)) > 0:
		return 1.0
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
## (spend freely), ramping linearly to 1.0 as rounds approach zero.
func _mortar_ammo_scarcity(mortar: Unit) -> float:
	return clamp(1.0 - float(mortar.mortar_rounds_remaining) / float(GameConfig.MORTAR_STARTING_AMMO), 0.0, 1.0)


## Public accessor for CasualtyDashboard's live per-mortar readout — never
## reveals the true underlying arrival time as some kind of privileged
## knowledge the player shouldn't have (this IS the player's own mortar's
## status board, not the enemy's), just a friendly summary of the same
## state _mortar_resupply_urgency already computes from.
func mortar_resupply_status(mortar: Unit) -> Dictionary:
	var record: Dictionary = _mortar_resupply.get(mortar, {})
	if record.is_empty():
		return {"pending": false}
	if int(record.get("rounds_waiting", 0)) > 0:
		return {"pending": true, "ready_for_pickup": true}
	var arrivals: Array = record.get("wave_arrival_times", [])
	var resolved: Array = record.get("wave_resolved", [])
	var soonest: float = INF
	for i in arrivals.size():
		if not resolved[i]:
			soonest = min(soonest, float(arrivals[i]))
	if is_inf(soonest):
		return {"pending": false}
	var minutes_left: float = max(soonest - scenario_elapsed_time, 0.0) / 60.0
	return {"pending": true, "ready_for_pickup": false, "minutes_until_next": minutes_left}


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


## Minutes since `mortar` was last detected firing, for the same "detected
## firing" dashboard case above — INF if it's never been detected at all
## (callers should already have checked mortar_recently_detected_firing).
func mortar_minutes_since_detected_firing(mortar: Unit) -> float:
	var info: Dictionary = _last_detected_mortar_fire.get(mortar, {})
	if info.is_empty():
		return INF
	return (scenario_elapsed_time - info.time) / 60.0


## How much a MORTAR would value firing on `target` right now — see
## _pick_target's own doc comment for the two factors this weighs.
## Casualty potential is just the target's own current pip count (more
## people actually there to hit); danger is _squad_danger_priority judged
## against `unit`'s OWN side (not unconditionally the player's — an enemy
## mortar weighing this cares about danger to the ENEMY side), zero for
## anything that isn't a squad currently ACTIVE (a spotter, an
## already-fleeing mortar crew, or a squad that's itself RETREATING poses
## no real danger to anyone — it's pulling out, not fighting, so proximity
## to a friendly alone shouldn't read as a threat; matches the same
## state == ACTIVE gate _drone_search_target already applies to its own
## squad-danger scoring). Both terms land on roughly the same 0-10ish
## scale by construction (max pips 9, TARGET_PRIORITY_SQUAD_MAX 10), so
## equal weights (GameConfig.MORTAR_TARGET_CASUALTY_WEIGHT/_DANGER_WEIGHT)
## already balance them reasonably without needing wildly different
## magnitudes.
func _mortar_target_value(unit: Unit, target: Unit) -> float:
	var casualty_value: float = float(target.pips)
	var is_active_squad: bool = target.kind == Unit.Kind.SQUAD and target.state == Unit.State.ACTIVE
	var danger_value: float = _squad_danger_priority(target, unit.team) if is_active_squad else 0.0
	return GameConfig.MORTAR_TARGET_CASUALTY_WEIGHT * casualty_value + GameConfig.MORTAR_TARGET_DANGER_WEIGHT * danger_value


## A genuine weighted-random choice among `candidates` (each one's own
## _mortar_target_value as its weight), not a deterministic "always the
## single best one" — real fire-mission targeting isn't perfectly
## rational, and this keeps the mortar's target choice from being
## trivially predictable the way always picking the objective maximum
## would be. Every candidate's value is guaranteed positive (a targetable
## unit always has at least 1 pip), so no separate floor is needed to keep
## every weight meaningfully positive.
func _weighted_mortar_target_pick(unit: Unit, candidates: Array[Unit]) -> Unit:
	var weights: Array[float] = []
	var total := 0.0
	for c in candidates:
		var w: float = _mortar_target_value(unit, c)
		weights.append(w)
		total += w
	var roll: float = randf() * total
	var cumulative := 0.0
	for i in candidates.size():
		cumulative += weights[i]
		if roll <= cumulative:
			return candidates[i]
	return candidates[candidates.size() - 1]


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
## contributes to the known TOTAL order of battle (pips_total) but not a
## single casualty — assumed still active and undamaged, not "unknown,"
## since crediting losses nobody actually confirmed would be worse than
## just not knowing.
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
		if u.kind != Unit.Kind.DRONE:
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
		if u.kind != Unit.Kind.DRONE:
			pips_lost += (u.max_pips - eff_pips)
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
				if not unit_estimated:
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
	lines.append("Village held: %s" % ("YES" if held else "NO"))
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
	if enemy_stats.estimated:
		lines.append("Enemy casualties: an estimated %d/%d personnel (~%.0f%%) — the position wasn't held for a battlefield assessment, so this reflects only what was actually scouted during the fight, not the true toll" % [
			enemy_stats.pips_lost, enemy_stats.pips_total, enemy_stats.casualty_percent,
		])
	else:
		# No "walking wounded" line here, unlike the player's own casualties
		# above — a losing side evacuates its own ambulatory wounded under
		# their own power even from a position it's about to lose, so
		# holding the ground afterward doesn't actually answer what became
		# of them; `evacuated_unknown` is a real, counted personnel loss,
		# just not one this assessment can characterize any further (see
		# _compute_side_stats's own `is_enemy_side` doc comment).
		lines.append("Enemy casualties: %d/%d personnel (%.0f%%) — %d killed, %d heavily wounded, %d captured, %d more unaccounted for (likely evacuated wounded — the enemy pulls its own ambulatory casualties out even from ground it's about to lose)" % [
			enemy_stats.pips_lost, enemy_stats.pips_total, enemy_stats.casualty_percent,
			enemy_stats.killed, enemy_stats.heavily_wounded, enemy_stats.captured, enemy_stats.evacuated_unknown,
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
