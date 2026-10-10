extends SceneTree
## Direct user instruction: "If a drone is lost, be sure to note why so we can look at it afterwards." Every site that loses an airframe
## notes it (BattleManager._record_drone_loss): when, which drone, what it was doing, a cause key and in words, its charge, where it was and
## how far from the team, the weather, and cause-specific detail. The record is in the after-action report (only when a drone was lost) and in
## the loss snapshot.
##
## Run: godot --headless --path . --script scripts/tests/test_drone_loss_records.gd
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

func make() -> BattleManager:
	var w := Weather.new()
	w.wind_speed_10m = 6.0
	w.temperature_c = 2.0
	w._gust_z = 0.0
	w.rng.seed = 9
	Weather.current = w
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	var team: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2(m(-800.0), m(1500.0)))
	bm.player_units.append(team)
	bm.drone_team = team
	bm.scenario_elapsed_time = 4000.0
	return bm

func drone(bm: BattleManager, east_m: float, charge: float) -> Unit:
	var d: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, bm.drone_team.global_position + Vector2(m(east_m), 0.0))
	bm.player_units.append(d)
	d.drone_battery_charge = charge
	return d

func run() -> void:
	# 1. a battery that ran flat, and one held on station over a mortar until it did
	var bm := make()
	var d1: Unit = drone(bm, 2000.0, 0.0)
	bm.active_drone = d1
	bm._crash_drone(d1, null)
	check(bm._drone_losses.size() == 1, "One loss is noted (%d)" % bm._drone_losses.size())
	var e: Dictionary = bm._drone_losses[0]
	check(e.cause == "battery_empty" and e.role == "on station" and e.charge_pct == 0, "A flat battery in flight: cause %s, role %s, charge %d%%" % [e.cause, e.role, e.charge_pct])
	check(e.distance_from_team_m == 2000 and e.position.has("x") and e.clock == bm.clock_string(), "...with how far from the team (%d m), where, and the time (%s)" % [e.distance_from_team_m, e.clock])
	check(e.conditions.has("wind_mps") and e.conditions.temperature_c == 2.0, "...and the weather at the time (%s)" % str(e.conditions))
	var gun: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(m(3000.0), m(1500.0)))
	bm.enemy_units.append(gun)
	var d2: Unit = drone(bm, 2200.0, 0.0)
	bm.backup_drone = d2
	bm._crash_drone(d2, gun)
	check(bm._drone_losses[1].cause == "battery_empty_on_station" and bm._drone_losses[1].role == "backup" and str(bm._drone_losses[1].detail.watched) == gun.display_name(), "Held over a mortar until it ran flat: cause %s, role %s, mortar named" % [bm._drone_losses[1].cause, bm._drone_losses[1].role])
	bm.combat_log.free()
	bm.free()

	# 2. a failed pack
	bm = make()
	var d3: Unit = drone(bm, 1500.0, 0.06)
	bm.returning_drones.append(d3)
	bm._battery_fail_drone(d3, 0.0002, 0.07)
	e = bm._drone_losses[0]
	check(e.cause == "low_battery" and e.role == "returning" and e.charge_pct == 6, "A pack that failed at 6%%: cause %s, role %s, charge %d%%" % [e.cause, e.role, e.charge_pct])
	check(is_equal_approx(e.detail.low_charge_hazard_per_min, 0.07) and e.detail.has("weather_hazard_per_min") and e.detail.low_charge_onset_pct >= 20, "...with the hazard rates and the onset in the detail (%s)" % str(e.detail))
	check(not bm.returning_drones.has(d3) and bm._drones_lost_to_low_battery == 1, "...and the drone is gone and counted")
	bm.combat_log.free()
	bm.free()

	# 3. weather: a drone sent home instead of lost is not a loss; one lost is noted with its cause
	bm = make()
	var altitude: float = bm.weather.drone_operating_altitude_m()
	var aborted := false
	for seed_value in range(1, 60):
		bm.weather.rng.seed = seed_value
		var d4: Unit = drone(bm, 800.0, 0.5)
		bm.active_drone = d4
		bm._drone_pilot_reasoning = {"tier": "Tracking dangerous squad"}
		bm._weather_fail_drone(d4, altitude)
		if bm.returning_drones.has(d4):
			aborted = true
			break
		bm._drone_losses.clear()
		bm._drones_destroyed = 0
	check(aborted, "(setup) some seed turns the drone for home instead of losing it")
	check(bm._drone_losses.is_empty(), "A drone the weather sent home is not noted as lost (%d)" % bm._drone_losses.size())
	var d5: Unit = drone(bm, 800.0, 0.5)
	bm.returning_drones.append(d5)
	bm._weather_fail_drone(d5, altitude)
	var weather_entries: Array = bm._drone_losses.filter(func(x): return x.cause == "weather")
	check(weather_entries.size() == 1, "A weather loss is noted (%d)" % weather_entries.size())
	if not weather_entries.is_empty():
		check(str(weather_entries[0].detail.hazard_cause) != "" and weather_entries[0].why.contains("weather"), "...with the cause named (%s)" % weather_entries[0].why)
	bm.combat_log.free()
	bm.free()

	# 4. hit
	bm = make()
	var d6: Unit = drone(bm, 1000.0, 0.4)
	bm.active_drone = d6
	d6.state = Unit.State.DESTROYED
	bm._on_drone_state_changed(d6)
	check(bm._drone_losses.size() == 1 and bm._drone_losses[0].cause == "shot_down" and bm._drone_losses[0].role == "on station", "A drone that was hit is noted as shot down (%s)" % str(bm._drone_losses.map(func(x): return x.cause)))
	bm.combat_log.free()
	bm.free()

	# 5. the team lost: everything airborne is noted
	bm = make()
	var d7: Unit = drone(bm, 900.0, 0.5)
	var d8: Unit = drone(bm, 400.0, 0.3)
	bm.active_drone = d7
	bm.returning_drones.append(d8)
	bm.drone_team.state = Unit.State.DESTROYED
	bm._update_drone_operations(1.0)
	check(bm._drone_losses.size() == 2 and bm._drone_losses.all(func(x): return x.cause == "ground_team_lost"), "With the team lost, both airborne drones are noted as lost for want of a ground station (%d)" % bm._drone_losses.size())

	# 6. the readers
	var lines: Array[String] = bm.drone_loss_report_lines()
	check(lines.size() == 3 and lines[0] == "Drones lost: 2" and lines[1].contains("charge") and lines[1].contains("ground station"), "The report lists them: %s" % str(lines))
	var snap: Dictionary = bm.drone_loss_debug_snapshot()
	check(snap.count == 2 and snap.losses.size() == 2 and snap.losses[0].has("why") and snap.losses[0].has("conditions"), "The loss snapshot holds them in full")
	var clean: BattleManager = make()
	check(clean.drone_loss_report_lines().is_empty() and clean.drone_loss_debug_snapshot().count == 0, "With no drone lost, nothing is added to the report and the snapshot is empty")
	clean.combat_log.free()
	clean.free()
	bm.combat_log.free()
	bm.free()
	print("Drone loss record tests: %d failures" % failures)
	quit(1 if failures else 0)
