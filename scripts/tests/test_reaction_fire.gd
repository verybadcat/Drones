extends SceneTree
## Reaction fire: what a closing squad pays. User: "Approach should be costly unless the defenders are suppressed." A squad that is not
## moving and sees an opposing squad MOVING within 250 m, in its line of sight, fires at it at six times its usual rate, less as it is
## suppressed (none extra at the pin level); the nearest such squad is the target in preference to a stationary one.
##
## Run: godot --headless --path . --script scripts/tests/test_reaction_fire.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(x: float, y: float = 0.0) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

func make() -> Dictionary:
	GameConfig.set_active_map("voznesensk")
	GameConfig._build_terrain_grid()
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.scenario_elapsed_time = 1000.0
	var rect: Rect2 = GameConfig._building_rects[0]
	var open_point := Vector2.INF
	for dx in [-90.0, 90.0, -140.0, 140.0]:
		var p: Vector2 = Vector2(rect.position.x if dx < 0.0 else rect.end.x, rect.get_center().y) + Vector2(dx, 0.0) * GameConfig.PIXELS_PER_METER
		if GameConfig.get_terrain_type_at(p) == GameConfig.TerrainType.OPEN:
			open_point = p
			break
	# the side away from the building, so that nothing is between the point and what is put out along it
	var away: float = -1.0 if open_point.x < rect.get_center().x else 1.0
	return {"bm": bm, "open": open_point, "away": away}

func unit(c: Dictionary, team: Unit.Team, kind: Unit.Kind, point: Vector2) -> Unit:
	var u: Unit = c.bm._make_unit(team, kind, point)
	if team == Unit.Team.PLAYER:
		c.bm.player_units.append(u)
	else:
		c.bm.enemy_units.append(u)
	u.is_visible = true
	return u

func cleanup(c: Dictionary) -> void:
	c.bm.combat_log.free()
	c.bm.free()

func run() -> void:
	var c := make()
	var bm: BattleManager = c.bm
	check(not is_inf(c.open.x), "Setup: open ground near a building")
	var defender: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, c.open)
	var away: float = c.away
	var closing: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.open + m(200 * away))
	closing.activity = Unit.Activity.MOVING
	var still: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.open + m(0, 100))
	var enemies: Array[Unit] = bm.enemy_units

	# 1. what it reacts to
	check(bm._closing_squad_for(defender, enemies) == closing, "It reacts to the squad that is moving, not the nearer one that is still")
	closing.global_position = c.open + m(300 * away)
	check(bm._closing_squad_for(defender, enemies) == null, "...not beyond 250 m")
	closing.global_position = c.open + m(200 * away)
	closing.activity = Unit.Activity.STATIONARY
	check(bm._closing_squad_for(defender, enemies) == null, "...nor a squad that is not moving")
	closing.activity = Unit.Activity.MOVING

	# 2. the rate: six times, less as it is suppressed, the usual at the pin level
	var usual: float = defender.fire_interval
	defender.fire_timer = 100.0
	defender.suppression = 0.0
	bm._tick_fire(defender, 0.01, 0.6, enemies)
	check(defender.fire_timer < usual / 3.0 and absf(defender.fire_timer - (usual / GameConfig.ASSAULT_REACTION_FIRE_MULTIPLIER - 0.01)) < 0.01, "Unsuppressed: the timer is cut to a sixth at once (%.3f of %.3f)" % [defender.fire_timer, usual])
	defender.fire_timer = 100.0
	defender.suppression = 0.3
	bm._tick_fire(defender, 0.01, 0.6, enemies)
	var half: float = defender.fire_timer
	check(half > usual / GameConfig.ASSAULT_REACTION_FIRE_MULTIPLIER + 0.1 and half < 0.7 * usual, "Half suppressed: in between (%.3f)" % half)
	defender.fire_timer = 100.0
	defender.suppression = GameConfig.SUPPRESSION_PIN_LEVEL
	bm._tick_fire(defender, 0.01, 0.6, enemies)
	check(defender.fire_timer > 0.9 * usual, "Pinned: the usual rate (%.3f)" % defender.fire_timer)
	defender.suppression = 0.0

	# 3. it fires at the closing squad, and the volley costs what a volley costs
	defender.fire_timer = 0.0
	var rounds_before: int = defender.rounds
	var shots_before: int = bm._history_fire_events.size()
	bm._tick_fire(defender, 0.01, 0.6, enemies)
	check(bm._history_fire_events.size() == shots_before + 1 and bm._history_fire_events[shots_before].to == closing.global_position, "It fires at the closing squad, not the one beside it")
	check(rounds_before - defender.rounds == defender.pips * GameConfig.SQUAD_ROUNDS_PER_PERSON_PER_VOLLEY, "...at the usual cost a volley (%d)" % (rounds_before - defender.rounds))
	# a squad that is itself moving does not
	var walker: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, c.open + m(0, -80))
	walker.has_move_target = true
	walker.move_target = walker.position + m(100)
	walker.fire_timer = 100.0
	bm._tick_fire(walker, 0.01, 0.6, enemies)
	check(walker.fire_timer > 90.0, "A squad that is itself moving fires at nothing")

	# 4. the cost of an approach: a squad closing from 230 m on a defender that is not suppressed, and on one that is pinned
	cleanup(c)
	var lost_free := 0.0
	var lost_pinned := 0.0
	var trials := 60
	seed(2024)
	for pinned in [false, true]:
		for t in trials:
			var c2 := make()
			var b2: BattleManager = c2.bm
			var d: Unit = unit(c2, Unit.Team.PLAYER, Unit.Kind.SQUAD, c2.open)
			d.retreat_threshold = 3.0
			var a: Unit = unit(c2, Unit.Team.ENEMY, Unit.Kind.SQUAD, c2.open + m(230 * float(c2.away)))
			a.retreat_threshold = 3.0
			a.move_target = c2.open + m(20 * float(c2.away))
			a.has_move_target = true
			a.move_speed = GameConfig.ENEMY_ADVANCE_SPEED
			a.sought_cover = true
			var start: int = a.pips
			var foes: Array[Unit] = b2.enemy_units
			for step in 80:
				if pinned:
					d.suppression = 1.0
					d.pinned = true
				b2.scenario_elapsed_time += 6.0
				b2._tick_movement(6.0)
				b2._tick_fire(d, 0.1, 6.0, foes)
				if a.global_position.distance_to(d.global_position) <= m(25).x or a.state != Unit.State.ACTIVE:
					break
			if pinned:
				lost_pinned += float(start - a.pips)
			else:
				lost_free += float(start - a.pips)
			cleanup(c2)
	lost_free /= float(trials)
	lost_pinned /= float(trials)
	check(lost_free > 1.2 and lost_free > 2.5 * lost_pinned, "An approach costs an unsuppressed defence more than twice what it costs a pinned one (%.2f against %.2f of 9)" % [lost_free, lost_pinned])

	print("Reaction fire tests: %d failures" % failures)
	quit(1 if failures else 0)
