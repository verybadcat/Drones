extends SceneTree
## Direct user ruling: "The effects of a shell only depend on where it lands. Friendly fire should be possible too." Before, a round only
## hurt anyone if the unit it was AIMED at was within MORTAR_EVASION_RADIUS (40 m) of where it landed (and then the aimed-at unit had its
## own roll, plus one bystander at most): a round that went 50 m wide of its target landed "on empty ground" even with another squad
## standing at the impact point. Now every unit of either side within reach of where the round lands is caught by the same distance and
## cover model (CombatResolver.blast_casualty_chance), whoever it was aimed at, whichever side fired, whether or not the aimed-at unit is
## still there.
##
## Run: godot --headless --path . --script scripts/tests/test_shell_effects_depend_on_landing.gd
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
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	return bm

func squad(bm: BattleManager, team: Unit.Team, x_m: float, y_m: float = 0.0) -> Unit:
	var u: Unit = bm._make_unit(team, Unit.Kind.SQUAD, Vector2(m(x_m), m(y_m)))
	if team == Unit.Team.PLAYER:
		bm.player_units.append(u)
	else:
		bm.enemy_units.append(u)
	u.pips = u.max_pips
	# Lying, not upright: nothing here is about posture (test_posture_under_fire is), and the figures below were set for men down.
	u.gone_to_ground = true
	return u

## One round from `mortar`, aimed at `target`, landing at (x_m, y_m), resolved through the real path.
func fire(bm: BattleManager, mortar: Unit, target: Unit, x_m: float, y_m: float = 0.0) -> void:
	var shots: Array[Dictionary] = [{
		"mortar": mortar, "target": target, "aim_point": target.global_position,
		"impact_point": Vector2(m(x_m), m(y_m)), "impact_time": bm.scenario_elapsed_time - 1.0,
	}]
	bm._pending_mortar_shots = shots
	bm._resolve_pending_mortar_shots()

func hurt(u: Unit) -> bool:
	return u.pips < u.max_pips or u.state != Unit.State.ACTIVE

func reset(u: Unit) -> void:
	u.pips = u.max_pips
	u.state = Unit.State.ACTIVE

func run() -> void:
	# 1. a round aimed at A that lands 80 m from A and 5 m from B hurts B (it used to hurt nobody: "empty ground")
	var bm := make()
	var gun: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(m(-3000.0), 0.0))
	bm.player_units.append(gun)
	var a := squad(bm, Unit.Team.ENEMY, 0.0)
	var b := squad(bm, Unit.Team.ENEMY, 80.0)
	var hits_b := 0
	var hits_a := 0
	seed(11)
	var n := 400
	for i in n:
		reset(a)
		reset(b)
		fire(bm, gun, a, 85.0)
		if hurt(b):
			hits_b += 1
		if hurt(a):
			hits_a += 1
	check(hits_b > n * 0.7, "A squad 5 m from where the round lands is caught most of the time even though the round was aimed at another squad 85 m away (%d of %d)" % [hits_b, n])
	check(hits_a < n * 0.15, "...and the aimed-at squad, 85 m from the impact, only rarely (%d of %d)" % [hits_a, n])

	# 2. the aimed-at unit is no longer there at all: the round hurts whoever is at the impact point
	reset(a)
	reset(b)
	a.state = Unit.State.DESTROYED
	var hits := 0
	for i in n:
		reset(b)
		a.state = Unit.State.DESTROYED
		fire(bm, gun, a, 80.0)
		if hurt(b):
			hits += 1
	check(hits > n * 0.8, "With the aimed-at unit already gone, a squad at the impact point is still caught (%d of %d)" % [hits, n])
	bm.combat_log.free()
	bm.free()

	# 3. friendly fire: our mortar's round aimed at an enemy squad lands among our own squad
	bm = make()
	gun = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(m(-3000.0), 0.0))
	bm.player_units.append(gun)
	var foe := squad(bm, Unit.Team.ENEMY, 0.0)
	var ours := squad(bm, Unit.Team.PLAYER, 60.0)
	hits = 0
	for i in n:
		reset(ours)
		reset(foe)
		fire(bm, gun, foe, 62.0)
	check(bm.friendly_fire_hits.get(Unit.Team.PLAYER, 0) > n * 0.7, "Our own squad where our own round lands is hit, and counted as friendly fire (%d of %d)" % [bm.friendly_fire_hits.get(Unit.Team.PLAYER, 0), n])
	bm.combat_log.free()
	bm.free()

	# 4. who it was aimed at changes nothing: the same round, the same dice, aimed at different squads, hurts the same units
	var results := {}
	for aimed_at in ["near", "far", "nobody"]:
		bm = make()
		gun = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(m(3000.0), 0.0))
		bm.enemy_units.append(gun)
		var s1 := squad(bm, Unit.Team.PLAYER, 0.0, 0.0)
		var s2 := squad(bm, Unit.Team.PLAYER, 20.0, 10.0)
		var s3 := squad(bm, Unit.Team.PLAYER, 45.0, -20.0)
		var far := squad(bm, Unit.Team.PLAYER, 400.0, 0.0)
		var aimed: Unit = null
		match aimed_at:
			"near":
				aimed = s1
			"far":
				aimed = far
		var record := []
		seed(2024)
		for i in 60:
			for u in [s1, s2, s3]:
				reset(u)
			if aimed == null:
				# the aimed-at unit is gone (freed): nobody to aim at
				var shots: Array[Dictionary] = [{"mortar": gun, "target": null, "aim_point": Vector2.ZERO, "impact_point": Vector2(m(10.0), 0.0), "impact_time": bm.scenario_elapsed_time - 1.0}]
				bm._pending_mortar_shots = shots
				bm._resolve_pending_mortar_shots()
			else:
				fire(bm, gun, aimed, 10.0)
			record.append([hurt(s1), hurt(s2), hurt(s3)])
		results[aimed_at] = record
		bm.combat_log.free()
		bm.free()
	check(results["near"] == results["far"] and results["near"] == results["nobody"], "The same round with the same dice hurts the same units whoever it was aimed at (or nobody)")

	# 5. cover and movement are the unit's own: a squad in trees is caught less often than one in the open at the same distance, and a
	# moving one has no cover; every unit near the impact rolls for itself, so several are caught by one round
	bm = make()
	gun = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(m(3000.0), 0.0))
	bm.enemy_units.append(gun)
	var s_open := squad(bm, Unit.Team.PLAYER, 0.0, 0.0)
	var s_second := squad(bm, Unit.Team.PLAYER, 0.0, 10.0)
	var caught_two := 0
	for i in 400:
		reset(s_open)
		reset(s_second)
		fire(bm, gun, s_open, 0.0, 5.0)
		if hurt(s_open) and hurt(s_second):
			caught_two += 1
	check(caught_two > 100, "One round catches several squads near its impact, each by its own roll (%d of 400 caught both)" % caught_two)
	var open_chance: float = CombatResolver.blast_casualty_chance(m(20.0), GameConfig.MORTAR_BLAST_COLLATERAL_MAX_CHANCE, GameConfig.TerrainType.OPEN)
	var tree_chance: float = CombatResolver.blast_casualty_chance(m(20.0), GameConfig.MORTAR_BLAST_COLLATERAL_MAX_CHANCE, GameConfig.TerrainType.TREES)
	check(tree_chance < open_chance * 0.6, "A unit in cover is less likely to be caught than one in the open at the same distance (%.2f against %.2f)" % [tree_chance, open_chance])
	bm.combat_log.free()
	bm.free()

	# 6. far from the impact (beyond the blast's reach) nothing happens
	bm = make()
	gun = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(m(3000.0), 0.0))
	bm.enemy_units.append(gun)
	var distant := squad(bm, Unit.Team.PLAYER, 0.0, 0.0)
	var decoy := squad(bm, Unit.Team.PLAYER, 500.0, 0.0)
	hits = 0
	for i in 200:
		reset(distant)
		fire(bm, gun, decoy, 500.0)
		if hurt(distant):
			hits += 1
	check(hits == 0, "A squad 500 m from the impact is never caught (%d)" % hits)
	bm.combat_log.free()
	bm.free()

	print("Shell effects depend on landing tests: %d failures" % failures)
	quit(1 if failures else 0)
