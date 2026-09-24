extends SceneTree
## Direct user report from a live battle: "drone is going back and forth for no
## good reason ... every 1-2 seconds of real time". The state, read off the live
## debug snapshot: light rain and wind had forced the drone down to 161 m, so its
## detection range was ~860 m — about the spacing of the sweep grid — and it was
## flying between two sweep cells (x=3250 and x=4950) from x~4100.
##
## Cause: the drone's own camera counted against the cell it was flying TO. The
## moment the approach brought that cell into view its value dropped to
## DRONE_SWEEP_CLEARED_WEIGHT_MULTIPLIER of a fresh one, the sticky commitment
## collapsed mid-flight, the drone turned for the other cell — and the cell it
## turned away from went back to full value once out of view, so the pair
## alternated forever, never arriving anywhere. Now the committed cell keeps its
## value while the drone approaches; a leg ends by arriving, as designed.
##
## Run: godot --headless --path . --script scripts/tests/test_drone_no_dithering.gd
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

## The live battle's own conditions: light rain, NW wind, 161 m altitude.
func live_battle():
	var w := Weather.new()
	w.wind_speed_10m = 5.4
	w.wind_from_deg = 307.0
	w.temperature_c = 8.7
	w.precip_mm_h = 0.34
	w._wet = true
	w._gust_z = 0.0
	w.rng.seed = 1
	Weather.current = w
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.weather = w
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	bm.drone_team = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2(m(-650), m(1860)))
	bm.player_units.append(bm.drone_team)
	var d: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(m(4073), m(1750)))
	bm.player_units.append(d)
	d.drone_battery_charge = 0.66
	bm.active_drone = d
	return bm

func run() -> void:
	test_no_reversal_while_flying_to_a_cell()
	test_committed_cell_keeps_its_value_in_view()
	print("Drone dithering tests: %d failures" % failures)
	quit(1 if failures else 0)


## Fly the real selection code for 600 one-second steps at 25 m each and record
## every change of destination and how far the drone had flown since the last.
func test_no_reversal_while_flying_to_a_cell() -> void:
	var bm = live_battle()
	check(bm._drone_detection_range() < m(900.0), "Setup: the live weather must put the detection range under ~900 m (was %.0f m)" % (bm._drone_detection_range() / GameConfig.PIXELS_PER_METER))
	var d: Unit = bm.active_drone
	var last := ""
	var switches := 0
	var steps_since_switch := 0
	var shortest_leg := 9999
	for i in 600:
		bm.scenario_elapsed_time += 1.0
		var pick: Dictionary = bm._drone_routine_recon_target(bm._flank_watch_candidates())
		if pick.is_empty():
			break
		if pick.key != last:
			if last != "":
				switches += 1
				shortest_leg = mini(shortest_leg, steps_since_switch)
			steps_since_switch = 0
			last = pick.key
		steps_since_switch += 1
		var to: Vector2 = pick.point - d.global_position
		d.global_position += to.normalized() * minf(m(25.0), to.length())
	check(switches <= 25, "The drone must fly legs, not dither: %d destination changes in 600 steps" % switches)
	check(shortest_leg >= 10, "No leg may be abandoned within a few steps of being chosen (shortest %d steps)" % shortest_leg)
	print("  %d destination changes in 600 steps, shortest leg %d steps" % [switches, shortest_leg])
	bm.combat_log.free()
	bm.free()


## The mechanism itself: the drone seeing the cell it is committed to must not
## discount it; the same cell as an ordinary candidate (or seen by a ground
## unit) still is.
func test_committed_cell_keeps_its_value_in_view() -> void:
	var bm = live_battle()
	var d: Unit = bm.active_drone
	var cells: Array = bm._sweep_candidates()
	var seen_cell: Dictionary = {}
	for c in cells:
		if bm._drone_currently_sees(c.point):
			seen_cell = c
			break
	check(not seen_cell.is_empty(), "Setup: at least one cell must be in the drone's view")
	if not seen_cell.is_empty():
		var committed: Dictionary = {}
		for c in bm._sweep_candidates(seen_cell.key):
			if c.key == seen_cell.key:
				committed = c
		check(committed.value > seen_cell.value * 3.0, "Committed cell in view keeps its value (%.3f vs %.3f as an ordinary candidate)" % [committed.value, seen_cell.value])
		# A ground unit's view still counts against it, committed or not.
		var squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, seen_cell.point)
		bm.player_units.append(squad)
		var by_squad: Dictionary = {}
		for c in bm._sweep_candidates(seen_cell.key):
			if c.key == seen_cell.key:
				by_squad = c
		check(by_squad.value < committed.value * 0.5, "A ground unit watching the cell still discounts it (%.3f vs %.3f)" % [by_squad.value, committed.value])
	bm.combat_log.free()
	bm.free()
