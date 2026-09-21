extends SceneTree
## Seeing through trees (late winter / early spring: bare woods are porous, not
## opaque). Guards, on a synthetic map with one round 100 m-radius wood:
## - depth: metres of sightline actually inside canopy, respecting elevation
##   (a wood in a hollow between two high points does not matter);
## - roll_spot: woods cut a ground observer's spotting rate to exp(-depth/80m);
##   a drone is exempt;
## - staying visible: far easier than acquiring (deterministic, ~200 m of woods),
##   and a target lost ONLY to woods gets a grace period before it drops,
##   while one lost to range drops at once (no flicker on a roll);
## - the per-pair cache reuses an answer for a stationary pair and recomputes
##   once either end moves.
##
## Run: godot --headless --path . --script scripts/tests/test_tree_sight.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0
var _saved_map_id := ""

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(x: float, y: float) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

## A copy of an existing map with one 100 m wood at (2500, 1750), no hills or
## buildings, optionally with a 60 m-deep hollow under the wood.
func use_test_map(hollow: bool) -> void:
	var base: Dictionary = GameConfig.MAPS["pishchane"].duplicate(true)
	base.forest_patches = [{"center_m": Vector2(2500.0, 1750.0), "radius_m": 100.0, "warp_harmonics": []}]
	base.terrain_zones = []
	base.hills = []
	if hollow:
		base.hills = [{"center_m": Vector2(2500.0, 1750.0), "radius_m": 300.0, "height_m": -60.0, "warp_harmonics": []}]
	GameConfig.CURRENT_MAP = base # MAPS is a constant, so install the copy directly
	GameConfig._recompute_map_derived_state()
	GameConfig.prepare_canopy()

func make_battle():
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	return bm

func unit(bm, team: Unit.Team, kind: Unit.Kind, pos_m: Vector2) -> Unit:
	var u: Unit = bm._make_unit(team, kind, pos_m * GameConfig.PIXELS_PER_METER)
	(bm.player_units if team == Unit.Team.PLAYER else bm.enemy_units).append(u)
	return u


func test_depth_and_elevation() -> void:
	use_test_map(false)
	var through: float = GameConfig.tree_sight_depth_m(m(2200, 1750), m(2800, 1750))
	check(absf(through - 200.0) <= 15.0, "A line straight through a 100 m-radius wood must read about 200 m of canopy (got %.0f)" % through)
	check(GameConfig.tree_sight_depth_m(m(2200, 1200), m(2800, 1200)) == 0.0, "A line nowhere near the wood must read no canopy")
	var graze: float = GameConfig.tree_sight_depth_m(m(2200, 1750 + 90), m(2800, 1750 + 90))
	check(graze > 0.0 and graze < through * 0.6, "A line clipping the wood's edge reads a short depth (got %.0f)" % graze)
	# Elevation: the same wood sitting in a 60 m hollow between two high points.
	use_test_map(true)
	var hollow_depth: float = GameConfig.tree_sight_depth_m(m(2200, 1750), m(2800, 1750))
	check(hollow_depth == 0.0, "A wood far below both ends' sightline must not matter at all (got %.0f m)" % hollow_depth)
	# Standing IN a wood on level ground still counts, near the ends of the line.
	use_test_map(false)
	var from_inside: float = GameConfig.tree_sight_depth_m(m(2500, 1750), m(2800, 1750))
	check(absf(from_inside - 100.0) <= 15.0, "An observer standing in the wood sees through the rest of it (got %.0f)" % from_inside)


func spot_rate(bm, obs: Unit, tgt: Unit, trials: int) -> float:
	var hits := 0
	for i in trials:
		if CombatResolver.roll_spot(obs, tgt, 0.5):
			hits += 1
	return float(hits) / float(trials)


func test_woods_cut_the_spotting_rate() -> void:
	use_test_map(false)
	var bm = make_battle()
	seed(99)
	var obs: Unit = unit(bm, Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(2350, 1750))
	var tgt: Unit = unit(bm, Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(2650, 1750)) # 300 m, 200 m of it wood
	tgt.seconds_stationary = 10000.0
	var open_obs: Unit = unit(bm, Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(2350, 1200))
	var open_tgt: Unit = unit(bm, Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(2650, 1200)) # same 300 m, no wood
	open_tgt.seconds_stationary = 10000.0
	var trials := 60000
	var wooded: float = spot_rate(bm, obs, tgt, trials)
	var open: float = spot_rate(bm, open_obs, open_tgt, trials)
	var expected: float = exp(-200.0 / GameConfig.TREE_SIGHT_ATTENUATION_LENGTH_M)
	check(open > 0.03, "Setup check: the open control must spot at a healthy rate (got %.4f)" % open)
	var ratio: float = wooded / open
	check(ratio > expected * 0.6 and ratio < expected * 1.6, "200 m of woods must cut the spotting rate to about exp(-200/80)=%.3f of the open rate (got %.3f)" % [expected, ratio])
	# A drone looks down, not through.
	var drone: Unit = unit(bm, Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(2350, 1750))
	var drone_rate: float = spot_rate(bm, drone, tgt, trials)
	var drone_open: float = spot_rate(bm, unit(bm, Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(2350, 1200)), open_tgt, trials)
	check(drone_open > 0.0 and absf(drone_rate - drone_open) / drone_open < 0.35, "A drone's spotting must not be cut by woods between (%.4f vs %.4f open)" % [drone_rate, drone_open])
	# A moving target keeps the existing 3x edge, with the SAME woods factor.
	tgt.seconds_stationary = 0.0
	var moving: float = spot_rate(bm, obs, tgt, trials)
	check(moving > wooded * 2.0 and moving < wooded * 4.5, "Movement still helps by about its existing 3x, not a separate woods bonus (moving %.4f vs stationary %.4f)" % [moving, wooded])


func test_keeping_sight_is_easier_and_has_a_grace() -> void:
	use_test_map(false)
	var bm = make_battle()
	var obs: Unit = unit(bm, Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(2350, 1750))
	var shallow: Unit = unit(bm, Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(2450, 1750)) # ~50 m of wood
	var obs_list: Array[Unit] = [obs]
	check(CombatResolver.has_live_observer(shallow, obs_list), "A target with little wood between stays in view")
	# Beyond the keep threshold: widen the wood to a 250 m radius.
	var base: Dictionary = GameConfig.CURRENT_MAP
	base.forest_patches = [{"center_m": Vector2(2500.0, 1750.0), "radius_m": 250.0, "warp_harmonics": []}]
	GameConfig._recompute_map_derived_state()
	GameConfig.prepare_canopy()
	var blocked: Unit = unit(bm, Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(2650, 1750)) # observer at 2350: ~ 300 m wood
	var blocked_obs: Array[Unit] = [obs]
	check(GameConfig.tree_sight_depth_m(obs.global_position, blocked.global_position) > 250.0, "Setup check: enough wood between to fail the keep test")
	check(not CombatResolver.has_live_observer(blocked, blocked_obs), "Too much wood between: no longer 'live'")
	check(CombatResolver.has_live_observer(blocked, blocked_obs, true), "...but it is lost only to the woods (ignore_trees still sees it)")

	# Grace: a visible target lost only to the woods stays visible for a while.
	blocked.is_visible = true
	var seen_for := 0
	for step in 40:
		bm._refresh_visibility(bm.player_units, bm.enemy_units, 1.0)
		if not blocked.is_visible:
			break
		seen_for += 1
	check(GameConfig.TREE_SIGHT_LOSS_GRACE_S >= 5.0 and seen_for >= int(GameConfig.TREE_SIGHT_LOSS_GRACE_S) - 2 and seen_for <= int(GameConfig.TREE_SIGHT_LOSS_GRACE_S) + 1,
		"A target lost only to woods must hold for about the %.0f s grace before dropping (held %d ticks)" % [GameConfig.TREE_SIGHT_LOSS_GRACE_S, seen_for])
	# A target lost to RANGE drops at once, no grace.
	var distant: Unit = unit(bm, Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(2350 + 3000, 1750))
	distant.is_visible = true
	bm._refresh_visibility(bm.player_units, bm.enemy_units, 1.0)
	check(not distant.is_visible, "A target beyond range must drop immediately, not get a woods grace")
	# The grace clock restarts once it is seen properly again.
	var flicker: Unit = unit(bm, Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(2650, 1750))
	flicker.is_visible = true
	for step in 10:
		bm._refresh_visibility(bm.player_units, bm.enemy_units, 1.0)
	flicker.global_position = m(2250, 1700) # out of the woods, in the clear
	bm._refresh_visibility(bm.player_units, bm.enemy_units, 1.0)
	check(not bm._tree_sight_lost_for.has(flicker), "Regaining a clear view must reset the grace clock")


func test_pair_cache() -> void:
	use_test_map(false)
	var a := m(2350, 1750)
	var b := m(2650, 1750)
	var t1: float = GameConfig.tree_sight_transmission(1, 2, a, b)
	# Poison the cached entry: a stationary pair must reuse it, not recompute.
	GameConfig._tree_sight_cache[1][2][2] = 0.123
	check(GameConfig.tree_sight_transmission(1, 2, a, b) == 0.123, "A pair that has not moved must reuse its cached answer")
	check(GameConfig.tree_sight_transmission(1, 2, a + m(3, 0), b) == 0.123, "A few metres of movement must still hit the cache")
	var moved: float = GameConfig.tree_sight_transmission(1, 2, a, b + m(0, 400))
	check(moved != 0.123 and moved > t1, "Once an end has moved well away the answer must be recomputed (got %.3f)" % moved)


func run() -> void:
	_saved_map_id = ""
	for id in GameConfig.MAPS:
		if GameConfig.CURRENT_MAP == GameConfig.MAPS[id]:
			_saved_map_id = id
	test_depth_and_elevation()
	test_woods_cut_the_spotting_rate()
	test_keeping_sight_is_easier_and_has_a_grace()
	test_pair_cache()
	if _saved_map_id != "":
		GameConfig.set_active_map(_saved_map_id)
	print("Tree sight tests: %d failures" % failures)
	quit(1 if failures else 0)
