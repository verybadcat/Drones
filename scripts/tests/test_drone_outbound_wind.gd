extends SceneTree
## Direct user requests: a drone "moving into the wind and struggling" on an
## OUTBOUND search leg (it flew a fixed 14 m/s airspeed against ~11 m/s of
## headwind, making ~3 m/s over the ground toward a cell ~18 km away), so:
## (1) let outbound/search legs use the same Sport-mode speed-up the flight
## home already had, and (2) skip sweep targets "too far upwind for the
## battery". "The key metric here is battery expended per ground meter
## traveled. The speed decision should be based on that."
##
## Run: godot --headless --path . --script scripts/tests/test_drone_outbound_wind.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(meters: float) -> float:
	return meters * GameConfig.PIXELS_PER_METER

## Wind blowing FROM `from_deg` at `wind10` m/s (10 m), no gust noise, dry.
func pinned(wind10: float, from_deg: float = 270.0) -> Weather:
	var w := Weather.new()
	w.wind_speed_10m = wind10
	w.wind_from_deg = from_deg
	w.temperature_c = 10.0
	w._gust_z = 0.0
	w.rng.seed = 1
	return w

func wind_at_300(mps: float) -> float:
	return mps / pow(30.0, 0.14)

## One battle: drone team at x=-800 m, an active drone 1300 m east of it.
func make_battle(w: Weather, charge: float = 0.9):
	Weather.current = w
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.weather = w
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	bm.drone_team = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2(m(-800), m(1500)))
	bm.player_units.append(bm.drone_team)
	var d: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(m(500), m(1500)))
	bm.player_units.append(d)
	d.move_speed = GameConfig.DRONE_CRUISE_SPEED
	d.drone_battery_charge = charge
	bm.active_drone = d
	return bm

func run() -> void:
	test_best_airspeed_minimizes_battery_per_ground_meter()
	test_the_same_distance_costs_more_upwind()
	test_the_drain_follows_the_airspeed_actually_flown()
	test_a_search_leg_flies_the_best_airspeed_for_its_own_direction()
	test_a_target_too_far_upwind_for_the_battery_is_not_affordable()
	test_with_nothing_affordable_the_drone_heads_home()
	test_the_snapshot_reports_the_airspeed()
	print("Drone outbound wind tests: %d failures" % failures)
	quit(1 if failures else 0)


## Recompute the battery-per-ground-meter cost of every candidate airspeed the
## slow way and check the chosen one against it.
func test_best_airspeed_minimizes_battery_per_ground_meter() -> void:
	var bm = make_battle(pinned(wind_at_300(13.0)))
	var west := Vector2.LEFT # into a wind FROM the west
	var chosen: float = bm._drone_best_airspeed(west)
	var step: float = GameConfig.DRONE_RETURN_SPEED_STEP_MPS * GameConfig.PIXELS_PER_METER
	var costs: Dictionary = {}
	var best := INF
	var speed: float = GameConfig.DRONE_CRUISE_SPEED
	while speed <= GameConfig.DRONE_MAX_AIRSPEED + 0.0001:
		var cost: float = GameConfig.drone_power_factor(speed) / bm._drone_ground_speed(speed, west, false)
		costs[speed] = cost
		best = minf(best, cost)
		speed += step
	var chosen_cost: float = GameConfig.drone_power_factor(chosen) / bm._drone_ground_speed(chosen, west, false)
	check(chosen_cost <= best * (1.0 + GameConfig.DRONE_RETURN_ENERGY_TOLERANCE) + 1e-9, "The chosen airspeed must be within the tolerance of the cheapest battery per ground meter (%.4f vs best %.4f)" % [chosen_cost, best])
	for s in costs:
		if s < chosen - 0.0001:
			check(costs[s] > best * (1.0 + GameConfig.DRONE_RETURN_ENERGY_TOLERANCE), "...and it is the SLOWEST such speed: %.1f m/s would also have been good enough" % (s / GameConfig.PIXELS_PER_METER))
	check(chosen > GameConfig.DRONE_CRUISE_SPEED * 1.3, "Into a 13 m/s headwind that is well above cruise (%.1f m/s)" % (chosen / GameConfig.PIXELS_PER_METER))
	check(is_equal_approx(bm._drone_best_airspeed(Vector2.RIGHT), GameConfig.DRONE_CRUISE_SPEED), "Downwind, faster isn't considered: cruise")
	var crosswind: float = bm._drone_best_airspeed(Vector2.UP)
	check(crosswind > GameConfig.DRONE_CRUISE_SPEED and crosswind < chosen, "A pure crosswind sits between the two (%.1f m/s)" % (crosswind / GameConfig.PIXELS_PER_METER))
	check(is_equal_approx(make_battle(pinned(0.0))._drone_best_airspeed(Vector2.LEFT), GameConfig.DRONE_CRUISE_SPEED), "No wind: cruise, in any direction")


func test_the_same_distance_costs_more_upwind() -> void:
	var bm = make_battle(pinned(wind_at_300(11.0)))
	var here: Vector2 = bm.active_drone.global_position
	var upwind: float = bm._drone_leg_charge(here, here + Vector2(-m(4000), 0))
	var downwind: float = bm._drone_leg_charge(here, here + Vector2(m(4000), 0))
	check(upwind > downwind * 2.0, "4 km into an 11 m/s headwind must cost far more battery than 4 km with the wind (%.3f vs %.3f)" % [upwind, downwind])
	var calm = make_battle(pinned(0.0))
	var expected: float = m(4000) / GameConfig.DRONE_CRUISE_SPEED / calm._drone_full_charge_flight_time()
	check(absf(calm._drone_leg_charge(here, here + Vector2(-m(4000), 0)) - expected) < 1e-6, "In still air a leg costs distance / cruise speed / full-charge flight time")
	check(is_equal_approx(calm._drone_leg_charge(here, here), 0.0), "A leg of no length costs nothing")


## The bug this test came from: a freshly launched drone carries a generic unit
## default move_speed that is not an airspeed, and the drain (which runs before
## the first speed is set) treated it as one -- draining the battery at once.
func test_the_drain_follows_the_airspeed_actually_flown() -> void:
	var bm = make_battle(pinned(0.0))
	var d: Unit = bm.active_drone
	var full: float = bm._drone_full_charge_flight_time()
	check(is_equal_approx(bm._drone_drain_per_second(d), 1.0 / full), "At cruise the drain is the plain rate")
	d.move_speed = GameConfig.DRONE_MAX_AIRSPEED
	check(is_equal_approx(bm._drone_drain_per_second(d), GameConfig.drone_power_factor(GameConfig.DRONE_MAX_AIRSPEED) / full), "At Sport speed it drains faster, by the power model")
	d.move_speed = 123456.0 # a leftover default, not an airspeed
	check(bm._drone_drain_per_second(d) <= GameConfig.drone_power_factor(GameConfig.DRONE_MAX_AIRSPEED) / full + 1e-9, "A meaningless speed must never drain faster than the real maximum")
	d.move_speed = 0.0
	check(is_equal_approx(bm._drone_drain_per_second(d), 1.0 / full), "No speed yet counts as cruise")
	# ...and through the real update: a whole tick at Sport speed spends exactly that.
	d.move_speed = GameConfig.DRONE_MAX_AIRSPEED
	d.drone_battery_charge = 0.9
	bm._update_active_drone(10.0)
	check(absf((0.9 - d.drone_battery_charge) - 10.0 * GameConfig.drone_power_factor(GameConfig.DRONE_MAX_AIRSPEED) / full) < 1e-6, "The search drone's tick drains at the airspeed it was flying, got %.5f" % (0.9 - d.drone_battery_charge))
	# A drone launched for real starts at cruise, not at a unit default.
	var launcher = make_battle(pinned(0.0))
	launcher.active_drone = null
	launcher._drones_ready.clear()
	launcher._drones_ready.append(1.0)
	launcher._launch_drone()
	check(is_equal_approx(launcher.active_drone.move_speed, GameConfig.DRONE_CRUISE_SPEED), "A freshly launched drone flies at cruise speed")


## Whatever leg the search drone picks, it flies it at the best airspeed for
## THAT direction -- checked over several wind directions and starting
## points, and it must actually go faster than cruise on some of them.
func test_a_search_leg_flies_the_best_airspeed_for_its_own_direction() -> void:
	var boosted_somewhere := false
	for from_deg in [270.0, 0.0, 90.0, 180.0]:
		for start_x in [-400.0, 500.0, 1500.0]:
			var bm = make_battle(pinned(wind_at_300(11.0), from_deg), 0.95)
			bm.active_drone.global_position = Vector2(m(start_x), m(1500))
			bm._update_active_drone(1.0)
			var d: Unit = bm.active_drone
			if d == null:
				continue # sent home (covered elsewhere)
			var expected: float = bm._drone_airspeed_toward(d.global_position, d.move_target)
			check(is_equal_approx(d.move_speed, expected), "The leg toward %s must be flown at the best airspeed for that bearing (%.1f vs %.1f m/s, wind from %d deg)" % [d.move_target, d.move_speed / GameConfig.PIXELS_PER_METER, expected / GameConfig.PIXELS_PER_METER, from_deg])
			if d.move_speed > GameConfig.DRONE_CRUISE_SPEED * 1.05:
				boosted_somewhere = true
	check(boosted_somewhere, "Into a real headwind at least one search leg must be flown faster than cruise")


## The round trip has one headwind leg and one tailwind leg whichever way the
## target lies, and the headwind leg costs far more than the tailwind leg
## saves -- so what the battery can afford SHRINKS in a strong wind. The same
## cell, on the same battery, is reachable-and-back in calm air but not in an
## 11 m/s wind: exactly the "too far upwind for the battery it has" case.
func round_trip_need(bm, target: Vector2) -> float:
	var here: Vector2 = bm.active_drone.global_position
	var home: Vector2 = bm.drone_team.global_position
	return bm._drone_leg_charge(here, target) + bm._drone_leg_charge(target, home) + bm._drone_arrival_reserve_charge()


func test_a_target_too_far_upwind_for_the_battery_is_not_affordable() -> void:
	var here := Vector2(m(500), m(1500))
	var targets: Array[Vector2] = [here + Vector2(m(5000), 0), here + Vector2(-m(5000), 0), here + Vector2(0, m(5000))]
	# Weather.current is one static (one battle at a time, as in the real
	# game), so each weather is switched in explicitly before it is measured.
	var calm_w: Weather = pinned(0.0)
	var windy_w: Weather = pinned(wind_at_300(11.0))
	var bm = make_battle(calm_w)
	Weather.current = calm_w
	var calm_need: Array[float] = []
	for t in targets:
		calm_need.append(round_trip_need(bm, t))
	Weather.current = windy_w
	for i in targets.size():
		var windy_need: float = round_trip_need(bm, targets[i])
		check(windy_need > calm_need[i] * 1.2, "The round trip to %s must cost clearly more in an 11 m/s wind (%.3f vs %.3f calm)" % [targets[i], windy_need, calm_need[i]])
		var between: float = (calm_need[i] + windy_need) / 2.0
		bm.active_drone.drone_battery_charge = between
		Weather.current = windy_w
		check(bm._drone_can_afford_target(bm.active_drone, targets[i]) == false, "On a battery that covers it in calm air, %s is NOT affordable in the wind" % targets[i])
		Weather.current = calm_w
		check(bm._drone_can_afford_target(bm.active_drone, targets[i]), "...while the same battery does cover it in calm air")
		Weather.current = windy_w
		bm.active_drone.drone_battery_charge = windy_need + 0.01
		check(bm._drone_can_afford_target(bm.active_drone, targets[i]), "With enough battery it is affordable in the wind too")
	bm.active_drone.drone_battery_charge = 1.0
	check(not bm._drone_can_afford_target(bm.active_drone, here + Vector2(m(40000), 0)), "Somewhere beyond the airframe's range is never affordable")


func test_with_nothing_affordable_the_drone_heads_home() -> void:
	# A nearly flat battery: every sweep cell needs more than it has.
	var low = make_battle(pinned(0.0), 0.10)
	low.active_drone.global_position = low.drone_team.global_position
	var d: Unit = low.active_drone
	low._update_active_drone(1.0)
	check(low._drone_search_exhausted, "With no routine target affordable the search is exhausted")
	check(low._drone_pilot_reasoning.get("tier", "") == "Nothing reachable", "...and the pilot reasoning says so, got %s" % [low._drone_pilot_reasoning])
	check(low.active_drone == null and low.returning_drones.has(d), "...and the drone is sent home rather than crawling toward a cell it can't afford")

	# A healthy battery: plenty is affordable, so it keeps searching.
	var healthy = make_battle(pinned(0.0), 0.95)
	healthy.active_drone.global_position = healthy.drone_team.global_position
	var e: Unit = healthy.active_drone
	healthy._update_active_drone(1.0)
	check(not healthy._drone_search_exhausted and healthy.active_drone == e and e.has_move_target, "With a healthy battery it keeps searching")


func test_the_snapshot_reports_the_airspeed() -> void:
	var bm = make_battle(pinned(0.0))
	bm.active_drone.move_speed = 17.0 * GameConfig.PIXELS_PER_METER
	var snap: Dictionary = bm.drone_pilot_debug_snapshot()
	check(snap.has("drone_airspeed_mps") and is_equal_approx(snap.drone_airspeed_mps, 17.0), "The drone debug snapshot reports its airspeed, got %s" % [snap.get("drone_airspeed_mps")])
