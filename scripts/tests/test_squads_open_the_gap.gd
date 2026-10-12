extends SceneTree
## Direct user report, live: two friendly squads standing 15 m apart, in cover, doing nothing (their screening order had lapsed), with the
## mortar gone. And the standing instructions: "Use 75m as the desirable distance. This does NOT mean they can never be closer. It means
## they strive for 75 meters" and "If they are under pressure from other squads, it could be reasonable to be closer."
##
## A squad standing in cover closer than GameConfig.SQUAD_DESIRED_SPACING to another friendly squad moves to a better cover point (one that
## is actually farther from the others), when no real enemy pressure is on it. Only one of a pair goes. A single enemy squad against two of
## ours is not pressure; equal or greater numbers close by are, and then they stay as they are.
##
## Run: godot --headless --path . --script scripts/tests/test_squads_open_the_gap.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(x: float, y: float) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

## The Voznesensk tree patch at about (1665, 1855) m, and two squads of ours 15 m apart inside it.
func make() -> Dictionary:
	GameConfig.set_active_map("voznesensk")
	seed(5)
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var a: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(1665, 1855))
	var b: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(1680, 1855))
	bm.player_units.append(a)
	bm.player_units.append(b)
	return {"bm": bm, "a": a, "b": b}

func foe(bm: BattleManager, x: float, y: float) -> Unit:
	var e: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(x, y))
	bm.enemy_units.append(e)
	e.player_has_been_sighted = true
	e.player_known_position = e.global_position
	e.player_known_state = Unit.State.ACTIVE
	return e

func cleanup(c: Dictionary) -> void:
	c.bm.combat_log.free()
	c.bm.free()

func run() -> void:
	# 1. nothing around: exactly one of the two goes, to cover farther from the other
	var c := make()
	var bm: BattleManager = c.bm
	check(GameConfig.is_in_cover(c.a.terrain_type()) and GameConfig.is_in_cover(c.b.terrain_type()), "Setup: both are standing in cover")
	bm._update_friendly_squad_positioning()
	var movers: Array = [c.a, c.b].filter(func(u): return u.has_move_target)
	check(movers.size() == 1, "Exactly one of two squads 15 m apart moves (got %d)" % movers.size())
	if movers.size() == 1:
		var mover: Unit = movers[0]
		var other: Unit = c.b if mover == c.a else c.a
		check(mover.last_order_reason == BattleManager.SPREAD_REASON, "...with its reason stated (%s)" % mover.last_order_reason)
		check(mover.move_target.distance_to(other.global_position) > m(15, 0).x + m(10, 0).x, "...to a place farther from the other than it stood (%.0f m)" % (mover.move_target.distance_to(other.global_position) / GameConfig.PIXELS_PER_METER))
	# a second pass changes nothing: the one on its way is not a neighbour, and the other is not asked to go
	var before_b: bool = c.b.has_move_target
	bm._update_friendly_squad_positioning()
	check(c.b.has_move_target == before_b, "...and the other does not also go on the next pass")
	cleanup(c)

	# 2. already 100 m apart: neither moves
	c = make()
	c.b.global_position = m(1765, 1855)
	var no_enemies: Array[Vector2] = []
	var nothing_claimed: Array[Vector2] = []
	check(c.bm._spread_from_neighbour(c.a, no_enemies, nothing_claimed) == c.a.global_position, "A squad 100 m from its neighbour is left alone")
	cleanup(c)

	# 3. one enemy squad 250 m away is not pressure on two of ours: they still open the gap
	c = make()
	foe(c.bm, 1665.0 + 250.0, 1855.0)
	c.bm._update_friendly_squad_positioning()
	# (a squad with something to shoot at stands and fights: this checks only that the presence of one enemy squad is not read as pressure)
	check(c.bm._enemy_squad_pressure(c.a) == 0.0, "One enemy squad 250 m away against two of ours is no pressure (%.2f)" % c.bm._enemy_squad_pressure(c.a))
	cleanup(c)

	# 4. three enemy squads close by are pressure: they stay close
	c = make()
	foe(c.bm, 1665.0 + 250.0, 1855.0)
	foe(c.bm, 1665.0 + 300.0, 1900.0)
	foe(c.bm, 1665.0 + 300.0, 1810.0)
	check(c.bm._enemy_squad_pressure(c.a) >= 0.5, "Setup: three enemy squads within engagement range of two of ours are pressure (%.2f)" % c.bm._enemy_squad_pressure(c.a))
	var nothing_claimed2: Array[Vector2] = []
	check(c.bm._spread_from_neighbour(c.a, c.bm._known_enemy_positions(Unit.Team.PLAYER), nothing_claimed2) == c.a.global_position, "Under pressure a squad stays where it is, close to its neighbour")
	cleanup(c)

	# 5. taking fire is full pressure
	c = make()
	c.a.taking_fire = true
	var none_a: Array[Vector2] = []
	var none_b: Array[Vector2] = []
	check(c.bm._enemy_squad_pressure(c.a) == 1.0 and c.bm._spread_from_neighbour(c.a, none_a, none_b) == c.a.global_position, "A squad taking fire stays where it is")
	cleanup(c)

	print("Squads open the gap tests: %d failures" % failures)
	quit(1 if failures else 0)
