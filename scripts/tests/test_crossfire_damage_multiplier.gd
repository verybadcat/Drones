extends SceneTree
## Direct user design (after a long, fruitless search for a quantitative source on how much worse it is to be
## fired on from several directions): a unit's "safe arc" is the largest circular arc from which it is NOT
## taking fire — one direction leaves 360, a ten-degree spread of shooters 350, two opposite sides 180, four
## sides (N, S, E, W) 90. Expected damage taken is x1 at a 360 safe arc, x2 at 240, x3 at 120, x4 at 0
## (linear). "Taking fire" means DIRECT fire from a shooter that has fired at the unit within the last 10
## tactical seconds, at the bearing it fired from; mortar fire does not count toward the arc.
##
## Before this, nothing about the direction of fire entered the hit chance at all (see
## CombatResolver.hit_probability): three shooters on three sides just meant three independent rolls.
##
## Run: godot --headless --path . --script scripts/tests/test_crossfire_damage_multiplier.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(x: float, y: float) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

func run() -> void:
	test_the_safe_arc_geometry()
	test_the_multiplier_scale()
	test_shots_are_recorded_by_bearing_and_expire()
	test_mortar_fire_does_not_count_toward_the_arc()
	test_the_multiplier_reaches_the_hit_chance()
	test_the_hit_rate_really_scales()
	test_the_real_fire_path_applies_it()
	print("Crossfire damage multiplier tests: %d failures" % failures)
	quit(1 if failures else 0)


func near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps


func test_the_safe_arc_geometry() -> void:
	var here := Vector2(100.0, 100.0)
	check(near(CombatResolver.safe_arc_deg(here, []), 360.0), "Nobody firing: the whole 360 is safe")
	check(near(CombatResolver.safe_arc_deg(here, [here + Vector2(50.0, 0.0)]), 360.0), "One shooter: 360 safe (all the fire is from one direction)")
	check(near(CombatResolver.safe_arc_deg(here, [here + Vector2(50.0, 0.0), here + Vector2(80.0, 0.0)]), 360.0), "Two shooters in the same direction: still 360")
	# "A unit taking fire from only a ten degree range would have a 350 degree safe arc."
	var ten: Array = [here + Vector2.from_angle(deg_to_rad(40.0)) * 60.0, here + Vector2.from_angle(deg_to_rad(50.0)) * 90.0]
	check(near(CombatResolver.safe_arc_deg(here, ten), 350.0), "Fire from a ten-degree range: 350 safe (%.2f)" % CombatResolver.safe_arc_deg(here, ten))
	check(near(CombatResolver.safe_arc_deg(here, [here + Vector2(60.0, 0.0), here + Vector2(-60.0, 0.0)]), 180.0), "Two opposite sides: 180")
	var four: Array = [here + Vector2(60.0, 0.0), here + Vector2(-60.0, 0.0), here + Vector2(0.0, 60.0), here + Vector2(0.0, -60.0)]
	check(near(CombatResolver.safe_arc_deg(here, four), 90.0), "North, south, east and west: 90")
	# The gap that wraps through the +-180 degree seam must count: shooters at 170 and -170 degrees are only 20 apart
	# on that side, so the safe arc is the other 340.
	var seam: Array = [here + Vector2.from_angle(deg_to_rad(170.0)) * 60.0, here + Vector2.from_angle(deg_to_rad(-170.0)) * 60.0]
	check(near(CombatResolver.safe_arc_deg(here, seam), 340.0), "Shooters either side of the 180-degree seam are 20 degrees apart, not 340 (%.2f)" % CombatResolver.safe_arc_deg(here, seam))
	# Three at 120 degrees apart leave 120.
	var three: Array = []
	for a in [0.0, 120.0, 240.0]:
		three.append(here + Vector2.from_angle(deg_to_rad(a)) * 70.0)
	check(near(CombatResolver.safe_arc_deg(here, three), 120.0), "Three evenly spaced: 120")
	check(near(CombatResolver.safe_arc_deg(here, [here, here + Vector2(60.0, 0.0)]), 360.0), "A shooter on the unit's own spot has no bearing and is ignored")


func test_the_multiplier_scale() -> void:
	check(near(CombatResolver.crossfire_multiplier(360.0), 1.0), "360 safe arc: x1 (current damage)")
	check(near(CombatResolver.crossfire_multiplier(240.0), 2.0), "240 safe arc: x2")
	check(near(CombatResolver.crossfire_multiplier(120.0), 3.0), "120 safe arc: x3")
	check(near(CombatResolver.crossfire_multiplier(0.0), 4.0), "0 safe arc: x4")
	check(near(CombatResolver.crossfire_multiplier(180.0), 2.5), "Linear in between: 180 is x2.5")
	check(near(CombatResolver.crossfire_multiplier(90.0), 3.25), "...and 90 is x3.25")
	check(near(CombatResolver.crossfire_multiplier(-20.0), 4.0) and near(CombatResolver.crossfire_multiplier(500.0), 1.0), "Out-of-range arcs are clamped")


func make_battle() -> BattleManager:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	return bm

func squad(bm: BattleManager, team: Unit.Team, pos_m: Vector2) -> Unit:
	var u: Unit = bm._make_unit(team, Unit.Kind.SQUAD, m(pos_m.x, pos_m.y))
	(bm.player_units if team == Unit.Team.PLAYER else bm.enemy_units).append(u)
	u.base_hit_chance = 0.0 # these tests are about the bookkeeping: nobody should actually get hurt
	return u

func cleanup(bm: BattleManager) -> void:
	bm.combat_log.free()
	bm.free()


func test_shots_are_recorded_by_bearing_and_expire() -> void:
	var bm := make_battle()
	var target: Unit = squad(bm, Unit.Team.PLAYER, Vector2(0.0, 0.0))
	var north: Unit = squad(bm, Unit.Team.ENEMY, Vector2(0.0, -300.0))
	var south: Unit = squad(bm, Unit.Team.ENEMY, Vector2(0.0, 300.0))
	var east: Unit = squad(bm, Unit.Team.ENEMY, Vector2(300.0, 0.0))
	var west: Unit = squad(bm, Unit.Team.ENEMY, Vector2(-300.0, 0.0))
	# One shooter, firing over and over: still all one direction.
	for i in 5:
		bm.scenario_elapsed_time = float(i)
		bm._resolve_fire_and_check_bunching(north, target, target.global_position)
	check(near(bm._safe_arc_of(target), 360.0), "One shooter firing repeatedly leaves a 360 safe arc (%.1f)" % bm._safe_arc_of(target))
	check(near(bm._crossfire_multiplier_against(target), 1.0), "...and no extra damage (x%.2f)" % bm._crossfire_multiplier_against(target))
	# A second side joins in.
	bm.scenario_elapsed_time = 5.0
	bm._resolve_fire_and_check_bunching(south, target, target.global_position)
	check(near(bm._safe_arc_of(target), 180.0), "North and south: 180 safe (%.1f)" % bm._safe_arc_of(target))
	bm._resolve_fire_and_check_bunching(east, target, target.global_position)
	bm._resolve_fire_and_check_bunching(west, target, target.global_position)
	check(near(bm._safe_arc_of(target), 90.0), "All four sides: 90 safe (%.1f)" % bm._safe_arc_of(target))
	check(near(bm._crossfire_multiplier_against(target), 3.25), "...x3.25 (x%.2f)" % bm._crossfire_multiplier_against(target))
	# Ten tactical seconds after the last shots, the memory is gone; a shooter that stops drops out first.
	bm.scenario_elapsed_time = 5.0 + GameConfig.CROSSFIRE_MEMORY_S - 0.5
	bm._resolve_fire_and_check_bunching(north, target, target.global_position) # only north refreshes
	check(near(bm._safe_arc_of(target), 90.0), "Just inside the memory window all four still count (%.1f)" % bm._safe_arc_of(target))
	bm.scenario_elapsed_time = 5.0 + GameConfig.CROSSFIRE_MEMORY_S + 1.0
	check(near(bm._safe_arc_of(target), 360.0), "Past ten seconds only the one that kept firing is left: 360 (%.1f)" % bm._safe_arc_of(target))
	# Another unit's arc is its own.
	var other: Unit = squad(bm, Unit.Team.PLAYER, Vector2(500.0, 500.0))
	check(near(bm._safe_arc_of(other), 360.0), "Fire at one unit does not put another into crossfire")
	cleanup(bm)


func test_mortar_fire_does_not_count_toward_the_arc() -> void:
	var bm := make_battle()
	var target: Unit = squad(bm, Unit.Team.PLAYER, Vector2(0.0, 0.0))
	var rifle: Unit = squad(bm, Unit.Team.ENEMY, Vector2(0.0, -300.0))
	var mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(0.0, 900.0))
	bm.enemy_units.append(mortar)
	mortar.base_hit_chance = 0.0
	bm.scenario_elapsed_time = 1.0
	bm._resolve_fire_and_check_bunching(rifle, target, target.global_position)
	bm._resolve_fire_and_check_bunching(mortar, target, target.global_position)
	check(near(bm._safe_arc_of(target), 360.0), "A mortar round from the opposite side does not open a second direction (%.1f)" % bm._safe_arc_of(target))
	check(not bm._recent_direct_fire.get(target, {}).has(mortar), "Mortar rounds are not recorded as direct fire at all")
	cleanup(bm)


## The multiplier is in the hit chance itself, for the shot being resolved.
func test_the_multiplier_reaches_the_hit_chance() -> void:
	var bm := make_battle()
	var target: Unit = squad(bm, Unit.Team.PLAYER, Vector2(0.0, 0.0))
	var shooter: Unit = squad(bm, Unit.Team.ENEMY, Vector2(0.0, -300.0))
	shooter.base_hit_chance = 0.05
	var base: float = CombatResolver.hit_probability(shooter, target)
	check(base > 0.0 and base * 4.0 < 1.0, "Setup: a small unclamped base chance (%.3f)" % base)
	check(near(CombatResolver.hit_probability(shooter, target, 1.0, Vector2.INF, Vector2.INF, 2.0), base * 2.0, 0.0001), "A x2 crossfire doubles the hit chance")
	check(near(CombatResolver.hit_probability(shooter, target, 1.0, Vector2.INF, Vector2.INF, 4.0), base * 4.0, 0.0001), "...and x4 quadruples it")
	check(near(CombatResolver.hit_probability(shooter, target), base, 0.0000001), "No crossfire is exactly the old chance")
	shooter.base_hit_chance = 0.9
	check(CombatResolver.hit_probability(shooter, target, 1.0, Vector2.INF, Vector2.INF, 4.0) <= 1.0, "A chance can never exceed 1")
	cleanup(bm)


## Observed hit rate, many rolls through the real resolve_fire: x2.5 at a 180 safe arc.
func test_the_hit_rate_really_scales() -> void:
	seed(4242)
	var bm := make_battle()
	var target: Unit = squad(bm, Unit.Team.PLAYER, Vector2(0.0, 0.0))
	var shooter: Unit = squad(bm, Unit.Team.ENEMY, Vector2(0.0, -300.0))
	shooter.base_hit_chance = 0.05
	var trials := 20000
	var plain := 0
	var crossed := 0
	var mult: float = CombatResolver.crossfire_multiplier(180.0)
	for i in trials:
		if CombatResolver.resolve_fire(shooter, target):
			plain += 1
		if CombatResolver.resolve_fire(shooter, target, [], [], 1.0, 0.0, mult):
			crossed += 1
	var ratio: float = float(crossed) / float(maxi(plain, 1))
	check(ratio > 2.2 and ratio < 2.8, "Two opposite sides do about 2.5 times the hits of one (observed %.2f from %d vs %d of %d)" % [ratio, crossed, plain, trials])
	cleanup(bm)


var _hits_taken := 0
func _count_hit(_u: Unit) -> void:
	_hits_taken += 1

## The whole chain, through BattleManager._resolve_fire_and_check_bunching (record the shot, work out the arc,
## pass the multiplier to the roll): the same number of shots does about 3.25 times the hits when they come
## from four sides as when they all come from one.
func test_the_real_fire_path_applies_it() -> void:
	seed(777)
	var bm := make_battle()
	var target: Unit = squad(bm, Unit.Team.PLAYER, Vector2(0.0, 0.0))
	target.max_pips = 1000000
	target.pips = 1000000 # cannot be destroyed, so every hit keeps being counted
	target.took_hit.connect(_count_hit)
	var shooters: Array[Unit] = []
	for p in [Vector2(0.0, -300.0), Vector2(0.0, 300.0), Vector2(300.0, 0.0), Vector2(-300.0, 0.0)]:
		var s: Unit = squad(bm, Unit.Team.ENEMY, p)
		s.base_hit_chance = 0.03
		shooters.append(s)
	var shots := 6000
	_hits_taken = 0
	for i in shots: # one direction only
		bm._resolve_fire_and_check_bunching(shooters[0], target, target.global_position)
	var one_side := _hits_taken
	_hits_taken = 0
	bm._recent_direct_fire.clear()
	for i in shots: # the same shots, spread over all four sides in turn
		bm._resolve_fire_and_check_bunching(shooters[i % 4], target, target.global_position)
	var four_sides := _hits_taken
	var ratio: float = float(four_sides) / float(maxi(one_side, 1))
	check(near(bm._safe_arc_of(target), 90.0), "Setup: four sides leave 90 safe (%.1f)" % bm._safe_arc_of(target))
	check(ratio > 2.8 and ratio < 3.7, "Four sides do about 3.25 times the hits of one through the real fire path (observed %.2f: %d vs %d of %d shots)" % [ratio, four_sides, one_side, shots])
	cleanup(bm)
