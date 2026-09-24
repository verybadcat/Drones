extends SceneTree
## Direct user reports/requests, in order: drones in a strong wind "were
## unable to reach the station" (they crawled home at ~1.4 m/s against a
## headwind near their fixed cruise speed); then "let a homebound drone use up
## to 21 m/s" (a real pilot switches to Sport mode), "base the turn-home
## decision on mean wind, not the instantaneous gust", "the other adjustment
## the pilot would make is to fly lower if that means less wind", and "return
## flight should absolutely drain -- if the battery runs out, the drone is lost"
## (found along the way: a returning drone never drained AT ALL before).
##
## Run: godot --headless --path . --script scripts/tests/test_drone_return_flight_in_wind.gd
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

## Everything pinned: wind blows FROM the west at `wind10` m/s (10 m), no gust
## noise unless asked, dry, mild. The drone team sits WEST of the drone below,
## so a west wind is a headwind on the way home.
func pinned(wind10: float, gust_z: float = 0.0) -> Weather:
	var w := Weather.new()
	w.wind_speed_10m = wind10
	w.wind_from_deg = 270.0
	w.temperature_c = 10.0
	w._gust_z = gust_z
	w.rng.seed = 1
	return w

func wind_at_300(mps: float) -> float:
	return mps / pow(30.0, 0.14) # the 10 m wind that gives `mps` at 300 m

func make_battle(w: Weather, drone_distance_m: float = 1300.0):
	Weather.current = w
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.weather = w
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	bm.drone_team = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2(m(-800), m(1500)))
	bm.player_units.append(bm.drone_team)
	var d: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(m(-800.0 + drone_distance_m), m(1500)))
	bm.player_units.append(d)
	bm.active_drone = d
	return bm

func run() -> void:
	test_power_model_is_fitted_to_djis_two_published_points()
	test_still_air_return_stays_at_cruise()
	test_a_headwind_return_uses_sport_mode_and_actually_makes_progress()
	test_pilot_flies_lower_when_the_wind_aloft_is_strong()
	test_turn_home_is_planned_on_mean_wind_not_the_gust()
	test_headwind_makes_the_drone_turn_home_sooner()
	test_return_flight_drains_and_a_dry_battery_loses_the_drone()
	test_a_drone_really_flies_home_faster_and_arrives_in_a_headwind()
	print("Drone return flight in wind tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_power_model_is_fitted_to_djis_two_published_points() -> void:
	check(is_equal_approx(GameConfig.drone_power_factor(GameConfig.DRONE_CRUISE_SPEED), 1.0), "Drain at cruise speed is the reference rate")
	var endurance_factor: float = GameConfig.drone_power_factor(GameConfig.DRONE_ENDURANCE_TEST_SPEED_MPS * GameConfig.PIXELS_PER_METER)
	# DJI: 46 min at 9 m/s vs 35.7 min at 14 m/s -> the 9 m/s drain is 35.7/46 of the cruise drain.
	var expected: float = GameConfig.DRONE_FULL_CHARGE_FLIGHT_TIME / GameConfig.DRONE_MAX_FLIGHT_TIME
	check(absf(endurance_factor - expected) < 0.001, "At DJI's 46-minute test speed the drain must match the published endurance (got %.3f, want %.3f)" % [endurance_factor, expected])
	var sport: float = GameConfig.drone_power_factor(GameConfig.DRONE_MAX_AIRSPEED)
	check(sport > 1.5 and sport < 2.0, "Sport-mode drain should be well above cruise but not absurd, got %.2fx" % sport)


func test_still_air_return_stays_at_cruise() -> void:
	var bm = make_battle(pinned(0.0))
	check(is_equal_approx(bm._drone_return_airspeed(bm.active_drone.global_position), GameConfig.DRONE_CRUISE_SPEED),
		"With no wind a drone must fly home at plain cruise speed, not drift to some faster 'optimum'")
	var breeze = make_battle(pinned(2.0)) # (the previous battle is finished with by now)
	check(is_equal_approx(breeze._drone_return_airspeed(breeze.active_drone.global_position), GameConfig.DRONE_CRUISE_SPEED),
		"A light headwind isn't worth burning extra battery for either")


func test_a_headwind_return_uses_sport_mode_and_actually_makes_progress() -> void:
	var bm = make_battle(pinned(wind_at_300(13.0)))
	var pos: Vector2 = bm.active_drone.global_position
	var airspeed: float = bm._drone_return_airspeed(pos)
	check(airspeed > GameConfig.DRONE_CRUISE_SPEED * 1.3, "Into a 13 m/s headwind the drone must speed up well past cruise, got %.1f m/s" % (airspeed / GameConfig.PIXELS_PER_METER))
	check(airspeed <= GameConfig.DRONE_MAX_AIRSPEED + 0.001, "...but never past its real maximum")
	var dir: Vector2 = (bm.drone_team.global_position - pos).normalized()
	var at_cruise: float = bm._drone_ground_speed(GameConfig.DRONE_CRUISE_SPEED, dir, false)
	var boosted: float = bm._drone_ground_speed(airspeed, dir, false)
	check(at_cruise < GameConfig.DRONE_CRUISE_SPEED * 0.3, "Setup check: at plain cruise this headwind nearly stalls the drone (%.1f m/s over the ground)" % (at_cruise / GameConfig.PIXELS_PER_METER))
	check(boosted > at_cruise * 3.0, "Sport mode must turn a crawl into real progress (%.1f vs %.1f m/s over the ground)" % [boosted / GameConfig.PIXELS_PER_METER, at_cruise / GameConfig.PIXELS_PER_METER])


func test_pilot_flies_lower_when_the_wind_aloft_is_strong() -> void:
	var calm: Weather = pinned(wind_at_300(8.0))
	check(is_equal_approx(calm.drone_operating_altitude_m(), 300.0), "A wind within the rating aloft leaves the drone at its normal altitude")
	var windy: Weather = pinned(8.0) # the battle that prompted this: 8 m/s at 10 m, ~12.9 aloft
	var altitude: float = windy.drone_operating_altitude_m()
	check(altitude < 250.0 and altitude >= 60.0, "A wind above the rating aloft must bring the drone down, got %.0f m" % altitude)
	check(windy.wind_speed_at(altitude) <= Weather.DRONE_WIND_RATING_MPS + 0.01, "At the lower altitude the mean wind must be within the rating (%.2f m/s)" % windy.wind_speed_at(altitude))
	check(is_equal_approx(windy.drone_detection_scale(), altitude / 300.0), "Flying lower costs sensor range in proportion")
	check(is_equal_approx(pinned(30.0).drone_operating_altitude_m(), Weather.DRONE_MIN_ALTITUDE_M), "It never goes below the floor altitude")
	var wet: Weather = pinned(8.0)
	wet._wet = true
	wet.precip_mm_h = 0.5
	check(wet.drone_operating_altitude_m() <= minf(altitude, 130.0), "Rain and wind both want it low: it takes the lower of the two")
	check(pinned(8.0).drone_hazard_per_minute(altitude) < pinned(8.0).drone_hazard_per_minute(300.0), "The lower altitude must actually cut the wind hazard")


## Weather.current is one static per process (one battle at a time, as in the
## real game), so each battle is measured right after it's built, never
## side by side.
func rtb_spare_time(w: Weather) -> float:
	var bm = make_battle(w)
	bm.active_drone.drone_battery_charge = 0.6
	return bm._drone_time_until_rtb(bm.active_drone)


func test_turn_home_is_planned_on_mean_wind_not_the_gust() -> void:
	var no_gust: float = rtb_spare_time(pinned(wind_at_300(11.0), 0.0))
	var big_gust: float = rtb_spare_time(pinned(wind_at_300(11.0), 3.0))
	check(is_equal_approx(no_gust, big_gust), "The turn-home decision must not jump around with the instantaneous gust (%.1f vs %.1f s)" % [no_gust, big_gust])


func test_headwind_makes_the_drone_turn_home_sooner() -> void:
	var still: float = rtb_spare_time(pinned(0.0))
	var windy: float = rtb_spare_time(pinned(wind_at_300(12.5)))
	check(windy < still, "The same drone, same distance, same charge must have to turn for home sooner into a headwind (%.0f s of spare time vs %.0f s in still air)" % [windy, still])


func test_return_flight_drains_and_a_dry_battery_loses_the_drone() -> void:
	var bm = make_battle(pinned(0.0))
	var d: Unit = bm.active_drone
	bm.active_drone = null
	bm._send_drone_home(d)
	d.drone_battery_charge = 0.5
	bm._update_returning_drones(30.0)
	check(d.drone_battery_charge < 0.5, "A drone flying home must burn battery (it used to fly home free)")
	var drained: float = 0.5 - d.drone_battery_charge
	check(absf(drained - 30.0 / bm._drone_full_charge_flight_time()) < 0.001, "At cruise speed the drain is the plain per-second rate (got %.4f)" % drained)

	var lost_before: int = bm._drones_destroyed
	d.drone_battery_charge = 0.001
	bm._update_returning_drones(60.0)
	check(not bm.returning_drones.has(d), "A battery that runs out on the way home must remove the drone from the return flight")
	check(bm._drones_destroyed == lost_before + 1, "...and count it as a lost airframe")
	check(not bm.player_units.has(d), "...and take it off the field")


## The whole thing end to end: a real headwind, a real flight home, stepped
## the way the game steps it. At plain cruise this wind leaves the drone
## crawling (~2 m/s over the ground: ~11 minutes for these 1.3 km); in
## Sport mode it should be home in a few minutes, still with charge left.
func test_a_drone_really_flies_home_faster_and_arrives_in_a_headwind() -> void:
	var bm = make_battle(pinned(wind_at_300(12.5)))
	var d: Unit = bm.active_drone
	bm.active_drone = null
	bm._send_drone_home(d)
	d.drone_battery_charge = 0.9
	bm._update_returning_drones(1.0)
	check(d.move_speed > GameConfig.DRONE_CRUISE_SPEED * 1.3, "A homebound drone in a headwind must actually be flying at the boosted airspeed, not just plan to (%.1f m/s)" % (d.move_speed / GameConfig.PIXELS_PER_METER))
	var seconds := 0
	while d.has_move_target and seconds < 1200:
		bm._update_returning_drones(1.0)
		if not bm.returning_drones.has(d):
			break # battery ran dry on the way (caught below)
		bm._step_toward_target(d, 1.0)
		seconds += 1
	check(not d.has_move_target, "The drone must actually arrive home (still en route after %d s)" % seconds)
	check(seconds < 300, "Sport mode must get it home in a few minutes, not crawl (took %d s; plain cruise takes ~650 s)" % seconds)
	check(d.drone_battery_charge > 0.0, "...and it should arrive with charge left, not fall out of the sky (charge %.3f)" % d.drone_battery_charge)
	var cruise_rate_only: float = float(seconds) / bm._drone_full_charge_flight_time()
	check(0.9 - d.drone_battery_charge > cruise_rate_only * 1.2, "The faster flight must cost more battery than the same time at cruise would have (%.3f vs %.3f)" % [0.9 - d.drone_battery_charge, cruise_rate_only])
