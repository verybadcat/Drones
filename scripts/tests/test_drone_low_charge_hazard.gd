extends SceneTree
## Direct user decision, after the formula was worked out: "Yes, let's do that." A drone with a nearly empty pack has an added failure rate,
## because a sagging pack can cut out under load while still showing some charge (more so in cold and wind). Below
## Weather.DRONE_LOW_CHARGE_ONSET (0.20, higher in the cold) the rate is 0.15 per flight-minute at empty times the square of the shortfall
## times the load (the wind and cold multipliers, capped at 4). And a drone is held to land with GameConfig.DRONE_ARRIVAL_CHARGE_RESERVE (12%)
## in hand, instead of the old few percent, so that routine sorties do not run through it.
##
## Run: godot --headless --path . --script scripts/tests/test_drone_low_charge_hazard.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func calm(temperature_c: float = 10.0, wind: float = 0.0) -> Weather:
	var w := Weather.new()
	w.wind_speed_10m = wind
	w.temperature_c = temperature_c
	w._gust_z = 0.0
	w.rng.seed = 11
	return w

func run() -> void:
	var peak: float = GameConfig.DRONE_ALTITUDE_M
	var w: Weather = calm()
	var lam: float = Weather.DRONE_LOW_CHARGE_FAILURES_PER_MIN_AT_EMPTY
	var onset: float = Weather.DRONE_LOW_CHARGE_ONSET
	# 1. the formula, in calm weather at 10 C
	check(is_zero_approx(w.drone_low_charge_hazard_per_minute(1.0, peak)) and is_zero_approx(w.drone_low_charge_hazard_per_minute(onset, peak)) and is_zero_approx(w.drone_low_charge_hazard_per_minute(0.5, peak)), "No added hazard at or above the onset")
	check(is_equal_approx(w.drone_low_charge_hazard_per_minute(0.10, peak), lam * 0.25), "At 10%% it is a quarter of the empty rate (%.4f)" % w.drone_low_charge_hazard_per_minute(0.10, peak))
	check(is_equal_approx(w.drone_low_charge_hazard_per_minute(0.05, peak), lam * 0.5625), "At 5%% it is 0.5625 of it (%.4f)" % w.drone_low_charge_hazard_per_minute(0.05, peak))
	check(is_equal_approx(w.drone_low_charge_hazard_per_minute(0.0, peak), lam), "At empty it is the full rate (%.3f per minute)" % w.drone_low_charge_hazard_per_minute(0.0, peak))
	var previous := -1.0
	var rising := true
	for c in [0.2, 0.15, 0.1, 0.05, 0.02, 0.0]:
		var h: float = w.drone_low_charge_hazard_per_minute(c, peak)
		if h < previous:
			rising = false
		previous = h
	check(rising, "...rising as the charge falls")

	# 2. cold raises the onset and the load
	var cold: Weather = calm(-5.0)
	check(is_equal_approx(cold.drone_low_charge_onset(), onset + 0.10), "At -5 C the onset is 0.10 higher (%.2f)" % cold.drone_low_charge_onset())
	check(cold.drone_low_charge_hazard_per_minute(0.25, peak) > 0.0 and w.drone_low_charge_hazard_per_minute(0.25, peak) == 0.0, "...so a drone at 25%% is already in it in the cold and not in mild weather")
	check(cold.drone_low_charge_hazard_per_minute(0.10, peak) > w.drone_low_charge_hazard_per_minute(0.10, peak) * 2.0, "...and the same charge is worse in the cold (%.3f against %.3f)" % [cold.drone_low_charge_hazard_per_minute(0.10, peak), w.drone_low_charge_hazard_per_minute(0.10, peak)])
	# the load is capped
	var gale: Weather = calm(-10.0, 14.0)
	check(gale.drone_low_charge_hazard_per_minute(0.0, peak) <= lam * Weather.DRONE_LOW_CHARGE_LOAD_CAP + 1e-9, "The load multiplier is capped (%.2f per minute at most %.2f)" % [gale.drone_low_charge_hazard_per_minute(0.0, peak), lam * Weather.DRONE_LOW_CHARGE_LOAD_CAP])

	# 3. the return reserve
	Weather.current = calm()
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	var team: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2.ZERO)
	bm.player_units.append(team)
	bm.drone_team = team
	check(is_equal_approx(bm._drone_arrival_reserve_charge(), GameConfig.DRONE_ARRIVAL_CHARGE_RESERVE + GameConfig.DRONE_LANDING_CHARGE_COST), "A drone is held to land with %d%% in hand (reserve %.3f)" % [int(GameConfig.DRONE_ARRIVAL_CHARGE_RESERVE * 100.0), bm._drone_arrival_reserve_charge()])
	check(GameConfig.DRONE_ARRIVAL_CHARGE_RESERVE >= 0.10, "...about 12%, not the old few percent")
	var d: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2.ZERO)
	bm.player_units.append(d)
	d.drone_battery_charge = bm._drone_arrival_reserve_charge() + 0.01
	check(not bm._drone_should_rtb(d) and bm._drone_time_until_rtb(d) > 0.0, "Just above the reserve over the team it is not yet time to go home")
	d.drone_battery_charge = bm._drone_arrival_reserve_charge() - 0.01
	check(bm._drone_should_rtb(d), "...and just below it, it is")

	# 4. the failures, in the real loop: drones at 5% lose power at about the stated rate, those at 30% do not
	var trials := 2500
	var lost_low := 0
	var lost_ok := 0
	Weather.current = calm()
	bm.weather = Weather.current
	bm.weather.rng.seed = 77
	for i in trials:
		var low: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2.ZERO)
		bm.player_units.append(low)
		low.drone_battery_charge = 0.05
		bm.returning_drones.append(low)
		var fine: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2.ZERO)
		bm.player_units.append(fine)
		fine.drone_battery_charge = 0.30
		bm.returning_drones.append(fine)
		bm._update_drone_weather(60.0)
		if not bm.returning_drones.has(low):
			lost_low += 1
		else:
			bm.returning_drones.erase(low)
			bm.player_units.erase(low)
			low.free()
		if not bm.returning_drones.has(fine):
			lost_ok += 1
		else:
			bm.returning_drones.erase(fine)
			bm.player_units.erase(fine)
			fine.free()
	var expected: float = 1.0 - exp(-lam * 0.5625)
	var rate: float = float(lost_low) / float(trials)
	check(rate > expected * 0.7 and rate < expected * 1.3, "A drone at 5%% charge is lost about %.1f%% of minutes (%.1f%% in %d trials)" % [expected * 100.0, rate * 100.0, trials])
	check(lost_ok <= 3, "...while one at 30%% almost never is (%d of %d)" % [lost_ok, trials])
	check(bm._drones_lost_to_low_battery > 0 and bm._drones_lost_to_low_battery <= lost_low + lost_ok, "...and the losses are counted as battery losses (%d)" % bm._drones_lost_to_low_battery)
	check(bm.weather_debug_snapshot().get("drones_lost_to_low_battery", -1) == bm._drones_lost_to_low_battery, "The weather snapshot reports them")
	bm.combat_log.free()
	bm.free()
	print("Drone low-charge hazard tests: %d failures" % failures)
	quit(1 if failures else 0)
