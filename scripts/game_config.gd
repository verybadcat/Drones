extends RefCounted
class_name GameConfig
## Shared map layout: the village, terrain, deployment zone, and enemy
## approach. Kept in one place so no other script can drift out of sync.

enum TerrainType { OPEN, TREES, BUILDING, HIGH_GROUND, ROAD }

# Each zone is a rectangle + terrain type + elevation level (0 = lowland,
# 1 = high ground). HIGH_GROUND and ROAD contribute no concealment/cover of
# their own (see get_terrain_type_at) — HIGH_GROUND is elevation only, ROAD
# is a movement corridor the enemy marches down before scattering. Order
# matters for drawing: earlier = painted first (underneath).
#
# More scattered cover than the first pass: small outbuildings/walls and
# extra tree clumps between the village and the enemy's approach, so a
# squad that breaks from the road under fire actually has somewhere nearby
# to go to ground.
const TERRAIN_ZONES: Array[Dictionary] = [
	{"rect": Rect2(100, 40, 300, 620), "type": TerrainType.HIGH_GROUND, "elevation": 1},
	{"rect": Rect2(330, 335, 600, 24), "type": TerrainType.ROAD, "elevation": 0},
	{"rect": Rect2(150, 150, 180, 260), "type": TerrainType.BUILDING, "elevation": 1},
	{"rect": Rect2(480, 110, 90, 160), "type": TerrainType.TREES, "elevation": 0},
	{"rect": Rect2(560, 400, 90, 160), "type": TerrainType.TREES, "elevation": 0},
	{"rect": Rect2(700, 40, 70, 620), "type": TerrainType.TREES, "elevation": 0},
	{"rect": Rect2(420, 40, 60, 60), "type": TerrainType.TREES, "elevation": 0},
	{"rect": Rect2(420, 590, 60, 60), "type": TerrainType.TREES, "elevation": 0},
	{"rect": Rect2(560, 230, 40, 35), "type": TerrainType.BUILDING, "elevation": 0},
	{"rect": Rect2(600, 470, 45, 35), "type": TerrainType.BUILDING, "elevation": 0},
]

# Legal area for the player to drag their units into on the deployment
# screen — inside the village/high ground, matching "holding the village."
const PLAYER_DEPLOYMENT_ZONE: Rect2 = Rect2(140, 160, 260, 340)

# Default starting token positions on the deployment screen, before the
# player drags them anywhere else within PLAYER_DEPLOYMENT_ZONE.
const PLAYER_DEFAULT_POSITIONS: Array[Vector2] = [
	Vector2(200, 220),
	Vector2(220, 340),
	Vector2(190, 400),
]
const PLAYER_MORTAR_DEFAULT_POSITION: Vector2 = Vector2(280, 300)

# Enemy squads start at the map's far edge and initially march down the
# road toward the village; once they take fire they break off toward the
# nearest cover (see BattleManager/Unit.seek_cover). The enemy's two
# mortars deploy at fixed rear positions and never advance.
const ENEMY_SPAWN_X: float = 950.0
const ENEMY_SQUAD_START_Y: Array[float] = [60.0, 170.0, 280.0, 390.0, 500.0, 610.0]
const ENEMY_ROAD_RALLY_POINT: Vector2 = Vector2(420.0, 335.0) # where the road march initially heads
const ENEMY_MORTAR_POSITIONS: Array[Vector2] = [Vector2(950.0, 250.0), Vector2(950.0, 450.0)]
const ENEMY_ADVANCE_SPEED: float = 35.0 # pixels/sec
const ENEMY_RETREAT_SPEED: float = 60.0 # pixels/sec, away from the village
const ENEMY_RETREAT_THRESHOLD: float = 0.5
const ENEMY_CONCERN_THRESHOLD: float = 0.25 # logs "reports the issue", doesn't retreat

# A RETREATING unit that reaches its own safe_x is marked WITHDRAWN — no
# longer part of the fight, but its casualties still count in the AAR report.
const ENEMY_SAFE_X: float = ENEMY_SPAWN_X + 60.0
const PLAYER_RETREAT_SPEED: float = 50.0 # pixels/sec, only used after a general retreat order
const PLAYER_SAFE_X: float = 20.0

const BATTLE_TIME_LIMIT: float = 300.0 # seconds; ends the battle if reached

# Spotting.
const DETECTION_BASE_RANGE: float = 260.0
const DETECTION_ELEVATION_BONUS: float = 150.0 # added when spotter is higher than target
const SPOT_CHANCE_PER_SECOND: float = 0.15
const MOVING_SPOT_MULTIPLIER: float = 3.0

# A unit caught moving in the open is much easier to hit, not just to spot —
# it has broken cover to advance (or to retreat). See CombatResolver.
const MOVING_HIT_MULTIPLIER: float = 1.6

# Direct-fire (squad) engagement range — a squad can only fire at a target
# IT could plausibly see and reach with its own weapons, unlike a mortar
# (see below), which fires on anything any friendly unit has spotted.
const SQUAD_ENGAGEMENT_RANGE: float = 300.0

# Mortars fire indirectly on spotter-relayed information — no LOS or range
# check of their own, and firing does not automatically reveal one to enemy
# squads the way a rifle's muzzle flash does. It can still be picked up by
# the opposing mortar's counter-battery (see CombatResolver / BattleManager).
const MORTAR_COUNTER_BATTERY_HOLD_CHANCE: float = 0.22 # per shot, holding position
const MORTAR_COUNTER_BATTERY_SCOOT_CHANCE: float = 0.06 # per shot, shoot-and-scoot
const MORTAR_SCOOT_HOP_DISTANCE: float = 40.0 # visible little jump after each scoot

# A squad hit by mortar fire may bolt for nearby cover regardless of overall
# casualties — mortar fire is disruptive even when it doesn't kill outright.
const RELOCATE_ON_MORTAR_HIT_CHANCE: float = 0.35
const REPOSITION_SPEED: float = 45.0 # pixels/sec, for any non-retreat repositioning


static func get_elevation_at(pos: Vector2) -> int:
	var elevation := 0
	for zone in TERRAIN_ZONES:
		if zone.rect.has_point(pos):
			elevation = max(elevation, zone.elevation)
	return elevation


## Concealment/cover terrain type at a point. HIGH_GROUND and ROAD are
## excluded — HIGH_GROUND is elevation-only, ROAD is a movement corridor.
## BUILDING beats TREES if both overlap a point.
static func get_terrain_type_at(pos: Vector2) -> TerrainType:
	var best := TerrainType.OPEN
	for zone in TERRAIN_ZONES:
		if zone.type == TerrainType.HIGH_GROUND or zone.type == TerrainType.ROAD:
			continue
		if zone.rect.has_point(pos):
			if zone.type == TerrainType.BUILDING:
				return TerrainType.BUILDING
			best = TerrainType.TREES
	return best


## A point inside the nearest TREES/BUILDING zone to `from` — where a unit
## bolting for cover heads. Randomized within the zone (not always the exact
## center) so several units heading for the same patch of cover spread out
## instead of stacking on the same pixel. Always returns something (there is
## always at least one cover zone on this map).
static func nearest_cover_point(from: Vector2) -> Vector2:
	var best_rect: Rect2
	var best_dist: float = INF
	var found := false
	for zone in TERRAIN_ZONES:
		if zone.type != TerrainType.TREES and zone.type != TerrainType.BUILDING:
			continue
		var center: Vector2 = zone.rect.position + zone.rect.size / 2.0
		var d: float = from.distance_to(center)
		if d < best_dist:
			best_dist = d
			best_rect = zone.rect
			found = true
	if not found:
		return from

	var margin := 10.0
	var w: float = max(best_rect.size.x - margin * 2.0, 1.0)
	var h: float = max(best_rect.size.y - margin * 2.0, 1.0)
	return best_rect.position + Vector2(margin, margin) + Vector2(randf() * w, randf() * h)


## Shared terrain rendering, used by both the battle view and the deployment
## screen so the map always looks the same. Call from inside a CanvasItem's
## own _draw().
static func draw_terrain(ci: CanvasItem) -> void:
	for zone in TERRAIN_ZONES:
		match zone.type:
			TerrainType.HIGH_GROUND:
				_draw_hill(ci, zone.rect)
			TerrainType.ROAD:
				_draw_road(ci, zone.rect)
			TerrainType.BUILDING:
				_draw_village(ci, zone.rect)
			TerrainType.TREES:
				_draw_forest(ci, zone.rect)


static func _draw_hill(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_rect(rect, Color(0.62, 0.58, 0.4, 0.55))
	for inset in [18.0, 40.0, 65.0]:
		var r := Rect2(rect.position + Vector2(inset, inset), rect.size - Vector2(inset * 2.0, inset * 2.0))
		if r.size.x > 0.0 and r.size.y > 0.0:
			ci.draw_rect(r, Color(0.78, 0.73, 0.52, 0.6), false, 2.0)


static func _draw_road(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_rect(rect, Color(0.55, 0.53, 0.5))
	var y: float = rect.position.y + rect.size.y / 2.0
	var x: float = rect.position.x + 5.0
	while x < rect.position.x + rect.size.x - 10.0:
		ci.draw_line(Vector2(x, y), Vector2(x + 12.0, y), Color(0.9, 0.9, 0.8), 2.0)
		x += 24.0


## Small isolated BUILDING zones (outside the main village blob) render as a
## single low wall/ruin rather than a cluster of houses.
static func _draw_village(ci: CanvasItem, rect: Rect2) -> void:
	if rect.size.x <= 60.0:
		ci.draw_rect(rect, Color(0.5, 0.48, 0.45))
		ci.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 5.0)), Color(0.32, 0.3, 0.28))
		return

	ci.draw_rect(rect, Color(0.65, 0.58, 0.45, 0.4))
	var buildings: Array[Rect2] = [
		Rect2(rect.position + Vector2(10, 10), Vector2(55, 42)),
		Rect2(rect.position + Vector2(85, 25), Vector2(45, 55)),
		Rect2(rect.position + Vector2(15, 95), Vector2(60, 48)),
		Rect2(rect.position + Vector2(100, 105), Vector2(48, 52)),
	]
	for b in buildings:
		if not rect.encloses(b):
			continue
		ci.draw_rect(b, Color(0.55, 0.42, 0.3))
		ci.draw_rect(Rect2(b.position, Vector2(b.size.x, 8.0)), Color(0.35, 0.2, 0.15))


static func _draw_forest(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_rect(rect, Color(0.3, 0.45, 0.25, 0.5))
	var spacing := 22.0
	var y: float = rect.position.y + 10.0
	var row := 0
	while y < rect.position.y + rect.size.y - 5.0:
		var x_offset: float = 10.0 if row % 2 == 0 else 20.0
		var x: float = rect.position.x + x_offset
		while x < rect.position.x + rect.size.x - 5.0:
			ci.draw_circle(Vector2(x, y), 6.0, Color(0.15, 0.35, 0.12))
			x += spacing
		y += spacing * 0.85
		row += 1
