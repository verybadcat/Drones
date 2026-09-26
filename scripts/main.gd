extends Node2D
## Root scene and coordinator. It holds what outlasts any one screen — the map itself (a
## SubViewport with its own fixed camera), the parts of the display that belong to it (the scale
## bar, compass and weather block in MapHudOverlay, the tactical clock, the elevation and
## location readouts), the wind and rain sound, the durable score history and the chosen recon
## setup — and shows exactly one screen at a time (a GameScreen): level select, then
## deployment (drag units into position, optionally set the seed), then the battle (with a general retreat order the
## player can give at any time) and its after-action report, whose "choose a new setup" goes
## back to level select — so trying again can change the reconnaissance setup itself, not just
## doctrine.
##
## A screen owns every widget it creates and is closed by freeing it, so nothing from one
## screen can linger on the next; what it needs from the parts kept here it says through
## GameScreen's few methods (shows_map_marks, clock_text, map_mouse_world_position,
## battle_is_over) rather than this class knowing which screen is up.

const BattleScoreLog = preload("res://scripts/battle_score_log.gd")
const WindAmbience = preload("res://scripts/wind_ambience.gd")
const RainAmbience = preload("res://scripts/rain_ambience.gd")

## The screen showing right now (null only before _ready finishes).
var current_screen: GameScreen
var recon_mode: GameConfig.ReconMode = GameConfig.ReconMode.SPOTTER
## The seed the player typed on the first screen (-1: random), and the one the coming battle actually
## uses (drawn from it, or at random, when deployment starts; always 0 or more). The battle report shows it.
var chosen_seed: int = -1
var battle_seed: int = -1

# The map (deployment, the battle) lives inside this SubViewport rather than directly under root
# so it can have its own Camera2D, kept permanently fixed at GameConfig.CAMERA_CENTER_X showing
# the ENTIRE modeled world (GameConfig.CAMERA_VIEWPORT_WIDTH_PX wide — see that constant's own
# doc comment for why this is wider than just MAP_WIDTH_PX, and why nothing here ever pans any
# more) — see _ready() for the full setup. Built once and kept for the app's whole lifetime.
var map_container: SubViewportContainer
var map_viewport: SubViewport
var map_camera: Camera2D

# A fixed 1000m reference bar, top-right of the map (the attacker's own corner — every map here
# has the enemy approaching from the east/right, so judging the enemy's own closing distance
# against this is the more useful place for it than the defender's own corner), a compass rose,
# bottom-right, showing true north on this real map, and the wind/precipitation block. See
# MapHudOverlay's own doc comment for why this lives in a separate node rather than main.gd's own
# _draw(): it must be added as a CHILD of this node, and specifically AFTER map_container, so it
# draws on top of the map instead of underneath it.
var _map_hud_overlay: Node2D
var _last_weather_signature: String = ""

# The sound of the wind — follows Weather.current from deployment through the end of the battle
# (see _process); silent on the level-select screen, which shows no weather.
var wind_ambience: WindAmbience
# The sound of the rain — same lifetime as the wind (see _process).
var rain_ambience: RainAmbience

# Always present (not part of any screen). A real 5km map needs a frame of reference: this shows
# real ground elevation under the cursor.
var _elevation_label: Label

# The tactical clock (0600 + BattleManager.scenario_elapsed_time) — shown before the battle starts
# too, frozen at the planned H-hour; what it reads is the current screen's to say (clock_text).
var _clock_label: Label

# The real place this map depicts — see GameConfig.CURRENT_MAP.name.
var _location_label: Label

## The durable score history (see BattleScoreLog for how it survives restarts and code updates).
## A field, not a constant path, so a test can point it somewhere disposable — nothing else should
## ever reassign it.
var score_log := BattleScoreLog.new()


func _ready() -> void:
	# The score history is a PLAYER's record: an automated (headless) run — every
	# test that drives a battle through this scene — must never write to it.
	# (An empty path is "no history"; a test that wants one sets its own.)
	if DisplayServer.get_name() == "headless":
		score_log.path = ""
	map_container = SubViewportContainer.new()
	map_container.position = Vector2(0, 0)
	map_container.stretch = true
	add_child(map_container)

	wind_ambience = WindAmbience.new()
	add_child(wind_ambience)
	rain_ambience = RainAmbience.new()
	add_child(rain_ambience)

	# Added AFTER map_container specifically — see MapHudOverlay's own doc
	# comment for why draw order here isn't cosmetic, it's the whole fix.
	_map_hud_overlay = preload("res://scripts/map_hud_overlay.gd").new()
	add_child(_map_hud_overlay)

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

	_map_hud_overlay.queue_redraw() # the scale bar/compass depend on the loaded map too


## What the display that outlasts the screens shows follows what the current screen asks for
## (see GameScreen): the scale bar and compass and the tactical clock belong to the map and the
## battle — not on the level-select screen, back from deployment on — and the weather is only
## presented where the screen shows it. (Weather.current is global; it is never cleared for this.)
func _apply_screen_hud(screen: GameScreen) -> void:
	_map_hud_overlay.map_marks_visible = screen.shows_map_marks()
	_map_hud_overlay.weather_visible = screen.shows_weather()
	_map_hud_overlay.queue_redraw()
	_clock_label.visible = screen.shows_map_marks()


## The map dropdown changed — switch GameConfig's own active map, then
## re-apply everything in main.gd itself that depends on it (window size,
## camera limits, the location readout) so the change is visible
## immediately, still on the level-select screen, rather than only taking
## effect once deployment starts.
func _on_map_chosen(map_id: String) -> void:
	GameConfig.set_active_map(map_id)
	_apply_map_dimensions()


func _process(_delta: float) -> void:
	# Root itself carries no camera, so this stays exactly screen-anchored
	# and matches map_container's own fixed screen rect (GameConfig.
	# CAMERA_VIEWPORT_WIDTH_PX x MAP_HEIGHT_PX) — the current screen's
	# map_mouse_world_position still goes through the inner Camera2D's transform to
	# get the actual world position for the elevation lookup itself.
	var mouse_pos := get_global_mouse_position()
	if mouse_pos.x < 0.0 or mouse_pos.x > GameConfig.CAMERA_VIEWPORT_WIDTH_PX or mouse_pos.y < 0.0 or mouse_pos.y > GameConfig.MAP_HEIGHT_PX:
		_elevation_label.visible = false
	else:
		_elevation_label.visible = true
		var elevation_m: float = GameConfig.elevation_m(current_screen.map_mouse_world_position())
		_elevation_label.text = "Elevation: %dm" % int(round(elevation_m))

	_clock_label.text = current_screen.clock_text()

	# Wind and rain sound: from the moment this battle's weather is rolled (deployment)
	# until the battle ends; none where the screen presents no weather (the scenario
	# picker) or once the battle is over. Ground-level wind, gusts ignored.
	var weather_audible: bool = Weather.current != null and current_screen.shows_weather() and not current_screen.battle_is_over()
	wind_ambience.set_wind(Weather.current.wind_speed_10m if weather_audible else -1.0)
	# Rain sounds on the same terms (only actual rain: sleet and snow are silent).
	rain_ambience.set_rain(
		Weather.current.intensity_class() if weather_audible else Weather.Intensity.NONE,
		Weather.current.precip_type() if weather_audible else Weather.Precip.NONE)

	var weather_signature: String = Weather.current.hud_signature() if Weather.current != null else ""
	if weather_signature != _last_weather_signature:
		_last_weather_signature = weather_signature
		_map_hud_overlay.queue_redraw()


## Shows `screen` in place of whatever is showing: the old one is freed (with everything it
## created), the map marks and clock follow what the new one asks for. The caller has already
## set everything the screen needs.
func _open_screen(screen: GameScreen) -> void:
	if current_screen != null:
		current_screen.queue_free()
	current_screen = screen
	_apply_screen_hud(screen)
	add_child(screen)


func _show_level_select() -> void:
	var screen := LevelSelectScreen.new()
	screen.score_log = score_log # one history, one path (and the same headless guard)
	screen.mode_chosen.connect(_on_recon_mode_chosen)
	screen.map_chosen.connect(_on_map_chosen)
	_open_screen(screen)


func _on_recon_mode_chosen(mode: GameConfig.ReconMode) -> void:
	recon_mode = mode
	if current_screen is LevelSelectScreen:
		chosen_seed = current_screen.chosen_seed()
	_show_deployment()


func _show_deployment() -> void:
	# The battle's seed: the one typed on the first screen, or a random one — always a real number, so
	# the report can show it and it can be used again. The March weather is drawn from it (the
	# offset is the one BattleManager has always used), shown on the map from the moment
	# deployment starts, and used as-is by BattleManager.start_battle.
	battle_seed = chosen_seed if chosen_seed >= 0 else randi_range(0, LevelSelectScreen.MAX_SEED - 8000)
	Weather.current = Weather.roll(battle_seed + 7919)
	var screen := DeploymentPhase.new()
	screen.battle_seed = battle_seed
	screen.recon_mode = recon_mode
	screen.map_viewport = map_viewport
	screen.start_requested.connect(_on_start_requested)
	_open_screen(screen)


## "Start Battle" was pressed with this doctrine (see DeploymentPhase.request_start).
func _on_start_requested(doctrine: Dictionary) -> void:
	var screen := BattleScreen.new()
	screen.doctrine = doctrine
	screen.recon_mode = recon_mode
	screen.map_viewport = map_viewport
	screen.map_area = Rect2(Vector2.ZERO, map_container.size)
	screen.score_log = score_log
	screen.restart_requested.connect(_show_level_select)
	_open_screen(screen)
