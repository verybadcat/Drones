extends SceneTree
## Direct user report, live: "Right now, enemy squads are headed towards the bottom left corner. This is not rational. They know where at least
## some of our squads are. They have a general idea where they last saw the mortar. None of this is the bottom left corner." The live snapshot:
## three Russian squads at x = -1,100 m in the south-west corner of the map, objective (-1,400, their own y), our squads 1,300 m east of them and
## known, our mortar far to the north. Once a squad has reached the village (a latch) its objective is "push west on its own line toward the
## defenders' side", which was meant for when nothing is known. With the mortar still active but no fresh fix, nothing earlier in
## _enemy_advance_objective applies, so every squad ran that blind line. Now, with something known, it goes for it: the nearest of the mortar's
## last known position and (if the force has the numbers, _enemy_attack_stance) the nearest known friendly squad.
##
## Run: godot --headless --path . --script scripts/tests/test_enemy_push_goes_for_what_is_known.gd
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

func make() -> Dictionary:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(136, 433))
	bm.player_units.append(mortar)
	var squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(250, 2300))
	bm.player_units.append(squad)
	var raider: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(-1100, 3500))
	bm.enemy_units.append(raider)
	raider.village_reached = true
	# an enemy force big enough to attack
	for i in 3:
		var e: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(-1000 + i * 100, 3400))
		bm.enemy_units.append(e)
	bm._enemy_attacking = true
	return {"bm": bm, "mortar": mortar, "squad": squad, "raider": raider}

func know_squad(c: Dictionary, at: Vector2) -> void:
	var s: Unit = c.squad
	s.enemy_has_been_sighted = true
	s.enemy_known_position = at
	s.enemy_known_state = Unit.State.ACTIVE

func know_mortar(c: Dictionary, at: Vector2) -> void:
	var u: Unit = c.mortar
	u.enemy_has_been_sighted = true
	u.enemy_known_position = at
	u.enemy_known_position_time = 100.0
	u.enemy_known_state = Unit.State.ACTIVE

func run() -> void:
	GameConfig.set_active_map("voznesensk")
	# 1. nothing known: the blind push west along its own line, as before
	var c := make()
	var obj: Vector2 = c.bm._enemy_advance_objective(c.raider)
	check(is_equal_approx(obj.x, GameConfig.PLAYER_SAFE_X) and is_equal_approx(obj.y, c.raider.global_position.y), "With nothing known the squad still pushes west along its own line (%s)" % str(obj / GameConfig.PIXELS_PER_METER))
	# 2. the mortar's last known place: go there
	know_mortar(c, m(120, 500))
	obj = c.bm._enemy_advance_objective(c.raider)
	check(obj.distance_to(m(120, 500)) < 1.0, "With the mortar's last known position, the squad heads for it, not the corner (%s)" % str(obj / GameConfig.PIXELS_PER_METER))
	# 3. a known squad as well, and the numbers to attack: whichever is nearer the raider
	know_squad(c, m(250, 2300))
	obj = c.bm._enemy_advance_objective(c.raider)
	check(obj.distance_to(m(250, 2300)) < 1.0, "With a known friendly squad nearer than the mortar, and the numbers to attack, it heads for the squad (%s)" % str(obj / GameConfig.PIXELS_PER_METER))
	# 4. a known squad but no stance to attack: not the squad, the mortar's last known place
	c.bm._enemy_attacking = false
	obj = c.bm._enemy_advance_objective(c.raider)
	check(obj.distance_to(m(120, 500)) < 1.0, "Without the numbers to attack the squad, it still goes for the mortar's last known place (%s)" % str(obj / GameConfig.PIXELS_PER_METER))
	c.bm.combat_log.free()
	c.bm.free()
	# 5. only a known squad and no stance: gather, not the corner
	c = make()
	know_squad(c, m(250, 2300))
	c.bm._enemy_attacking = false
	obj = c.bm._enemy_advance_objective(c.raider)
	check(not (is_equal_approx(obj.x, GameConfig.PLAYER_SAFE_X) and is_equal_approx(obj.y, c.raider.global_position.y)), "With only a known squad and no numbers to attack it gathers; it does not run for the corner (%s)" % str(obj / GameConfig.PIXELS_PER_METER))
	# 6. not yet at the village: the village, as before
	c.raider.village_reached = false
	obj = c.bm._enemy_advance_objective(c.raider)
	check(obj.distance_to(GameConfig.CURRENT_MAP.village_center) < 1.0, "A squad that has not reached the village still goes to it")
	c.bm.combat_log.free()
	c.bm.free()
	print("Enemy push goes for what is known tests: %d failures" % failures)
	quit(1 if failures else 0)
