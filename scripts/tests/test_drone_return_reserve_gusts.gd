extends SceneTree
## Direct user instruction: "The return reserve should account for gusts. If the pilot feels a mission is worth losing the drone, that's
## fine. But it should be a choice the pilot made, not something that fell out of a bad model." The turn-home point is planned on the mean
## wind raised by GameConfig.DRONE_PLAN_GUST_ALLOWANCE_SD standard deviations of the turbulence (the planning allowance of
## Weather.wind_velocity_mps), so a gust of that size does not eat the reserve: a drone that turns at its planned point and flies home in
## such a gust still touches down with GameConfig.DRONE_ARRIVAL_CHARGE_RESERVE in hand.
##
## Run: godot --headless --path . --script scripts/tests/test_drone_return_reserve_gusts.gd
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

## A steady wind from the west (so the flight home from the east is into it) of `wind10` m/s at 10 m, with the gust state fixed at `gust_z`.
func weather_with(wind10: float, gust_z: float) -> Weather:
	var w := Weather.new()
	w.wind_speed_10m = wind10
	w.wind_from_deg = 270.0
	w.temperature_c = 10.0
	w._gust_z = gust_z
	w.rng.seed = 3
	w.enabled = false
	return w

func run() -> void:
	var alt: float = weather_with(7.0, 0.0).drone_operating_altitude_m()

	# 1. the planning wind: the mean raised by the allowance; the wind actually flown in is the real gust, whatever is planned
	var w := weather_with(7.0, 1.5)
	var mean: float = w.wind_velocity_mps(alt, false).length()
	var planned: float = w.wind_velocity_mps(alt, false, 2.0).length()
	var ti: float = w.turbulence_intensity(alt)
	check(is_equal_approx(planned, mean * (1.0 + 2.0 * ti)), "The planning wind is the mean plus two standard deviations of turbulence (%.2f vs %.2f m/s)" % [planned, mean * (1.0 + 2.0 * ti)])
	check(is_equal_approx(w.wind_velocity_mps(alt, true, 2.0).length(), mean * w.gust_multiplier(alt)), "...and the actual wind the drone flies in is the real gust, whatever is planned")

	# 2. a drone that turned for home at the planned point, in a gust of 1.5 sigma: how much it touches down with
	var results := {}
	for allowance in [0.0, GameConfig.DRONE_PLAN_GUST_ALLOWANCE_SD]:
		Weather.current = weather_with(7.0, 1.5)
		var bm := BattleManager.new()
		root.add_child(bm)
		bm.set_process(false)
		bm.combat_log = Log.new()
		var team: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2(m(-800.0), m(1500.0)))
		bm.player_units.append(team)
		bm.drone_team = team
		var far: Vector2 = team.global_position + Vector2(m(3000.0), 0.0)
		var dir: Vector2 = (team.global_position - far).normalized()
		var airspeed: float = bm._drone_best_airspeed(dir)
		var plan_wind: Vector2 = Weather.current.wind_velocity_mps(alt, false, allowance) * GameConfig.PIXELS_PER_METER
		var actual_wind: Vector2 = Weather.current.wind_velocity_mps(alt, true) * GameConfig.PIXELS_PER_METER
		var distance: float = far.distance_to(team.global_position)
		var power: float = GameConfig.drone_power_factor(airspeed) / bm._drone_full_charge_flight_time()
		var planned_leg: float = distance / Weather.ground_speed(airspeed, dir, plan_wind) * power
		var actual_leg: float = distance / Weather.ground_speed(airspeed, dir, actual_wind) * power
		var charge_at_turn: float = planned_leg + bm._drone_arrival_reserve_charge()
		results[allowance] = charge_at_turn - actual_leg # what it touches down with, before the letdown
		bm.combat_log.free()
		bm.free()
	var touchdown_floor: float = GameConfig.DRONE_ARRIVAL_CHARGE_RESERVE + GameConfig.DRONE_LANDING_CHARGE_COST
	check(results[0.0] < touchdown_floor - 0.005, "Planned on the plain mean wind, a 1.5 sigma gust on the way home eats the reserve (touches down with %.1f%% against the planned %.1f%%)" % [results[0.0] * 100.0, touchdown_floor * 100.0])
	check(results[GameConfig.DRONE_PLAN_GUST_ALLOWANCE_SD] >= touchdown_floor - 0.0005, "With the allowance the reserve is intact in the same gust (%.1f%% against %.1f%%)" % [results[GameConfig.DRONE_PLAN_GUST_ALLOWANCE_SD] * 100.0, touchdown_floor * 100.0])

	# 3. the planner itself costs the leg home above the plain mean-wind cost
	Weather.current = weather_with(7.0, 0.0)
	var bm2 := BattleManager.new()
	root.add_child(bm2)
	bm2.set_process(false)
	bm2.combat_log = Log.new()
	var team2: Unit = bm2._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2(m(-800.0), m(1500.0)))
	bm2.player_units.append(team2)
	bm2.drone_team = team2
	var far2: Vector2 = team2.global_position + Vector2(m(3000.0), 0.0)
	var leg_planned: float = bm2._drone_leg_charge(far2, team2.global_position)
	var dir2: Vector2 = (team2.global_position - far2).normalized()
	var airspeed2: float = bm2._drone_best_airspeed(dir2)
	var mean_gs: float = Weather.ground_speed(airspeed2, dir2, Weather.current.wind_velocity_mps(alt, false) * GameConfig.PIXELS_PER_METER)
	var mean_leg: float = far2.distance_to(team2.global_position) / mean_gs * GameConfig.drone_power_factor(airspeed2) / bm2._drone_full_charge_flight_time()
	check(leg_planned > mean_leg * 1.02, "The leg home is costed above the plain mean-wind cost (%.1f%% against %.1f%%)" % [leg_planned * 100.0, mean_leg * 100.0])
	bm2.combat_log.free()
	bm2.free()

	print("Drone return reserve (gusts) tests: %d failures" % failures)
	quit(1 if failures else 0)
