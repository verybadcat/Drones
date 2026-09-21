extends SceneTree
## March weather (Weather): the climatology it draws from, its memory over
## time, and every effect it has on the battle — drone ground speed, return-to-
## base, cold, vision, failures, detection ranges and mortar wind bias.
##
## The numbers checked here are the ones the design doc lists: the SOURCED ones
## (ERA5 March 2013-2024, DJI manual) as measured statistics, the JUDGMENT ones
## (drone failure rates, rain thresholds, detection scales) as the exact values
## the user agreed to — so retuning one is a deliberate edit to both places.
##
## Run: godot --headless --path . --script scripts/tests/test_weather.gd
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

## A weather with everything pinned: wind blows FROM `from_deg` at `wind10`
## (10 m), no gust noise, no precipitation, mild temperature.
func pinned(wind10: float = 0.0, from_deg: float = 270.0, temp: float = 10.0) -> Weather:
	var w := Weather.new()
	w.wind_speed_10m = wind10
	w.wind_from_deg = from_deg
	w.temperature_c = temp
	w._gust_z = 0.0
	w.rng.seed = 1
	return w

func wet(w: Weather, mm_h: float, temp: float = 8.0) -> Weather:
	w._wet = true
	w.precip_mm_h = mm_h
	w.temperature_c = temp
	return w

func sortie_failure_chance(w: Weather, minutes: float, altitude: float = 300.0) -> float:
	return 1.0 - exp(-w.drone_hazard_per_minute(altitude) * minutes)


# ---------------------------------------------------------------- climatology

func test_climatology_matches_the_era5_march_data() -> void:
	seed(3)
	var n := 6000
	var speeds: Array[float] = []
	var wet_count := 0
	var temp_sum := 0.0
	var east_or_west := 0
	for i in n:
		var w := Weather.roll(i + 1000)
		speeds.append(w.wind_speed_10m)
		if w.is_precipitating():
			wet_count += 1
		temp_sum += w.temperature_c
		var d: String = Weather.compass_name(w.wind_from_deg)
		if d == "E" or d == "SE" or d == "W":
			east_or_west += 1
	var mean := 0.0
	for s in speeds:
		mean += s
	mean /= n
	var over8 := 0
	var over10 := 0
	for s in speeds:
		if s > 8.0: over8 += 1
		if s > 10.0: over10 += 1
	speeds.sort()
	check(absf(mean - 4.74) < 0.25, "Mean 10 m wind must be about 4.7 m/s (got %.2f)" % mean)
	check(absf(float(over8) / n - 0.073) < 0.02, "P(wind > 8 m/s) must be about 7%% (got %.3f)" % (float(over8) / n))
	check(float(over10) / n < 0.03, "P(wind > 10 m/s) must be about 1%% — the real Weibull tail, not a heavier one (got %.3f)" % (float(over10) / n))
	check(absf(speeds[int(n * 0.95)] - 8.4) < 0.8, "95th percentile must be about 8.4 m/s (got %.1f)" % speeds[int(n * 0.95)])
	check(absf(float(wet_count) / n - 0.179) < 0.03, "About 18%% of battles must start with precipitation (got %.3f)" % (float(wet_count) / n))
	check(absf(temp_sum / n - 4.0) < 0.4, "Mean temperature must be about +4 C (got %.1f)" % (temp_sum / n))
	check(float(east_or_west) / n > 0.42 and float(east_or_west) / n < 0.54, "E, SE and W winds together must be about 45%% of draws (got %.2f)" % (float(east_or_west) / n))


func test_wind_has_memory() -> void:
	seed(5)
	var n := 2500
	var xs: Array[float] = []
	var ys: Array[float] = []
	var far: Array[float] = []
	for i in n:
		var w := Weather.roll(i + 50)
		xs.append(log(w.wind_speed_10m))
		for step in 6:
			w.advance(600.0) # one hour
		ys.append(log(w.wind_speed_10m))
		for step in 138:
			w.advance(600.0) # to 24 h
		far.append(log(w.wind_speed_10m))
	var hour_corr: float = _correlation(xs, ys)
	var day_corr: float = _correlation(xs, far)
	check(absf(hour_corr - 0.94) < 0.03, "Hour-to-hour wind must correlate about 0.94 (got %.3f)" % hour_corr)
	check(absf(day_corr - 0.25) < 0.08, "Wind a day later must correlate about 0.25 (got %.3f)" % day_corr)


func _correlation(a: Array[float], b: Array[float]) -> float:
	var n: int = a.size()
	var ma := 0.0
	var mb := 0.0
	for i in n:
		ma += a[i]
		mb += b[i]
	ma /= n
	mb /= n
	var cov := 0.0
	var va := 0.0
	var vb := 0.0
	for i in n:
		cov += (a[i] - ma) * (b[i] - mb)
		va += (a[i] - ma) * (a[i] - ma)
		vb += (b[i] - mb) * (b[i] - mb)
	return cov / sqrt(va * vb)


func test_direction_drifts_slowly_and_precipitation_comes_in_spells() -> void:
	var changes: Array[float] = []
	for i in 800:
		var w := Weather.roll(i + 9000)
		var before: float = w.wind_from_deg
		for step in 6:
			w.advance(600.0)
		changes.append(absf(fposmod(w.wind_from_deg - before + 180.0, 360.0) - 180.0))
	changes.sort()
	check(changes[changes.size() / 2] < 9.0, "Median wind-direction change over an hour must be a few degrees (got %.1f)" % changes[changes.size() / 2])

	# Long runs: wet share and mean wet-spell length.
	var wet_steps := 0
	var total_steps := 0
	var spells: Array[float] = []
	for run in 120:
		var w := Weather.roll(run + 700)
		var spell := 0.0
		for step in 600: # 300 hours at 30 minutes
			w.advance(1800.0)
			total_steps += 1
			if w.is_precipitating():
				wet_steps += 1
				spell += 0.5
			elif spell > 0.0:
				spells.append(spell)
				spell = 0.0
	var wet_share: float = float(wet_steps) / total_steps
	var mean_spell := 0.0
	for s in spells:
		mean_spell += s
	mean_spell /= maxf(spells.size(), 1)
	check(absf(wet_share - 0.179) < 0.04, "Long-run wet share must be about 18%% (got %.3f)" % wet_share)
	check(absf(mean_spell - 4.9) < 1.3, "Mean wet spell must be about 4.9 hours (got %.1f)" % mean_spell)


func test_intensity_distribution_has_a_heavy_tail_and_a_light_body() -> void:
	var intensities: Array[float] = []
	for i in 6000:
		var w := Weather.new()
		w.rng.seed = i + 3
		w._start_event()
		intensities.append(w.precip_mm_h)
	intensities.sort()
	var median: float = intensities[intensities.size() / 2]
	var moderate_or_worse := 0
	var heavy := 0
	for v in intensities:
		if v >= 1.0: moderate_or_worse += 1
		if v >= 3.0: heavy += 1
	check(absf(median - 0.2) < 0.04, "Median wet-hour intensity must be about 0.2 mm/h (got %.2f)" % median)
	check(float(moderate_or_worse) / intensities.size() > 0.04 and float(moderate_or_worse) / intensities.size() < 0.12, "About 7%% of wet events must be moderate or worse (got %.3f)" % (float(moderate_or_worse) / intensities.size()))
	check(float(heavy) / intensities.size() > 0.01 and float(heavy) / intensities.size() < 0.06, "Heavy rain must be possible but rare (got %.3f of events)" % (float(heavy) / intensities.size()))
	check(intensities[0] >= 0.1, "No wet hour is lighter than the 0.1 mm/h that counts as precipitation")


func test_same_seed_same_weather() -> void:
	var a := Weather.roll(77)
	var b := Weather.roll(77)
	for step in 30:
		a.advance(120.0)
		b.advance(120.0)
	check(is_equal_approx(a.wind_speed_10m, b.wind_speed_10m) and is_equal_approx(a.wind_from_deg, b.wind_from_deg) and is_equal_approx(a.precip_mm_h, b.precip_mm_h),
		"A battle seed must give the same weather every time")


# ------------------------------------------------------------------ types & classes

func test_precipitation_type_follows_temperature_and_classes_follow_intensity() -> void:
	check(wet(pinned(), 0.3, -5.0).precip_type() == Weather.Precip.SNOW, "Well below freezing: snow")
	check(wet(pinned(), 0.3, 0.5).precip_type() == Weather.Precip.SLEET, "Around freezing: sleet")
	check(wet(pinned(), 0.3, 6.0).precip_type() == Weather.Precip.RAIN, "Above freezing: rain")
	check(pinned().precip_type() == Weather.Precip.NONE and pinned().precip_label() == "", "Dry: no type, no label")
	var cases := {0.2: Weather.Intensity.LIGHT, 0.7: Weather.Intensity.LIGHT_MODERATE, 1.5: Weather.Intensity.MODERATE, 4.0: Weather.Intensity.HEAVY}
	for mm in cases:
		check(wet(pinned(), mm).intensity_class() == cases[mm], "%.1f mm/h must classify as %d" % [mm, cases[mm]])
	check(wet(pinned(), 1.5).precip_label() == "Moderate rain", "Label reads as the user's classes (got '%s')" % wet(pinned(), 1.5).precip_label())
	check(wet(pinned(), 0.03).is_precipitating() == false, "Below 0.1 mm/h is not precipitation")


# ----------------------------------------------------------------------- drone

func test_ground_speed_crabs_into_the_wind() -> void:
	var dir := Vector2.RIGHT
	check(is_equal_approx(Weather.ground_speed(14.0, dir, Vector2(10.0, 0.0)), 24.0), "A 10 m/s tailwind adds to the ground speed")
	check(is_equal_approx(Weather.ground_speed(14.0, dir, Vector2(-10.0, 0.0)), 4.0), "A 10 m/s headwind subtracts")
	check(is_equal_approx(Weather.ground_speed(14.0, dir, Vector2(0.0, 8.0)), sqrt(14.0 * 14.0 - 64.0)), "A crosswind costs sqrt(airspeed^2 - crosswind^2)")
	check(Weather.ground_speed(14.0, dir, Vector2(-16.0, 0.0)) > 0.0, "A headwind above airspeed still leaves a crawl, never zero or negative")
	check(Weather.ground_speed(14.0, dir, Vector2(0.0, 20.0)) > 0.0, "A crosswind above airspeed can barely hold a track, but never divides by zero")


func test_wind_vector_points_the_way_it_blows_and_grows_with_height() -> void:
	var w := pinned(6.0, 270.0) # from the west, north up on the default map
	var v: Vector2 = w.wind_velocity_mps(10.0, false)
	check(v.x > 5.9 and absf(v.y) < 0.1, "A west wind blows toward +x on a north-up map (got %s)" % v)
	check(w.wind_speed_at(300.0) > w.wind_speed_at(10.0) * 1.5, "Wind at 300 m must be much stronger than at 10 m (%.1f vs %.1f)" % [w.wind_speed_at(300.0), w.wind_speed_at(10.0)])
	check(absf(w.wind_speed_at(300.0) / w.wind_speed_at(10.0) - pow(30.0, 0.14)) < 0.001, "Shear follows the measured 0.14 power law")


func test_rain_lowers_flight_altitude_and_blinds_moderate_or_worse() -> void:
	check(pinned().drone_operating_altitude_m() == 300.0 and pinned().drone_detection_scale() == 1.0, "Dry: full altitude, full range")
	var drizzle: float = wet(pinned(), 0.1).drone_operating_altitude_m()
	var light: float = wet(pinned(), 0.2).drone_operating_altitude_m()
	var lm: float = wet(pinned(), 0.5).drone_operating_altitude_m()
	check(absf(drizzle - 250.0) < 8.0 and absf(light - 208.0) < 8.0 and absf(lm - 120.0) < 8.0, "Flight ceiling in 0.1 / 0.2 / 0.5 mm/h must be about 250 / 208 / 120 m (got %.0f / %.0f / %.0f)" % [drizzle, light, lm])
	check(absf(wet(pinned(), 0.5).drone_detection_scale() - lm / 300.0) < 0.001, "Detection range scales with altitude")
	check(not wet(pinned(), 0.9).drone_vision_blocked(), "Light-moderate rain is still flyable")
	check(wet(pinned(), 1.0).drone_vision_blocked() and wet(pinned(), 5.0).drone_vision_blocked(), "Moderate and heavy rain blind the camera")
	check(wet(pinned(), 1.5).drone_detection_scale() == 0.0, "Blind means zero detection range")
	check(wet(pinned(), 0.5).ground_detection_scale() == 0.8 and wet(pinned(), 5.0).ground_detection_scale() == 0.4 and pinned().ground_detection_scale() == 1.0, "Ground detection shrinks with precipitation class")


func test_cold_shortens_flight_time() -> void:
	check(is_equal_approx(pinned(0.0, 270.0, 6.0).drone_cold_flight_time_factor(), 1.0), "Above 5 C: no loss")
	check(absf(pinned(0.0, 270.0, -5.0).drone_cold_flight_time_factor() - 0.85) < 0.001, "At -5 C: 15% less flight time")
	check(pinned(0.0, 270.0, -40.0).drone_cold_flight_time_factor() >= 0.5, "Never below half")


func test_failure_rates_are_the_agreed_table() -> void:
	# Baseline, calm and mild: about 0.3% per 35-minute sortie.
	var calm: float = sortie_failure_chance(pinned(0.0), 35.0)
	check(calm > 0.002 and calm < 0.005, "Calm baseline is about 0.3%% per sortie (got %.4f)" % calm)
	# Wind at flight altitude: about 6% at 12 m/s, about 29% at 15 m/s.
	var w12 := pinned(12.0 / pow(30.0, 0.14))
	var w15 := pinned(15.0 / pow(30.0, 0.14))
	check(absf(sortie_failure_chance(w12, 35.0) - 0.059) < 0.012, "12 m/s aloft: about 6%% per sortie (got %.3f)" % sortie_failure_chance(w12, 35.0))
	check(absf(sortie_failure_chance(w15, 35.0) - 0.29) < 0.05, "15 m/s aloft: about 29%% per sortie (got %.3f)" % sortie_failure_chance(w15, 35.0))
	# Rain below moderate: per 35-minute sortie, at the altitude the drone then flies.
	var expected := {0.1: 0.059, 0.2: 0.091, 0.5: 0.166}
	for mm in expected:
		var w := wet(pinned(0.0), mm)
		var p: float = sortie_failure_chance(w, 35.0, w.drone_operating_altitude_m())
		check(absf(p - expected[mm]) < 0.015, "%.1f mm/h rain: about %.0f%% per sortie (got %.3f)" % [mm, expected[mm] * 100.0, p])
	# Moderate and worse: the flight home, per minute — about 20/30/45/60% over 5 minutes.
	var home := {1.0: 0.20, 2.0: 0.30, 4.0: 0.45, 8.0: 0.62}
	for mm in home:
		var w := wet(pinned(0.0), mm)
		var p5: float = sortie_failure_chance(w, 5.0)
		check(absf(p5 - home[mm]) < 0.05, "%.0f mm/h: about %.0f%% over a 5-minute flight home (got %.3f)" % [mm, home[mm] * 100.0, p5])
	# Moderate rain is far worse than light-moderate, minute for minute.
	check(wet(pinned(0.0), 1.0).drone_hazard_per_minute(300.0) > wet(pinned(0.0), 0.9).drone_hazard_per_minute(120.0) * 4.0, "Crossing into moderate rain must step the hazard up sharply")
	# Snow: half the rain effect when dry, the full rain effect when wet or mixed
	# (compared with the cold multiplier divided out, since cold adds its own).
	var rain: float = wet(pinned(0.0), 0.3, 6.0).drone_hazard_per_minute(300.0)
	var dry_snow: float = wet(pinned(0.0), 0.3, -6.0).drone_hazard_per_minute(300.0) / 2.1
	var sleet: float = wet(pinned(0.0), 0.3, 0.0).drone_hazard_per_minute(300.0) / 1.5
	check(dry_snow < rain * 0.75, "Dry snow must be clearly milder than rain (%.5f vs %.5f)" % [dry_snow, rain])
	check(absf(sleet - rain) / rain < 0.05, "Sleet is as bad as rain (%.5f vs %.5f)" % [sleet, rain])
	check(pinned(0.0, 270.0, -5.0).drone_hazard_per_minute(300.0) > pinned(0.0, 270.0, 10.0).drone_hazard_per_minute(300.0) * 1.8, "Cold must raise the hazard")


func test_failure_cause_names_the_biggest_contributor() -> void:
	check(wet(pinned(0.0), 1.5).drone_hazard_cause(300.0) == "the moderate rain", "Moderate rain gets the blame")
	check(pinned(14.0 / pow(30.0, 0.14)).drone_hazard_cause(300.0) == "the wind", "Strong wind gets the blame")
	check(pinned(0.0, 270.0, -8.0).drone_hazard_cause(300.0) == "the cold", "Cold gets the blame")
	check(pinned(0.0).drone_hazard_cause(300.0) == "a mechanical fault", "Nothing else: a fault")


# ----------------------------------------------------------------------- mortar

func test_mortar_wind_bias() -> void:
	var w := pinned(8.0 / pow(30.0, 0.14), 270.0)
	var bias: Vector2 = w.mortar_wind_bias_px(GameConfig.MORTAR_FLIGHT_TIME)
	var meters: float = bias.length() / GameConfig.PIXELS_PER_METER
	check(absf(meters - 16.0) < 2.0, "An 8 m/s wind aloft leaves about 16 m of uncorrected drift (got %.1f)" % meters)
	check(bias.x > 0.0 and absf(bias.y) < absf(bias.x) * 0.05, "A west wind pushes the shell east")
	check(pinned(0.0).mortar_wind_bias_px(40.0).length() < 0.001, "No wind, no bias")


# ------------------------------------------------------------------ battle level

func make_battle():
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	return bm

func unit(bm, team: Unit.Team, kind: Unit.Kind, pos: Vector2) -> Unit:
	var u: Unit = bm._make_unit(team, kind, pos)
	(bm.player_units if team == Unit.Team.PLAYER else bm.enemy_units).append(u)
	return u

## A drone-team battle with one drone airborne as the active search drone and
## two ready batteries, on the given weather.
func drone_battle(w: Weather):
	Weather.current = w
	var bm = make_battle()
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	bm.drone_team = unit(bm, Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2(m(-800), m(1500)))
	var d: Unit = unit(bm, Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(m(500), m(1500)))
	d.drone_battery_charge = 0.9
	bm.active_drone = d
	bm._drones_ready.clear()
	bm._drones_ready.append(1.0)
	bm._drones_ready.append(1.0)
	return bm


func test_moderate_rain_recalls_and_grounds_the_drones_until_it_eases() -> void:
	var w := wet(pinned(0.0), 2.0)
	var bm = drone_battle(w)
	var d: Unit = bm.active_drone
	bm._update_drone_operations(6.0)
	check(bm.active_drone == null and bm.returning_drones.has(d), "Moderate rain must recall the search drone at once")
	check(bm._drone_grounded_for_weather, "...and ground the team")
	for i in 20:
		bm._update_drone_operations(6.0)
	check(bm.active_drone == null, "Nothing may launch while it is raining moderately")
	check(CombatResolver.effective_detection_range(d, unit(bm, Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(m(900), m(1500)))) == 0.0, "A drone's detection range must be zero at once")
	# Eases to light-moderate: still grounded until it has stayed calm for a while.
	w.precip_mm_h = 0.4
	for i in 30: # 180 s
		bm._update_drone_operations(6.0)
	check(bm._drone_grounded_for_weather and bm.active_drone == null, "Just easing is not enough — still grounded after 3 minutes")
	for i in 30: # another 180 s
		bm._update_drone_operations(6.0)
	check(not bm._drone_grounded_for_weather, "After five calm minutes the grounding lifts")
	check(bm.active_drone != null, "...and a drone launches again")


func test_light_rain_does_not_ground_and_drizzle_lowers_range() -> void:
	var w := wet(pinned(0.0), 0.3)
	var bm = drone_battle(w)
	bm._update_drone_operations(6.0)
	check(bm.active_drone != null and not bm._drone_grounded_for_weather, "Light rain must not recall the drone")
	var target: Unit = unit(bm, Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(m(900), m(1500)))
	var expected: float = GameConfig.DRONE_DETECTION_RANGE * w.drone_operating_altitude_m() / 300.0
	check(absf(CombatResolver.effective_detection_range(bm.active_drone, target) - expected) < 0.01, "The drone's range shrinks with the altitude it flies at in rain")
	var squad: Unit = unit(bm, Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(m(0), m(1500)))
	Weather.current = pinned(0.0)
	var dry_range: float = CombatResolver.effective_detection_range(squad, target)
	Weather.current = w
	check(CombatResolver.effective_detection_range(squad, target) < dry_range, "Ground detection is shorter in rain")
	# A blinded drone at point-blank range must not divide by zero.
	Weather.current = wet(pinned(0.0), 3.0)
	var lucky: bool = CombatResolver.roll_spot(bm.active_drone, unit(bm, Unit.Team.ENEMY, Unit.Kind.SQUAD, bm.active_drone.global_position), 0.5)
	check(not lucky and not CombatResolver.has_live_observer(target, [bm.active_drone] as Array[Unit]), "A blind drone spots and holds nothing")


func test_weather_failures_lose_or_abort_and_the_books_balance() -> void:
	var w := pinned(0.0)
	var bm = drone_battle(w)
	var lost := 0
	var aborted := 0
	for trial in 300:
		var d: Unit = unit(bm, Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(m(500), m(1500)))
		bm.active_drone = d
		var before_lost: int = bm._drones_lost_to_weather
		var before_abort: int = bm._drones_aborted_by_weather
		bm._weather_fail_drone(d, 300.0)
		if bm._drones_lost_to_weather > before_lost:
			lost += 1
			check(bm.active_drone == null and not bm.player_units.has(d), "A lost drone leaves its slot and the roster")
		elif bm._drones_aborted_by_weather > before_abort:
			aborted += 1
			check(bm.active_drone == null and bm.returning_drones.has(d), "An aborted drone heads home")
	check(absf(float(aborted) / 300.0 - 0.35) < 0.09, "About 35%% of ordinary failures must be aborts (got %.2f)" % (float(aborted) / 300.0))
	check(lost + aborted == 300 and bm._drones_destroyed == lost, "Every failure is a loss or an abort, and losses count as destroyed airframes")
	# In moderate+ rain (already flying home) a failure is always a loss.
	Weather.current = wet(pinned(0.0), 2.0)
	var homeward: Unit = unit(bm, Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(m(200), m(1500)))
	bm.returning_drones.append(homeward)
	var destroyed_before: int = bm._drones_destroyed
	bm._weather_fail_drone(homeward, 60.0)
	check(bm._drones_destroyed == destroyed_before + 1 and not bm.returning_drones.has(homeward), "A drone failing on the flight home in moderate rain is lost, never 'aborted'")


func test_hazard_actually_kills_drones_over_time() -> void:
	# 12 m/s aloft and moderate rain on the way home: run many drone-minutes and
	# check the loss count is in the expected ballpark (not zero, not everything).
	var w := wet(pinned(0.0), 2.0)
	var bm = drone_battle(w)
	bm.active_drone = null
	var total_drones := 400
	var losses := 0
	for k in total_drones:
		var d: Unit = unit(bm, Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(m(-700), m(1500)))
		d.has_move_target = true
		bm.returning_drones.append(d)
	for minute in 5:
		for tick in 10:
			bm._update_drone_weather(6.0)
	losses = bm._drones_lost_to_weather
	var share: float = float(losses) / total_drones
	check(share > 0.22 and share < 0.38, "A 5-minute flight home in 2 mm/h rain should lose about 30%% of drones (got %.2f)" % share)


func test_wind_changes_ground_speed_and_the_trip_home() -> void:
	# Wind from the west: blows east. Tailwind flying east, headwind flying west.
	var w := pinned(6.0, 270.0)
	var bm = drone_battle(w)
	var east: Unit = unit(bm, Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(m(0), m(1500)))
	east.move_speed = GameConfig.DRONE_CRUISE_SPEED
	east.move_target = Vector2(m(5000), m(1500))
	east.has_move_target = true
	var start: Vector2 = east.position
	bm._step_toward_target(east, 10.0)
	var east_speed: float = (east.position - start).length() / 10.0 / GameConfig.PIXELS_PER_METER
	var west: Unit = unit(bm, Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(m(3000), m(1500)))
	west.move_speed = GameConfig.DRONE_CRUISE_SPEED
	west.move_target = Vector2(m(-2000), m(1500))
	west.has_move_target = true
	start = west.position
	bm._step_toward_target(west, 10.0)
	var west_speed: float = (west.position - start).length() / 10.0 / GameConfig.PIXELS_PER_METER
	var aloft: float = w.wind_speed_at(300.0)
	check(absf(east_speed - (14.0 + aloft)) < 0.3, "Flying with the wind: cruise + wind aloft (got %.1f, expected %.1f)" % [east_speed, 14.0 + aloft])
	check(absf(west_speed - (14.0 - aloft)) < 0.3, "Flying into the wind: cruise - wind aloft (got %.1f, expected %.1f)" % [west_speed, 14.0 - aloft])
	# No weather at all: plain cruise speed, exactly as before.
	Weather.current = null
	var plain: Unit = unit(bm, Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(m(0), m(1600)))
	plain.move_speed = GameConfig.DRONE_CRUISE_SPEED
	plain.move_target = Vector2(m(5000), m(1600))
	plain.has_move_target = true
	start = plain.position
	bm._step_toward_target(plain, 10.0)
	check(absf((plain.position - start).length() / 10.0 - GameConfig.DRONE_CRUISE_SPEED) < 0.001, "With no weather the drone flies at plain cruise speed")

	# The trip home: a drone far east of the team needs longer (less charge to
	# spare) flying home into a headwind than with a tailwind.
	var far := Vector2(m(2500), m(1500))
	Weather.current = pinned(6.0, 270.0) # wind FROM the west blows east: a headwind flying west toward the team
	var bm_head = drone_battle(Weather.current)
	bm_head.active_drone.global_position = far
	var spare_head: float = bm_head._drone_time_until_rtb(bm_head.active_drone)
	Weather.current = pinned(6.0, 90.0) # from the east blows west: a tailwind flying home
	var bm_tail = drone_battle(Weather.current)
	bm_tail.active_drone.global_position = far
	var spare_tail: float = bm_tail._drone_time_until_rtb(bm_tail.active_drone)
	check(spare_head < spare_tail - 30.0, "A headwind home must leave less time before RTB than a tailwind (%.0f s vs %.0f s)" % [spare_head, spare_tail])


func test_cold_drains_the_battery_faster() -> void:
	var warm_weather := pinned(0.0, 270.0, 10.0)
	var cold_weather := pinned(0.0, 270.0, -5.0)
	var bm = drone_battle(warm_weather)
	Weather.current = warm_weather
	var warm_time: float = bm._drone_full_charge_flight_time()
	Weather.current = cold_weather
	var cold_time: float = bm._drone_full_charge_flight_time()
	check(absf(cold_time / warm_time - 0.85) < 0.001, "A full battery in -5 C is worth 85%% of the flight time (got %.3f)" % (cold_time / warm_time))


func test_mortar_shells_drift_with_the_wind_and_it_fades_with_adjustment() -> void:
	Weather.current = pinned(8.0 / pow(30.0, 0.14), 270.0)
	var bm = make_battle()
	var mortar: Unit = unit(bm, Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(m(0), m(1500)))
	var target: Unit = unit(bm, Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(m(2000), m(1500)))
	var sum := Vector2.ZERO
	var n := 600
	for i in n:
		bm._mortar_fire_adjustment.erase(mortar)
		sum += bm._mortar_dispersion_offset(mortar, target, target.global_position)
	var mean_offset_m: Vector2 = sum / n / GameConfig.PIXELS_PER_METER
	check(mean_offset_m.x > 10.0 and mean_offset_m.x < 22.0, "Fresh, unadjusted rounds drift ~16 m downwind on average (got %.1f)" % mean_offset_m.x)
	Weather.current = pinned(0.0)
	var calm := Vector2.ZERO
	for i in n:
		bm._mortar_fire_adjustment.erase(mortar)
		calm += bm._mortar_dispersion_offset(mortar, target, target.global_position)
	check(absf((calm / n / GameConfig.PIXELS_PER_METER).x) < 6.0, "Without wind the average offset is centered")


func test_start_battle_rolls_fresh_weather_each_time_and_keeps_a_deployment_roll() -> void:
	Weather.current = null
	var doctrine := {"squads": [], "mortar": {"position": Vector2(m(100), m(1500)), "shoot_and_scoot": false}, "spotter": {"position": Vector2(m(200), m(1500))}, "recon_mode": GameConfig.ReconMode.SPOTTER, "seed": 4242}
	var first = make_battle()
	first.start_battle(doctrine, Log.new())
	var a: Weather = Weather.current
	check(a != null and a.battle_started, "start_battle must roll weather when none was rolled at deployment")
	var second = make_battle()
	second.start_battle(doctrine, Log.new())
	check(Weather.current != a, "A second battle must roll its own weather")
	check(is_equal_approx(Weather.current.wind_speed_10m, a.wind_speed_10m), "The same battle seed gives the same weather")
	var deployed := Weather.roll(11)
	Weather.current = deployed
	var third = make_battle()
	third.start_battle({"squads": [], "mortar": doctrine.mortar, "spotter": doctrine.spotter, "recon_mode": GameConfig.ReconMode.SPOTTER}, Log.new())
	check(Weather.current == deployed, "A battle uses the weather rolled at deployment, not a new one")


func run() -> void:
	test_climatology_matches_the_era5_march_data()
	test_wind_has_memory()
	test_direction_drifts_slowly_and_precipitation_comes_in_spells()
	test_intensity_distribution_has_a_heavy_tail_and_a_light_body()
	test_same_seed_same_weather()
	test_precipitation_type_follows_temperature_and_classes_follow_intensity()
	test_ground_speed_crabs_into_the_wind()
	test_wind_vector_points_the_way_it_blows_and_grows_with_height()
	test_rain_lowers_flight_altitude_and_blinds_moderate_or_worse()
	test_cold_shortens_flight_time()
	test_failure_rates_are_the_agreed_table()
	test_failure_cause_names_the_biggest_contributor()
	test_mortar_wind_bias()
	test_moderate_rain_recalls_and_grounds_the_drones_until_it_eases()
	test_light_rain_does_not_ground_and_drizzle_lowers_range()
	test_weather_failures_lose_or_abort_and_the_books_balance()
	test_hazard_actually_kills_drones_over_time()
	test_wind_changes_ground_speed_and_the_trip_home()
	test_cold_drains_the_battery_faster()
	test_mortar_shells_drift_with_the_wind_and_it_fades_with_adjustment()
	test_start_battle_rolls_fresh_weather_each_time_and_keeps_a_deployment_roll()
	Weather.current = null
	print("Weather tests: %d failures" % failures)
	quit(1 if failures else 0)
