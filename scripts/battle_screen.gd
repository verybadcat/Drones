class_name BattleScreen
extends GameScreen
## The battle: the battle manager (in the map's SubViewport) with everything that watches
## or commands it — the casualty dashboard and combat log in the sidebar, the fall back, retreat
## and pause controls in the strip above the map, the orders card, the
## AI inspector and the developer overlays — and, once the battle ends, the end-of-battle
## report (BattleReport). main.gd sets `doctrine`, `recon_mode`, `map_viewport`, `map_area`
## and `score_log` BEFORE adding this to the tree; the battle starts as soon as it is there.
## When the player asks for a new setup from the report, restart_requested is emitted.

signal restart_requested

# "See what the drone pilot is thinking" — off by default, toggled by the "d" key
# (_unhandled_input) rather than a sidebar button since the sidebar has no vertical space
# left. A standing developer preference, so it persists across battles within a session
# (static), unlike the panel itself, which is recreated per battle.
static var drone_debug_enabled: bool = false

# "Where enemies are known to be, and where the commander's models guess they might be" —
# the enemy heat-map overlay, toggled independently by the "e" key, so either overlay, both,
# or neither can be on. Same off-by-default/persists-across-battles reasoning.
static var enemy_heatmap_enabled: bool = false

# Where the live debug snapshots are written every frame a battle is running —
# unconditionally, independent of whether an on-screen overlay happens to be visible, so
# reading these files is a reliable way to get real visibility into what the AI is actually
# deciding without depending on the player's screen or a screenshot at all. res:// resolves
# to the real project directory in a normal (non-exported) run, which is what makes them
# externally readable at all. See DronePilotDebugPanel's own doc comment for why a paused
# battle still refreshes them correctly (frozen state, re-read and re-written unchanged).
const DRONE_DEBUG_SNAPSHOT_PATH: String = "res://debug_state/drone_pilot_snapshot.json"
# battle_manager.mortar_decision_debug_snapshot() — every mortar on BOTH sides, since this is
# an out-of-band developer file, not something the player sees (see that function's own doc
# comment for why that's fine here but wouldn't be for an on-screen panel).
const MORTAR_DEBUG_SNAPSHOT_PATH: String = "res://debug_state/mortar_decision_snapshot.json"
# battle_manager.general_unit_debug_snapshot() — every unit on BOTH sides, not just
# mortars/drones. Built directly from a real investigation (a general-retreat order routing
# squads through a distant, unnecessary cover detour) that the other snapshots had no
# visibility into at all — this is the general-purpose one.
const UNIT_DEBUG_SNAPSHOT_PATH: String = "res://debug_state/unit_snapshot.json"
# Conditions, drone hazard and drone weather counters (BattleManager.weather_debug_snapshot).
const WEATHER_DEBUG_SNAPSHOT_PATH: String = "res://debug_state/weather_snapshot.json"
# Every mortar-fire sound event, both sides (BattleManager.mortar_audio_debug_snapshot) — a
# real, previously-reported gap: "sometimes I hear the enemy mortar and sometimes I don't",
# where static reading of the firing/fast-forward code couldn't fully account for what was
# seen. Real-world timing and pool-reuse state can only be caught by watching it happen.
const MORTAR_AUDIO_DEBUG_SNAPSHOT_PATH: String = "res://debug_state/mortar_audio_snapshot.json"

var doctrine: Dictionary
var recon_mode: GameConfig.ReconMode = GameConfig.ReconMode.SPOTTER
var map_viewport: SubViewport
var map_area: Rect2 # the on-screen area of the map (the orders card stays inside it)
var score_log: BattleScoreLog

var battle_manager: BattleManager
var combat_log: CombatLog
var casualty_dashboard: CasualtyDashboard
var retreat_button: Button
var pause_button: Button
# Untyped (not DronePilotDebugPanel) — a brand-new class_name script isn't resolvable via a
# static type reference from another script until the Godot editor itself has scanned the
# project and rebuilt its global class cache, which a plain run (or headless CLI test) never
# triggers on its own; the panels are constructed via preload() instead.
var drone_debug_panel
var decision_inspector
var keys_help: KeysHelp
var fall_back_button: Button
var clear_orders_button: Button
var top_buttons: HBoxContainer
const TOP_BUTTONS_X: float = 580.0
const TOP_BUTTONS_GAP: int = 12
# Untyped for the same class-cache reason. Lives in the map's SubViewport (NOT screen space,
# unlike drone_debug_panel): it draws in MAP space so its heat cells and contact markers line
# up with real world positions.
var enemy_heatmap_overlay
var unit_orders_panel: UnitOrdersPanel
## The end-of-battle report, once the battle has ended (null before).
var report: BattleReport


func _ready() -> void:
	super()
	battle_manager = BattleManager.new()
	battle_manager.battle_ended.connect(_on_battle_ended)
	add_map_node(map_viewport, battle_manager)

	casualty_dashboard = CasualtyDashboard.new()
	# retreat_button/pause_button used to share a button row here; both now
	# live in the open strip above the map instead (see their own creation
	# below, next to fall_back_button) — the sidebar no longer has
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
	# doc comment. Hidden by default; drone_debug_enabled is a standing
	# preference toggled via "d" (_unhandled_input), not reset per battle.
	drone_debug_panel = preload("res://scripts/drone_pilot_debug_panel.gd").new()
	drone_debug_panel.position = Vector2(8, GameConfig.MAP_HEIGHT_PX - 260.0 - 8.0)
	drone_debug_panel.setup(battle_manager)
	drone_debug_panel.visible = drone_debug_enabled
	add_child(drone_debug_panel)

	# In the map's SubViewport, not screen space — this one draws IN MAP SPACE (heat
	# cells and contact markers at real world positions), unlike
	# drone_debug_panel's fixed-position sidebar-style text above. Hidden
	# by default; independent of drone_debug_enabled (see EnemyHeatmap
	# Overlay's own doc comment) — toggled via "e", not "d".
	enemy_heatmap_overlay = preload("res://scripts/enemy_heatmap_overlay.gd").new()
	enemy_heatmap_overlay.setup(battle_manager)
	enemy_heatmap_overlay.visible = enemy_heatmap_enabled
	add_map_node(map_viewport, enemy_heatmap_overlay)

	battle_manager.start_battle(doctrine, combat_log)

	# A card that pops up beside a friendly unit when it's clicked (and goes away
	# on any click outside it); hides itself if the unit is lost or the battle
	# ends.
	unit_orders_panel = UnitOrdersPanel.new()
	unit_orders_panel.setup(battle_manager, map_viewport, map_area)
	add_child(unit_orders_panel)
	battle_manager.unit_selected.connect(unit_orders_panel.show_for)
	decision_inspector = preload("res://scripts/decision_inspector.gd").new()
	decision_inspector.setup(battle_manager)
	decision_inspector.position = Vector2(12, 50)
	decision_inspector.visible = false
	add_child(decision_inspector)
	# (No button for the AI inspector: it is on the "i" key, and the list of keys (keys_help, "?") says so.)

	# The list of keys, "?" or the small note in the corner; not a battle order, so not in the top row.
	keys_help = KeysHelp.new()
	add_child(keys_help)

	# Fall back: every unit that can be ordered to (see BattleManager.order_all_fall_back) moves
	# back toward the edge of the map and holds there — a step short of retreat_button's own
	# withdrawal, which takes everyone off the map. It replaced the delayed-retreat controls
	# (a delay slider and its button): "get rid of ... the slider. Instead have a 'fall back'
	# button. That orders all units to fall back."
	fall_back_button = Button.new()
	fall_back_button.text = "Fall Back"
	fall_back_button.tooltip_text = "Orders every unit to fall back toward your edge of the map — usually 500 to 1000 m — and hold there. Not a retreat off the map."
	fall_back_button.pressed.connect(_on_fall_back_pressed)

	# Clear Orders: cancels every order given (falling back and holding, the general retreat, a
	# mortar's squad-fire order). Grayed out while there is nothing to clear (see _process).
	clear_orders_button = Button.new()
	clear_orders_button.text = "Clear Orders"
	clear_orders_button.tooltip_text = "Cancel every order you have given."
	clear_orders_button.disabled = true
	clear_orders_button.pressed.connect(_on_clear_orders_pressed)

	# The full withdrawal, next to fall_back_button — same top row, not the sidebar (see
	# casualty_dashboard's own comment on why that row is empty now).
	retreat_button = Button.new()
	retreat_button.text = "Retreat Now"
	retreat_button.pressed.connect(_on_retreat_pressed)

	pause_button = Button.new()
	pause_button.text = "Pause"
	pause_button.pressed.connect(_on_pause_pressed)

	# The four order buttons in one row, laid out by a container so the gaps between them are the
	# same whatever each label's width ("Let's make the spacing among the top buttons uniform"), and
	# stay so when Pause becomes Resume.
	top_buttons = HBoxContainer.new()
	top_buttons.position = Vector2(TOP_BUTTONS_X, 4)
	top_buttons.add_theme_constant_override("separation", TOP_BUTTONS_GAP)
	add_child(top_buttons)
	for button in [clear_orders_button, fall_back_button, retreat_button, pause_button]:
		top_buttons.add_child(button)


func clock_text() -> String:
	return battle_manager.clock_string() if battle_manager else super()


func map_mouse_world_position() -> Vector2:
	return battle_manager.get_global_mouse_position() if battle_manager else Vector2.ZERO


func battle_is_over() -> bool:
	return battle_manager != null and battle_manager.battle_over


func _process(_delta: float) -> void:
	if battle_manager == null:
		return
	if clear_orders_button:
		clear_orders_button.disabled = not battle_manager.has_orders_to_clear()
	# The mortar's range circle while the mouse is over the mortar (also while paused).
	battle_manager.update_hover(map_mouse_world_position(), map_area.has_point(get_viewport().get_mouse_position()))
	# Deliberately NOT gated on drone_debug_enabled (the human-facing visual
	# overlay) or battle_manager.is_paused — these files are how an outside
	# investigator (reading them directly, not watching the screen) gets
	# reliable visibility into the AI's actual live decisions, and that
	# has to work whether or not the player happens to have the on-screen
	# panel toggled on, and needs a paused battle to still reflect the
	# frozen-in-place state rather than going stale. Writing every frame
	# regardless is a trivial cost (a tiny JSON dump) for what it buys.
	# The mortar decision snapshot is what actually diagnosed the
	# mortar-not-firing report that led to the mortar decisionmaking rewrite.
	_write_debug_snapshot(DRONE_DEBUG_SNAPSHOT_PATH, battle_manager.drone_pilot_debug_snapshot())
	_write_debug_snapshot(MORTAR_DEBUG_SNAPSHOT_PATH, battle_manager.mortar_decision_debug_snapshot())
	_write_debug_snapshot(UNIT_DEBUG_SNAPSHOT_PATH, battle_manager.general_unit_debug_snapshot())
	_write_debug_snapshot(WEATHER_DEBUG_SNAPSHOT_PATH, battle_manager.weather_debug_snapshot())
	_write_debug_snapshot(MORTAR_AUDIO_DEBUG_SNAPSHOT_PATH, battle_manager.mortar_audio_debug_snapshot())


## _unhandled_input rather than _input: lets any real UI control (a
## button, a text field) consume the key first if it ever legitimately
## wants "d"/"e" for something; these are global fallback toggles, not
## per-control shortcuts. The two are deliberately independent — separate
## keys, separate flags, separate nodes — so either overlay, both, or
## neither can be on at once.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_D:
			drone_debug_enabled = not drone_debug_enabled
			if drone_debug_panel:
				drone_debug_panel.visible = drone_debug_enabled
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_I:
			if decision_inspector:
				decision_inspector.visible = not decision_inspector.visible
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_E:
			enemy_heatmap_enabled = not enemy_heatmap_enabled
			if enemy_heatmap_overlay:
				enemy_heatmap_overlay.visible = enemy_heatmap_enabled
			get_viewport().set_input_as_handled()


## Writes `snap` to `path` as JSON — a direct dump of a JSON-native snapshot dictionary.
## Called every frame the battle is running (see _process) — a tiny dict each, so the cost
## is negligible even at full frame rate.
func _write_debug_snapshot(path: String, snap: Dictionary) -> void:
	var dir := DirAccess.open("res://")
	if dir and not dir.dir_exists("debug_state"):
		dir.make_dir("debug_state")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(snap, "\t"))


func _on_clear_orders_pressed() -> void:
	if battle_manager:
		battle_manager.clear_all_orders()


func _on_fall_back_pressed() -> void:
	if battle_manager:
		battle_manager.order_all_fall_back()


func _on_retreat_pressed() -> void:
	if battle_manager:
		battle_manager.order_general_retreat()


func _on_pause_pressed() -> void:
	if not battle_manager:
		return
	battle_manager.toggle_pause()
	pause_button.text = "Resume" if battle_manager.is_paused else "Pause"


## The battle is over: the retreat and pause controls have nothing left to do, and the
## report takes the screen (see BattleReport), with the AI inspector kept above it.
func _on_battle_ended(report_text: String) -> void:
	if fall_back_button:
		fall_back_button.queue_free()
		fall_back_button = null
	if clear_orders_button:
		clear_orders_button.queue_free()
		clear_orders_button = null
	if retreat_button:
		retreat_button.queue_free()
		retreat_button = null
	if pause_button:
		pause_button.queue_free()
		pause_button = null

	report = BattleReport.new()
	report.battle_manager = battle_manager
	report.map_viewport = map_viewport
	report.score_log = score_log
	report.recon_mode = recon_mode
	report.dashboard = casualty_dashboard
	report.restart_requested.connect(func(): restart_requested.emit())
	add_child(report)
	report.open(report_text)
	if decision_inspector:
		move_child(decision_inspector, -1)
	move_child(keys_help, -1) # the list of keys stays above the report
