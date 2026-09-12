extends RefCounted
class_name GameConfig
## Shared map layout: the village, terrain, deployment zones, and enemy
## approach. Kept in one place so no other script can drift out of sync.
##
## The map's real-world size is itself DATA (see CURRENT_MAP.width_m/
## height_m/west_flank_width_m below) — different real places are
## different sizes, and nothing about the rest of this file's math cares
## which one is currently loaded. Every distance-like constant in this
## file (map dimensions included) is authored in METERS — the number you
## read IS the real-world distance — and only converted to the pixel
## space Godot actually draws in via a multiply by PIXELS_PER_METER, done
## right inline since that's a compile-time constant expression (no
## runtime conversion, no drift between "the real number" and "the number
## the engine uses"). Speeds are the one deliberate exception: they're
## tuned for a battle that resolves in a few minutes, not literal infantry
## marching pace — see the note above the movement constants.

enum TerrainType { OPEN, TREES, BUILDING }

## The two fieldable reconnaissance/target-acquisition setups the player
## chooses between before deployment (see main.gd's level-select screen):
## SPOTTER is the original ground team calling in fire on what it can see
## from wherever it's posted; DRONE_TEAM replaces it with a small crew
## flying a rotation of scout drones — see Unit.Kind.DRONE_TEAM/DRONE and
## the drone-specific constants below.
enum ReconMode { SPOTTER, DRONE_TEAM }

## Everything about ANY map — as opposed to the game's general rules,
## which live as ordinary top-level constants throughout this file — lives
## in one dictionary per real place, INCLUDING its own real-world size
## (width_m/height_m/west_flank_width_m). draw_terrain and every terrain-
## lookup function (get_terrain_type_at, nearest_cover_point,
## has_direct_los, is_river_at, elevation_m, road_waypoints_px, etc.) read
## from CURRENT_MAP's fields, never from a map-specific name of their own —
## adding a new real place to the catalog, or changing which one loads by
## default, means writing/pointing at a new MAPS entry, not touching the
## functions that read CURRENT_MAP, the window/camera sizing, or any other
## code. PIXELS_PER_METER (below) is the one deliberate exception: it's a
## fixed engine<->real-world conversion factor, not itself map data,
## specifically so every OTHER range/speed constant in this file —
## authored as "meters * PIXELS_PER_METER" — never has to change just
## because the currently-loaded map's own size did.
##
## MAPS is the full catalog — every real place this game can currently
## load, keyed by a short id. CURRENT_MAP is just MAPS[DEFAULT_MAP_ID]:
## changing the default (or adding a third place later) is a one-line/
## one-entry change here, never a change to the functions that consume
## CURRENT_MAP. A map already built stays in the catalog even once it's
## no longer the default — building up a real roster of places to fight
## over, not replacing one with the next each time.
const DEFAULT_MAP_ID: String = "pishchane"

## This map depicts Pervomaiske, a small hamlet in Kupiansk Raion, Kharkiv
## Oblast — a handful of buildings at a rural crossroads along the road
## between the larger village of Myrne (to the west, in the defender's own
## rear — NOT what's being defended here) and the wider Kupiansk axis to
## the east. The area has been fought over repeatedly since the 2022
## Kharkiv counteroffensive, unlike Moshchun's single dated battle, so no
## specific date is claimed here — just the real place and its real
## orientation. Modeled from a real satellite/map screenshot: a paved road
## running roughly east-west with tree lines on both sides, a drainage
## canal running parallel to it (not perpendicular, unlike Moshchun's
## river — it doesn't block the attacker's own line of advance, only a
## flanking move to the north), and open farmland on both sides rather
## than forest — this map is deliberately much sparser on trees than
## Moshchun's Pushcha-Vodytsia-influenced one. No detailed topographic
## data for this exact spot was found beyond the wider raion's own
## regional elevation range (roughly 80-170m) — hills below are a modest,
## gently-rolling approximation from that and the visibly flat-to-gently-
## undulating farmland in the source imagery, not a survey.
##
## The screenshot fixed the defended position, the attack's axis (due
## east along the main road), and one specific real detail — the canal
## running parallel to the road rather than perpendicular to it — but was
## never meant to fix the map's own overall scale: it picked a REGION, not
## a bounding box for the whole battle. So this map uses the same 5000m x
## 3500m core (1500m west flank) every prior map here has used, rather
## than a smaller footprint sized to just what the screenshot itself
## showed — the extra ground beyond the screenshot's own frame is authored
## as more of the same open, gently-rolling Kupiansk Raion farmland the
## sourced imagery already established, not a new kind of terrain, and the
## hamlet itself sits at the same 30%-across/50%-down position within the
## frame that it always has.
##
## The real attack direction here is simply due EAST — no rotation needed
## at all (screen-right already means real east, matching every other
## piece of this game's own east-attacker/west-defender convention), so
## unlike Moshchun's compass, true north on this map points straight up.
const MAPS: Dictionary = {
"pervomaiske": {
	"name": "Pervomaiske",
	"location_subtitle": "Kupiansk Raion, Kharkiv Oblast",
	# The real coordinates the source screenshot itself was centered on —
	# shown on the map's own location readout (see main.gd's
	# _location_label) so a curious player can look the actual place up.
	"coordinates": "49.657741, 37.270141",
	"compass_north_screen_direction": Vector2(0.0, -1.0),

	# Matches this game's standard battlefield footprint — same as
	# Moshchun and the original fictional map before it — rather than a
	# size derived from the screenshot itself; see this dictionary's own
	# doc comment above.
	"width_m": 5000.0,
	"height_m": 3500.0,
	"west_flank_width_m": 1500.0,

	"village_center": Vector2(1500.0, 1750.0) * PIXELS_PER_METER,

	# Midpoint of the regional elevation range this dictionary's own doc
	# comment already cites (roughly 80-170m ASL) — elevation_m() adds
	# this to every hill's local contribution, so "flat ground" here reads
	# as a real sea-level figure instead of 0m.
	"elevation_baseline_m": 125.0,

	## Gently rolling farmland, not Moshchun's real ridgelines — see this
	## dictionary's own doc comment for the regional elevation sourcing.
	## The first five sit near the hamlet/road, exactly where the source
	## imagery placed them; the rest fill the wider frame the screenshot
	## itself didn't show (see the doc comment above).
	"hills": [
		{"center_m": Vector2(1350.0, 1900.0), "radius_m": 480.0, "height_m": 12.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.15, "phase": 0.5}, {"frequency": 3, "amplitude": 0.1, "phase": 2.0},
		]}, # gentle rise around the hamlet
		{"center_m": Vector2(2700.0, 1400.0), "radius_m": 420.0, "height_m": 10.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 1.6}, {"frequency": 2, "amplitude": 0.12, "phase": 2.8},
		]}, # rise on the attacker's approach, north side
		{"center_m": Vector2(2900.0, 2200.0), "radius_m": 380.0, "height_m": 9.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.16, "phase": 2.3}, {"frequency": 4, "amplitude": 0.08, "phase": 0.6},
		]}, # rise south of the road, attacker side
		{"center_m": Vector2(950.0, 2250.0), "radius_m": 380.0, "height_m": 11.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.15, "phase": 0.9}, {"frequency": 2, "amplitude": 0.11, "phase": 3.0},
		]}, # rear rise, defender side
		{"center_m": Vector2(250.0, 1750.0), "radius_m": 320.0, "height_m": 10.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.14, "phase": 1.2}, {"frequency": 3, "amplitude": 0.1, "phase": 2.5},
		]}, # well west of the hamlet, gentle rise
		{"center_m": Vector2(4200.0, 1500.0), "radius_m": 450.0, "height_m": 13.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.13, "phase": 0.8}, {"frequency": 3, "amplitude": 0.11, "phase": 1.9},
		]}, # distant rise on the attacker's approach, far east — newly visible ground
		{"center_m": Vector2(2600.0, 3100.0), "radius_m": 400.0, "height_m": 10.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.15, "phase": 2.6}, {"frequency": 2, "amplitude": 0.1, "phase": 1.0},
		]}, # southern farmland rise — newly visible ground
		{"center_m": Vector2(2000.0, 300.0), "radius_m": 380.0, "height_m": 9.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.14, "phase": 1.4}, {"frequency": 3, "amplitude": 0.12, "phase": 3.0},
		]}, # northern farmland rise — newly visible ground
		{"center_m": Vector2(-1100.0, 2300.0), "radius_m": 340.0, "height_m": 9.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.15, "phase": 2.1}, {"frequency": 3, "amplitude": 0.09, "phase": 0.5},
		]}, # deeper west-flank rise, rear area
	],

	# The hamlet itself: a genuinely small, compact cluster (not Moshchun's
	# elongated riverside ribbon — this is a rural crossroads settlement,
	# not a river-side one), plus one small outlying farmstead further
	# along the road, matching the handful of separate structures visible
	# in the source imagery. Sizes match the source imagery exactly —
	# widening the map's own frame doesn't make the real buildings bigger.
	"terrain_zones": [
		{"rect": Rect2(1440.0 * PIXELS_PER_METER, 1700.0 * PIXELS_PER_METER, 120.0 * PIXELS_PER_METER, 100.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING}, # Pervomaiske
		{"rect": Rect2(1935.0 * PIXELS_PER_METER, 1765.0 * PIXELS_PER_METER, 35.0 * PIXELS_PER_METER, 30.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING}, # outlying farmstead
	],

	## Sparse, small patches — thin tree-lines along the road and canal
	## (the dark fringes visible flanking both in the source imagery),
	## plus a few scattered field-edge copses, NOT Moshchun's big rounded
	## forest blocks. This is open farmland, not woodland — deliberately
	## much less tree cover overall than Moshchun's map. The first thirteen
	## sit exactly where the source imagery placed them relative to the
	## hamlet; the last four fill the wider frame the screenshot itself
	## didn't show, in the same sparse style.
	"forest_patches": [
		{"center_m": Vector2(3300.0, 1630.0), "radius_m": 80.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.18, "phase": 0.4}, {"frequency": 3, "amplitude": 0.1, "phase": 2.1},
		]}, # tree line, road/canal corridor
		{"center_m": Vector2(2900.0, 1655.0), "radius_m": 75.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.16, "phase": 1.3}, {"frequency": 2, "amplitude": 0.12, "phase": 2.9},
		]}, # tree line, road/canal corridor
		{"center_m": Vector2(2500.0, 1705.0), "radius_m": 85.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.17, "phase": 2.2}, {"frequency": 4, "amplitude": 0.09, "phase": 0.5},
		]}, # tree line, road/canal corridor
		{"center_m": Vector2(2100.0, 1730.0), "radius_m": 70.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.15, "phase": 0.8}, {"frequency": 2, "amplitude": 0.13, "phase": 2.6},
		]}, # tree line, road/canal corridor
		{"center_m": Vector2(1700.0, 1745.0), "radius_m": 80.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.16, "phase": 1.9}, {"frequency": 3, "amplitude": 0.11, "phase": 0.3},
		]}, # tree line, road/canal corridor, near the hamlet
		{"center_m": Vector2(1300.0, 1715.0), "radius_m": 75.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 2.7}, {"frequency": 2, "amplitude": 0.12, "phase": 0.6},
		]}, # tree line, road/canal corridor, near the hamlet
		{"center_m": Vector2(900.0, 1675.0), "radius_m": 70.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.15, "phase": 0.2}, {"frequency": 4, "amplitude": 0.08, "phase": 2.4},
		]}, # tree line, road/canal corridor, toward the rear
		{"center_m": Vector2(2400.0, 2150.0), "radius_m": 90.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.16, "phase": 1.1}, {"frequency": 2, "amplitude": 0.1, "phase": 3.0},
		]}, # field-edge copse, attacker side
		{"center_m": Vector2(1600.0, 2250.0), "radius_m": 85.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.14, "phase": 2.5}, {"frequency": 3, "amplitude": 0.12, "phase": 0.7},
		]}, # field-edge copse, south of the hamlet
		{"center_m": Vector2(2600.0, 1250.0), "radius_m": 80.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.15, "phase": 0.3}, {"frequency": 2, "amplitude": 0.11, "phase": 2.2},
		]}, # field-edge copse, attacker approach north
		{"center_m": Vector2(1200.0, 1350.0), "radius_m": 75.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.17, "phase": 1.7}, {"frequency": 4, "amplitude": 0.08, "phase": 3.1},
		]}, # field-edge copse, rear north
		{"center_m": Vector2(300.0, 1650.0), "radius_m": 90.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 0.6}, {"frequency": 2, "amplitude": 0.13, "phase": 2.8},
		]}, # field copse west of the hamlet
		{"center_m": Vector2(0.0, 2150.0), "radius_m": 80.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.16, "phase": 2.0}, {"frequency": 3, "amplitude": 0.1, "phase": 0.4},
		]}, # field copse southwest of the hamlet, near the flank boundary
		{"center_m": Vector2(3900.0, 1450.0), "radius_m": 80.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.13, "phase": 1.5}, {"frequency": 3, "amplitude": 0.09, "phase": 0.2},
		]}, # tree line, far east approach — newly visible ground
		{"center_m": Vector2(2300.0, 2950.0), "radius_m": 85.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 2.9}, {"frequency": 2, "amplitude": 0.1, "phase": 1.1},
		]}, # field-edge copse, newly visible southern farmland
		{"center_m": Vector2(2700.0, 400.0), "radius_m": 80.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.15, "phase": 0.6}, {"frequency": 3, "amplitude": 0.11, "phase": 2.3},
		]}, # field-edge copse, newly visible northern farmland
		{"center_m": Vector2(-1200.0, 2000.0), "radius_m": 75.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.16, "phase": 1.8}, {"frequency": 2, "amplitude": 0.12, "phase": 0.3},
		]}, # west flank copse, deeper rear
	],

	"road_width_m": 6.0,
	"road_waypoints_m": [
		Vector2(4900.0, 1580.0), # newly visible ground — extends the attacker's approach to the wider frame
		Vector2(4200.0, 1615.0), # newly visible ground
		Vector2(3550.0, 1650.0),
		Vector2(3100.0, 1680.0),
		Vector2(2700.0, 1700.0),
		Vector2(2300.0, 1720.0),
		Vector2(1900.0, 1735.0),
		Vector2(1500.0, 1750.0), # the hamlet
		Vector2(1100.0, 1720.0),
		Vector2(750.0, 1680.0),
	],

	## The drainage canal visible in the source imagery, running roughly
	## PARALLEL to the road (not perpendicular, unlike Moshchun's river) —
	## it doesn't block the attacker's own east-west line of advance at
	## all, only a flanking move to the north, but is still a real,
	## impassable obstacle where it does run (steep-banked drainage
	## channels are a genuine infantry/vehicle obstacle) except at the one
	## crossing near the hamlet, where a real culvert/crossing point is
	## plausible. Narrower than Moshchun's river — this is a canal, not a
	## real river. A constant 120m south of the road throughout (matching
	## the source imagery), including along the two new far-east legs.
	"river": {
		"width_m": 15.0,
		"crossing_point_m": Vector2(1500.0, 1630.0), # sits exactly on path_m below, at the hamlet's own longitude
		"crossing_gap_m": 50.0,
		"path_m": [
			Vector2(4900.0, 1460.0), # newly visible ground
			Vector2(4200.0, 1495.0), # newly visible ground
			Vector2(3550.0, 1530.0),
			Vector2(3100.0, 1560.0),
			Vector2(2700.0, 1580.0),
			Vector2(2300.0, 1600.0),
			Vector2(1900.0, 1615.0),
			Vector2(1500.0, 1630.0), # the crossing
			Vector2(1100.0, 1600.0),
			Vector2(750.0, 1560.0),
		],
	},

	"player": {
		"deployment_zone": Rect2(150.0 * PIXELS_PER_METER, 100.0 * PIXELS_PER_METER, 2200.0 * PIXELS_PER_METER, 3300.0 * PIXELS_PER_METER),
		"mortar_deployment_zone": Rect2(30.0 * PIXELS_PER_METER, 60.0 * PIXELS_PER_METER, 1950.0 * PIXELS_PER_METER, 3400.0 * PIXELS_PER_METER),
		"spotter_deployment_zone": Rect2(30.0 * PIXELS_PER_METER, 30.0 * PIXELS_PER_METER, 4940.0 * PIXELS_PER_METER, 3440.0 * PIXELS_PER_METER),
		"default_squad_positions": [
			Vector2(1390.0, 1700.0) * PIXELS_PER_METER,
			Vector2(1510.0, 1750.0) * PIXELS_PER_METER,
			Vector2(1410.0, 1830.0) * PIXELS_PER_METER,
		],
		# South of the hamlet's own building footprint and clear of the
		# canal — a mortar can never be set up inside a building or
		# dragged into one.
		"mortar_default_position": Vector2(1500.0, 1920.0) * PIXELS_PER_METER,
		"spotter_default_position": Vector2(1250.0, 1770.0) * PIXELS_PER_METER,
	},

	"enemy": {
		"spawn_x": 4900.0 * PIXELS_PER_METER, # matches the new easternmost road/river waypoint, same as before
		"squad_spread_min_offset_m": -260.0,
		"squad_spread_max_offset_m": 260.0,
		"mortar_rear_x_m": 4700.0, # 200m behind spawn_x, same offset as before
		"mortar_spread_min_y_m": 1450.0,
		"mortar_spread_max_y_m": 1950.0,
		# Deep enough into the (now 1500m) west flank to be a real flank,
		# same 2/3-in proportion as before and as Moshchun.
		"flank_waypoint_x": -1000.0 * PIXELS_PER_METER,
		"flank_waypoint_arrival_radius": 350.0 * PIXELS_PER_METER, # must stay > ENEMY_SURROUND_STANDOFF_RADIUS (300m) — see that constant's own doc comment
	},
},

## This map depicts Pishchane, a small settlement in Kalmiuskyi Raion,
## Donetsk Oblast, built from real satellite imagery around the coordinates
## 47.768118, 37.878843 — a real farm/livestock complex at the settlement's
## southern edge (the coordinates land almost exactly on it), a residential
## strip just north of it, and, immediately northeast, a real wooded ravine
## (a "balka" — a natural gully cut by drainage, not a planted feature)
## that narrows as it runs down toward a small pond right next to the
## complex. Unlike Moshchun and Pervomaiske, no specific documented
## engagement is claimed for this exact spot — this part of Donetsk Oblast
## has been outside Ukrainian government control since 2014, not a place
## that changed hands in 2022, so there is no real battle to depict here.
## The terrain is real; the engagement fought over it is a hypothetical
## one, same fictional-tactical premise (a Russian assault probing from
## the east) as every other map in this game, not a re-creation of an
## actual fight — stated plainly rather than implied, the way this file
## already states plainly when a map's elevation or building layout is an
## approximation rather than a survey.
##
## The ravine's own tree cover is modeled as a CHAIN of small, closely-
## spaced patches following the real tapering shape traced from the source
## imagery — a wide wedge at the head, narrowing leg by leg down to the
## pond — rather than one or two large circles standing in for the whole
## area. A single big blob would have been faster to author but would
## have covered ground that's actually open, and left the real taper
## invisible; keeping each patch small enough that the chain's own outline
## does the work is what makes the shape on screen the real one instead of
## an idealized stand-in. The same technique models two real steppe
## shelterbelts (windbreak tree lines — "lisosmuha," extremely common
## across this open farmland, planted in long straight or gently curved
## rows between fields) as chains of small overlapping patches forming a
## thin line, rather than as an oval that would misrepresent them as a
## rounded stand of trees. Regional elevation for this part of the Donets
## uplands runs higher and more varied than Pervomaiske's flat steppe
## (roughly 150-220m ASL, with real ravines like this one cut into it) —
## hills below are a modest approximation from that and the real ravine's
## own rim, not a survey.
##
## The real road/tree-line axis here runs diagonally (perceptibly NW-SE)
## rather than due east-west like Pervomaiske's — reproduced directly as a
## steady y-drift as x increases along road_waypoints_m/the forest chain,
## the same technique Pervomaiske and Moshchun already used for local
## geometry that isn't axis-aligned, rather than rotating the compass over
## it. The real village center-line actually runs north from the complex,
## off this east-west axis entirely; it's modeled as real, present terrain
## (the residential terrain_zones entry) rather than forced onto the
## attacker/defender axis just to have somewhere to put it. Compass north
## points straight up: the real attack axis modeled here (from the open
## farmland to the real east) already matches this game's standing east-
## attacker/west-defender convention, same as Pervomaiske, so no rotation
## is needed. This map has no river/canal — the real watercourse near here
## is the small pond by the complex, fed by the ravine's own drainage, too
## local to model as a map-spanning obstacle the way Moshchun's river or
## Pervomaiske's canal are; CURRENT_MAP simply omits the "river" key, and
## every river-aware function treats that as "no river on this map" rather
## than assuming every map must have one.
"pishchane": {
	"name": "Pishchane",
	"location_subtitle": "Kalmiuskyi Raion, Donetsk Oblast",
	# The real coordinates this map was built from — shown on the map's
	# own location readout (see main.gd's _location_label) so a curious
	# player can look the actual place up.
	"coordinates": "47.768118, 37.878843",
	"compass_north_screen_direction": Vector2(0.0, -1.0),

	"width_m": 5000.0,
	"height_m": 3500.0,
	"west_flank_width_m": 1500.0,

	"village_center": Vector2(1500.0, 1750.0) * PIXELS_PER_METER,

	# Midpoint of the regional elevation range this dictionary's own doc
	# comment already cites (roughly 150-220m ASL) — elevation_m() adds
	# this to every hill's local contribution, so "flat ground" here reads
	# as a real sea-level figure instead of 0m.
	"elevation_baseline_m": 185.0,

	## The first four sit near real features (the ravine's own rim, the
	## village, the complex's south side, the rear); the rest fill the
	## standard frame's wider margins, in the same modestly-rolling style.
	"hills": [
		{"center_m": Vector2(1800.0, 1250.0), "radius_m": 400.0, "height_m": 11.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.15, "phase": 0.9}, {"frequency": 3, "amplitude": 0.1, "phase": 2.4},
		]}, # high ground flanking the ravine's own northern rim
		# Sits astride the road roughly 700m out — real, unnamed high
		# ground is plausible here (no precise survey data exists for
		# this exact spot, same honesty caveat as every hill on this
		# map), and without SOME rise between the complex and the open
		# farmland, the position has an unbroken sightline for kilometers
		# in every direction: real ground-level LOS in this engine is
		# masked by elevation, not by TREES (which only affect detection
		# odds/cover, not raw visibility — see has_direct_los's own doc
		# comment), so completely flat terrain here would leave the
		# spotter, mortar, and squads all visible to (and equally able to
		# see) the entire approach from minute one — confirmed directly:
		# before this hill existed, the defended position could see, and
		# be seen from, the road nearly 2.5km out, and lost the spotter
		# almost every trial as a direct result.
		{"center_m": Vector2(2000.0, 1520.0), "radius_m": 340.0, "height_m": 20.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.14, "phase": 1.7}, {"frequency": 3, "amplitude": 0.11, "phase": 0.2},
		]}, # rise astride the road, masks the complex from the open approach
		{"center_m": Vector2(1300.0, 2100.0), "radius_m": 380.0, "height_m": 9.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 1.1}, {"frequency": 2, "amplitude": 0.12, "phase": 2.7},
		]}, # gentle rise south of the complex, defender's side
		{"center_m": Vector2(1400.0, 1050.0), "radius_m": 350.0, "height_m": 10.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.16, "phase": 0.3}, {"frequency": 4, "amplitude": 0.08, "phase": 2.9},
		]}, # rise near the village proper, north of the complex
		{"center_m": Vector2(400.0, 1900.0), "radius_m": 320.0, "height_m": 9.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.15, "phase": 1.8}, {"frequency": 2, "amplitude": 0.11, "phase": 0.6},
		]}, # rear rise, defender's side
		{"center_m": Vector2(4300.0, 1000.0), "radius_m": 450.0, "height_m": 12.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.13, "phase": 2.2}, {"frequency": 3, "amplitude": 0.1, "phase": 0.4},
		]}, # distant rise on the attacker's approach, far east
		{"center_m": Vector2(2600.0, 3100.0), "radius_m": 400.0, "height_m": 10.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 0.7}, {"frequency": 2, "amplitude": 0.12, "phase": 2.1},
		]}, # southern farmland rise
		{"center_m": Vector2(2200.0, 300.0), "radius_m": 380.0, "height_m": 9.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.15, "phase": 1.5}, {"frequency": 3, "amplitude": 0.09, "phase": 3.0},
		]}, # northern farmland rise
		{"center_m": Vector2(-1100.0, 2300.0), "radius_m": 340.0, "height_m": 9.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.14, "phase": 2.6}, {"frequency": 3, "amplitude": 0.11, "phase": 0.8},
		]}, # deeper west-flank rise, rear area
	],

	# The real complex the coordinates land on, a smaller outbuilding just
	# south of it, and the residential streets north of both — three
	# separate, axis-aligned footprints rather than one shape standing in
	# for the whole settlement, matching how the source imagery actually
	# shows three distinct built-up clusters, not one continuous one.
	"terrain_zones": [
		{"rect": Rect2(1410.0 * PIXELS_PER_METER, 1685.0 * PIXELS_PER_METER, 180.0 * PIXELS_PER_METER, 130.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING}, # the defended complex
		{"rect": Rect2(1515.0 * PIXELS_PER_METER, 1840.0 * PIXELS_PER_METER, 50.0 * PIXELS_PER_METER, 40.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING}, # smaller outbuilding, south of the complex
		{"rect": Rect2(1295.0 * PIXELS_PER_METER, 1300.0 * PIXELS_PER_METER, 350.0 * PIXELS_PER_METER, 140.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING}, # Pishchane's residential streets, north of the complex
	],

	## See this dictionary's own doc comment above for why these are
	## chains of small patches, not a few big ones: patches 1-6 trace the
	## real ravine's tapering shape; 7-12 and 13-16 are two real steppe
	## shelterbelt lines; 17-19 are village garden trees; 20-22 are single
	## isolated copses filling the standard frame's wider margins.
	"forest_patches": [
		{"center_m": Vector2(1750.0, 1330.0), "radius_m": 110.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.16, "phase": 0.5}, {"frequency": 3, "amplitude": 0.1, "phase": 2.2},
		]}, # ravine head, widest point
		{"center_m": Vector2(1780.0, 1410.0), "radius_m": 95.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.15, "phase": 1.4}, {"frequency": 2, "amplitude": 0.12, "phase": 2.8},
		]}, # ravine, narrowing
		{"center_m": Vector2(1760.0, 1490.0), "radius_m": 80.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.17, "phase": 2.5}, {"frequency": 4, "amplitude": 0.09, "phase": 0.6},
		]}, # ravine, narrowing
		{"center_m": Vector2(1700.0, 1560.0), "radius_m": 65.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 0.8}, {"frequency": 2, "amplitude": 0.13, "phase": 2.3},
		]}, # ravine, narrowing
		{"center_m": Vector2(1630.0, 1620.0), "radius_m": 50.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.16, "phase": 1.9}, {"frequency": 3, "amplitude": 0.1, "phase": 0.3},
		]}, # ravine tail, near the pond
		{"center_m": Vector2(1560.0, 1670.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.15, "phase": 2.7}, {"frequency": 2, "amplitude": 0.11, "phase": 0.9},
		]}, # ravine tail, right at the pond by the complex
		{"center_m": Vector2(3200.0, 900.0), "radius_m": 45.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.15, "phase": 0.4}, {"frequency": 3, "amplitude": 0.1, "phase": 2.1},
		]}, # steppe shelterbelt, attacker's farmland
		{"center_m": Vector2(3200.0, 990.0), "radius_m": 45.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 1.2}, {"frequency": 2, "amplitude": 0.12, "phase": 2.6},
		]}, # steppe shelterbelt, attacker's farmland
		{"center_m": Vector2(3200.0, 1080.0), "radius_m": 45.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.16, "phase": 2.4}, {"frequency": 4, "amplitude": 0.08, "phase": 0.5},
		]}, # steppe shelterbelt, attacker's farmland
		{"center_m": Vector2(3200.0, 1170.0), "radius_m": 45.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.15, "phase": 0.7}, {"frequency": 2, "amplitude": 0.13, "phase": 2.9},
		]}, # steppe shelterbelt, attacker's farmland
		{"center_m": Vector2(3200.0, 1260.0), "radius_m": 45.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.17, "phase": 1.6}, {"frequency": 3, "amplitude": 0.09, "phase": 0.2},
		]}, # steppe shelterbelt, attacker's farmland
		{"center_m": Vector2(3200.0, 1350.0), "radius_m": 45.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 2.3}, {"frequency": 2, "amplitude": 0.1, "phase": 0.7},
		]}, # steppe shelterbelt, attacker's farmland
		{"center_m": Vector2(4400.0, 1600.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.15, "phase": 0.9}, {"frequency": 3, "amplitude": 0.1, "phase": 2.5},
		]}, # second shelterbelt, near the attacker's spawn
		{"center_m": Vector2(4400.0, 1690.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.16, "phase": 1.7}, {"frequency": 2, "amplitude": 0.12, "phase": 0.3},
		]}, # second shelterbelt, near the attacker's spawn
		{"center_m": Vector2(4400.0, 1780.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.14, "phase": 2.8}, {"frequency": 4, "amplitude": 0.09, "phase": 1.0},
		]}, # second shelterbelt, near the attacker's spawn
		{"center_m": Vector2(4400.0, 1870.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.15, "phase": 0.4}, {"frequency": 2, "amplitude": 0.11, "phase": 2.0},
		]}, # second shelterbelt, near the attacker's spawn
		{"center_m": Vector2(1400.0, 1320.0), "radius_m": 25.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.18, "phase": 0.6}, {"frequency": 3, "amplitude": 0.1, "phase": 2.4},
		]}, # household garden trees, village
		{"center_m": Vector2(1550.0, 1300.0), "radius_m": 22.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.17, "phase": 1.3}, {"frequency": 2, "amplitude": 0.13, "phase": 2.9},
		]}, # household garden trees, village
		{"center_m": Vector2(1480.0, 1420.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.16, "phase": 2.1}, {"frequency": 4, "amplitude": 0.08, "phase": 0.5},
		]}, # household garden trees, village
		{"center_m": Vector2(2600.0, 3100.0), "radius_m": 90.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.15, "phase": 2.6}, {"frequency": 2, "amplitude": 0.1, "phase": 1.0},
		]}, # isolated copse, southern farmland
		{"center_m": Vector2(2200.0, 300.0), "radius_m": 85.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.14, "phase": 1.4}, {"frequency": 3, "amplitude": 0.12, "phase": 3.0},
		]}, # isolated copse, northern farmland
		{"center_m": Vector2(-1100.0, 2300.0), "radius_m": 70.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.16, "phase": 1.8}, {"frequency": 2, "amplitude": 0.12, "phase": 0.3},
		]}, # west flank copse, deeper rear
	],

	"road_width_m": 6.0,
	# Runs diagonally (NW-SE) through the complex, not due east-west — see
	# this dictionary's own doc comment for why that's reproduced as a
	# y-drift instead of a compass rotation.
	"road_waypoints_m": [
		Vector2(750.0, 1900.0),
		Vector2(1500.0, 1750.0), # the complex
		Vector2(2200.0, 1610.0),
		Vector2(2900.0, 1470.0),
		Vector2(3600.0, 1330.0),
		Vector2(4300.0, 1190.0),
		Vector2(4900.0, 1070.0),
	],

	"player": {
		"deployment_zone": Rect2(150.0 * PIXELS_PER_METER, 100.0 * PIXELS_PER_METER, 2200.0 * PIXELS_PER_METER, 3300.0 * PIXELS_PER_METER),
		"mortar_deployment_zone": Rect2(30.0 * PIXELS_PER_METER, 60.0 * PIXELS_PER_METER, 1950.0 * PIXELS_PER_METER, 3400.0 * PIXELS_PER_METER),
		"spotter_deployment_zone": Rect2(30.0 * PIXELS_PER_METER, 30.0 * PIXELS_PER_METER, 4940.0 * PIXELS_PER_METER, 3440.0 * PIXELS_PER_METER),
		"default_squad_positions": [
			Vector2(1320.0, 1780.0) * PIXELS_PER_METER,
			Vector2(1460.0, 1870.0) * PIXELS_PER_METER,
			Vector2(1610.0, 1690.0) * PIXELS_PER_METER,
		],
		# South of both the complex and its outbuilding, clear of either.
		"mortar_default_position": Vector2(1300.0, 1950.0) * PIXELS_PER_METER,
		# Actually inside the ravine's own tree cover (not just nearby —
		# checked directly against forest_patches, not eyeballed), with a
		# clear ~250m sightline down to the road.
		"spotter_default_position": Vector2(1780.0, 1440.0) * PIXELS_PER_METER,
	},

	"enemy": {
		"spawn_x": 4900.0 * PIXELS_PER_METER, # matches the road's own easternmost waypoint
		"squad_spread_min_offset_m": -260.0,
		"squad_spread_max_offset_m": 260.0,
		"mortar_rear_x_m": 4700.0, # 200m behind spawn_x, same offset as every other map
		"mortar_spread_min_y_m": 850.0,
		"mortar_spread_max_y_m": 1350.0,
		# Deep enough into the 1500m west flank to be a real flank, same
		# 2/3-in proportion as every other map.
		"flank_waypoint_x": -1000.0 * PIXELS_PER_METER,
		"flank_waypoint_arrival_radius": 350.0 * PIXELS_PER_METER, # must stay > ENEMY_SURROUND_STANDOFF_RADIUS (300m) — see that constant's own doc comment
	},
},
}

## The map actually loaded right now — see MAPS/DEFAULT_MAP_ID's own doc
## comment above. A `static var`, not a `const`: the level-select screen's
## own map dropdown (LevelSelectScreen) lets the player switch this at
## runtime, before deployment — see set_active_map, the only place this
## (and everything derived from it below) should ever be reassigned.
static var CURRENT_MAP: Dictionary = MAPS[DEFAULT_MAP_ID]

## The internal engine<->real-world scale: a fixed, map-INDEPENDENT
## conversion, not derived from any particular map's own size. This is
## the actual key to a genuine data-driven map: every OTHER range/speed
## constant in this file is written as "meters * PIXELS_PER_METER" and
## evaluated once at compile time — as long as this factor itself never
## changes, none of those hundreds of other constants need to change
## either when the map's own real-world dimensions do. (An earlier version
## derived this FROM a fixed MAP_WIDTH_PX/MAP_WIDTH_M pair, which is
## exactly backwards for a swappable map: it made the "how many engine
## units per meter" question depend on which specific map happened to be
## loaded.)
const PIXELS_PER_METER: float = 0.2

## The map's own real-world dimensions — genuine map DATA, unlike
## PIXELS_PER_METER above — live in CURRENT_MAP (width_m/height_m/
## west_flank_width_m) and get their pixel-space equivalents derived
## right below it once it's actually defined. See CURRENT_MAP's own doc
## comment for why width/height specifically count as data while the
## conversion factor doesn't.
static var MAP_WIDTH_M: float
static var MAP_HEIGHT_M: float
static var WEST_FLANK_WIDTH_M: float
## MAP_WIDTH_PX is the core battle canvas's width; the actual map VIEWPORT
## is wider still (see CAMERA_VIEWPORT_WIDTH_PX below — it also shows
## WEST_FLANK_WIDTH_PX of ground to the west), with the sidebar UI
## starting at GameConfig.SIDEBAR_X (see main.gd).
##
## MAP_HEIGHT_PX is the map viewport's OWN height — main.gd sizes
## map_container/map_viewport to exactly this AND resizes the actual
## window to fit (see main.gd's _ready and MIN_WINDOW_HEIGHT_PX below),
## so a differently-sized map's window adjusts automatically with it —
## nothing about the window is a fixed, map-specific number to remember
## to update by hand.
static var MAP_WIDTH_PX: float
static var MAP_HEIGHT_PX: float

## Open, undeveloped ground west of x=0 — nobody deploys here, no authored
## cover/terrain features exist here, but units can be pushed into it
## (enemy flanking, a hard-pressed player retreat, a mortar evading
## encirclement). Always visible (see CAMERA_VIEWPORT_WIDTH_PX below), not
## revealed by panning — the whole modeled map already fits inside the
## display column at this fixed scale, so this is the first world-space
## that doesn't, which is what originally made a wider viewport than just
## MAP_WIDTH_PX necessary here at all.
static var WEST_FLANK_WIDTH_PX: float

## The map viewport is permanently wide enough to show the ENTIRE modeled
## world — the west flank through the map's true east edge — at once, at
## full scale, so the camera never needs to pan at all. This replaced an
## earlier panning camera (and, briefly, a runtime-toggled "wide view" that
## reclaimed the casualty dashboard's screen space only when needed): both
## turned out to be the wrong layer to solve "simultaneous action at both
## ends shouldn't make the screen fight itself" at — panning has nowhere to
## go that satisfies both ends at once (its own range was only 300px wide),
## and toggling the viewport size at runtime meant hiding the casualty
## dashboard, which the user didn't want gone even temporarily. Simplest
## fix: make the window (and this viewport) wide enough up front that
## panning is never needed in the first place — see project.godot's
## viewport_width and main.gd's sidebar layout (GameConfig.SIDEBAR_X),
## both widened by exactly WEST_FLANK_WIDTH_PX to make room.
static var CAMERA_VIEWPORT_WIDTH_PX: float
## The camera's own fixed x, always — the midpoint of the full
## [-WEST_FLANK_WIDTH_PX, MAP_WIDTH_PX] range the viewport now permanently
## shows. Fixed, not dynamically tracked: since the viewport already shows
## that entire range at all times, every possible unit position is already
## visible regardless of exactly where it sits, so there's nothing left to
## track or pan toward.
static var CAMERA_CENTER_X: float
## Where the sidebar column (casualty dashboard, combat log, retreat/pause
## buttons, doctrine panel) starts — right after the widened map viewport,
## with the same 20px gap the original [0,1000]-wide layout used.
static var SIDEBAR_X: float
## The sidebar column's own fixed width (DoctrinePanel's own declared
## custom_minimum_size is 320px; this adds a small margin) — independent
## of the map's size, so main.gd can compute a correctly-sized WINDOW for
## whichever map is loaded (SIDEBAR_X + this) instead of a hand-set
## project.godot number that would silently stop matching the moment a
## differently-sized map was swapped in.
const SIDEBAR_COLUMN_WIDTH: float = 340.0
## The sidebar's own worst-case vertical content needs this much height
## regardless of how tall any particular map's own MAP_HEIGHT_PX happens
## to be — see main.gd's _ready, which sizes the actual window to
## max(MAP_HEIGHT_PX, this). CasualtyDashboard itself now scrolls
## internally past a handful of enemy mortar rows rather than growing the
## window for a worst case that's rare in practice (see its own _ready) —
## this stays fixed at the panel's own tuned, comfortably-fits-the-common-
## case height rather than tracking ENEMY_MORTAR_COUNT_MAX.
const MIN_WINDOW_HEIGHT_PX: float = 760.0

## Recomputes every static var derived from CURRENT_MAP (see each one's
## own doc comment above/below for why it's data-derived rather than a
## plain compile-time const now that CURRENT_MAP itself can change at
## runtime) and drops the river/contour caches, which are built once per
## loaded map and would otherwise keep showing the PREVIOUS map's terrain.
## Called once automatically at script load (_static_init, below) and
## again by set_active_map every time the player picks a different map.
static func _recompute_map_derived_state() -> void:
	MAP_WIDTH_M = CURRENT_MAP.width_m
	MAP_HEIGHT_M = CURRENT_MAP.height_m
	WEST_FLANK_WIDTH_M = CURRENT_MAP.west_flank_width_m
	MAP_WIDTH_PX = MAP_WIDTH_M * PIXELS_PER_METER
	MAP_HEIGHT_PX = MAP_HEIGHT_M * PIXELS_PER_METER
	WEST_FLANK_WIDTH_PX = WEST_FLANK_WIDTH_M * PIXELS_PER_METER
	CAMERA_VIEWPORT_WIDTH_PX = MAP_WIDTH_PX + WEST_FLANK_WIDTH_PX
	CAMERA_CENTER_X = (-WEST_FLANK_WIDTH_PX + MAP_WIDTH_PX) / 2.0
	SIDEBAR_X = CAMERA_VIEWPORT_WIDTH_PX + 20.0
	ENEMY_SAFE_X = CURRENT_MAP.enemy.spawn_x + 150.0 * PIXELS_PER_METER
	PLAYER_SAFE_X = -(WEST_FLANK_WIDTH_M - 100.0) * PIXELS_PER_METER

	_river_rects_built = false
	_river_segment_rects.clear()
	_contour_cache_built = false
	_contour_segments_cache.clear()
	_contour_col_origin_m = 0.0


## Runs automatically the first time this script is loaded/referenced —
## Godot 4.4+'s static-constructor hook — so every static var above is
## already correctly populated before anything else in the game (main.gd's
## own _ready included) ever reads one, exactly as if they were still the
## compile-time consts they used to be.
static func _static_init() -> void:
	_recompute_map_derived_state()


## Switches which real place is loaded, for the level-select screen's own
## map dropdown (LevelSelectScreen) — the only intended caller. Must run
## BEFORE deployment/battle setup reads any CURRENT_MAP-derived value
## (default_squad_positions, MAP_WIDTH_PX, ...), which is exactly when the
## dropdown offers the choice: before recon-mode selection, let alone
## deployment. main.gd still has to re-apply the derived window/camera
## sizing itself afterward (see its own _apply_map_dimensions) — this
## function only updates GameConfig's own state.
static func set_active_map(map_id: String) -> void:
	if not MAPS.has(map_id) or CURRENT_MAP == MAPS[map_id]:
		return
	CURRENT_MAP = MAPS[map_id]
	_recompute_map_derived_state()


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

## How much of a defender's own terrain-cover reduction a genuinely
## higher-up direct-fire attacker (same ELEVATION_ADVANTAGE_THRESHOLD_M
## gate as the detection bonus above) partially defeats — 0.4 means cover
## that would normally cut incoming fire to (say) 20% effectiveness only
## cuts it to 52% (lerp toward 1.0, "as if no cover," never past it —
## elevation lets an attacker see and shoot INTO a position, it doesn't
## make that position more dangerous to occupy than open ground would be).
##
## Grounded in real, if qualitative rather than precisely numeric, doctrine
## rather than a fabricated "elevation = free accuracy" bonus: plunging
## fire from higher ground is the textbook reason a "reverse slope
## defense" exists at all (positioning behind the crest specifically to
## deny an attacker the ability to see and fire down INTO the position —
## see Wikipedia's own "Plunging fire"/"Defensive fighting position"
## articles) and why infantry doctrine (e.g. FM 3-21.8) instructs against
## occupying low ground observable from higher terrain in the first place
## — a foxhole or treeline built to stop a flat, direct-line shot loses
## much of its value against fire coming down INTO it from above, the
## same physical reason MORTAR_COVER_MULTIPLIER's own table is already
## weaker than SQUAD_COVER_MULTIPLIER's. Deliberately NOT modeled as a
## flat "downhill shots are more accurate" bonus independent of cover: the
## real, well-documented ballistic effect at that end (the "rifleman's
## rule" — gravity only acts over the horizontal component of a slanted
## shot, so an unadjusted uphill/downhill shot flies high) is a shooter's
## AIM-CORRECTION problem, resolved by trained soldiers accounting for
## slant range, not a demonstrated hit-probability swing in real combat
## data — no equivalent to the 1948 ORO close-range dataset or the FM 7-90
## mortar-casualty figures already cited elsewhere in this file exists for
## "elevation alone raises hit chance," so this file doesn't claim one.
const ELEVATION_COVER_DEFEAT_FRACTION: float = 0.4


## How much a blob's effective radius is stretched (>1) or pinched (<1) in
## the direction `theta` (radians from its center) — a sum of cosine
## harmonics, each blob's own fixed set giving it a distinct, irregular,
## non-circular footprint instead of a perfect circle/radial Gaussian.
## Amplitudes are kept well under 1.0 in total so this can never flip the
## effective radius negative. Shared by CURRENT_MAP.hills (see _hill_radius_warp,
## elevation_m) and CURRENT_MAP.forest_patches (see _forest_radius_at) — same technique,
## two different uses of "irregular blob."
static func _radius_warp(warp_harmonics: Array, theta: float) -> float:
	var w := 1.0
	for h in warp_harmonics:
		w += h.amplitude * cos(h.frequency * theta + h.phase)
	return w


static func _hill_radius_warp(hill: Dictionary, theta: float) -> float:
	return _radius_warp(hill.warp_harmonics, theta)


## Ground elevation in meters ABOVE SEA LEVEL at a point (given in the
## engine's pixel space, like everything else) — CURRENT_MAP's own
## elevation_baseline_m (the real place's actual regional ASL range,
## sourced the same way every other piece of a map's terrain is, see that
## dictionary's own doc comment) plus the sum of every hill's (warped,
## non-circular) local contribution above it. Adding a per-map CONSTANT
## offset here is free everywhere else in the file that reads elevation:
## has_direct_los and _build_contour_cache only ever compare or difference
## two elevations, and a shared additive constant cancels out of both a
## comparison and a difference identically — flat, open ground reads as
## elevation_baseline_m, not 0m, matching how a real elevation reading
## always would, but nothing about line-of-sight masking changes.
static func elevation_m(pos_px: Vector2) -> float:
	var pos_m: Vector2 = pos_px / PIXELS_PER_METER
	var total: float = CURRENT_MAP.get("elevation_baseline_m", 0.0)
	for hill in CURRENT_MAP.hills:
		var offset: Vector2 = pos_m - hill.center_m
		var d: float = offset.length()
		var r: float = hill.radius_m * (_hill_radius_warp(hill, offset.angle()) if d > 0.01 else 1.0)
		total += hill.height_m * exp(-(d * d) / (2.0 * r * r))
	return total


## Road/river data now lives in CURRENT_MAP (road_width_m/road_waypoints_m/
## river) — see that dictionary's own doc comment for why.
##
## The river's own blocking geometry, built once from CURRENT_MAP.river's
## `path_m` — a real river (or canal) doesn't run in one straight line,
## and doesn't necessarily run perpendicular to the attacker's own axis
## of advance either (Moshchun's river did; Pervomaiske's canal runs
## roughly PARALLEL to the road instead), so this makes no assumption
## about the path's orientation at all: each leg becomes its own
## blocking rect (that leg's bounding box, padded by the river's half-
## width) via the same rect-crossing check BUILDING zones already use,
## and the one crossing is cut out of whichever leg(s) it actually falls
## on by walking distance ALONG that leg's own direction from the
## crossing point — see _split_leg_around_crossing — rather than assuming
## the crossing sits on a vertical (or any other specific) stretch.
static var _river_segment_rects: Array[Rect2] = []
static var _river_rects_built: bool = false


## Splits the leg (a, b) around `crossing` (all in the same space) into
## whatever survives once a stretch of `gap_half` on each side of it is
## removed — 0, 1, or 2 remaining sub-legs, each still just an (a, b)
## pair. Orientation-agnostic: works identically whether the leg runs
## vertically, horizontally, or diagonally, and whether the crossing
## sits mid-leg or exactly at one of its endpoints (a shared vertex with
## the next/previous leg) — the ONLY assumption is that `crossing` itself
## lies on the segment (a,b), which the map's own data is responsible for
## guaranteeing (a leg that doesn't contain the crossing at all should
## never be passed in here — see the caller's own distance check).
static func _split_leg_around_crossing(a: Vector2, b: Vector2, crossing: Vector2, gap_half: float) -> Array:
	var leg_len: float = a.distance_to(b)
	if leg_len < 0.001:
		return []
	var dir: Vector2 = (b - a) / leg_len
	var t: float = (crossing - a).dot(dir) # how far along the leg, from a, the crossing sits
	var out: Array = []
	if t - gap_half > 0.0:
		out.append([a, a + dir * (t - gap_half)])
	if t + gap_half < leg_len:
		out.append([a + dir * (t + gap_half), b])
	return out


## True if `crossing` lies on the segment (a, b) — collinear AND between
## the endpoints, with a small tolerance for the map data's own precision.
static func _crossing_is_on_leg(a: Vector2, b: Vector2, crossing: Vector2) -> bool:
	var leg_len: float = a.distance_to(b)
	if leg_len < 0.001:
		return a.distance_to(crossing) < 1.0
	var dir: Vector2 = (b - a) / leg_len
	var t: float = (crossing - a).dot(dir)
	if t < -1.0 or t > leg_len + 1.0:
		return false
	var closest: Vector2 = a + dir * clamp(t, 0.0, leg_len)
	return closest.distance_to(crossing) < 1.0


static func _build_river_rects() -> void:
	if _river_rects_built:
		return
	_river_rects_built = true
	_river_segment_rects.clear()
	if not CURRENT_MAP.has("river"):
		return # not every real place has one — see CURRENT_MAP's own doc comment
	var river: Dictionary = CURRENT_MAP.river
	var path: Array = river.path_m
	var half_w: float = river.width_m / 2.0 * PIXELS_PER_METER
	var crossing: Vector2 = river.crossing_point_m * PIXELS_PER_METER
	var gap_half: float = river.crossing_gap_m * PIXELS_PER_METER
	for i in path.size() - 1:
		var a: Vector2 = path[i] * PIXELS_PER_METER
		var b: Vector2 = path[i + 1] * PIXELS_PER_METER
		var legs: Array = [[a, b]]
		if _crossing_is_on_leg(a, b, crossing):
			legs = _split_leg_around_crossing(a, b, crossing, gap_half)
		for leg in legs:
			var p0: Vector2 = leg[0]
			var p1: Vector2 = leg[1]
			var min_x: float = min(p0.x, p1.x) - half_w
			var max_x: float = max(p0.x, p1.x) + half_w
			var min_y: float = min(p0.y, p1.y) - half_w
			var max_y: float = max(p0.y, p1.y) + half_w
			_river_segment_rects.append(Rect2(min_x, min_y, max_x - min_x, max_y - min_y))


## True if `pos` sits in the (impassable) river itself, excluding the
## crossing's own gap.
static func is_river_at(pos: Vector2) -> bool:
	_build_river_rects()
	for rect in _river_segment_rects:
		if rect.has_point(pos):
			return true
	return false


## True if the straight segment from `from` to `to` crosses the river
## outside the crossing's own gap — same convention as path_crosses_building.
static func path_crosses_river(from: Vector2, to: Vector2) -> bool:
	_build_river_rects()
	for rect in _river_segment_rects:
		if _line_crosses_rect(from, to, rect):
			return true
	return false


## The one crossing point, in pixel space — there's only one, so unlike
## nearest_cover_point this doesn't need to search anything; `from`/`to`
## are accepted (rather than a bare getter) purely so every existing call
## site written for that signature keeps working unchanged regardless of
## which map — and which orientation of river — is actually loaded.
static func nearest_river_crossing(_from: Vector2, _to: Vector2) -> Vector2:
	return CURRENT_MAP.river.crossing_point_m * PIXELS_PER_METER


## The road's waypoints converted to pixel space, for BattleManager to build
## the enemy's march path from directly.
static func road_waypoints_px() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for wp in CURRENT_MAP.road_waypoints_m:
		out.append(wp * PIXELS_PER_METER)
	return out


## The drone's OWN default search pattern when it has no better lead (see
## BattleManager._sweep_candidates) — deliberately NOT the same list as
## CURRENT_MAP.road_waypoints_m above. That road is where enemy SQUADS march, but a
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
## see BattleManager._sweep_candidates, which feeds these in as each cell's
## base value in the shared routine-recon pool. Row 2 is the same y-band as
## the road: the single most
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

## The commander's own standing, doctrinal assumption about which HALF of
## the road's own band is more likely to matter, absent any actual contact
## — see BattleManager._enemy_approach_likelihood, which turns this into a
## smooth per-cell multiplier across DRONE_SEARCH_GRID_COLUMNS_M (a
## SEPARATE axis from DRONE_SWEEP_ROW_WEIGHTS above, which only judges
## the row/y-band). ENEMY_SPAWN_X sits at the map's own eastern edge — the
## enemy's only start line and approach road — so ground near it is simply
## more worth an early look than ground toward the friendly rear, with NO
## contact needed to justify that: it's public knowledge of the terrain,
## the same idiom already used for weighting the road's own y-band.
## MIN (not zero) keeps the west end of the grid a real, if deprioritized,
## possibility rather than ruled out outright — a smooth gradient, not a
## hard cutoff, matching "much more likely," not "certain."
const ENEMY_APPROACH_LIKELIHOOD_MIN: float = 0.1
const ENEMY_APPROACH_LIKELIHOOD_MAX: float = 1.0

## "Possible" enemy mortar locations — the doctrinal counterpart to actual
## detected/known ones (see BattleManager._update_recent_enemy_contacts'
## own doc comment for that half). A real indirect-fire mortar deliberately
## avoids sitting draped over the same open road a rifle squad marches
## down (see DRONE_SEARCH_GRID_COLUMNS_M/ROWS_M's own doc comment on why
## the full grid exists at all, not just a road-hugging sweep) — it wants
## concealment and standoff from the visible line while staying close
## enough to the enemy's own rear to support the advance. This is a
## SEPARATE row bias from DRONE_SWEEP_ROW_WEIGHTS above (which is really
## about where SQUADS concentrate — the road itself), favoring the bands
## just off the road instead of the road's own row, added on top rather
## than replacing it (see BattleManager._sweep_candidates) — the road
## remains the single most valuable row overall (worth checking for BOTH
## squads and, to a lesser extent, a mortar sited just off it), but the
## flanking bands are no longer crushed down to a token weight the way
## they are for pure squad-spotting purposes. Public knowledge of mortar
## deployment doctrine, not secret intelligence about any specific
## position — same idiom as the road-band weighting itself.
const DRONE_MORTAR_HUNT_ROW_WEIGHTS: Array[float] = [0.05, 0.35, 0.05, 0.35, 0.05]

## Once an enemy unit is confirmed no longer any kind of threat — DESTROYED,
## WITHDRAWN, or SURRENDERED, the same "not still a threat" boundary
## _known_enemy_positions itself already draws — the ground it was last
## known to occupy is genuinely known-clear, real information gained
## through play, not a static bias like the road-band weighting above (see
## BattleManager._area_confirmed_clear/_sweep_candidates). A
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

## A softer, TEMPORARY counterpart to the permanent "confirmed clear" bias
## above — see BattleManager._drone_destination_recency_multiplier. Shared
## across BOTH sweep cells and flank-watch bearings now that the two
## compete in one pool (BattleManager._drone_routine_recon_target): the
## drone's own re-picks could otherwise keep bouncing straight back to a
## spot it just left (nothing there is real, hard-won information too,
## it's just not permanent the way a confirmed kill is — an enemy unit
## could still walk into that same ground later), spending a lot of time
## "concentrating" on one area while genuinely unchecked ground sits
## untouched. Not as severe as the permanent penalty (0.2 vs. 0.15) since
## this is weaker, temporary evidence, and it fully decays rather than
## staying suppressed forever.
const DRONE_DESTINATION_RECENTLY_VISITED_MIN_WEIGHT_MULTIPLIER: float = 0.2
## How long "I was just there" keeps suppressing a candidate's own value —
## a judgment call, not sourced: long enough that the drone actually
## spreads out over the grid instead of thrashing between a couple of
## favored spots, short enough that a genuinely quiet area doesn't stay
## permanently under-checked for the whole battle.
const DRONE_DESTINATION_RECENTLY_VISITED_COOLDOWN_S: float = 20.0 * 60.0

## Distance cost applied per pixel in BattleManager._pick_best_drone_
## destination's value/recency/distance formula — the routine-recon pool's
## candidates (sweep cells ~850m/~170px apart, flank-watch bearings out at
## MORTAR_FLANK_THREAT_RADIUS) are far enough apart that a bare value/
## recency comparison alone would happily send the drone clear across the
## map for a marginally fresher cell right next to one it's already near.
##
## Halved from an original 0.0005 once real play showed the problem this
## was guarding against had flipped direction. _enemy_approach_likelihood
## and DRONE_MORTAR_HUNT_ROW_WEIGHTS (added later) widened the real value
## spread across the map considerably — a genuinely hot cell far to the
## east can now be worth meaningfully more than a mediocre one nearby. At
## the old rate, that real value advantage lost outright to flank-watch
## candidates, which sit close to the mortar (and so close to the drone's
## own launch point) purely by construction: at true battle start, a nearby
## flank bearing (value 0.5, ~300px away) beat the single hottest sweep
## cell (value 0.64, ~600px away) by a hair, sending the drone to check the
## mortar's own doorstep instead of the enemy's actual likely approach —
## exactly backwards from the whole point of the approach-likelihood bias.
## At this rate, crossing a full sweep-grid leg (~170px) still costs a real
## ~0.043 — comparable to a meaningful fraction of a DRONE_SWEEP_ROW_
## WEIGHTS step — so nearby, modest opportunities can still win over
## distant, only marginally better ones; it just no longer overrides a
## genuinely large value gap at long range the way the old rate did.
const DRONE_DESTINATION_DISTANCE_COST_PER_PX: float = 0.00025

## A flank-watch bearing's own base value in the shared routine-recon pool
## (BattleManager._flank_watch_candidates) — tuned near the top of
## DRONE_SWEEP_ROW_WEIGHTS's own range (0.6 for the road's own band) since
## watching an exposed flank gap is roughly as worth a look as checking the
## single most likely sweep area, not something that should always win or
## always lose against it outright.
const DRONE_FLANK_WATCH_BASE_VALUE: float = 0.5

## The floor of BattleManager._flank_watch_plausibility's time-gated
## discount — a bearing the enemy could not plausibly have reached yet is
## heavily discounted, not zeroed out entirely (still possible, e.g. an
## unusually fast probe or a threat this model doesn't otherwise account
## for). Same floor value and "still possible, not ruled out" reasoning as
## ENEMY_APPROACH_LIKELIHOOD_MIN, applied to a different axis (time here,
## not direction).
const DRONE_FLANK_WATCH_EARLY_DISCOUNT_MIN: float = 0.1


# Attacking force size, rolled once per battle (see
# BattleManager.roll_enemy_force_size) — a real attack isn't always the
# same size. Squad count is the PRIMARY roll, a two-piece mixture: with
# probability (1 - ENEMY_SQUAD_COUNT_TAIL_CHANCE) it's uniform across the
# ORDINARY range (ENEMY_SQUAD_COUNT_MIN..MAX, every value equally likely,
# same as before); the rest of the time it's uniform across the RIGHT
# TAIL instead (MAX+1..TAIL_MAX) — a real assault is usually a company-
# minus-sized probe, occasionally something much larger, not a smooth
# gradient between the two. Mortar count is derived FROM the squad count
# (roughly squads / ENEMY_SQUAD_PER_MORTAR_RATIO, jittered by ENEMY_
# MORTAR_COUNT_JITTER before being clamped into its own range) rather
# than the other way around, same as before — but the jitter itself is
# now wide enough relative to the ratio that a real mismatch (8 squads
# fielding just 1 mortar, say) is an occasional, not just theoretical,
# outcome, rather than the tight ±1 band that used to keep the derived
# count almost mechanically tied to the ratio.
const ENEMY_MORTAR_COUNT_MIN: int = 1
const ENEMY_MORTAR_COUNT_MAX: int = 5
const ENEMY_SQUAD_COUNT_MIN: int = 2
const ENEMY_SQUAD_COUNT_MAX: int = 10
const ENEMY_SQUAD_COUNT_TAIL_MAX: int = 15
const ENEMY_SQUAD_COUNT_TAIL_CHANCE: float = 0.15
const ENEMY_SQUAD_PER_MORTAR_RATIO: float = 3.0
const ENEMY_MORTAR_COUNT_JITTER: int = 2

## Perpendicular-ish y offsets for `n` enemy squads — see
## CURRENT_MAP.enemy's squad_spread_min/max_offset_m.
static func enemy_squad_y_offsets_m(n: int) -> Array[float]:
	var out: Array[float] = []
	if n <= 1:
		out.append(0.0)
		return out
	var enemy: Dictionary = CURRENT_MAP.enemy
	var span: float = enemy.squad_spread_max_offset_m - enemy.squad_spread_min_offset_m
	for i in n:
		out.append(enemy.squad_spread_min_offset_m + i * span / float(n - 1))
	return out


## Rear mortar positions for `n` enemy mortars — see CURRENT_MAP.enemy's
## mortar_rear_x_m/mortar_spread_min/max_y_m.
static func enemy_mortar_positions_m(n: int) -> Array[Vector2]:
	var enemy: Dictionary = CURRENT_MAP.enemy
	var out: Array[Vector2] = []
	if n <= 1:
		out.append(Vector2(enemy.mortar_rear_x_m, (enemy.mortar_spread_min_y_m + enemy.mortar_spread_max_y_m) / 2.0))
		return out
	var span: float = enemy.mortar_spread_max_y_m - enemy.mortar_spread_min_y_m
	for i in n:
		out.append(Vector2(enemy.mortar_rear_x_m, enemy.mortar_spread_min_y_m + i * span / float(n - 1)))
	return out

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

# BattleHistoryViewer's own "Play" button (post-battle replay, unrelated to
# the live battle's own time scale above): 1 real second = 1 tactical
# minute, same felt pace as TIME_SCALE_NORMAL's "worth watching closely"
# rate, since a replay is exactly that. Fire flashes during replay fade over
# a tactical-time window scaled the same way a real flash's 0.3-real-second
# fade would look at this rate (0.3 * 60 = 18 tactical seconds) — brief
# relative to playback, not a lingering marker.
const HISTORY_PLAYBACK_TIME_SCALE: float = 60.0
const HISTORY_FIRE_FLASH_DURATION_TACTICAL_S: float = 18.0
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
static var ENEMY_SAFE_X: float
const PLAYER_RETREAT_SPEED: float = 2.0 * PIXELS_PER_METER

## The true world edge is -WEST_FLANK_WIDTH_PX; this stays 100m short of it
## so a retreat never ends literally on the map boundary. Used to be a
## shallower "ordinary" line near the old map's own edge (x=0), reached
## before the west flank instead, with a deeper escalation only for a unit
## still under pressure there — that made sense back when the camera only
## panned into the west flank on demand, so most retreats never needed to
## reveal it. Now that the viewport is permanently wide and the west flank
## is always on screen (see CAMERA_VIEWPORT_WIDTH_PX), stopping at the old
## shallow line just reads as stopping in the middle of visible ground for
## no reason — every player retreat now goes all the way to the real edge.
static var PLAYER_SAFE_X: float # -(WEST_FLANK_WIDTH_M - 100.0) * PIXELS_PER_METER

## The final retreat leg's straight dash (see BattleManager._step_retreat)
## bends laterally away from the single nearest known threat once it's
## within reacting distance — real troops falling back don't walk a
## compass-straight line through ground they know the enemy is on, and
## once the enemy can be somewhere other than dead ahead (a flanking
## squad in the west flank, say), a pure x-only dash could walk a
## retreating unit straight past or even into one. Reactive, not planned
## in advance: re-evaluated every tick against whatever's currently known,
## so it responds immediately if a threat is spotted mid-retreat and
## relaxes just as immediately once it's no longer close enough to matter.
## Fraction of retreat_speed divertable to the lateral correction at
## maximum urgency (the threat right on top of the retreat line) — well
## under 1.0 so a unit under threat still makes real forward progress
## toward safety throughout, never stalling to purely sidestep.
const RETREAT_THREAT_STEER_FRACTION: float = 0.6

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

# Spotting. Named _PER_TACTICAL_SECOND, not just _PER_SECOND, on purpose —
# CombatResolver.roll_spot multiplies this by scenario_delta (tactical
# seconds), matching every other rate constant in this game, after a real
# bug where it was fed real elapsed_time instead: at TIME_SCALE_NORMAL
# (60x) alone, a target in plain view for a real 10 seconds — 30 tactical
# MINUTES — could still go entirely unspotted, since the roll only ever
# accumulated real-world seconds' worth of chance.
const DETECTION_BASE_RANGE: float = 900.0 * PIXELS_PER_METER
const DETECTION_ELEVATION_BONUS: float = 500.0 * PIXELS_PER_METER # added when spotter is higher than target
const SPOT_CHANCE_PER_TACTICAL_SECOND: float = 0.15
const MOVING_SPOT_MULTIPLIER: float = 3.0

## How long (tactical seconds) the MOVING_SPOT_MULTIPLIER bonus takes to
## fade back to 1.0 after a unit actually stops — see Unit.seconds_
## stationary/CombatResolver.roll_spot. A unit that's JUST halted hasn't
## thereby become as hard to notice as one that's been sitting still the
## whole time: real movement leaves a lingering signature behind it
## (settling dust, a thermal bloom, foliage that hasn't sprung back) —
## exact persistence times aren't something published research quantifies
## cleanly, so this is a judgment call, not cited, same as every other
## probability in this file — sized to a few tactical minutes, the same
## rough order of magnitude as this file's other short-lived "how long
## does recent evidence stay meaningful" windows (HEATMAP_RECENTLY_
## CLEARED_COOLDOWN_S, DRONE_CONTACT_BONUS_EXPIRY).
const RECENT_MOVEMENT_SIGNATURE_DECAY_S: float = 240.0

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

# A mortar crew, same idea as the spotter above: real siting/camouflage
# doctrine (dug in, netted, tucked into vegetation) makes a well-hidden
# gun genuinely hard to notice even with clear line of sight to it — but
# not impossible outright the way a categorical "never visible" rule
# would claim. This is a SEPARATE, probabilistic layer underneath the
# hard geometric one: a mortar genuinely masked by a hill (has_direct_los
# blocked outright) is already fully protected regardless of any of this;
# this only ever matters once LOS is actually clear, deciding how hard
# the crew is to spot given real camouflage discipline (hidden in
# TREES) vs. none at all (caught in the OPEN). Applies to both sides'
# mortars symmetrically, same as every other detection rule in this file.
const MORTAR_HIDDEN_DETECTION_RANGE: float = 250.0 * PIXELS_PER_METER # replaces detection range entirely when in cover
const MORTAR_EXPOSED_CONCEALMENT_MULTIPLIER: float = 0.8 # applies only when NOT in cover

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
# that's just made contact should have that shift where it looks next, not
# just note the one exact spot and move on. This used to be its own
# dedicated mechanism (a slow circle around the single most dangerous
# visible squad, re-centered every tick) but that meant the ENTIRE drone
# committed to orbiting one spot, and a sighting had no visible effect on
# the broader search at all otherwise. Replaced by BattleManager.
# _contact_search_bonus: a real, recent sighting (of any enemy unit, not
# just the single most dangerous one) now adds value to nearby candidates
# in the shared routine-recon pool (BattleManager._sweep_candidates/
# _flank_watch_candidates) instead, so the search is drawn toward it
# without abandoning everything else — see that function's own doc
# comment. The single most dangerous visible squad still gets flown at
# directly (BattleManager._drone_search_target's own tier 4), for the
# separate reason that an active, closing threat is worth watching
# directly regardless of what else might be nearby.
const DRONE_CONTACT_BONUS_RADIUS: float = 900.0 * PIXELS_PER_METER # a bit more than the sweep grid's own ~750-850m cell spacing, so a sighting's influence genuinely reaches the next cell over, not just its own cell
const DRONE_CONTACT_BONUS_EXPIRY: float = 600.0 # tactical seconds — matches DRONE_MORTAR_FIRE_LEAD_EXPIRY's own "how long is a lead still worth acting on" reasoning
const DRONE_CONTACT_BONUS_VALUE: float = 0.5 # comparable to the sweep grid's own top row weight (0.6) and DRONE_FLANK_WATCH_BASE_VALUE — a real, recent contact is roughly as compelling as the single most likely area to check anyway, not an automatic trump card

## The enemy heat-map overlay's own "just confirmed clear" discount (see
## BattleManager._heatmap_recently_cleared_multiplier/estimated_enemy_
## likelihood) — a genuinely separate concept from DRONE_DESTINATION_
## RECENTLY_VISITED_COOLDOWN_S above, which is about search EFFICIENCY
## (don't immediately re-check the same spot). This one is about physical
## PLAUSIBILITY: a real enemy squad moves far slower than the drone does,
## so ground just confirmed empty is unlikely to already have an enemy
## back in it — not impossible, just unlikely, hence a real minimum
## rather than a hard zero.
##
## The actual cooldown is DISTANCE-scaled, not a flat window: how long
## full suspicion takes to rebuild is however long it would take someone
## on foot, at HEATMAP_INFILTRATION_SPEED, to walk here from the nearest
## enemy position we actually know about (see
## _heatmap_recently_cleared_multiplier) — a flat few minutes was
## reasonable for one grid cell's own width, but badly wrong once a WIDE
## area gets cleared at once: a spot a kilometer from anything we've ever
## seen doesn't become suspect again just because the same fixed clock
## ran out everywhere else too.
##
## HEATMAP_INFILTRATION_SPEED is deliberately well under REPOSITION_
## SPEED's own 1.8 m/s (6.5 km/h) — that's an ordinary, unconcerned
## repositioning pace; this is someone carrying a load specifically
## trying NOT to be seen, closer to a real "slow, deliberate, cover-to-
## cover" tactical movement rate than a normal walking pace. A judgment
## call, not cited, same as every other probability in this file: about
## 1 km/h — a kilometer in 5 minutes (12 km/h) is clearly not something a
## covert foot patrol does; a kilometer in roughly an hour is.
const HEATMAP_INFILTRATION_SPEED: float = 0.28 * PIXELS_PER_METER # ~1.0 km/h
const HEATMAP_RECENTLY_CLEARED_MIN_MULTIPLIER: float = 0.05

# A unit caught moving in the open is much easier to hit by DIRECT fire, not
# just to spot — it has broken cover to advance (or to retreat). See
# CombatResolver.
const MOVING_HIT_MULTIPLIER: float = 1.6

## DIRECT fire gets a real, independent lethality bonus the closer the
## range — the effective danger space a rifle squad can actually control
## accurately shrinks fast with distance, on top of whatever cover the
## target does or doesn't have. Shaped to match real infantry-combat data,
## not a straight-line guess: the US Army's 1948 Operations Research Office
## study of roughly 3 million WWII/Korea casualty reports found hit
## probability "satisfactory only up to 100 yards, declining rapidly
## beyond," with the vast majority of engagements — and hits — occurring
## within 300 yards even though rifles were effective to nearly 3x that;
## separately, 1960s-era M16 test data put 50% hit probability on a
## STATIONARY man-sized target at roughly 250m under favorable range
## conditions (combat stress drives real figures well below that). That's a
## front-loaded curve — most of the advantage concentrated at genuinely
## close range, a rapid initial falloff, then a long, nearly-flat tail — not
## a straight line from 2x at the muzzle down to 1x at max range. Modeled
## here as exponential decay (see CombatResolver.resolve_fire): `1.0 +
## (this - 1.0) * exp(-distance_m / SQUAD_CLOSE_RANGE_DECAY_M)`. At the
## chosen SQUAD_CLOSE_RANGE_DECAY_M (150m), that's ~1.72x still at 50m,
## ~1.55x at 100 yards (still "satisfactory"), down to ~1.16x by 300 yards
## and ~1.03x by SQUAD_ENGAGEMENT_RANGE (400m) itself — genuinely brutal at
## point-blank, and correctly back near baseline by the range real data
## says most rifle lethality has already dropped off. Stacks with
## SQUAD_COVER_MULTIPLIER's own OPEN entry; TREES/BUILDING's tiny
## multipliers mean even the doubled close-range bonus still lands on a
## small number, so cover keeps doing its job regardless of range. Direct
## fire only — a mortar's plunging indirect fire doesn't get easier to aim
## just because the target happens to be closer to the tube.
const SQUAD_CLOSE_RANGE_HIT_MULTIPLIER: float = 2.0
const SQUAD_CLOSE_RANGE_DECAY_M: float = 150.0 * PIXELS_PER_METER

# MORTAR fire against a moving target is the opposite story: indirect fire
# has to be aimed at where the target WILL be, which only works if the
# movement is predictable (the enemy's steady road march — see
# Unit.movement_predictable). Erratic, reactive movement (diving for cover,
# retreating) is hard to lead-aim against — a real hit-chance penalty, not
# just "no bonus."
const MORTAR_PREDICTABLE_MOVING_MULTIPLIER: float = 1.1
const MORTAR_UNPREDICTABLE_MOVING_MULTIPLIER: float = 0.25

## A continuous, real-time video feed genuinely makes indirect fire more
## accurate than a ground spotter ever can — modern reporting on drone-
## directed artillery/mortar fire in Ukraine cites accuracy improvements on
## the order of 200-250% (roughly doubled to tripled) over ground-observer-
## adjusted fire, plus a dramatically shorter sensor-to-shooter cycle (a
## Russian account put UAV-cued fire at 3-5 minutes versus roughly 30
## minutes without one) — a drone operator watches the round actually land
## and corrects the next one immediately, where a ground observer needs
## line of sight to both the target AND the impact, is limited to what's
## visible from one fixed position, and passes corrections by voice. Set
## conservatively within that cited range (not the high end) so even the
## single most favorable case (a fully exposed target in the open) still
## isn't a mathematical certainty — see CombatResolver.resolve_fire, applied
## only to the PLAYER's own mortar (the only one with a doctrine-level
## SPOTTER/DRONE_TEAM choice at all) and only while a friendly drone is
## actually airborne to provide it, not merely available in principle.
const DRONE_DIRECTED_MORTAR_ACCURACY_MULTIPLIER: float = 1.75

# Direct-fire (squad) engagement range — a squad can only fire at a target
# IT could plausibly see and reach with its own weapons, unlike a mortar
# (see below).
const SQUAD_ENGAGEMENT_RANGE: float = 400.0 * PIXELS_PER_METER

# A mortar fires indirectly on spotter-relayed information — no LOS
# requirement of its own, and firing does not automatically reveal one to
# enemy squads the way a rifle's muzzle flash does. But it is NOT unlimited
# range: a real light/medium mortar tops out well short of the whole map.
#
# Raised from an earlier, uncited 3500m to real, recent (2023-2024) 82mm
# figures from this exact war: reporting on Ukrainian-produced 82mm mortar
# shells cites a max range of 4500m, and Russia's currently-issued 2B24
# 82mm light mortar is rated to 6000m — both well above the older Soviet-
# era 82-BM-37's own 3040m, which the previous 3500m figure was closer to
# despite not actually citing it. Set at the conservative end of that
# 4500-6000m range, not the high end, matching this file's own established
# practice for a cited range with real uncertainty in it (see
# DRONE_DIRECTED_MORTAR_ACCURACY_MULTIPLIER's identical reasoning). Found
# to matter concretely, not just cosmetically: at the old 3500m, a direct
# empirical check found the median real distance between the two sides'
# own mortar positions on this game's current (larger, right-tailed-
# assault) maps already exceeded it — cross-mortar counter-battery duels
# were geometrically impossible more often than any hold/scoot chance
# tuning could ever compensate for.
const MORTAR_MAX_RANGE: float = 5000.0 * PIXELS_PER_METER

## Squad tactics: the enemy tries to flank toward the friendly mortar (see
## BattleManager._enemy_advance_objective/_score_advance_candidate), and
## friendly squads answer by screening it and by not letting themselves get
## surrounded (see BattleManager._update_friendly_squad_positioning).
##
## A candidate advance point within SQUAD_ENGAGEMENT_RANGE and direct LOS of
## a known player position is walking straight into that squad's kill zone
## rather than around it — a real tactical cost on top of simply not
## qualifying for the concealment bonus (ENEMY_ADVANCE_CONCEALMENT_BONUS),
## which only rewards being COMPLETELY unseen. This is what actually makes
## routing wide around a known defender pay off over walking up to it.
const ENEMY_ADVANCE_EXPOSURE_PENALTY: float = 2.5

# How far out a friendly squad watches for known enemies converging on it
# from multiple directions at once (BattleManager._reposition_for_
# encirclement) — bigger than SQUAD_ENGAGEMENT_RANGE so a squad can react to
# being flanked before the encircling enemies are actually already in range
# to fire.
const FRIENDLY_ENCIRCLEMENT_DETECT_RADIUS: float = 600.0 * PIXELS_PER_METER

## The angular arc (degrees, as seen from the squad) that known nearby
## enemies have to span before a position counts as genuinely surrounded —
## two contacts roughly in the same direction is just "the enemy is over
## there," not encirclement; contacts spread across most of the compass
## rose is the real, hopeless case this is meant to catch.
const FRIENDLY_ENCIRCLEMENT_ANGLE_THRESHOLD_DEG: float = 140.0

## "Surrounded by enemies under cover" is the specific fear this doctrine
## calls out — not just outnumbered from multiple sides, but by contacts
## already dug in and hard to dislodge. At least this fraction of the
## nearby, encircling contacts have to actually be sitting in TREES/BUILDING
## terrain (GameConfig.is_in_cover) for a squad to treat its position as
## genuinely hopeless and pull back rather than stand and fight it out.
const FRIENDLY_ENCIRCLEMENT_MIN_COVERED_FRACTION: float = 0.5

## The three FRIENDLY_ENCIRCLEMENT_* thresholds above, at full
## BattleManager._scheduled_retreat_urgency (an overall retreat is already
## planned and the scheduled time is close or past) — a real unit that
## knows the whole line is pulling out soon doesn't hold a marginal
## position as stubbornly as one with no such order at all, so all three
## relax together: watch farther out, accept a narrower surrounding arc,
## and need less of it actually dug into cover before treating the
## position as not worth holding. `_reposition_for_encirclement` linearly
## interpolates between the two sets of values by urgency, so these only
## ever matter once a retreat is actually scheduled — judgment calls, not
## cited, same as every other probability in this file.
const FRIENDLY_ENCIRCLEMENT_DETECT_RADIUS_URGENT: float = 900.0 * PIXELS_PER_METER
const FRIENDLY_ENCIRCLEMENT_ANGLE_THRESHOLD_URGENT_DEG: float = 80.0
const FRIENDLY_ENCIRCLEMENT_MIN_COVERED_FRACTION_URGENT: float = 0.2

## How long before a scheduled retreat's actual time counts as "close" for
## BattleManager._scheduled_retreat_urgency — comfortably ahead of it,
## urgency reads near 0 (no change from normal behavior); within this
## window, it ramps up toward 1.0 as the scheduled time approaches. Sized
## to roughly how long a real fighting withdrawal takes to actually
## organize once ordered, not an instant switch the moment the order is
## given.
const SCHEDULED_RETREAT_URGENCY_WINDOW_S: float = 1200.0 # 20 tactical minutes

# Bounded step (like ENEMY_ADVANCE_RUSH_DISTANCE) for a friendly squad
# repositioning toward its own side's center of mass rather than standing
# to be surrounded — reassessed next tick rather than committing to the
# whole distance at once, same "advance/reposition by bounds" idiom.
const FRIENDLY_REPOSITION_RUSH_DISTANCE: float = 300.0 * PIXELS_PER_METER

# How close a known enemy has to get to the friendly mortar's OWN actual
# position (not the enemy's own, possibly stale, fix on it — the player's
# side always knows exactly where its own gun is) before it counts as a
# real flanking threat worth a squad breaking off to screen.
const MORTAR_FLANK_THREAT_RADIUS: float = 1500.0 * PIXELS_PER_METER

# A friendly squad "screens" an approach if it sits within this distance of
# the straight line between a threatening enemy and the mortar, somewhere
# between the two — close enough that the enemy would have to fight past it
# (or at least through its engagement range) to actually reach the gun.
const MORTAR_FLANK_CORRIDOR_WIDTH: float = 300.0 * PIXELS_PER_METER

# Where a squad answering an open flanking lane actually takes position:
# on a ring at this radius around the mortar, on the bearing toward the
# threat — directly interposed between the two, not all the way out at the
# threat's own position (which could be a long, unnecessary march for a
# threat that's still distant, and would abandon the mortar's other flanks).
const MORTAR_PROTECTIVE_RADIUS: float = 350.0 * PIXELS_PER_METER

## The drone's own flank-watch search (BattleManager._flank_watch_
## candidates): a fixed ring of compass bearings around the friendly mortar,
## checked at MORTAR_FLANK_THREAT_RADIUS out — the same distance that
## already defines "close enough to be a real threat" for the friendly
## squads' own screening behavior, so the drone is watching exactly the
## zone an unscreened approach would actually trigger a squad response in.
## 8 bearings (every 45°) is coarse — a real patrol pattern, not pixel-
## perfect coverage — deliberately, since this is meant to catch a
## developing flanking approach in the open country around the mortar, not
## to replace the squads' own close-in screening.
const DRONE_FLANK_WATCH_BEARINGS_DEG: Array[float] = [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]

## Once the drone arrives within this radius of its current flank-watch
## point (or that bearing stops qualifying — see BattleManager.
## _flank_watch_candidates/_drone_routine_recon_target), it picks a new one
## rather than parking there for the rest of the battle.
const DRONE_FLANK_WATCH_ARRIVE_RADIUS: float = 150.0 * PIXELS_PER_METER

## The routine-recon tier's OUTER competing value (see BattleManager.
## _drone_search_target's own tier-6 doc comment) whenever flank-watch
## actually has at least one open bearing to check right now — deliberately
## NOT scaled by _mortar_existence_confidence() the way the general sweep's
## own outer value is. Watching the mortar's blind side is a standing duty
## that matters regardless of how confident anyone is that a SECOND mortar
## exists; tying its relevance to that confidence meant it could fade below
## an already-spotted squad's own tracking priority (TARGET_PRIORITY_
## SQUAD_MAX = 10) well before a typical battle ends, letting the drone
## fixate on one contact and stop checking the mortar's flanks entirely.
## Set comfortably above that squad-tracking ceiling for the same reason
## the old, pre-merge TARGET_PRIORITY_FLANK_WATCH (30) was: catching a
## flanking squad before it ever reaches the mortar is worth more than
## continuing to watch one already-known contact.
const DRONE_FLANK_WATCH_STANDING_PRIORITY: float = 30.0

## How far along a retreating unit's OWN remaining route (BattleManager.
## _retreat_route_scout_target) the drone screens ahead of it once a
## general retreat is ordered — 0.0 would just watch the unit's current
## position (already covered by its own eyes as it walks), 1.0 would sit
## right on top of its final destination before it's even close. A
## judgment call, not cited, same as every other probability in this file:
## far enough out to actually give useful early warning, not so far that
## it's watching empty ground nobody's anywhere near yet.
const DRONE_RETREAT_SCOUT_LOOKAHEAD_FRACTION: float = 0.6

# Limited ammunition — every mortar team on both sides starts with this
# many rounds (see Unit.setup) and has to actually manage it, not just
# reload for free forever. See BattleManager's request_mortar_resupply/
# _update_mortar_resupply/_spawn_resupply_run for the full request ->
# wave-arrival -> physical delivery-run pipeline this drives.
const MORTAR_STARTING_AMMO: int = 20
const MORTAR_RESUPPLY_ROUNDS: int = 20

## How much a crew keeps on hand at the firing position at all, on top of
## what it's already carrying — a real position doesn't have unlimited pit
## storage, and it isn't realistic to hand-carry a large surplus through
## every shoot-and-scoot displacement either (the tube, base plate, and
## bipod are already a multi-man carry on their own; each round is close to
## 10 lb). Real logistics doctrine backs the shape of this even without a
## single precise "rounds per tube" figure to cite: a unit keeps a
## prescribed "basic load" on hand to sustain it until the next resupply,
## with the bulk of any surplus deliberately staged/cached farther back
## (an ammunition supply point, not piled at an exposed forward position)
## rather than pushed all the way forward "just in case." A modest 1.5x the
## starting load reflects a slightly-larger-than-initial ready pit, not a
## second full load sitting exposed next to the gun. See
## _update_mortar_resupply's arrival handling for how a wave actually gets
## held back (never dispatched at all) once the position is already at
## this ceiling, rather than a run walking all the way up only to be
## capped/wasted on arrival.
const MORTAR_MAX_AMMO_ON_HAND: int = 30

# A resupply run's delay from the moment it's requested — genuinely random,
# not a fixed countdown, modeled as log-normal (right-skewed: it can run
# late by a lot more than it can ever run early) with the requested MEDIAN,
# not mean — see GameConfig.sample_resupply_delay. SIGMA is the log-space
# spread; 1.0 puts a 2-hour wait at roughly the 75th percentile (a real,
# fairly common outcome, not a rare tail one) while keeping the 60-minute
# MEDIAN itself unchanged — at this spread, roughly the middle two-thirds
# of outcomes fall between ~22 and ~163 minutes, with a real (if unlikely)
# tail well beyond that, and only a small chance of arriving under a
# third of the median time.
const MORTAR_RESUPPLY_DELAY_MEDIAN: float = 60.0 * 60.0 # tactical seconds
const MORTAR_RESUPPLY_DELAY_SIGMA: float = 1.0
# The second wave's delay is measured from the FIRST wave's own (already
# random) arrival, not from the original request — "a further 20 rounds
# will arrive after approximately another hour" reads as one more hour on
# top of the first, not a fixed ~2 hours from the request. Both waves are
# scheduled at request time regardless of how wave 1 actually turns out
# (including if it fails) — see request_mortar_resupply.
const MORTAR_RESUPPLY_WAVE_COUNT: int = 2

# Every resupply run, independently, can simply fail to get through —
# nothing wrong with the request itself, the convoy just doesn't make it.
const MORTAR_RESUPPLY_FAILURE_CHANCE: float = 0.10

# The "roughly 15 minutes out" heads-up — deliberately NOT computed as
# exactly (true arrival time - 15 minutes), which would make the estimate
# perfectly accurate by construction. Real ETAs are themselves estimates:
# this fires once the ACTUAL remaining time first drops to a value drawn
# from its own distribution centered on 15 minutes, so the stated "roughly
# 15 minutes" can and sometimes will be meaningfully wrong by the time the
# run actually arrives (or fails) — matching "this guess might again prove
# to be incorrect" directly, not just as flavor text.
const MORTAR_RESUPPLY_ETA_WARNING_MEDIAN: float = 15.0 * 60.0 # tactical seconds
const MORTAR_RESUPPLY_ETA_WARNING_SIGMA: float = 0.35

# Whether to hold fire on a SQUAD target to conserve ammunition (an enemy
# mortar target is never subject to this at all — see BattleManager.
# _pick_target — "that shot should always be taken") is a genuine sliding
# scale, not a hard cutoff: "five shots remaining should never be a magical
# number." Two independent factors, both continuous, combine into one
# hold-fire PROBABILITY (see BattleManager._pick_target/_mortar_ammo_
# scarcity/_mortar_resupply_urgency) rather than a deterministic rule:
#   - SCARCITY: how much of a full load is left. 0 at a full
#     MORTAR_STARTING_AMMO load (no inclination to hold at all), ramping
#     linearly up to 1 as rounds approach zero — "the less ammo is left,
#     the greater the inclination to hold some."
#   - URGENCY: how soon resupply is actually expected. 0 with nothing
#     pending or still MORTAR_RESUPPLY_URGENCY_HORIZON_MINUTES or more
#     away, ramping linearly up to 1 as the soonest still-unresolved wave's
#     arrival approaches (or already-arrived-but-uncollected rounds sitting
#     at the resupply point, which count as maximally urgent) — "the sooner
#     resupply is expected, the more willing one should be to fire."
# The actual hold-fire chance is scarcity * (1 - urgency): full ammo never
# hesitates regardless of urgency; empty-handed with nothing coming holds
# almost every time; anywhere in between genuinely slides with both.
const MORTAR_RESUPPLY_URGENCY_HORIZON_MINUTES: float = 30.0

# Once a resupply wave's log-normal delay elapses (see MORTAR_RESUPPLY_
# DELAY_MEDIAN/SIGMA), rounds no longer just appear at a rear point — a
# real, physical Unit.Kind.RESUPPLY_RUN sets out across open ground toward
# the mortar's CURRENT position, spottable and targetable exactly like any
# other unit (see BattleManager._spawn_resupply_run/_update_resupply_run_
# targets/_resolve_resupply_run_arrivals). Faster than any dismounted
# unit's pace in this game (compare MORTAR_RELOCATE_SPEED's 2.2 m/s) since
# this represents a light vehicle or a hustling carrying party covering
# ground quickly, not a formed unit's tactical movement — but still no
# armor, no weapon, and a single hit ends it (see Unit.setup's
# Kind.RESUPPLY_RUN case).
const MORTAR_RESUPPLY_RUN_SPEED: float = 7.0 * PIXELS_PER_METER

## How close a resupply run needs to get to the mortar for delivery to
## actually trigger (see BattleManager._resolve_resupply_run_arrivals) —
## deliberately its OWN constant rather than reusing Unit.MOVE_ARRIVE_
## RADIUS (5m), which is tuned for a unit reaching its own empty waypoint,
## not for judging when two DRAWN TOKENS visually look like they've met.
## The mortar's own icon is drawn at a 10px radius and the run's at 6px
## (see Unit._draw) — 50m and 30m respectively at this map's scale — so a
## 5m tolerance leaves a real, visible gap where the two tokens already
## look like they're touching or overlapping on screen well before the
## precise delivery condition would actually fire. Set comfortably inside
## the ~80m distance at which the icons' own edges would touch, so
## delivery completes while they're still visibly closing the last of the
## gap rather than needing to sit exactly on top of one another first.
const MORTAR_RESUPPLY_ARRIVAL_RADIUS: float = 30.0 * PIXELS_PER_METER

# Only worth a mortar actively closing distance toward its own resupply
# point (a real "linkup," see BattleManager's resupply-linkup idle check)
# once it's meaningfully far away — exactly the case a mortar that
# relocated deep into the west flank creates. A mortar already reasonably
# close to its own resupply point has nothing to gain by walking toward it
# early; the run's own move_target already tracks the mortar live either
# way (see Unit.resupply_target_mortar), so closing distance always helps
# once it's actually worth bothering with.
const MORTAR_RESUPPLY_LINKUP_TRIGGER_RANGE: float = 1000.0 * PIXELS_PER_METER

## Log-normal sample with the given MEDIAN (not mean) and log-space SIGMA —
## shared by both resupply-wave delays and the ETA-warning threshold so
## "substantial variability" means the same thing everywhere it's used.
## randfn(0.0, sigma) draws a normal deviate in log-space; exponentiating
## converts it back, which is what makes the result right-skewed (a
## symmetric spread in log-space is an asymmetric one in real time — it can
## run late by a much larger absolute margin than it can run early).
static func sample_resupply_delay(median: float, sigma: float) -> float:
	return exp(log(median) + randfn(0.0, sigma))

# The drone's own TARGET PRIORITY scoring (see BattleManager.
# _drone_search_target/_squad_danger_priority/_mortar_existence_
# confidence) — a general "how urgent is this to watch" scale, not
# hard-coded "if it's a mortar" branching, so a future third target kind
# only needs its own priority term added here, not a rewrite of the
# decision logic itself. A mortar we're actually oriented to engage soon
# (seen live AND matching some active friendly mortar's own hunt-fix —
# see BattleManager._is_priority_hunt_target —, a fresh specific fire-
# detection lead, or an active joint hunt commitment) sits far above
# anything a squad can ever reach — real mortars are simply the bigger
# threat once we're actually going to act on one — while a squad's own
# priority is genuinely variable, scaling with how close it's gotten to
# any friendly unit (SQUAD_DANGER_RANGE: beyond it, a squad isn't yet a
# real threat and scores 0; within it, danger ramps up to
# TARGET_PRIORITY_SQUAD_MAX right at contact). Bumped from the original
# 100 — "the value of an enemy mortar is still not high enough relative
# to a squad" for the cases where we genuinely are going after one, a
# judgment call, not cited. A live-visible mortar with no such near-term
# plan (DRONE_NON_PRIORITY_MORTAR_WATCH_VALUE below) is worth
# meaningfully less than a squad already in real contact — a drone
# doesn't need to hang over every mortar it's ever spotted regardless of
# whether anything's about to be done about it; a bare fire-detection
# lead (real evidence, but a stale position estimate rather than a live
# one) is discounted somewhat but still normally beats any squad.
const TARGET_PRIORITY_MORTAR: float = 150.0
const TARGET_PRIORITY_MORTAR_LEAD_DISCOUNT: float = 0.8
const TARGET_PRIORITY_SQUAD_MAX: float = 10.0

## A confirmed-visible enemy mortar NOBODY on the friendly side currently
## has any hunt-fix pointed at (see BattleManager._is_priority_hunt_
## target) — no joint commitment, no individual mortar's own lead — reads
## as this instead of the full TARGET_PRIORITY_MORTAR. Deliberately below
## TARGET_PRIORITY_SQUAD_MAX (a squad already in real contact should
## usually win the drone's attention over a mortar nothing is currently
## planning to shoot), but still comfortably above 0 — general awareness
## of a found mortar's position still has some standing value even with
## no near-term plan for it, just not enough to justify parking over it
## indefinitely while a real threat goes unwatched.
const DRONE_NON_PRIORITY_MORTAR_WATCH_VALUE: float = 6.0

## How worried the drone's routine background recon (BattleManager.
## _drone_search_target's tier 6) should be about a SECOND enemy mortar
## nobody's found yet — scaled by _mortar_existence_confidence(), which
## decays the longer no mortar fire is detected anywhere. Deliberately its
## own, separate constant from TARGET_PRIORITY_MORTAR (kept at its
## original, pre-bump value) rather than reusing that one: TARGET_
## PRIORITY_MORTAR now prices a mortar we can actually act on — seen live,
## or committed to via a hunt-fix — a fundamentally more certain, more
## valuable case than a merely POSSIBLE undiscovered one. Sharing the same
## bumped value would have let pure speculation about a second mortar
## out-bid a squad already in real, visible contact — exactly backwards
## from wanting a real threat to be able to compete for the drone's
## attention.
const TARGET_PRIORITY_UNDISCOVERED_MORTAR_SWEEP: float = 100.0
const SQUAD_DANGER_RANGE: float = 1200.0 * PIXELS_PER_METER

## Checking whether an enemy is currently flanking around toward the
## mortar's blind side used to be its own outer-tier TARGET_PRIORITY_
## FLANK_WATCH constant, competing directly against squad-danger/
## retreating-enemy/sweep as a fifth candidate. It's since been folded into
## the shared routine-recon pool instead (BattleManager._flank_watch_
## candidates/_drone_routine_recon_target) — see DRONE_FLANK_WATCH_BASE_
## VALUE for its value within that pool now that it's judged the same way
## a sweep cell is (value/recency/distance), not as a fixed priority of its
## own.

# How a MORTAR weighs which non-mortar candidate to actually fire on — see
# BattleManager._enemy_target_value/_pick_target's own doc comment. Equal
# weights on purpose: casualty potential (a target's own current pips,
# capped at 9) and danger (_squad_danger_priority, capped at
# TARGET_PRIORITY_SQUAD_MAX = 10) already land on comparable scales by
# construction, so 1.0/1.0 already balances "a fuller unit is a juicier
# target" against "a dangerous unit is worth hitting even if it's already
# been worn down" without either one dominating outright.
const MORTAR_TARGET_CASUALTY_WEIGHT: float = 1.0
const MORTAR_TARGET_DANGER_WEIGHT: float = 1.0

## Tier 3 of the mortar decision ladder ("destroy dangerous squads") — how
## completely an especially dangerous candidate overrides ammo-conservation
## hold-fire, sliding with BattleManager._target_danger_to_force's own
## 0..TARGET_PRIORITY_SQUAD_MAX scale rather than a threshold ("five shots
## remaining should never be a magical number," the same principle behind
## the existing sliding-scale hold-fire chance itself). A genuinely
## different axis from the existing overrun-range override just below
## _pick_target's hold_fire_chance computation: that one measures danger
## to the CREW (distance to the mortar itself — a tier-1, self-preservation
## question); this one measures danger to the FORCE (_squad_danger_
## priority's own distance-to-nearest-friendly, via _mortar_candidate_
## danger) — both matter, as parallel terms, not one replacing the other.
## At 1.0, a squad already in contact with a friendly (danger at its own
## maximum) fully cancels ammo conservation regardless of distance from
## the mortar; a squad at half that danger only halves it.
const MORTAR_DANGER_HOLD_FIRE_OVERRIDE: float = 1.0

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
# TARGET_PRIORITY_UNDISCOVERED_MORTAR_SWEEP (what finding one would be
# worth) times this confidence (the estimated odds one is actually still
# out there to find).
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

## The player's own mortar's reluctance to open up on a mere squad target
## before ANY enemy mortar has actually been found — a real, previously-
## reported failure mode: firing reveals this position, and if an enemy
## mortar the crew has no idea about is out there, it can answer with
## counter-battery the crew never saw coming. Real fire-support doctrine
## holds indirect fire back during the initial phase of contact
## specifically so reconnaissance gets a chance to establish the enemy's
## own supporting weapons first — but that's a real, informational
## question ("do we understand what the enemy is doing yet"), not a flat
## timer, so this scales by BattleManager._mortar_existence_confidence() —
## already exactly that estimate, built for the drone's own routine-recon
## weighting (see its own doc comment): high right at first contact,
## decaying over MORTAR_CONFIDENCE_DECAY_TAU as no enemy mortar fire is
## detected anywhere, and hard zero once every enemy mortar is confirmed
## destroyed. This constant is the hold chance at that confidence's peak
## (1.0) — a judgment call, not a cited figure, picked by working backward
## from the reported incident's own "give it a couple of minutes" framing:
## at this mortar's own ~30-tactical-second fire-decision cadence
## (Unit.reload_time), a 0.9 peak hold chance means an expected ~10 checks
## (~5 minutes) before firing anyway even at maximum uncertainty, without
## ever being an actual clock — a lucky roll can fire sooner, a run of bad
## luck holds longer, and the whole thing keeps loosening on its own as
## real evidence (or its absence) accumulates. Deliberately player-only
## for now — the enemy's own targeting is intentionally left alone (see
## the tactical-rewrite doctrine doc's "enemy may differ" principle).
##
## Raised from an original 0.75 (~2 minute expected wait) after a repeat
## report of the same failure: this side can field up to ENEMY_MORTAR_
## COUNT_MAX (5) mortars in one battle, and the ORIGINAL hold also stopped
## applying outright the instant ANY lead existed on even ONE of them
## (BattleManager._pick_target no longer gates on enemy_mortar_fix.
## is_empty() for exactly this reason — see that call site's own doc
## comment). Finding one enemy mortar doesn't mean a second, still-
## unaccounted-for one isn't the one that ends up landing a shell here;
## a longer, unconditional hold is the honest fix, not just a bigger
## number covering for the same gap.
const MORTAR_UNKNOWN_ENEMY_HOLD_FIRE_CHANCE: float = 0.9

# A mortar shell doesn't land the instant it's fired — 40 tactical seconds
# of real flight time (see BattleManager._launch_mortar_shot /
# _resolve_pending_mortar_shots). It's aimed at the target's ANTICIPATED
# position, not a live one — if the target moves more than this far from
# that anticipated spot by the time the shell arrives, the round lands on
# empty ground: an outright miss, no roll needed. Roughly a mortar's
# effective burst radius — close enough and it's still in the beaten zone.
const MORTAR_FLIGHT_TIME: float = 40.0 # tactical seconds
const MORTAR_EVASION_RADIUS: float = 40.0 * PIXELS_PER_METER

# Whether the opposing mortar even ATTEMPTS a counter-battery mission
# after this shot (see BattleManager._resolve_mortar_counter_battery) —
# one shared rate, not split by the firing mortar's own shoot-and-scoot
# doctrine. It used to be: 0.22 holding position, 0.06 shoot-and-scoot —
# reasoning that the opposing side wouldn't bother trying against a
# target it expected to already be gone. That's backwards from how real
# counter-battery actually works and from what a bare, uncited comment
# ("it can still be picked up") was ever really claiming: a responding
# crew reacts to a detected firing signature, not a prediction of what
# THIS specific target will do next — real, radar-cued counter-battery in
# this exact war routinely returns fire within under two minutes of
# detection, and reporting on Ukrainian mortar tactics specifically
# frames shoot-and-scoot as a way to avoid EFFECTIVE counter-battery
# fire (i.e., not being there when the round lands), not as something
# that makes the enemy less likely to shoot back at all. That "will it
# actually catch them" half is already modeled separately and correctly
# — _resolve_pending_counter_battery checks, after a real 1-3 minute
# flight delay, whether the target is still near where it fired from —
# so a single shared attempt-chance here doesn't lose the real
# shoot-and-scoot protection, it just stops double-counting it as an
# ALSO-reduced chance of ever being shot at in the first place. Kept at
# the old HOLD rate rather than the old SCOOT rate: "always try" is the
# realistic default; a hold-position mortar's own poor survivability in
# this war comes from actually being caught by the impact, not from
# somehow inviting more return-fire attempts.
const MORTAR_COUNTER_BATTERY_CHANCE: float = 0.22 # per shot

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

# A crew doesn't teleport between "walking" and "ready to fire" — the tube
# has to actually be set down, leveled, and laid (or broken back down and
# shouldered) either way. Real, recent reporting on Russia's currently-
# issued 2B24 82mm light mortar (the same system already cited for
# MORTAR_MAX_RANGE above) states "the transition from traveling to firing
# position, and vice versa, is accomplished in less than 30 seconds" — one
# real figure covering both directions, used here as a floor on Unit.
# seconds_stationary (already tracked for spotting-signature decay — see
# CombatResolver) rather than inventing a separate "set up"/"moving" state
# machine: Unit.Activity's existing STATIONARY/MOVING split, plus how long
# a unit has genuinely BEEN stationary, already is that distinction.
# Gates two things: a mortar can't actually fire (BattleManager.
# _mortar_shot_this_tick) or respond to counter-battery (_resolve_mortar_
# counter_battery) until it's been stationary this long since its last
# real displacement; and a shoot-and-scoot crew doesn't start walking away
# until this long after firing (_queue_mortar_displacement /
# _resolve_pending_mortar_displacement). A mortar that's never moved at
# all defaults to Unit.seconds_stationary = 1e9 (already emplaced since
# before the battle began), so this never delays a hold-position mortar's
# very first shot.
const MORTAR_SETUP_TEARDOWN_TIME: float = 30.0 # tactical seconds

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
# _enemy_target_value, which is why a fuller unit is also a more
# attractive target in the first place. 20% of a unit's CURRENT strength,
# rounded, floored at 1 (a "hit" that costs nothing would read as a
# non-event) and never more than what's actually there to lose. A full
# 9-person squad loses 2 per hit (round(9*0.2)=2); anything at 6 or below
# is back to losing 1, same as the old flat model — the scaling only
# really shows up while a unit is still close to full strength.
const MORTAR_CASUALTY_FRACTION: float = 0.2

static func mortar_casualty_count(current_pips: int) -> int:
	return clampi(int(round(float(current_pips) * MORTAR_CASUALTY_FRACTION)), 1, current_pips)

## "1 rounds" reads as a typo, not a translation of the game state — every
## display of a mortar's ammo count needs this, not just the one place it
## was first noticed.
static func round_count_text(rounds: int) -> String:
	return "%d round" % rounds if rounds == 1 else "%d rounds" % rounds

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

## A mortar crew's decision to keep the gun in action after taking
## casualties, rather than abandon it outright (see Unit._apply_crew_
## casualties) — real doctrine favors cross-leveling a reduced crew to keep
## a crew-served weapon firing rather than automatically abandoning it after
## any casualty (US infantry battle drills treat "man the crew-served
## weapon first, evacuate wounded second" as standard), and Korean War-era
## mortar-position design was explicitly built to let a squad "continue to
## fight, even during intense enemy countermortar fire" (FM 7-90). What
## actually decides it is how much crew is left AND whether the crew itself
## — not just the gun — is in real danger of being overrun by advancing
## enemy infantry, not casualties alone: a crew that's taken a hit from
## long-range counter-battery fire with no ground threat anywhere nearby
## has every reason to patch up and keep firing (possibly relocating first
## — see Unit.evading_counter_battery), where the same casualties with an
## enemy squad closing to within this range is a real, immediate fight-or-
## flight call a real crew makes in favor of flight. Mirrors WOUNDED_ABANDON_
## DANGER_RANGE's own scale — inside it, a known threat reads as realistically
## able to overrun the position; beyond it, the position itself is safe
## enough that only crew strength (not proximity) drives the decision.
##
## Proximity alone, though: whether that's enough on its own to call a
## known enemy a real threat varies by call site. BattleManager._decide_
## mortar_action's own proactive "is anything closing in on us" check
## additionally requires genuine line of sight from the threat to the
## crew's own position (GameConfig.has_direct_los) — a nearby-but-blind
## enemy (terrain in the way) isn't actually a reason to abandon a
## perfectly concealed position. The REACTIVE checks (_mortar_crew_holds_
## position's post-hit hold-or-flee roll, _pick_target's own overrun
## override) don't add that requirement — by the time either of those
## runs, the crew has either already been hit (so something can already
## reach them regardless of this range) or is actively choosing whether
## to spend a round on a candidate already inside normal engagement
## range, a different question than "is anything about to find us."
const MORTAR_CREW_OVERRUN_DANGER_RANGE: float = 600.0 * PIXELS_PER_METER

## How far out a known enemy actually CLOSING on the drone team's ground
## position (see BattleManager._update_drone_team_evasion) starts to be
## worth considering relocating over — an unarmed rear element with no
## crew-served weapon to hold onto, so this is a proactive "would consider
## moving" watch range, not a last-second "must move now" one, and wider
## than MORTAR_CREW_OVERRUN_DANGER_RANGE accordingly. Matches SQUAD_DANGER_
## RANGE's own scale — the same distance at which a squad starts reading as
## a live threat to anyone else.
const DRONE_TEAM_EVASION_RANGE: float = 1200.0 * PIXELS_PER_METER

## A hit that lands on/near a mortar position can set off its OWN stored
## rounds in a secondary explosion ("cook-off" — a well-documented real
## phenomenon: a round already primed by heat/blast can detonate and
## sympathetically set off adjacent stacked rounds). No source found gives
## a hard probability for this happening to a field mortar position
## specifically — this is a judgment call, not a cited figure — but the
## qualitative logic is solid enough to model directly: more rounds
## actually stacked at the gun means more fuel for it to happen at all, and
## a mortar that's already fired off its stockpile (or hasn't been
## resupplied yet) has nothing left to cook off. Scaled linearly against
## MORTAR_STARTING_AMMO — a full load gives this MAX_CHANCE outright; an
## empty tube gives exactly zero, not just a smaller number. See Unit.
## _apply_crew_casualties/_roll_mortar_ammo_cookoff: a cook-off forces the
## crew to abandon the position regardless of how the ordinary hold-or-flee
## roll would have gone (nobody stays next to their own exploding
## ammunition) and can add real additional casualties on top of the
## original hit, on top of destroying whatever rounds were left.
const MORTAR_AMMO_COOKOFF_MAX_CHANCE: float = 0.35

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
## left or right, whichever side actually offers cover, breaks a known
## contact's line of sight, or opens up a bearing around the friendly
## cluster (or the objective itself) none of its own side has claimed yet
## (see ENEMY_ADVANCE_ENCIRCLE_BONUS). 0.0 keeps the literal straight-line
## rush in the pool too, since "usually avoid the open" isn't "never."
##
## Goes all the way out to ±120.0 — genuinely PAST perpendicular, meaning
## the outermost entries are a real step backward along the direct line to
## the objective, not just a lateral bend. That's deliberate: several
## squads that all break for cover at the same moment (see
## _alert_enemy_squads) usually start out bunched close together (the same
## road-march column), and a squad trying to circle around to a genuinely
## different side of a nearby objective needs more room to maneuver than a
## shallow bend can give it — capping at a "moderate," always-forward angle
## was exactly what left squads with no real way to spread out from a tight
## starting cluster, however strongly ENEMY_ADVANCE_ENCIRCLE_BONUS wanted to
## push them apart. A wide or backward-leaning candidate only actually wins
## the weighted roll when the scoring says the detour (or the temporary lost
## ground) is worth it — see ANGLE_PENALTY_PER_DEG below, which still taxes
## the widest entries the most heavily of any candidate.
const ENEMY_ADVANCE_ANGLES_DEG: Array[float] = [-120.0, -80.0, -50.0, -25.0, 0.0, 25.0, 50.0, 80.0, 120.0]

## Fraction of enemy squads (rolled once each, at spawn — see
## BattleManager._spawn_enemy_units) designated to swing wide through the
## new west flank rather than advance along the road/toward the village
## directly — basic fire-and-maneuver: a real assault doesn't send every
## element on the same axis. ~1/3 gives a good chance of at least one
## genuine flank most battles without making it the default behavior for
## every squad.
const ENEMY_FLANK_CHANCE: float = 0.35
## The flank waypoint itself (deep enough into the west flank to be a real
## flank, not a token step off the road) and its arrival radius now live in
## CURRENT_MAP.enemy (flank_waypoint_x/flank_waypoint_arrival_radius) — the
## arrival radius specifically MUST be larger than ENEMY_SURROUND_STANDOFF_
## RADIUS (below), not tighter: _next_advance_point stops requesting any
## further movement once within that radius of whatever _enemy_advance_
## objective currently returns, and while flanking_route_active is still
## true, that objective IS this waypoint — a tighter arrival radius was a
## real, previously-shipped bug where a squad halted exactly at the
## standoff distance and got stuck there forever, never pivoting to the
## real objective (caught at 0% of flanking squads ever completing the
## maneuver across 200 characterization trials).

## Advance-candidate scoring — see BattleManager._score_advance_candidate.
## COVER rewards a candidate that actually lands in TREES/BUILDING terrain,
## a standing "use the terrain" preference that applies whether or not any
## enemy contact is currently known. CONCEALMENT additionally rewards a
## candidate that every currently-known player position is unable to
## directly see — this is what makes bending wide toward one side actually
## pay off as a real flanking move once there's a spotted friendly to route
## around, rather than costing distance for nothing. ENCIRCLE_BONUS rewards
## a candidate that opens up a DIFFERENT bearing — relative to the known
## friendly cluster's own center once there's an actual contact to surround,
## or relative to the objective itself before then, so several squads
## converging on the same mortar/village don't stack on the same approach
## bearing even with nothing sighted yet — than where the rest of the
## squad's own side is already standing. See BattleManager._next_advance_
## point/_score_advance_candidate's own comments for why this is what
## actually keeps squads from all piling onto the same patch of cover once
## close to a shared objective.
## ANGLE_PENALTY_PER_DEG makes a bigger bend cost more, so a detour has to
## actually be worth it rather than every rush wandering aimlessly;
## BASE_WEIGHT keeps the literal straight-line-through-the-open candidate
## meaningfully reachable (never zero), so a direct dash across open ground
## still happens sometimes — just not usually. All four bonus/penalty terms
## are deliberately similar magnitudes (2.0-3.0, against a 0.1-0.2 total
## angle-penalty spread across the widened angle set) so no single goal
## structurally dominates the others — which one actually wins a given roll
## depends on the real terrain and known contacts, not a fixed pecking
## order.
const ENEMY_ADVANCE_COVER_BONUS: float = 3.0
const ENEMY_ADVANCE_CONCEALMENT_BONUS: float = 2.0
const ENEMY_ADVANCE_ENCIRCLE_BONUS: float = 3.0
const ENEMY_ADVANCE_ANGLE_PENALTY_PER_DEG: float = 0.03
const ENEMY_ADVANCE_BASE_WEIGHT: float = 1.0

## Once an enemy squad is this close to its current objective (see
## BattleManager._enemy_advance_objective/_next_advance_point), it treats
## the objective as "reached" and stops advancing further inward — the
## direct fix for squads bunching up on top of each other (or the objective
## itself): every squad approaching the SAME point would otherwise
## eventually converge on that literal coordinate regardless of how well
## ENCIRCLE_BONUS spread out their approach bearings along the way. Halting
## on a ring at this radius instead — reached from a different bearing per
## squad, thanks to that same encirclement pull during the approach — is
## what actually turns "several squads converging on one spot" into "an
## objective surrounded from multiple sides," matching the doctrine's own
## "surround the friendly squads" goal as a real end state, not just a
## scoring nudge along the way.
const ENEMY_SURROUND_STANDOFF_RADIUS: float = 300.0 * PIXELS_PER_METER


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
	for zone in CURRENT_MAP.terrain_zones:
		if zone.type == TerrainType.BUILDING and zone.rect.has_point(pos):
			return TerrainType.BUILDING
	for patch in CURRENT_MAP.forest_patches:
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
	for zone in CURRENT_MAP.terrain_zones:
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

## `known_enemy_positions`/DANGER_RADIUS above only ever look at where a
## known enemy IS right now — a real, previously-reported failure mode: a
## retreat ordered toward a hill the enemy hadn't quite reached yet at the
## moment of the order sailed straight through DANGER_RADIUS's own check,
## only to have the enemy — advancing at its own steady, already-known
## pace the whole time — actually be there by the time the (much slower,
## cover-picking, not sprinting) retreat walk arrived. Real awareness of
## the enemy means tracking where they're headed, not just a single
## snapshot. BattleManager._known_enemy_positions_for_retreat projects a
## second point along a currently-visible, currently-moving enemy's own
## real heading (the same honest, already-established
## _estimate_unit_velocity extrapolation _mortar_aim_point uses to lead a
## shot — never applied to a unit only known via a stale, no-longer-
## visible sighting, since there's no honest read on ITS current heading)
## this many tactical seconds out, then feeds BOTH points into the exact
## same nearest_cover_point/safest_cover_point machinery unchanged — a
## candidate near where the enemy will plausibly BE gets excluded exactly
## like one near where they already are. Picked as a rough approximation
## of how long it actually takes to walk to a nearby candidate cover
## point at REPOSITION_SPEED (a few hundred meters at 1.8 m/s), not a
## cited figure.
const RETREAT_ADVANCE_PROJECTION_TIME: float = 240.0 # tactical seconds (4 minutes)

## Every BUILDING zone and FOREST_PATCH, unified into one "cover zone" shape
## so the search functions below can treat a rectangular building and an
## irregular forest blob identically: a center point, "does this contain
## point p" (_cover_zone_contains), and "a random point inside it"
## (_random_point_in_cover_zone), each dispatched on `zone.type`.
static func _all_cover_zones() -> Array[Dictionary]:
	var zones: Array[Dictionary] = []
	for zone in CURRENT_MAP.terrain_zones:
		if zone.type != TerrainType.BUILDING:
			continue
		zones.append({"type": TerrainType.BUILDING, "rect": zone.rect, "center": zone.rect.position + zone.rect.size / 2.0})
	for patch in CURRENT_MAP.forest_patches:
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
## The map's own real operating area: the modeled west flank
## (WEST_FLANK_WIDTH_M — real, legitimate ground) through the core map's
## east edge horizontally, and the core map's own height vertically.
## Nothing is modeled (or should ever be suspected, searched toward, or
## walked toward) outside this — used anywhere a candidate point is built
## by projecting outward from a starting position (a ring search, a
## flank-watch bearing) rather than picked from an already-bounded list
## of real map features, since that kind of projection has no other
## reason to stay on the map at all.
static func clamp_to_operating_area(point: Vector2) -> Vector2:
	return Vector2(
		clamp(point.x, -WEST_FLANK_WIDTH_PX, MAP_WIDTH_PX),
		clamp(point.y, 0.0, MAP_HEIGHT_PX)
	)


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
			# Clamped to the map's real operating area — an unclamped ring
			# sample can walk arbitrarily far past the actual west/east/
			# north/south edge (repeated evasions all biased the same
			# direction, away from threats approaching from one side,
			# compound outward with nothing to stop them), landing a unit
			# somewhere the camera can't even scroll to (main.gd's own
			# limit_left is exactly -WEST_FLANK_WIDTH_PX) — invisible, not
			# just far away. See clamp_to_operating_area's own doc comment.
			var candidate: Vector2 = clamp_to_operating_area(from + Vector2(cos(theta), sin(theta)) * radius_px)
			if avoid_buildings and (is_building_at(candidate) or path_crosses_building(from, candidate)):
				continue
			var hidden := true
			for threat in threat_positions:
				# Being out of direct LOS alone isn't real safety on its
				# own — a candidate can be LOS-blocked by a single wall or
				# fold in the ground while still standing right around the
				# corner from a known enemy: one step by either side, or a
				# threat this search simply doesn't know about yet, and
				# it's exposed again with no warning. MORTAR_CREW_OVERRUN_
				# DANGER_RANGE is reused here as a general "too close to
				# read as a real hiding spot" standoff, not a mortar-only
				# concept — the same "close enough that a small shift ruins
				# it" reasoning applies to any ground unit relocating for
				# safety (see this function's three call sites).
				if has_direct_los(candidate, threat) or candidate.distance_to(threat) < MORTAR_CREW_OVERRUN_DANGER_RANGE:
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
## The candidate is anchored to the hill's own geometry and the threats'
## bearing, NOT to `from` -- so a unit already dug in near a hill's reverse
## slope (a normal, encouraged posture) can end up with a candidate only a
## few meters from where it already is. That's fine for pure concealment,
## but useless as a post-shot "scoot": it would leave the unit well within
## COUNTER_BATTERY_BLAST_RADIUS of the position a counter-battery strike is
## aimed at. So candidates closer than that radius are rejected outright,
## falling through to the ring search (nearest_hidden_point's other path),
## which is guaranteed to clear it by construction (its nearest ring is
## already farther out than the blast radius).
## Returns `from` (no better option this way) if no hill qualifies.
static func _reverse_slope_candidate(from: Vector2, threat_positions: Array[Vector2], avoid_buildings: bool) -> Vector2:
	var avg_threat := Vector2.ZERO
	for t in threat_positions:
		avg_threat += t
	avg_threat /= threat_positions.size()

	var best := from
	var best_dist := INF
	for hill in CURRENT_MAP.hills:
		var center_px: Vector2 = hill.center_m * PIXELS_PER_METER
		var away: Vector2 = center_px - avg_threat
		if away.length() < 1.0:
			continue
		# Clamped for the same reason nearest_hidden_point's own ring search
		# is: a hill near the map's edge can otherwise project a "reverse
		# slope" candidate off the actual operating area.
		var candidate: Vector2 = clamp_to_operating_area(center_px + away.normalized() * (hill.radius_m * PIXELS_PER_METER * 0.75))
		var d: float = from.distance_to(candidate)
		if d >= best_dist or d > REVERSE_SLOPE_MAX_TRAVEL_M * PIXELS_PER_METER:
			continue
		if d < COUNTER_BATTERY_BLAST_RADIUS:
			continue # too close to be a real scoot -- let the ring search find something further out
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
##   elevation (see elevation_m/CURRENT_MAP.hills), a hillside genuinely can block sight
##   between two points on opposite sides of it. Sampled along the line and
##   compared against the straight sightline between each end's eye height
##   (EYE_HEIGHT_M) — standing on a hill (or anywhere at least as high) lets
##   you see over/down its own slope just fine, in either direction; two
##   points in the lowland on opposite sides of a hill genuinely cannot see
##   each other.
const LOS_SAMPLE_COUNT: int = 20
const LOS_TERRAIN_TOLERANCE_M: float = 2.0 # slack so a sample dead-level with the sightline doesn't falsely block

static func has_direct_los(from: Vector2, to: Vector2) -> bool:
	for zone in CURRENT_MAP.terrain_zones:
		if zone.type != TerrainType.BUILDING:
			continue
		if zone.rect.has_point(from) or zone.rect.has_point(to):
			continue # firing from/into this building doesn't block itself
		if _line_crosses_rect(from, to, zone.rect):
			return false

	# The river's own banks and reed-lined floodplain block a ground-level
	# sightline the same way a building would — real ground-level cover, not
	# just distance. Aerial LOS (has_aerial_los) deliberately does NOT get
	# this: a drone looking down from DRONE_ALTITUDE_M sees the water and
	# both banks just fine — nothing about a river has a roof.
	if path_crosses_river(from, to):
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
	for zone in CURRENT_MAP.terrain_zones:
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
	_draw_river(ci)
	_draw_road(ci)
	for zone in CURRENT_MAP.terrain_zones:
		if zone.type == TerrainType.BUILDING:
			_draw_village(ci, zone.rect)
	for patch in CURRENT_MAP.forest_patches:
		_draw_forest_patch(ci, patch)


## Drawn by following CURRENT_MAP.river's own path_m, not the blocking
## rects directly — a real river/canal winds, and drawing the (boxier,
## bounding-box-padded) collision rects instead would look like a
## staircase. The gap is cut out of whichever leg(s) actually contain the
## crossing point, via the same orientation-agnostic split
## _build_river_rects uses, so the drawn gap always lines up with the one
## that's actually passable regardless of which way the path runs. A
## short plank mark across the gap marks the crossing itself.
static func _draw_river(ci: CanvasItem) -> void:
	if not CURRENT_MAP.has("river"):
		return
	var river: Dictionary = CURRENT_MAP.river
	var path: Array = river.path_m
	var width_px: float = river.width_m * PIXELS_PER_METER
	var water := Color(0.3, 0.45, 0.55, 0.85)
	var crossing: Vector2 = river.crossing_point_m * PIXELS_PER_METER
	var gap_half: float = river.crossing_gap_m * PIXELS_PER_METER
	for i in path.size() - 1:
		var a: Vector2 = path[i] * PIXELS_PER_METER
		var b: Vector2 = path[i + 1] * PIXELS_PER_METER
		var legs: Array = [[a, b]]
		if _crossing_is_on_leg(a, b, crossing):
			legs = _split_leg_around_crossing(a, b, crossing, gap_half)
		for leg in legs:
			ci.draw_line(leg[0], leg[1], water, width_px)
	# The plank mark runs across the gap, perpendicular to whichever
	# direction the path happens to be running through the crossing —
	# found from the (up to two) legs the crossing actually sits on,
	# rather than assuming any particular axis.
	var crossing_dir := Vector2(1.0, 0.0)
	for i in path.size() - 1:
		var a: Vector2 = path[i] * PIXELS_PER_METER
		var b: Vector2 = path[i + 1] * PIXELS_PER_METER
		if _crossing_is_on_leg(a, b, crossing) and a.distance_to(b) > 0.001:
			crossing_dir = (b - a).normalized()
			break
	var perp: Vector2 = Vector2(-crossing_dir.y, crossing_dir.x)
	var plank := Color(0.55, 0.45, 0.3)
	var t: float = -gap_half
	while t < gap_half:
		var center: Vector2 = crossing + crossing_dir * t
		ci.draw_line(center - perp * width_px / 2.0, center + perp * width_px / 2.0, plank, 2.0)
		t += 10.0


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
## Grid column 0's world x, in meters — negative so the grid also covers
## WEST_FLANK_WIDTH_M (see _build_contour_cache). Set there; read by
## _marching_squares_cell so grid-index math and world-position math for a
## cell agree with each other.
static var _contour_col_origin_m: float = 0.0
## The spacing actually used for the currently-loaded map — chosen in
## _build_contour_cache from that map's own real local relief (highest
## sampled point minus lowest), not a single fixed number for every map.
## A map with only a few meters of rise from lowest to highest point needs
## a much tighter interval than one with real ridgelines, or every hill
## would draw as a single ring or none at all; real topographic sheets
## make the same per-area choice rather than using one interval for every
## kind of terrain. Read by _draw_hills for the brightness ramp; not
## meaningful before _build_contour_cache has run at least once.
static var _contour_interval_m: float = 10.0


## See _contour_interval_m's own doc comment for why this isn't fixed.
static func _choose_contour_interval_m(relief_range_m: float) -> float:
	if relief_range_m <= 50.0:
		return 5.0
	elif relief_range_m <= 120.0:
		return 10.0
	elif relief_range_m <= 250.0:
		return 20.0
	else:
		return 25.0


static func _draw_hills(ci: CanvasItem) -> void:
	for hill in CURRENT_MAP.hills:
		var center_px: Vector2 = hill.center_m * PIXELS_PER_METER
		var halo_radius_px: float = hill.radius_m * 1.4 * PIXELS_PER_METER
		ci.draw_circle(center_px, halo_radius_px, Color(0.32, 0.29, 0.2, 0.12))

	_build_contour_cache()
	var baseline: float = CURRENT_MAP.get("elevation_baseline_m", 0.0)
	var max_height := 0.0
	for hill in CURRENT_MAP.hills:
		max_height = max(max_height, hill.height_m)
	for seg in _contour_segments_cache:
		var t: float = (seg.level - baseline) / max_height # local relief only — baseline is a flat offset, not relief
		var b: float = 0.5 + 0.35 * t # brighter toward the highest terrain
		ci.draw_line(seg.a, seg.b, Color(b, b * 0.95, b * 0.68, 0.8), 1.5)

	for hill in CURRENT_MAP.hills:
		var center_px: Vector2 = hill.center_m * PIXELS_PER_METER
		ci.draw_string(ThemeDB.fallback_font, center_px + Vector2(-14.0, -4.0), "%dm" % int(hill.height_m),
			HORIZONTAL_ALIGNMENT_CENTER, 60, 12, Color(0.35, 0.3, 0.16, 0.9))


static func _build_contour_cache() -> void:
	if _contour_cache_built:
		return
	_contour_cache_built = true

	# West flank first, so the grid also traces the new open ground rather
	# than stopping dead at x=0 — a hard-edged void starting exactly at the
	# old map boundary would read as a rendering bug, not open terrain.
	var west_cols: int = int(WEST_FLANK_WIDTH_M / CONTOUR_GRID_STEP_M) + 1
	_contour_col_origin_m = -float(west_cols) * CONTOUR_GRID_STEP_M
	var cols: int = west_cols + int(MAP_WIDTH_M / CONTOUR_GRID_STEP_M) + 2
	var rows: int = int(MAP_HEIGHT_M / CONTOUR_GRID_STEP_M) + 2
	var grid: Array[PackedFloat32Array] = []
	var min_elev := INF
	var max_elev := -INF
	for row in rows:
		var line := PackedFloat32Array()
		line.resize(cols)
		for col in cols:
			var pos_m := Vector2(_contour_col_origin_m + col * CONTOUR_GRID_STEP_M, row * CONTOUR_GRID_STEP_M)
			var e: float = elevation_m(pos_m * PIXELS_PER_METER)
			line[col] = e
			min_elev = min(min_elev, e)
			max_elev = max(max_elev, e)
		grid.append(line)

	_contour_interval_m = _choose_contour_interval_m(max_elev - min_elev)

	# Levels are real ASL values now (elevation_m includes the map's own
	# baseline), so they need to start at the first round multiple of the
	# interval ABOVE the lowest sampled point, not at "one interval above
	# zero" — a map whose baseline isn't itself a multiple of the interval
	# would otherwise silently draw no lines at all, or lines that don't
	# land on round numbers the way a real contour sheet's would.
	var level: float = ceil(min_elev / _contour_interval_m) * _contour_interval_m
	if level <= min_elev:
		level += _contour_interval_m
	while level < max_elev:
		for row in rows - 1:
			for col in cols - 1:
				_marching_squares_cell(grid, row, col, level)
		level += _contour_interval_m


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

	var p_tl := Vector2(_contour_col_origin_m + col * CONTOUR_GRID_STEP_M, row * CONTOUR_GRID_STEP_M)
	var p_tr := Vector2(_contour_col_origin_m + (col + 1) * CONTOUR_GRID_STEP_M, row * CONTOUR_GRID_STEP_M)
	var p_br := Vector2(_contour_col_origin_m + (col + 1) * CONTOUR_GRID_STEP_M, (row + 1) * CONTOUR_GRID_STEP_M)
	var p_bl := Vector2(_contour_col_origin_m + col * CONTOUR_GRID_STEP_M, (row + 1) * CONTOUR_GRID_STEP_M)

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


## A real bent dirt road (CURRENT_MAP.road_waypoints_m), not a straight strip — drawn as
## connected thick segments with dashed centerline ticks. Drawn width has a
## small legibility floor (real roads are only a few meters wide, which at
## this map's scale would otherwise be sub-pixel) — the road's true width
## still governs nothing gameplay-relevant, it's purely cosmetic.
static func _draw_road(ci: CanvasItem) -> void:
	var width_px: float = max(CURRENT_MAP.road_width_m * PIXELS_PER_METER, 2.5)
	for i in CURRENT_MAP.road_waypoints_m.size() - 1:
		var a: Vector2 = CURRENT_MAP.road_waypoints_m[i] * PIXELS_PER_METER
		var b: Vector2 = CURRENT_MAP.road_waypoints_m[i + 1] * PIXELS_PER_METER
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
