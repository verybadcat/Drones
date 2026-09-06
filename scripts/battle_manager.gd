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

# Unit (a mortar) -> {"position": Vector2, "time": float} — where and when
# that mortar was last DETECTED firing, via muzzle blast/trajectory rather
# than visual spotting (real counter-battery detection doesn't need to see
# the crew) — see _launch_mortar_shot (records it, every shot, any mortar)
# and _known_friendly_mortar_position (consumes it, as a fallback when the
# mortar isn't currently visible either).
var _last_detected_mortar_fire: Dictionary = {}

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
	_drone_sweep_index = 0

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
func order_general_retreat() -> void:
	if battle_over:
		return
	player_general_retreat_ordered = true
	var known_enemy_positions := _known_enemy_positions(Unit.Team.PLAYER)
	var any_ordered := false
	for unit in player_units:
		if unit.state == Unit.State.ACTIVE:
			unit.order_retreat(known_enemy_positions)
			combat_log.log_ordered_retreat(unit)
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
func _check_enemy_commander_retreat() -> void:
	if enemy_general_retreat_ordered or battle_over:
		return
	if not _enemy_situation_hopeless():
		return
	enemy_general_retreat_ordered = true
	var known_player_positions := _known_enemy_positions(Unit.Team.ENEMY)
	var any_ordered := false
	for unit in enemy_units:
		if unit.kind == Unit.Kind.SQUAD and unit.state == Unit.State.ACTIVE:
			unit.order_retreat(known_player_positions)
			combat_log.log_ordered_retreat(unit)
			any_ordered = true
	if any_ordered:
		var casualty_percent: float = _compute_side_stats(enemy_units).casualty_percent
		combat_log.add_entry("--- Enemy commander orders a general retreat: the attack has failed (%.0f%% casualties) — mortars continue the fire mission ---" % casualty_percent)


## Judged against the WHOLE enemy force's casualties (pips lost across every
## enemy squad and mortar), not any single unit's own threshold — a
## commander sees the overall picture, not just one squad's casualty count.
func _enemy_situation_hopeless() -> bool:
	var stats := _compute_side_stats(enemy_units)
	return stats.casualty_percent / 100.0 >= GameConfig.ENEMY_COMMANDER_RETREAT_THRESHOLD


## Currently-visible enemy positions, from `team`'s point of view — "some
## idea where the enemy is" for the spotter's smarter retreat routing (see
## Unit.order_retreat). Only live-visible units count, matching the rest of
## the game's live-visibility model — not a permanent memory of everywhere
## the enemy has ever been seen.
func _known_enemy_positions(team: Unit.Team) -> Array[Vector2]:
	var opposing: Array[Unit] = enemy_units if team == Unit.Team.PLAYER else player_units
	var positions: Array[Vector2] = []
	for u in opposing:
		if u.state != Unit.State.DESTROYED and u.is_visible:
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
	var hit := CombatResolver.resolve_fire(attacker, target, _ally_positions_for(target), _known_enemy_positions(target.team))
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
			return {"position": u.global_position, "trusted": true}

	var best_pos := Vector2.INF
	var best_time := -INF
	var found := false
	for u in enemy_units:
		if u.kind != Unit.Kind.MORTAR or u.state != Unit.State.ACTIVE:
			continue
		var info: Dictionary = _last_detected_mortar_fire.get(u, {})
		if info.is_empty():
			continue
		if info.time > best_time:
			best_time = info.time
			best_pos = info.position
			found = true
	if not found:
		return {}

	var drone_covering_it := false
	for d in [active_drone, backup_drone]:
		if d != null and d.has_move_target and d.move_target.distance_to(best_pos) < 1.0:
			drone_covering_it = true
			break

	var expiry: float = GameConfig.DRONE_MORTAR_FIRE_LEAD_EXPIRY if drone_covering_it else GameConfig.MORTAR_FIRE_DETECTION_EXPIRY
	if scenario_elapsed_time - best_time > expiry:
		return {}

	return {"position": best_pos, "trusted": drone_covering_it}


## The friendly mirror of _update_enemy_mortar_positioning — closing the
## distance on a known enemy mortar to bring it into range, re-aiming every
## tick there's still a fix and it's still out of range, same as that
## function — but with two things the enemy's simpler version doesn't need
## to weigh: the friendly mortar's own drone/spotter recon means "known"
## comes in trusted and untrusted flavors (see _known_enemy_mortar_lead),
## and unlike the enemy just running down a fix on us, this crew still very
## much does NOT want to be spotted while doing it — see
## _friendly_mortar_hunt_point, which is chosen with that in mind, unlike
## _mortar_advance_point's plain building-avoidance. An untrusted (bare
## fire-detection-only) lead is only worth a modest walk
## (MORTAR_HUNT_UNTRUSTED_MAX_RELOCATE) — real cover is worth more than a
## long march chasing a guess; a trusted one (live, or a drone already
## closing on it) is worth going after regardless of distance, same as the
## enemy's own unconditional chase.
func _update_friendly_mortar_hunting() -> void:
	var lead: Dictionary = _known_enemy_mortar_lead()
	if lead.is_empty():
		return
	var target_pos: Vector2 = lead.position
	var trusted: bool = lead.trusted

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
## much does. Falls back to the first building-clear candidate (what
## _mortar_advance_point would have picked) if none of them are actually
## hidden — some progress toward the shot beats none.
##
## The mortar being hunted itself is excluded from that threat check —
## every candidate sits close to it by construction (that's the whole
## point), so treating it as a threat to hide from would reject every
## angle equally, for no real gain: closing to indirect-fire range doesn't
## require mutual line of sight the way direct fire would, and the actual
## exposure risk this guards against is everyone ELSE near the route, not
## the one target the mortar is already committed to engaging.
func _friendly_mortar_hunt_point(mortar: Unit, target_pos: Vector2) -> Vector2:
	var threats := _known_enemy_positions(mortar.team).filter(func(p): return p.distance_to(target_pos) > 1.0)
	var base_dir: Vector2 = (target_pos - mortar.global_position).normalized()
	var target_distance: float = GameConfig.MORTAR_MAX_RANGE * 0.9 # comfortably in range, not right on the edge
	var fallback: Vector2 = mortar.global_position
	for offset_deg in [0.0, -15.0, 15.0, -30.0, 30.0, -45.0, 45.0]:
		var dir: Vector2 = base_dir.rotated(deg_to_rad(offset_deg))
		var candidate: Vector2 = target_pos - dir * target_distance
		if GameConfig.is_building_at(candidate) or GameConfig.path_crosses_building(mortar.global_position, candidate):
			continue
		if fallback == mortar.global_position:
			fallback = candidate # first building-clear candidate, kept as a last resort
		var hidden := true
		for threat in threats:
			if GameConfig.has_direct_los(candidate, threat):
				hidden = false
				break
		if hidden:
			return candidate
	return fallback


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
	d.drone_battery_charge = charge
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
	d.drone_battery_charge = charge
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
## Once the remaining charge is only just enough to get home (with
## DRONE_RTB_SAFETY_MARGIN worth to spare), it normally hands off search
## duty and turns for home — UNLESS it's currently watching a live,
## engageable enemy mortar (_visible_engageable_mortar) with no backup
## already on-station to take over: in that specific case it sacrifices
## itself instead, deliberately ignoring the safety margin and continuing
## to watch until the battery is genuinely empty (0.0), at which point the
## airframe is lost (_crash_drone) rather than making it home. This is
## re-evaluated every tick, not decided once — if a backup shows up, the
## mortar dies/retreats/leaves range, or the friendly mortar itself is lost
## partway through (making the target no longer engageable), the sacrifice
## is abandoned immediately and it heads home with whatever's left.
func _update_active_drone(scenario_delta: float) -> void:
	var d := active_drone
	d.drone_battery_charge -= scenario_delta / GameConfig.DRONE_FULL_CHARGE_FLIGHT_TIME

	if _drone_should_rtb(d):
		if backup_drone == null:
			var watched: Unit = _visible_engageable_mortar()
			if watched != null and _can_engage_position(watched.global_position):
				if d.drone_battery_charge <= 0.0:
					_crash_drone(d, watched)
					active_drone = null
				# else: sacrifice continues -- fall through to keep watching.
				else:
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
func _update_backup_drone(scenario_delta: float) -> void:
	var d := backup_drone
	d.drone_battery_charge -= scenario_delta / GameConfig.DRONE_FULL_CHARGE_FLIGHT_TIME

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
	var charge_needed_to_get_home: float = (time_needed_home + margin_time) / GameConfig.DRONE_FULL_CHARGE_FLIGHT_TIME
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


## The battery finally runs dry mid-sacrifice — the airframe is lost right
## where it stood, not "shot down" (see _on_drone_state_changed's own
## comment on why this bypasses that signal/log path entirely) but gone all
## the same: no landing, no battery to recover, just a permanent loss
## counted the same way.
func _crash_drone(d: Unit, watched: Unit) -> void:
	combat_log.log_drone_sacrificed(d, watched)
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
		_battery_pool.append(d.drone_battery_charge)
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


## A visible, ACTIVE enemy squad's own target-priority score — see
## GameConfig.TARGET_PRIORITY_SQUAD_MAX/SQUAD_DANGER_RANGE. Danger is
## judged by proximity to the NEAREST active friendly unit of any kind
## (squad, mortar, or the drone team's own ground station) — the closer it
## is to actually being able to fight someone, the more it matters,
## ramping smoothly from 0 at SQUAD_DANGER_RANGE up to the max right at
## contact, rather than a hard in-range/out-of-range step.
func _squad_danger_priority(u: Unit) -> float:
	var nearest_friendly_dist := INF
	for f in player_units:
		if f.state == Unit.State.ACTIVE:
			nearest_friendly_dist = min(nearest_friendly_dist, u.global_position.distance_to(f.global_position))
	if is_inf(nearest_friendly_dist):
		return 0.0
	return GameConfig.TARGET_PRIORITY_SQUAD_MAX * clamp(1.0 - nearest_friendly_dist / GameConfig.SQUAD_DANGER_RANGE, 0.0, 1.0)


## Where the airborne drone flies next, re-evaluated every tick — a genuine
## TARGET PRIORITY comparison (GameConfig.TARGET_PRIORITY_*), not hard-coded
## "mortars always win": whichever candidate scores highest right now wins,
## so a future third target kind only needs its own scoring term, not a
## rewrite of this decision. Candidates, each mapped to an actual position:
## (1) a currently visible, engageable mortar (_visible_engageable_mortar) —
## practically always the winner when one exists, since TARGET_PRIORITY_
## MORTAR sits far above anything a squad can reach; (2) the freshest
## in-range fire-detection lead on any ACTIVE mortar, discounted somewhat
## for being a stale position rather than a live one, but still real
## evidence rather than speculation; (3) the single most dangerous
## currently-visible ACTIVE enemy squad; (4) the ongoing area sweep
## (_drone_sweep_target), valued as the genuine expected value of what it
## might still find — TARGET_PRIORITY_MORTAR times _mortar_existence_
## confidence(). That last term is what lets the drone's default search
## effort shift naturally toward tracking real, visible squads instead of
## an indefinite mortar-shaped sweep once mortar fire hasn't been detected
## in a long while, or every known enemy mortar is confirmed out of
## action — without ever hard-coding either condition directly here.
func _drone_search_target() -> Vector2:
	var best_score := -1.0
	var best_pos := Vector2.INF

	var watched: Unit = _visible_engageable_mortar()
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

	var sweep_score: float = GameConfig.TARGET_PRIORITY_MORTAR * _mortar_existence_confidence()
	if sweep_score > best_score or is_inf(best_pos.x):
		best_pos = _drone_sweep_target()

	return best_pos


## The single currently-visible, still-ACTIVE, in-range enemy mortar worth
## a drone's undivided attention, or null if there isn't one — the exact
## condition _drone_search_target's top tier checks, factored out since the
## backup-drone and self-sacrifice logic (_update_active_drone/
## _update_backup_drone) both need to ask "is there one right now," not
## just "where should THIS drone fly." A RETREATING mortar has already had
## its crew abandon the gun for good (Unit._apply_crew_casualties — it will
## never fire again no matter how well it's watched), and one outside
## GameConfig.MORTAR_MAX_RANGE of the friendly mortar can't be engaged
## right now regardless of visibility — continuing to park on either just
## wastes effort that could instead find (or wait for) a mortar actually
## worth acting on.
func _visible_engageable_mortar() -> Unit:
	for u in enemy_units:
		if u.kind == Unit.Kind.MORTAR and u.state == Unit.State.ACTIVE and u.is_visible and _in_friendly_mortar_range(u.global_position):
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


## No mortar lead at all yet: patrol a methodical boustrophedon across the
## whole contested area (GameConfig.DRONE_SEARCH_WAYPOINTS_M — the map's
## full height, not just the road's own narrow band a mortar would never
## actually sit on), advancing to the next waypoint once close enough
## rather than flying to and sitting at one single fixed point — genuine
## progressive search coverage instead of parking somewhere and stopping.
## Deliberately does NOT aim at the enemy's actual (fixed) mortar
## emplacements — the drone has no more prior knowledge of exactly where
## they are than the player does; it only acts on what it can currently see
## or has recently detected firing (the two checks in _drone_search_target
## above it).
const DRONE_SWEEP_WAYPOINT_RADIUS: float = 500.0 * GameConfig.PIXELS_PER_METER

func _drone_sweep_target() -> Vector2:
	var waypoints: Array[Vector2] = GameConfig.drone_search_waypoints_px()
	if active_drone.global_position.distance_to(waypoints[_drone_sweep_index]) <= DRONE_SWEEP_WAYPOINT_RADIUS:
		_drone_sweep_index = (_drone_sweep_index + 1) % waypoints.size()
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


func _process(delta: float) -> void:
	if battle_over or combat_log == null:
		return

	elapsed_time += delta
	_seconds_since_last_shot += delta

	var scenario_delta: float = delta * _current_time_scale()
	scenario_elapsed_time += scenario_delta

	_tick_movement(scenario_delta)
	_update_spotting(delta)
	_update_enemy_mortar_positioning()
	_update_friendly_mortar_hunting()
	_update_enemy_squad_advance()
	_update_drone_operations(scenario_delta)

	for unit in player_units:
		_tick_fire(unit, delta, scenario_delta, enemy_units)
	for unit in enemy_units:
		_tick_fire(unit, delta, scenario_delta, player_units)

	_update_friendly_mortar_concealment()
	_resolve_pending_counter_battery()
	_resolve_pending_mortar_shots()
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
		if target.state == Unit.State.DESTROYED:
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
		if target.state == Unit.State.DESTROYED or target.state == Unit.State.WITHDRAWN:
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
## march and send it to cover, same reaction as if it had personally been
## shot at (see Unit.take_hit's ENEMY-team branch). Squads already seeking
## cover, retreating, withdrawn, or destroyed are left alone.
##
## All of them break at once here, which is exactly the scenario most
## likely to pile several squads into the same nearest patch of cover —
## `claimed` tracks where each squad processed so far in THIS event is
## already headed, on top of any other active squad's current position, so
## each successive squad prefers a different one (see Unit.seek_cover /
## GameConfig.nearest_cover_point's avoid_positions).
func _alert_enemy_squads() -> void:
	var alerted_any := false
	var claimed: Array[Vector2] = []
	for u in enemy_units:
		if u.kind != Unit.Kind.SQUAD or u.state != Unit.State.ACTIVE or u.sought_cover:
			continue
		u.sought_cover = true
		u.sought_cover_logged = true # logged once, right here, not via _log_hit_consequence
		u.seek_cover(_ally_positions_for(u) + claimed)
		claimed.append(u.move_target)
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


## A bounded step toward the village from `u`'s current position — the next
## leg of an advance-by-rushes, not the whole remaining distance in one go.
func _next_advance_point(u: Unit) -> Vector2:
	var to_village: Vector2 = GameConfig.VILLAGE_CENTER - u.global_position
	if to_village.length() < 10.0:
		return u.global_position # already there
	var rush: float = min(to_village.length(), GameConfig.ENEMY_ADVANCE_RUSH_DISTANCE)
	return u.global_position + to_village.normalized() * rush


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
	if unit.state == Unit.State.DESTROYED:
		combat_log.log_destroyed(unit)
	elif unit.state == Unit.State.RETREATING and was_active_before:
		if unit.kind == Unit.Kind.MORTAR or unit.kind == Unit.Kind.DRONE_TEAM:
			combat_log.log_crew_abandoned(unit)
		else:
			combat_log.log_threshold_retreat(unit)
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
	return candidates[randi() % candidates.size()]


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
	if u.crew_killed > 0 and (u.kind == Unit.Kind.MORTAR or u.kind == Unit.Kind.DRONE_TEAM):
		var what := "gun abandoned" if u.kind == Unit.Kind.MORTAR else "operations abandoned"
		return "%s (%d/%d crew killed, %s)" % [u.display_name(), u.crew_killed, u.crew_size, what]
	return u.display_name()


## Public entry point for UI (see CasualtyDashboard) to read live casualty
## stats for one side — the exact same numbers the AAR report is built
## from, just readable mid-battle instead of only at the end.
func casualty_stats(team: Unit.Team) -> Dictionary:
	return _compute_side_stats(player_units if team == Unit.Team.PLAYER else enemy_units)


## Public read for UI (see CasualtyDashboard) — a snapshot of the drone
## fleet's rotation state, for the same "just as prominent as casualties"
## treatment the mortar already gets. Only meaningful when recon_mode is
## DRONE_TEAM; harmless (all-zero/inactive) otherwise.
func drone_fleet_status() -> Dictionary:
	return {
		"team_active": drone_team != null and drone_team.state == Unit.State.ACTIVE,
		"team_state": drone_team.state if drone_team else Unit.State.DESTROYED,
		"team_crew_killed": drone_team.crew_killed if drone_team else 0,
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


func _compute_side_stats(units: Array[Unit]) -> Dictionary:
	var pips_total := 0
	var pips_lost := 0
	var destroyed: PackedStringArray = []
	var withdrawn: PackedStringArray = []
	var still_retreating: PackedStringArray = []
	for u in units:
		# A drone is equipment, not personnel — losing one doesn't hurt the
		# 3-person crew, so it never counts toward the human casualty tally
		# (it still shows up below if destroyed, just not in the pip count).
		if u.kind != Unit.Kind.DRONE:
			pips_total += u.max_pips
			pips_lost += (u.max_pips - u.pips)
		match u.state:
			Unit.State.DESTROYED:
				if u.kind == Unit.Kind.MORTAR or u.kind == Unit.Kind.DRONE_TEAM:
					destroyed.append("%s (%d/%d crew killed)" % [u.display_name(), u.crew_killed, u.crew_size])
				else:
					destroyed.append(u.display_name())
			Unit.State.WITHDRAWN:
				withdrawn.append(_crew_survivor_label(u))
			Unit.State.RETREATING:
				still_retreating.append(_crew_survivor_label(u))
	var casualty_percent: float = (float(pips_lost) / float(pips_total) * 100.0) if pips_total > 0 else 0.0
	return {
		"pips_total": pips_total,
		"pips_lost": pips_lost,
		"casualty_percent": casualty_percent,
		"destroyed": destroyed,
		"withdrawn": withdrawn,
		"still_retreating": still_retreating,
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
	var enemy_stats := _compute_side_stats(enemy_units)
	var held: bool = _has_active_units(player_units)
	var exchange_ratio: float = float(enemy_stats.pips_lost) / float(max(player_stats.pips_lost, 1))

	var verdict: String
	if held and exchange_ratio >= 1.5:
		verdict = "SUCCESSFUL DEFENSE"
	elif held:
		verdict = "PYRRHIC DEFENSE"
	elif exchange_ratio >= 2.0:
		verdict = "TACTICAL WITHDRAWAL — favorable exchange"
	else:
		verdict = "DEFEAT"

	var lines: PackedStringArray = []
	lines.append("=== AFTER-ACTION REPORT ===")
	lines.append("Verdict: %s" % verdict)
	lines.append("Village held: %s" % ("YES" if held else "NO"))
	var tactical_minutes: int = int(scenario_elapsed_time / 60.0)
	lines.append("Time elapsed: %dh %02dm (0600 to %s)" % [tactical_minutes / 60, tactical_minutes % 60, clock_string().substr(0, 5)])
	lines.append("Player casualties: %d/%d personnel (%.0f%%)" % [player_stats.pips_lost, player_stats.pips_total, player_stats.casualty_percent])
	lines.append("Enemy casualties: %d/%d personnel (%.0f%%)" % [enemy_stats.pips_lost, enemy_stats.pips_total, enemy_stats.casualty_percent])
	lines.append("Exchange ratio (enemy : player personnel lost): %.2f : 1" % exchange_ratio)
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

	var report_text := "\n".join(lines)
	combat_log.log_battle_end(report_text)
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
