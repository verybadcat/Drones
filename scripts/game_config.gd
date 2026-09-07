extends RefCounted
class_name GameConfig
## Shared map layout: the village, terrain, deployment zones, and enemy
## approach. Kept in one place so no other script can drift out of sync.
##
## The map is a real 5km x 3.5km battlefield (see PIXELS_PER_METER). Every
## distance-like constant below is authored in METERS — the number you read
## IS the real-world distance — and only converted to the pixel space Godot
## actually draws in via a multiply by PIXELS_PER_METER, done right inline
## since that's a compile-time constant expression (no runtime conversion,
## no drift between "the real number" and "the number the engine uses").
## Speeds are the one deliberate exception: they're tuned for a battle that
## resolves in a few minutes, not literal infantry marching pace — see the
## note above the movement constants.

enum TerrainType { OPEN, TREES, BUILDING }

## The two fieldable reconnaissance/target-acquisition setups the player
## chooses between before deployment (see main.gd's level-select screen):
## SPOTTER is the original ground team calling in fire on what it can see
## from wherever it's posted; DRONE_TEAM replaces it with a small crew
## flying a rotation of scout drones — see Unit.Kind.DRONE_TEAM/DRONE and
## the drone-specific constants below.
enum ReconMode { SPOTTER, DRONE_TEAM }

## The map spans a real 5km left-to-right. The playable battle canvas is
## MAP_WIDTH_PX wide (the rest of the window, from ~1020px on, is the sidebar
## UI — see main.gd) and MAP_HEIGHT_PX tall (the full window height), which
## works out to a 5000m x 3500m battlefield.
const MAP_WIDTH_PX: float = 1000.0
const MAP_HEIGHT_PX: float = 700.0
const MAP_WIDTH_M: float = 5000.0
const PIXELS_PER_METER: float = MAP_WIDTH_PX / MAP_WIDTH_M # 0.2 px/m
const MAP_HEIGHT_M: float = MAP_HEIGHT_PX / PIXELS_PER_METER # 3500m

## Runtime meters<->pixels conversion, for the few places that need to
## convert a value that isn't known until the game is running (the mouseover
## elevation readout's cursor position, mainly). Every constant below is
## already pixel-space via compile-time "meters * PIXELS_PER_METER" — these
## are NOT needed for those.
static func px_to_m(px: float) -> float:
	return px / PIXELS_PER_METER


static func m_to_px(meters: float) -> float:
	return meters * PIXELS_PER_METER


## Terrain masking treats a unit's eye/muzzle as this high off the ground it
## is standing on.
const EYE_HEIGHT_M: float = 1.6
## An observer needs to be at least this much higher than the target (not
## just numerically greater) before elevation grants a detection bonus —
## avoids granting it over meaningless terrain noise.
const ELEVATION_ADVANTAGE_THRESHOLD_M: float = 8.0

## Rolling hills as smooth, continuous high ground rather than a flat zone —
## elevation at any point is the sum of each hill's contribution, so the
## terrain has real, continuous relief (and can be drawn as real contour
## lines — see _draw_hills). A hill isn't a plain radially-symmetric bump,
## either — each has a few "warp_harmonics" (frequency/amplitude/phase
## triples) that scale its effective radius by angle from center, so its
## footprint is an irregular, elongated blob rather than a perfect circle —
## see _hill_radius_warp. One broad hill sits behind/around the village,
## giving the defenders a genuine elevation advantage; the rest add varied,
## natural-looking relief across the whole battlefield.
const HILLS: Array[Dictionary] = [
	{"center_m": Vector2(1300.0, 1550.0), "radius_m": 650.0, "height_m": 35.0, "warp_harmonics": [
		{"frequency": 2, "amplitude": 0.18, "phase": 0.4}, {"frequency": 3, "amplitude": 0.12, "phase": 2.1},
	]}, # the village's high ground
	{"center_m": Vector2(500.0, 3200.0), "radius_m": 420.0, "height_m": 18.0, "warp_harmonics": [
		{"frequency": 2, "amplitude": 0.15, "phase": 1.0}, {"frequency": 4, "amplitude": 0.1, "phase": 0.5},
	]}, # rear rise, south
	{"center_m": Vector2(3500.0, 1950.0), "radius_m": 520.0, "height_m": 26.0, "warp_harmonics": [
		{"frequency": 3, "amplitude": 0.16, "phase": 1.8}, {"frequency": 2, "amplitude": 0.13, "phase": 3.0},
	]}, # a rise on the enemy's approach
	{"center_m": Vector2(4100.0, 700.0), "radius_m": 380.0, "height_m": 15.0, "warp_harmonics": [
		{"frequency": 2, "amplitude": 0.14, "phase": 2.5}, {"frequency": 5, "amplitude": 0.08, "phase": 1.2},
	]}, # minor rise, north
	{"center_m": Vector2(350.0, 550.0), "radius_m": 380.0, "height_m": 20.0, "warp_harmonics": [
		{"frequency": 3, "amplitude": 0.17, "phase": 0.9}, {"frequency": 2, "amplitude": 0.11, "phase": 2.7},
	]}, # ridge west of the village, rear
	{"center_m": Vector2(2400.0, 3100.0), "radius_m": 350.0, "height_m": 16.0, "warp_harmonics": [
		{"frequency": 2, "amplitude": 0.16, "phase": 1.5}, {"frequency": 4, "amplitude": 0.09, "phase": 0.3},
	]}, # rise above the southern woods
	{"center_m": Vector2(2700.0, 900.0), "radius_m": 300.0, "height_m": 14.0, "warp_harmonics": [
		{"frequency": 3, "amplitude": 0.15, "phase": 2.2}, {"frequency": 2, "amplitude": 0.12, "phase": 0.7},
	]}, # rise along the road's midpoint bend
]
const CONTOUR_INTERVAL_M: float = 10.0


## How much a blob's effective radius is stretched (>1) or pinched (<1) in
## the direction `theta` (radians from its center) — a sum of cosine
## harmonics, each blob's own fixed set giving it a distinct, irregular,
## non-circular footprint instead of a perfect circle/radial Gaussian.
## Amplitudes are kept well under 1.0 in total so this can never flip the
## effective radius negative. Shared by HILLS (see _hill_radius_warp,
## elevation_m) and FOREST_PATCHES (see _forest_radius_at) — same technique,
## two different uses of "irregular blob."
static func _radius_warp(warp_harmonics: Array, theta: float) -> float:
	var w := 1.0
	for h in warp_harmonics:
		w += h.amplitude * cos(h.frequency * theta + h.phase)
	return w


static func _hill_radius_warp(hill: Dictionary, theta: float) -> float:
	return _radius_warp(hill.warp_harmonics, theta)


## Continuous ground elevation in meters at a point (given in the engine's
## pixel space, like everything else) — the sum of every hill's (warped,
## non-circular) contribution. Never negative; flat, open ground is 0m.
static func elevation_m(pos_px: Vector2) -> float:
	var pos_m: Vector2 = pos_px / PIXELS_PER_METER
	var total := 0.0
	for hill in HILLS:
		var offset: Vector2 = pos_m - hill.center_m
		var d: float = offset.length()
		var r: float = hill.radius_m * (_hill_radius_warp(hill, offset.angle()) if d > 0.01 else 1.0)
		total += hill.height_m * exp(-(d * d) / (2.0 * r * r))
	return total


## A dirt road, not a rectangle — a real bent path from the enemy's spawn
## edge down toward the village, in meters. Both the drawn road AND the
## enemy's actual road-march waypoints (see BattleManager._spawn_enemy_units)
## come from this single list, so the two can never drift out of sync.
const ROAD_WIDTH_M: float = 7.0
const ROAD_WAYPOINTS_M: Array[Vector2] = [
	Vector2(4950.0, 1780.0),
	Vector2(4300.0, 1850.0),
	Vector2(3600.0, 1680.0),
	Vector2(2900.0, 1900.0),
	Vector2(2200.0, 1720.0),
	Vector2(1550.0, 1780.0),
]


## The road's waypoints converted to pixel space, for BattleManager to build
## the enemy's march path from directly.
static func road_waypoints_px() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for wp in ROAD_WAYPOINTS_M:
		out.append(wp * PIXELS_PER_METER)
	return out


## The drone's OWN default search pattern when it has no better lead (see
## BattleManager._drone_sweep_target) — deliberately NOT the same list as
## ROAD_WAYPOINTS_M above. That road is where enemy SQUADS march, but a
## real mortar deploys well back from the line, not draped over the march
## route (see BattleManager._pick_target's own reasoning for why the two
## get very different treatment) — sweeping only the road's own narrow
## ~200m-tall band, as the drone used to, structurally could never pass
## near a mortar sitting a few hundred meters off to either side, no
## matter how much flight time it had.
##
## A genuine 5x5 GRID (columns spaced ~850m apart across the same
## contested x-range as the road — ENEMY_SPAWN_X down to the road's own
## innermost waypoint — rows spaced 750m apart across the map's FULL
## height), visited in boustrophedon order (each row alternating
## direction) — still no more prior knowledge of the enemy's actual, fixed
## emplacements than the player has (an evenly-spaced sweep, not their
## exact coordinates), just methodical enough that DRONE_DETECTION_RANGE's
## own 1600m reach actually gets a chance at whatever's out there instead
## of depending on a lucky coincidence of where the road happens to run.
##
## Deliberately a fine grid rather than 5 long full-width rows (an earlier
## version of this pattern): a single row spanning the entire 3400m width
## meant the drone's actual in-area searching, not just getting there, was
## one long, uninterrupted dash along the enemy's own east-west axis of
## attack the whole time it was "searching" at all. With comparable
## ~750-850m leg lengths in both directions, a drone conducting a local
## search alternates between horizontal and vertical motion constantly
## instead of favoring either axis — it can still cross a good distance to
## reach a given part of the grid first (that transit is real and
## unavoidable), but once actually working an area, the search itself no
## longer prefers the attack axis over the perpendicular one.
const DRONE_SEARCH_GRID_COLUMNS_M: Array[float] = [1550.0, 2400.0, 3250.0, 4100.0, 4950.0]
const DRONE_SEARCH_GRID_ROWS_M: Array[float] = [300.0, 1050.0, 1750.0, 2450.0, 3150.0]

static func _drone_search_waypoints_m() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for row_i in DRONE_SEARCH_GRID_ROWS_M.size():
		var y: float = DRONE_SEARCH_GRID_ROWS_M[row_i]
		var columns: Array[float] = DRONE_SEARCH_GRID_COLUMNS_M.duplicate()
		if row_i % 2 == 1: # alternate direction each row — a real boustrophedon
			columns.reverse()
		for x in columns:
			out.append(Vector2(x, y))
	return out

static func drone_search_waypoints_px() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for wp in _drone_search_waypoints_m():
		out.append(wp * PIXELS_PER_METER)
	return out


## How much search effort DRONE_SEARCH_GRID_ROWS_M's 5 rows each get, from
## the map's far north edge (index 0) to its far south edge (index 4) —
## see BattleManager._weighted_random_sweep_index, used both for where a
## fresh battle's sweep starts and every subsequent re-roll once it's
## underway. Row 2 is the same y-band as the road: the single most
## operationally relevant strip, since that's where the enemy squads
## actually march and where whatever's supporting them is most likely to
## be within reach of. Weighting toward it isn't the same thing as knowing
## exact enemy coordinates — the road's existence is public knowledge, not
## secret intelligence — it just reflects that real activity concentrates
## near a known approach route rather than spreading evenly across the
## whole map. Always starting at (and endlessly cycling through) a fixed,
## uniform sequence made the sweep both identical every single game AND
## indifferent to how likely any given spot actually was; this fixes both
## at once. The two edge rows are never ruled out entirely (5% each) —
## just correctly treated as far less likely than the middle of the map.
const DRONE_SWEEP_ROW_WEIGHTS: Array[float] = [0.05, 0.15, 0.6, 0.15, 0.05]

## Once an enemy unit is confirmed no longer any kind of threat — DESTROYED,
## WITHDRAWN, or SURRENDERED, the same "not still a threat" boundary
## _known_enemy_positions itself already draws — the ground it was last
## known to occupy is genuinely known-clear, real information gained
## through play, not a static bias like the road-band weighting above (see
## BattleManager._area_confirmed_clear/_weighted_random_sweep_index). A
## sweep waypoint landing within this radius of that position is much less
## worth the trip. Sized to roughly match the grid's own leg spacing
## (~750-850m between waypoints) so "cleared" tracks an area genuinely
## comparable to one search leg, not a token few meters around the exact
## former position.
const DRONE_SWEEP_CLEARED_RADIUS_M: float = 600.0
## Not zero — a cleared area is meaningfully less worth revisiting, not
## certain to stay empty forever (a unit could in principle still pass
## through later), so this stays a strong bias, not a hard exclusion,
## matching this game's usual "real decisions aren't perfectly certain"
## idiom (see _weighted_mortar_target_pick, _weighted_advance_point_pick).
const DRONE_SWEEP_CLEARED_WEIGHT_MULTIPLIER: float = 0.15


# Each zone is a rectangle + terrain type (TREES/BUILDING only — elevation
# is now the continuous heightmap above, and the road is its own waypoint
# path, not a zone; see draw_terrain). Order matters for drawing: earlier =
# painted first (underneath).
#
# The village is a small, real settlement — a handful of buildings, not a
# quarter of the map — plus a scatter of natural-looking woodland and a
# couple of isolated outlying farm buildings, positioned organically rather
# than in tidy rows.
#
# The village's own center, in meters — matches TERRAIN_ZONES[0] below.
# Named explicitly (not derived from the zone array) so anything that needs
# "the objective" — like an enemy squad resuming its advance after breaking
# for cover — doesn't depend on zone ordering.
const VILLAGE_CENTER: Vector2 = Vector2(1400.0 * PIXELS_PER_METER, 1750.0 * PIXELS_PER_METER)

const TERRAIN_ZONES: Array[Dictionary] = [
	{"rect": Rect2(1175.0 * PIXELS_PER_METER, 1560.0 * PIXELS_PER_METER, 450.0 * PIXELS_PER_METER, 380.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING}, # the village
	{"rect": Rect2(2380.0 * PIXELS_PER_METER, 1580.0 * PIXELS_PER_METER, 55.0 * PIXELS_PER_METER, 46.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING}, # isolated farmhouse, mid-approach
	{"rect": Rect2(880.0 * PIXELS_PER_METER, 2480.0 * PIXELS_PER_METER, 60.0 * PIXELS_PER_METER, 50.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING}, # isolated farmhouse, rear
]

## Forested areas, as irregular blobs rather than rectangles — same technique
## as HILLS (see _radius_warp): each patch's actual footprint at any angle
## `theta` from its `center_m` is `radius_m * _radius_warp(warp_harmonics,
## theta)`, so real woodland has ragged, elongated, natural-looking edges
## instead of a boxy outline (see _forest_radius_at / _point_in_forest_patch,
## and _draw_forest_patch for the matching filled-polygon rendering). A real
## forest doesn't come in one size either, so patches range from small
## copses to substantial woods.
const FOREST_PATCHES: Array[Dictionary] = [
	{"center_m": Vector2(1080.0, 1335.0), "radius_m": 145.0, "warp_harmonics": [
		{"frequency": 2, "amplitude": 0.2, "phase": 0.6}, {"frequency": 3, "amplitude": 0.12, "phase": 2.4},
	]}, # wooded slope, village hill NW — kept clear of the village's own BUILDING zone (nearest corner ~244m away)
	{"center_m": Vector2(1690.0, 1370.0), "radius_m": 125.0, "warp_harmonics": [
		{"frequency": 3, "amplitude": 0.16, "phase": 1.1}, {"frequency": 2, "amplitude": 0.14, "phase": 3.4},
	]}, # wooded slope, village hill NE — kept clear of the village's own BUILDING zone (nearest corner ~201m away)
	{"center_m": Vector2(3070.0, 1545.0), "radius_m": 175.0, "warp_harmonics": [
		{"frequency": 2, "amplitude": 0.18, "phase": 2.0}, {"frequency": 4, "amplitude": 0.1, "phase": 0.8},
	]}, # copse along the approach
	{"center_m": Vector2(3930.0, 2300.0), "radius_m": 220.0, "warp_harmonics": [
		{"frequency": 3, "amplitude": 0.17, "phase": 0.3}, {"frequency": 2, "amplitude": 0.15, "phase": 2.9},
	]}, # woods on the enemy-side rise
	{"center_m": Vector2(2310.0, 2880.0), "radius_m": 230.0, "warp_harmonics": [
		{"frequency": 2, "amplitude": 0.19, "phase": 1.4}, {"frequency": 3, "amplitude": 0.11, "phase": 3.6},
	]}, # southern woods, off the road
	{"center_m": Vector2(645.0, 2230.0), "radius_m": 145.0, "warp_harmonics": [
		{"frequency": 3, "amplitude": 0.15, "phase": 2.6}, {"frequency": 2, "amplitude": 0.13, "phase": 0.5},
	]}, # copse near the rear
	{"center_m": Vector2(4265.0, 945.0), "radius_m": 175.0, "warp_harmonics": [
		{"frequency": 2, "amplitude": 0.16, "phase": 0.9}, {"frequency": 4, "amplitude": 0.09, "phase": 2.2},
	]}, # woods near the northern rise
	{"center_m": Vector2(2805.0, 635.0), "radius_m": 160.0, "warp_harmonics": [
		{"frequency": 3, "amplitude": 0.14, "phase": 1.7}, {"frequency": 2, "amplitude": 0.12, "phase": 3.1},
	]}, # copse, north side
	{"center_m": Vector2(240.0, 825.0), "radius_m": 140.0, "warp_harmonics": [
		{"frequency": 2, "amplitude": 0.17, "phase": 2.8}, {"frequency": 3, "amplitude": 0.1, "phase": 0.4},
	]}, # slope below the western ridge
	{"center_m": Vector2(2600.0, 735.0), "radius_m": 155.0, "warp_harmonics": [
		{"frequency": 4, "amplitude": 0.1, "phase": 1.3}, {"frequency": 2, "amplitude": 0.15, "phase": 3.5},
	]}, # woods above the road bend
	{"center_m": Vector2(1910.0, 2490.0), "radius_m": 165.0, "warp_harmonics": [
		{"frequency": 3, "amplitude": 0.16, "phase": 0.2}, {"frequency": 2, "amplitude": 0.13, "phase": 2.5},
	]}, # copse south of the village
	{"center_m": Vector2(4030.0, 3105.0), "radius_m": 195.0, "warp_harmonics": [
		{"frequency": 2, "amplitude": 0.18, "phase": 1.9}, {"frequency": 3, "amplitude": 0.12, "phase": 3.8},
	]}, # woods, far southeast
	{"center_m": Vector2(1095.0, 475.0), "radius_m": 145.0, "warp_harmonics": [
		{"frequency": 3, "amplitude": 0.15, "phase": 3.0}, {"frequency": 2, "amplitude": 0.11, "phase": 0.7},
	]}, # copse, north of the village
	{"center_m": Vector2(4505.0, 1885.0), "radius_m": 160.0, "warp_harmonics": [
		{"frequency": 2, "amplitude": 0.14, "phase": 0.1}, {"frequency": 4, "amplitude": 0.09, "phase": 2.3},
	]}, # woods near the enemy's rear
	{"center_m": Vector2(685.0, 1670.0), "radius_m": 130.0, "warp_harmonics": [
		{"frequency": 3, "amplitude": 0.13, "phase": 1.6}, {"frequency": 2, "amplitude": 0.16, "phase": 3.3},
	]}, # copse, west-central
	{"center_m": Vector2(3315.0, 2595.0), "radius_m": 180.0, "warp_harmonics": [
		{"frequency": 2, "amplitude": 0.17, "phase": 2.1}, {"frequency": 3, "amplitude": 0.1, "phase": 0.6},
	]}, # woods on the approach rise's south slope
	{"center_m": Vector2(2000.0, 1020.0), "radius_m": 170.0, "warp_harmonics": [
		{"frequency": 3, "amplitude": 0.15, "phase": 0.5}, {"frequency": 2, "amplitude": 0.12, "phase": 2.7},
	]}, # north-central woods
	{"center_m": Vector2(3300.0, 3200.0), "radius_m": 200.0, "warp_harmonics": [
		{"frequency": 2, "amplitude": 0.19, "phase": 1.2}, {"frequency": 4, "amplitude": 0.09, "phase": 3.2},
	]}, # deep southeast forest
	{"center_m": Vector2(700.0, 3300.0), "radius_m": 160.0, "warp_harmonics": [
		{"frequency": 3, "amplitude": 0.14, "phase": 2.4}, {"frequency": 2, "amplitude": 0.13, "phase": 0.3},
	]}, # far south rear woods
	{"center_m": Vector2(4700.0, 2600.0), "radius_m": 180.0, "warp_harmonics": [
		{"frequency": 2, "amplitude": 0.16, "phase": 3.0}, {"frequency": 3, "amplitude": 0.11, "phase": 1.0},
	]}, # far east edge woods, enemy side
	{"center_m": Vector2(1200.0, 3100.0), "radius_m": 150.0, "warp_harmonics": [
		{"frequency": 4, "amplitude": 0.09, "phase": 0.8}, {"frequency": 2, "amplitude": 0.15, "phase": 2.2},
	]}, # south of the rear farmhouse
	{"center_m": Vector2(3900.0, 1020.0), "radius_m": 170.0, "warp_harmonics": [
		{"frequency": 3, "amplitude": 0.16, "phase": 1.5}, {"frequency": 2, "amplitude": 0.12, "phase": 3.4},
	]}, # north woods, enemy approach
	{"center_m": Vector2(2500.0, 2200.0), "radius_m": 155.0, "warp_harmonics": [
		{"frequency": 2, "amplitude": 0.15, "phase": 2.9}, {"frequency": 3, "amplitude": 0.1, "phase": 0.9},
	]}, # central woods between road and southern woods
	{"center_m": Vector2(600.0, 1020.0), "radius_m": 145.0, "warp_harmonics": [
		{"frequency": 3, "amplitude": 0.13, "phase": 0.4}, {"frequency": 2, "amplitude": 0.14, "phase": 2.6},
	]}, # northwest quadrant woods
	{"center_m": Vector2(4600.0, 500.0), "radius_m": 165.0, "warp_harmonics": [
		{"frequency": 2, "amplitude": 0.18, "phase": 1.8}, {"frequency": 4, "amplitude": 0.08, "phase": 3.7},
	]}, # far northeast corner
	{"center_m": Vector2(1700.0, 3300.0), "radius_m": 155.0, "warp_harmonics": [
		{"frequency": 3, "amplitude": 0.15, "phase": 2.3}, {"frequency": 2, "amplitude": 0.11, "phase": 0.2},
	]}, # south rear woods
	{"center_m": Vector2(3600.0, 700.0), "radius_m": 145.0, "warp_harmonics": [
		{"frequency": 2, "amplitude": 0.14, "phase": 3.1}, {"frequency": 3, "amplitude": 0.1, "phase": 1.1},
	]}, # north woods near enemy path
	{"center_m": Vector2(200.0, 2700.0), "radius_m": 155.0, "warp_harmonics": [
		{"frequency": 4, "amplitude": 0.09, "phase": 1.9}, {"frequency": 2, "amplitude": 0.16, "phase": 0.1},
	]}, # far west rear woods
	{"center_m": Vector2(4200.0, 3200.0), "radius_m": 170.0, "warp_harmonics": [
		{"frequency": 3, "amplitude": 0.12, "phase": 0.7}, {"frequency": 2, "amplitude": 0.15, "phase": 2.8},
	]}, # far southeast corner
	{"center_m": Vector2(2900.0, 350.0), "radius_m": 150.0, "warp_harmonics": [
		{"frequency": 2, "amplitude": 0.17, "phase": 2.5}, {"frequency": 3, "amplitude": 0.11, "phase": 0.6},
	]}, # far north strip
]

# Legal area for the player to drag squads into — wider than just the
# village: the defense can post squads forward in ambush/blocking positions
# or held back in reserve, not only inside the village itself. Spans most
# of the western half of the map, through and a good way past the village.
const PLAYER_DEPLOYMENT_ZONE: Rect2 = Rect2(400.0 * PIXELS_PER_METER, 100.0 * PIXELS_PER_METER, 2600.0 * PIXELS_PER_METER, 3300.0 * PIXELS_PER_METER)

# The mortar gets its own, much larger deployment zone spanning from the
# western map edge through and a bit past the village — real mortars sit
# well back from the line, and there's real playable depth behind the
# village for one to use now that the map is a real 5km across.
const PLAYER_MORTAR_DEPLOYMENT_ZONE: Rect2 = Rect2(50.0 * PIXELS_PER_METER, 80.0 * PIXELS_PER_METER, 2150.0 * PIXELS_PER_METER, 3350.0 * PIXELS_PER_METER)

# Whichever reconnaissance asset the player is fielding this battle (see
# ReconMode) can deploy just about anywhere on the map — it's not a firing
# position, and unlike squads/mortar isn't restricted to the village. Kept a
# small margin off the outer edges only so it can't be dropped literally
# off-map. Shared by both the artillery spotter and the drone team's ground
# station: the deployment CHOICE they represent (where to post your recon
# asset) is the same regardless of which one it physically is.
const PLAYER_SPOTTER_DEPLOYMENT_ZONE: Rect2 = Rect2(50.0 * PIXELS_PER_METER, 50.0 * PIXELS_PER_METER, 4900.0 * PIXELS_PER_METER, 3400.0 * PIXELS_PER_METER)
const PLAYER_SPOTTER_DEFAULT_POSITION: Vector2 = Vector2(1900.0 * PIXELS_PER_METER, 1750.0 * PIXELS_PER_METER)

# Default starting token positions on the deployment screen, before the
# player drags them anywhere else within their zone.
const PLAYER_DEFAULT_POSITIONS: Array[Vector2] = [
	Vector2(1280.0 * PIXELS_PER_METER, 1670.0 * PIXELS_PER_METER),
	Vector2(1480.0 * PIXELS_PER_METER, 1750.0 * PIXELS_PER_METER),
	Vector2(1300.0 * PIXELS_PER_METER, 1860.0 * PIXELS_PER_METER),
]
# Below the village's BUILDING footprint and clear of the tree zones — a
# mortar can never be set up inside a building or dragged into one.
const PLAYER_MORTAR_DEFAULT_POSITION: Vector2 = Vector2(1400.0 * PIXELS_PER_METER, 2050.0 * PIXELS_PER_METER)

# Enemy squads start at the map's eastern edge, march down the winding road
# (ROAD_WAYPOINTS_M above) in a loose spread rather than single file, then
# break off toward cover once they take fire. The enemy's two mortars deploy
# at fixed rear positions and never advance.
const ENEMY_SPAWN_X: float = 4950.0 * PIXELS_PER_METER
# Perpendicular-ish spread off the road's line, per squad — six squads
# advancing near, not literally on top of, each other and the road.
const ENEMY_SQUAD_Y_OFFSETS_M: Array[float] = [-420.0, -250.0, -80.0, 80.0, 250.0, 420.0]
const ENEMY_MORTAR_POSITIONS_M: Array[Vector2] = [Vector2(4700.0, 1300.0), Vector2(4700.0, 2500.0)]

# The tactical clock runs faster than the actual time you spend watching —
# without this, a battle at real distances/speeds would take the better
# part of an hour to play out (see the speeds and MORTAR_FLIGHT_TIME below,
# all genuinely realistic now). Three tiers, picked each tick by
# BattleManager._current_time_scale() — fastest whenever there's nothing
# worth watching closely, realistic-paced the moment there is:
#   - TIME_SCALE_FAST_FORWARD: no live contact at all (nobody on either side
#     currently sees an enemy) — covers both the long road march before
#     first contact AND a single unit's own isolated retreat with nobody
#     else around; neither needs realistic-time watching.
#   - TIME_SCALE_GENERAL_RETREAT: no live contact, but a GENERAL withdrawal
#     is under way for either side (BattleManager.order_general_retreat, or
#     the enemy commander's own equivalent — see
#     _check_enemy_commander_retreat) — the battle's effectively decided,
#     just not literally over yet. Exactly double TIME_SCALE_NORMAL: the
#     same "nothing left to watch closely" withdrawal sequence as always,
#     just shown twice as fast.
#   - TIME_SCALE_NORMAL: live contact — 1 real (engine) second = 1 tactical
#     MINUTE. This is the "realistic and worth watching" pace, and always
#     wins over the general-retreat tier — a fighting withdrawal (some
#     units still retreating, but contact remains elsewhere) is still worth
#     watching closely, same as before this tier's speed was doubled.
# See BattleManager.scenario_elapsed_time.
const TIME_SCALE_FAST_FORWARD: float = 300.0
const TIME_SCALE_NORMAL: float = 60.0
const TIME_SCALE_GENERAL_RETREAT: float = TIME_SCALE_NORMAL * 2.0
# The tactical clock shown to the player (see BattleManager.clock_string())
# starts here — the assault kicks off at 0600.
const SCENARIO_START_HOUR: float = 6.0

# Movement speeds are genuine real-world pace now (meters per TACTICAL
# second — see TIME_SCALE_NORMAL above for why that's still snappy to
# actually watch): a steady infantry march, a hastened but not panicked
# withdrawal, and a brisk dash for cover, respectively.
const ENEMY_ADVANCE_SPEED: float = 1.4 * PIXELS_PER_METER
const ENEMY_RETREAT_SPEED: float = 2.2 * PIXELS_PER_METER
# A single squad's OWN casualty threshold — bottom-up, that one unit's own
# losses only. See ENEMY_COMMANDER_RETREAT_THRESHOLD below for the
# top-down, whole-force version the enemy commander judges by instead.
const ENEMY_RETREAT_THRESHOLD: float = 0.5
const ENEMY_CONCERN_THRESHOLD: float = 0.25 # logs "reports the issue", doesn't retreat

# The enemy commander orders a full withdrawal (BattleManager.
# _check_enemy_commander_retreat) once the attack AS A WHOLE looks
# hopeless — judged against total casualties across every enemy squad and
# mortar, not any single unit's own threshold. Set higher than a single
# squad's own ENEMY_RETREAT_THRESHOLD (0.5): a commander keeps pressing the
# attack with individual squads falling back here and there, and only
# calls it off once losses are heavy across the whole force.
const ENEMY_COMMANDER_RETREAT_THRESHOLD: float = 0.4

# When the enemy commander's general retreat order reaches a given squad
# (see BattleManager._squad_surrender_chance), that squad doesn't
# automatically attempt the retreat — a squad in a genuinely poor position
# for it might reasonably decide surrender is the safer bet, and might
# just as reasonably decide to try its luck anyway; either way it's a
# random roll, not a fixed rule.
#
# MULTIPLICATIVE, not additive — isolation on its own, with no enemy
# actually close, is not a reason to surrender (nobody gives up just
# because their friends are elsewhere; the original additive version let
# isolation alone contribute a real chance even with the enemy nowhere
# near, which is exactly what let a squad 600m out, with a clear line
# home, surrender — that shouldn't happen). Isolation instead AMPLIFIES
# genuine proximate danger: SURRENDER_ISOLATION_BASE_FACTOR is the
# multiplier even with an ally right there, rising to
# SURRENDER_ISOLATION_BASE_FACTOR + SURRENDER_ISOLATION_AMPLIFIER (1.0)
# when fully alone — "surrounded," not just "isolated," is what actually
# pushes a squad over the edge.
#
# SURRENDER_POSITION_RANGE is deliberately tight — 300m, not the 1200m a
# squad's own ADVANCING danger score (SQUAD_DANGER_RANGE) uses for a very
# different question. This is close-quarters/no-realistic-way-out
# territory: ~100m out still reads as genuinely dangerous (badness ~0.67),
# but by 300m it's already zero, and anything beyond that (600m, with room
# to actually retreat) contributes nothing from this term at all,
# regardless of isolation, since the two factors multiply rather than add.
#
# The result is capped at SURRENDER_MAX_CHANCE — deliberately well short
# of certainty even in the single worst case (point-blank AND surrounded)
# a squad might still choose to run for it.
const SURRENDER_POSITION_RANGE: float = 300.0 * PIXELS_PER_METER
const SURRENDER_ISOLATION_RANGE: float = 1000.0 * PIXELS_PER_METER
const SURRENDER_ISOLATION_BASE_FACTOR: float = 0.3
const SURRENDER_ISOLATION_AMPLIFIER: float = 0.7
const SURRENDER_MAX_CHANCE: float = 0.6

# Applied on top of the position/isolation math above, per side, before
# the shared SURRENDER_MAX_CHANCE cap (see BattleManager.
# _squad_surrender_chance) — deliberately NOT the same value for both
# sides. This game's setting is the Russian invasion of Ukraine;
# credible, extensively documented reporting (UN and Human Rights Watch
# monitoring among it) describes systematic mistreatment of Ukrainian
# POWs in Russian custody. A Ukrainian squad in a hopeless position has
# real, well-founded reasons the enemy simply doesn't share to keep
# fighting or trying to get out rather than lay down arms, so the
# player's own side surrenders far less readily than the same
# position/isolation math would otherwise predict.
const SURRENDER_WILLINGNESS_MULTIPLIER_PLAYER: float = 0.15
const SURRENDER_WILLINGNESS_MULTIPLIER_ENEMY: float = 1.0

# A RETREATING unit that reaches its own safe_x is marked WITHDRAWN — no
# longer part of the fight, but its casualties still count in the AAR.
const ENEMY_SAFE_X: float = ENEMY_SPAWN_X + 150.0 * PIXELS_PER_METER
const PLAYER_RETREAT_SPEED: float = 2.0 * PIXELS_PER_METER
const PLAYER_SAFE_X: float = 60.0 * PIXELS_PER_METER

# How much slack a cover zone gets on the "wrong" side of a retreating
# unit's current position before it's excluded as a detour toward the
# front — see nearest_cover_point/safest_cover_point's retreat_dir param.
const RETREAT_DIRECTION_TOLERANCE: float = 100.0 * PIXELS_PER_METER

# Tactical seconds (see TIME_SCALE_NORMAL) — ends the battle if reached.
# Real infantry engagements can run for hours; the road march alone eats
# ~2500 tactical seconds (42 min) before contact is even possible, and a
# realistic-paced firefight — punctuated by units breaking for cover at a
# realistic pace too, not instantly re-engaging — needs real room after
# that to actually develop and resolve, not just time out early with both
# sides barely scratched. 4 tactical hours, worst case, still caps actual
# watching time at BATTLE_TIME_LIMIT / TIME_SCALE_NORMAL (240 real seconds).
const BATTLE_TIME_LIMIT: float = 14400.0

# Spotting.
const DETECTION_BASE_RANGE: float = 900.0 * PIXELS_PER_METER
const DETECTION_ELEVATION_BONUS: float = 500.0 * PIXELS_PER_METER # added when spotter is higher than target
const SPOT_CHANCE_PER_SECOND: float = 0.15
const MOVING_SPOT_MULTIPLIER: float = 3.0

# The artillery spotter: a small, fragile, unarmed recon team whose job is
# purely to extend detection for the mortar. Better trained to spot at range
# than a rifle squad is. Concealment is two very different stories depending
# on whether it's actually using cover: hidden in trees/a building, the
# enemy effectively cannot find it beyond point-blank range — "unless they
# get very close." Standing in the open, it's found close to normally (just
# a small trained-to-minimize-exposure edge).
const SPOTTER_DETECTION_RANGE_BONUS: float = 500.0 * PIXELS_PER_METER # added to its own spotting rolls
const SPOTTER_HIDDEN_DETECTION_RANGE: float = 250.0 * PIXELS_PER_METER # replaces detection range entirely when in cover
const SPOTTER_EXPOSED_CONCEALMENT_MULTIPLIER: float = 0.8 # applies only when NOT in cover

# The drone team (ReconMode.DRONE_TEAM): a 3-person ground crew (ground-side
# stats mirror the mortar's crew model — see Unit.Kind.DRONE_TEAM/
# _apply_crew_casualties) operating a rotation of DRONE_FLEET_SIZE small
# quadcopter scouts. Real numbers, not abstractions: a Mavic-class
# airframe's actual specs are what actually force the rotation, not a
# made-up "cooldown."
#
# Exactly one drone is airborne at a time; a second sits ready to launch
# the instant the flying one needs replacing — either because it's been
# shot down (unplanned — see BattleManager._on_drone_state_changed) or
# because it's hit its flight-time/range budget and is returning to base
# (planned — the standby launches immediately, not after the old one
# physically lands, so there's no coverage gap on a routine swap; see
# BattleManager._update_drone_operations).
#
# Airframes and batteries are tracked SEPARATELY, because they recover at
# wildly different speeds: the team also carries DRONE_SPARE_BATTERIES
# charged spare batteries (DRONE_FLEET_SIZE + DRONE_SPARE_BATTERIES = 8
# batteries total for only 4 airframes), and "batteries are easily
# swappable" — a landed airframe gets whichever's the best-charged battery
# currently on hand after just DRONE_BATTERY_SWAP_DURATION (a real
# battery-swap-and-inspection, a few minutes), not the full ~100-minute
# DRONE_RECHARGE_DURATION a spent battery actually needs to reach 100%.
#
# What's actually tracked, both airborne (Unit.drone_battery_charge) and on
# the ground (BattleManager._battery_pool/_drones_ready), is each
# battery's real CHARGE LEVEL (0.0-1.0), not a fixed recharge duration —
# recharge time is a CONSEQUENCE of how depleted a battery happens to be
# when it comes off an airframe, not something separately counted down.
# With 8 batteries for 4 airframes, at least DRONE_SPARE_BATTERIES worth
# are mathematically always sitting uninstalled, so a landed airframe is
# never left with literally nothing to swap in — but with heavy use, "best
# available" can still mean a partial charge, not a full one: the team
# launches on whatever it actually has, same as the real thing would.
const DRONE_FLEET_SIZE: int = 4
const DRONE_SPARE_BATTERIES: int = 4
const DRONE_TEAM_CREW_SIZE: int = 3
const DRONE_ALTITUDE_M: float = 300.0
# DJI's own published Mavic 3 specs, not a guess: 46-minute max flight time
# (rated), and a 30km max flight distance rated for a sustained 50.4 kph
# cruise (both figures are DJI's own lab numbers, not battlefield-derated —
# see the design doc's revision log for sourcing). DRONE_CRUISE_SPEED uses
# that exact 50.4kph, the speed DJI's own range figure was measured at, so
# the two aren't silently mismatched: sustained flight at this speed covers
# the full 30km around the 35-36 minute mark — genuinely a bit before the
# separately-rated 46-minute figure (that rating reflects the lowest-power
# hover condition, not continuous directional flight, so this gap is real,
# not a modeling error). On this map (a 5-6km diagonal) neither number is
# normally tight; a sortie generally ends on whichever of the two a
# particular flight path happens to use up first.
const DRONE_CRUISE_SPEED: float = 14.0 * PIXELS_PER_METER # 50.4 km/h — DJI's own tested speed for the range figure below
const DRONE_MAX_FLIGHT_TIME: float = 46.0 * 60.0 # tactical seconds — DJI's rated Mavic 3 max flight time, cited for realism
const DRONE_ROUND_TRIP_RANGE: float = 30000.0 * PIXELS_PER_METER # DJI's rated Mavic 3 max flight distance
# What a battery's charge level ACTUALLY tracks against, in flight-time
# terms: the range-derived figure, not the separately-rated
# DRONE_MAX_FLIGHT_TIME above. The drone always moves at a fixed
# DRONE_CRUISE_SPEED, so time and distance are always directly
# proportional — a single depletion rate has to be picked, and the range
# figure is the one that's actually self-consistent with that constant
# speed (see the comment above DRONE_MAX_FLIGHT_TIME for why the two DJI
# figures don't quite agree in the first place).
const DRONE_FULL_CHARGE_FLIGHT_TIME: float = DRONE_ROUND_TRIP_RANGE / DRONE_CRUISE_SPEED # ~35.7 minutes
const DRONE_RTB_SAFETY_MARGIN: float = 300.0 * PIXELS_PER_METER # turn for home this much charge-equivalent before the battery is actually flat

# Getting to DRONE_ALTITUDE_M (or back down from it) isn't free — DJI's own
# rated Normal-mode ascent/descent speeds, applied as a real time-and-charge
# cost the cruise-only model above would otherwise skip entirely. Not
# modeled as an extra movement phase (the drone doesn't go anywhere
# horizontally while climbing/descending straight up or down over a fixed
# point, so there's nothing for the existing move system to actually
# simulate) — instead a one-time charge deduction, converted through the
# same charge-per-second rate as everything else here
# (DRONE_FULL_CHARGE_FLIGHT_TIME), applied once at launch
# (BattleManager._launch_drone/_launch_backup_drone) and once at an actual
# landing (_update_returning_drones) — never at a shoot-down or a
# battery-dry sacrifice crash, since neither of those ever actually lands.
# Small in absolute terms (~50s each way against a ~35.7-minute full
# charge, call it ~4.5% of a sortie's total endurance round-trip) but a
# genuine gap the pure cruise-speed model left on the table.
const DRONE_ASCENT_SPEED_MPS: float = 6.0 # DJI-rated Normal-mode ascent speed (real m/s — a time calc, not a move_speed, so no PIXELS_PER_METER here)
const DRONE_DESCENT_SPEED_MPS: float = 6.0 # DJI-rated Normal-mode descent speed
const DRONE_CLIMB_TIME: float = DRONE_ALTITUDE_M / DRONE_ASCENT_SPEED_MPS # ~50 tactical seconds
const DRONE_DESCENT_TIME: float = DRONE_ALTITUDE_M / DRONE_DESCENT_SPEED_MPS # ~50 tactical seconds
const DRONE_LAUNCH_CHARGE_COST: float = DRONE_CLIMB_TIME / DRONE_FULL_CHARGE_FLIGHT_TIME
const DRONE_LANDING_CHARGE_COST: float = DRONE_DESCENT_TIME / DRONE_FULL_CHARGE_FLIGHT_TIME
# DJI's own published Mavic 3 charging spec: 1h36m (96 minutes) from empty
# on the standard 65W charger — this is what a SPENT battery actually needs
# before it's usable again, regardless of how quickly its airframe got back
# in the air on a different (spare) battery. (A fast 100W charger/hub can do
# it in ~70-80 minutes instead, but that's not assumed here — treat this as
# the more conservative field case.)
const DRONE_RECHARGE_DURATION: float = 100.0 * 60.0 # tactical seconds

# The actual "easily swappable" part: popping out a spent battery, clipping
# in a charged spare, and a quick power-on/GPS-lock check before the
# airframe is trusted back in the air. Real and quick — this, not the full
# recharge above, is normally what limits how fast a landed airframe
# returns to service, as long as a charged spare is available.
const DRONE_BATTERY_SWAP_DURATION: float = 4.0 * 60.0 # tactical seconds

# A ground unit noticing a small quadcopter loitering ~DRONE_ALTITUDE_M
# overhead, on unaided eyes/ears alone, is a fundamentally different (and
# far rarer) event than spotting anyone on the ground — see
# CombatResolver._roll_ground_notices_drone, which uses these two directly
# rather than running a drone target through the normal terrain-concealment/
# elevation/movement spotting formula (none of that describes "is anyone
# glancing at the right patch of sky right now").
#
# Sourced from real drone-detection research rather than guessed: a
# dedicated visual-detection study (Ahn et al., "Distance and Visual Angle
# of Line-of-Sight of a Small Drone," Applied Sciences 2020) found only a
# 50% chance of visually acquiring a Mavic-class airframe at ~307m, and
# that's for an observer ACTIVELY SCANNING for it under good conditions —
# unaided HEARING did worse still in the same study: most participants
# couldn't hear the drone even once they could already see it. A mortar or
# squad isn't scanning the sky at all — they're loading, laying, watching
# the ground for threats — so what this models is an occasional, distracted
# glance happening to catch something, not a deliberate search. That's why
# DRONE_GROUND_NOTICE_CHANCE_PER_MINUTE sits roughly two orders of magnitude
# below the study's best-case per-look figure, expressed directly as a
# chance PER MINUTE (an occasional glance is naturally a per-minute event,
# not a per-second one) — low enough that even several minutes spent
# hovering over the same crew still usually goes unnoticed, same as real
# reconnaissance-drone experience suggests. DRONE_GROUND_NOTICE_MAX_RANGE_M
# is a hard real-world cutoff past the same study's own effective range —
# beyond it, naked-eye/ear detection of something this small is noise, not
# signal, no matter how long it lingers.
const DRONE_GROUND_NOTICE_CHANCE_PER_MINUTE: float = 0.01
const DRONE_GROUND_NOTICE_MAX_RANGE_M: float = 400.0

# From 300m up, camera resolution and a small, quiet airframe make a drone
# hard to actually hit with small arms even once someone IS looking right at
# it. It doesn't stand on any terrain in a meaningful sense, so (unlike the
# notice roll above) this still applies uniformly regardless of terrain.
const DRONE_HIT_CHANCE_MULTIPLIER: float = 0.1

# The drone's own view is a genuinely different (better) sensor, not just a
# bigger number bolted onto the spotter's: a wider detection range, and —
# because it's looking mostly straight down rather than across open ground —
# concealment that works at ground level (a treeline breaking up a rifle
# squad's sightline, a building's wall blocking a ground observer) is much
# less effective against it. A solid roof still fully hides what's under it
# from directly overhead, though, so BUILDING stays real cover — more
# effective against the drone than TREES is, the reverse of the ground-level
# table (see CombatResolver.CONCEALMENT_MULTIPLIER).
const DRONE_DETECTION_RANGE: float = 1600.0 * PIXELS_PER_METER
const DRONE_CONCEALMENT_MULTIPLIER := {
	TerrainType.OPEN: 1.0,
	TerrainType.TREES: 0.8,
	TerrainType.BUILDING: 0.5,
}

# A spotted enemy squad rarely travels alone — a real reconnaissance asset
# that's just made contact works the surrounding ground for more of them
# (and whatever might be supporting them) instead of just parking directly
# overhead the one unit it already has eyes on. See BattleManager.
# _drone_vicinity_search_point, which the squad-tracking priority tier
# (_drone_search_target) uses instead of the squad's own exact position —
# a slow circle at this radius, comfortably inside DRONE_DETECTION_RANGE so
# the original contact never actually drops out of view while the drone
# works the area around it. Re-centers on the current highest-priority
# visible squad every tick, so the circle follows if that squad moves (or
# hands off cleanly to a different one that becomes more dangerous).
const DRONE_VICINITY_SEARCH_RADIUS: float = 600.0 * PIXELS_PER_METER
const DRONE_VICINITY_SEARCH_ARRIVAL_RADIUS: float = 150.0 * PIXELS_PER_METER
# Not a clean fraction of 360 on purpose — a step that evenly divided the
# circle would eventually retrace the exact same handful of points forever;
# this keeps sweeping fresh ground around the contact instead.
const DRONE_VICINITY_SEARCH_ANGLE_STEP_DEG: float = 70.0

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
# (see below).
const SQUAD_ENGAGEMENT_RANGE: float = 400.0 * PIXELS_PER_METER

# A mortar fires indirectly on spotter-relayed information — no LOS
# requirement of its own, and firing does not automatically reveal one to
# enemy squads the way a rifle's muzzle flash does. But it is NOT unlimited
# range: a real light/medium mortar tops out well short of the whole map.
const MORTAR_MAX_RANGE: float = 3500.0 * PIXELS_PER_METER

# The drone's own TARGET PRIORITY scoring (see BattleManager.
# _drone_search_target/_squad_danger_priority/_mortar_existence_
# confidence) — a general "how urgent is this to watch" scale, not
# hard-coded "if it's a mortar" branching, so a future third target kind
# only needs its own priority term added here, not a rewrite of the
# decision logic itself. A confirmed mortar (seen live, or a fresh,
# specific fire-detection lead) sits far above anything a squad can ever
# reach — real mortars are simply the bigger threat — while a squad's own
# priority is genuinely variable, scaling with how close it's gotten to
# any friendly unit (SQUAD_DANGER_RANGE: beyond it, a squad isn't yet a
# real threat and scores 0; within it, danger ramps up to
# TARGET_PRIORITY_SQUAD_MAX right at contact). A live-visible mortar
# always wins outright; a bare fire-detection lead (real evidence, but a
# stale position estimate rather than a live one) is discounted somewhat
# but still normally beats any squad.
const TARGET_PRIORITY_MORTAR: float = 100.0
const TARGET_PRIORITY_MORTAR_LEAD_DISCOUNT: float = 0.8
const TARGET_PRIORITY_SQUAD_MAX: float = 10.0
const SQUAD_DANGER_RANGE: float = 1200.0 * PIXELS_PER_METER

# How a MORTAR weighs which non-mortar candidate to actually fire on — see
# BattleManager._mortar_target_value/_pick_target's own doc comment. Equal
# weights on purpose: casualty potential (a target's own current pips,
# capped at 9) and danger (_squad_danger_priority, capped at
# TARGET_PRIORITY_SQUAD_MAX = 10) already land on comparable scales by
# construction, so 1.0/1.0 already balances "a fuller unit is a juicier
# target" against "a dangerous unit is worth hitting even if it's already
# been worn down" without either one dominating outright.
const MORTAR_TARGET_CASUALTY_WEIGHT: float = 1.0
const MORTAR_TARGET_DANGER_WEIGHT: float = 1.0

# A safety valve on the mortar/drone team's shared commitment to hunting
# one specific enemy mortar together (see BattleManager.
# _update_joint_mortar_hunt) — a generous ceiling, not a normal expiry.
# MORTAR_RELOCATE_SPEED is a walking pace, so closing even a middling gap
# can legitimately take a while; this only exists to eventually let go of
# a commitment that's stopped making sense (geography blocking every
# route, the target having effectively gone to ground) rather than
# holding onto it forever.
const JOINT_MORTAR_HUNT_MAX_DURATION: float = 1800.0 # tactical seconds (30 min)

# A visible RETREATING enemy (squad or mortar crew — a mortar crew that's
# abandoned its gun can never fire it again, so it counts as "retreating,"
# not "the mortar priority," the instant that happens) is worth two very
# different things depending on whether the battle is still actually going
# on. Once the enemy commander has ordered a general retreat — the fight
# is effectively over, just not literally finished — it's a kill already
# in progress and worth finishing: TARGET_PRIORITY_RETREATING_ENEMY, well
# above an advancing squad's own max and second only to an actual live
# mortar. But while the battle is STILL CONTINUING (no general retreat —
# other real threats, especially an active mortar, could still be out
# there), one broken, defanged unit already running away is a distraction,
# not a priority: TARGET_PRIORITY_RETREATING_ENEMY_LOW instead, low enough
# to lose to the sweep or any genuinely dangerous advancing squad, so the
# drone stays on the actual fight instead of babysitting one straggler.
# Both flat rather than distance-scaled like TARGET_PRIORITY_SQUAD_MAX —
# the question here is "is it worth finishing off right now," not "how
# close is it to a fight."
const TARGET_PRIORITY_RETREATING_ENEMY: float = 25.0
const TARGET_PRIORITY_RETREATING_ENEMY_LOW: float = 2.0

# Once the enemy commander has ordered a general retreat, there's little
# reason left to keep sweeping wide for a NEW enemy — every ACTIVE squad
# was just pulled into RETREATING in that same instant (see BattleManager.
# _check_enemy_commander_retreat), so the "fresh squad might be arriving"
# half of the sweep's value is simply gone, and even the standing worry
# about an undiscovered mortar is heavily discounted here: a mortar that's
# actually still covering the withdrawal will show up live or via a fresh
# fire-detection lead and win outright regardless of this discount (see
# BattleManager._drone_search_target's tiers 1/2) — this only affects the
# speculative "nothing detected yet, but maybe" component of the sweep,
# which should now lose to a real, already-broken kill in progress
# (TARGET_PRIORITY_RETREATING_ENEMY) rather than keep competing with it.
const SWEEP_DISCOUNT_DURING_ENEMY_RETREAT: float = 0.2

# How much the drone team should still bother sweeping wide for an
# as-yet-undiscovered enemy mortar, expressed as a genuine expected value:
# TARGET_PRIORITY_MORTAR (what finding one would be worth) times this
# confidence (the estimated odds one is actually still out there to find).
# Early in the battle a mortar may simply not have had a target yet, or be
# holding fire waiting for one — confidence starts high (see the decay
# function's own t=0 behavior) — but the longer real tactical time passes
# with NO mortar fire detected anywhere (_last_detected_mortar_fire, which
# already covers a mortar never even spotted, via muzzle-flash/trajectory
# detection), the less plausible a live one remains, and confidence decays
# on this real time constant toward MORTAR_CONFIDENCE_FLOOR (never quite
# zero while at least one enemy mortar is genuinely still ACTIVE somewhere
# — see _mortar_existence_confidence for the one case that DOES go to a
# hard, certain zero: every enemy mortar confirmed out of action). This is
# what lets the drone naturally shift its default search effort toward
# tracking real, dangerous squads instead of an indefinite mortar-shaped
# sweep once mortars stop looking like a live concern — exactly the
# "increasingly confident there are no mortars to look for" behavior asked
# for, without hard-coding "if both mortars are dead" anywhere.
const MORTAR_CONFIDENCE_DECAY_TAU: float = 900.0 # tactical seconds (15 tactical minutes)
const MORTAR_CONFIDENCE_FLOOR: float = 0.05

# A mortar shell doesn't land the instant it's fired — 40 tactical seconds
# of real flight time (see BattleManager._launch_mortar_shot /
# _resolve_pending_mortar_shots). It's aimed at the target's ANTICIPATED
# position, not a live one — if the target moves more than this far from
# that anticipated spot by the time the shell arrives, the round lands on
# empty ground: an outright miss, no roll needed. Roughly a mortar's
# effective burst radius — close enough and it's still in the beaten zone.
const MORTAR_FLIGHT_TIME: float = 40.0 # tactical seconds
const MORTAR_EVASION_RADIUS: float = 40.0 * PIXELS_PER_METER

# It can still be picked up by the opposing mortar's counter-battery (see
# CombatResolver / BattleManager).
const MORTAR_COUNTER_BATTERY_HOLD_CHANCE: float = 0.22 # per shot, holding position
const MORTAR_COUNTER_BATTERY_SCOOT_CHANCE: float = 0.06 # per shot, shoot-and-scoot

# How long a mortar's firing position stays "worth pursuing" for counter-
# battery-range-chasing purposes after being detected (see BattleManager.
# _launch_mortar_shot / _known_friendly_mortar_position) — real counter-
# battery detection is via the outgoing round's muzzle blast/trajectory,
# not visual spotting, so this doesn't require the mortar to stay visually
# exposed. Tactical seconds; roughly the upper end of the counter-battery
# response window (COUNTER_BATTERY_DELAY_MAX) — old enough and the mortar
# has almost certainly moved on, not worth chasing a stale fix.
const MORTAR_FIRE_DETECTION_EXPIRY: float = 180.0

# The drone's OWN use of the same muzzle-flash/trajectory detection (see
# BattleManager._known_enemy_mortar_fire_position) needs a much longer
# window than the enemy's quick ground-based counter-battery reaction
# above: it can be anywhere on the map when the shot fires and has to
# physically fly there at DRONE_CRUISE_SPEED before the lead is any good to
# it, unlike a mortar reacting from nearby. ~10 minutes covers a flight
# across most of the map's real diagonal at that speed.
const DRONE_MORTAR_FIRE_LEAD_EXPIRY: float = 600.0

# The friendly mortar's OWN willingness to relocate toward a KNOWN enemy
# mortar that's currently out of range — see BattleManager.
# _known_enemy_mortar_lead / _update_friendly_mortar_hunting. A live-visible
# mortar, or one a friendly drone is already en route to cover, is trusted
# enough to be worth chasing at real distance and given the same generous
# DRONE_MORTAR_FIRE_LEAD_EXPIRY window above; a bare, uncovered fire-
# detection lead gets the enemy's own quick MORTAR_FIRE_DETECTION_EXPIRY
# window instead (it's no more likely to still be good than the enemy's
# own equivalent read on the friendly mortar), and even within that window
# is only worth a modest repositioning, not abandoning good cover for a
# long march on a guess.
const MORTAR_HUNT_UNTRUSTED_MAX_RELOCATE: float = 1000.0 * PIXELS_PER_METER

# An ABSOLUTE ceiling on the friendly mortar's own hunting, independent of
# how good the intel is — see BattleManager._friendly_mortar_home_position
# / _update_joint_mortar_hunt / _update_friendly_mortar_hunting. Hunting a
# known enemy mortar is good, but a real crew still won't range
# indefinitely far from wherever they were actually set up just because a
# drone reports a trusted fix — this caps how far a hunt's DESTINATION may
# end up from that deployment position, regardless of trust level, and
# regardless of whether any enemy squads are known to be nearby (that's
# a SEPARATE concern, already handled by _friendly_mortar_hunt_point's own
# concealment-seeking — this is about distance from home, full stop, not
# about avoiding specific known threats along the way). Set to half
# MORTAR_MAX_RANGE — enough real room to reposition meaningfully for a
# shot, not half the map.
const MORTAR_HUNT_MAX_RANGE_FROM_HOME: float = MORTAR_MAX_RANGE * 0.5

# A relocating mortar crew actually walks there — real speed, real distance,
# real time, no separate "cooldown" bolted on top (see BattleManager.
# _relocate_mortar). MORTAR_RELOCATE_SPEED is a hustling pace, faster than
# ordinary REPOSITION_SPEED — displacing a tube under at least the
# THEORETICAL threat of counter-battery is more urgent than a routine
# reposition. If the crew has actually taken counter-battery fire recently
# (Unit.evading_counter_battery), it moves at ..._URGENT instead and, via
# nearest_hidden_point's own urgent search rings, goes farther too — a
# crew that's been found moves fast AND puts real distance behind it, not
# just one or the other. Moving into trees is slower than open ground —
# hauling a tube and base plate through undergrowth is real work.
const MORTAR_RELOCATE_SPEED: float = 2.2 * PIXELS_PER_METER
const MORTAR_RELOCATE_SPEED_URGENT: float = 2.6 * PIXELS_PER_METER
const MORTAR_RELOCATE_TREES_MULTIPLIER: float = 0.8

# Counter-battery fire isn't instant: the enemy can only aim at where the
# mortar WAS when it fired, and it takes real time to organize and fire a
# response — a random 1-3 tactical minutes, not a fixed interval (see
# BattleManager._resolve_mortar_counter_battery). By the time it lands, a
# shoot-and-scoot mortar has likely moved well clear; a hold-position
# mortar is still standing right there. If the mortar is still within the
# blast radius when the shell lands, it can still get hit — the odds just
# fall off with distance from the original firing spot.
const COUNTER_BATTERY_DELAY_MIN: float = 60.0 # tactical seconds
const COUNTER_BATTERY_DELAY_MAX: float = 180.0 # tactical seconds
const COUNTER_BATTERY_BLAST_RADIUS: float = 150.0 * PIXELS_PER_METER # beyond this, the old position is safe

# A squad hit by mortar fire may bolt for nearby cover regardless of overall
# casualties — mortar fire is disruptive even when it doesn't kill outright.
const RELOCATE_ON_MORTAR_HIT_CHANCE: float = 0.35

# A mortar round's fragmentation covers an area, not one aimed person —
# see Unit.take_hit's own from_mortar branch, and BattleManager.
# _mortar_target_value, which is why a fuller unit is also a more
# attractive target in the first place. 20% of a unit's CURRENT strength,
# rounded, floored at 1 (a "hit" that costs nothing would read as a
# non-event) and never more than what's actually there to lose. A full
# 9-person squad loses 2 per hit (round(9*0.2)=2); anything at 6 or below
# is back to losing 1, same as the old flat model — the scaling only
# really shows up while a unit is still close to full strength.
const MORTAR_CASUALTY_FRACTION: float = 0.2

static func mortar_casualty_count(current_pips: int) -> int:
	return clampi(int(round(float(current_pips) * MORTAR_CASUALTY_FRACTION)), 1, current_pips)

# Every pip a SQUAD actually loses (see Unit._categorize_casualties) is
# sorted into killed / heavily wounded (immobile — needs carrying, see
# Unit._resolve_wounded_evacuation) / walking wounded (mobile, no retreat
# cost) by independent weighted rolls. Fractions must sum to 1.0; walking
# wounded is deliberately left as "whatever's left" below rather than its
# own named constant, so the three can never drift out of sync. First-pass
# estimates, not validated against actual play — see doctrine doc.
const CASUALTY_KILLED_FRACTION: float = 0.3
const CASUALTY_HEAVILY_WOUNDED_FRACTION: float = 0.35
# (walking wounded = 1.0 - CASUALTY_KILLED_FRACTION - CASUALTY_HEAVILY_WOUNDED_FRACTION = 0.35)

# How much slower a retreat is per HEAVILY_WOUNDED person actually carried
# along (see Unit._resolve_wounded_evacuation) — a real cost for "we want to
# take the wounded with us," not just flavor. Floored so even a badly mauled
# squad carrying several still makes SOME progress rather than effectively
# stopping.
const HEAVILY_WOUNDED_SLOWDOWN_PER_PERSON: float = 0.12
const HEAVILY_WOUNDED_MIN_RETREAT_SPEED_FRACTION: float = 0.4

# The enemy-only choice to leave heavily wounded behind instead of carrying
# them (see Unit._resolve_wounded_evacuation) — a genuine risk-weighted roll,
# not a hard cutoff. DANGER_RANGE mirrors the scale of DANGER_RADIUS/
# SQUAD_DANGER_RANGE elsewhere: inside it, a known threat reads as
# realistically able to catch a slowed column; beyond it, carrying wounded
# is essentially free. CHANCE_PER_PERSON scales with how many are actually
# being carried (a bigger encumbrance is a bigger risk to accept), capped at
# MAX_CHANCE so even a large, close threat doesn't make abandonment an
# absolute certainty.
const WOUNDED_ABANDON_DANGER_RANGE: float = 600.0 * PIXELS_PER_METER
const WOUNDED_ABANDON_CHANCE_PER_PERSON: float = 0.25
const WOUNDED_ABANDON_MAX_CHANCE: float = 0.85

# Squads bunched up this close together (e.g. piled into the same patch of
# cover) risk a stray hit spreading from whichever of them was actually
# targeted — real militaries avoid bunching up for exactly this reason. See
# BattleManager._resolve_fire_and_check_bunching / _bunched_ally.
const BUNCHING_RADIUS: float = 30.0 * PIXELS_PER_METER
const BUNCHING_SPILLOVER_CHANCE: float = 0.25
const REPOSITION_SPEED: float = 1.8 * PIXELS_PER_METER # m/s (tactical), for any non-retreat repositioning

# A retreating unit under actual mortar fire (Unit.zigzagging) juke
# sideways rather than run a clean straight line — real evasive broken-
# field running. Direction re-rolled every JINK interval (randomized within
# this range, not a clean predictable period — a mortar that figured out a
# steady rhythm could lead it right back) at a fraction of the unit's own
# retreat speed, so it still makes real forward progress while dodging.
const ZIGZAG_LATERAL_SPEED_FRACTION: float = 0.6
const ZIGZAG_JINK_MIN_INTERVAL: float = 6.0 # tactical seconds
const ZIGZAG_JINK_MAX_INTERVAL: float = 12.0 # tactical seconds

# How far an enemy squad advances per rush once it resumes closing on the
# village after breaking for cover (see BattleManager._update_enemy_squad_advance)
# — a bounded leg, not a single sprint to the objective, so it still pauses
# to reassess (and fire, if something's now in range) between rushes rather
# than covering the whole remaining distance blind.
const ENEMY_ADVANCE_RUSH_DISTANCE: float = 400.0 * PIXELS_PER_METER

## _next_advance_point's candidate directions, in degrees off the straight
## line to the objective — spread both ways so a squad can bend its rush
## left or right, whichever side actually offers cover or breaks a known
## contact's line of sight; 0.0 keeps the literal straight-line rush in the
## pool too, since "usually avoid the open" isn't "never." Capped at a
## moderate angle (not 90+) so every candidate still makes real net progress
## toward the objective — bending the approach, not sidestepping in place.
const ENEMY_ADVANCE_ANGLES_DEG: Array[float] = [-50.0, -25.0, 0.0, 25.0, 50.0]

## Advance-candidate scoring — see BattleManager._score_advance_candidate.
## COVER rewards a candidate that actually lands in TREES/BUILDING terrain,
## a standing "use the terrain" preference that applies whether or not any
## enemy contact is currently known. CONCEALMENT additionally rewards a
## candidate that every currently-known player position is unable to
## directly see — this is what makes bending wide toward one side actually
## pay off as a real flanking move once there's a spotted friendly to route
## around, rather than costing distance for nothing. ANGLE_PENALTY_PER_DEG
## makes a bigger bend cost more, so a detour has to actually be worth it
## rather than every rush wandering aimlessly; BASE_WEIGHT keeps the literal
## straight-line-through-the-open candidate meaningfully reachable (never
## zero), so a direct dash across open ground still happens sometimes — just
## not usually.
const ENEMY_ADVANCE_COVER_BONUS: float = 3.0
const ENEMY_ADVANCE_CONCEALMENT_BONUS: float = 2.0
const ENEMY_ADVANCE_ANGLE_PENALTY_PER_DEG: float = 0.03
const ENEMY_ADVANCE_BASE_WEIGHT: float = 1.0


## A FOREST_PATCH's actual footprint radius at angle `theta` (radians) from
## its own center — see _radius_warp.
static func _forest_radius_at(patch: Dictionary, theta: float) -> float:
	return patch.radius_m * _radius_warp(patch.warp_harmonics, theta)


## True if a center-relative offset (in METERS) falls within a forest
## patch's irregular footprint — shared by the point-in-world check below
## and the deterministic tree-scatter placement in _draw_forest_patch, so
## what's drawn always matches what actually counts as TREES.
static func _forest_patch_contains_offset_m(patch: Dictionary, offset_m: Vector2) -> bool:
	var d: float = offset_m.length()
	if d < 0.01:
		return true
	return d <= _forest_radius_at(patch, offset_m.angle())


static func _point_in_forest_patch(patch: Dictionary, pos_px: Vector2) -> bool:
	return _forest_patch_contains_offset_m(patch, pos_px / PIXELS_PER_METER - patch.center_m)


## Upper bound on a patch's own radius warp, for sizing a bounding box around
## it (see _draw_forest_patch) — not exact (different harmonics peak at
## different angles, so this can't all be reached at once), just a safe "big
## enough" bound, since overshooting merely means scanning a bit more empty
## area, not a distortion of the shape's own math.
static func _forest_patch_max_warp(patch: Dictionary) -> float:
	var w := 1.0
	for h in patch.warp_harmonics:
		w += h.amplitude
	return w


## Concealment/cover terrain type at a point. BUILDING beats TREES if both
## overlap a point.
static func get_terrain_type_at(pos: Vector2) -> TerrainType:
	for zone in TERRAIN_ZONES:
		if zone.type == TerrainType.BUILDING and zone.rect.has_point(pos):
			return TerrainType.BUILDING
	for patch in FOREST_PATCHES:
		if _point_in_forest_patch(patch, pos):
			return TerrainType.TREES
	return TerrainType.OPEN


static func is_in_cover(terrain: TerrainType) -> bool:
	return terrain == TerrainType.BUILDING or terrain == TerrainType.TREES


## A mortar can't be fired from inside a building (no overhead clearance for
## the round's arc) and is never allowed to set up or take cover inside one
## — see BattleManager._tick_fire, DeploymentScreen, and the avoid_buildings
## param on the cover-point functions below.
static func is_building_at(pos: Vector2) -> bool:
	return get_terrain_type_at(pos) == TerrainType.BUILDING


## True if the straight segment from `from` to `to` passes through any
## BUILDING zone along the way — not just whether either END is inside one.
## A mortar can't be walked straight through a house wall to reach an
## otherwise-legal destination on the far side of it; see avoid_buildings on
## the cover-point functions below and BattleManager._relocate_mortar.
static func path_crosses_building(from: Vector2, to: Vector2) -> bool:
	for zone in TERRAIN_ZONES:
		if zone.type != TerrainType.BUILDING:
			continue
		if _line_crosses_rect(from, to, zone.rect):
			return true
	return false


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
##
## `avoid_positions` (typically other same-team units' current/planned
## positions) excludes any zone that already contains one of them, IF at
## least one zone still qualifies without it — real squads spread out
## across different patches of cover rather than piling into the same one,
## which also puts all of them at risk from a single burst or shell landing
## there (see BattleManager's bunching-spillover mechanic). Falls back to
## the normal (unrestricted) candidate set if avoiding them would leave
## nowhere to go — some cover, even shared, beats none.
##
## `known_enemy_positions` HARD-excludes any zone within DANGER_RADIUS of
## one, same graceful-fallback rule — a unit fleeing for cover should never
## be routed toward, or right next to, an enemy it already knows about, on
## top of retreat_dir's "never detour toward the front" rule above (that
## one only checks x-direction; this one is a real distance check against
## actual known positions, so together they rule out heading toward, or
## landing next to, a specific enemy the unit knows is there).
const DANGER_RADIUS: float = 250.0 * PIXELS_PER_METER

## Every BUILDING zone and FOREST_PATCH, unified into one "cover zone" shape
## so the search functions below can treat a rectangular building and an
## irregular forest blob identically: a center point, "does this contain
## point p" (_cover_zone_contains), and "a random point inside it"
## (_random_point_in_cover_zone), each dispatched on `zone.type`.
static func _all_cover_zones() -> Array[Dictionary]:
	var zones: Array[Dictionary] = []
	for zone in TERRAIN_ZONES:
		if zone.type != TerrainType.BUILDING:
			continue
		zones.append({"type": TerrainType.BUILDING, "rect": zone.rect, "center": zone.rect.position + zone.rect.size / 2.0})
	for patch in FOREST_PATCHES:
		zones.append({"type": TerrainType.TREES, "patch": patch, "center": patch.center_m * PIXELS_PER_METER})
	return zones


static func _cover_zone_contains(zone: Dictionary, p: Vector2) -> bool:
	if zone.type == TerrainType.BUILDING:
		return zone.rect.has_point(p)
	return _point_in_forest_patch(zone.patch, p)


## A random point solidly inside the zone — for a BUILDING, uniform within
## an inset rect (same as before); for a forest patch, a random angle and a
## radius pulled in well short of the blob's own edge, so the point always
## lands inside the irregular shape without needing rejection sampling.
static func _random_point_in_cover_zone(zone: Dictionary) -> Vector2:
	if zone.type == TerrainType.BUILDING:
		var rect: Rect2 = zone.rect
		var margin: float = min(rect.size.x, rect.size.y) * 0.15
		var w: float = max(rect.size.x - margin * 2.0, 1.0)
		var h: float = max(rect.size.y - margin * 2.0, 1.0)
		return rect.position + Vector2(margin, margin) + Vector2(randf() * w, randf() * h)
	var patch: Dictionary = zone.patch
	var theta: float = randf() * TAU
	var r_m: float = _forest_radius_at(patch, theta) * randf_range(0.15, 0.7)
	return patch.center_m * PIXELS_PER_METER + Vector2(cos(theta), sin(theta)) * r_m * PIXELS_PER_METER


static func nearest_cover_point(from: Vector2, retreat_dir: float = 0.0, avoid_buildings: bool = false, avoid_positions: Array[Vector2] = [], known_enemy_positions: Array[Vector2] = []) -> Vector2:
	var candidates: Array[Dictionary] = []
	for zone in _all_cover_zones():
		if avoid_buildings and zone.type == TerrainType.BUILDING:
			continue
		var center: Vector2 = zone.center
		if retreat_dir != 0.0 and (center.x - from.x) * retreat_dir < -RETREAT_DIRECTION_TOLERANCE:
			continue
		if avoid_buildings and path_crosses_building(from, center):
			continue # can't walk/hop straight through a building to get here either
		candidates.append({"zone": zone, "dist": from.distance_to(center)})
	if candidates.is_empty():
		return from

	candidates = _exclude_dangerous(candidates, known_enemy_positions)

	if not avoid_positions.is_empty():
		var unclaimed: Array[Dictionary] = []
		for c in candidates:
			var claimed := false
			for p in avoid_positions:
				if _cover_zone_contains(c.zone, p):
					claimed = true
					break
			if not claimed:
				unclaimed.append(c)
		if not unclaimed.is_empty():
			candidates = unclaimed

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
	return _random_point_in_cover_zone(candidates[chosen_index].zone)


## Drops any candidate within DANGER_RADIUS of a known enemy position, as
## long as at least one candidate survives — falls back to the full set
## otherwise (some cover, even dangerously close cover, beats none). Shared
## by nearest_cover_point and safest_cover_point so both give the same hard
## "never toward a known threat" guarantee.
static func _exclude_dangerous(candidates: Array[Dictionary], known_enemy_positions: Array[Vector2]) -> Array[Dictionary]:
	if known_enemy_positions.is_empty():
		return candidates
	var safe: Array[Dictionary] = []
	for c in candidates:
		var center: Vector2 = c.zone.center
		var too_close := false
		for ep in known_enemy_positions:
			if center.distance_to(ep) < DANGER_RADIUS:
				too_close = true
				break
		if not too_close:
			safe.append(c)
	return safe if not safe.is_empty() else candidates


## A cover point picked with some awareness of where the enemy actually is —
## used for the spotter's retreat, which can afford to be choosier than a
## squad bolting on instinct. First applies the same hard DANGER_RADIUS
## exclusion as nearest_cover_point, then — among whatever's left — narrows
## to the nearest few cover zones (so it doesn't trek across the map for a
## marginal safety gain) and picks whichever of THOSE is farthest from the
## nearest currently-known enemy position. With no known enemies, behaves
## like nearest_cover_point.
##
## `retreat_dir` / `avoid_buildings` — see nearest_cover_point.
static func safest_cover_point(from: Vector2, known_enemy_positions: Array[Vector2], retreat_dir: float = 0.0, avoid_buildings: bool = false) -> Vector2:
	if known_enemy_positions.is_empty():
		return nearest_cover_point(from, retreat_dir, avoid_buildings)

	var candidates: Array[Dictionary] = []
	for zone in _all_cover_zones():
		if avoid_buildings and zone.type == TerrainType.BUILDING:
			continue
		var center: Vector2 = zone.center
		if retreat_dir != 0.0 and (center.x - from.x) * retreat_dir < -RETREAT_DIRECTION_TOLERANCE:
			continue
		if avoid_buildings and path_crosses_building(from, center):
			continue # can't walk/hop straight through a building to get here either
		candidates.append({"zone": zone, "dist_from_self": from.distance_to(center)})
	if candidates.is_empty():
		return from

	candidates = _exclude_dangerous(candidates, known_enemy_positions)
	for c in candidates:
		var center: Vector2 = c.zone.center
		var nearest_enemy_dist: float = INF
		for ep in known_enemy_positions:
			nearest_enemy_dist = min(nearest_enemy_dist, center.distance_to(ep))
		c["safety"] = nearest_enemy_dist

	candidates.sort_custom(func(a, b): return a.dist_from_self < b.dist_from_self)
	var pool_size: int = min(4, candidates.size())
	var pool := candidates.slice(0, pool_size)
	pool.sort_custom(func(a, b): return a.safety > b.safety) # safest (farthest from known enemies) first
	return _random_point_in_cover_zone(pool[0].zone)


# How far out (and in how many steps) to search for a concealed spot — see
# nearest_hidden_point. Three expanding rings, nearest checked first, so a
# mortar prefers a short hop to cover over a long trek if both work. The
# URGENT set (a crew that's actually taken counter-battery fire recently —
# see Unit.evading_counter_battery) searches noticeably farther out: real
# distance from a position that's been found, not just the usual shuffle.
const CONCEALMENT_SEARCH_RINGS_M: Array[float] = [250.0, 450.0, 650.0]
const CONCEALMENT_SEARCH_RINGS_URGENT_M: Array[float] = [450.0, 700.0, 1000.0]
const CONCEALMENT_SEARCH_SAMPLES: int = 16

# How far (at most) it's worth walking to reach an actual hill's reverse
# slope rather than settling for a closer, weaker spot — see
# _reverse_slope_candidate. Generous, since real cover (a whole hill
# blocking LOS, not a random point that merely tests clear right now) is
# worth a real walk.
const REVERSE_SLOPE_MAX_TRAVEL_M: float = 1500.0

## A nearby point with NO direct line of sight from ANY of `threat_positions`
## — true concealment (like the reverse slope of a hill, or behind a
## building), not just the reduced spot-chance TREES/BUILDING give as
## "cover." Tries the reverse slope of an actual nearby hill FIRST (see
## _reverse_slope_candidate) — genuine high-ground masking that stays valid
## even if the threat shifts around somewhat, not just a point that happens
## to test clear this instant — falling back to sampling a ring around
## `from` at increasing radii if no hill qualifies, returning the first
## sampled point that's fully hidden from every threat (and, if
## `avoid_buildings`, isn't inside one or reachable only by cutting through
## one). Falls back to `from` (no move) if there's nothing to hide from yet
## or nothing qualifies at all. `urgent` searches farther out
## (CONCEALMENT_SEARCH_RINGS_URGENT_M) — see Unit.evading_counter_battery.
static func nearest_hidden_point(from: Vector2, threat_positions: Array[Vector2], avoid_buildings: bool = false, urgent: bool = false) -> Vector2:
	if threat_positions.is_empty():
		return from

	var hill_spot := _reverse_slope_candidate(from, threat_positions, avoid_buildings)
	if hill_spot != from:
		return hill_spot

	var rings: Array[float] = CONCEALMENT_SEARCH_RINGS_URGENT_M if urgent else CONCEALMENT_SEARCH_RINGS_M
	for radius_m in rings:
		var radius_px: float = radius_m * PIXELS_PER_METER
		for i in CONCEALMENT_SEARCH_SAMPLES:
			var theta: float = TAU * float(i) / float(CONCEALMENT_SEARCH_SAMPLES)
			var candidate: Vector2 = from + Vector2(cos(theta), sin(theta)) * radius_px
			if avoid_buildings and (is_building_at(candidate) or path_crosses_building(from, candidate)):
				continue
			var hidden := true
			for threat in threat_positions:
				if has_direct_los(candidate, threat):
					hidden = false
					break
			if hidden:
				return candidate
	return from


## The reverse slope of whichever nearby HILL (within REVERSE_SLOPE_MAX_TRAVEL_M)
## gives the closest genuinely-hidden spot: a point on the far side of the
## hill's own center from the threats, at 75% of its radius (solidly down
## the masked slope, not right on the crest). Real elevation-based masking
## like this tends to stay valid even if a threat shifts position somewhat
## — the whole hill is still in the way — unlike a point chosen only
## because it happens to test clear against today's exact threat positions.
## Returns `from` (no better option this way) if no hill qualifies.
static func _reverse_slope_candidate(from: Vector2, threat_positions: Array[Vector2], avoid_buildings: bool) -> Vector2:
	var avg_threat := Vector2.ZERO
	for t in threat_positions:
		avg_threat += t
	avg_threat /= threat_positions.size()

	var best := from
	var best_dist := INF
	for hill in HILLS:
		var center_px: Vector2 = hill.center_m * PIXELS_PER_METER
		var away: Vector2 = center_px - avg_threat
		if away.length() < 1.0:
			continue
		var candidate: Vector2 = center_px + away.normalized() * (hill.radius_m * PIXELS_PER_METER * 0.75)
		var d: float = from.distance_to(candidate)
		if d >= best_dist or d > REVERSE_SLOPE_MAX_TRAVEL_M * PIXELS_PER_METER:
			continue
		if avoid_buildings and (is_building_at(candidate) or path_crosses_building(from, candidate)):
			continue
		var hidden := true
		for t in threat_positions:
			if has_direct_los(candidate, t):
				hidden = false
				break
		if not hidden:
			continue
		best = candidate
		best_dist = d
	return best


## True if a straight line from `from` to `to` is clear — used for both
## direct (squad) fire and spotting; mortars ignore this entirely (indirect,
## spotter-relayed fire). Two kinds of masking block it outright, not just
## "harder to hit/spot" (that's what cover/concealment are for):
##
## - A BUILDING that is neither endpoint's own position — some third
##   building sits between attacker and target. Trees do NOT block LOS
##   outright — they only affect cover/concealment.
## - The actual ground profile between the two points: with real, continuous
##   elevation (see elevation_m/HILLS), a hillside genuinely can block sight
##   between two points on opposite sides of it. Sampled along the line and
##   compared against the straight sightline between each end's eye height
##   (EYE_HEIGHT_M) — standing on a hill (or anywhere at least as high) lets
##   you see over/down its own slope just fine, in either direction; two
##   points in the lowland on opposite sides of a hill genuinely cannot see
##   each other.
const LOS_SAMPLE_COUNT: int = 20
const LOS_TERRAIN_TOLERANCE_M: float = 2.0 # slack so a sample dead-level with the sightline doesn't falsely block

static func has_direct_los(from: Vector2, to: Vector2) -> bool:
	for zone in TERRAIN_ZONES:
		if zone.type != TerrainType.BUILDING:
			continue
		if zone.rect.has_point(from) or zone.rect.has_point(to):
			continue # firing from/into this building doesn't block itself
		if _line_crosses_rect(from, to, zone.rect):
			return false

	var from_eye: float = elevation_m(from) + EYE_HEIGHT_M
	var to_eye: float = elevation_m(to) + EYE_HEIGHT_M
	for i in range(1, LOS_SAMPLE_COUNT):
		var t: float = float(i) / float(LOS_SAMPLE_COUNT)
		var sample_pos: Vector2 = from.lerp(to, t)
		var sightline_height: float = lerp(from_eye, to_eye, t)
		if elevation_m(sample_pos) > sightline_height + LOS_TERRAIN_TOLERANCE_M:
			return false
	return true


## The same BUILDING-blocking rule as has_direct_los, but with NO ground-
## elevation masking at all — a drone loitering at DRONE_ALTITUDE_M (300m)
## is well above every hill on this map (the tallest is 35m), so terrain
## that would block a ground-level sightline simply doesn't block a look
## straight down from up there. A solid roof still hides what's directly
## under it, though — that's a real obstruction regardless of viewing
## angle — so BUILDING blocking is kept exactly as-is.
static func has_aerial_los(from: Vector2, to: Vector2) -> bool:
	for zone in TERRAIN_ZONES:
		if zone.type != TerrainType.BUILDING:
			continue
		if zone.rect.has_point(from) or zone.rect.has_point(to):
			continue
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
	_draw_hills(ci)
	_draw_road(ci)
	for zone in TERRAIN_ZONES:
		if zone.type == TerrainType.BUILDING:
			_draw_village(ci, zone.rect)
	for patch in FOREST_PATCHES:
		_draw_forest_patch(ci, patch)


## A ring around a unit/token showing whether its current spot is cover —
## shown in the battle view AND on the deployment screen, so cover status is
## visible before the battle even starts.
static func draw_cover_ring(ci: CanvasItem, radius: float, terrain: TerrainType) -> void:
	var in_cover := is_in_cover(terrain)
	var color: Color = Color(0.25, 1.0, 0.35, 0.9) if in_cover else Color(1.0, 0.3, 0.2, 0.55)
	var width: float = 3.0 if in_cover else 1.5
	ci.draw_arc(Vector2.ZERO, radius + 5.0, 0.0, TAU, 24, color, width, true)


## Real, believable contour lines, not perfect circles: each hill's isoline
## at a given level is traced as a closed polygon whose radius at every
## angle is warped by _hill_radius_warp — the exact isoline of the same
## warped-Gaussian formula elevation_m uses, so what's drawn always matches
## what actually blocks line of sight. Brightens toward the summit, with
## the peak height labeled.
## Real contour lines of the ACTUAL combined elevation field (elevation_m —
## the sum of every hill's contribution at a point), traced via marching
## squares over a sampled grid, not each hill's own isolated Gaussian drawn
## independently. The old approach drew every hill's own isoline in
## isolation; wherever two hills' footprints came close enough to overlap
## (e.g. the village hill and the ridge west of it), their separately-drawn
## rings could visually cross each other — genuinely impossible for real
## contour lines, which by definition can never cross (a point has exactly
## one elevation). Gameplay (elevation_m, has_direct_los) was never affected
## by this — only the drawing was — but the drawing should still show the
## same field it's claiming to.
##
## Terrain never changes at runtime, so the whole grid + traced segments are
## computed once (cached in _contour_segments_cache) and just replayed every
## frame after that, not re-traced per draw call.
const CONTOUR_GRID_STEP_M: float = 40.0
static var _contour_segments_cache: Array[Dictionary] = [] # [{"level": float, "a": Vector2, "b": Vector2}] in px
static var _contour_cache_built: bool = false


static func _draw_hills(ci: CanvasItem) -> void:
	for hill in HILLS:
		var center_px: Vector2 = hill.center_m * PIXELS_PER_METER
		var halo_radius_px: float = hill.radius_m * 1.4 * PIXELS_PER_METER
		ci.draw_circle(center_px, halo_radius_px, Color(0.32, 0.29, 0.2, 0.12))

	_build_contour_cache()
	var max_height := 0.0
	for hill in HILLS:
		max_height = max(max_height, hill.height_m)
	for seg in _contour_segments_cache:
		var t: float = seg.level / max_height
		var b: float = 0.5 + 0.35 * t # brighter toward the highest terrain
		ci.draw_line(seg.a, seg.b, Color(b, b * 0.95, b * 0.68, 0.8), 1.5)

	for hill in HILLS:
		var center_px: Vector2 = hill.center_m * PIXELS_PER_METER
		ci.draw_string(ThemeDB.fallback_font, center_px + Vector2(-14.0, -4.0), "%dm" % int(hill.height_m),
			HORIZONTAL_ALIGNMENT_CENTER, 60, 12, Color(0.35, 0.3, 0.16, 0.9))


static func _build_contour_cache() -> void:
	if _contour_cache_built:
		return
	_contour_cache_built = true

	var cols: int = int(MAP_WIDTH_M / CONTOUR_GRID_STEP_M) + 2
	var rows: int = int(MAP_HEIGHT_M / CONTOUR_GRID_STEP_M) + 2
	var grid: Array[PackedFloat32Array] = []
	for row in rows:
		var line := PackedFloat32Array()
		line.resize(cols)
		for col in cols:
			var pos_m := Vector2(col, row) * CONTOUR_GRID_STEP_M
			line[col] = elevation_m(pos_m * PIXELS_PER_METER)
		grid.append(line)

	var max_height := 0.0
	for hill in HILLS:
		max_height = max(max_height, hill.height_m)

	var level := CONTOUR_INTERVAL_M
	while level < max_height:
		for row in rows - 1:
			for col in cols - 1:
				_marching_squares_cell(grid, row, col, level)
		level += CONTOUR_INTERVAL_M


## One cell of the standard marching-squares algorithm: 4 corners (TL, TR,
## BR, BL — matching the grid's row/col layout), a 4-bit case from which
## corners are above `level`, and a fixed table of which of the cell's 4
## (interpolated) edge crossings to connect for each case. Cases 0 and 15
## (fully below/above) have no crossing. Cases 5 and 10 are the classic
## "saddle" ambiguity (opposite corners above, the other two below) — two
## segments either way; which diagonal resolution is picked doesn't matter
## for how this looks (correct real contour maps have the exact same
## textbook ambiguity at true saddle points).
static func _marching_squares_cell(grid: Array[PackedFloat32Array], row: int, col: int, level: float) -> void:
	var v_tl: float = grid[row][col]
	var v_tr: float = grid[row][col + 1]
	var v_br: float = grid[row + 1][col + 1]
	var v_bl: float = grid[row + 1][col]

	var case_index := 0
	if v_tl > level: case_index |= 1
	if v_tr > level: case_index |= 2
	if v_br > level: case_index |= 4
	if v_bl > level: case_index |= 8
	if case_index == 0 or case_index == 15:
		return

	var p_tl := Vector2(col, row) * CONTOUR_GRID_STEP_M
	var p_tr := Vector2(col + 1, row) * CONTOUR_GRID_STEP_M
	var p_br := Vector2(col + 1, row + 1) * CONTOUR_GRID_STEP_M
	var p_bl := Vector2(col, row + 1) * CONTOUR_GRID_STEP_M

	var e_top: Vector2 = _lerp_edge(p_tl, p_tr, v_tl, v_tr, level)
	var e_right: Vector2 = _lerp_edge(p_tr, p_br, v_tr, v_br, level)
	var e_bottom: Vector2 = _lerp_edge(p_bl, p_br, v_bl, v_br, level)
	var e_left: Vector2 = _lerp_edge(p_tl, p_bl, v_tl, v_bl, level)

	match case_index:
		1, 14:
			_add_segment(level, e_left, e_top)
		2, 13:
			_add_segment(level, e_top, e_right)
		3, 12:
			_add_segment(level, e_left, e_right)
		4, 11:
			_add_segment(level, e_right, e_bottom)
		6, 9:
			_add_segment(level, e_top, e_bottom)
		7, 8:
			_add_segment(level, e_left, e_bottom)
		5:
			_add_segment(level, e_left, e_top)
			_add_segment(level, e_right, e_bottom)
		10:
			_add_segment(level, e_top, e_right)
			_add_segment(level, e_left, e_bottom)


static func _lerp_edge(pa: Vector2, pb: Vector2, va: float, vb: float, level: float) -> Vector2:
	var t: float = 0.5 if is_equal_approx(va, vb) else (level - va) / (vb - va)
	return pa.lerp(pb, clamp(t, 0.0, 1.0))


static func _add_segment(level: float, a_m: Vector2, b_m: Vector2) -> void:
	_contour_segments_cache.append({"level": level, "a": a_m * PIXELS_PER_METER, "b": b_m * PIXELS_PER_METER})


## A real bent dirt road (ROAD_WAYPOINTS_M), not a straight strip — drawn as
## connected thick segments with dashed centerline ticks. Drawn width has a
## small legibility floor (real roads are only a few meters wide, which at
## this map's scale would otherwise be sub-pixel) — the road's true width
## still governs nothing gameplay-relevant, it's purely cosmetic.
static func _draw_road(ci: CanvasItem) -> void:
	var width_px: float = max(ROAD_WIDTH_M * PIXELS_PER_METER, 2.5)
	for i in ROAD_WAYPOINTS_M.size() - 1:
		var a: Vector2 = ROAD_WAYPOINTS_M[i] * PIXELS_PER_METER
		var b: Vector2 = ROAD_WAYPOINTS_M[i + 1] * PIXELS_PER_METER
		ci.draw_line(a, b, Color(0.55, 0.53, 0.5), width_px)
		var dir: Vector2 = (b - a).normalized()
		var length: float = a.distance_to(b)
		var t := 0.0
		while t < length - 8.0:
			var p: Vector2 = a + dir * t
			ci.draw_line(p, p + dir * 8.0, Color(0.9, 0.9, 0.8), 1.0)
			t += 18.0


## Small isolated BUILDING zones (outside the main village blob) render as a
## single low wall/ruin. The main village renders as a grid of houses,
## scaling with the zone's size — a bigger village automatically gets more
## buildings, no hand-placed list to keep in sync. All margins/gaps below
## are PROPORTIONAL to the zone's own size rather than fixed pixel amounts,
## so this still renders sensibly now that a "small village" can genuinely
## be under 100px across at this map's real-world scale.
static func _draw_village(ci: CanvasItem, rect: Rect2) -> void:
	if rect.size.x <= 40.0:
		ci.draw_rect(rect, Color(0.5, 0.48, 0.45))
		ci.draw_rect(Rect2(rect.position, Vector2(rect.size.x, max(rect.size.y * 0.1, 1.0))), Color(0.32, 0.3, 0.28))
		return

	ci.draw_rect(rect, Color(0.65, 0.58, 0.45, 0.4))

	var cols := 3
	var rows := 4
	var margin: float = rect.size.x * 0.05
	var cell_w: float = (rect.size.x - margin) / float(cols)
	var cell_h: float = (rect.size.y - margin) / float(rows)
	var gap_w: float = cell_w * 0.18
	var gap_h: float = cell_h * 0.22
	for row in rows:
		for col in cols:
			# Skip a few cells so the village reads as organic, not a grid.
			if (row + col) % 4 == 3:
				continue
			var b := Rect2(
				rect.position.x + margin + col * cell_w + gap_w * 0.5,
				rect.position.y + margin + row * cell_h + gap_h * 0.5,
				cell_w - gap_w,
				cell_h - gap_h
			)
			if b.size.x <= 0.5 or b.size.y <= 0.5:
				continue
			ci.draw_rect(b, Color(0.55, 0.42, 0.3))
			ci.draw_rect(Rect2(b.position, Vector2(b.size.x, min(b.size.y * 0.35, max(b.size.y * 0.35, 1.0)))), Color(0.35, 0.2, 0.15))


## Fills the patch's actual irregular footprint (the same warped-radius
## outline _point_in_forest_patch tests against, drawn as a closed polygon —
## the same single-shape polar-ring technique _draw_hills used before it
## switched to tracing the true combined field; a lone, non-overlapping
## forest patch has no other patch's field to conflict with, so it's still
## exactly right here), then scatters tree symbols across it. The tree grid
## itself is a fixed, deterministic offset pattern
## (no per-frame randomness — this redraws every frame via queue_redraw, so
## anything randomized here would visibly shimmer); each candidate point is
## kept only if _forest_patch_contains_offset_m says it actually falls
## inside the blob, so the scatter naturally follows the same ragged edge
## as the filled outline instead of a rectangle's straight border.
static func _draw_forest_patch(ci: CanvasItem, patch: Dictionary) -> void:
	const RING_SEGMENTS: int = 40
	var center_px: Vector2 = patch.center_m * PIXELS_PER_METER
	var outline := PackedVector2Array()
	for i in RING_SEGMENTS:
		var theta: float = TAU * float(i) / float(RING_SEGMENTS)
		var r_m: float = _forest_radius_at(patch, theta)
		outline.append(center_px + Vector2(cos(theta), sin(theta)) * r_m * PIXELS_PER_METER)
	ci.draw_colored_polygon(outline, Color(0.3, 0.45, 0.25, 0.5))

	var max_r_m: float = patch.radius_m * _forest_patch_max_warp(patch)
	var spacing_m: float = clamp(max_r_m / 7.0, 12.0, 28.0)
	var tree_radius_px: float = clamp(spacing_m * PIXELS_PER_METER * 0.27, 2.5, 6.0)
	var y_m: float = -max_r_m + spacing_m * 0.5
	var row := 0
	while y_m < max_r_m - spacing_m * 0.25:
		var x_offset_m: float = spacing_m * 0.45 if row % 2 == 0 else spacing_m * 0.9
		var x_m: float = -max_r_m + x_offset_m
		while x_m < max_r_m - spacing_m * 0.25:
			var offset_m := Vector2(x_m, y_m)
			if _forest_patch_contains_offset_m(patch, offset_m):
				ci.draw_circle(center_px + offset_m * PIXELS_PER_METER, tree_radius_px, Color(0.15, 0.35, 0.12))
			x_m += spacing_m
		y_m += spacing_m * 0.85
		row += 1


## A RichTextLabel configured to behave like a plain Label for layout
## purposes -- no bbcode (bbcode_enabled stays off, the default, so literal
## text with "%", ":", "=" etc. never gets parsed as markup), no scrollbar
## of its own (scroll_active off, fit_content on, so it sizes to its full
## content and leaves any actual scrolling to a wrapping Container, exactly
## like a Label would) -- but with real text selection: click-drag to select,
## Ctrl+C to copy, AND a right-click "Select All"/"Copy" context menu that
## works regardless of scroll position. That last part matters more than it
## sounds: a plain click-drag selection can't extend past whatever's
## currently visible inside a ScrollContainer, so without the context menu
## there'd be no way to select, say, an AAR report's header line together
## with everything below it once the report is taller than its scroll box.
## Used everywhere a Label previously showed real text worth reading back or
## copying -- see call sites (combat log entries, the AAR report, on-screen
## descriptive text, live casualty readouts).
static func make_selectable_label(text: String = "") -> RichTextLabel:
	var label := RichTextLabel.new()
	label.text = text
	label.selection_enabled = true
	label.context_menu_enabled = true
	label.scroll_active = false
	label.fit_content = true
	return label
