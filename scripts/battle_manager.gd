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

var player_units: Array[Unit] = []
var enemy_units: Array[Unit] = []
var combat_log: CombatLog
var elapsed_time: float = 0.0
var battle_over: bool = false
var _fire_flashes: Array[Dictionary] = []


func start_battle(doctrine: Dictionary, p_combat_log: CombatLog) -> void:
	combat_log = p_combat_log
	elapsed_time = 0.0
	battle_over = false
	_fire_flashes.clear()

	for unit in player_units + enemy_units:
		unit.queue_free()
	player_units.clear()
	enemy_units.clear()

	_spawn_player_units(doctrine)
	_spawn_enemy_units()

	queue_redraw()


func _spawn_player_units(doctrine: Dictionary) -> void:
	for squad_doctrine in doctrine.squads:
		var squad := _make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, squad_doctrine.position)
		squad.retreat_threshold = squad_doctrine.retreat_threshold
		_set_retreat_profile(squad, Unit.Team.PLAYER)
		player_units.append(squad)

	var m1 := _make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, doctrine.mortar.position)
	m1.shoot_and_scoot = doctrine.mortar.shoot_and_scoot
	m1.relocate_cooldown = doctrine.mortar.relocate_cooldown
	_set_retreat_profile(m1, Unit.Team.PLAYER)
	player_units.append(m1)

	var spotter := _make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, doctrine.spotter.position)
	_set_retreat_profile(spotter, Unit.Team.PLAYER)
	player_units.append(spotter)


func _spawn_enemy_units() -> void:
	for i in GameConfig.ENEMY_SQUAD_START_Y.size():
		var start_y: float = GameConfig.ENEMY_SQUAD_START_Y[i]
		var squad := _make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(GameConfig.ENEMY_SPAWN_X, start_y))
		squad.retreat_threshold = GameConfig.ENEMY_RETREAT_THRESHOLD
		squad.concern_threshold = GameConfig.ENEMY_CONCERN_THRESHOLD
		squad.move_speed = GameConfig.ENEMY_ADVANCE_SPEED
		# Spread the road-march waypoints out well so all 6 don't converge on
		# nearly the same point (and end up bunched again once they scatter).
		var offset := Vector2(randf_range(-60.0, 60.0), randf_range(-120.0, 120.0))
		squad.move_target = GameConfig.ENEMY_ROAD_RALLY_POINT + offset
		squad.has_move_target = true
		squad.activity = Unit.Activity.MOVING
		_set_retreat_profile(squad, Unit.Team.ENEMY)
		enemy_units.append(squad)

	for mortar_pos in GameConfig.ENEMY_MORTAR_POSITIONS:
		var em := _make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, mortar_pos)
		em.shoot_and_scoot = false
		em.relocate_cooldown = 5.0
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
	var any_ordered := false
	for unit in player_units:
		if unit.state == Unit.State.ACTIVE:
			unit.order_retreat()
			combat_log.log_ordered_retreat(unit)
			any_ordered = true
	if any_ordered:
		combat_log.add_entry("--- General retreat ordered ---")


func _process(delta: float) -> void:
	if battle_over or combat_log == null:
		return

	elapsed_time += delta

	_tick_movement(delta)
	_update_spotting(delta)

	for unit in player_units:
		_tick_fire(unit, delta, enemy_units)
	for unit in enemy_units:
		_tick_fire(unit, delta, player_units)

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
func _tick_movement(delta: float) -> void:
	for unit in player_units + enemy_units:
		if unit.state == Unit.State.RETREATING:
			if unit.has_move_target:
				_step_toward_target(unit, delta)
			else:
				_step_retreat(unit, delta)
		elif unit.state == Unit.State.ACTIVE and unit.has_move_target:
			_step_toward_target(unit, delta)


func _step_toward_target(unit: Unit, delta: float) -> void:
	unit.activity = Unit.Activity.MOVING
	var to_target: Vector2 = unit.move_target - unit.position
	var dist: float = to_target.length()
	var step: float = unit.move_speed * delta
	if step >= dist or dist <= Unit.MOVE_ARRIVE_RADIUS:
		unit.position = unit.move_target
		unit.has_move_target = false
		unit.activity = Unit.Activity.STATIONARY
	else:
		unit.position += to_target.normalized() * step


func _step_retreat(unit: Unit, delta: float) -> void:
	unit.activity = Unit.Activity.MOVING
	var reached: bool
	if unit.team == Unit.Team.PLAYER:
		unit.position.x -= unit.retreat_speed * delta
		reached = unit.position.x <= unit.retreat_target_x
	else:
		unit.position.x += unit.retreat_speed * delta
		reached = unit.position.x >= unit.retreat_target_x

	if reached:
		unit.position.x = unit.retreat_target_x
		unit.state = Unit.State.WITHDRAWN
		unit.queue_redraw()
		combat_log.log_withdrawn(unit)


func _update_spotting(delta: float) -> void:
	_spot_side(player_units, enemy_units, delta)
	_spot_side(enemy_units, player_units, delta)


func _spot_side(spotters: Array[Unit], targets: Array[Unit], delta: float) -> void:
	for target in targets:
		if target.state == Unit.State.DESTROYED or target.is_spotted:
			continue
		for spotter in spotters:
			if spotter.state != Unit.State.ACTIVE:
				continue
			if CombatResolver.roll_spot(spotter, target, delta):
				target.is_spotted = true
				target.queue_redraw()
				combat_log.log_spotted(target)
				break


func _tick_fire(unit: Unit, delta: float, enemies: Array[Unit]) -> void:
	if unit.kind == Unit.Kind.SPOTTER:
		return # the spotter never fires — it only extends detection (see roll_spot)
	if unit.state != Unit.State.ACTIVE:
		return # destroyed/withdrawn/retreating units don't fire

	unit.fire_timer -= delta
	if unit.fire_timer > 0.0:
		return

	var target := _pick_target(unit, enemies)
	if target == null:
		unit.fire_timer = unit.fire_interval
		return

	# A squad's muzzle flash gives it away; a mortar firing on spotter-relayed
	# information does not — see CombatResolver / GameConfig for the
	# counter-battery consequence of firing instead.
	if unit.kind == Unit.Kind.SQUAD and not unit.is_spotted:
		unit.is_spotted = true
		unit.queue_redraw()
		combat_log.log_revealed_by_fire(unit)

	var target_was_active := target.state == Unit.State.ACTIVE
	CombatResolver.resolve_fire(unit, target)
	_fire_flashes.append({"from": unit.global_position, "to": target.global_position, "team": unit.team, "time": elapsed_time})
	_log_hit_consequence(target, target_was_active)

	if unit.kind == Unit.Kind.MORTAR:
		_resolve_mortar_counter_battery(unit)
		if unit.shoot_and_scoot:
			combat_log.log_relocate(unit)
			_hop_mortar(unit)
			unit.fire_timer = unit.relocate_cooldown + unit.reload_time
		else:
			unit.fire_timer = unit.reload_time
	else:
		unit.fire_timer = unit.fire_interval


## Firing gives the OPPOSING mortar(s) — and only the opposing mortar, not
## every enemy unit — a chance to fire back. Shoot-and-scoot keeps that
## chance low; holding position in one spot raises it a lot. Mortars are a
## high-priority target for each other.
func _resolve_mortar_counter_battery(firing_mortar: Unit) -> void:
	var opposing: Array[Unit] = player_units if firing_mortar.team == Unit.Team.ENEMY else enemy_units
	var chance: float = GameConfig.MORTAR_COUNTER_BATTERY_SCOOT_CHANCE if firing_mortar.shoot_and_scoot else GameConfig.MORTAR_COUNTER_BATTERY_HOLD_CHANCE
	for m in opposing:
		if m.kind != Unit.Kind.MORTAR or m.state != Unit.State.ACTIVE:
			continue
		if randf() < chance:
			var was_active := firing_mortar.state == Unit.State.ACTIVE
			firing_mortar.take_hit(true)
			combat_log.log_counter_battery(firing_mortar)
			_log_hit_consequence(firing_mortar, was_active)


## Shoot-and-scoot is now visible, not just a cooldown number — the mortar
## actually hops a short, random distance after firing.
func _hop_mortar(mortar: Unit) -> void:
	var hop := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	if hop.length() < 0.01:
		hop = Vector2.RIGHT
	mortar.position += hop.normalized() * GameConfig.MORTAR_SCOOT_HOP_DISTANCE
	mortar.position.x = clamp(mortar.position.x, 20.0, 1340.0)
	mortar.position.y = clamp(mortar.position.y, 20.0, 680.0)
	mortar.queue_redraw()


func _log_hit_consequence(unit: Unit, was_active_before: bool) -> void:
	if unit.state == Unit.State.DESTROYED:
		combat_log.log_destroyed(unit)
	elif unit.state == Unit.State.RETREATING and was_active_before:
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


## A SQUAD can only fire at a target within its own engagement range — direct
## fire needs the firer's own eyes on it. A MORTAR has no such limit: it
## fires on anything any friendly unit has spotted, anywhere on the map,
## per the design doc's spotter-relayed indirect fire.
## A SQUAD can only fire at a target within its own engagement range AND
## with actual line of sight — a building between attacker and target blocks
## it outright, not just "harder to hit" (that's what the cover multiplier
## is for). A MORTAR has neither restriction: it fires on anything any
## friendly unit has spotted, anywhere, per the design doc's spotter-relayed
## indirect fire.
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
		candidates.append(e)
	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]


func _prune_fire_flashes() -> void:
	_fire_flashes = _fire_flashes.filter(func(f): return elapsed_time - f.time <= FLASH_DURATION)


func _check_battle_end() -> void:
	if _all_done_fighting(player_units) or _all_done_fighting(enemy_units) \
			or elapsed_time >= GameConfig.BATTLE_TIME_LIMIT:
		_end_battle()


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
					destroyed.append("%s (est. %d%% crew casualties)" % [u.display_name(), u.crew_casualty_percent])
				else:
					destroyed.append(u.display_name())
			Unit.State.WITHDRAWN:
				withdrawn.append(u.display_name())
			Unit.State.RETREATING:
				still_retreating.append(u.display_name())
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
	lines.append("Time elapsed: %ds" % int(elapsed_time))
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
		draw_line(flash.from, flash.to, color, 2.0)
		draw_circle(flash.from, 5.0, Color(1.0, 1.0, 0.6, alpha))
