extends Node2D
## Root scene: a level-select screen (spotter vs. drone team — see
## GameConfig.ReconMode), then deployment (drag units + set doctrine), then
## the battle (with a general retreat order the player can give at any
## time), then the AAR report with a restart back to level select — so
## trying again can change the reconnaissance setup itself, not just
## doctrine, rather than being stuck with whatever was chosen at launch.

# The playback-speed dropdown's own choices — parallel arrays (index i's
# label names index i's multiplier) rather than a Dictionary, so the
# dropdown's item order is exactly this array's order with no separate
# sort/lookup step. 1/4x to 4x per the request; doubling steps read
# naturally on a speed control the same way camera zoom or audio playback
# speed controls usually do.
const SPEED_OPTIONS: Array[float] = [0.25, 0.5, 1.0, 2.0, 4.0]
const SPEED_LABELS: Array[String] = ["Speed: 0.25x", "Speed: 0.5x", "Speed: 1x", "Speed: 2x", "Speed: 4x"]

var level_select_screen: LevelSelectScreen
var recon_mode: GameConfig.ReconMode = GameConfig.ReconMode.SPOTTER

# The map (deployment_screen/battle_manager) lives inside this SubViewport
# rather than directly under root so it can have its own Camera2D, kept
# permanently fixed at GameConfig.CAMERA_CENTER_X showing the ENTIRE
# modeled world (GameConfig.CAMERA_VIEWPORT_WIDTH_PX wide — see that
# constant's own doc comment for why this is wider than just MAP_WIDTH_PX,
# and why nothing here ever pans any more) — see _ready() for the full
# setup. Built once and kept for the app's whole lifetime, unlike the phase
# nodes below which _clear_all() tears down and recreates every phase.
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
var decision_inspector
var inspect_button: Button
var speed_dropdown: OptionButton
var schedule_retreat_label: Label
var scheduled_retreat_slider: HSlider
var scheduled_retreat_value_label: Label
var schedule_retreat_button: Button
var scheduled_retreat_status_label: Label
var cancel_scheduled_retreat_button: Button
# Untyped for the same class-cache reason as drone_debug_panel above. Added
# to map_viewport (NOT root, unlike drone_debug_panel) — it draws in MAP
# space so its heat cells and contact markers line up with real world
# positions and pan correctly with the camera.
var enemy_heatmap_overlay

var report_background: Control
var restart_button: Button
var review_history_button: Button
var hide_report_button: Button

# Post-battle "drag through time" replay — see battle_history_viewer.gd.
# history_viewer is untyped for the same brand-new-class_name reason as
# drone_debug_panel/enemy_heatmap_overlay above, and lives in map_viewport
# (map-space rendering). Created/freed per battle-end, not per app
# lifetime, since it depends on that specific battle's recorded history.
var history_viewer
var history_slider: HSlider
var history_time_label: Label
var history_back_button: Button
var history_play_button: Button

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

# Where the live drone-pilot debug snapshot is written every frame any
# battle is running — unconditionally, independent of whether the on-screen
# overlay (_drone_debug_enabled, the "d" key) happens to be visible, so
# reading this file is a reliable way to get real visibility into the
# drone's actual live decision (position, current reasoning, top candidates)
# without depending on the player's screen or a screenshot at all — see
# DronePilotDebugPanel's own doc comment for why a paused battle still
# refreshes this correctly (frozen state, re-read and re-written unchanged).
# res:// resolves to the real project directory in a normal (non-exported)
# run, which is what makes this externally readable at all.
const DRONE_DEBUG_SNAPSHOT_PATH: String = "res://debug_state/drone_pilot_snapshot.json"

# Same reasoning as DRONE_DEBUG_SNAPSHOT_PATH above, for battle_manager.
# mortar_decision_debug_snapshot() — every mortar on BOTH sides, since this
# is an out-of-band developer file, not something the player sees (see
# that function's own doc comment for why that's fine here but wouldn't be
# for an on-screen panel).
const MORTAR_DEBUG_SNAPSHOT_PATH: String = "res://debug_state/mortar_decision_snapshot.json"

# Always present, in both the deployment and battle phases — not cleared by
# _clear_all(). A real 5km map needs a frame of reference: this shows real
# ground elevation under the cursor, and a fixed-length scale bar gives a
# sense of true distance at a glance.
var _elevation_label: Label

# The tactical clock (0600 + BattleManager.scenario_elapsed_time) — shown
# before the battle starts too, frozen at the planned H-hour.
var _clock_label: Label

# The real place this map depicts — see GameConfig.CURRENT_MAP.name.
var _location_label: Label


func _ready() -> void:
	map_container = SubViewportContainer.new()
	map_container.position = Vector2(0, 0)
	map_container.stretch = true
	add_child(map_container)

	map_viewport = SubViewport.new()
	map_container.add_child(map_viewport)

	map_camera = Camera2D.new()
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
	_clock_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_clock_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_clock_label.add_theme_constant_override("shadow_offset_x", 1)
	_clock_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_clock_label)

	# Always on screen (unlike _elevation_label, which only shows on hover)
	# — this map depicts a real place, not a generic fictional one, and the
	# name should be as visible as the clock. See GameConfig.CURRENT_MAP.name's
	# own doc comment for the real history.
	_location_label = Label.new()
	_location_label.position = Vector2(8, 24)
	_location_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_location_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_location_label.add_theme_constant_override("shadow_offset_x", 1)
	_location_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_location_label)

	_apply_map_dimensions()

	_show_level_select()


## Every window/viewport/camera/label property that depends on WHICH real
## place is loaded — split out of _ready() so the level-select screen's own
## map dropdown (LevelSelectScreen.map_chosen) can re-apply all of it after
## GameConfig.set_active_map, not just at startup. Idempotent: safe to call
## again with the same map already active (LevelSelectScreen only actually
## calls this when the selection changes, but nothing here assumes that).
func _apply_map_dimensions() -> void:
	# Sized from GameConfig's own map-derived state, not project.godot's
	# fixed viewport_width/height — those were hand-set for one specific
	# map's own dimensions and would silently stop matching the moment a
	# differently-sized real map was loaded (see GameConfig.
	# SIDEBAR_COLUMN_WIDTH/MIN_WINDOW_HEIGHT_PX's own doc comments).
	get_window().size = Vector2i(
		int(GameConfig.SIDEBAR_X + GameConfig.SIDEBAR_COLUMN_WIDTH),
		int(max(GameConfig.MAP_HEIGHT_PX, GameConfig.MIN_WINDOW_HEIGHT_PX)))

	# map_viewport's own size isn't set directly — map_container.stretch
	# (set once in _ready) keeps it locked to the container's own size
	# automatically; setting it here too, after the viewport is already a
	# stretch-managed child, just produces an engine warning and is ignored.
	map_container.size = Vector2(GameConfig.CAMERA_VIEWPORT_WIDTH_PX, GameConfig.MAP_HEIGHT_PX)

	map_camera.position = Vector2(GameConfig.CAMERA_CENTER_X, GameConfig.MAP_HEIGHT_PX / 2.0)
	map_camera.limit_left = int(-GameConfig.WEST_FLANK_WIDTH_PX)
	map_camera.limit_right = int(GameConfig.MAP_WIDTH_PX)
	map_camera.limit_top = 0
	map_camera.limit_bottom = int(GameConfig.MAP_HEIGHT_PX)

	_clock_label.position = Vector2(GameConfig.CAMERA_VIEWPORT_WIDTH_PX - 90, 4)

	# Coordinates alongside the place name/subtitle — real, verifiable, and
	# enough for a curious player to go look the actual spot up themselves
	# on a real map, the same way this game's own terrain was sourced.
	_location_label.text = "%s, %s (%s)" % [
		GameConfig.CURRENT_MAP.name, GameConfig.CURRENT_MAP.location_subtitle, GameConfig.CURRENT_MAP.coordinates]

	queue_redraw() # the scale bar/compass depend on the loaded map too


func _process(delta: float) -> void:
	# Root itself carries no camera, so this stays exactly screen-anchored
	# and matches map_container's own fixed screen rect (GameConfig.
	# CAMERA_VIEWPORT_WIDTH_PX x MAP_HEIGHT_PX) — _map_mouse_world_position
	# below still goes through the inner Camera2D's transform to get the
	# actual world position for the elevation lookup itself.
	var mouse_pos := get_global_mouse_position()
	if mouse_pos.x < 0.0 or mouse_pos.x > GameConfig.CAMERA_VIEWPORT_WIDTH_PX or mouse_pos.y < 0.0 or mouse_pos.y > GameConfig.MAP_HEIGHT_PX:
		_elevation_label.visible = false
	else:
		_elevation_label.visible = true
		var elevation_m: float = GameConfig.elevation_m(_map_mouse_world_position())
		_elevation_label.text = "Elevation: %dm" % int(round(elevation_m))

	_clock_label.text = battle_manager.clock_string() if battle_manager else "%02d:00:00" % int(GameConfig.SCENARIO_START_HOUR)

	if scheduled_retreat_status_label and cancel_scheduled_retreat_button:
		var has_schedule: bool = battle_manager != null and not is_inf(battle_manager.scheduled_retreat_time) and not battle_manager.player_general_retreat_ordered
		scheduled_retreat_status_label.visible = has_schedule
		cancel_scheduled_retreat_button.visible = has_schedule
		if has_schedule:
			scheduled_retreat_status_label.text = "Retreat scheduled for %s" % battle_manager.clock_string(battle_manager.scheduled_retreat_time)

	# Deliberately NOT gated on _drone_debug_enabled (the human-facing visual
	# overlay) or battle_manager.is_paused — this file is how an outside
	# investigator (reading it directly, not watching the screen) gets
	# reliable visibility into the drone's actual live decision, and that
	# has to work whether or not the player happens to have the on-screen
	# panel toggled on, and needs a paused battle to still reflect the
	# frozen-in-place state rather than going stale. Writing every frame
	# regardless is a trivial cost (a tiny JSON dump) for what it buys.
	# Same reasoning for the mortar decision snapshot below — this is what
	# actually diagnosed the mortar-not-firing report that led to the
	# mortar decisionmaking rewrite.
	if battle_manager:
		_write_debug_snapshot(DRONE_DEBUG_SNAPSHOT_PATH, battle_manager.drone_pilot_debug_snapshot())
		_write_debug_snapshot(MORTAR_DEBUG_SNAPSHOT_PATH, battle_manager.mortar_decision_debug_snapshot())

	# History playback: BattleHistoryViewer owns the actual time-advance
	# logic (advance_playback); this just drives it every frame and keeps
	# the slider/label/button in sync while it's running. set_value_no_
	# signal avoids re-entering _on_history_slider_changed (which would
	# otherwise treat the programmatic update as a manual scrub and pause
	# playback right back off again).
	if history_viewer and history_viewer.is_playing:
		history_viewer.advance_playback(delta)
		if history_slider:
			history_slider.set_value_no_signal(history_viewer.current_index)
		_update_history_time_label()
		if not history_viewer.is_playing: # reached the end this frame
			_update_history_play_button_text()


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
		elif event.keycode == KEY_I:
			if decision_inspector:
				decision_inspector.visible = not decision_inspector.visible
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_E:
			_enemy_heatmap_enabled = not _enemy_heatmap_enabled
			if enemy_heatmap_overlay:
				enemy_heatmap_overlay.visible = _enemy_heatmap_enabled
			get_viewport().set_input_as_handled()


## Writes `snap` to `path` as JSON — shared by both the drone and mortar
## debug snapshots (drone_pilot_debug_snapshot()/mortar_decision_debug_
## snapshot(), both already JSON-native, so this is a direct dump, no
## conversion needed). Called unconditionally every frame any battle is
## running (see _process) — a tiny dict each, so the cost is negligible
## even at full frame rate.
func _write_debug_snapshot(path: String, snap: Dictionary) -> void:
	var dir := DirAccess.open("res://")
	if dir and not dir.dir_exists("debug_state"):
		dir.make_dir("debug_state")
	var f := FileAccess.open(path, FileAccess.WRITE)
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


## A fixed 1000m reference bar, top-right of the map (the attacker's own
## corner — every map here has the enemy approaching from the east/right,
## so judging the enemy's own closing distance against this is the more
## useful place for it than the defender's own corner, who already knows
## their deployment at a glance) — the one thing on screen with a known,
## constant real-world length to judge everything else against — plus a
## compass rose, bottom-right, showing true north on this real map. Read
## from GameConfig.CURRENT_MAP.compass_north_screen_direction, not a
## constant of main.gd's own: this map keeps the attacker approaching from
## the map's own east/right (the existing convention every other piece of
## this game already assumes), and different real places' own real attack
## directions land at different angles relative to that — north doesn't
## have to point up, or the same way twice.
func _draw() -> void:
	var bar_m := 1000.0
	var bar_px: float = bar_m * GameConfig.PIXELS_PER_METER
	var origin := Vector2(GameConfig.CAMERA_VIEWPORT_WIDTH_PX - 20.0 - bar_px, 34.0) # below _clock_label, which sits at y=4
	draw_line(origin, origin + Vector2(bar_px, 0.0), Color.WHITE, 2.0)
	draw_line(origin, origin + Vector2(0.0, 6.0), Color.WHITE, 2.0)
	draw_line(origin + Vector2(bar_px, 0.0), origin + Vector2(bar_px, 6.0), Color.WHITE, 2.0)
	draw_string(ThemeDB.fallback_font, origin + Vector2(0.0, 20.0), "%d m" % int(bar_m),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

	var compass_center := Vector2(GameConfig.CAMERA_VIEWPORT_WIDTH_PX - 50.0, GameConfig.MAP_HEIGHT_PX - 50.0)
	var compass_radius := 26.0
	var north_dir: Vector2 = GameConfig.CURRENT_MAP.compass_north_screen_direction
	draw_arc(compass_center, compass_radius, 0.0, TAU, 32, Color(1, 1, 1, 0.7), 1.5, true)
	var north_tip: Vector2 = compass_center + north_dir * compass_radius
	draw_line(compass_center, north_tip, Color(1.0, 0.85, 0.2), 2.0)
	draw_string(ThemeDB.fallback_font, north_tip + north_dir * 10.0 - Vector2(5, -5), "N",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color(1.0, 0.85, 0.2))


func _clear_all() -> void:
	for node in [level_select_screen, deployment_screen, doctrine_panel, start_button, battle_manager,
			combat_log, casualty_dashboard, retreat_button, pause_button, drone_debug_panel, decision_inspector, inspect_button,
			speed_dropdown, enemy_heatmap_overlay, report_background, restart_button, review_history_button,
			history_viewer, history_slider, history_time_label, history_back_button, history_play_button,
			schedule_retreat_label, scheduled_retreat_slider, scheduled_retreat_value_label, schedule_retreat_button,
			scheduled_retreat_status_label, cancel_scheduled_retreat_button]:
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
	decision_inspector = null
	inspect_button = null
	speed_dropdown = null
	schedule_retreat_label = null
	scheduled_retreat_slider = null
	scheduled_retreat_value_label = null
	schedule_retreat_button = null
	scheduled_retreat_status_label = null
	cancel_scheduled_retreat_button = null
	enemy_heatmap_overlay = null
	report_background = null
	restart_button = null
	review_history_button = null
	history_viewer = null
	history_slider = null
	history_time_label = null
	history_back_button = null
	history_play_button = null


func _show_level_select() -> void:
	_clear_all()

	level_select_screen = LevelSelectScreen.new()
	level_select_screen.mode_chosen.connect(_on_recon_mode_chosen)
	level_select_screen.map_chosen.connect(_on_map_chosen)
	add_child(level_select_screen)


## The map dropdown changed — switch GameConfig's own active map, then
## re-apply everything in main.gd itself that depends on it (window size,
## camera limits, the location readout) so the change is visible
## immediately, still on the level-select screen, rather than only taking
## effect once deployment starts.
func _on_map_chosen(map_id: String) -> void:
	GameConfig.set_active_map(map_id)
	_apply_map_dimensions()


func _on_recon_mode_chosen(mode: GameConfig.ReconMode) -> void:
	recon_mode = mode
	_show_deployment()


func _show_deployment() -> void:
	_clear_all()

	deployment_screen = DeploymentScreen.new()
	deployment_screen.recon_mode = recon_mode
	map_viewport.add_child(deployment_screen)

	doctrine_panel = DoctrinePanel.new()
	doctrine_panel.position = Vector2(GameConfig.SIDEBAR_X, 20)
	add_child(doctrine_panel)

	start_button = Button.new()
	start_button.text = "Start Battle"
	start_button.position = Vector2(GameConfig.SIDEBAR_X, 540)
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

	doctrine.merge(doctrine_panel.get_commander_doctrine())

	deployment_screen.queue_free()
	deployment_screen = null
	doctrine_panel.queue_free()
	doctrine_panel = null
	start_button.queue_free()
	start_button = null

	battle_manager = BattleManager.new()
	battle_manager.battle_ended.connect(_on_battle_ended)
	map_viewport.add_child(battle_manager)

	casualty_dashboard = CasualtyDashboard.new()
	# retreat_button/pause_button used to share a button row here; both now
	# live in the open strip above the map instead (see their own creation
	# below, next to schedule_retreat_button) — the sidebar no longer has
	# any buttons of its own, but this fixed y is kept as-is rather than
	# reclaiming the now-empty space above it.
	casualty_dashboard.position = Vector2(GameConfig.SIDEBAR_X, 65)
	casualty_dashboard.setup(battle_manager)
	add_child(casualty_dashboard)

	combat_log = CombatLog.new()
	# 65 (dashboard's own y) + 550 (the dashboard's own fixed, tuned panel
	# height — comfortably fits the common case; see CasualtyDashboard.
	# _ready, which scrolls internally rather than growing past this for a
	# worst case with many enemy mortars) + 10px breathing room.
	combat_log.position = Vector2(GameConfig.SIDEBAR_X, 625)
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
	decision_inspector = preload("res://scripts/decision_inspector.gd").new()
	decision_inspector.setup(battle_manager)
	decision_inspector.position = Vector2(12, 50)
	decision_inspector.visible = false
	add_child(decision_inspector)
	inspect_button = Button.new()
	inspect_button.text = "Inspect AI (i)"
	inspect_button.position = Vector2(140, 8)
	inspect_button.pressed.connect(func(): decision_inspector.visible = not decision_inspector.visible)
	add_child(inspect_button)

	# Item text carries its own label ("Speed: ...") rather than a separate
	# Label node next to it — one less node to track through _clear_all's
	# cleanup for what's otherwise self-explanatory. Placed to the right of
	# inspect_button, in the open strip above the map rather than the
	# already-tightly-packed sidebar button row (see retreat_button/
	# pause_button's own doc comments for how little room that row has
	# left). Multiplies BattleManager.playback_speed, which scales `delta`
	# once at the very top of _process — see that var's own doc comment;
	# is_paused still freezes the battle outright regardless of this.
	speed_dropdown = OptionButton.new()
	for i in SPEED_OPTIONS.size():
		speed_dropdown.add_item(SPEED_LABELS[i])
	speed_dropdown.selected = SPEED_OPTIONS.find(1.0)
	speed_dropdown.position = Vector2(280, 8)
	speed_dropdown.item_selected.connect(func(index): battle_manager.playback_speed = SPEED_OPTIONS[index])
	add_child(speed_dropdown)

	# Plan a retreat for a later time, distinct from retreat_button's own
	# immediate order — see BattleManager.order_scheduled_retreat. A
	# slider rather than a fixed choice, per direct request, so the delay
	# can be dialed in and re-confirmed (re-pressing the button just
	# reschedules) rather than picked from a short fixed list. Placed in
	# the same open strip as inspect_button/speed_dropdown, further right,
	# since the sidebar's own button row has no spare width left (see
	# retreat_button/pause_button's own doc comments).
	schedule_retreat_label = Label.new()
	schedule_retreat_label.text = "Retreat in:"
	schedule_retreat_label.position = Vector2(430, 12)
	add_child(schedule_retreat_label)

	scheduled_retreat_slider = HSlider.new()
	scheduled_retreat_slider.min_value = 5
	scheduled_retreat_slider.max_value = 30
	scheduled_retreat_slider.step = 5
	scheduled_retreat_slider.value = 10
	scheduled_retreat_slider.custom_minimum_size = Vector2(120, 0)
	scheduled_retreat_slider.position = Vector2(500, 12)
	scheduled_retreat_slider.value_changed.connect(func(v): scheduled_retreat_value_label.text = "%d min" % int(v))
	add_child(scheduled_retreat_slider)

	scheduled_retreat_value_label = Label.new()
	scheduled_retreat_value_label.text = "10 min"
	scheduled_retreat_value_label.position = Vector2(628, 12)
	add_child(scheduled_retreat_value_label)

	schedule_retreat_button = Button.new()
	schedule_retreat_button.text = "Schedule Retreat"
	schedule_retreat_button.position = Vector2(680, 4)
	schedule_retreat_button.pressed.connect(_on_schedule_retreat_pressed)
	add_child(schedule_retreat_button)

	# The immediate order, right next to the option to schedule one for
	# later instead — same top row, not the sidebar (see casualty_
	# dashboard's own comment on why that row is empty now).
	retreat_button = Button.new()
	retreat_button.text = "Retreat Now"
	retreat_button.position = Vector2(850, 4)
	retreat_button.pressed.connect(_on_retreat_pressed)
	add_child(retreat_button)

	pause_button = Button.new()
	pause_button.text = "Pause"
	pause_button.position = Vector2(990, 4)
	pause_button.pressed.connect(_on_pause_pressed)
	add_child(pause_button)

	# Second row: once a retreat is actually scheduled, show when (kept in
	# sync every frame from _process, since the underlying time never
	# changes except by rescheduling/cancelling) and let the commander
	# countermand it. Both start hidden — nothing is scheduled yet at
	# battle start — and _process toggles their visibility together.
	scheduled_retreat_status_label = Label.new()
	scheduled_retreat_status_label.position = Vector2(430, 40)
	scheduled_retreat_status_label.visible = false
	add_child(scheduled_retreat_status_label)

	cancel_scheduled_retreat_button = Button.new()
	cancel_scheduled_retreat_button.text = "Cancel Scheduled Retreat"
	cancel_scheduled_retreat_button.position = Vector2(680, 36)
	cancel_scheduled_retreat_button.visible = false
	cancel_scheduled_retreat_button.pressed.connect(_on_cancel_scheduled_retreat_pressed)
	add_child(cancel_scheduled_retreat_button)


func _on_schedule_retreat_pressed() -> void:
	if battle_manager:
		battle_manager.order_scheduled_retreat(scheduled_retreat_slider.value * 60.0)


func _on_cancel_scheduled_retreat_pressed() -> void:
	if battle_manager:
		battle_manager.cancel_scheduled_retreat()


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
	if decision_inspector:
		move_child(decision_inspector, -1)
		move_child(inspect_button, -1)

	# A bare Label outside any Container never actually respects a width
	# smaller than its own natural (unwrapped) content size — custom_min_size
	# can only raise a control's minimum, never cap it below that, so the
	# report's longest line (e.g. a full "Enemy withdrew: ..." list) forced
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
	var report_label := GameConfig.make_selectable_label(report_text)
	report_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report_scroll.add_child(report_label)
	var summary_tab := Button.new()
	summary_tab.text = "Battle summary"
	summary_tab.position = Vector2(10, 10)
	summary_tab.pressed.connect(func(): report_label.text = report_text; report_scroll.scroll_vertical = 0)
	report_background.add_child(summary_tab)
	var damage_tab := Button.new()
	damage_tab.name = "DamageByUnit"
	damage_tab.text = "Damage by unit"
	damage_tab.position = Vector2(165, 10)
	damage_tab.pressed.connect(func(): report_label.text = "\n".join(battle_manager.unit_combat_stats.report_lines()); report_scroll.scroll_vertical = 0)
	report_background.add_child(damage_tab)

	restart_button = Button.new()
	restart_button.text = "Choose new setup and try again"
	restart_button.position = Vector2(20, 540)
	restart_button.pressed.connect(_show_level_select)
	add_child(restart_button)

	review_history_button = Button.new()
	review_history_button.text = "Review Battle History"
	review_history_button.position = Vector2(20, 581) # below restart_button (measured 31px tall)
	review_history_button.pressed.connect(_on_review_history_pressed)
	add_child(review_history_button)

	# A sibling of report_background, not a child of it — it has to stay
	# clickable and visible even while the report itself is hidden, or
	# there'd be no way back. Lets the player peek at the final map
	# underneath the report (units' end positions, terrain) without
	# tearing the report down the way Review Battle History does.
	hide_report_button = Button.new()
	hide_report_button.text = "Hide Report"
	hide_report_button.position = Vector2(20, 622) # below review_history_button
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
