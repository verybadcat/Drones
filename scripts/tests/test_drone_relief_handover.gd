extends SceneTree
## Direct user instruction: "Once the replacement is there, no reason for the old one to stay any longer." Two drones were seen staying
## out at the same place at the same time: the replacement (sent ahead, see BattleManager._plan_drone_replacement) waited beside a drone
## that still had charge to stay. Now, when the replacement has reached the spot it was sent to, the drone on station turns for home at
## once and the replacement takes over on the same tick. Not before it is there, and not if the replacement itself has hardly any time
## left (then the old one, which has more, stays until it must go).
##
## Run: godot --headless --path . --script scripts/tests/test_drone_relief_handover.gd
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

func make_battle() -> BattleManager:
	var w := Weather.new()
	w.wind_speed_10m = 0.0
	w.temperature_c = 10.0
	w._gust_z = 0.0
	w.rng.seed = 5
	Weather.current = w
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
	return bm

func drone_at(bm: BattleManager, east_m: float, charge: float) -> Unit:
	var d: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, bm.drone_team.global_position + Vector2(m(east_m), 0.0))
	bm.player_units.append(d)
	d.drone_battery_charge = charge
	return d

## Sets the charge of the drone on station so that it must turn for home in `seconds` (BattleManager._drone_time_until_rtb).
func set_leaves_in(bm: BattleManager, d: Unit, seconds: float) -> void:
	var home_cost: float = bm._drone_leg_charge(d.global_position, bm.drone_team.global_position) + bm._drone_arrival_reserve_charge()
	d.drone_battery_charge = home_cost + seconds / bm._drone_full_charge_flight_time()

func run() -> void:
	# 1. the replacement is on the spot while the drone on station still has two minutes to stay: it goes home and the replacement is on
	# station, in one tick
	var bm := make_battle()
	var old: Unit = drone_at(bm, 3000.0, 0.9)
	set_leaves_in(bm, old, 120.0)
	bm.active_drone = old
	bm._drone_station_hint = old.global_position
	var relief: Unit = drone_at(bm, 3000.0 + 20.0, 0.7)
	bm.backup_drone = relief
	bm._update_drone_operations(0.5)
	check(bm.active_drone == relief and bm.backup_drone == null, "With the replacement on the spot, it is the drone on station at once")
	check(bm.returning_drones.has(old), "...and the drone it relieved is flying home, though it had charge to stay")
	check(bm._drone_return_plans.has(old.get_instance_id()) and str(bm._drone_return_plans[old.get_instance_id()].reason).contains("relieved"), "...and its record says why it left")
	check(old.drone_battery_charge > bm._drone_leg_charge(old.global_position, bm.drone_team.global_position) + bm._drone_arrival_reserve_charge() - 0.001, "...with the reserve it had in hand, not run down to it")
	bm.combat_log.free()
	bm.free()

	# 2. the replacement is still on its way: the old one stays
	bm = make_battle()
	old = drone_at(bm, 3000.0, 0.9)
	set_leaves_in(bm, old, 120.0)
	bm.active_drone = old
	bm._drone_station_hint = old.global_position
	relief = drone_at(bm, 1500.0, 0.7)
	bm.backup_drone = relief
	bm._update_drone_operations(0.5)
	check(bm.active_drone == old and bm.backup_drone == relief and bm.returning_drones.is_empty(), "A replacement 1.5 km short of the spot has not relieved anyone: the old one stays")
	bm.combat_log.free()
	bm.free()

	# 3. the replacement is there but has hardly any time left: the old one, with more, stays
	bm = make_battle()
	old = drone_at(bm, 3000.0, 0.9)
	set_leaves_in(bm, old, 120.0)
	bm.active_drone = old
	bm._drone_station_hint = old.global_position
	relief = drone_at(bm, 3000.0, 0.0)
	bm.backup_drone = relief
	relief.drone_battery_charge = bm._drone_leg_charge(relief.global_position, bm.drone_team.global_position) + bm._drone_arrival_reserve_charge() + 20.0 / bm._drone_full_charge_flight_time()
	bm._relieve_drone_on_station()
	check(bm.active_drone == old and bm.returning_drones.is_empty(), "A replacement with only 20 s before it must turn does not send away a drone that can stay two minutes more")
	bm.combat_log.free()
	bm.free()

	# 4. no replacement: nothing changes (the drone on station stays until its own return point)
	bm = make_battle()
	old = drone_at(bm, 3000.0, 0.9)
	bm.active_drone = old
	bm._relieve_drone_on_station()
	check(bm.active_drone == old and bm.returning_drones.is_empty(), "With no replacement, the drone on station is left alone")
	bm.combat_log.free()
	bm.free()

	print("Drone relief handover tests: %d failures" % failures)
	quit(1 if failures else 0)
