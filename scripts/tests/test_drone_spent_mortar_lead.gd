extends SceneTree
## Direct user report, live: "right now the drone is hovering over a spot the enemy mortar fired from. But no enemy mortar is visible on
## screen. Not sure what is going on." The debug snapshot showed it: tier "Fresh mortar fire-detection lead", the drone exactly on the
## fix, the fix 498 s old (a lead is worth acting on for 600 s), and the enemy crew 284 m away in a wood: it fired, moved off, and a
## mortar in cover is only noticed within 250 m. The drone had nothing to do but wait out the lead.
##
## A lead the drone has flown to and watched for DRONE_LEAD_EMPTY_DWELL_S with the mortar not in view is now spent, and the drone looks
## around it a bit (user: "If the drone doesn't see the mortar, it would look around a bit"): the four points of a diamond 300 m out, each
## visited once, then back to the ordinary search. A newer fix of the same mortar is a new lead.
##
## Run: godot --headless --path . --script scripts/tests/test_drone_spent_mortar_lead.gd
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

func make_battle(drone_at: Vector2):
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(1500, 1500))
	bm.player_units.append(mortar)
	bm.drone_team = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, m(-800, 1500))
	bm.player_units.append(bm.drone_team)
	var d: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, drone_at)
	bm.player_units.append(d)
	d.move_speed = GameConfig.DRONE_CRUISE_SPEED
	d.drone_battery_charge = 0.9
	bm.active_drone = d
	return bm

func cleanup(bm) -> void:
	bm.combat_log.free()
	bm.free()

func tier(bm) -> String:
	return str(bm._drone_pilot_reasoning.get("tier", ""))

const LEAD_TIER := "Fresh mortar fire-detection lead"


func test_the_drone_does_not_hover_over_an_empty_fix() -> void:
	var fix := m(4000, 1500)
	var bm = make_battle(fix) # the drone is already on the fix
	bm.scenario_elapsed_time = 1000.0
	var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4290, 1560)) # moved off, out of sight
	bm.enemy_units.append(em)
	em.is_visible = false
	bm._last_detected_mortar_fire[em] = {"position": fix, "time": 900.0}
	bm._drone_search_target()
	check(tier(bm) == LEAD_TIER, "Set-up: the lead is worth going to, and the drone is on it (%s)" % tier(bm))
	bm.scenario_elapsed_time += BattleManager.DRONE_LEAD_EMPTY_DWELL_S * 0.5
	bm._drone_search_target()
	check(tier(bm) == LEAD_TIER, "Half the dwell time on, it is still watching the spot (%s)" % tier(bm))
	bm.scenario_elapsed_time += BattleManager.DRONE_LEAD_EMPTY_DWELL_S
	bm._drone_search_target()
	check(tier(bm) != LEAD_TIER, "Watched for the whole dwell time with nothing in view, the lead is spent and the drone moves on (%s)" % tier(bm))
	# It stays spent: asking again does not bring it back.
	bm.scenario_elapsed_time += 5.0
	bm._drone_search_target()
	check(tier(bm) != LEAD_TIER, "...and does not come back (%s)" % tier(bm))
	# A newer fix of the same mortar is a new lead.
	bm._last_detected_mortar_fire[em] = {"position": m(4290, 1560), "time": bm.scenario_elapsed_time - 1.0}
	bm._drone_search_target()
	check(tier(bm) == LEAD_TIER, "A fresh fix of the same mortar is worth going to again (%s)" % tier(bm))
	cleanup(bm)


func test_the_drone_looks_around_a_bit_then_moves_on() -> void:
	var fix := m(4000, 1500)
	var bm = make_battle(fix)
	bm.scenario_elapsed_time = 1000.0
	var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4290, 1560))
	bm.enemy_units.append(em)
	em.is_visible = false
	bm._last_detected_mortar_fire[em] = {"position": fix, "time": 900.0}
	bm._drone_search_target()
	bm.scenario_elapsed_time += BattleManager.DRONE_LEAD_EMPTY_DWELL_S * 1.5
	var looked: Array[Vector2] = []
	for i in 8:
		var target: Vector2 = bm._drone_search_target()
		if tier(bm) == "Looking around an empty mortar lead":
			looked.append(target)
			bm.active_drone.global_position = target # arrives
			bm.scenario_elapsed_time += 5.0
			bm._drone_search_target() # the arrival is noticed on the next look
		else:
			break
	check(looked.size() == 4, "It checks the four points around the empty fix, once each (%d visited)" % looked.size())
	var all_near := true
	for p in looked:
		if absf(p.distance_to(fix) - BattleManager.LEAD_SEARCH_RADIUS) > 1.0:
			all_near = false
	check(all_near, "...each 300 m from the fix")
	var seen := {}
	for p in looked:
		seen[str(p)] = true
	check(seen.size() == looked.size(), "...no point twice")
	check(tier(bm) != "Looking around an empty mortar lead", "Having looked, it goes back to its ordinary search (%s)" % tier(bm))
	cleanup(bm)


func test_a_lead_the_drone_has_not_reached_is_not_spent() -> void:
	var bm = make_battle(m(1000, 1500)) # 3 km from the fix
	bm.scenario_elapsed_time = 1000.0
	var fix := m(4000, 1500)
	var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4290, 1560))
	bm.enemy_units.append(em)
	em.is_visible = false
	bm._last_detected_mortar_fire[em] = {"position": fix, "time": 900.0}
	bm._drone_search_target()
	bm.scenario_elapsed_time += BattleManager.DRONE_LEAD_EMPTY_DWELL_S * 3.0
	bm._drone_search_target()
	check(tier(bm) == LEAD_TIER, "Time passing alone does not spend a lead the drone has not flown to (%s)" % tier(bm))
	cleanup(bm)


func test_a_mortar_in_view_is_never_spent() -> void:
	var fix := m(4000, 1500)
	var bm = make_battle(fix)
	bm.scenario_elapsed_time = 1000.0
	var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, fix + m(50, 0))
	bm.enemy_units.append(em)
	em.is_visible = true
	bm._update_player_intel()
	bm._last_detected_mortar_fire[em] = {"position": fix, "time": 900.0}
	bm._drone_search_target()
	bm.scenario_elapsed_time += BattleManager.DRONE_LEAD_EMPTY_DWELL_S * 3.0
	bm._drone_search_target()
	check(not bm._drone_checked_leads.has(em), "A mortar the player can see is not a spent lead")
	cleanup(bm)


func run() -> void:
	test_the_drone_does_not_hover_over_an_empty_fix()
	test_the_drone_looks_around_a_bit_then_moves_on()
	test_a_lead_the_drone_has_not_reached_is_not_spent()
	test_a_mortar_in_view_is_never_spent()
	print("Drone spent mortar lead tests: %d failures" % failures)
	quit(1 if failures else 0)
