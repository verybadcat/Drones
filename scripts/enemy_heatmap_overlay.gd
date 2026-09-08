extends Node2D
class_name EnemyHeatmapOverlay
## "Where enemies are known to be, and where the commander's models guess
## they might be" — a player-toggleable overlay (default OFF, see main.gd's
## "e" key), independent of the drone-pilot debug overlay ("d" key) so
## either, both, or neither can be on at once. Drawn IN MAP SPACE (added to
## map_viewport, not root — see main.gd) so it pans correctly with the
## camera and lines up with real unit/terrain positions, unlike
## DronePilotDebugPanel's fixed-position sidebar-style text panel.
## Refreshed every engine frame regardless of the battle's own pause state,
## for the same reason DronePilotDebugPanel is: a paused battle just means
## the same frozen picture keeps getting redrawn, which is the point.
##
## Two independent layers, matching the two different kinds of knowledge:
## a smooth background gradient (BattleManager.estimated_enemy_likelihood)
## for the doctrinal GUESS absent contact, and bright foreground markers
## for actual KNOWN contacts (BattleManager._known_enemy_positions/
## _recent_enemy_contacts) — both already fog-of-war-correct (gated on
## is_visible), so this never reveals anything the player doesn't already
## have a legitimate way to know. The guess layer is also actively
## suppressed over ground any friendly asset (drone or ground unit) can
## currently see — a real commander stops guessing an enemy might be
## somewhere their own people are looking right now and see is empty
## (BattleManager._point_currently_observed).

const GRID_STEP_PX: float = 150.0 * GameConfig.PIXELS_PER_METER # ~30px cells -- smooth-looking without being wasteful
const KNOWN_RADIUS_PX: float = 60.0 * GameConfig.PIXELS_PER_METER
const RECENT_RING_RADIUS_PX: float = 45.0 * GameConfig.PIXELS_PER_METER

# estimated_enemy_likelihood now checks every friendly unit's LOS to each
# cell (see BattleManager._point_currently_observed) — real ray/terrain
# geometry, not cheap, and re-running it for ~1000 cells every single
# rendered frame would be wasteful for a toggleable debug view. Recomputed
# on this slower timer instead; _draw() just paints whatever's cached, so
# the visible picture is at most RECOMPUTE_INTERVAL_S stale, never wrong.
const RECOMPUTE_INTERVAL_S: float = 0.4

var battle_manager: BattleManager
var _cached_values: Array[float] = []
var _cached_max_value: float = 0.0
var _cached_cols: int = 0
var _cached_rows: int = 0
var _recompute_timer: float = 0.0


func setup(p_battle_manager: BattleManager) -> void:
	battle_manager = p_battle_manager


func _process(delta: float) -> void:
	_recompute_timer -= delta
	if _recompute_timer <= 0.0:
		_recompute_timer = RECOMPUTE_INTERVAL_S
		_recompute_guessed_grid()
	queue_redraw()


func _draw() -> void:
	if battle_manager == null:
		return
	_draw_guessed_heatmap()
	_draw_known_contacts()


## Samples BattleManager.estimated_enemy_likelihood on a coarse grid
## covering the whole map (including the west flank, since a real
## flanking threat can be guessed at just as validly there) into the
## cache _draw() actually paints from.
func _recompute_guessed_grid() -> void:
	_cached_cols = int((GameConfig.MAP_WIDTH_PX + GameConfig.WEST_FLANK_WIDTH_PX) / GRID_STEP_PX) + 1
	_cached_rows = int(GameConfig.MAP_HEIGHT_PX / GRID_STEP_PX) + 1
	_cached_values.resize(_cached_cols * _cached_rows)
	_cached_max_value = 0.0
	for row_i in _cached_rows:
		for col_i in _cached_cols:
			var p := Vector2(-GameConfig.WEST_FLANK_WIDTH_PX + col_i * GRID_STEP_PX, row_i * GRID_STEP_PX)
			var v: float = battle_manager.estimated_enemy_likelihood(p)
			_cached_values[row_i * _cached_cols + col_i] = v
			_cached_max_value = max(_cached_max_value, v)


## Paints the cached grid's relative share of the current highest value as
## a warm, low-opacity tint — a genuine heat map, not a handful of
## isolated sample dots, so the same east/off-road doctrinal bias driving
## the drone's actual sweep (and the "ground we can currently see is
## empty" suppression) is visible as a continuous field.
func _draw_guessed_heatmap() -> void:
	if _cached_max_value <= 0.0:
		return
	for row_i in _cached_rows:
		for col_i in _cached_cols:
			var t: float = _cached_values[row_i * _cached_cols + col_i] / _cached_max_value
			if t < 0.03:
				continue
			var p := Vector2(-GameConfig.WEST_FLANK_WIDTH_PX + col_i * GRID_STEP_PX, row_i * GRID_STEP_PX)
			var color := Color(1.0, 0.35, 0.05, 0.06 + 0.4 * t)
			draw_rect(Rect2(p - Vector2(GRID_STEP_PX, GRID_STEP_PX) * 0.5, Vector2(GRID_STEP_PX, GRID_STEP_PX)), color, true)


## Solid, fully-opaque markers for anything currently actually visible
## (ground truth as far as fog-of-war allows); fainter, fading rings for a
## contact remembered but not currently in view — the same decaying
## window BattleManager._contact_search_bonus itself uses, so a marker's
## own fade rate always matches how long it's still actually influencing
## the drone's search.
func _draw_known_contacts() -> void:
	for pos in battle_manager._known_enemy_positions(Unit.Team.PLAYER):
		draw_circle(pos, KNOWN_RADIUS_PX, Color(1.0, 0.1, 0.1, 0.85))

	for u in battle_manager._recent_enemy_contacts:
		if u.state == Unit.State.ACTIVE and u.is_visible:
			continue # already drawn solid above
		var info: Dictionary = battle_manager._recent_enemy_contacts[u]
		var age: float = battle_manager.scenario_elapsed_time - info.time
		if age >= GameConfig.DRONE_CONTACT_BONUS_EXPIRY:
			continue
		var alpha: float = 0.75 * (1.0 - age / GameConfig.DRONE_CONTACT_BONUS_EXPIRY)
		draw_arc(info.position, RECENT_RING_RADIUS_PX, 0.0, TAU, 24, Color(1.0, 0.6, 0.1, alpha), 3.0, true)
