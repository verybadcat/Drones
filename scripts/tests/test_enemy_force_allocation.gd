extends SceneTree
## Direct user instruction, after watching a whole enemy column walk past three friendly squads in good cover to go after the mortar: a
## real force does both. A detachment is sent after the mortar; a fixing force and a main body deal with the squads (real doctrine: fire
## and movement, with some elements covering the movement of others; a fixing force pins the defender so the rest can move; mortars are
## mostly a matter for counter-battery, not for the infantry to march past a defended position toward).
##
## What changed: (1) only the closest MORTAR_HUNT_SQUAD_CAP squads (or the surplus beyond MORTAR_HUNT_SUPERIORITY_RATIO to 1) have the
## mortar as their objective, from wherever they are; the others go for the nearest friendly squad they know of (or gather clear of
## them, with no numerical advantage); (2) a squad that is mid-bound stops where it is when a friendly squad is in its range and line of
## sight, instead of walking on (a moving squad cannot fire).
##
## Run: godot --headless --path . --script scripts/tests/test_enemy_force_allocation.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
const Orders = preload("res://scripts/unit_doctrine.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(v: float) -> float:
	return v * GameConfig.PIXELS_PER_METER

## A battle with an active player mortar at (0, 0) whose position the enemy has a fix on, `friendly` player squads far to the north
## (known to the enemy), and `enemy` enemy squads 3 to 4 km east, in a column.
func make(enemy: int, friendly: int) -> Dictionary:
	seed(41)
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.unit_type_doctrines[Unit.Team.ENEMY] = Orders.sanitize({})
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(0.0, 0.0))
	bm.player_units.append(mortar)
	mortar.is_visible = true
	var ours: Array[Unit] = []
	for i in friendly:
		var s: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(m(2000.0), m(-1500.0 - 100.0 * i)))
		bm.player_units.append(s)
		s.enemy_has_been_sighted = true
		s.enemy_known_position = s.global_position
		s.enemy_known_state = Unit.State.ACTIVE
		ours.append(s)
	var theirs: Array[Unit] = []
	for i in enemy:
		var e: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(m(3000.0 + 40.0 * i), m(0.0)))
		bm.enemy_units.append(e)
		e.sought_cover = true
		theirs.append(e)
	return {"bm": bm, "ours": ours, "theirs": theirs, "mortar": mortar}

func cleanup(c: Dictionary) -> void:
	c.bm.combat_log.free()
	c.bm.free()

func run() -> void:
	# 1. 12 against 3: three (the cap) go after the mortar, the closest three to it; the other nine go for the nearest friendly squad
	var c := make(12, 3)
	var bm: BattleManager = c.bm
	bm._update_enemy_attack_stance()
	bm._mortar_hunters = bm._compute_mortar_hunters()
	check(bm._mortar_hunters.size() == GameConfig.MORTAR_HUNT_SQUAD_CAP, "A detachment of the cap (%d) is sent after the mortar (got %d)" % [GameConfig.MORTAR_HUNT_SQUAD_CAP, bm._mortar_hunters.size()])
	var closest_ok := true
	for i in GameConfig.MORTAR_HUNT_SQUAD_CAP:
		if not bm._mortar_hunters.has(c.theirs[i]):
			closest_ok = false
	check(closest_ok, "...the squads closest to the mortar")
	check(bm._enemy_advance_objective(c.theirs[0]).distance_to(c.mortar.global_position) < 1.0, "A squad of the detachment has the mortar as its objective")
	var main_objective: Vector2 = bm._enemy_advance_objective(c.theirs[8])
	var nearest_known: Vector2 = bm._known_friendly_squad_objective(c.theirs[8])
	check(main_objective.distance_to(nearest_known) < 1.0 and main_objective.distance_to(c.mortar.global_position) > m(500.0), "Any other squad's objective is the nearest friendly squad it knows of, not the mortar")
	cleanup(c)

	# 2. no friendly squad known: everyone's objective is the mortar, as before
	c = make(12, 0)
	bm = c.bm
	bm._mortar_hunters = bm._compute_mortar_hunters()
	check(bm._enemy_advance_objective(c.theirs[8]).distance_to(c.mortar.global_position) < 1.0, "With no friendly squad to go for, every squad's objective is the mortar")
	cleanup(c)

	# 3. no numerical advantage (2 against 2): the detachment goes, the others gather clear of the friendly squads instead of attacking
	c = make(2, 2)
	bm = c.bm
	bm._update_enemy_attack_stance()
	check(not bm._enemy_attack_stance(), "Setup: no 2:1 advantage, so no attack")
	bm._mortar_hunters = {c.theirs[0]: true}
	check(bm._enemy_advance_objective(c.theirs[1]).distance_to(bm._enemy_consolidation_point()) < 1.0, "Without the numbers to attack, the squads not sent after the mortar gather clear of the friendly squads")
	cleanup(c)

	# 4. a large superiority: the surplus beyond the ratio may go after the mortar too (20 against 3: 20 - 9 = 11)
	c = make(20, 3)
	bm = c.bm
	check(bm._compute_mortar_hunters().size() == 11, "20 squads against 3: the surplus beyond the superiority ratio hunts too (11), got %d" % bm._compute_mortar_hunters().size())
	cleanup(c)
	# ...and with no friendly squad in action, all of them
	c = make(6, 0)
	bm = c.bm
	check(bm._compute_mortar_hunters().size() == 6, "With no friendly squad in action every squad is sent after the mortar")
	cleanup(c)

	# 5. a squad on its wide flanking route is not counted
	c = make(5, 3)
	bm = c.bm
	c.theirs[0].flanking_route_active = true
	check(not bm._compute_mortar_hunters().has(c.theirs[0]), "A squad on its flanking route is not one of the detachment")
	cleanup(c)

	# 6. contact: a squad mid-bound stops when a friendly squad is in its range and line of sight; one with nothing in range keeps going;
	# a flanker keeps going
	c = make(3, 1)
	bm = c.bm
	var foe: Unit = c.ours[0]
	foe.global_position = Vector2(m(3000.0 - 200.0), m(0.0)) # 200 m from the first enemy squad (inside its 400 m)
	foe.is_visible = true
	var in_contact: Unit = c.theirs[0]
	var far_squad: Unit = c.theirs[2]
	far_squad.global_position = Vector2(m(5000.0), m(0.0)) # 2 km from the friendly squad: nothing in its range
	for u in c.theirs:
		u.has_move_target = true
		u.move_target = Vector2(m(-2000.0), 0.0)
	var flanker: Unit = c.theirs[1]
	flanker.flanking_route_active = true
	flanker.global_position = Vector2(m(3000.0 - 150.0), m(30.0))
	bm._update_enemy_squad_advance()
	check(not in_contact.has_move_target, "A squad mid-bound with a friendly squad in range and line of sight stops to fight")
	check(flanker.has_move_target, "...a squad on its flanking route does not")
	check(far_squad.has_move_target, "...nor a squad with nothing in range")
	cleanup(c)

	print("Enemy force allocation tests: %d failures" % failures)
	quit(1 if failures else 0)
