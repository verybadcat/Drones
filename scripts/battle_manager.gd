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


## Picks how fast the tactical clock runs this tick — realistic pace the
## moment there's something worth watching closely (live contact, which
## always wins even during a general withdrawal — a fighting retreat is
## still worth watching closely), faster once a general withdrawal is under
## way and nobody's currently in contact, fastest of all when there's
## nothing happening at all yet (e.g. the long road march before first
## contact, or a single unit's own quiet, isolated retreat) — see
## GameConfig's TIME_SCALE_* constants for the reasoning.
func _current_time_scale() -> float:
	if _any_contact():
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
## personally hit (Unit._apply_mortar_casualties) — this just means the
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
	_update_enemy_squad_advance()

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
	if unit.kind == Unit.Kind.SPOTTER:
		return # the spotter never fires — it only extends detection (see roll_spot)
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
## squad." A target on a steady, predictable course (Unit.movement_predictable
## — the enemy's road march) can be correctly LED: aim at where it's
## heading, not where it stands, using its current speed/direction
## extrapolated across the shell's whole flight time. Anything else
## (stationary, or moving erratically — diving for cover, retreating) can
## only be aimed at its current position; if it's still there 40 seconds
## later the shot lands true, but a target that changes course mid-flight —
## breaking from the march for cover, changing direction — can still evade
## a shot that started out well-aimed. See _resolve_pending_mortar_shots.
func _mortar_aim_point(target: Unit) -> Vector2:
	if target.movement_predictable and target.activity == Unit.Activity.MOVING and target.has_move_target:
		var to_target: Vector2 = target.move_target - target.global_position
		if to_target.length() > 0.01:
			var velocity: Vector2 = to_target.normalized() * target.move_speed
			return target.global_position + velocity * GameConfig.MORTAR_FLIGHT_TIME
	return target.global_position


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
		var target: Unit = shot.target
		if target.state == Unit.State.DESTROYED or target.state == Unit.State.WITHDRAWN:
			continue # nothing left there to hit

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
		if unit.kind == Unit.Kind.MORTAR:
			combat_log.log_mortar_abandoned(unit)
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
## Unit._apply_mortar_casualties), so a RETREATING mortar is just fleeing
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
func _anyone_moving() -> bool:
	for u in player_units + enemy_units:
		if u.state == Unit.State.RETREATING:
			return true
		if u.state == Unit.State.ACTIVE and u.has_move_target:
			return true
	return false


## True once nobody in `units` is still ACTIVE or mid-RETREAT — everyone left
## is either WITHDRAWN or DESTROYED. Battle end waits for this so a retreat
## actually finishes before the report is generated.
func _all_done_fighting(units: Array[Unit]) -> bool:
	for u in units:
		if u.state == Unit.State.ACTIVE or u.state == Unit.State.RETREATING:
			return false
	return true


func _has_active_units(units: Array[Unit]) -> bool:
	for u in units:
		if u.state == Unit.State.ACTIVE:
			return true
	return false


## Display name for a WITHDRAWN/RETREATING unit in the AAR — a mortar whose
## crew took casualties before abandoning the gun gets that noted, since
## "withdrew safely" alone would hide that its crew was hurt and its gun lost.
func _mortar_survivor_label(u: Unit) -> String:
	if u.kind == Unit.Kind.MORTAR and u.crew_killed > 0:
		return "%s (%d/%d crew killed, gun abandoned)" % [u.display_name(), u.crew_killed, u.crew_size]
	return u.display_name()


## Public entry point for UI (see CasualtyDashboard) to read live casualty
## stats for one side — the exact same numbers the AAR report is built
## from, just readable mid-battle instead of only at the end.
func casualty_stats(team: Unit.Team) -> Dictionary:
	return _compute_side_stats(player_units if team == Unit.Team.PLAYER else enemy_units)


func _compute_side_stats(units: Array[Unit]) -> Dictionary:
	var pips_total := 0
	var pips_lost := 0
	var destroyed: PackedStringArray = []
	var withdrawn: PackedStringArray = []
	var still_retreating: PackedStringArray = []
	for u in units:
		pips_total += u.max_pips
		pips_lost += (u.max_pips - u.pips)
		match u.state:
			Unit.State.DESTROYED:
				if u.kind == Unit.Kind.MORTAR:
					destroyed.append("%s (%d/%d crew killed)" % [u.display_name(), u.crew_killed, u.crew_size])
				else:
					destroyed.append(u.display_name())
			Unit.State.WITHDRAWN:
				withdrawn.append(_mortar_survivor_label(u))
			Unit.State.RETREATING:
				still_retreating.append(_mortar_survivor_label(u))
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
	lines.append("Player casualties: %d/%d pips (%.0f%%)" % [player_stats.pips_lost, player_stats.pips_total, player_stats.casualty_percent])
	lines.append("Enemy casualties: %d/%d pips (%.0f%%)" % [enemy_stats.pips_lost, enemy_stats.pips_total, enemy_stats.casualty_percent])
	lines.append("Exchange ratio (enemy : player pips lost): %.2f : 1" % exchange_ratio)
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
