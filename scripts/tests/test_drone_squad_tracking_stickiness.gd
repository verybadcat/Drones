extends SceneTree
## Direct user report, live: the drone was "changing its mind between enemy squads 1 and 3." Fast-polling the
## running battle's drone snapshot showed the tracked target hopping between two squads of nearly equal danger.
##
## Root cause: BattleManager._drone_squad_to_track picked the best squad by a bare argmax of (class, nearness)
## EVERY tick, with no memory of the squad it was already on. Two squads at almost the same distance from our
## forces swap the lead with every few meters of ordinary movement, and the drone swung to follow whichever was
## ahead this tick.
##
## Fix: the squad being tracked keeps the drone until a rival is clearly worse for us — in a higher class (a
## squad that has newly come to threaten the mortar still wins immediately), or in the same class with a
## nearness score beyond GameConfig.DRONE_SQUAD_SWITCH_FACTOR/_MARGIN. A tracked squad that stops being a
## candidate is replaced at once.
##
## Run: godot --headless --path . --script scripts/tests/test_drone_squad_tracking_stickiness.gd
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

## One friendly squad at the origin of the action (what "danger" is measured against) and the drone team.
func make_battle() -> BattleManager:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	var f: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(0.0, 0.0))
	bm.player_units.append(f)
	bm.drone_team = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, m(-600.0, 0.0))
	bm.player_units.append(bm.drone_team)
	return bm

func enemy_squad(bm: BattleManager, pos_m: Vector2) -> Unit:
	var e: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(pos_m.x, pos_m.y))
	bm.enemy_units.append(e)
	e.is_visible = true
	return e

func cleanup(bm: BattleManager) -> void:
	bm.combat_log.free()
	bm.free()

func run() -> void:
	test_two_near_equal_squads_do_not_trade_the_lead()
	test_a_clearly_nearer_squad_still_takes_over()
	test_a_squad_that_newly_threatens_the_mortar_wins_at_once()
	test_a_tracked_squad_that_is_gone_is_replaced()
	test_squads_whose_class_wobbles_do_not_swap_faster_than_the_dwell_time()
	print("Drone squad tracking stickiness tests: %d failures" % failures)
	quit(1 if failures else 0)


## The reported case, driven with real ticks of jitter: two squads whose distances to our squad differ by a
## few meters, wobbling past each other. Counts how many times the pick changes.
func test_two_near_equal_squads_do_not_trade_the_lead() -> void:
	var bm := make_battle()
	var a: Unit = enemy_squad(bm, Vector2(0.0, 300.0))
	var b: Unit = enemy_squad(bm, Vector2(0.0, -300.0))
	var switches := 0
	var last: Unit = null
	for i in 200:
		var wobble: float = 4.0 * sin(i * 0.7) # a few metres either way, crossing back and forth
		a.global_position = m(0.0, 300.0 + wobble)
		b.global_position = m(0.0, -(300.0 - wobble))
		var pick: Unit = bm._drone_squad_to_track().get("unit", null)
		if last != null and pick != last:
			switches += 1
		last = pick
	check(last != null, "Setup: a squad is being tracked")
	check(switches == 0, "Two squads at nearly the same distance never trade the lead as they wobble (%d switches)" % switches)
	cleanup(bm)


## Stickiness must not make the drone stubborn: a rival that is clearly more dangerous (well past the
## factor/margin) takes over.
func test_a_clearly_nearer_squad_still_takes_over() -> void:
	var bm := make_battle()
	var far: Unit = enemy_squad(bm, Vector2(0.0, 400.0))
	var near: Unit = enemy_squad(bm, Vector2(0.0, 900.0))
	check(bm._drone_squad_to_track().get("unit", null) == far, "Setup: the nearer squad is tracked first")
	far.global_position = m(0.0, 1100.0)
	near.global_position = m(0.0, 200.0)
	check(bm._drone_squad_to_track().get("unit", null) == near, "A rival now clearly nearer to our squad takes the drone over")
	cleanup(bm)


## A higher class beats the tracked squad immediately, whatever the factor: a squad newly within range of the
## friendly mortar and not moving away.
func test_a_squad_that_newly_threatens_the_mortar_wins_at_once() -> void:
	var bm := make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(-1500.0, 0.0)) # well apart from the squad's own position
	bm.player_units.append(mortar)
	var tracked: Unit = enemy_squad(bm, Vector2(0.0, 300.0)) # near our squad, not near the mortar
	var other: Unit = enemy_squad(bm, Vector2(3000.0, 3000.0)) # nowhere near anything
	var first: Dictionary = bm._drone_squad_to_track()
	check(first.get("unit", null) == tracked, "Setup: the squad near our forces is tracked")
	other.global_position = mortar.global_position + m(0.0, -150.0) # now right at the mortar, well inside its danger range
	var pick: Dictionary = bm._drone_squad_to_track()
	check(pick.get("unit", null) == other, "A squad that has newly come to threaten the mortar wins immediately")
	check("threatening the mortar" in str(pick.get("why", "")), "...and says so")
	cleanup(bm)


func test_a_tracked_squad_that_is_gone_is_replaced() -> void:
	var bm := make_battle()
	var a: Unit = enemy_squad(bm, Vector2(0.0, 300.0))
	var b: Unit = enemy_squad(bm, Vector2(0.0, 320.0))
	var first: Unit = bm._drone_squad_to_track().get("unit", null)
	check(first == a, "Setup: the nearer squad is tracked first")
	a.is_visible = false
	check(bm._drone_squad_to_track().get("unit", null) == b, "A tracked squad that goes out of sight is replaced at once, not held onto")
	a.is_visible = true
	check(bm._drone_squad_to_track().get("unit", null) == b, "...and the replacement is then the one kept")
	cleanup(bm)


## Two squads far apart (one far north, one far south — the user's case), both far from every friendly, so
## their nearness scores are both ~0 and what separates them is their CLASS, which comes from heading: each
## alternately "heading toward our squad" and not. A bare argmax swaps the lead every tick; with the dwell
## time the drone may only change its mind once per DRONE_SQUAD_MIN_DWELL_S.
func test_squads_whose_class_wobbles_do_not_swap_faster_than_the_dwell_time() -> void:
	var bm := make_battle()
	var north: Unit = enemy_squad(bm, Vector2(0.0, 5000.0))
	var south: Unit = enemy_squad(bm, Vector2(0.0, -5000.0))
	var switches := 0
	var last: Unit = null
	var ticks := 400
	var tick_s := 5.0
	for i in ticks:
		bm.scenario_elapsed_time = i * tick_s
		# Alternate which one is "heading at us" (a move target at our squad) each tick.
		var north_heads_in: bool = i % 2 == 0
		north.has_move_target = north_heads_in
		north.move_target = m(0.0, 0.0)
		north.move_speed = 10.0
		south.has_move_target = not north_heads_in
		south.move_target = m(0.0, 0.0)
		south.move_speed = 10.0
		var pick: Unit = bm._drone_squad_to_track().get("unit", null)
		if last != null and pick != last:
			switches += 1
		last = pick
	var allowed: int = int(ceil(ticks * tick_s / GameConfig.DRONE_SQUAD_MIN_DWELL_S))
	check(switches <= allowed, "No more than one change of mind per dwell time (%d switches over %.0f s, at most %d allowed)" % [switches, ticks * tick_s, allowed])
	check(switches < ticks / 10, "...and nowhere near one per tick (%d switches in %d ticks)" % [switches, ticks])
	cleanup(bm)
