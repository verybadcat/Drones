extends SceneTree
## Guards _mortar_impacts — the real-HE-landing visual effect, distinct
## from _fire_flashes' own tracer-at-firing-time visual (a shell's real
## flight time means it lands well after the tracer has already faded).
## An impact must be recorded at the real landing spot regardless of
## what happened to the target in the meantime, and pruned after
## IMPACT_EFFECT_DURATION real seconds.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_impact_effects.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func make_battle():
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	return bm


func test_ordinary_mortar_shot_records_impact_at_the_right_spot() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	bm.player_units.append(mortar)
	var target: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(300, 0))
	bm.enemy_units.append(target)
	var impact_point := Vector2(305, 4)
	var shots: Array[Dictionary] = [{
		"mortar": mortar, "target": target, "aim_point": target.global_position,
		"impact_point": impact_point, "impact_time": bm.scenario_elapsed_time - 1.0,
	}]
	bm._pending_mortar_shots = shots
	bm._mortar_impacts.clear()
	bm._resolve_pending_mortar_shots()
	check(bm._mortar_impacts.size() == 1, "An ordinary resolved mortar shot must record exactly one impact")
	if not bm._mortar_impacts.is_empty():
		check(bm._mortar_impacts[0].position == impact_point, "The recorded impact must be at the round's real impact_point, not the aim point or the target")


## The round physically lands even if the target has since been
## destroyed/withdrawn/surrendered — a real shell doesn't un-fire itself.
func test_impact_recorded_even_when_target_no_longer_valid() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	bm.player_units.append(mortar)
	var target: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(300, 0))
	bm.enemy_units.append(target)
	target.state = Unit.State.DESTROYED
	var impact_point := Vector2(305, 4)
	var shots: Array[Dictionary] = [{
		"mortar": mortar, "target": target, "aim_point": target.global_position,
		"impact_point": impact_point, "impact_time": bm.scenario_elapsed_time - 1.0,
	}]
	bm._pending_mortar_shots = shots
	bm._mortar_impacts.clear()
	bm._resolve_pending_mortar_shots()
	check(bm._mortar_impacts.size() == 1, "The round must still physically land (and be recorded) even if the target is already destroyed by the time it arrives")


func test_counter_battery_strike_records_impact() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	bm.player_units.append(mortar)
	var enemy_mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(2000, 0))
	bm.enemy_units.append(enemy_mortar)
	var impact_point := Vector2(10, 0)
	var strikes: Array[Dictionary] = [{
		"target": mortar, "attacker": enemy_mortar, "fired": true,
		"impact_position": impact_point, "impact_time": bm.scenario_elapsed_time - 1.0,
	}]
	bm._pending_counter_battery = strikes
	bm._mortar_impacts.clear()
	bm._resolve_pending_counter_battery()
	check(bm._mortar_impacts.size() == 1, "A resolved counter-battery strike must record an impact")
	check(bm._mortar_impacts[0].position == impact_point, "The recorded impact must be at the strike's own real impact_position")


func test_impact_pruned_after_its_duration_elapses() -> void:
	var bm = make_battle()
	bm._mortar_impacts.append({"position": Vector2(50, 50), "time": bm.elapsed_time})
	bm.elapsed_time += bm.IMPACT_EFFECT_DURATION * 0.5
	bm._prune_fire_flashes()
	check(bm._mortar_impacts.size() == 1, "An impact younger than IMPACT_EFFECT_DURATION must not be pruned yet")
	bm.elapsed_time += bm.IMPACT_EFFECT_DURATION
	bm._prune_fire_flashes()
	check(bm._mortar_impacts.is_empty(), "An impact older than IMPACT_EFFECT_DURATION must be pruned")


func run() -> void:
	test_ordinary_mortar_shot_records_impact_at_the_right_spot()
	test_impact_recorded_even_when_target_no_longer_valid()
	test_counter_battery_strike_records_impact()
	test_impact_pruned_after_its_duration_elapses()
	print("Mortar impact-effect tests: %d failures" % failures)
	quit(1 if failures else 0)
