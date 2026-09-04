extends Node2D
class_name BattleManager
## Runs one battle: spawns units per doctrine, advances the enemy, resolves
## spotting and fire each tick, and produces an after-action report once both
## sides are done fighting. Enemy doctrine is fixed/hardcoded here —
## deliberately NOT a mirrored doctrine-interpreting engine (see design doc).
##
## No routine per-shot fire log (see CombatLog) — the log only records
## moments that change the picture.

signal battle_ended(report_text: String)

var player_units: Array[Unit] = []
var enemy_units: Array[Unit] = []
var combat_log: CombatLog
var elapsed_time: float = 0.0
var battle_over: bool = false


func start_battle(doctrine: Dictionary, p_combat_log: CombatLog) -> void:
	combat_log = p_combat_log
	elapsed_time = 0.0
	battle_over = false

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


func _spawn_enemy_units() -> void:
	for start_y in GameConfig.ENEMY_SQUAD_START_Y:
		var squad := _make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(GameConfig.ENEMY_SPAWN_X, start_y))
		squad.retreat_threshold = GameConfig.ENEMY_RETREAT_THRESHOLD
		squad.concern_threshold = GameConfig.ENEMY_CONCERN_THRESHOLD
		squad.advance_stop_x = GameConfig.ENEMY_ADVANCE_STOP_X
		squad.move_speed = GameConfig.ENEMY_ADVANCE_SPEED
		squad.activity = Unit.Activity.MOVING
		_set_retreat_profile(squad, Unit.Team.ENEMY)
		enemy_units.append(squad)

	var em := _make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, GameConfig.ENEMY_MORTAR_POS)
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

	_check_battle_end()


## Enemy squads advance on the village until they reach engagement range,
## then hold. Any unit ordered to retreat (automatically, past its casualty
## threshold, or by the player's general order) pulls back toward its own
## side's safe line and is marked WITHDRAWN on arrival — no longer part of
## the fight, but its casualties still count in the AAR report.
func _tick_movement(delta: float) -> void:
	for unit in enemy_units:
		if unit.kind == Unit.Kind.SQUAD and unit.state == Unit.State.ACTIVE:
			if unit.position.x > unit.advance_stop_x:
				unit.position.x -= unit.move_speed * delta
				unit.activity = Unit.Activity.MOVING
			else:
				unit.activity = Unit.Activity.STATIONARY

	for unit in player_units + enemy_units:
		if unit.state == Unit.State.RETREATING:
			_step_retreat(unit, delta)


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
	if unit.state == Unit.State.DESTROYED:
		return

	# Counter-battery accrual for a mortar holding position too long
	# (only applies in "hold position" mode, not shoot-and-scoot).
	if unit.kind == Unit.Kind.MORTAR and not unit.shoot_and_scoot \
			and unit.state == Unit.State.ACTIVE \
			and unit.shots_since_relocate > unit.counter_battery_shot_threshold:
		unit.counter_battery_timer += delta
		while unit.counter_battery_timer >= 1.0:
			unit.counter_battery_timer -= 1.0
			if randf() < unit.counter_battery_tick_chance:
				unit.take_hit()
				combat_log.log_counter_battery(unit)
				_log_hit_consequence(unit, true)

	if unit.state != Unit.State.ACTIVE:
		return # retreating units stop firing but remain on the field

	unit.fire_timer -= delta
	if unit.fire_timer > 0.0:
		return

	var target := _pick_target(enemies)
	if target == null:
		unit.fire_timer = unit.fire_interval
		return

	if not unit.is_spotted:
		unit.is_spotted = true
		unit.queue_redraw()
		combat_log.log_revealed_by_fire(unit)

	var target_was_active := target.state == Unit.State.ACTIVE
	CombatResolver.resolve_fire(unit, target)
	_log_hit_consequence(target, target_was_active)

	if unit.kind == Unit.Kind.MORTAR:
		if unit.shoot_and_scoot:
			unit.shots_since_relocate = 0
			combat_log.log_relocate(unit)
			unit.fire_timer = unit.relocate_cooldown + unit.reload_time
		else:
			unit.shots_since_relocate += 1
			unit.fire_timer = unit.reload_time
	else:
		unit.fire_timer = unit.fire_interval


func _log_hit_consequence(unit: Unit, was_active_before: bool) -> void:
	if unit.state == Unit.State.DESTROYED:
		combat_log.log_destroyed(unit)
	elif unit.state == Unit.State.RETREATING and was_active_before:
		combat_log.log_threshold_retreat(unit)
	if unit.reported_issue and not unit.reported_issue_logged:
		unit.reported_issue_logged = true
		combat_log.log_reports_issue(unit)


func _pick_target(enemies: Array[Unit]) -> Unit:
	var candidates: Array[Unit] = []
	for e in enemies:
		if e.is_targetable():
			candidates.append(e)
	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]


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
