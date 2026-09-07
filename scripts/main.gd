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

var report_background: Control
var restart_button: Button

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
		var target_x: float = GameConfig.compute_camera_target_x(battle_manager._camera_relevant_positions())
		map_camera.position.x = lerp(map_camera.position.x, target_x, delta * GameConfig.CAMERA_FOLLOW_LERP_SPEED)


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
			combat_log, casualty_dashboard, retreat_button, report_background, restart_button]:
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
	report_background = null
	restart_button = null


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
		"resupply_point": positions.resupply_point,
	}

	deployment_screen.queue_free()
	deployment_screen = null
	doctrine_panel.queue_free()
	doctrine_panel = null
	start_button.queue_free()
	start_button = null

	retreat_button = Button.new()
	retreat_button.text = "Order General Retreat"
	retreat_button.position = Vector2(1020, 20) # measured 31px tall — see casualty_dashboard's own y below
	retreat_button.pressed.connect(_on_retreat_pressed)
	add_child(retreat_button)

	battle_manager = BattleManager.new()
	battle_manager.battle_ended.connect(_on_battle_ended)
	map_viewport.add_child(battle_manager)

	casualty_dashboard = CasualtyDashboard.new()
	# 20 + 31 (retreat_button's real height) + 14px breathing room. Mortar
	# resupply requests itself automatically now (see BattleManager.
	# _update_mortar_resupply_requests) — no button for it, so this sidebar
	# is back to the single button row it had before that was ever added.
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

	battle_manager.start_battle(doctrine, combat_log)


func _on_retreat_pressed() -> void:
	if battle_manager:
		battle_manager.order_general_retreat()


func _on_battle_ended(report_text: String) -> void:
	if retreat_button:
		retreat_button.queue_free()
		retreat_button = null

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
