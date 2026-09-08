extends Node2D
## Root scene: a level-select screen (spotter vs. drone team — see
## GameConfig.ReconMode), then deployment (drag units + set doctrine), then
## the battle (with a general retreat order the player can give at any
## time), then the AAR report with a restart so you can change doctrine and
## try again. Restarting keeps the recon mode chosen at the start — level
## select only appears once, at launch.

var level_select_screen: LevelSelectScreen
var recon_mode: GameConfig.ReconMode = GameConfig.ReconMode.SPOTTER

# The map (deployment_screen/battle_manager) lives inside this SubViewport
# rather than directly under root, so a Camera2D can pan just the map
# without dragging the sidebar (a direct sibling of root, outside the
# viewport) along with it — see _ready() for the full setup and
# GameConfig.WEST_FLANK_WIDTH_PX for why a camera is needed here at all.
# Built once and kept for the app's whole lifetime, unlike the phase nodes
# below which _clear_all() tears down and recreates every phase.
var map_container: SubViewportContainer
var map_viewport: SubViewport
var map_camera: Camera2D

var deployment_screen: DeploymentScreen
var doctrine_panel: DoctrinePanel
var start_button: Button

var battle_manager: BattleManager
var combat_log: CombatLog
var casualty_dashboard: CasualtyDashboard
var retreat_button: Button
var pause_button: Button
# Untyped (not DronePilotDebugPanel) — a brand-new class_name script isn't
# resolvable via a static type reference from another script until the
# Godot editor itself has scanned the project and rebuilt its global class
# cache, which a plain run (or headless CLI test) never triggers on its
# own. See _on_start_pressed for the matching preload()-based construction.
var drone_debug_panel
# Untyped for the same class-cache reason as drone_debug_panel above. Added
# to map_viewport (NOT root, unlike drone_debug_panel) — it draws in MAP
# space so its heat cells and contact markers line up with real world
# positions and pan correctly with the camera.
var enemy_heatmap_overlay

var report_background: Control
var restart_button: Button
var review_history_button: Button

# Post-battle "drag through time" replay — see battle_history_viewer.gd.
# history_viewer is untyped for the same brand-new-class_name reason as
# drone_debug_panel/enemy_heatmap_overlay above, and lives in map_viewport
# (map-space rendering). Created/freed per battle-end, not per app
# lifetime, since it depends on that specific battle's recorded history.
var history_viewer
var history_slider: HSlider
var history_time_label: Label
var history_back_button: Button

# "See what the drone pilot is thinking" — off by default (see _ready),
# toggled by the "d" key (_unhandled_input) rather than a sidebar button
# since the sidebar has no vertical space left (see the button-row
# comments in _on_start_pressed). Persists across battles within a
# session (unlike drone_debug_panel itself, which is recreated per
# battle) since it's a standing developer preference, not battle state.
var _drone_debug_enabled: bool = false

# "Where enemies are known to be, and where the commander's models guess
# they might be" — the enemy heat-map overlay, toggled independently of
# the drone-pilot debug overlay above by the "e" key, so either, both, or
# neither can be on. Same off-by-default/persists-across-battles
# reasoning as _drone_debug_enabled.
var _enemy_heatmap_enabled: bool = false

# Where the live drone-pilot debug snapshot is written whenever the
# overlay above is on, so it can be inspected from OUTSIDE the running
# game (e.g. by pasting/reading this file) at the exact moment the battle
# is paused — see DronePilotDebugPanel's own doc comment for why a paused
# battle still refreshes this correctly (frozen state, re-read and
# re-written unchanged). res:// resolves to the real project directory in
# a normal (non-exported) run, which is what makes this externally
# readable at all.
const DRONE_DEBUG_SNAPSHOT_PATH: String = "res://debug_state/drone_pilot_snapshot.json"

# Always present, in both the deployment and battle phases — not cleared by
# _clear_all(). A real 5km map needs a frame of reference: this shows real
# ground elevation under the cursor, and a fixed-length scale bar gives a
# sense of true distance at a glance.
var _elevation_label: Label

# The tactical clock (0600 + BattleManager.scenario_elapsed_time) — shown
# before the battle starts too, frozen at the planned H-hour.
var _clock_label: Label


func _ready() -> void:
	map_container = SubViewportContainer.new()
	map_container.position = Vector2(0, 0)
	map_container.size = Vector2(GameConfig.MAP_WIDTH_PX, GameConfig.MAP_HEIGHT_PX)
	map_container.stretch = true
	add_child(map_container)

	map_viewport = SubViewport.new()
	map_viewport.size = Vector2i(int(GameConfig.MAP_WIDTH_PX), int(GameConfig.MAP_HEIGHT_PX))
	map_container.add_child(map_viewport)

	map_camera = Camera2D.new()
	map_camera.position = Vector2(GameConfig.CAMERA_DEFAULT_X, GameConfig.MAP_HEIGHT_PX / 2.0)
	map_camera.limit_left = int(-GameConfig.WEST_FLANK_WIDTH_PX)
	map_camera.limit_right = int(GameConfig.MAP_WIDTH_PX)
	map_camera.limit_top = 0
	map_camera.limit_bottom = int(GameConfig.MAP_HEIGHT_PX)
	map_viewport.add_child(map_camera)
	map_camera.make_current()

	_elevation_label = Label.new()
	_elevation_label.position = Vector2(8, 4)
	_elevation_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_elevation_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_elevation_label.add_theme_constant_override("shadow_offset_x", 1)
	_elevation_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_elevation_label)

	_clock_label = Label.new()
	_clock_label.position = Vector2(GameConfig.MAP_WIDTH_PX - 90, 4)
	_clock_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_clock_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_clock_label.add_theme_constant_override("shadow_offset_x", 1)
	_clock_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_clock_label)

	queue_redraw() # the scale bar is static; draw it once up front

	_show_level_select()


func _process(delta: float) -> void:
	# Root itself carries no camera, so this stays exactly screen-anchored
	# and still matches map_container's fixed 1000x700 screen rect — only
	# the elevation VALUE (below) needs to account for the map's own
	# camera pan.
	var mouse_pos := get_global_mouse_position()
	if mouse_pos.x < 0.0 or mouse_pos.x > GameConfig.MAP_WIDTH_PX or mouse_pos.y < 0.0 or mouse_pos.y > GameConfig.MAP_HEIGHT_PX:
		_elevation_label.visible = false
	else:
		_elevation_label.visible = true
		var elevation_m: float = GameConfig.elevation_m(_map_mouse_world_position())
		_elevation_label.text = "Elevation: %dm" % int(round(elevation_m))

	_clock_label.text = battle_manager.clock_string() if battle_manager else "%02d:00:00" % int(GameConfig.SCENARIO_START_HOUR)

	if battle_manager and map_camera:
		var target_x: float = GameConfig.compute_camera_target_x(battle_manager._camera_relevant_positions(), map_camera.position.x)
		map_camera.position.x = lerp(map_camera.position.x, target_x, delta * GameConfig.CAMERA_FOLLOW_LERP_SPEED)
		# A resupply run spawns at whatever edge of the map is CURRENTLY on
		# screen (see BattleManager._resupply_entry_point_for) rather than a
		# fixed pre-placed point, so it always visually enters from off-map
		# instead of popping into existence mid-view — battle_manager has no
		# reach up to the actual Camera2D node, so this is pushed down to it
		# every frame instead.
		battle_manager.current_camera_x = map_camera.position.x

	# Deliberately NOT gated on battle_manager.is_paused — main.gd's own
	# _process keeps running regardless (see DronePilotDebugPanel's doc
	# comment), so a paused battle just means drone_pilot_debug_snapshot()
	# keeps returning the same frozen values each frame, which get written
	# out unchanged. That's exactly what makes this externally inspectable
	# at a paused moment, not a bug to fix.
	if _drone_debug_enabled and battle_manager:
		_write_drone_debug_snapshot()


## _unhandled_input rather than _input: lets any real UI control (a
## button, a text field) consume the key first if it ever legitimately
## wants "d"/"e" for something; these are global fallback toggles, not
## per-control shortcuts. The two are deliberately independent — separate
## keys, separate flags, separate nodes — so either overlay, both, or
## neither can be on at once.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_D:
			_drone_debug_enabled = not _drone_debug_enabled
			if drone_debug_panel:
				drone_debug_panel.visible = _drone_debug_enabled
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_E:
			_enemy_heatmap_enabled = not _enemy_heatmap_enabled
			if enemy_heatmap_overlay:
				enemy_heatmap_overlay.visible = _enemy_heatmap_enabled
			get_viewport().set_input_as_handled()


## Writes battle_manager.drone_pilot_debug_snapshot() to DRONE_DEBUG_
## SNAPSHOT_PATH as JSON — the snapshot is already JSON-native (see that
## function's own doc comment), so this is a direct dump, no conversion
## needed. Overwrites every frame the overlay is on; a tiny dict, so the
## cost is negligible even at full frame rate.
func _write_drone_debug_snapshot() -> void:
	var snap: Dictionary = battle_manager.drone_pilot_debug_snapshot()
	var dir := DirAccess.open("res://")
	if dir and not dir.dir_exists("debug_state"):
		dir.make_dir("debug_state")
	var f := FileAccess.open(DRONE_DEBUG_SNAPSHOT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(snap, "\t"))


## The mouse's position in the MAP's own world space, camera pan included —
## SubViewport.get_mouse_position() only accounts for the container's
## screen offset, not the inner Camera2D's transform, so this has to go
## through a node that actually lives inside the SubViewport instead
## (Node2D.get_global_mouse_position() applies the viewport's full canvas
## transform, camera and all).
func _map_mouse_world_position() -> Vector2:
	if battle_manager:
		return battle_manager.get_global_mouse_position()
	if deployment_screen:
		return deployment_screen.get_global_mouse_position()
	return Vector2.ZERO


## A fixed 1000m reference bar, bottom-left of the map — the one thing on
## screen with a known, constant real-world length to judge everything else
## against.
func _draw() -> void:
	var bar_m := 1000.0
	var bar_px: float = bar_m * GameConfig.PIXELS_PER_METER
	var origin := Vector2(20.0, GameConfig.MAP_HEIGHT_PX - 24.0)
	draw_line(origin, origin + Vector2(bar_px, 0.0), Color.WHITE, 2.0)
	draw_line(origin, origin + Vector2(0.0, -6.0), Color.WHITE, 2.0)
	draw_line(origin + Vector2(bar_px, 0.0), origin + Vector2(bar_px, -6.0), Color.WHITE, 2.0)
	draw_string(ThemeDB.fallback_font, origin + Vector2(0.0, -10.0), "%d m" % int(bar_m),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)


func _clear_all() -> void:
	for node in [level_select_screen, deployment_screen, doctrine_panel, start_button, battle_manager,
			combat_log, casualty_dashboard, retreat_button, pause_button, drone_debug_panel,
			enemy_heatmap_overlay, report_background, restart_button, review_history_button,
			history_viewer, history_slider, history_time_label, history_back_button]:
		if node:
			node.queue_free()
	level_select_screen = null
	deployment_screen = null
	doctrine_panel = null
	start_button = null
	battle_manager = null
	combat_log = null
	casualty_dashboard = null
	retreat_button = null
	pause_button = null
	drone_debug_panel = null
	enemy_heatmap_overlay = null
	report_background = null
	restart_button = null
	review_history_button = null
	history_viewer = null
	history_slider = null
	history_time_label = null
	history_back_button = null


func _show_level_select() -> void:
	_clear_all()

	level_select_screen = LevelSelectScreen.new()
	level_select_screen.mode_chosen.connect(_on_recon_mode_chosen)
	add_child(level_select_screen)


func _on_recon_mode_chosen(mode: GameConfig.ReconMode) -> void:
	recon_mode = mode
	_show_deployment()


func _show_deployment() -> void:
	_clear_all()
	map_camera.position = Vector2(GameConfig.CAMERA_DEFAULT_X, GameConfig.MAP_HEIGHT_PX / 2.0) # nobody deploys off-map, so the camera never needs to move during this phase

	deployment_screen = DeploymentScreen.new()
	deployment_screen.recon_mode = recon_mode
	map_viewport.add_child(deployment_screen)

	doctrine_panel = DoctrinePanel.new()
	doctrine_panel.position = Vector2(1020, 20)
	add_child(doctrine_panel)

	start_button = Button.new()
	start_button.text = "Start Battle"
	start_button.position = Vector2(1020, 540)
	start_button.pressed.connect(_on_start_pressed)
	add_child(start_button)


func _on_start_pressed() -> void:
	var positions := deployment_screen.get_positions()
	# One standing order for the whole force, not a separately dialed-in
	# threshold per squad — see DoctrinePanel.get_retreat_threshold's own
	# doc comment for the real-command-authority reasoning behind this.
	var retreat_threshold := doctrine_panel.get_retreat_threshold()

	var squads: Array[Dictionary] = []
	for pos in positions.squad_positions:
		squads.append({
			"position": pos,
			"retreat_threshold": retreat_threshold,
		})

	var mortar_doctrine := doctrine_panel.get_mortar_doctrine()
	mortar_doctrine["position"] = positions.mortar_position

	var doctrine := {
		"squads": squads,
		"mortar": mortar_doctrine,
		"spotter": {"position": positions.spotter_position},
		"recon_mode": recon_mode,
	}

	deployment_screen.queue_free()
	deployment_screen = null
	doctrine_panel.queue_free()
	doctrine_panel = null
	start_button.queue_free()
	start_button = null

	retreat_button = Button.new()
	retreat_button.text = "Order General Retreat"
	retreat_button.position = Vector2(1020, 20) # measured 181x31 — see pause_button's own x below; casualty_dashboard's y below is against this row's shared height
	retreat_button.pressed.connect(_on_retreat_pressed)
	add_child(retreat_button)

	pause_button = Button.new()
	pause_button.text = "Pause"
	# Same row as retreat_button (measured 181px wide) rather than a new row
	# below it — the sidebar's vertical space is already fully accounted for
	# down to combat_log's fixed position near the window's own 700px
	# bottom edge (see combat_log.position below), with no slack left to
	# push everything down a further button-row's worth.
	pause_button.position = Vector2(1020 + 181.0 + 14.0, 20)
	pause_button.pressed.connect(_on_pause_pressed)
	add_child(pause_button)

	battle_manager = BattleManager.new()
	battle_manager.battle_ended.connect(_on_battle_ended)
	map_viewport.add_child(battle_manager)

	casualty_dashboard = CasualtyDashboard.new()
	# 20 + 31 (retreat_button's real height, shared by pause_button on the
	# same row) + 14px breathing room. Mortar resupply requests itself
	# automatically now (see BattleManager._update_mortar_resupply_requests)
	# — no button for it, so this sidebar is back to the single button row
	# it had before that was ever added, now shared by retreat + pause.
	casualty_dashboard.position = Vector2(1020, 65)
	casualty_dashboard.setup(battle_manager)
	add_child(casualty_dashboard)

	combat_log = CombatLog.new()
	# 65 (dashboard's own y) + 500 (its real measured worst-case height, see
	# CasualtyDashboard._ready) + 10px breathing room — clears the dashboard
	# even with every row showing, drone fleet row wrapped to its full
	# multi-line worst case included. The window is a fixed 700px tall (see
	# project.godot); CombatLog's own declared SIZE.y (see combat_log.gd)
	# is sized to fill what's left over.
	combat_log.position = Vector2(1020, 575)
	add_child(combat_log)

	# Drawn over the map itself, bottom-left, rather than in the sidebar
	# (which has no vertical space left) — see DronePilotDebugPanel's own
	# doc comment. Hidden by default; _drone_debug_enabled is a standing
	# preference toggled via "d" (_unhandled_input), not reset per battle.
	drone_debug_panel = preload("res://scripts/drone_pilot_debug_panel.gd").new()
	drone_debug_panel.position = Vector2(8, GameConfig.MAP_HEIGHT_PX - 260.0 - 8.0)
	drone_debug_panel.setup(battle_manager)
	drone_debug_panel.visible = _drone_debug_enabled
	add_child(drone_debug_panel)

	# Added to map_viewport, not root — this one draws IN MAP SPACE (heat
	# cells and contact markers at real world positions), unlike
	# drone_debug_panel's fixed-position sidebar-style text above. Hidden
	# by default; independent of _drone_debug_enabled (see EnemyHeatmap
	# Overlay's own doc comment) — toggled via "e", not "d".
	enemy_heatmap_overlay = preload("res://scripts/enemy_heatmap_overlay.gd").new()
	enemy_heatmap_overlay.setup(battle_manager)
	enemy_heatmap_overlay.visible = _enemy_heatmap_enabled
	map_viewport.add_child(enemy_heatmap_overlay)

	battle_manager.start_battle(doctrine, combat_log)


func _on_retreat_pressed() -> void:
	if battle_manager:
		battle_manager.order_general_retreat()


func _on_pause_pressed() -> void:
	if not battle_manager:
		return
	battle_manager.toggle_pause()
	pause_button.text = "Resume" if battle_manager.is_paused else "Pause"


func _on_battle_ended(report_text: String) -> void:
	if retreat_button:
		retreat_button.queue_free()
		retreat_button = null
	if pause_button:
		pause_button.queue_free()
		pause_button = null

	report_background = ColorRect.new()
	report_background.color = Color(0.05, 0.05, 0.05, 0.85)
	report_background.position = Vector2(20, 20)
	report_background.size = Vector2(560, 500)
	add_child(report_background)

	# A bare Label outside any Container never actually respects a width
	# smaller than its own natural (unwrapped) content size — custom_min_size
	# can only raise a control's minimum, never cap it below that, so the
	# report's longest line (e.g. a full "Enemy withdrew: ..." list) forced
	# the label wider than this box regardless of autowrap_mode. A
	# ScrollContainer is a real Container: it assigns the label's width from
	# the outside and clips anything that still doesn't fit, exactly like
	# CombatLog already does — so wrapping actually takes effect here too.
	var report_scroll := ScrollContainer.new()
	report_scroll.position = Vector2(10, 10)
	report_scroll.custom_minimum_size = Vector2(540, 480)
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
	var report_label := GameConfig.make_selectable_label(report_text)
	report_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report_scroll.add_child(report_label)

	restart_button = Button.new()
	restart_button.text = "Set new doctrine and try again"
	restart_button.position = Vector2(20, 540)
	restart_button.pressed.connect(_show_deployment)
	add_child(restart_button)

	review_history_button = Button.new()
	review_history_button.text = "Review Battle History"
	review_history_button.position = Vector2(20, 581) # below restart_button (measured 31px tall)
	review_history_button.pressed.connect(_on_review_history_pressed)
	add_child(review_history_button)


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
	_set_live_units_visible(false)

	history_viewer = preload("res://scripts/battle_history_viewer.gd").new()
	var history: Array[Dictionary] = battle_manager.battle_history()
	history_viewer.setup(history)
	map_viewport.add_child(history_viewer)

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


func _on_history_slider_changed(value: float) -> void:
	if history_viewer:
		history_viewer.set_index(int(value))
	_update_history_time_label()


func _update_history_time_label() -> void:
	if not history_viewer or not battle_manager:
		return
	history_time_label.text = battle_manager.clock_string(history_viewer.current_time())


## Leaves history-review mode: tears down the scrubber and restores the
## AAR report and the live units' own (final, current) visibility exactly
## as they were.
func _on_history_back_pressed() -> void:
	for node in [history_viewer, history_slider, history_time_label, history_back_button]:
		if node:
			node.queue_free()
	history_viewer = null
	history_slider = null
	history_time_label = null
	history_back_button = null

	_set_live_units_visible(true)
	if report_background:
		report_background.visible = true
	if restart_button:
		restart_button.visible = true
	if review_history_button:
		review_history_button.visible = true


func _set_live_units_visible(p_visible: bool) -> void:
	if not battle_manager:
		return
	for u in battle_manager.player_units + battle_manager.enemy_units:
		u.visible = p_visible
