extends SceneTree
## The dedicated audit the user asked for after the mortar-lead fix: "OK, after this, do the separate
## audit." A systematic sweep of battle_manager.gd for the same class of bug (a decision reading an
## opposing unit's real, current Unit.state instead of what that unit's own side actually knows —
## player_known_state / enemy_known_state) found six more confirmed instances, all in the player's drone
## reconnaissance logic (the enemy fields no such asset, so there is no mirror-image case for these six).
## Each is its own test here.
##
## Two related, deliberately UNCHANGED functions were found and considered, not missed: _mortar_existence_
## confidence and _enemy_mortars_in_range both read ground truth on purpose, and both say so in their own
## doc comments (an eventual "the enemy mortars are confirmed destroyed" briefing; standing doctrine that
## assumes counter-battery risk from the enemy fielding mortars AT ALL, not from a specific detection) —
## real, previously-reasoned exceptions, not this bug.
##
## Run: godot --headless --path . --script scripts/tests/test_knowledge_locality_audit.gd
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

func make_battle():
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	return bm

func cleanup(bm) -> void:
	bm.combat_log.free()
	bm.free()

## A sighted-and-believed-ACTIVE enemy squad, not currently visible, real ground truth `state`.
func sighted_squad(bm, pos_m: Vector2, real_state: Unit.State) -> Unit:
	var u: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, pos_m)
	bm.enemy_units.append(u)
	u.is_visible = true
	bm._update_player_intel() # records player_known_state = ACTIVE, the real state at the moment of sighting
	u.is_visible = false
	u.state = real_state # the unseen change: ground truth moves, knowledge does not
	return u

func run() -> void:
	test_enemy_squads_still_in_the_fight()
	test_squad_fire_order_watch_target()
	test_area_confirmed_clear()
	test_flank_watch_standing_priority()
	test_known_squad_danger_pressure()
	test_known_enemy_mortars_in_range()
	print("Knowledge locality audit tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_enemy_squads_still_in_the_fight() -> void:
	var bm = make_battle()
	var u := sighted_squad(bm, m(4000, 1500), Unit.State.DESTROYED) # unseen kill, still believed ACTIVE
	bm._recent_enemy_contacts[u] = {"position": u.global_position, "time": bm.scenario_elapsed_time} # "in view now or seen within" the recent-contact window
	check(bm._enemy_squads_still_in_the_fight(), "A squad the player still believes ACTIVE still counts as in the fight, even though it was destroyed unseen")
	cleanup(bm)


func test_squad_fire_order_watch_target() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(500, 1500))
	bm.player_units.append(mortar)
	bm.set_mortar_squad_fire_order(mortar, true)
	var u := sighted_squad(bm, m(700, 1500), Unit.State.DESTROYED) # in range, unseen kill
	bm.scenario_elapsed_time = 1.0 # inside DRONE_CONTACT_BONUS_EXPIRY of the sighting
	bm._recent_enemy_contacts[u] = {"position": u.global_position, "time": 0.0}
	var target: Dictionary = bm._squad_fire_order_watch_target()
	check(not target.is_empty(), "A squad still believed ACTIVE is still worth watching for the fire order, unseen kill notwithstanding")
	cleanup(bm)


func test_area_confirmed_clear() -> void:
	var bm = make_battle()
	sighted_squad(bm, m(4000, 1500), Unit.State.DESTROYED) # unseen kill, still believed ACTIVE
	check(not bm._area_confirmed_clear(m(4000, 1500)), "The area is not marked confirmed-clear off a kill nobody witnessed")
	cleanup(bm)


func test_flank_watch_standing_priority() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(500, 1500))
	bm.player_units.append(mortar)
	sighted_squad(bm, m(500, 1500) + m(600, 0) - m(500,1500), Unit.State.DESTROYED) # close enough to fade the standing priority, if counted
	var far_priority: float = GameConfig.DRONE_FLANK_WATCH_STANDING_PRIORITY
	check(bm._flank_watch_standing_priority() < far_priority, "A squad still believed nearby and ACTIVE fades the standing flank-watch priority, even after an unseen kill")
	cleanup(bm)


func test_known_squad_danger_pressure() -> void:
	var bm = make_battle()
	var friendly: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(1400, 1500))
	bm.player_units.append(friendly)
	sighted_squad(bm, m(1500, 1500), Unit.State.DESTROYED) # right next to a friendly, unseen kill
	check(bm._known_squad_danger_pressure() > 0.0, "Danger pressure from a squad still believed ACTIVE and close to our forces persists after an unseen kill")
	cleanup(bm)


func test_known_enemy_mortars_in_range() -> void:
	var bm = make_battle()
	sighted_squad(bm, Vector2.ZERO, Unit.State.ACTIVE) # placeholder to keep enemy_units non-trivial; unused
	var mortar_pos := m(4700, 1500)
	var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, mortar_pos)
	bm.enemy_units.append(em)
	em.is_visible = true
	bm._update_player_intel()
	em.is_visible = false
	em.state = Unit.State.DESTROYED # unseen kill
	check(bm._known_enemy_mortars_in_range(mortar_pos) == 1, "A mortar still believed ACTIVE still counts toward the known-density check after an unseen kill")
	cleanup(bm)
