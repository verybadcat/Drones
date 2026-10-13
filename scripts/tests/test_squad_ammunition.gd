extends SceneTree
## Squad small-arms ammunition and fire discipline. User, 2026-10-13: "Finite ammunition is a good idea", "Don't do the position cache. Our
## squads move pretty often. Let's try assuming that resupply is not available on the scale of this battle. Fire discipline yes do that."
## A squad has what it carries (GameConfig.SQUAD_ROUNDS_PER_PERSON a person) and nothing more; a volley costs rounds by the people who
## fire it; casualties do not take the pool with them; below half a load it holds fire at targets not worth the rounds, never at
## targets close by; a squad that has fired its last round pulls back. Either side. Not mortars, spotters or drone teams.
##
## Run: godot --headless --path . --script scripts/tests/test_squad_ammunition.gd
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

## One call of the real fire tick for `shooter` at the opposing squad list.
func fire(c: Dictionary, shooter: Unit) -> void:
	shooter.fire_timer = 0.0
	var foes: Array[Unit] = c.bm.enemy_units if shooter.team == Unit.Team.PLAYER else c.bm.player_units
	c.bm._tick_fire(shooter, 1.0, 60.0, foes)

func run() -> void:
	var c := make()
	var bm: BattleManager = c.bm
	var squad: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, c.open)
	var foe: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.open + m(200))
	foe.is_visible = true
	squad.is_visible = true
	foe.entrenchment = Unit.Entrenchment.NONE

	# 1. what each unit has
	check(squad.rounds_limited and squad.rounds == squad.max_pips * GameConfig.SQUAD_ROUNDS_PER_PERSON and squad.rounds_capacity == squad.rounds, "A squad starts with a load for each of its people (%d)" % squad.rounds)
	check(foe.rounds_limited and foe.rounds == foe.rounds_capacity, "...the enemy's too")
	var gun: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.MORTAR, c.open + m(0, 600))
	var scout: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SPOTTER, c.open + m(0, 700))
	check(not gun.rounds_limited and not scout.rounds_limited, "A mortar (its own rounds) and a spotter (unarmed) are not on this ledger")
	var bare := Unit.new()
	bare.kind = Unit.Kind.SQUAD
	check(not bare.rounds_limited, "A bare unit that was not set up is not rationed")
	bare.free()

	# 2. a volley costs rounds by the people who fire it; a casualty does not take the pool with him
	var before: int = squad.rounds
	fire(c, squad)
	check(before - squad.rounds == squad.pips * GameConfig.SQUAD_ROUNDS_PER_PERSON_PER_VOLLEY, "A volley of nine costs %d rounds (%d)" % [9 * GameConfig.SQUAD_ROUNDS_PER_PERSON_PER_VOLLEY, before - squad.rounds])
	squad.pips = 4
	before = squad.rounds
	fire(c, squad)
	check(before - squad.rounds == 4 * GameConfig.SQUAD_ROUNDS_PER_PERSON_PER_VOLLEY, "...and a volley of four, four people's worth (%d)" % (before - squad.rounds))
	check(squad.rounds > 0.9 * squad.rounds_capacity - 100, "...the pool is not cut by the people lost (%d of %d)" % [squad.rounds, squad.rounds_capacity])
	squad.pips = 9

	# 3. fire discipline: nothing until below half a load; then a target not worth the rounds is held fire at, more as the load falls; a
	# close target or a good shot never is
	var far_cover: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.open + m(350, 120))
	var rect: Rect2 = GameConfig._building_rects[0]
	far_cover.global_position = rect.get_center()
	squad.global_position = rect.get_center() + m(300, 0)
	if GameConfig.get_terrain_type_at(squad.global_position) != GameConfig.TerrainType.OPEN:
		squad.global_position = rect.get_center() + m(0, 300)
	var poor_shot: float = CombatResolver.hit_probability(squad, far_cover)
	check(poor_shot < 0.5 * GameConfig.SQUAD_FIRE_DISCIPLINE_REFERENCE_HIT_CHANCE, "Setup: a target in a building 300 m away is a poor shot (%.3f)" % poor_shot)
	var near_open: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, squad.global_position + m(60, 0))
	var held := func(shooter: Unit, target: Unit, trials: int) -> int:
		var n := 0
		for i in trials:
			if bm._squad_holds_fire_for_ammunition(shooter, target):
				n += 1
		return n
	squad.rounds = squad.rounds_capacity
	check(held.call(squad, far_cover, 300) == 0, "A full load: no fire discipline")
	squad.rounds = int(0.55 * squad.rounds_capacity)
	check(held.call(squad, far_cover, 300) == 0, "Above half a load: none")
	squad.rounds = int(0.25 * squad.rounds_capacity)
	var quarter: int = held.call(squad, far_cover, 600)
	squad.rounds = int(0.05 * squad.rounds_capacity)
	var low: int = held.call(squad, far_cover, 600)
	check(quarter > 60 and low > quarter + 60, "Lower, it holds fire at a poor shot more: %d of 600 at a quarter, %d at a twentieth" % [quarter, low])
	check(held.call(squad, near_open, 600) == 0, "...but not at a good shot 60 m away, however little it has")
	var close_cover: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, squad.global_position + m(30, 0))
	close_cover.global_position = squad.global_position + m(0, 30)
	check(held.call(squad, close_cover, 300) < 30, "...nor at anything within 30 m (%d of 300)" % held.call(squad, close_cover, 300))

	# 4. the last round: it fires what it has, says so, and pulls back; dry it does not fire
	squad.global_position = c.open
	squad.rounds = 7
	squad.state = Unit.State.ACTIVE
	squad.has_move_target = false
	fire(c, squad)
	check(squad.rounds == 0 and squad.state == Unit.State.RETREATING and squad.last_order_reason == "Out of ammunition.", "Its last rounds go, and it pulls back (rounds %d, %s, %s)" % [squad.rounds, Unit.State.keys()[squad.state], squad.last_order_reason])
	var shots_before: int = bm._history_fire_events.size()
	squad.has_move_target = false
	fire(c, squad)
	check(bm._history_fire_events.size() == shots_before, "A squad with nothing left fires nothing")

	# 5. the enemy's squads are the same
	foe.pips = 9
	foe.state = Unit.State.ACTIVE
	foe.has_move_target = false # our volleys sent it to cover, which is a move: too busy to fire
	foe.move_queue.clear()
	foe.rounds = foe.rounds_capacity
	var theirs: int = foe.rounds
	squad.state = Unit.State.ACTIVE
	squad.rounds = squad.rounds_capacity
	fire(c, foe)
	check(theirs - foe.rounds == 9 * GameConfig.SQUAD_ROUNDS_PER_PERSON_PER_VOLLEY, "An enemy squad spends the same (%d)" % (theirs - foe.rounds))
	cleanup(c)

	print("Squad ammunition tests: %d failures" % failures)
	quit(1 if failures else 0)
