extends SceneTree
## Squads keep apart while advancing. User, 2026-10-24: "yes, of course it should apply to the locations of the squads while advancing. They should try to
## keep 100 meters apart. That was the whole point." The next point of an advance bound (BattleManager._next_advance_point) is weighted down when it is
## closer than GameConfig.ENEMY_ADVANCE_DESIRED_SPACING_M to where another active enemy squad is, or is going (its move target); a preference, not a wall.
##
## Run: godot --headless --path . --script scripts/tests/test_advance_spacing.gd
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

func make_battle() -> BattleManager:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	for p in [Vector2(0.0, 0.0), Vector2(0.0, 100.0), Vector2(0.0, -100.0)]:
		var f: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(p.x + 1500.0, p.y + 1900.0)) # on the map (a map is 5000 m by 3800 m; positions off it are clamped)
		f.enemy_has_been_sighted = true
		f.enemy_known_state = Unit.State.ACTIVE
		bm.player_units.append(f)
	return bm

func enemy_at(bm: BattleManager, pos_m: Vector2) -> Unit:
	var e: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(pos_m.x, pos_m.y))
	bm.enemy_units.append(e)
	return e

## The share of rolled bounds of `u` that end within the desired spacing of `spot`.
func share_near(bm: BattleManager, u: Unit, spot: Vector2, rolls: int) -> float:
	var near := 0
	var wanted: float = GameConfig.ENEMY_ADVANCE_DESIRED_SPACING_M * GameConfig.PIXELS_PER_METER
	for i in rolls:
		if bm._next_advance_point(u).distance_to(spot) < wanted:
			near += 1
	return float(near) / float(rolls)

func run() -> void:
	GameConfig.set_active_map("voznesensk")
	seed(4242)
	check(GameConfig.ENEMY_ADVANCE_DESIRED_SPACING_M == 100.0 and GameConfig.ENEMY_ADVANCE_MIN_SPACING_M == 100.0, "the squads are to keep 100 m apart, in the starting formation too")
	var bm := make_battle()
	var u: Unit = enemy_at(bm, Vector2(3500.0, 1900.0))
	var straight: Vector2 = u.global_position + (bm._enemy_advance_objective(u) - u.global_position).normalized() * GameConfig.ENEMY_ADVANCE_RUSH_DISTANCE # where a bound goes, so far from the fight
	var rolls := 600

	# alone: the bound ends within 100 m of the spot most of the time (it is the straight-ahead point)
	var alone: float = share_near(bm, u, straight, rolls)
	check(alone > 0.6, "setup: alone, the bound ends near the straight-ahead spot (%.2f)" % alone)

	# another squad standing on that spot: the bound goes elsewhere much more often
	var mate: Unit = enemy_at(bm, straight / GameConfig.PIXELS_PER_METER)
	var with_mate: float = share_near(bm, u, straight, rolls)
	check(with_mate < 0.5 * alone, "with a squad standing at that spot the bound ends within 100 m of it far less often (%.2f against %.2f)" % [with_mate, alone])
	check(with_mate > 0.0, "...but it is a preference, not a wall: it still sometimes does (%.2f)" % with_mate)

	# another squad on its way to that spot counts the same
	mate.global_position = m(3500.0, 2800.0)
	mate.has_move_target = true
	mate.move_target = straight
	var going: float = share_near(bm, u, straight, rolls)
	check(going < 0.5 * alone, "with a squad on its way to that spot, the same (%.2f against %.2f)" % [going, alone])

	# a retreating or destroyed squad is not one to keep apart from; nor is a squad of the other side
	mate.has_move_target = false
	mate.global_position = straight
	mate.state = Unit.State.RETREATING
	var retreating: float = share_near(bm, u, straight, rolls)
	check(retreating > 0.8 * alone, "a retreating squad standing there does not count (%.2f against %.2f)" % [retreating, alone])

	# a squad 150 m from the spot is far enough: no effect
	mate.state = Unit.State.ACTIVE
	mate.global_position = straight + Vector2(0.0, 150.0) * GameConfig.PIXELS_PER_METER
	var far_mate: float = share_near(bm, u, straight, rolls)
	check(far_mate > 0.8 * alone, "a squad 150 m from the spot is far enough away (%.2f against %.2f)" % [far_mate, alone])

	print("Advance spacing tests: %d failures" % failures)
	bm.combat_log.free()
	bm.free()
	quit(1 if failures else 0)
