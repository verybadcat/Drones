extends SceneTree
## Suppression and posture (docs/designs/posture-and-suppression.md, stage D). Suppression is what keeps heads down: a pinned squad is
## down and stays down until it is released; one told to move hesitates once per spell of being pinned, and one that becomes pinned
## while moving halts; a retreat is not stopped; a pinned squad can hardly engage a man moving in the open, which is what covering fire is
## for; and a mortar values pinning a squad that is firing on its own side's squads, unless it is being shelled already.
##
## Run: godot --headless --path . --script scripts/tests/test_suppression_posture.gd
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
	return {"bm": bm, "open": m(-5000, -5000)}

func unit(c: Dictionary, team: Unit.Team, kind: Unit.Kind, point: Vector2) -> Unit:
	var u: Unit = c.bm._make_unit(team, kind, point)
	if team == Unit.Team.PLAYER:
		c.bm.player_units.append(u)
	else:
		c.bm.enemy_units.append(u)
	return u

func cleanup(c: Dictionary) -> void:
	c.bm.combat_log.free()
	c.bm.free()

func order_move(u: Unit, metres: float) -> void:
	u.move_target = u.position + m(metres)
	u.has_move_target = true
	u.move_speed = 2.0 * GameConfig.PIXELS_PER_METER

func run() -> void:
	# 1. pinned is down, and stays down past the stay-down time; released, it gets up once the fire has been away that long
	var c := make()
	var bm: BattleManager = c.bm
	var squad: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, c.open)
	bm._note_fire_arrival(squad)
	squad.suppression = 0.8
	squad.pinned = true
	bm.scenario_elapsed_time += GameConfig.GO_TO_GROUND_REACTION_S + 1.0
	bm._update_postures()
	check(squad.posture() == Unit.Posture.PRONE, "A pinned squad is down")
	bm.scenario_elapsed_time += GameConfig.STAY_DOWN_AFTER_FIRE_S * 3.0
	bm._update_postures()
	check(squad.posture() == Unit.Posture.PRONE, "...and still down long after the stay-down time, while it is pinned")
	squad.suppression = 0.2
	bm._update_suppression(0.1)
	check(not squad.pinned and not squad.pinned_hesitated, "Released")
	bm._update_postures()
	check(squad.posture() == Unit.Posture.STANDING, "...and, with the last round long ago, it is upright again")

	# 2. a squad told to move while pinned hesitates PINNED_HESITATION_S, once per spell; a squad that is moving when pinned halts
	var walker: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, c.open + m(0, 300))
	order_move(walker, 300.0)
	bm._tick_movement(0.5)
	check(walker.activity == Unit.Activity.MOVING, "Setup: an unpinned squad is under way")
	var where: Vector2 = walker.position
	walker.pinned = true
	walker.suppression = 0.8
	bm._tick_movement(0.5)
	check(walker.position == where and walker.activity == Unit.Activity.STATIONARY, "A squad that becomes pinned while moving halts at once")
	for i in 10:
		bm._tick_movement(0.5)
	check(walker.position == where, "...and holds for the hesitation (5.5 s of 6)")
	for i in 3:
		bm._tick_movement(0.5)
	check(walker.position != where and walker.pinned_hesitated, "...then goes on")
	# a fresh order in the same spell: no second hesitation
	walker.has_move_target = false
	walker.activity = Unit.Activity.STATIONARY
	order_move(walker, 100.0)
	var again: Vector2 = walker.position
	bm._tick_movement(0.5)
	check(walker.position != again, "In the same spell of being pinned it does not hesitate twice")
	# released and pinned again: it does
	walker.suppression = 0.2
	bm._update_suppression(0.1)
	check(not walker.pinned and not walker.pinned_hesitated, "Released: the hesitation is spent no more")
	walker.has_move_target = false
	walker.activity = Unit.Activity.STATIONARY
	walker.pinned = true
	walker.suppression = 0.8
	order_move(walker, 100.0)
	again = walker.position
	bm._tick_movement(0.5)
	check(walker.position == again, "Pinned afresh, it hesitates again")

	# 3. a retreat is not stopped for being pinned
	var runner: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, c.open + m(0, 700))
	runner.state = Unit.State.RETREATING
	runner.pinned = true
	runner.suppression = 0.9
	order_move(runner, 200.0)
	var start_run: Vector2 = runner.position
	bm._tick_movement(0.5)
	check(runner.position != start_run, "A pinned squad that is retreating keeps going")

	# 4. covering fire: a pinned shooter hits a moving man at half the chance; a stationary one as any suppressed shooter does
	var shooter: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.open + m(0, 1200))
	var mark: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, c.open + m(250, 1200))
	var still_free: float = CombatResolver.hit_probability(shooter, mark)
	mark.activity = Unit.Activity.MOVING
	var moving_free: float = CombatResolver.hit_probability(shooter, mark)
	shooter.pinned = true
	shooter.suppression = 0.7
	var accuracy: float = 1.0 - GameConfig.SUPPRESSION_MAX_ACCURACY_LOSS * 0.7
	var moving_pinned: float = CombatResolver.hit_probability(shooter, mark)
	mark.activity = Unit.Activity.STATIONARY
	var still_pinned: float = CombatResolver.hit_probability(shooter, mark)
	check(absf(still_pinned / still_free - accuracy) < 0.01, "Against a still target a suppressed shooter loses accuracy only (%.3f of %.3f)" % [still_pinned, still_free])
	check(moving_pinned / moving_free < 0.6 * accuracy and moving_pinned > 0.0, "...against a moving one, pinned, about half again (%.3f of %.3f)" % [moving_pinned, moving_free])
	shooter.pinned = false
	mark.activity = Unit.Activity.MOVING
	check(absf(CombatResolver.hit_probability(shooter, mark) / moving_free - accuracy) < 0.01, "A suppressed shooter that is not pinned loses only accuracy against a moving man")
	cleanup(c)

	# 5. the mortar values pinning a squad that is firing on its own side's squads, not one already being shelled
	var c2 := make()
	var gun: Unit = unit(c2, Unit.Team.PLAYER, Unit.Kind.MORTAR, c2.open)
	var firer: Unit = unit(c2, Unit.Team.ENEMY, Unit.Kind.SQUAD, c2.open + m(1500, 0))
	var quiet: Unit = unit(c2, Unit.Team.ENEMY, Unit.Kind.SQUAD, c2.open + m(1500, 400))
	var ours: Unit = unit(c2, Unit.Team.PLAYER, Unit.Kind.SQUAD, c2.open + m(1200, 0))
	firer.is_visible = true
	quiet.is_visible = true
	var b: BattleManager = c2.bm
	var base_firer: float = b._enemy_target_value(gun, firer)
	var base_quiet: float = b._enemy_target_value(gun, quiet)
	b._record_direct_fire(firer, ours)
	var engaged_value: float = b._enemy_target_value(gun, firer)
	check(engaged_value - base_firer > 1.0 and engaged_value - base_firer < 6.0, "A squad firing on one of ours is worth more to pin (%.2f against %.2f)" % [engaged_value, base_firer])
	check(absf(b._enemy_target_value(gun, quiet) - base_quiet) < 0.01, "...one that is not, no more")
	b._last_shelled_at[firer] = b.scenario_elapsed_time - 10.0
	check(absf(b._enemy_target_value(gun, firer) - base_firer) < 0.01, "...and no more once it is being shelled already")
	b._last_shelled_at[firer] = b.scenario_elapsed_time - GameConfig.MORTAR_SUPPRESSION_RECENT_FIRE_S - 1.0
	check(absf((b._enemy_target_value(gun, firer) - base_firer) - (engaged_value - base_firer)) < 0.01, "...but is again when the shelling is a while ago")
	b.scenario_elapsed_time += GameConfig.CROSSFIRE_MEMORY_S + 1.0
	check(absf(b._enemy_target_value(gun, firer) - base_firer) < 0.01, "...and not when it has stopped firing")
	cleanup(c2)

	print("Suppression and posture tests: %d failures" % failures)
	quit(1 if failures else 0)
