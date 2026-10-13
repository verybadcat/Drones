extends SceneTree
## Our squads assault too, but rarely. User: "Our squads can assault too, but only if they have numbers and surround, which won't happen
## often." The enemy's decision (test_enemy_assault) applied to the player's squads, with two gates: at least twice the people of the enemy
## squads the player's side knows of near the target, and at least half the circle (two opposite sides) held; and not when the squad is
## under an order of the player's (a move already under way, a fall-back, a hold) or pinned.
##
## Run: godot --headless --path . --script scripts/tests/test_player_assault.gd
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
	return {"bm": bm, "open": open_point}

func unit(c: Dictionary, team: Unit.Team, kind: Unit.Kind, point: Vector2) -> Unit:
	var u: Unit = c.bm._make_unit(team, kind, point)
	if team == Unit.Team.PLAYER:
		c.bm.player_units.append(u)
	else:
		c.bm.enemy_units.append(u)
	return u

func known_to_player(f: Unit) -> void:
	f.player_has_been_sighted = true
	f.player_known_position = f.global_position
	f.player_known_state = Unit.State.ACTIVE
	f.player_known_pips = f.pips

func cleanup(c: Dictionary) -> void:
	c.bm.combat_log.free()
	c.bm.free()

func run() -> void:
	var c := make()
	var bm: BattleManager = c.bm
	var o: Vector2 = c.open
	var foe: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, o)
	known_to_player(foe)
	var east: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, o + m(300, 0))

	# 1. one squad of ours against one of theirs, from one side: not allowed (no sides held, no numbers)
	check(not bm._player_assault_allowed(east, foe), "One squad against one, from one side: not allowed")
	# 2. two of ours on opposite sides against one: sides and numbers
	var west: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, o + m(-300, 0))
	check(bm._player_assault_allowed(east, foe), "Two squads on opposite sides against one: allowed")
	# 3. ... but two of theirs near it make it 1:1, not allowed
	var buddy: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, o + m(60, 40))
	known_to_player(buddy)
	check(not bm._player_assault_allowed(east, foe), "Two of ours against two of theirs: not enough numbers")
	# 4. three of ours on three sides against two: allowed again
	var north: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, o + m(0, -300))
	var south: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, o + m(0, 300))
	check(bm._player_assault_allowed(east, foe), "Four of ours on four sides against two: allowed")
	buddy.state = Unit.State.WITHDRAWN
	buddy.player_known_state = Unit.State.WITHDRAWN
	# 5. numbers without the sides: three of ours all on one side
	west.global_position = o + m(300, 40)
	north.global_position = o + m(300, -40)
	south.global_position = o + m(330, 0)
	check(not bm._player_assault_allowed(east, foe), "Three of ours on the same side: numbers, but no sides held")
	west.global_position = o + m(-300, 0)
	north.global_position = o + m(0, -300)
	south.global_position = o + m(0, 300)

	# 6. what it does: it takes it up in the end, closing to inside grenade range; and not under an order of the player's
	seed(1717)
	var took := false
	var minutes := 0
	while minutes < 400 and not took:
		bm.scenario_elapsed_time += 61.0
		minutes += 1
		bm._update_friendly_assaults()
		for s in [east, west, north, south]:
			if s.assaulting:
				took = true
	check(took, "With the numbers and the sides, one of ours closes on it in the end (after %d minutes)" % minutes)
	var mover: Unit = null
	for s in [east, west, north, south]:
		if s.assaulting:
			mover = s
	if mover != null:
		var goal_m: float = mover.move_target.distance_to(foe.global_position) / GameConfig.PIXELS_PER_METER
		check(mover.has_move_target and goal_m <= GameConfig.CLOSE_RANGE_COVER_DEFEAT_M, "...to inside grenade range (%.0f m)" % goal_m)
		check(int(bm._assaults_started.get(Unit.Team.PLAYER, 0)) >= 1, "...and it is counted")
	for s in [east, west, north, south]:
		s.assaulting = false
		s.has_move_target = false
	var blocked := true
	for order in ["move", "pinned", "fall back", "hold"]:
		for s in [east, west, north, south]:
			s.pinned = false
			s.has_move_target = false
			bm._fall_back_orders.erase(s)
			bm._risk_holds.erase(s)
		match order:
			"move":
				for s in [east, west, north, south]:
					s.has_move_target = true
					s.move_target = s.position + m(50)
			"pinned":
				for s in [east, west, north, south]:
					s.pinned = true
			"fall back":
				for s in [east, west, north, south]:
					bm._fall_back_orders[s] = {"x": 0.0}
			"hold":
				for s in [east, west, north, south]:
					bm._risk_holds[s] = true
		for i in 200:
			bm.scenario_elapsed_time += 61.0
			bm._update_friendly_assaults()
			for s in [east, west, north, south]:
				if s.assaulting and order != "move":
					blocked = false
		for s in [east, west, north, south]:
			if s.assaulting and not (order == "move"):
				blocked = false
			s.assaulting = false
	check(blocked, "Not while pinned, under a fall-back, a hold, or already moving on an order")
	cleanup(c)

	print("Player assault tests: %d failures" % failures)
	quit(1 if failures else 0)
