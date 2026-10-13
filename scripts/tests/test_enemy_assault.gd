extends SceneTree
## Closing to assault range (GameConfig.ASSAULT_*). User: "Closing range is definitely a good idea", "closing to assault range has to
## be much easier when you are on multiple sides of the same enemy", and "Assaults should never be made without a numerical advantage.
## They should also usually not be made without a surround advantage." An enemy squad that knows of a player squad within 450 m rolls once
## a minute to close to 20 m of it: never unless its side has twice the people near the target, a tenth of the chance below two opposite
## sides held, many times larger when its side has put fire on that squad or that squad has gone silent, and many times larger again the
## more sides of it its side holds. Only what the attacking side itself knows. It cannot fire while it moves.
##
## Run: godot --headless --path . --script scripts/tests/test_enemy_assault.gd
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
	# open ground ON the map (clamp_to_operating_area would otherwise move a destination): just outside the first building
	var rect: Rect2 = GameConfig._building_rects[0]
	var open_point := Vector2.INF
	for dx in [-90.0, 90.0, -140.0, 140.0]:
		var p: Vector2 = Vector2(rect.position.x if dx < 0.0 else rect.end.x, rect.get_center().y) + Vector2(dx, 0.0) * GameConfig.PIXELS_PER_METER
		if GameConfig.get_terrain_type_at(p) == GameConfig.TerrainType.OPEN:
			open_point = p
			break
	var away: float = -1.0 if open_point.x < rect.get_center().x else 1.0 # the side away from the building, nothing between
	return {"bm": bm, "open": open_point, "away": away}

func unit(c: Dictionary, team: Unit.Team, kind: Unit.Kind, point: Vector2) -> Unit:
	var u: Unit = c.bm._make_unit(team, kind, point)
	if team == Unit.Team.PLAYER:
		c.bm.player_units.append(u)
	else:
		c.bm.enemy_units.append(u)
	return u

func known(t: Unit) -> void:
	t.enemy_has_been_sighted = true
	t.enemy_known_position = t.global_position
	t.enemy_known_state = Unit.State.ACTIVE
	t.enemy_known_pips = t.pips

func cleanup(c: Dictionary) -> void:
	c.bm.combat_log.free()
	c.bm.free()

func run() -> void:
	var c := make()
	var bm: BattleManager = c.bm
	var target: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, c.open)
	known(target)
	var east: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.open + m(300, 0))
	east.sought_cover = true

	# 1. the chance, by what the attacking side has and knows
	var base: float = GameConfig.ASSAULT_BASE_CHANCE_PER_MIN
	var lone: float = bm._assault_chance_per_minute(east, target)
	check(absf(lone - base * GameConfig.ASSAULT_UNSURROUNDED_FACTOR) < 0.0001, "From one side, nothing put on it, not silent: the base chance, a tenth of it for want of a surround (%.4f)" % lone)
	var west: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.open + m(-300, 0))
	var two: float = bm._assault_chance_per_minute(east, target)
	check(two > 2.0 * base and two < 3.5 * base and two > 20.0 * lone, "On two opposite sides: about three times the base, and the surround penalty is gone (%.3f against %.3f)" % [two, base])
	var north: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.open + m(0, -300))
	var south: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.open + m(0, 300))
	var four: float = bm._assault_chance_per_minute(east, target)
	check(four > 3.5 * base and four <= 4.2 * base and four > two, "On four sides: about four times, more than on two (%.3f)" % four)
	# fire put on it, and its silence
	bm._volleys_at[target] = [bm.scenario_elapsed_time - 30.0, bm.scenario_elapsed_time - 10.0]
	check(bm._assault_chance_per_minute(east, target) > 3.5 * four, "Two volleys from its side in the last two minutes: about four times again (%.3f)" % bm._assault_chance_per_minute(east, target))
	bm._volleys_at.erase(target)
	target.last_volley_at = bm.scenario_elapsed_time - 60.0
	check(absf(bm._assault_chance_per_minute(east, target) - four) < 0.0001, "A squad that fired a minute ago is not silent")
	target.last_volley_at = bm.scenario_elapsed_time - 240.0
	check(bm._assault_chance_per_minute(east, target) > 3.5 * four, "One that has not fired for four minutes, having been in contact: about four times (%.3f)" % bm._assault_chance_per_minute(east, target))
	bm._volleys_at[target] = [bm.scenario_elapsed_time - 30.0, bm.scenario_elapsed_time - 10.0]
	check(bm._assault_chance_per_minute(east, target) <= GameConfig.ASSAULT_MAX_CHANCE_PER_MIN + 0.0001, "...and never more than the cap")
	bm._volleys_at.erase(target)
	target.last_volley_at = -1.0e9

	# 2. the numbers rule: never without a numerical advantage; with it, on two sides, it closes in the end, to inside grenade range
	for e in [north, south]:
		e.state = Unit.State.WITHDRAWN
	east.global_position = c.open + m(300 * float(c.away))
	west.global_position = c.open + m(-300 * float(c.away))
	west.sought_cover = true
	west.state = Unit.State.ACTIVE
	var eq1: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, c.open + m(40, 40))
	known(eq1)
	var engaged := false
	seed(4242)
	for minute in 60:
		bm.scenario_elapsed_time += 61.0
		bm._update_enemy_squad_advance()
		if east.assaulting or west.assaulting:
			engaged = true
	check(not engaged, "Two of theirs against two of ours (even numbers): no assault in an hour, where the chance would otherwise be near certain")
	eq1.state = Unit.State.WITHDRAWN
	eq1.enemy_known_state = Unit.State.WITHDRAWN
	var closed := false
	var minutes := 0
	while minutes < 400 and not closed:
		bm.scenario_elapsed_time += 61.0
		minutes += 1
		bm._update_enemy_squad_advance()
		closed = east.assaulting or west.assaulting
	check(closed, "Two of theirs on opposite sides against one of ours: closes in the end (after %d minutes)" % minutes)
	var mover: Unit = east if east.assaulting else west
	if closed:
		var goal_distance_m: float = mover.move_target.distance_to(target.global_position) / GameConfig.PIXELS_PER_METER
		check(mover.has_move_target and goal_distance_m <= GameConfig.CLOSE_RANGE_COVER_DEFEAT_M, "...to inside grenade range of it (%.0f m)" % goal_distance_m)
		check(mover.last_order_reason.begins_with("Assaulting"), "...and says why (%s)" % mover.last_order_reason)
		mover.last_order_reason = "marker"
		bm._update_enemy_squad_advance()
		check(mover.last_order_reason == "marker" and mover.has_move_target, "While it is closing nothing else re-orders it")
	# one side only, with the numbers: possible, but a tenth as readily as on two
	var west_gone := 0
	west.state = Unit.State.WITHDRAWN
	west.assaulting = false
	east.assaulting = false
	east.has_move_target = false
	var buddy: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.open + m(320 * float(c.away), 30))
	buddy.sought_cover = true
	check(bm._assault_numbers_allowed(east, target), "Setup: two of theirs on the same side against one of ours have the numbers")
	var one_side: float = bm._assault_chance_per_minute(east, target)
	check(one_side < 0.25 * two, "...but from one side only the chance is a tenth (%.4f against %.3f)" % [one_side, two])

	# 3. what it does not do: a squad it does not know of, a squad too weak to assault, one that has no minute's roll due
	var c2 := make()
	var b2: BattleManager = c2.bm
	var lonely: Unit = unit(c2, Unit.Team.PLAYER, Unit.Kind.SQUAD, c2.open)
	var attacker: Unit = unit(c2, Unit.Team.ENEMY, Unit.Kind.SQUAD, c2.open + m(300, 0))
	attacker.sought_cover = true
	seed(11)
	var got_there := false
	for i in 120:
		b2.scenario_elapsed_time += 61.0
		b2._update_enemy_squad_advance()
		if attacker.assaulting:
			got_there = true
	check(not got_there, "A squad the attacker has never sighted is not assaulted")
	known(lonely)
	attacker.pips = 3
	for i in 120:
		b2.scenario_elapsed_time += 61.0
		b2._update_enemy_squad_advance()
		if attacker.assaulting:
			got_there = true
	check(not got_there, "A squad below four does not assault")
	cleanup(c2)
	cleanup(c)

	print("Enemy assault tests: %d failures" % failures)
	quit(1 if failures else 0)
