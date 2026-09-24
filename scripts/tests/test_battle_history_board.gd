extends SceneTree
## Direct user report: "When replaying the battle history, it is not updating
## mortar status as the battle progresses. Rounds of ammo available that is."
## And: "Consider whether the whole board should be in a single code path."
##
## The casualty board (bars, mortar rows, drone row, both sides) is now built as
## plain data from either source — the live battle or the replay's recorded
## snapshot — and drawn by one renderer. So: the mortar and drone rows follow
## the replay, and at any moment the live board and a replay of that same
## moment read identically (where fog of war doesn't deliberately differ).
##
## Run: godot --headless --path . --script scripts/tests/test_battle_history_board.gd
const Viewer := preload("res://scripts/battle_history_viewer.gd")
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

func make_battle():
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(m(-1000), m(1500)))
	bm.player_units.append(mortar)
	bm.drone_team = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2(m(-800), m(1500)))
	bm.player_units.append(bm.drone_team)
	var drone: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(m(0), m(1500)))
	bm.player_units.append(drone)
	bm.active_drone = drone
	drone.drone_battery_charge = 0.9
	return bm

func make_board(bm, viewer):
	var board := CasualtyDashboard.new()
	root.add_child(board)
	board.setup(bm)
	board.history_viewer = viewer
	return board

func mortar_text(board) -> String:
	return board._player_mortar_rows[0].label.text

func run() -> void:
	test_mortar_ammo_follows_the_replay()
	test_drone_row_follows_the_replay()
	test_live_and_replay_boards_are_the_same_data()
	test_replay_shows_ground_truth_for_the_enemy()
	test_replay_casualty_tally_matches_the_live_tally()
	print("Battle history board tests: %d failures" % failures)
	quit(1 if failures else 0)


## The reported bug: scrubbing the replay must show the rounds the mortar had
## AT that moment, not the count it ended the battle with.
func test_mortar_ammo_follows_the_replay() -> void:
	var bm = make_battle()
	var mortar: Unit = bm.player_units[0]
	for step in [[0.0, 20], [300.0, 14], [600.0, 7], [900.0, 1]]:
		bm.scenario_elapsed_time = step[0]
		mortar.mortar_rounds_remaining = step[1]
		bm._record_history_snapshot()
	var viewer := Viewer.new()
	viewer.setup(bm.battle_history(), [])
	var board = make_board(bm, viewer)
	var expected := {0: "20 rounds", 1: "14 rounds", 2: "7 rounds", 3: "1 round"}
	for i in [0, 2, 1, 3, 0]: # forward, back, and to the ends
		viewer.set_index(i)
		board._refresh()
		check(("in action (%s" % expected[i]) in mortar_text(board), "At snapshot %d the row must read %s (got '%s')" % [i, expected[i], mortar_text(board)])
	# ...and a mortar lost partway shows that state at that moment only.
	bm.scenario_elapsed_time = 1200.0
	mortar.state = Unit.State.DESTROYED
	mortar.crew_casualties = 4
	mortar.crew_size = 4
	bm._record_history_snapshot()
	viewer.setup(bm.battle_history(), [])
	viewer.set_index(4)
	board._refresh()
	check("destroyed (4/4 crew casualties)" in mortar_text(board), "A mortar destroyed by that moment reads destroyed (got '%s')" % mortar_text(board))
	viewer.set_index(3)
	board._refresh()
	check("in action (1 round" in mortar_text(board), "...but scrubbing back to before shows it in action again (got '%s')" % mortar_text(board))
	# A resupply pending at the moment recorded shows in that row's suffix.
	bm._mortar_resupply[mortar] = {"arrival_time": 1500.0, "staged": false}
	mortar.state = Unit.State.ACTIVE
	bm.scenario_elapsed_time = 1260.0
	bm._record_history_snapshot()
	viewer.setup(bm.battle_history(), [])
	board._refresh()
	check("resupply ~4m out" in mortar_text(board), "The recorded resupply status shows in the replay row (got '%s')" % mortar_text(board))
	board.free()
	viewer.free()
	bm.combat_log.free()
	bm.free()


func test_drone_row_follows_the_replay() -> void:
	var bm = make_battle()
	bm.scenario_elapsed_time = 0.0
	bm.active_drone.drone_battery_charge = 0.90
	bm._record_history_snapshot()
	bm.scenario_elapsed_time = 600.0
	bm.active_drone.drone_battery_charge = 0.35
	bm._record_history_snapshot()
	var viewer := Viewer.new()
	viewer.setup(bm.battle_history(), [])
	var board = make_board(bm, viewer)
	viewer.set_index(0)
	board._refresh()
	check("90% charge" in board._drone_label.text, "The drone row shows the fleet as it was (got '%s')" % board._drone_label.text)
	viewer.set_index(1)
	board._refresh()
	check("35% charge" in board._drone_label.text, "...and follows the replay forward (got '%s')" % board._drone_label.text)
	board.free()
	viewer.free()
	bm.combat_log.free()
	bm.free()


## The single-path guarantee: the live board and the replay of that same moment
## are the same data, row for row, however the battle got there.
func test_live_and_replay_boards_are_the_same_data() -> void:
	var bm = make_battle()
	var mortar: Unit = bm.player_units[0]
	mortar.mortar_rounds_remaining = 9
	bm.active_drone.drone_battery_charge = 0.6
	bm._record_history_snapshot()
	var viewer := Viewer.new()
	viewer.setup(bm.battle_history(), [])
	var board = make_board(bm, viewer)
	board.history_viewer = null
	var live: Dictionary = board._live_board()
	board.history_viewer = viewer
	var replay: Dictionary = board._replay_board()
	check(live.player.mortars == replay.player.mortars, "Player mortar rows must be identical live vs replay: %s vs %s" % [str(live.player.mortars), str(replay.player.mortars)])
	check(live.drone == replay.drone, "Drone rows must be identical live vs replay: %s vs %s" % [str(live.drone), str(replay.drone)])
	check(live.player.stats.pips_lost == replay.player.stats.pips_lost and live.player.stats.pips_total == replay.player.stats.pips_total, "Player casualty stats agree live vs replay")
	# Both drive the one renderer.
	board._render(live)
	var live_text: String = mortar_text(board)
	board._render(replay)
	check(mortar_text(board) == live_text and live_text.begins_with("Mortar: in action (9 rounds"), "One renderer: same text either way (got '%s')" % live_text)
	board.free()
	viewer.free()
	bm.combat_log.free()
	bm.free()


## The one deliberate difference: the replay is omniscient (a confirmed choice
## for this feature), so an enemy mortar the player never discovered shows in
## the replay's rows but not on the live board's.
func test_replay_shows_ground_truth_for_the_enemy() -> void:
	var bm = make_battle()
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(m(3000), m(1500)))
	bm.enemy_units.append(enemy)
	enemy.mortar_rounds_remaining = 12
	bm._record_history_snapshot()
	var viewer := Viewer.new()
	viewer.setup(bm.battle_history(), [])
	var board = make_board(bm, viewer)
	board.history_viewer = null
	check(board._live_board().enemy.mortars.is_empty(), "Live: an undiscovered enemy mortar stays hidden (fog of war)")
	board.history_viewer = viewer
	var rows: Array = board._replay_board().enemy.mortars
	check(rows.size() == 1 and "in action (12 rounds" in rows[0].text, "Replay: the true enemy mortar shows (got %s)" % str(rows))
	board.free()
	viewer.free()
	bm.combat_log.free()
	bm.free()


## The replay's casualty numbers are computed by the viewer from recorded unit
## records (casualty_pips_at_current_index), the live board's by
## BattleManager._compute_side_stats — two implementations of the same personnel
## sums (the live one also carries the AAR's much richer breakdown, and counts
## wounded left behind, which snapshots don't record). This is the drift guard:
## on a battle with squad casualties, a destroyed mortar, a surrendered squad
## and equipment that must not count, both must agree, for both sides.
func test_replay_casualty_tally_matches_the_live_tally() -> void:
	var bm = make_battle()
	var squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(m(-500), m(1500)))
	bm.player_units.append(squad)
	squad.pips = squad.max_pips - 2
	var mortar: Unit = bm.player_units[0]
	mortar.state = Unit.State.DESTROYED
	mortar.pips = 0
	mortar.crew_casualties = mortar.crew_size
	var hurt: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(m(2000), m(1500)))
	bm.enemy_units.append(hurt)
	hurt.pips = hurt.max_pips - 1
	var surrendered: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(m(2500), m(1500)))
	bm.enemy_units.append(surrendered)
	surrendered.state = Unit.State.SURRENDERED
	bm._record_history_snapshot()
	var viewer := Viewer.new()
	viewer.setup(bm.battle_history(), [])
	for team in [Unit.Team.PLAYER, Unit.Team.ENEMY]:
		var replay: Dictionary = viewer.casualty_pips_at_current_index(team)
		var live: Dictionary = bm._compute_side_stats(bm.player_units if team == Unit.Team.PLAYER else bm.enemy_units, false, team == Unit.Team.ENEMY)
		var side := "player" if team == Unit.Team.PLAYER else "enemy"
		check(replay.pips_total == live.pips_total, "%s: replay total %d must equal live total %d" % [side, replay.pips_total, live.pips_total])
		check(replay.pips_lost == live.pips_lost, "%s: replay lost %d must equal live lost %d" % [side, replay.pips_lost, live.pips_lost])
		check(replay.captured == live.captured, "%s: replay captured %d must equal live captured %d" % [side, replay.captured, live.captured])
	check(viewer.casualty_pips_at_current_index(Unit.Team.PLAYER).pips_lost > 0 and viewer.casualty_pips_at_current_index(Unit.Team.ENEMY).captured > 0, "Setup: the scenario must actually contain casualties and a capture")
	viewer.free()
	bm.combat_log.free()
	bm.free()
