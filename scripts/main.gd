extends Node2D
## Root scene: a level-select screen (spotter vs. drone team — see
## GameConfig.ReconMode), then deployment (drag units + set doctrine), then
## the battle (with a general retreat order the player can give at any
## time), then the AAR report with a restart so you can change doctrine and
## try again. Restarting keeps the recon mode chosen at the start — level
## select only appears once, at launch.

var level_select_screen: LevelSelectScreen
var recon_mode: GameConfig.ReconMode = GameConfig.ReconMode.SPOTTER

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


func _process(_delta: float) -> void:
	var mouse_pos := get_global_mouse_position()
	if mouse_pos.x < 0.0 or mouse_pos.x > GameConfig.MAP_WIDTH_PX or mouse_pos.y < 0.0 or mouse_pos.y > GameConfig.MAP_HEIGHT_PX:
		_elevation_label.visible = false
	else:
		_elevation_label.visible = true
		var elevation_m: float = GameConfig.elevation_m(mouse_pos)
		_elevation_label.text = "Elevation: %dm" % int(round(elevation_m))

	_clock_label.text = battle_manager.clock_string() if battle_manager else "%02d:00:00" % int(GameConfig.SCENARIO_START_HOUR)


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

	deployment_screen = DeploymentScreen.new()
	deployment_screen.recon_mode = recon_mode
	add_child(deployment_screen)

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
	var thresholds := doctrine_panel.get_squad_retreat_thresholds()

	var squads: Array[Dictionary] = []
	for i in positions.squad_positions.size():
		squads.append({
			"position": positions.squad_positions[i],
			"retreat_threshold": thresholds[i],
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
	retreat_button.position = Vector2(1020, 20)
	retreat_button.pressed.connect(_on_retreat_pressed)
	add_child(retreat_button)

	battle_manager = BattleManager.new()
	battle_manager.battle_ended.connect(_on_battle_ended)
	add_child(battle_manager)

	casualty_dashboard = CasualtyDashboard.new()
	casualty_dashboard.position = Vector2(1020, 55)
	casualty_dashboard.setup(battle_manager)
	add_child(casualty_dashboard)

	combat_log = CombatLog.new()
	combat_log.position = Vector2(1020, 370) # clears the dashboard's height even with the drone row shown
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

	# RichTextLabel instead of a plain Label so the report can actually be
	# selected and copied (click-drag to select, Ctrl+C to copy) rather than
	# needing a screenshot — bbcode_enabled stays off (the default) so the
	# report's own "===", "%", ":" etc. render as literal text, never parsed
	# as markup. scroll_active is off and fit_content is on so this sizes
	# itself to its full content and leaves the actual scrolling to the
	# wrapping ScrollContainer above, exactly like the Label it replaces did.
	var report_label := RichTextLabel.new()
	report_label.text = report_text
	report_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	report_label.selection_enabled = true
	report_label.scroll_active = false
	report_label.fit_content = true
	report_scroll.add_child(report_label)

	restart_button = Button.new()
	restart_button.text = "Set new doctrine and try again"
	restart_button.position = Vector2(20, 540)
	restart_button.pressed.connect(_show_deployment)
	add_child(restart_button)
