extends SceneTree
## Run: godot --headless --path . --script scripts/tests/test_unit_doctrine.gd
const Orders = preload("res://scripts/unit_doctrine.gd")
const Forecast = preload("res://scripts/risk_forecast.gd")
const Log = preload("res://scripts/tests/test_combat_log.gd")
const Suite = preload("res://scripts/tests/test_decision_ai.gd")
var failures := 0

class SplashBattle extends BattleManager:
	var splash: Unit
	func _collateral_victim(_impact_point: Vector2, _exclude: Array[Unit], _radius: float, _chance_at: Callable, _only_squads: bool = false) -> Unit:
		return splash

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func make_battle(script = BattleManager):
	var bm = script.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	return bm

func clean(bm) -> void:
	bm.combat_log.free()
	bm.free()

func spawn(bm, team: Unit.Team, kind: Unit.Kind, point: Vector2) -> Unit:
	var u: Unit = bm._make_unit(team, kind, point)
	if team == Unit.Team.PLAYER: bm.player_units.append(u)
	else: bm.enemy_units.append(u)
	u.is_visible = true
	return u

func test_targeting_and_forecast() -> void:
	var bm = make_battle()
	var mortar := spawn(bm, Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	var near := spawn(bm, Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(20, 0))
	var far := spawn(bm, Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(100, 0))
	far.pips = 1
	mortar.mortar_rounds_remaining = GameConfig.MORTAR_STARTING_AMMO
	bm.unit_type_doctrines[Unit.Team.PLAYER] = Orders.sanitize({"mortar": {"targeting": "nearest"}})
	check(bm._pick_target(mortar, bm.enemy_units) == near, "Nearest policy must choose nearby target")
	bm.unit_type_doctrines[Unit.Team.PLAYER] = Orders.sanitize({"mortar": {"targeting": "weakest"}})
	check(bm._pick_target(mortar, bm.enemy_units) == far, "Weakest policy must change the choice")
	check(bm.unit_doctrine_for(near).targeting == "inherit", "Player settings must not leak to enemy")
	check(bm.unit_doctrine_for(spawn(bm, Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2.ZERO)).targeting == "inherit", "Mortar settings must not leak to infantry")
	far.is_visible = false
	check(bm._pick_target(mortar, bm.enemy_units) == near, "Custom priority cannot target a hidden unit")
	seed(314)
	var expected := randi()
	seed(314)
	bm._risk_forecast(mortar, near, mortar.position)
	check(randi() == expected, "Risk forecasting must not draw simulation randomness")
	near.is_visible = false
	check(bm._risk_forecast(mortar, null, mortar.position).known_threats == 0, "Unobserved units must not become forecast threats")
	clean(bm)

func test_risk_changes_actions() -> void:
	for risk in ["preserve", "mission_first"]:
		var bm = make_battle()
		var mortar := spawn(bm, Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
		var threat := spawn(bm, Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(10, 0))
		threat.base_hit_chance = 1.0
		mortar.base_hit_chance = 1.0
		mortar.fire_timer = 0.0
		bm.unit_type_doctrines[Unit.Team.PLAYER] = Orders.sanitize({"mortar": {"targeting": "nearest", "risk": risk}})
		bm._update_ground_risk_orders()
		# A target cached earlier in the tick must not bypass a later risk rejection.
		bm._mortar_tick_shot[mortar] = {"resolved": true, "target": threat}
		var rounds := mortar.mortar_rounds_remaining
		bm._tick_fire(mortar, 1.0, 60.0, bm.enemy_units)
		if risk == "preserve":
			check(bm._risk_holds.has(mortar), "Preserve profile must reject high exposure before firing")
			check(mortar.mortar_rounds_remaining == rounds, "Risk rejection must actually prevent the shot")
			var destination := mortar.move_target
			bm._decide_mortar_action(mortar)
			check(mortar.move_target == destination, "Mortar decision ladder must not overwrite the safety decision")
		else:
			check(not bm._risk_holds.has(mortar), "Mission-first profile must accept the same opportunity")
			check(mortar.mortar_rounds_remaining == rounds - 1, "Accepted opportunity must actually fire")
		clean(bm)

func test_damage_credit() -> void:
	var bm = make_battle(SplashBattle)
	var shooter := spawn(bm, Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2.ZERO)
	shooter.base_hit_chance = 100.0
	var target := spawn(bm, Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(20, 0))
	var nearby := spawn(bm, Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(21, 0))
	bm.splash = nearby
	var before := target.pips + nearby.pips
	bm._resolve_fire_and_check_bunching(shooter, target, target.global_position)
	var row: Dictionary = bm.unit_combat_stats.rows[shooter.get_instance_id()]
	check(row.casualties == before - target.pips - nearby.pips, "Direct and splash casualties must both credit the shooter")
	check(row.casualties == 2 and row.hits == 2, "Two direct/splash damage events must count exactly once")
	check(row.killed + row.wounded == row.casualties, "Killed and wounded must reconcile to casualties")
	# Clear the forced splash victim before moving on — counter-battery
	# resolution now also checks for a collateral victim (any unit near
	# the actual impact point, not just the intended target — see
	# _resolve_pending_counter_battery's own doc comment), and SplashBattle's
	# override would otherwise keep forcing `nearby` into that unrelated
	# scenario too, well past the one it was set up for.
	bm.splash = null
	var artillery := spawn(bm, Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	artillery.state = Unit.State.DESTROYED
	var enemy_mortar := spawn(bm, Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(100, 0))
	var hp := enemy_mortar.pips
	bm._pending_counter_battery.append({"attacker": artillery, "target": enemy_mortar, "impact_position": enemy_mortar.position, "fired": true, "impact_time": 0.0})
	bm._resolve_pending_counter_battery()
	check(bm.unit_combat_stats.rows[artillery.get_instance_id()].casualties == hp - enemy_mortar.pips, "Delayed counter-battery damage must credit its original, now-destroyed shooter")
	check(bm.unit_combat_stats.rows[shooter.get_instance_id()].casualties == 2, "Other units must not receive counter-battery credit")
	var delayed_target := spawn(bm, Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(180, 0))
	artillery.state = Unit.State.ACTIVE
	artillery.base_hit_chance = 100.0
	var before_delayed: int = bm.unit_combat_stats.rows[artillery.get_instance_id()].casualties
	var target_hp := delayed_target.pips
	bm._launch_mortar_shot(artillery, delayed_target)
	artillery.state = Unit.State.DESTROYED
	bm.scenario_elapsed_time += GameConfig.MORTAR_FLIGHT_TIME
	bm._resolve_pending_mortar_shots()
	check(bm.unit_combat_stats.rows[artillery.get_instance_id()].casualties - before_delayed == target_hp - delayed_target.pips, "A mortar round landing after its shooter dies must keep its damage credit")
	var report: String = "\n".join(bm.unit_combat_stats.report_lines())
	check(report.contains(shooter.display_name()) and report.contains(artillery.display_name()), "Report must identify every damage dealer")
	clean(bm)

## Collateral damage is real-world grounded and side-agnostic: an attack
## is aimed at a UNIT but resolves against a LOCATION, so anyone actually
## near that location — either side, not just an ally of the specific
## unit that was aimed at — has a real chance of being caught too, and
## that chance doesn't depend on whether the aimed-at unit itself was hit
## (a round that misses its intended target still lands somewhere real).
## See BattleManager._resolve_fire_and_check_bunching / _collateral_victim.
func test_collateral_damage() -> void:
	# Case 1: a mortar's blast has no ally-only restriction — it can catch
	# a unit on the SHOOTER'S OWN side standing near the target, not just
	# an ally of whoever was actually aimed at.
	var found_shooter_side_blast := false
	for i in 300:
		seed(i)
		var bm = make_battle()
		var shooter := spawn(bm, Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
		var enemy_mortar := spawn(bm, Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(20, 0))
		var own_side_bystander := spawn(bm, Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(20, 5))
		var before_pips := own_side_bystander.pips
		bm._resolve_fire_and_check_bunching(shooter, enemy_mortar, enemy_mortar.global_position)
		if own_side_bystander.pips < before_pips:
			found_shooter_side_blast = true
		clean(bm)
		if found_shooter_side_blast:
			break
	check(found_shooter_side_blast, "A mortar shot at an enemy mortar must be able to hit a unit on the SHOOTER'S OWN side near the target — mortar blast isn't restricted to allies of whoever was aimed at")

	# Case 2: collateral is possible even when the primary aimed-at unit
	# is missed outright — decoupled from the primary hit/miss roll.
	var found_collateral_despite_miss := false
	for i in 300:
		seed(i)
		var bm = make_battle()
		var shooter := spawn(bm, Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
		shooter.base_hit_chance = 0.0 # guaranteed miss on the primary target
		var target := spawn(bm, Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(20, 0))
		var bystander := spawn(bm, Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(20, 5))
		var before_pips := bystander.pips
		bm._resolve_fire_and_check_bunching(shooter, target, target.global_position)
		if bystander.pips < before_pips:
			found_collateral_despite_miss = true
		clean(bm)
		if found_collateral_despite_miss:
			break
	check(found_collateral_despite_miss, "Collateral damage must be possible even when the primary aimed-at unit is missed — attacks are aimed at a unit but hit a location")

	# Case 3: a DRONE is never a collateral victim (airborne).
	var drone_ever_hit := false
	for i in 300:
		seed(i)
		var bm = make_battle()
		var shooter := spawn(bm, Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
		shooter.base_hit_chance = 1.0
		var target := spawn(bm, Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(20, 0))
		var drone := spawn(bm, Unit.Team.ENEMY, Unit.Kind.DRONE, Vector2(20, 5))
		var before_pips := drone.pips
		bm._resolve_fire_and_check_bunching(shooter, target, target.global_position)
		if drone.pips < before_pips:
			drone_ever_hit = true
		clean(bm)
	check(not drone_ever_hit, "A DRONE must never be a collateral victim — airborne, same as its other protections")

	# Case 4: a counter-battery strike's own impact can also produce a
	# collateral hit on a nearby bystander, not just its specific target.
	var found_cb_collateral := false
	for i in 300:
		seed(i)
		var bm = make_battle()
		var responder := spawn(bm, Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2.ZERO)
		var mortar_target := spawn(bm, Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(20, 0))
		var bystander := spawn(bm, Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(20, 5))
		bm._pending_counter_battery.append({
			"attacker": responder, "target": mortar_target, "impact_position": mortar_target.global_position,
			"fired": true, "impact_time": 0.0,
		})
		var before_pips := bystander.pips
		bm._resolve_pending_counter_battery()
		if bystander.pips < before_pips:
			found_cb_collateral = true
		clean(bm)
		if found_cb_collateral:
			break
	check(found_cb_collateral, "A counter-battery strike's own impact must be able to produce a collateral hit on a nearby bystander, not just its specific mortar target")


func test_drone_risk() -> void:
	var bm = make_battle()
	var crew := spawn(bm, Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2.ZERO)
	bm.drone_team = crew
	var drone := spawn(bm, Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2.ZERO)
	drone.drone_battery_charge = 110.0 / GameConfig.DRONE_FULL_CHARGE_FLIGHT_TIME + GameConfig.DRONE_LANDING_CHARGE_COST
	var destination := Vector2(GameConfig.DRONE_CRUISE_SPEED * 60.0, 0)
	bm.unit_type_doctrines[Unit.Team.PLAYER] = Orders.sanitize({"drone": {"risk": "preserve"}})
	check(not bm._drone_risk_accepts(drone, destination), "Preserve drone must refuse a task that prevents returning home")
	bm.unit_type_doctrines[Unit.Team.PLAYER] = Orders.sanitize({"drone": {"risk": "mission_first"}})
	check(bm._drone_risk_accepts(drone, destination), "Expendable drone may accept useful observation without enough battery to return")
	clean(bm)


func test_full_battles() -> void:
	var helper = Suite.new()
	for mode in [GameConfig.ReconMode.SPOTTER, GameConfig.ReconMode.DRONE_TEAM]:
		var bm = make_battle()
		var setup: Dictionary = helper.doctrine("deliberate", mode, 17)
		var types := {}
		for key in Orders.TYPES: types[key] = {"targeting": "nearest", "risk": "balanced"}
		setup.player_unit_types = types
		setup.enemy_unit_types = types
		bm.start_battle(setup, bm.combat_log)
		var ticks := 0
		while not bm.battle_over and ticks < 30000:
			bm._process(0.5)
			ticks += 1
		check(bm.battle_over, "Configured battle must complete in mode %d" % mode)
		for row in bm.unit_combat_stats.rows.values():
			check(row.killed + row.wounded == row.casualties, "Lifetime damage totals must reconcile")
		check(bm.decisions.latest.values().any(func(e): return e.channel == "Self-risk assessment"), "Configured battle must record the risk decisions")
		print("Per-type battle completed: mode %d, %d ticks" % [mode, ticks])
		clean(bm)
	helper.free()

func run() -> void:
	test_targeting_and_forecast()
	test_risk_changes_actions()
	test_damage_credit()
	test_collateral_damage()
	test_drone_risk()
	test_full_battles()
	print("Per-type doctrine tests: %d failures" % failures)
	quit(1 if failures else 0)
