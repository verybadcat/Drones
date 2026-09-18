extends SceneTree
## Guards a live-reported bug: while scrubbing "Review Battle History,"
## CasualtyDashboard's two casualty bars stayed frozen at the battle's
## final totals throughout — main.gd's _on_review_history_pressed never
## hid or redirected them, so they kept reading straight from the live
## (by then finished) BattleManager regardless of where the replay slider
## sat. Direct user requirement: "the casualties bar should start at zero
## and show casualties as they happen. If the user scrolls forwards or
## backwards, the casualties should show what they were at wherever the
## user scrolls to." Fixed via BattleHistoryViewer.casualty_pips_at_
## current_index, a ground-truth read of the CURRENTLY DISPLAYED snapshot,
## and CasualtyDashboard.history_viewer, which _refresh() now checks
## before falling back to the live battle_manager reading.
##
## Run: godot --headless --path . --script scripts/tests/test_battle_history_casualties.gd
const Viewer := preload("res://scripts/battle_history_viewer.gd")
const TestCombatLogScript := preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

## A minimal, hand-built two-snapshot history: a player squad starts at
## full strength and ends having taken 3 of 10 pips lost; an enemy drone
## and an enemy resupply run are included specifically to confirm they're
## excluded from the pip count, same as BattleManager._compute_side_stats'
## own ground-truth math excludes them.
func _make_history() -> Array[Dictionary]:
	var snapshot_0 := {"time": 0.0, "units": [
		{"team": Unit.Team.PLAYER, "kind": Unit.Kind.SQUAD, "x": 0.0, "y": 0.0, "state": Unit.State.ACTIVE, "unit_label": "P1", "pips": 10, "max_pips": 10},
		{"team": Unit.Team.ENEMY, "kind": Unit.Kind.SQUAD, "x": 0.0, "y": 0.0, "state": Unit.State.ACTIVE, "unit_label": "E1", "pips": 10, "max_pips": 10},
		{"team": Unit.Team.ENEMY, "kind": Unit.Kind.DRONE, "x": 0.0, "y": 0.0, "state": Unit.State.ACTIVE, "unit_label": "ED1", "pips": 1, "max_pips": 1},
		{"team": Unit.Team.ENEMY, "kind": Unit.Kind.RESUPPLY_RUN, "x": 0.0, "y": 0.0, "state": Unit.State.ACTIVE, "unit_label": "ER1", "pips": 1, "max_pips": 1},
	]}
	var snapshot_1 := {"time": 300.0, "units": [
		{"team": Unit.Team.PLAYER, "kind": Unit.Kind.SQUAD, "x": 0.0, "y": 0.0, "state": Unit.State.ACTIVE, "unit_label": "P1", "pips": 7, "max_pips": 10},
		{"team": Unit.Team.ENEMY, "kind": Unit.Kind.SQUAD, "x": 0.0, "y": 0.0, "state": Unit.State.ACTIVE, "unit_label": "E1", "pips": 10, "max_pips": 10},
		{"team": Unit.Team.ENEMY, "kind": Unit.Kind.DRONE, "x": 0.0, "y": 0.0, "state": Unit.State.DESTROYED, "unit_label": "ED1", "pips": 0, "max_pips": 1},
		{"team": Unit.Team.ENEMY, "kind": Unit.Kind.RESUPPLY_RUN, "x": 0.0, "y": 0.0, "state": Unit.State.ACTIVE, "unit_label": "ER1", "pips": 1, "max_pips": 1},
	]}
	var out: Array[Dictionary] = [snapshot_0, snapshot_1]
	return out


func test_starts_at_zero_casualties_at_the_first_snapshot() -> void:
	var viewer := Viewer.new()
	viewer.setup(_make_history(), [])
	viewer.set_index(0)
	var stats: Dictionary = viewer.casualty_pips_at_current_index(Unit.Team.PLAYER)
	check(stats.pips_lost == 0, "The battle's opening snapshot must show zero casualties, not the final battle's total (got %d)" % stats.pips_lost)
	check(stats.pips_total == 10, "pips_total must reflect the roster at THIS snapshot (got %d)" % stats.pips_total)
	viewer.free()


func test_scrubbing_to_a_later_snapshot_shows_that_moments_casualties() -> void:
	var viewer := Viewer.new()
	viewer.setup(_make_history(), [])
	viewer.set_index(1)
	var stats: Dictionary = viewer.casualty_pips_at_current_index(Unit.Team.PLAYER)
	check(stats.pips_lost == 3, "The later snapshot's own recorded pip loss must be shown, not zero or some other value (got %d)" % stats.pips_lost)
	viewer.free()


func test_scrubbing_backward_returns_to_the_earlier_moments_lower_casualty_count() -> void:
	var viewer := Viewer.new()
	viewer.setup(_make_history(), [])
	viewer.set_index(1)
	check(viewer.casualty_pips_at_current_index(Unit.Team.PLAYER).pips_lost == 3, "Setup check: forward index shows 3 lost")
	viewer.set_index(0)
	check(viewer.casualty_pips_at_current_index(Unit.Team.PLAYER).pips_lost == 0,
		"Scrolling backward must show what casualties were AT that earlier point (0), not stay stuck at the later value")
	viewer.free()


func test_drone_and_resupply_run_are_excluded_from_the_pip_count() -> void:
	var viewer := Viewer.new()
	viewer.setup(_make_history(), [])
	viewer.set_index(1) # the enemy drone is DESTROYED here
	var stats: Dictionary = viewer.casualty_pips_at_current_index(Unit.Team.ENEMY)
	check(stats.pips_total == 10, "A drone (equipment) and a resupply run (transient logistics) must not count toward pips_total (got %d)" % stats.pips_total)
	check(stats.pips_lost == 0, "The enemy squad itself took no losses in this snapshot — the destroyed drone must not appear as a personnel casualty (got %d)" % stats.pips_lost)
	viewer.free()


func test_surrendered_unit_counts_its_remaining_pips_as_lost() -> void:
	var history: Array[Dictionary] = [{"time": 0.0, "units": [
		{"team": Unit.Team.PLAYER, "kind": Unit.Kind.SQUAD, "x": 0.0, "y": 0.0, "state": Unit.State.SURRENDERED, "unit_label": "P1", "pips": 6, "max_pips": 10},
	]}]
	var viewer := Viewer.new()
	viewer.setup(history, [])
	var stats: Dictionary = viewer.casualty_pips_at_current_index(Unit.Team.PLAYER)
	check(stats.pips_lost == 10,
		"A SURRENDERED unit's remaining pips (6) must be added on top of whatever it had already lost (4), reaching its full max_pips (10) — pips itself isn't reduced by surrendering (got %d)" % stats.pips_lost)
	viewer.free()


func test_casualty_dashboard_reads_from_the_history_viewer_when_scrubbing() -> void:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = TestCombatLogScript.new()
	# Give the live battle_manager a real, high casualty count — if the
	# dashboard ever falls back to reading this instead of the replay
	# snapshot, the test below would catch it immediately.
	var live_squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2.ZERO)
	live_squad.pips = 1
	bm.player_units.append(live_squad)

	var dashboard := CasualtyDashboard.new()
	root.add_child(dashboard)
	dashboard.setup(bm)

	var viewer := Viewer.new()
	viewer.setup(_make_history(), [])
	viewer.set_index(0) # the replay's OWN opening snapshot: zero casualties
	dashboard.history_viewer = viewer
	dashboard._refresh()

	check(dashboard._player_label.text.contains("0/10"),
		"With a history_viewer set, the dashboard must read the REPLAY's own snapshot (0/10 lost), not the live battle_manager's own current state — got: %s" % dashboard._player_label.text)

	dashboard.history_viewer = null
	dashboard._refresh()
	check(not dashboard._player_label.text.contains("0/10"),
		"Clearing history_viewer must return the dashboard to the live battle_manager reading")

	viewer.free()
	dashboard.free()
	bm.combat_log.free()
	bm.free()


func run() -> void:
	test_starts_at_zero_casualties_at_the_first_snapshot()
	test_scrubbing_to_a_later_snapshot_shows_that_moments_casualties()
	test_scrubbing_backward_returns_to_the_earlier_moments_lower_casualty_count()
	test_drone_and_resupply_run_are_excluded_from_the_pip_count()
	test_surrendered_unit_counts_its_remaining_pips_as_lost()
	test_casualty_dashboard_reads_from_the_history_viewer_when_scrubbing()
	if failures == 0:
		print("Battle history casualties tests: 0 failures")
	else:
		print("Battle history casualties tests: %d failures" % failures)
	quit(1 if failures else 0)
