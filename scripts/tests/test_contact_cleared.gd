extends SceneTree
## A contact that is gone (GameConfig.CONTACT_CLEARED_*). Found 2026-10-16 (voznesensk, seed 1008): our squad moved into a building 260 m
## from where the enemy last saw it; nine Russian squads converged on that last sighting, found nobody, and sat there for eleven hours
## re-rolling an assault on it (354 of them; the battle ran to its 12 h cap). An enemy squad that stands within 40 m of the place it last
## saw one of ours, with a line of sight to the place, for 30 s without seeing the squad, now knows it is not there. Not for a point in a
## building; not while the squad is in view; the timer starts again if the enemy squad leaves; a fresh sighting restores the contact. It
## uses only the enemy's own squads, the place of the last sighting and what the enemy can see now.
##
## Run: godot --headless --path . --script scripts/tests/test_contact_cleared.gd
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
	return {"bm": bm, "open": m(-5000, -5000), "building": GameConfig._building_rects[0].get_center()}

func unit(c: Dictionary, team: Unit.Team, kind: Unit.Kind, point: Vector2) -> Unit:
	var u: Unit = c.bm._make_unit(team, kind, point)
	if team == Unit.Team.PLAYER:
		c.bm.player_units.append(u)
	else:
		c.bm.enemy_units.append(u)
	return u

## One of our squads, last seen by the enemy at `seen_at` and in fact somewhere else, out of sight.
func ghost(c: Dictionary, seen_at: Vector2) -> Unit:
	var t: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, c.open + m(0, 900))
	t.is_visible = false
	t.enemy_has_been_sighted = true
	t.enemy_known_state = Unit.State.ACTIVE
	t.enemy_known_position = seen_at
	t.enemy_known_pips = t.pips
	return t

## Advance the enemy's intelligence by `seconds` of scenario time, one second at a time.
func run_for(c: Dictionary, seconds: int) -> void:
	for i in seconds:
		c.bm.scenario_elapsed_time += 1.0
		c.bm._update_enemy_intel()

func run() -> void:
	# 1. an enemy squad on the spot, in the open, sees nobody: 30 s later the contact is gone
	var c := make()
	var t: Unit = ghost(c, c.open)
	var e: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.open + m(20, 0))
	check(c.bm._known_friendly_squad_objective(e) == c.open, "before: the last sighting is the objective of the enemy squad")
	run_for(c, 25)
	check(t.enemy_has_been_sighted, "25 s on the spot: still sighted")
	run_for(c, 4)
	check(t.enemy_has_been_sighted, "29 s on the spot: still sighted")
	run_for(c, 3)
	check(not t.enemy_has_been_sighted, "32 s on the spot: the contact is gone")
	check(is_inf(c.bm._known_friendly_squad_objective(e).x), "after: no known squad for the advance to head for")
	check(c.bm._nearest_sighted_foe_squad(e, m(450).x) == null, "after: no sighted squad for an assault to be rolled on")
	# a fresh sighting restores it, where the squad really is
	t.is_visible = true
	run_for(c, 1)
	check(t.enemy_has_been_sighted and t.enemy_known_position.is_equal_approx(t.global_position), "seen again: known again, where it is")

	# 2. too far to be looking at the place: nothing is cleared
	c = make()
	t = ghost(c, c.open)
	e = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.open + m(120, 0))
	run_for(c, 120)
	check(t.enemy_has_been_sighted, "an enemy squad 120 m away does not clear it")

	# 3. the last sighting is inside a building: from outside nobody can tell
	c = make()
	t = ghost(c, c.building)
	e = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.building + m(15, 0))
	run_for(c, 120)
	check(t.enemy_has_been_sighted, "a last sighting in a building is not cleared")

	# 4. the enemy squad leaves for a moment: the thirty seconds start again
	c = make()
	t = ghost(c, c.open)
	e = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.open + m(20, 0))
	run_for(c, 20)
	e.global_position = c.open + m(300, 0)
	run_for(c, 1)
	e.global_position = c.open + m(20, 0)
	run_for(c, 20)
	check(t.enemy_has_been_sighted, "20 s, away, 20 s: not yet (the count began again)")
	run_for(c, 12)
	check(not t.enemy_has_been_sighted, "thirty seconds on the spot since it came back: gone")

	# 5. a squad that is in view is not a ghost, and a squad known to be out of the fight is not asked about
	c = make()
	t = ghost(c, c.open)
	t.is_visible = true
	e = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.open + m(20, 0))
	run_for(c, 120)
	check(t.enemy_has_been_sighted, "a squad in view stays sighted")
	c = make()
	t = ghost(c, c.open)
	t.enemy_known_state = Unit.State.RETREATING
	e = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.open + m(20, 0))
	run_for(c, 120)
	check(t.enemy_has_been_sighted, "a contact last known to be retreating is left as it was")

	# 6. only an ACTIVE enemy SQUAD looks: a mortar crew, or a squad that is down, does not
	c = make()
	t = ghost(c, c.open)
	var crew: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.MORTAR, c.open + m(20, 0))
	var down: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.open + m(25, 0))
	down.state = Unit.State.RETREATING
	run_for(c, 120)
	check(t.enemy_has_been_sighted, "a crew and a retreating squad do not clear it")

	print("Contact cleared tests: %d failures" % failures)
	quit(1 if failures else 0)
