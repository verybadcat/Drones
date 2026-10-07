extends SceneTree
## The drone team operating its drones while the team itself is on the move. The user: it "should
## be able to operate its drones while the team itself is moving. However, this should degrade
## its performance in multiple ways. Its value for artillery spotting should still be above that
## of a spotter, but less than its value when stationary. Aim for about halfway in between. It
## should also be slightly less likely to see enemies and suffer a slightly greater chance of
## drone loss."
##
## Run: godot --headless --path . --script scripts/tests/test_drone_team_on_the_move.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

class FailStub extends BattleManager:
	func _drone_failure_chance(_scenario_delta: float, _altitude: float) -> float:
		return 1.0

func _initialize() -> void:
	call_deferred("run")

func m(v: float) -> float:
	return v * GameConfig.PIXELS_PER_METER

## Calm, mild, dry weather, so nothing but the team's movement varies.
func calm_weather() -> Weather:
	var w := Weather.new()
	w.wind_speed_10m = 0.0
	w.temperature_c = 10.0
	w._gust_z = 0.0
	w.rng.seed = 5
	return w

func unit(bm, team: Unit.Team, kind: Unit.Kind, pos: Vector2) -> Unit:
	var u: Unit = bm._make_unit(team, kind, pos)
	(bm.player_units if team == Unit.Team.PLAYER else bm.enemy_units).append(u)
	return u

## A drone-team battle, all at y = 2700 m (south of the default map's village: a unit inside a building is hidden from a drone): the team at (-800, 2700) m, one drone airborne over (500, 2700) m, our mortar
## at (-200, 2700) m and an enemy squad in the drone's view at (900, 2700) m.
func make_battle(moving: bool) -> Dictionary:
	seed(11)
	Weather.current = calm_weather()
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	var team: Unit = unit(bm, Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2(m(-800), m(2700)))
	bm.drone_team = team
	var drone: Unit = unit(bm, Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(m(500), m(2700)))
	drone.drone_battery_charge = 0.9
	bm.active_drone = drone
	bm._drones_ready.clear()
	bm._drones_ready.append(1.0)
	bm._drones_ready.append(1.0)
	var mortar: Unit = unit(bm, Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(m(-200), m(2700)))
	var target: Unit = unit(bm, Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(m(900), m(2700)))
	if moving:
		team.move_target = Vector2(m(-1000), m(2700))
		team.has_move_target = true
	return {"bm": bm, "team": team, "drone": drone, "mortar": mortar, "target": target}

func cleanup(c: Dictionary) -> void:
	c.bm.combat_log.free()
	c.bm.free()
	Weather.current = null

func run() -> void:
	test_the_team_is_on_the_move_only_while_a_move_order_stands()
	test_drones_are_still_flown_while_the_team_moves()
	test_the_spotting_value_is_between_a_stationary_team_and_a_spotter()
	test_the_accuracy_bonus_is_halfway_too()
	test_a_moving_team_is_slightly_less_likely_to_see_enemies()
	test_a_moving_team_loses_drones_slightly_more_often()
	print("Drone team on the move tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_the_team_is_on_the_move_only_while_a_move_order_stands() -> void:
	var c := make_battle(false)
	check(not c.bm._drone_team_on_the_move(), "A team standing still is not on the move")
	c.team.move_target = Vector2(m(-1000), m(2700))
	c.team.has_move_target = true
	check(c.bm._drone_team_on_the_move(), "...one with a move order standing is")
	c.team.has_move_target = false
	check(not c.bm._drone_team_on_the_move(), "...and is not again once it has arrived")
	c.team.has_move_target = true
	c.team.state = Unit.State.RETREATING
	check(not c.bm._drone_team_on_the_move(), "A team that is no longer in action is not operating anything")
	c.team.state = Unit.State.ACTIVE
	c.bm.recon_mode = GameConfig.ReconMode.SPOTTER
	check(not c.bm._drone_team_on_the_move(), "In the spotter setup there is no drone team to be on the move")
	cleanup(c)


## "Should be able to operate its drones while the team itself is moving."
func test_drones_are_still_flown_while_the_team_moves() -> void:
	var c := make_battle(true)
	c.bm.active_drone = null
	c.drone.queue_free()
	c.bm.player_units.erase(c.drone)
	c.bm._update_drone_operations(6.0)
	check(c.bm.active_drone != null, "A team under way still launches a drone")
	if c.bm.active_drone != null:
		check(c.bm.active_drone.drone_operator_moving, "...which is flown on the move (flagged so)")
	for i in 10:
		c.bm._update_drone_operations(6.0)
	check(c.bm.active_drone != null and c.bm.active_drone.drone_operator_moving, "...and keeps flying while the team keeps moving")
	c.team.has_move_target = false
	c.bm._update_drone_operations(6.0)
	check(c.bm.active_drone != null and not c.bm.active_drone.drone_operator_moving, "Once the team has stopped the flag clears (full performance again)")
	cleanup(c)


## The mean miss distance (metres) of the mortar's next round, after `corrected_shots` earlier rounds have
## been corrected on this target, over many samples.
func mean_miss(c: Dictionary, corrected_shots: int, samples: int) -> float:
	var total := 0.0
	var aim: Vector2 = c.target.global_position
	for i in samples:
		c.bm._mortar_fire_adjustment[c.mortar] = {"target": c.target, "shots": corrected_shots, "wind_assumed": Vector2.ZERO}
		total += c.bm._mortar_dispersion_offset(c.mortar, c.target, aim).length()
	return total / samples / GameConfig.PIXELS_PER_METER # in metres


## "Above that of a spotter, but less than its value when stationary. Aim for about halfway."
func test_the_spotting_value_is_between_a_stationary_team_and_a_spotter() -> void:
	var still := make_battle(false)
	var moving := make_battle(true)
	var spotter_battle := make_battle(false)
	# The spotter case: the same battle with the drone gone and a spotter watching the target.
	spotter_battle.bm.active_drone = null
	spotter_battle.drone.global_position = Vector2(m(-5000), m(-5000)) # far out of the picture
	spotter_battle.bm.player_units.erase(spotter_battle.drone)
	spotter_battle.drone.queue_free()
	var spotter: Unit = unit(spotter_battle.bm, Unit.Team.PLAYER, Unit.Kind.SPOTTER, Vector2(m(500), m(2700)))
	check(still.bm._mortar_fire_observation_quality(still.mortar, still.target) == "drone", "A stationary team's drone gives 'drone' quality")
	check(moving.bm._mortar_fire_observation_quality(moving.mortar, moving.target) == "drone_moving", "A team on the move gives 'drone_moving' quality")
	check(spotter_battle.bm._mortar_fire_observation_quality(spotter_battle.mortar, spotter_battle.target) == "spotter", "Setup: a spotter gives 'spotter' quality")
	for k in [1, 2, 3]:
		var a: float = mean_miss(still, k, 700)
		var b: float = mean_miss(moving, k, 700)
		var s: float = mean_miss(spotter_battle, k, 700)
		var midpoint: float = (a + s) / 2.0
		check(a < b and b < s, "After %d corrected rounds, a team on the move corrects better than a spotter and worse than a stationary team (%.1f m < %.1f m < %.1f m)" % [k, a, b, s])
		check(absf(b - midpoint) <= 0.12 * (s - a), "...and about halfway between them (%.1f m vs midpoint %.1f m)" % [b, midpoint])
	cleanup(still)
	cleanup(moving)
	cleanup(spotter_battle)


## The drone feed's accuracy bonus — the other part of the spotting value.
func test_the_accuracy_bonus_is_halfway_too() -> void:
	var still := make_battle(false)
	var moving := make_battle(true)
	var full: float = still.bm._drone_directing_multiplier(still.mortar)
	var reduced: float = moving.bm._drone_directing_multiplier(moving.mortar)
	check(is_equal_approx(full, GameConfig.DRONE_DIRECTED_MORTAR_ACCURACY_MULTIPLIER) and full > 1.5, "A stationary team keeps its full accuracy bonus (x%.3f)" % full)
	check(reduced > 1.0 and reduced < full, "A team on the move still gives a bonus, a smaller one (x%.3f)" % reduced)
	check(is_equal_approx(reduced, (full + 1.0) / 2.0), "...halfway to a spotter's none (x%.3f, halfway is x%.3f)" % [reduced, (full + 1.0) / 2.0])
	# In real hit chances (a target the bonus does not push past certainty).
	var p_full: float = CombatResolver.hit_probability(still.mortar, still.target, full)
	var p_reduced: float = CombatResolver.hit_probability(moving.mortar, moving.target, reduced)
	var p_none: float = CombatResolver.hit_probability(still.mortar, still.target, 1.0)
	check(p_none < p_reduced and p_reduced < p_full and p_full < 1.0, "...so hit chances order stationary > moving > spotter (%.3f > %.3f > %.3f)" % [p_full, p_reduced, p_none])
	# Only the player's own mortar with a drone in the air gets any of it.
	moving.bm.active_drone = null
	check(moving.bm._drone_directing_multiplier(moving.mortar) == 1.0, "With no drone in the air there is no bonus")
	var enemy_mortar: Unit = unit(still.bm, Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(m(3000), m(2700)))
	check(still.bm._drone_directing_multiplier(enemy_mortar) == 1.0, "The enemy's mortar never gets it")
	cleanup(still)
	cleanup(moving)


## "Slightly less likely to see enemies": the drone's chance of noticing a target in its view.
func test_a_moving_team_is_slightly_less_likely_to_see_enemies() -> void:
	var c := make_battle(false)
	var trials := 12000
	var rates: Array[float] = []
	for on_the_move in [false, true]:
		c.drone.drone_operator_moving = on_the_move
		seed(21)
		var spotted := 0
		for i in trials:
			if CombatResolver.roll_spot(c.drone, c.target, 1.0):
				spotted += 1
		rates.append(float(spotted) / trials)
	var ratio: float = rates[1] / rates[0]
	check(rates[0] > 0.02, "Setup: a drone does notice a target in its view (%.3f per moment)" % rates[0])
	check(rates[1] < rates[0], "A drone flown from a team on the move notices less often (%.3f vs %.3f)" % [rates[1], rates[0]])
	check(ratio > 0.75 and ratio < 0.95, "...but only slightly less (%.2f of the usual)" % ratio)
	# Range is untouched: a target beyond the drone's range is out of sight either way.
	var far: Unit = unit(c.bm, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.drone.global_position + Vector2(GameConfig.DRONE_DETECTION_RANGE + m(300.0), 0.0))
	c.drone.drone_operator_moving = true
	var seen_far := false
	for i in 200:
		seen_far = seen_far or CombatResolver.roll_spot(c.drone, far, 1.0)
	check(not seen_far, "...and its range is not what changes")
	cleanup(c)


## "A slightly greater chance of drone loss."
func test_a_moving_team_loses_drones_slightly_more_often() -> void:
	var still := make_battle(false)
	var moving := make_battle(true)
	var altitude: float = Weather.current.drone_operating_altitude_m()
	var p_still: float = still.bm._drone_failure_chance(6.0, altitude)
	var p_moving: float = moving.bm._drone_failure_chance(6.0, altitude)
	check(p_still > 0.0 and p_moving > p_still, "A drone flown from a team on the move fails more often (%.6f vs %.6f)" % [p_moving, p_still])
	var ratio: float = p_moving / p_still
	check(ratio > 1.3 and ratio < 1.7, "...but only slightly (x%.2f)" % ratio)
	# That same function is what the in-flight roll uses (a stub whose chance is certain must fail the drone).
	var stub := FailStub.new()
	root.add_child(stub)
	stub.set_process(false)
	stub.combat_log = Log.new()
	Weather.current = calm_weather()
	stub.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	stub.drone_team = unit(stub, Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2(m(-800), m(2700)))
	var airframe: Unit = unit(stub, Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(m(500), m(2700)))
	stub.active_drone = airframe
	stub._update_drone_weather(6.0)
	check(stub.active_drone == null, "The in-flight failure roll is driven by _drone_failure_chance")
	stub.combat_log.free()
	stub.free()
	cleanup(still)
	cleanup(moving)
