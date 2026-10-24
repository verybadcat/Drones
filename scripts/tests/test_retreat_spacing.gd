extends SceneTree
## Direct user instruction: "Use 75m as the desirable distance. This does NOT mean they can never be closer. It means they strive for 75
## meters", and "If they are under pressure from other squads, it could be reasonable to be closer." After a battle in which two retreating
## squads ended 24 m apart (a mortar round on one catches a neighbour that close about 40% of the time).
##
## While retreating, a squad closer than GameConfig.SQUAD_DESIRED_SPACING to another squad of its side steers sideways, away from it, while
## still making its way to the safe line (BattleManager._retreat_spacing_offset). A preference: it fades as enemy squads close on it, and is
## gone when it is under direct fire.
##
## Run: godot --headless --path . --script scripts/tests/test_retreat_spacing.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(v: float) -> float:
	return v * GameConfig.PIXELS_PER_METER

func make() -> BattleManager:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	return bm

func squad(bm: BattleManager, pos_m: Vector2) -> Unit:
	var u: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(m(pos_m.x), m(pos_m.y)))
	bm.player_units.append(u)
	u.state = Unit.State.RETREATING
	u.retreat_speed = GameConfig.REPOSITION_SPEED
	u.retreat_target_x = GameConfig.PLAYER_SAFE_X
	return u

func foe(bm: BattleManager, pos_m: Vector2, known: bool = true) -> Unit:
	var e: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(m(pos_m.x), m(pos_m.y)))
	bm.enemy_units.append(e)
	e.player_has_been_sighted = known
	e.player_known_position = e.global_position
	e.player_known_state = Unit.State.ACTIVE
	return e

func run() -> void:
	# 1. two squads 24 m apart, nothing around: they open the gap while both still retreat west
	var bm := make()
	var a := squad(bm, Vector2(2000.0, 1000.0))
	var b := squad(bm, Vector2(2000.0, 1024.0))
	var x0: float = a.position.x
	var gap0: float = a.position.distance_to(b.position) / GameConfig.PIXELS_PER_METER
	for i in 120:
		bm._step_retreat(a, 1.0)
		bm._step_retreat(b, 1.0)
	var gap1: float = a.position.distance_to(b.position) / GameConfig.PIXELS_PER_METER
	check(gap1 > gap0 + 20.0, "Two squads 24 m apart open the gap while retreating (%.0f m to %.0f m)" % [gap0, gap1])
	check(a.position.y < b.position.y, "...in opposite directions (the one that was north goes further north)")
	check(a.position.x < x0 - m(10.0) and absf(a.position.x - b.position.x) < m(1.0), "...and both still make their way west at the same rate")
	bm.combat_log.free()
	bm.free()

	# 2. already as far apart as they want to be (GameConfig.SQUAD_DESIRED_SPACING, 100 m since 2026-10-24) or more: nothing
	bm = make()
	a = squad(bm, Vector2(2000.0, 1000.0))
	b = squad(bm, Vector2(2000.0, 1000.0 + GameConfig.SQUAD_DESIRED_SPACING / GameConfig.PIXELS_PER_METER + 5.0))
	check(bm._retreat_spacing_offset(a) == 0.0 and bm._retreat_spacing_offset(b) == 0.0, "Squads just over the desired spacing apart are left alone")
	bm.combat_log.free()
	bm.free()

	# 3. level with each other (same y): the two still pick opposite ways
	bm = make()
	a = squad(bm, Vector2(2000.0, 1000.0))
	b = squad(bm, Vector2(2020.0, 1000.0))
	var oa: float = bm._retreat_spacing_offset(a)
	var ob: float = bm._retreat_spacing_offset(b)
	check(oa != 0.0 and ob != 0.0 and signf(oa) != signf(ob), "Squads level with each other steer opposite ways (%.2f, %.2f)" % [oa, ob])
	bm.combat_log.free()
	bm.free()

	# 4. under pressure from enemy squads it relaxes, by their strength against ours (two squads here, 18 pips): none known -> full; one enemy
	# squad (9 pips) is not pressure even close; three 800 m away (inside the danger range, half weight) -> less; three at 300 m, or the squad
	# taking fire -> none
	bm = make()
	a = squad(bm, Vector2(2000.0, 1000.0))
	b = squad(bm, Vector2(2000.0, 1024.0))
	var calm: float = absf(bm._retreat_spacing_offset(a))
	check(calm > 0.4, "Setup: with nothing around the push is strong (%.2f)" % calm)
	var e1 := foe(bm, Vector2(2300.0, 1000.0)) # 300 m
	check(absf(bm._retreat_spacing_offset(a)) > 0.4, "One enemy squad 300 m away against two of ours is not pressure: the preference stands (%.2f)" % absf(bm._retreat_spacing_offset(a)))
	var e2 := foe(bm, Vector2(2800.0, 1100.0))
	var e3 := foe(bm, Vector2(2800.0, 900.0))
	for e in [e1, e2, e3]:
		e.pips = 9
	e1.global_position = Vector2(m(2800.0), m(1000.0)) # three squads, 800 m
	e1.player_known_position = e1.global_position
	var some: float = absf(bm._retreat_spacing_offset(a))
	check(some < calm and some > 0.0, "With three enemy squads 800 m away against our two the preference is weaker (%.2f against %.2f)" % [some, calm])
	for e in [e1, e2, e3]:
		e.global_position = Vector2(m(2300.0), m(1000.0)) # 300 m: inside engagement range
		e.player_known_position = e.global_position
	check(bm._retreat_spacing_offset(a) == 0.0, "With three enemy squads within engagement range it is gone: the squads may stay as close as they are")
	for e in [e1, e2, e3]:
		e.global_position = Vector2(m(4000.0), m(1000.0))
		e.player_known_position = e.global_position
	a.taking_fire = true
	check(bm._retreat_spacing_offset(a) == 0.0, "...and gone while the squad is taking fire")
	a.taking_fire = false
	for e in [e1, e2, e3]:
		e.global_position = Vector2(m(2300.0), m(1000.0))
		e.player_known_position = e.global_position
		e.player_has_been_sighted = false
	check(absf(bm._retreat_spacing_offset(a)) > 0.4, "Enemy squads this side has not sighted exert no pressure (it acts only on what it knows)")
	bm.combat_log.free()
	bm.free()

	# 5. only squads keep to each other: a mortar crew beside a squad is not pushed, and does not push it
	bm = make()
	a = squad(bm, Vector2(2000.0, 1000.0))
	var gun: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(m(2000.0), m(1020.0)))
	bm.player_units.append(gun)
	gun.state = Unit.State.RETREATING
	check(bm._retreat_spacing_offset(gun) == 0.0 and bm._retreat_spacing_offset(a) == 0.0, "A mortar crew is neither pushed by a squad nor pushes it")
	bm.combat_log.free()
	bm.free()

	print("Retreat spacing tests: %d failures" % failures)
	quit(1 if failures else 0)
