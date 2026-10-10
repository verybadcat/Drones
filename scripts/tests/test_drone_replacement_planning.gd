extends SceneTree
## Direct user instruction: "the next step is for the drone team to plan for it. Send out a replacement drone in time for it to be on
## station when the existing one needs to leave." The drone on station must turn for home in BattleManager._drone_time_until_rtb seconds; a
## replacement takes _drone_replacement_lead_time to fly to the same spot. It launches when the first has fallen to the second (and a charged
## drone is ready). Whatever the drone on station is doing (watching a mortar or not), and the replacement is promoted with no gap when the
## first leaves. (No battery is pulled out of the charger early for it: that measured worse.)
##
## Run: godot --headless --path . --script scripts/tests/test_drone_replacement_planning.gd
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

func calm_weather() -> Weather:
	var w := Weather.new()
	w.wind_speed_10m = 0.0
	w.temperature_c = 10.0
	w._gust_z = 0.0
	w.rng.seed = 5
	return w

## A drone-team battle with one drone on station 3 km east of the team, and an empty ready pool.
func make_battle(station_offset_m: float = 3000.0) -> BattleManager:
	Weather.current = calm_weather()
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	var team: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2(m(-800.0), m(1500.0)))
	bm.player_units.append(team)
	bm.drone_team = team
	bm._drones_ready.clear()
	bm._drones_swapping.clear()
	bm._battery_pool.clear()
	bm._airframes_awaiting_battery = 0
	var d: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, team.global_position + Vector2(m(station_offset_m), 0.0))
	bm.player_units.append(d)
	d.drone_battery_charge = 0.9
	bm.active_drone = d
	return bm

## Sets the drone on station's charge so it must leave in `seconds` (the planner's own `_drone_time_until_rtb`).
func set_leaves_in(bm: BattleManager, seconds: float) -> void:
	var d: Unit = bm.active_drone
	var home_cost: float = bm._drone_leg_charge(d.global_position, bm.drone_team.global_position) + bm._drone_arrival_reserve_charge()
	d.drone_battery_charge = home_cost + seconds / bm._drone_full_charge_flight_time()

func run() -> void:
	# 1. a charged drone is ready: it launches when the time left has fallen to the lead, and not before
	var bm := make_battle()
	bm._drones_ready.append(1.0)
	var station: Vector2 = bm.active_drone.global_position
	bm._drone_station_hint = station
	var lead: float = bm._drone_replacement_lead_time(station)
	check(lead > 150.0 and lead < 400.0, "Setup: a 3 km flight out takes %.0f s with the margin" % lead)
	set_leaves_in(bm, lead + 90.0)
	bm._plan_drone_replacement()
	check(bm.backup_drone == null, "With the drone on station able to stay %.0f s longer than the flight out takes, nothing launches yet" % 90.0)
	set_leaves_in(bm, lead + 5.0)
	bm._plan_drone_replacement()
	check(bm.backup_drone == null, "...nor just above the lead")
	set_leaves_in(bm, lead - 5.0)
	bm._plan_drone_replacement()
	check(bm.backup_drone != null, "Once it must leave within the flight out, the replacement launches")
	check(bm._drones_ready.is_empty(), "...on the ready battery")
	bm.combat_log.free()
	bm.free()

	# 2. it flies to the same spot, with no mortar to watch, and is not sent home at once
	bm = make_battle()
	bm._drones_ready.append(1.0)
	bm._drone_station_hint = bm.active_drone.global_position
	set_leaves_in(bm, bm._drone_replacement_lead_time(bm.active_drone.global_position) - 5.0)
	bm._plan_drone_replacement()
	var relief: Unit = bm.backup_drone
	check(relief != null, "Setup: launched")
	if relief != null:
		bm._update_backup_drone(1.0)
		check(bm.backup_drone == relief and relief.has_move_target and relief.move_target.distance_to(bm.active_drone.global_position) < 2.0, "With no mortar in sight it still heads for where the drone on station is working, and is not sent home")
		# 3. when the first has to leave, the replacement is promoted with no gap
		bm.active_drone.drone_battery_charge = 0.01
		bm.active_drone.global_position = bm.drone_team.global_position + Vector2(m(3000.0), 0.0)
		bm._update_drone_operations(1.0)
		check(bm.active_drone == relief and bm.backup_drone == null, "When the first drone goes home the replacement is the drone on station at once, with no gap")
	bm.combat_log.free()
	bm.free()

	# 4. nothing ready: no still-charging battery is pulled out early to have one (measured to make handoffs worse, see _plan_drone_replacement);
	# the replacement goes as soon as a charged battery is in, and not before the time
	bm = make_battle()
	bm._battery_pool.append(0.9)
	bm._airframes_awaiting_battery = 1
	bm._drone_station_hint = bm.active_drone.global_position
	lead = bm._drone_replacement_lead_time(bm.active_drone.global_position)
	set_leaves_in(bm, GameConfig.DRONE_BATTERY_SWAP_DURATION + lead - 10.0)
	bm._plan_drone_replacement()
	check(bm._drones_swapping.is_empty() and bm._battery_pool.size() == 1 and bm.backup_drone == null, "With nothing ready, a still-charging battery is not pulled out early for the relief")
	bm._drones_ready.append(1.0) # a battery finishes and goes in on the fleet's own rule
	set_leaves_in(bm, lead + 60.0)
	bm._plan_drone_replacement()
	check(bm.backup_drone == null, "...a charged drone does not launch before the time")
	set_leaves_in(bm, lead - 5.0)
	bm._plan_drone_replacement()
	check(bm.backup_drone != null, "...and launches in time once it is ready")
	bm.combat_log.free()
	bm.free()

	# 5. a ready battery too low to make the trip is not sent (it would turn straight back); nor one that only just covers it, with no time to
	# stay once there
	bm = make_battle()
	bm._drones_ready.append(0.2)
	bm._drone_station_hint = bm.active_drone.global_position
	set_leaves_in(bm, 10.0)
	bm._plan_drone_replacement()
	check(bm.backup_drone == null and bm._drones_ready.size() == 1, "A battery too low to reach the station and get back is not launched")
	bm._drones_ready.clear()
	var just_covers: float = bm._drone_required_launch_charge(bm.active_drone.global_position) + 0.01
	bm._drones_ready.append(just_covers)
	bm._plan_drone_replacement()
	check(bm.backup_drone == null, "...nor one that only just covers the trip, which would arrive and turn straight back (%.2f)" % just_covers)
	bm._drones_ready.clear()
	bm._drones_ready.append(just_covers + GameConfig.DRONE_REPLACEMENT_MIN_STATION_S / bm._drone_full_charge_flight_time() + 0.01)
	bm._plan_drone_replacement()
	check(bm.backup_drone != null, "...but one that leaves it %d minutes on station is" % int(GameConfig.DRONE_REPLACEMENT_MIN_STATION_S / 60.0))
	bm.combat_log.free()
	bm.free()

	# 6. a replacement waiting on a drone that is nowhere near leaving goes home rather than burn its charge
	bm = make_battle()
	bm._drones_ready.append(1.0)
	bm._drone_station_hint = bm.active_drone.global_position
	set_leaves_in(bm, bm._drone_replacement_lead_time(bm.active_drone.global_position) - 5.0)
	bm._plan_drone_replacement()
	relief = bm.backup_drone
	set_leaves_in(bm, bm._drone_replacement_lead_time(bm.active_drone.global_position) + GameConfig.DRONE_REPLACEMENT_RECALL_SLACK_S + 60.0)
	if relief != null:
		bm._update_backup_drone(1.0)
		check(bm.backup_drone == null and bm.returning_drones.has(relief), "If the drone on station turns out to have much longer to stay, the replacement goes home")
	bm.combat_log.free()
	bm.free()
	print("Drone replacement planning tests: %d failures" % failures)
	quit(1 if failures else 0)
