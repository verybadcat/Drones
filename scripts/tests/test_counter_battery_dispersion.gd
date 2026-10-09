extends SceneTree
## Direct user ruling: counter-battery has two sources of error. "One is an incorrect aim point. The second one is variation of where the
## shot lands from the aim point. The second one should apply in the same way to every mortar shot, regardless of whether or not it is a
## counter battery shot." A counter-battery round now scatters from its aim point through the same function as every other mortar round
## (BattleManager._mortar_dispersion_offset): about 3% of the range (never under 15 m) while nobody watches where it falls, tightening round
## by round when someone does. (The first error, how well the position was located, is a separate question: see the design log.)
##
## Run: godot --headless --path . --script scripts/tests/test_counter_battery_dispersion.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(x: float, y: float = 0.0) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

func median(values: Array) -> float:
	var v: Array = values.duplicate()
	v.sort()
	return v[v.size() / 2]

## Fires `count` counter-battery strikes from `responder` at `target`'s position, all at once, and returns the metres each landed from its aim.
func fire_strikes(bm: BattleManager, responder: Unit, target: Unit, count: int) -> Array:
	var strikes: Array[Dictionary] = []
	for i in count:
		var s := {"attacker": responder, "target": target, "aim_position": target.global_position, "impact_position": target.global_position,
			"fire_time": 0.0, "impact_time": 1e9, "fired": false}
		strikes.append(s)
		bm._pending_counter_battery.append(s)
	bm._resolve_pending_counter_battery()
	var errors: Array = []
	for s in strikes:
		check(s.fired, "Setup: the strike was fired")
		errors.append(s.impact_position.distance_to(s.aim_position) / GameConfig.PIXELS_PER_METER)
	return errors

func make(range_m: float) -> Dictionary:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.scenario_elapsed_time = 1000.0
	var target: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(300, 1700)); bm.player_units.append(target)
	var responder: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(300 + range_m, 1700)); bm.enemy_units.append(responder)
	responder.seconds_stationary = 1e9
	responder.mortar_rounds_remaining = 100000
	return {"bm": bm, "target": target, "responder": responder}

func run() -> void:
	GameConfig.set_active_map("pishchane")
	seed(41)
	# 1. nobody watching: the median miss is the CEP, 3% of the range (here 3,000 m: 90 m), and the same as an ordinary round's
	var c := make(3000.0)
	var bm: BattleManager = c.bm
	var errors: Array = fire_strikes(bm, c.responder, c.target, 400)
	var cep: float = 0.03 * 3000.0
	var med: float = median(errors)
	check(med > 0.75 * cep and med < 1.25 * cep, "A counter-battery round from 3,000 m lands a median %.0f m from its aim, about the 90 m CEP of any unobserved round" % med)
	var ordinary: Array = []
	for i in 400:
		var fresh: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(300, 1500 + i)) # a new target each time: no adjustment is carried over
		bm.player_units.append(fresh)
		var aim: Vector2 = fresh.global_position
		ordinary.append(bm._mortar_dispersion_offset(c.responder, fresh, aim).length() / GameConfig.PIXELS_PER_METER)
	var ord_med: float = median(ordinary)
	check(absf(med - ord_med) < 0.2 * cep, "...the same as an ordinary round's (%.0f m against %.0f m)" % [med, ord_med])
	check(errors.min() < 0.9 * cep and errors.max() > 1.5 * cep, "...spread over a wide range (%.0f to %.0f m), not a fixed offset" % [errors.min(), errors.max()])
	# the strike's own record: aim kept, landing is something else, and before firing the landing was the aim (planners read it)
	var pending := {"attacker": c.responder, "target": c.target, "aim_position": c.target.global_position, "impact_position": c.target.global_position, "fire_time": 1e9, "impact_time": 1e9, "fired": false}
	bm._pending_counter_battery.append(pending)
	bm._resolve_pending_counter_battery()
	check(not pending.fired and pending.impact_position == pending.aim_position, "Before it fires, a strike's landing point is still its aim point")
	bm.combat_log.free()
	bm.free()

	# 2. a short shot is held to the floor (15 m), not 3% of 500 m
	c = make(500.0)
	bm = c.bm
	errors = fire_strikes(bm, c.responder, c.target, 400)
	med = median(errors)
	check(med > 11.0 and med < 19.0, "From 500 m the median miss is about the 15 m floor (%.1f m)" % med)
	bm.combat_log.free()
	bm.free()

	# 3. when someone on the shooter's side watches where the rounds fall, the error shrinks round by round, as for any other round
	c = make(3000.0)
	bm = c.bm
	var observer: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(300 + 250, 1700)); bm.enemy_units.append(observer)
	check(CombatResolver.has_live_observer(c.target, bm.enemy_units), "Setup: an enemy squad can see the target")
	var first_errors: Array = []
	var sixth_errors: Array = []
	for trial in 120:
		bm._mortar_fire_adjustment.clear()
		var series: Array = fire_strikes(bm, c.responder, c.target, 6)
		first_errors.append(series[0])
		sixth_errors.append(series[5])
	check(median(sixth_errors) < 0.6 * median(first_errors), "With the fall of shot watched, the sixth round lands much closer than the first (%.0f m against %.0f m)" % [median(sixth_errors), median(first_errors)])
	bm.combat_log.free()
	bm.free()
	print("Counter-battery dispersion tests: %d failures" % failures)
	quit(1 if failures else 0)
