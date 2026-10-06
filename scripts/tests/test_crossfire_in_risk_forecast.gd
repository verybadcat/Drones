extends SceneTree
## Follow-up the user asked for ("Then do the risk forecast", right after the crossfire multiplier and the 80%
## small-arms change): a unit deciding whether to stay or move uses BattleManager._risk_forecast, which used
## the plain per-shot hit chance of each known threat — so it did not know that standing where it can be fired
## on from several sides is x2 to x4 as dangerous, and could happily accept a spot it should refuse.
##
## Now the forecast works out the safe arc AT THE POINT BEING ASSESSED from the bearings of the known
## direct-fire threats (what its own side can see: the same threats the forecast already counts, knowledge
## locality unchanged) and multiplies each direct-fire threat's chance by the crossfire multiplier. Mortar
## threats (and counter-battery strikes) are outside it, exactly as in the real fire path.
##
## Run: godot --headless --path . --script scripts/tests/test_crossfire_in_risk_forecast.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
const RiskForecast = preload("res://scripts/risk_forecast.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func near(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) <= eps

func m(v: Vector2) -> Vector2:
	return v * GameConfig.PIXELS_PER_METER

## An open spot (meters) where a unit and four shooters 300 m north, south, east and west of it all stand on
## open ground with a clear line of sight to it, found by scanning the map — so the geometry the test needs
## does not depend on where trees happen to be.
func find_open_centre() -> Vector2:
	var offsets := [Vector2(0.0, -300.0), Vector2(0.0, 300.0), Vector2(300.0, 0.0), Vector2(-300.0, 0.0)]
	for gx in range(-1000, 4500, 100):
		for gy in range(300, 3200, 100):
			var c := Vector2(gx, gy)
			var ok: bool = GameConfig.get_terrain_type_at(m(c)) == GameConfig.TerrainType.OPEN
			if ok:
				for o in offsets:
					var p: Vector2 = m(c + o)
					if GameConfig.get_terrain_type_at(p) != GameConfig.TerrainType.OPEN or not GameConfig.has_direct_los(p, m(c)):
						ok = false
						break
			if ok:
				return c
	return Vector2.INF

func make_battle() -> BattleManager:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	return bm

func shooter(bm: BattleManager, pos_m: Vector2) -> Unit:
	var e: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(pos_m))
	e.is_visible = true
	bm.enemy_units.append(e)
	return e

func cleanup(bm: BattleManager) -> void:
	bm.combat_log.free()
	bm.free()

## What the forecast's own chance bookkeeping should give for these threats at `point`: each threat's chance
## times `mult`, over its shots, through the same distribution.
func expected_hit_probability(bm: BattleManager, victim: Unit, point: Vector2, threats: Array, mult: float) -> float:
	var list: Array[Dictionary] = []
	for e in threats:
		var chance: float = minf(CombatResolver.hit_probability(e, victim, false, point, e.global_position) * mult, 1.0)
		list.append({"chance": chance, "shots": RiskForecast.shot_count(e, RiskForecast.HORIZON_SECONDS, GameConfig.TIME_SCALE_NORMAL, false), "mortar": false})
	return float(RiskForecast.damage_distribution(victim, list).hit_probability)


func run() -> void:
	var c: Vector2 = find_open_centre()
	check(not is_inf(c.x), "Setup: an open spot with four clear lines of fire exists")
	if is_inf(c.x):
		quit(1)
		return
	test_one_direction_is_unchanged(c)
	test_opposite_sides_and_four_sides(c)
	test_the_arc_is_judged_at_the_assessed_point_not_where_the_unit_stands(c)
	test_mortar_threats_are_outside_the_mechanism(c)
	print("Crossfire-in-risk-forecast tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_one_direction_is_unchanged(c: Vector2) -> void:
	var bm := make_battle()
	var victim: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(c))
	bm.player_units.append(victim)
	var a: Unit = shooter(bm, c + Vector2(0.0, -300.0))
	var b: Unit = shooter(bm, c + Vector2(0.0, -320.0)) # a second shooter, same direction
	var f: Dictionary = bm._risk_forecast(victim, null, victim.global_position)
	check(int(f.known_threats) == 2, "Setup: both known shooters are counted (%d)" % int(f.known_threats))
	check(near(f.crossfire_multiplier, 1.0), "Two shooters in the same direction: no crossfire (x%.2f)" % f.crossfire_multiplier)
	check(near(f.safe_arc_deg, 360.0), "...the whole circle is safe (%.1f)" % f.safe_arc_deg)
	check(near(f.hit_probability, expected_hit_probability(bm, victim, victim.global_position, [a, b], 1.0), 0.0001), "...and the forecast is the plain one (%.4f)" % f.hit_probability)
	cleanup(bm)


func test_opposite_sides_and_four_sides(c: Vector2) -> void:
	var bm := make_battle()
	var victim: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(c))
	bm.player_units.append(victim)
	var north: Unit = shooter(bm, c + Vector2(0.0, -300.0))
	var south: Unit = shooter(bm, c + Vector2(0.0, 300.0))
	var f: Dictionary = bm._risk_forecast(victim, null, victim.global_position)
	check(near(f.safe_arc_deg, 180.0) and near(f.crossfire_multiplier, 2.5), "North and south: 180 safe, x2.5 (%.1f, x%.2f)" % [f.safe_arc_deg, f.crossfire_multiplier])
	var plain: float = expected_hit_probability(bm, victim, victim.global_position, [north, south], 1.0)
	var crossed: float = expected_hit_probability(bm, victim, victim.global_position, [north, south], 2.5)
	check(near(f.hit_probability, crossed, 0.0001), "The forecast carries the multiplier (%.4f, expected %.4f)" % [f.hit_probability, crossed])
	check(f.hit_probability > plain + 0.01, "...and is clearly worse than the plain forecast (%.4f against %.4f)" % [f.hit_probability, plain])
	var east: Unit = shooter(bm, c + Vector2(300.0, 0.0))
	var west: Unit = shooter(bm, c + Vector2(-300.0, 0.0))
	f = bm._risk_forecast(victim, null, victim.global_position)
	check(near(f.safe_arc_deg, 90.0) and near(f.crossfire_multiplier, 3.25), "All four sides: 90 safe, x3.25 (%.1f, x%.2f)" % [f.safe_arc_deg, f.crossfire_multiplier])
	check(near(f.hit_probability, expected_hit_probability(bm, victim, victim.global_position, [north, south, east, west], 3.25), 0.0001), "...and the forecast carries that too")
	cleanup(bm)


## A unit weighing a move forecasts the arc at the DESTINATION: standing between the two shooters it is in
## crossfire from opposite sides, but a point out to the side puts both on roughly one side.
func test_the_arc_is_judged_at_the_assessed_point_not_where_the_unit_stands(c: Vector2) -> void:
	var bm := make_battle()
	var victim: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(c))
	bm.player_units.append(victim)
	shooter(bm, c + Vector2(0.0, -300.0))
	shooter(bm, c + Vector2(0.0, 300.0))
	var here: Dictionary = bm._risk_forecast(victim, null, m(c))
	# 200 m off to the east: the shooters are now at about +-56 degrees from straight west.. i.e. both on the west side.
	var aside_point: Vector2 = m(c + Vector2(200.0, 0.0))
	var aside: Dictionary = bm._risk_forecast(victim, null, aside_point)
	check(near(here.safe_arc_deg, 180.0), "Standing between them: 180 safe (%.1f)" % here.safe_arc_deg)
	var expected_arc: float = CombatResolver.safe_arc_deg(aside_point, [m(c + Vector2(0.0, -300.0)), m(c + Vector2(0.0, 300.0))])
	check(near(aside.safe_arc_deg, expected_arc) and expected_arc > 180.0 + 20.0, "At a point off to one side the arc is worked out from THERE (%.1f, expected %.1f)" % [aside.safe_arc_deg, expected_arc])
	cleanup(bm)


func test_mortar_threats_are_outside_the_mechanism(c: Vector2) -> void:
	var bm := make_battle()
	var victim: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(c))
	bm.player_units.append(victim)
	shooter(bm, c + Vector2(0.0, -300.0))
	var mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(c + Vector2(0.0, 900.0)))
	mortar.is_visible = true
	bm.enemy_units.append(mortar)
	var f: Dictionary = bm._risk_forecast(victim, null, victim.global_position)
	check(int(f.known_threats) == 2, "Setup: the squad and the mortar are both known threats (%d)" % int(f.known_threats))
	check(near(f.safe_arc_deg, 360.0) and near(f.crossfire_multiplier, 1.0), "A mortar on the far side does not open a second direction (%.1f, x%.2f)" % [f.safe_arc_deg, f.crossfire_multiplier])
	# And its own chance is the plain one: with a rifleman out of the picture the forecast is just the mortar's.
	bm.enemy_units.erase(bm.enemy_units[0])
	var alone: Dictionary = bm._risk_forecast(victim, null, victim.global_position)
	var mortar_only: Array[Dictionary] = [{"chance": CombatResolver.hit_probability(mortar, victim, false, victim.global_position, mortar.global_position), "shots": RiskForecast.shot_count(mortar, RiskForecast.HORIZON_SECONDS, GameConfig.TIME_SCALE_NORMAL, false), "mortar": true}]
	check(near(alone.hit_probability, float(RiskForecast.damage_distribution(victim, mortar_only).hit_probability), 0.0001), "A mortar's forecast chance is untouched (%.4f)" % alone.hit_probability)
	cleanup(bm)
