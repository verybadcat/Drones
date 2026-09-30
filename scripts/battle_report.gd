class_name BattleReport
extends GameScreen
## The end-of-battle report and everything that goes with it: the four tabs (Score, Damage
## by unit, Seed, After Action Report), the buttons under it (choose a new setup, review the
## battle's history, hide the report) and the history-review mode with its scrubbable
## timeline. Opened by the battle screen when the battle ends; it records the battle's
## score to the durable history (see BattleScoreLog) and asks main.gd, by signal, for a new
## setup when the player wants one.
##
## The caller sets `battle_manager`, `map_viewport`, `score_log`, `recon_mode` and
## `dashboard` (the casualty dashboard the history viewer feeds; may be null) and then
## calls open(report_text) after adding this to the tree.

signal restart_requested

const BattleScore = preload("res://scripts/battle_score.gd")
const BattleScoreLog = preload("res://scripts/battle_score_log.gd")

var battle_manager: BattleManager
var map_viewport: SubViewport
var score_log: BattleScoreLog
var recon_mode: GameConfig.ReconMode = GameConfig.ReconMode.SPOTTER
var dashboard: CasualtyDashboard

var report_background: Control
var restart_button: Button
var review_history_button: Button
var hide_report_button: Button
var copy_seed_button: Button

# Post-battle "drag through time" replay — see battle_history_viewer.gd. history_viewer is
# untyped for the brand-new-class_name reason, and lives in map_viewport (map-space
# rendering). Created/freed per visit to the review mode, since it depends on that
# specific battle's recorded history.
var history_viewer
var history_slider: HSlider
var history_time_label: Label
var history_back_button: Button
var history_play_button: Button

## The scenario-average line for the battle that just ended ("" if there is none) — kept
## so the Score tab can show it too, not just the After Action Report. Set by
## _record_score_and_annotate.
var _scenario_average_line: String = ""

## Where the end-of-battle report sits. Its top is below the strip along the top of
## the screen (elevation and location labels, the clock, "Inspect AI", the retreat
## slider) so it no longer covers them (user: "move the end-of-battle panel a bit
## further down in the UI so it doesn't overlap elements at the top. The buttons
## below it then also have to move down"). The three buttons stack under it.
const REPORT_PANEL_TOP: float = 64.0
const REPORT_PANEL_SIZE := Vector2(560, 500)
const REPORT_BUTTONS_GAP: float = 20.0
const REPORT_BUTTON_ROW_HEIGHT: float = 41.0 # a button is 31 px tall, plus spacing


## Records the finished battle's score to the durable history, then returns
## the report with this scenario's running average added under the "Battle
## score" line. A scenario is the LOCATION plus the KIND OF SCOUTING the
## player chose (the recon mode) — user's definition. Recording happens here,
## in the real UI flow, never in BattleManager (which runs in every test).
func _record_score_and_annotate(report_text: String) -> String:
	_scenario_average_line = ""
	if battle_manager == null or battle_manager.battle_result.is_empty():
		return report_text
	var map_id: String = GameConfig.current_map_id()
	var mode_name: String = GameConfig.ReconMode.keys()[recon_mode]
	score_log.record(battle_manager.battle_result, map_id, mode_name)
	var summary: Dictionary = BattleScoreLog.scenario_summary(score_log.load_records(), map_id, mode_name)
	if summary.is_empty():
		return report_text
	_scenario_average_line = "Scenario average: %s over %d %s (%s, %s)" % [
		BattleScore.format(summary.average), summary.count, "battle" if summary.count == 1 else "battles",
		GameConfig.CURRENT_MAP.name, GameConfig.RECON_MODE_LABELS[recon_mode],
	]
	var lines: PackedStringArray = report_text.split("\n")
	for i in lines.size():
		if lines[i].begins_with("Battle score:"):
			lines.insert(i + 1, _scenario_average_line)
			break
	return "\n".join(lines)


## The Score tab's text: the total, the running scenario average, and every
## line item that went into the score (see BattleScore.breakdown_text).
func _score_tab_text() -> String:
	if battle_manager == null or battle_manager.battle_result.is_empty():
		return "No score is available for this battle."
	return BattleScore.breakdown_text(battle_manager.battle_result.inputs, _scenario_average_line)


## The Seed tab: the seed this battle ran on, and what using it again does and does not do.
func seed_tab_text() -> String:
	var seed_value: int = battle_manager.battle_seed if battle_manager != null else -1
	if seed_value < 0:
		return "This battle had no seed (it was not started from the setup screens)."
	return "Battle seed: %d\n\n%s" % [seed_value, LevelSelectScreen.SEED_NOTE]


## "Copy seed": puts the number on the clipboard, ready to paste on the first screen.
func copy_seed() -> void:
	if battle_manager != null and battle_manager.battle_seed >= 0 and DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(str(battle_manager.battle_seed))


func open(report_text: String) -> void:
	report_text = _record_score_and_annotate(report_text)

	report_background = ColorRect.new()
	report_background.color = Color(0.05, 0.05, 0.05, 0.85)
	report_background.position = Vector2(20, REPORT_PANEL_TOP)
	report_background.size = REPORT_PANEL_SIZE
	add_child(report_background)

	# A bare Label outside any Container never actually respects a width
	# smaller than its own natural (unwrapped) content size — custom_min_size
	# can only raise a control's minimum, never cap it below that, so the
	# report's longest line (e.g. a full "Russian forces withdrew: ..." list) forced
	# the label wider than this box regardless of autowrap_mode. A
	# ScrollContainer is a real Container: it assigns the label's width from
	# the outside and clips anything that still doesn't fit, exactly like
	# CombatLog already does — so wrapping actually takes effect here too.
	var report_scroll := ScrollContainer.new()
	report_scroll.position = Vector2(10, 50)
	report_scroll.custom_minimum_size = Vector2(540, 440)
	report_scroll.size = report_scroll.custom_minimum_size
	report_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	report_background.add_child(report_scroll)

	# GameConfig.make_selectable_label instead of a plain Label so the report
	# can actually be selected and copied rather than needing a screenshot.
	# Its own context menu (right-click → Select All → Copy) is what actually
	# lets the header get copied together with everything below it — a plain
	# click-drag selection can't extend past whatever's currently visible in
	# the wrapping ScrollContainer, so once a report is tall enough to need
	# scrolling, drag-selection alone could never span the whole thing.
	# Three tabs, in this order (user's spec): Score, Damage by unit, After
	# Action Report. The last is the report this screen always had (formerly
	# titled "Battle summary"), unchanged. The Score tab opens first when the
	# battle produced a score; otherwise the report itself does, as before.
	var has_score: bool = battle_manager != null and not battle_manager.battle_result.is_empty()
	var score_text: String = _score_tab_text()
	var report_label := GameConfig.make_selectable_label(score_text if has_score else report_text)
	report_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report_scroll.add_child(report_label)
	var score_tab := Button.new()
	score_tab.name = "ScoreTab"
	score_tab.text = "Score"
	score_tab.pressed.connect(func(): report_label.text = score_text; report_scroll.scroll_vertical = 0)
	var damage_tab := Button.new()
	damage_tab.name = "DamageByUnit"
	damage_tab.text = "Damage by unit"
	damage_tab.pressed.connect(func(): report_label.text = "\n".join(battle_manager.unit_combat_stats.report_lines()); report_scroll.scroll_vertical = 0)
	var seed_tab := Button.new()
	seed_tab.name = "SeedTab"
	seed_tab.text = "Seed"
	seed_tab.pressed.connect(func(): report_label.text = seed_tab_text(); report_scroll.scroll_vertical = 0)
	var report_tab := Button.new()
	report_tab.name = "AfterActionReportTab"
	report_tab.text = "After Action Report"
	report_tab.pressed.connect(func(): report_label.text = report_text; report_scroll.scroll_vertical = 0)
	# Laid out left to right by each button's own measured width, so no tab
	# ever overlaps its neighbor whatever the font.
	var tab_x := 10.0
	for tab in [score_tab, damage_tab, seed_tab, report_tab]:
		report_background.add_child(tab)
		tab.position = Vector2(tab_x, 10)
		tab_x += tab.get_combined_minimum_size().x + 6.0

	# The Seed tab's button: copies the seed to the clipboard. Shown only while that tab is.
	copy_seed_button = Button.new()
	copy_seed_button.name = "CopySeed"
	copy_seed_button.text = "Copy seed"
	copy_seed_button.position = Vector2(10, REPORT_PANEL_SIZE.y - 40.0)
	copy_seed_button.visible = false
	copy_seed_button.pressed.connect(copy_seed)
	report_background.add_child(copy_seed_button)
	for tab in [score_tab, damage_tab, report_tab]:
		tab.pressed.connect(func(): copy_seed_button.visible = false)
	seed_tab.pressed.connect(func(): copy_seed_button.visible = true)

	restart_button = Button.new()
	restart_button.text = "Choose new setup and try again"
	var buttons_top: float = REPORT_PANEL_TOP + REPORT_PANEL_SIZE.y + REPORT_BUTTONS_GAP
	restart_button.position = Vector2(20, buttons_top)
	restart_button.pressed.connect(func(): restart_requested.emit())
	add_child(restart_button)

	review_history_button = Button.new()
	review_history_button.text = "Review Battle History"
	review_history_button.position = Vector2(20, buttons_top + REPORT_BUTTON_ROW_HEIGHT) # below restart_button
	review_history_button.pressed.connect(_on_review_history_pressed)
	add_child(review_history_button)

	# A sibling of report_background, not a child of it — it has to stay
	# clickable and visible even while the report itself is hidden, or
	# there'd be no way back. Lets the player peek at the final map
	# underneath the report (units' end positions, terrain) without
	# tearing the report down the way Review Battle History does.
	hide_report_button = Button.new()
	hide_report_button.text = "Hide Report"
	hide_report_button.position = Vector2(20, buttons_top + 2.0 * REPORT_BUTTON_ROW_HEIGHT) # below review_history_button
	hide_report_button.pressed.connect(_on_hide_report_pressed)
	add_child(hide_report_button)


func _on_hide_report_pressed() -> void:
	if not report_background:
		return
	report_background.visible = not report_background.visible
	hide_report_button.text = "Show Report" if not report_background.visible else "Hide Report"


## Enters history-review mode: hides the AAR report and the live units
## (their FINAL positions would otherwise show through/underneath the
## historical playback, which draws over the same map), and shows a
## scrubbable timeline over BattleManager's recorded history. Ground
## truth, not fog-of-war-limited — see BattleHistoryViewer's own doc
## comment for why that's a deliberate, confirmed choice for this feature
## specifically, unlike the AAR report itself.
func _on_review_history_pressed() -> void:
	if not battle_manager:
		return
	report_background.visible = false
	restart_button.visible = false
	review_history_button.visible = false
	hide_report_button.visible = false
	_set_live_units_visible(false)

	history_viewer = preload("res://scripts/battle_history_viewer.gd").new()
	var history: Array[Dictionary] = battle_manager.battle_history()
	history_viewer.setup(history, battle_manager.battle_history_fire_events())
	add_map_node(map_viewport, history_viewer)
	if dashboard:
		dashboard.history_viewer = history_viewer

	history_slider = HSlider.new()
	history_slider.position = Vector2(20, 610)
	history_slider.size = Vector2(700, 20)
	history_slider.min_value = 0
	history_slider.max_value = max(history.size() - 1, 0)
	history_slider.step = 1
	history_slider.value = history_slider.max_value # start at the battle's final moment
	history_slider.value_changed.connect(_on_history_slider_changed)
	add_child(history_slider)

	history_time_label = Label.new()
	history_time_label.position = Vector2(730, 606)
	history_time_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	add_child(history_time_label)
	_update_history_time_label()

	history_back_button = Button.new()
	history_back_button.text = "Back to Report"
	history_back_button.position = Vector2(20, 640)
	history_back_button.pressed.connect(_on_history_back_pressed)
	add_child(history_back_button)

	history_play_button = Button.new()
	history_play_button.text = "Play"
	history_play_button.position = Vector2(150, 640)
	history_play_button.pressed.connect(_on_history_play_pressed)
	add_child(history_play_button)


func _on_history_slider_changed(value: float) -> void:
	if history_viewer:
		history_viewer.set_index(int(value)) # pauses playback, same as any video player's seek bar
		_update_history_play_button_text()
	_update_history_time_label()


## Play/Pause — see BattleHistoryViewer.toggle_play for what happens when
## pressed at the battle's final moment (restarts from the beginning).
## The slider/label/button then stay in sync every frame via _process
## while is_playing, not just at the moment of the click.
func _on_history_play_pressed() -> void:
	if not history_viewer:
		return
	history_viewer.toggle_play()
	_update_history_play_button_text()


func _update_history_play_button_text() -> void:
	if history_play_button and history_viewer:
		history_play_button.text = "Pause" if history_viewer.is_playing else "Play"


func _update_history_time_label() -> void:
	if not history_viewer or not battle_manager:
		return
	history_time_label.text = battle_manager.clock_string(history_viewer.current_time())


## Leaves history-review mode: tears down the scrubber and restores the
## AAR report and the live units' own (final, current) visibility exactly
## as they were.
func _on_history_back_pressed() -> void:
	if dashboard:
		dashboard.history_viewer = null
	for node in [history_viewer, history_slider, history_time_label, history_back_button, history_play_button]:
		if node:
			node.queue_free()
	history_viewer = null
	history_slider = null
	history_time_label = null
	history_back_button = null
	history_play_button = null

	_set_live_units_visible(true)
	# report_background's own visibility is restored from hide_report_button's
	# text, not forced true — if the player had hidden the report before
	# opening history review, entering and leaving review mode shouldn't
	# silently pop it back open.
	if report_background and hide_report_button:
		report_background.visible = hide_report_button.text == "Hide Report"
	if restart_button:
		restart_button.visible = true
	if review_history_button:
		review_history_button.visible = true
	if hide_report_button:
		hide_report_button.visible = true


func _set_live_units_visible(p_visible: bool) -> void:
	if not battle_manager:
		return
	for u in battle_manager.player_units + battle_manager.enemy_units:
		u.visible = p_visible


## History playback: BattleHistoryViewer owns the actual time-advance
## logic (advance_playback); this just drives it every frame and keeps
## the slider/label/button in sync while it's running. set_value_no_
## signal avoids re-entering _on_history_slider_changed (which would
## otherwise treat the programmatic update as a manual scrub and pause
## playback right back off again).
func _process(delta: float) -> void:
	if history_viewer and history_viewer.is_playing:
		history_viewer.advance_playback(delta)
		if history_slider:
			history_slider.set_value_no_signal(history_viewer.current_index)
		_update_history_time_label()
		if not history_viewer.is_playing: # reached the end this frame
			_update_history_play_button_text()
