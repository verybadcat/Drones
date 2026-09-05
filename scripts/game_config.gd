extends RefCounted
class_name GameConfig
## Shared map layout: the village, terrain, deployment zones, and enemy
## approach. Kept in one place so no other script can drift out of sync.

enum TerrainType { OPEN, TREES, BUILDING, HIGH_GROUND, ROAD }

# Each zone is a rectangle + terrain type + elevation level (0 = lowland,
# 1 = high ground). HIGH_GROUND and ROAD contribute no concealment/cover of
# their own (see get_terrain_type_at) — HIGH_GROUND is elevation only, ROAD
# is a movement corridor the enemy marches down before scattering. Order
# matters for drawing: earlier = painted first (underneath).
#
# The village is now a proper-sized settlement (see _draw_village, which
# generates a grid of houses rather than a fixed handful) plus scattered
# outlying cover — small outbuildings/walls and tree clumps between the
# village and the enemy's approach, so a squad that breaks from the road
# under fire has somewhere nearby to go to ground.
const TERRAIN_ZONES: Array[Dictionary] = [
	{"rect": Rect2(90, 30, 340, 460), "type": TerrainType.HIGH_GROUND, "elevation": 1},
	{"rect": Rect2(330, 335, 600, 24), "type": TerrainType.ROAD, "elevation": 0},
	{"rect": Rect2(120, 60, 280, 360), "type": TerrainType.BUILDING, "elevation": 1},
	{"rect": Rect2(480, 110, 90, 160), "type": TerrainType.TREES, "elevation": 0},
	{"rect": Rect2(560, 400, 90, 160), "type": TerrainType.TREES, "elevation": 0},
	{"rect": Rect2(700, 40, 70, 620), "type": TerrainType.TREES, "elevation": 0},
	{"rect": Rect2(420, 40, 60, 60), "type": TerrainType.TREES, "elevation": 0},
	{"rect": Rect2(420, 590, 60, 60), "type": TerrainType.TREES, "elevation": 0},
	{"rect": Rect2(560, 230, 40, 35), "type": TerrainType.BUILDING, "elevation": 0},
	{"rect": Rect2(600, 470, 45, 35), "type": TerrainType.BUILDING, "elevation": 0},
]

# Legal area for the player to drag squads into on the deployment screen —
# inside the village, matching "holding the village."
const PLAYER_DEPLOYMENT_ZONE: Rect2 = Rect2(135, 75, 250, 330)

# The mortar gets its own, much larger zone — real mortars sit well back
# from the front line, further than the squads holding the perimeter. Spans
# from the western map edge through and a bit past the village, so it can
# still be set up inside the village if preferred, or well to the rear.
const PLAYER_MORTAR_DEPLOYMENT_ZONE: Rect2 = Rect2(20, 40, 400, 620)

# The spotter can deploy just about anywhere on the map — it's a
# reconnaissance asset, not a firing position, and unlike squads/mortar
# isn't restricted to the village. Kept a small margin off the outer edges
# only so it can't be dropped literally off-map.
const PLAYER_SPOTTER_DEPLOYMENT_ZONE: Rect2 = Rect2(20, 20, 1320, 660)
const PLAYER_SPOTTER_DEFAULT_POSITION: Vector2 = Vector2(500, 240)

# Default starting token positions on the deployment screen, before the
# player drags them anywhere else within their zone.
const PLAYER_DEFAULT_POSITIONS: Array[Vector2] = [
	Vector2(200, 120),
	Vector2(320, 190),
	Vector2(200, 340),
]
## Below the village's BUILDING footprint (y 60-420 at this x) — a mortar
## can never be set up inside a building, so its default position must not
## be either. Still within PLAYER_MORTAR_DEPLOYMENT_ZONE and on the high
## ground behind the village.
const PLAYER_MORTAR_DEFAULT_POSITION: Vector2 = Vector2(280, 460)

# Enemy squads start at the map's far edge, first move onto the road (the
# strip is Rect2(330, 335, 600, 24) -> y:335-359), then actually march DOWN
# it toward the village — a real two-waypoint path, not a beeline to a
# scattered point that might not even be on the road. Once they take fire
# they break off toward the nearest cover (see BattleManager/Unit.seek_cover).
# The enemy's two mortars deploy at fixed rear positions and never advance.
const ENEMY_SPAWN_X: float = 950.0
const ENEMY_SQUAD_START_Y: Array[float] = [60.0, 170.0, 280.0, 390.0, 500.0, 610.0]
const ENEMY_ROAD_ENTRY_X: float = 920.0 # just inside the road's east end
const ENEMY_ROAD_MARCH_TARGET_X: float = 420.0 # where the march ends and engagement begins
const ENEMY_ROAD_Y_MIN: float = 338.0 # kept inside the road strip (335-359) with margin
const ENEMY_ROAD_Y_MAX: float = 356.0
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

# How much slack a cover zone gets on the "wrong" side of a retreating
# unit's current position before it's excluded as a detour toward the
# front — see nearest_cover_point/safest_cover_point's retreat_dir param.
const RETREAT_DIRECTION_TOLERANCE: float = 30.0

const BATTLE_TIME_LIMIT: float = 300.0 # seconds; ends the battle if reached

# Spotting.
const DETECTION_BASE_RANGE: float = 260.0
const DETECTION_ELEVATION_BONUS: float = 150.0 # added when spotter is higher than target
const SPOT_CHANCE_PER_SECOND: float = 0.15
const MOVING_SPOT_MULTIPLIER: float = 3.0

# The artillery spotter: a small, fragile, unarmed recon team whose job is
# purely to extend detection for the mortar. Better trained to spot at range
# than a rifle squad is. Concealment is two very different stories depending
# on whether it's actually using cover: hidden in trees/a building, the
# enemy effectively cannot find it beyond point-blank range — "unless they
# get very close." Standing in the open, it's found close to normally (just
# a small trained-to-minimize-exposure edge).
const SPOTTER_DETECTION_RANGE_BONUS: float = 120.0 # added to its own spotting rolls
const SPOTTER_HIDDEN_DETECTION_RANGE: float = 70.0 # replaces detection range entirely when in cover
const SPOTTER_EXPOSED_CONCEALMENT_MULTIPLIER: float = 0.8 # applies only when NOT in cover

# A unit caught moving in the open is much easier to hit by DIRECT fire, not
# just to spot — it has broken cover to advance (or to retreat). See
# CombatResolver.
const MOVING_HIT_MULTIPLIER: float = 1.6

# MORTAR fire against a moving target is the opposite story: indirect fire
# has to be aimed at where the target WILL be, which only works if the
# movement is predictable (the enemy's steady road march — see
# Unit.movement_predictable). Erratic, reactive movement (diving for cover,
# retreating) is hard to lead-aim against — a real hit-chance penalty, not
# just "no bonus."
const MORTAR_PREDICTABLE_MOVING_MULTIPLIER: float = 1.1
const MORTAR_UNPREDICTABLE_MOVING_MULTIPLIER: float = 0.25

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

# Counter-battery fire isn't instant: the enemy can only aim at where the
# mortar WAS when it fired, and the shell takes time to arrive. By the time
# it lands, a shoot-and-scoot mortar has likely moved well clear; a
# hold-position mortar is still standing right there. If the mortar is still
# within the blast radius when the shell lands, it can still get hit — the
# odds just fall off with distance from the original firing spot.
const COUNTER_BATTERY_DELAY: float = 3.0 # seconds between trigger and impact
const COUNTER_BATTERY_BLAST_RADIUS: float = 60.0 # beyond this, the old position is safe

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


static func is_in_cover(terrain: TerrainType) -> bool:
	return terrain == TerrainType.BUILDING or terrain == TerrainType.TREES


## A mortar can't be fired from inside a building (no overhead clearance for
## the round's arc) and is never allowed to set up or take cover inside one
## — see BattleManager._tick_fire, DeploymentScreen, and the avoid_buildings
## param on the cover-point functions below.
static func is_building_at(pos: Vector2) -> bool:
	return get_terrain_type_at(pos) == TerrainType.BUILDING


## A point inside a nearby TREES/BUILDING zone to `from` — where a unit
## bolting for cover heads. Weighted-random among the 2-3 nearest zones
## (mostly the nearest, sometimes the next one out) rather than always the
## single closest, plus a randomized point within whichever zone is chosen —
## so several units converging from similar positions spread across
## different patches of cover instead of all piling into the same one.
##
## `retreat_dir` (-1.0 west/player, +1.0 east/enemy, 0.0 = no constraint at
## all) excludes any zone that would require moving further in the WRONG
## direction than `from` — a unit ordered to retreat should never detour
## toward the front just because that happens to be the nearest cover.
## Non-retreat callers (an enemy breaking from its road march, a squad
## bolting under mortar fire) pass the default 0.0: any direction is fine
## when you're not specifically trying to withdraw. Falls back to `from`
## itself if nothing qualifies — the caller then simply skips the cover leg.
##
## `avoid_buildings` excludes BUILDING zones entirely, leaving only TREES —
## used by the mortar, which can never enter a building (see is_building_at).
static func nearest_cover_point(from: Vector2, retreat_dir: float = 0.0, avoid_buildings: bool = false) -> Vector2:
	var candidates: Array[Dictionary] = []
	for zone in TERRAIN_ZONES:
		if zone.type != TerrainType.TREES and zone.type != TerrainType.BUILDING:
			continue
		if avoid_buildings and zone.type == TerrainType.BUILDING:
			continue
		var center: Vector2 = zone.rect.position + zone.rect.size / 2.0
		if retreat_dir != 0.0 and (center.x - from.x) * retreat_dir < -RETREAT_DIRECTION_TOLERANCE:
			continue
		candidates.append({"rect": zone.rect, "dist": from.distance_to(center)})
	if candidates.is_empty():
		return from
	candidates.sort_custom(func(a, b): return a.dist < b.dist)

	var pool_size: int = min(3, candidates.size())
	var weights: Array[float] = [0.55, 0.3, 0.15]
	var roll := randf()
	var cumulative := 0.0
	var chosen_index := pool_size - 1
	for i in pool_size:
		cumulative += weights[i]
		if roll <= cumulative:
			chosen_index = i
			break
	var best_rect: Rect2 = candidates[chosen_index].rect

	var margin := 10.0
	var w: float = max(best_rect.size.x - margin * 2.0, 1.0)
	var h: float = max(best_rect.size.y - margin * 2.0, 1.0)
	return best_rect.position + Vector2(margin, margin) + Vector2(randf() * w, randf() * h)


## A cover point picked with some awareness of where the enemy actually is —
## used for the spotter's retreat, which can afford to be choosier than a
## squad bolting on instinct. Restricts to the nearest few cover zones (so
## it doesn't trek across the map for a marginal safety gain), then among
## those picks whichever is farthest from the nearest currently-known enemy
## position. With no known enemies, behaves like nearest_cover_point.
##
## `retreat_dir` — see nearest_cover_point — excludes cover that would mean
## detouring toward the front first; a smarter route still has to actually
## be a retreat. `avoid_buildings` — see nearest_cover_point — excludes
## BUILDING zones entirely.
static func safest_cover_point(from: Vector2, known_enemy_positions: Array[Vector2], retreat_dir: float = 0.0, avoid_buildings: bool = false) -> Vector2:
	if known_enemy_positions.is_empty():
		return nearest_cover_point(from, retreat_dir, avoid_buildings)

	var candidates: Array[Dictionary] = []
	for zone in TERRAIN_ZONES:
		if zone.type != TerrainType.TREES and zone.type != TerrainType.BUILDING:
			continue
		if avoid_buildings and zone.type == TerrainType.BUILDING:
			continue
		var center: Vector2 = zone.rect.position + zone.rect.size / 2.0
		if retreat_dir != 0.0 and (center.x - from.x) * retreat_dir < -RETREAT_DIRECTION_TOLERANCE:
			continue
		var nearest_enemy_dist: float = INF
		for ep in known_enemy_positions:
			nearest_enemy_dist = min(nearest_enemy_dist, center.distance_to(ep))
		candidates.append({"rect": zone.rect, "dist_from_self": from.distance_to(center), "safety": nearest_enemy_dist})
	if candidates.is_empty():
		return from

	candidates.sort_custom(func(a, b): return a.dist_from_self < b.dist_from_self)
	var pool_size: int = min(4, candidates.size())
	var pool := candidates.slice(0, pool_size)
	pool.sort_custom(func(a, b): return a.safety > b.safety) # safest (farthest from known enemies) first
	var best_rect: Rect2 = pool[0].rect

	var margin := 10.0
	var w: float = max(best_rect.size.x - margin * 2.0, 1.0)
	var h: float = max(best_rect.size.y - margin * 2.0, 1.0)
	return best_rect.position + Vector2(margin, margin) + Vector2(randf() * w, randf() * h)


## True if a straight line from `from` to `to` is clear — used for both
## direct (squad) fire and spotting; mortars ignore this entirely (indirect,
## spotter-relayed fire). Two kinds of terrain block it outright, not just
## "harder to hit/spot" (that's what cover/concealment are for):
##
## - A BUILDING that is neither endpoint's own position — some third
##   building sits between attacker and target. Trees do NOT block LOS
##   outright — they only affect cover/concealment.
## - A HILL (HIGH_GROUND), but only between two points that are BOTH lower
##   than it — elevation matters: standing on the hill (or on ground at
##   least as high) lets you see over/down its own slope just fine, in
##   either direction. Two units in the lowland on opposite sides of a hill
##   genuinely cannot see each other.
static func has_direct_los(from: Vector2, to: Vector2) -> bool:
	var from_elevation := get_elevation_at(from)
	var to_elevation := get_elevation_at(to)
	for zone in TERRAIN_ZONES:
		if zone.type == TerrainType.BUILDING:
			if zone.rect.has_point(from) or zone.rect.has_point(to):
				continue # firing from/into this building doesn't block itself
			if _line_crosses_rect(from, to, zone.rect):
				return false
		elif zone.type == TerrainType.HIGH_GROUND:
			if from_elevation >= zone.elevation or to_elevation >= zone.elevation:
				continue # at least one side is already up at (or above) this hill's height
			if _line_crosses_rect(from, to, zone.rect):
				return false
	return true


static func _line_crosses_rect(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	var tl := rect.position
	var tr := rect.position + Vector2(rect.size.x, 0.0)
	var br := rect.position + rect.size
	var bl := rect.position + Vector2(0.0, rect.size.y)
	return _segments_intersect(from, to, tl, tr) \
		or _segments_intersect(from, to, tr, br) \
		or _segments_intersect(from, to, br, bl) \
		or _segments_intersect(from, to, bl, tl)


static func _segments_intersect(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> bool:
	var d1 := (p4 - p3).cross(p1 - p3)
	var d2 := (p4 - p3).cross(p2 - p3)
	var d3 := (p2 - p1).cross(p3 - p1)
	var d4 := (p2 - p1).cross(p4 - p1)
	return ((d1 > 0) != (d2 > 0)) and ((d3 > 0) != (d4 > 0))


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


## A ring around a unit/token showing whether its current spot is cover —
## shown in the battle view AND on the deployment screen, so cover status is
## visible before the battle even starts.
static func draw_cover_ring(ci: CanvasItem, radius: float, terrain: TerrainType) -> void:
	var in_cover := is_in_cover(terrain)
	var color: Color = Color(0.25, 1.0, 0.35, 0.9) if in_cover else Color(1.0, 0.3, 0.2, 0.55)
	var width: float = 3.0 if in_cover else 1.5
	ci.draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU, 24, color, width, true)


## A hill needs to read as elevated at a glance, not just "vaguely tinted
## ground" — a darker halo just outside its footprint gives it a raised
## edge against the surrounding lowland, dense topographic-style contour
## rings brightening toward the summit reinforce it, and an explicit label
## removes any remaining ambiguity.
static func _draw_hill(ci: CanvasItem, rect: Rect2) -> void:
	var halo := Rect2(rect.position - Vector2(8.0, 8.0), rect.size + Vector2(16.0, 16.0))
	ci.draw_rect(halo, Color(0.32, 0.29, 0.2, 0.4))

	ci.draw_rect(rect, Color(0.68, 0.6, 0.38, 0.75))

	var ring_count := 5
	var max_inset: float = min(rect.size.x, rect.size.y) / 2.0 - 10.0
	for i in ring_count:
		var t: float = float(i + 1) / float(ring_count)
		var inset: float = max_inset * t
		var r := Rect2(rect.position + Vector2(inset, inset), rect.size - Vector2(inset * 2.0, inset * 2.0))
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			continue
		var b: float = 0.55 + 0.35 * t # brighter toward the summit
		ci.draw_rect(r, Color(b, b * 0.95, b * 0.68, 0.75), false, 2.5)

	ci.draw_string(ThemeDB.fallback_font, rect.position + Vector2(10.0, 24.0), "HIGH GROUND",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.3, 0.26, 0.14, 0.9))


static func _draw_road(ci: CanvasItem, rect: Rect2) -> void:
	ci.draw_rect(rect, Color(0.55, 0.53, 0.5))
	var y: float = rect.position.y + rect.size.y / 2.0
	var x: float = rect.position.x + 5.0
	while x < rect.position.x + rect.size.x - 10.0:
		ci.draw_line(Vector2(x, y), Vector2(x + 12.0, y), Color(0.9, 0.9, 0.8), 2.0)
		x += 24.0


## Small isolated BUILDING zones (outside the main village blob) render as a
## single low wall/ruin. The main village renders as a grid of houses,
## scaling with the zone's size — a bigger village automatically gets more
## buildings, no hand-placed list to keep in sync.
static func _draw_village(ci: CanvasItem, rect: Rect2) -> void:
	if rect.size.x <= 60.0:
		ci.draw_rect(rect, Color(0.5, 0.48, 0.45))
		ci.draw_rect(Rect2(rect.position, Vector2(rect.size.x, 5.0)), Color(0.32, 0.3, 0.28))
		return

	ci.draw_rect(rect, Color(0.65, 0.58, 0.45, 0.4))

	var cols := 3
	var rows := 4
	var margin := 12.0
	var cell_w: float = (rect.size.x - margin) / float(cols)
	var cell_h: float = (rect.size.y - margin) / float(rows)
	for row in rows:
		for col in cols:
			# Skip a few cells so the village reads as organic, not a grid.
			if (row + col) % 4 == 3:
				continue
			var b := Rect2(
				rect.position.x + margin + col * cell_w + 4.0,
				rect.position.y + margin + row * cell_h + 4.0,
				cell_w - 12.0,
				cell_h - 14.0
			)
			if b.size.x <= 0.0 or b.size.y <= 0.0:
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
