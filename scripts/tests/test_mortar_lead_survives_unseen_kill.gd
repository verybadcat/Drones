extends SceneTree
## Direct user report from a live battle: "It looks like our drone was going towards the enemy mortar. We
## hit the enemy mortar, and the drone immediately went towards a squad. The problem here is that the
## drone team should not have known that we hit the enemy mortar. No one saw it. In that circumstance, the
## drone should still continue towards the mortar." Then, generalized: "We need a layer that tracks what
## each side knows about the other side. Every unit should act based on what it knows. It cannot act on
## information that it is not aware of."
##
## Cause: _known_enemy_mortar_lead's two STALE-lead branches (a fire-detection trace, a last-known
## position) filtered on the mortar's real, current state (Unit.is_targetable_state) rather than what the
## player actually knows about it (player_known_state) — so the instant an unseen shot killed it, ground
## truth flipped and the lead vanished the very next tick, even though nothing told the player. Fixed via
## Unit.is_targetable_state_known_to_player(). The enemy's own mirror (_known_friendly_mortar_position,
## hunting OUR mortar) had the identical gap and is fixed the same way (enemy_known_state).
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_lead_survives_unseen_kill.gd
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

func run() -> void:
	test_a_fresh_fire_detection_lead_survives_an_unseen_kill()
	test_a_last_known_position_lead_survives_an_unseen_kill()
	test_the_lead_does_drop_once_the_player_actually_sees_it_dead()
	test_the_enemys_own_lead_on_our_mortar_has_the_same_protection()
	test_the_drone_keeps_hunting_after_an_unseen_kill_end_to_end()
	print("Mortar lead knowledge tests: %d failures" % failures)
	quit(1 if failures else 0)


## An enemy mortar just fired (a fresh, unexpired fire-detection trace), was never actually seen, and then
## is destroyed by a shot nobody observed: the lead must still be there.
func test_a_fresh_fire_detection_lead_survives_an_unseen_kill() -> void:
	var bm = make_battle()
	var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4700, 1000))
	bm.enemy_units.append(em)
	em.is_visible = false
	bm._last_detected_mortar_fire[em] = {"position": em.global_position, "time": 100.0}
	bm.scenario_elapsed_time = 105.0
	em.state = Unit.State.DESTROYED # the unseen kill: ground truth changes, the player's knowledge does not
	var lead: Dictionary = bm._known_enemy_mortar_lead()
	check(lead.get("unit", null) == em, "The fire-detection lead survives a kill nobody witnessed")
	cleanup(bm)


## The same, off a last-known SIGHTING (player_known_position) rather than a fire-detection trace.
func test_a_last_known_position_lead_survives_an_unseen_kill() -> void:
	var bm = make_battle()
	var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4700, 1000))
	bm.enemy_units.append(em)
	em.is_visible = true
	bm._update_player_intel() # a real sighting, recorded
	em.is_visible = false
	em.state = Unit.State.DESTROYED # unseen kill after losing contact
	var lead: Dictionary = bm._known_enemy_mortar_lead()
	check(lead.get("unit", null) == em, "The last-known-position lead survives a kill nobody witnessed too")
	cleanup(bm)


## Once the player genuinely sees the wreck (or the empty position where it was) and intel updates, the
## lead correctly goes away — this is about missing knowledge, not permanent immortality.
func test_the_lead_does_drop_once_the_player_actually_sees_it_dead() -> void:
	var bm = make_battle()
	var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4700, 1000))
	bm.enemy_units.append(em)
	em.is_visible = false
	bm._last_detected_mortar_fire[em] = {"position": em.global_position, "time": 100.0}
	bm.scenario_elapsed_time = 105.0
	em.state = Unit.State.DESTROYED
	check(not bm._known_enemy_mortar_lead().is_empty(), "Set-up: the lead is there while unseen")
	em.is_visible = true
	bm._update_player_intel() # the player now actually sees it (a wreck, or is otherwise informed)
	check(bm._known_enemy_mortar_lead().is_empty() or bm._known_enemy_mortar_lead().get("unit", null) != em, "Once actually observed dead, the lead is gone")
	cleanup(bm)


## The exact mirror on the enemy's side, hunting the friendly mortar.
func test_the_enemys_own_lead_on_our_mortar_has_the_same_protection() -> void:
	var bm = make_battle()
	var pm: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(500, 1200))
	bm.player_units.append(pm)
	pm.is_visible = false
	bm._last_detected_mortar_fire[pm] = {"position": pm.global_position, "time": 100.0}
	bm.scenario_elapsed_time = 105.0
	pm.state = Unit.State.DESTROYED # the enemy never saw this happen
	check(not is_inf(bm._known_friendly_mortar_position().x), "The enemy's own lead on our mortar survives a kill it did not witness")
	pm.is_visible = true
	bm._update_enemy_intel()
	check(is_inf(bm._known_friendly_mortar_position().x), "...but goes away once the enemy actually sees it dead")
	cleanup(bm)


## End to end, the reported scenario: the drone is hunting a mortar off a fire-detection lead; the mortar
## is killed unseen; a visible dangerous squad is right there tempting the search away. The drone must keep
## going for the mortar's last-known position, not the squad.
func test_the_drone_keeps_hunting_after_an_unseen_kill_end_to_end() -> void:
	var bm = make_battle()
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	var friendly: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(1400, 1800))
	bm.player_units.append(friendly)
	bm.drone_team = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, m(-800, 1500))
	bm.player_units.append(bm.drone_team)
	var d: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, m(3000, 900))
	bm.player_units.append(d)
	d.move_speed = GameConfig.DRONE_CRUISE_SPEED
	d.drone_battery_charge = 0.9
	bm.active_drone = d
	var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4700, 1000))
	bm.enemy_units.append(em)
	em.is_visible = false
	bm._last_detected_mortar_fire[em] = {"position": em.global_position, "time": 100.0}
	bm.scenario_elapsed_time = 105.0
	# A tempting, visible, close-to-our-forces squad, right next to the friendly squad.
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(1450, 1800))
	bm.enemy_units.append(squad)
	squad.is_visible = true
	var before: Vector2 = bm._drone_search_target()
	check(before.distance_to(em.global_position) < 1.0, "Set-up: before the kill, the drone is oriented on the mortar's lead")

	em.state = Unit.State.DESTROYED # the unseen kill
	var after: Vector2 = bm._drone_search_target()
	check(after.distance_to(em.global_position) < 1.0, "After an unseen kill, the drone still goes for the mortar's last-known position, not the squad (target %s, tier %s)" % [after / GameConfig.PIXELS_PER_METER, str(bm._drone_pilot_reasoning.get("tier", ""))])
	check(bm._drone_pilot_reasoning.get("tier", "") != "Tracking dangerous squad", "...and does not read as tracking the squad")

	# Once actually seen dead, the search correctly moves on.
	em.is_visible = true
	bm._update_player_intel()
	em.is_visible = false
	var moved_on: Vector2 = bm._drone_search_target()
	check(moved_on.distance_to(em.global_position) > 1.0 or bm._drone_pilot_reasoning.get("tier", "") != "Fresh mortar fire-detection lead", "Once actually seen dead, the drone no longer treats it as a lead")
	cleanup(bm)
