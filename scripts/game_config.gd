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
## How each recon mode is named to the player (the level-select screen's option
## titles and the battle-score history both use these, so they can't drift).
const RECON_MODE_LABELS: Dictionary = {
	ReconMode.SPOTTER: "Level 0 — Artillery Spotter",
	ReconMode.DRONE_TEAM: "Level 1 — Drone Recon",
}

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
## Oblast, at a rural crossroads on the H-26 highway. The area has been
## fought over repeatedly since the 2022 Kharkiv counteroffensive, unlike
## Moshchun's single dated battle, so no specific date is claimed here —
## just the real place and its real orientation.
##
## REBUILT from real data (2026-09), the same pipeline as Svystunivka
## Heights: this entry used to be modeled from a single satellite/map
## screenshot centered on 49.657741, 37.270141, which showed only a
## handful of buildings — the map's own doc comment already named the
## larger real village of "Myrne (to the west, in the defender's own
## rear)" as the settlement actually worth defending, but the terrain was
## never built from Myrne's real footprint. It now is: the anchor moved
## about 1.45km to Myrne's own building-cluster centroid
## (49.666645, 37.255434) — a real, compact linear village strung along the
## H-26 — and every layer is now built from real data over that ground:
## SRTM 30m elevation (OpenTopoData, 16 hills fit to it, ~3.2m RMS overall,
## ~1.7m near the village); BUILDINGS from OpenStreetMap (ODbL, © OpenStreetMap
## contributors, 21 blocks aggregated from real footprints); the ROAD is the
## real H-26/village-street route (Dijkstra over OSM highways from the map's
## east edge to the village, not an invented "due east" line); TREE COVER
## from an automatic colour+texture classification of satellite imagery
## (240 patches — real cover here runs noticeably denser than the original
## screenshot-based version suggested, about 12-13% of the frame). The
## original entry's "drainage canal parallel to the road" was inferred from
## the screenshot; real OSM water data shows nothing running near the real
## route, so CURRENT_MAP no longer carries a "river" key for this map — the
## same honest omission Pishchane's pond and Svystunivka's stream already use.
##
## The real attack direction is EAST along the H-26 — no rotation needed
## (screen-right already means real east, matching this game's standing
## east-attacker/west-defender convention).
const MAPS: Dictionary = {
"pervomaiske": {
	"name": "Pervomaiske",
	"location_subtitle": "Kupiansk Raion, Kharkiv Oblast",
	# The real coordinates this map was built around — shown on the map's
	# own location readout (see main.gd's _location_label) so a curious
	# player can look the actual place up.
	"coordinates": "49.666645, 37.255434",
	"compass_north_screen_direction": Vector2(0.0, -1.0),

	"width_m": 5000.0,
	"height_m": 3500.0,
	"west_flank_width_m": 1500.0,

	"village_center": Vector2(1534.0, 1731.0) * PIXELS_PER_METER,

	# The fitted model's own constant term — see this dictionary's own doc
	# comment for the real elevation sourcing.
	"elevation_baseline_m": 159.5,

	## Least-squares fit to real SRTM data — see this dictionary's own doc
	## comment. Ordered nearest the village first.
	"hills": [
		{"center_m": Vector2(1300.0, 1950.0), "radius_m": 260.0, "height_m": 5.2, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.12, "phase": 5.5},
			{"frequency": 3, "amplitude": 0.07, "phase": 2.7},
		]},
		{"center_m": Vector2(1100.0, 1250.0), "radius_m": 550.0, "height_m": 11.9, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.10, "phase": 2.1},
			{"frequency": 3, "amplitude": 0.09, "phase": 6.1},
		]},
		{"center_m": Vector2(2300.0, 1750.0), "radius_m": 380.0, "height_m": 9.8, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.11, "phase": 2.5},
			{"frequency": 4, "amplitude": 0.08, "phase": 3.8},
		]},
		{"center_m": Vector2(500.0, 1850.0), "radius_m": 260.0, "height_m": 9.1, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.13, "phase": 5.9},
			{"frequency": 2, "amplitude": 0.08, "phase": 5.4},
		]},
		{"center_m": Vector2(2100.0, 850.0), "radius_m": 260.0, "height_m": 9.9, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.11, "phase": 4.0},
			{"frequency": 3, "amplitude": 0.08, "phase": 0.1},
		]},
		{"center_m": Vector2(1100.0, 2850.0), "radius_m": 260.0, "height_m": 11.4, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.12, "phase": 3.6},
			{"frequency": 4, "amplitude": 0.09, "phase": 2.1},
		]},
		{"center_m": Vector2(600.0, 2950.0), "radius_m": 180.0, "height_m": 7.4, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.13, "phase": 6.1},
			{"frequency": 2, "amplitude": 0.10, "phase": 6.1},
		]},
		{"center_m": Vector2(2900.0, 1150.0), "radius_m": 260.0, "height_m": 5.9, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.10, "phase": 2.7},
			{"frequency": 2, "amplitude": 0.07, "phase": 0.3},
		]},
		{"center_m": Vector2(300.0, 750.0), "radius_m": 260.0, "height_m": 7.6, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.12, "phase": 5.4},
			{"frequency": 3, "amplitude": 0.08, "phase": 3.7},
		]},
		{"center_m": Vector2(1500.0, -50.0), "radius_m": 380.0, "height_m": 12.8, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.11, "phase": 2.7},
			{"frequency": 3, "amplitude": 0.09, "phase": 1.9},
		]},
		{"center_m": Vector2(-600.0, 1750.0), "radius_m": 380.0, "height_m": 10.7, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.13, "phase": 2.2},
			{"frequency": 4, "amplitude": 0.07, "phase": 2.0},
		]},
		{"center_m": Vector2(3300.0, 3650.0), "radius_m": 1200.0, "height_m": 26.4, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.13, "phase": 5.1},
			{"frequency": 3, "amplitude": 0.08, "phase": 2.7},
		]},
		{"center_m": Vector2(-600.0, -50.0), "radius_m": 800.0, "height_m": 17.1, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.11, "phase": 4.2},
			{"frequency": 4, "amplitude": 0.09, "phase": 2.3},
		]},
		{"center_m": Vector2(-1400.0, 2050.0), "radius_m": 260.0, "height_m": 8.2, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.12, "phase": 4.7},
			{"frequency": 3, "amplitude": 0.07, "phase": 5.7},
		]},
		{"center_m": Vector2(5000.0, 250.0), "radius_m": 260.0, "height_m": 15.9, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.13, "phase": 5.8},
			{"frequency": 4, "amplitude": 0.09, "phase": 6.0},
		]},
		{"center_m": Vector2(5200.0, 3350.0), "radius_m": 550.0, "height_m": 13.9, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.11, "phase": 5.0},
			{"frequency": 4, "amplitude": 0.07, "phase": 4.3},
		]},
	],

	## Building blocks aggregated from real footprints (OpenStreetMap, plus
	## imagery detection where noted in the doc comment above).
	"terrain_zones": [
		{"rect": Rect2(695.0 * PIXELS_PER_METER, 1290.0 * PIXELS_PER_METER, 180.0 * PIXELS_PER_METER, 180.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(815.0 * PIXELS_PER_METER, 1190.0 * PIXELS_PER_METER, 175.0 * PIXELS_PER_METER, 155.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(1925.0 * PIXELS_PER_METER, 1855.0 * PIXELS_PER_METER, 155.0 * PIXELS_PER_METER, 225.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(2425.0 * PIXELS_PER_METER, 2625.0 * PIXELS_PER_METER, 170.0 * PIXELS_PER_METER, 195.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(-1510.0 * PIXELS_PER_METER, 1695.0 * PIXELS_PER_METER, 70.0 * PIXELS_PER_METER, 65.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(-1510.0 * PIXELS_PER_METER, 775.0 * PIXELS_PER_METER, 235.0 * PIXELS_PER_METER, 80.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(-1270.0 * PIXELS_PER_METER, 830.0 * PIXELS_PER_METER, 220.0 * PIXELS_PER_METER, 70.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(1520.0 * PIXELS_PER_METER, 1695.0 * PIXELS_PER_METER, 385.0 * PIXELS_PER_METER, 320.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(1700.0 * PIXELS_PER_METER, 2185.0 * PIXELS_PER_METER, 230.0 * PIXELS_PER_METER, 125.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(1900.0 * PIXELS_PER_METER, 2275.0 * PIXELS_PER_METER, 215.0 * PIXELS_PER_METER, 155.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(1320.0 * PIXELS_PER_METER, 1665.0 * PIXELS_PER_METER, 145.0 * PIXELS_PER_METER, 170.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(1430.0 * PIXELS_PER_METER, 1545.0 * PIXELS_PER_METER, 155.0 * PIXELS_PER_METER, 125.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(1095.0 * PIXELS_PER_METER, 1555.0 * PIXELS_PER_METER, 195.0 * PIXELS_PER_METER, 140.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(1225.0 * PIXELS_PER_METER, 1350.0 * PIXELS_PER_METER, 170.0 * PIXELS_PER_METER, 230.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(920.0 * PIXELS_PER_METER, 1415.0 * PIXELS_PER_METER, 140.0 * PIXELS_PER_METER, 200.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(1020.0 * PIXELS_PER_METER, 1315.0 * PIXELS_PER_METER, 175.0 * PIXELS_PER_METER, 170.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(2685.0 * PIXELS_PER_METER, -10.0 * PIXELS_PER_METER, 165.0 * PIXELS_PER_METER, 90.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(2895.0 * PIXELS_PER_METER, 180.0 * PIXELS_PER_METER, 175.0 * PIXELS_PER_METER, 140.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(3070.0 * PIXELS_PER_METER, 265.0 * PIXELS_PER_METER, 195.0 * PIXELS_PER_METER, 130.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(3250.0 * PIXELS_PER_METER, 340.0 * PIXELS_PER_METER, 205.0 * PIXELS_PER_METER, 125.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(3350.0 * PIXELS_PER_METER, -10.0 * PIXELS_PER_METER, 140.0 * PIXELS_PER_METER, 70.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
	],

	## Patches traced from satellite imagery — see the doc comment: wooded
	## blocks/thickets first, tree rows/shelterbelts after.
	"forest_patches": [
		{"center_m": Vector2(1750.0, 1670.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.15, "phase": 1.7},
			{"frequency": 3, "amplitude": 0.08, "phase": 2.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(2070.0, 1870.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.13, "phase": 5.4},
			{"frequency": 2, "amplitude": 0.10, "phase": 0.9},
		]}, # wooded block / thicket
		{"center_m": Vector2(2530.0, 2050.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.12, "phase": 3.6},
			{"frequency": 2, "amplitude": 0.08, "phase": 5.3},
		]}, # wooded block / thicket
		{"center_m": Vector2(2610.0, 2110.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.14, "phase": 1.7},
			{"frequency": 2, "amplitude": 0.11, "phase": 5.3},
		]}, # wooded block / thicket
		{"center_m": Vector2(2470.0, 2490.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.12, "phase": 0.1},
			{"frequency": 4, "amplitude": 0.11, "phase": 3.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(2670.0, 2150.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.15, "phase": 6.2},
			{"frequency": 4, "amplitude": 0.11, "phase": 0.3},
		]}, # wooded block / thicket
		{"center_m": Vector2(510.0, 910.0), "radius_m": 57.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.16, "phase": 0.6},
			{"frequency": 4, "amplitude": 0.11, "phase": 5.1},
		]}, # wooded block / thicket
		{"center_m": Vector2(2730.0, 2190.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 4.0},
			{"frequency": 2, "amplitude": 0.11, "phase": 0.6},
		]}, # wooded block / thicket
		{"center_m": Vector2(2430.0, 2710.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.15, "phase": 5.6},
			{"frequency": 4, "amplitude": 0.09, "phase": 1.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(2410.0, 2770.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.12, "phase": 5.4},
			{"frequency": 3, "amplitude": 0.11, "phase": 5.1},
		]}, # wooded block / thicket
		{"center_m": Vector2(470.0, 850.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.14, "phase": 4.9},
			{"frequency": 2, "amplitude": 0.10, "phase": 2.7},
		]}, # wooded block / thicket
		{"center_m": Vector2(2830.0, 2250.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.15, "phase": 3.2},
			{"frequency": 3, "amplitude": 0.11, "phase": 4.6},
		]}, # wooded block / thicket
		{"center_m": Vector2(370.0, 790.0), "radius_m": 54.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 2.5},
			{"frequency": 4, "amplitude": 0.09, "phase": 3.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(2870.0, 2350.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.13, "phase": 1.7},
			{"frequency": 2, "amplitude": 0.10, "phase": 5.0},
		]}, # wooded block / thicket
		{"center_m": Vector2(2630.0, 2730.0), "radius_m": 57.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.14, "phase": 0.2},
			{"frequency": 3, "amplitude": 0.09, "phase": 0.9},
		]}, # wooded block / thicket
		{"center_m": Vector2(2910.0, 2310.0), "radius_m": 54.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.15, "phase": 6.0},
			{"frequency": 2, "amplitude": 0.11, "phase": 1.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(310.0, 750.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.12, "phase": 0.3},
			{"frequency": 4, "amplitude": 0.11, "phase": 3.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(2710.0, 2750.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.13, "phase": 3.7},
			{"frequency": 4, "amplitude": 0.09, "phase": 4.7},
		]}, # wooded block / thicket
		{"center_m": Vector2(2990.0, 2350.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.12, "phase": 5.5},
			{"frequency": 4, "amplitude": 0.09, "phase": 4.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(250.0, 730.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.13, "phase": 4.0},
			{"frequency": 4, "amplitude": 0.10, "phase": 5.6},
		]}, # wooded block / thicket
		{"center_m": Vector2(2790.0, 2810.0), "radius_m": 54.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 0.4},
			{"frequency": 4, "amplitude": 0.11, "phase": 4.5},
		]}, # wooded block / thicket
		{"center_m": Vector2(190.0, 690.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.15, "phase": 5.8},
			{"frequency": 2, "amplitude": 0.11, "phase": 4.5},
		]}, # wooded block / thicket
		{"center_m": Vector2(3070.0, 2410.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 0.8},
			{"frequency": 4, "amplitude": 0.10, "phase": 3.7},
		]}, # wooded block / thicket
		{"center_m": Vector2(110.0, 650.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.12, "phase": 0.1},
			{"frequency": 3, "amplitude": 0.09, "phase": 0.9},
		]}, # wooded block / thicket
		{"center_m": Vector2(3130.0, 2450.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.14, "phase": 0.1},
			{"frequency": 4, "amplitude": 0.10, "phase": 4.4},
		]}, # wooded block / thicket
		{"center_m": Vector2(3150.0, 2510.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.14, "phase": 2.5},
			{"frequency": 3, "amplitude": 0.11, "phase": 4.6},
		]}, # wooded block / thicket
		{"center_m": Vector2(50.0, 610.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.13, "phase": 4.7},
			{"frequency": 4, "amplitude": 0.10, "phase": 4.3},
		]}, # wooded block / thicket
		{"center_m": Vector2(-10.0, 590.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 5.6},
			{"frequency": 4, "amplitude": 0.12, "phase": 4.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(-70.0, 550.0), "radius_m": 54.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.15, "phase": 3.0},
			{"frequency": 3, "amplitude": 0.09, "phase": 4.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(-30.0, 450.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.15, "phase": 3.4},
			{"frequency": 4, "amplitude": 0.09, "phase": 1.1},
		]}, # wooded block / thicket
		{"center_m": Vector2(3370.0, 1010.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 4.0},
			{"frequency": 2, "amplitude": 0.08, "phase": 1.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(3350.0, 2590.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.15, "phase": 4.7},
			{"frequency": 2, "amplitude": 0.09, "phase": 4.0},
		]}, # wooded block / thicket
		{"center_m": Vector2(-470.0, 1250.0), "radius_m": 73.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.12, "phase": 6.0},
			{"frequency": 2, "amplitude": 0.08, "phase": 4.0},
		]}, # wooded block / thicket
		{"center_m": Vector2(-190.0, 490.0), "radius_m": 54.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.14, "phase": 0.5},
			{"frequency": 4, "amplitude": 0.11, "phase": 2.1},
		]}, # wooded block / thicket
		{"center_m": Vector2(2990.0, 250.0), "radius_m": 57.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 3.6},
			{"frequency": 4, "amplitude": 0.11, "phase": 0.1},
		]}, # wooded block / thicket
		{"center_m": Vector2(-550.0, 1230.0), "radius_m": 54.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.15, "phase": 4.2},
			{"frequency": 4, "amplitude": 0.09, "phase": 3.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(-270.0, 410.0), "radius_m": 84.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 0.8},
			{"frequency": 4, "amplitude": 0.09, "phase": 0.7},
		]}, # wooded block / thicket
		{"center_m": Vector2(-770.0, 1890.0), "radius_m": 65.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.15, "phase": 4.4},
			{"frequency": 2, "amplitude": 0.09, "phase": 1.0},
		]}, # wooded block / thicket
		{"center_m": Vector2(-810.0, 1410.0), "radius_m": 57.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.14, "phase": 2.8},
			{"frequency": 3, "amplitude": 0.08, "phase": 3.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(-810.0, 2150.0), "radius_m": 65.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.15, "phase": 0.8},
			{"frequency": 2, "amplitude": 0.11, "phase": 4.6},
		]}, # wooded block / thicket
		{"center_m": Vector2(-850.0, 1750.0), "radius_m": 133.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.12, "phase": 6.1},
			{"frequency": 2, "amplitude": 0.11, "phase": 5.3},
		]}, # wooded block / thicket
		{"center_m": Vector2(-850.0, 1890.0), "radius_m": 54.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.15, "phase": 1.6},
			{"frequency": 2, "amplitude": 0.09, "phase": 4.9},
		]}, # wooded block / thicket
		{"center_m": Vector2(-930.0, 1870.0), "radius_m": 54.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.12, "phase": 4.2},
			{"frequency": 2, "amplitude": 0.09, "phase": 4.9},
		]}, # wooded block / thicket
		{"center_m": Vector2(-950.0, 1550.0), "radius_m": 187.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.15, "phase": 3.9},
			{"frequency": 2, "amplitude": 0.12, "phase": 6.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(3470.0, 170.0), "radius_m": 57.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.13, "phase": 2.8},
			{"frequency": 2, "amplitude": 0.10, "phase": 2.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(-1070.0, 1250.0), "radius_m": 95.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.14, "phase": 4.9},
			{"frequency": 2, "amplitude": 0.10, "phase": 3.5},
		]}, # wooded block / thicket
		{"center_m": Vector2(3850.0, 2910.0), "radius_m": 65.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.13, "phase": 3.2},
			{"frequency": 4, "amplitude": 0.08, "phase": 5.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(-1130.0, 1650.0), "radius_m": 73.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.14, "phase": 2.1},
			{"frequency": 3, "amplitude": 0.08, "phase": 1.3},
		]}, # wooded block / thicket
		{"center_m": Vector2(-1170.0, 1310.0), "radius_m": 73.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.15, "phase": 5.3},
			{"frequency": 2, "amplitude": 0.09, "phase": 3.6},
		]}, # wooded block / thicket
		{"center_m": Vector2(-750.0, 190.0), "radius_m": 65.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.15, "phase": 4.9},
			{"frequency": 4, "amplitude": 0.10, "phase": 1.7},
		]}, # wooded block / thicket
		{"center_m": Vector2(-710.0, 130.0), "radius_m": 57.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.13, "phase": 3.5},
			{"frequency": 3, "amplitude": 0.08, "phase": 0.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(-1270.0, 1690.0), "radius_m": 65.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.12, "phase": 5.6},
			{"frequency": 2, "amplitude": 0.09, "phase": 1.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(-1290.0, 1770.0), "radius_m": 54.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.13, "phase": 4.4},
			{"frequency": 2, "amplitude": 0.10, "phase": 4.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(-1310.0, 1370.0), "radius_m": 114.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.13, "phase": 5.6},
			{"frequency": 3, "amplitude": 0.10, "phase": 1.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(-850.0, 130.0), "radius_m": 73.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.12, "phase": 3.7},
			{"frequency": 3, "amplitude": 0.11, "phase": 6.1},
		]}, # wooded block / thicket
		{"center_m": Vector2(-1330.0, 2170.0), "radius_m": 76.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.13, "phase": 2.3},
			{"frequency": 2, "amplitude": 0.10, "phase": 3.5},
		]}, # wooded block / thicket
		{"center_m": Vector2(-1350.0, 1250.0), "radius_m": 73.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.14, "phase": 3.5},
			{"frequency": 3, "amplitude": 0.10, "phase": 2.4},
		]}, # wooded block / thicket
		{"center_m": Vector2(-1230.0, 2770.0), "radius_m": 57.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.15, "phase": 5.5},
			{"frequency": 3, "amplitude": 0.08, "phase": 1.7},
		]}, # wooded block / thicket
		{"center_m": Vector2(-950.0, 10.0), "radius_m": 133.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.13, "phase": 4.4},
			{"frequency": 2, "amplitude": 0.10, "phase": 5.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(-1090.0, 10.0), "radius_m": 76.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.14, "phase": 2.7},
			{"frequency": 4, "amplitude": 0.08, "phase": 0.4},
		]}, # wooded block / thicket
		{"center_m": Vector2(1470.0, 1710.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.2},
			{"frequency": 4, "amplitude": 0.05, "phase": 2.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1530.0, 1630.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 4.0},
			{"frequency": 2, "amplitude": 0.05, "phase": 4.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1510.0, 1590.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 3.2},
			{"frequency": 4, "amplitude": 0.06, "phase": 2.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1310.0, 1790.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 0.6},
			{"frequency": 2, "amplitude": 0.04, "phase": 5.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1610.0, 1570.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 1.1},
			{"frequency": 4, "amplitude": 0.04, "phase": 4.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1570.0, 1550.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.1},
			{"frequency": 3, "amplitude": 0.05, "phase": 5.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1710.0, 1630.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 5.2},
			{"frequency": 3, "amplitude": 0.04, "phase": 2.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1490.0, 1490.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 1.4},
			{"frequency": 3, "amplitude": 0.06, "phase": 6.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1450.0, 1470.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 5.1},
			{"frequency": 4, "amplitude": 0.05, "phase": 1.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1630.0, 1490.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 4.3},
			{"frequency": 2, "amplitude": 0.05, "phase": 2.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1690.0, 1530.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 5.0},
			{"frequency": 4, "amplitude": 0.06, "phase": 3.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1590.0, 1470.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.6},
			{"frequency": 3, "amplitude": 0.05, "phase": 1.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1290.0, 1530.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.7},
			{"frequency": 3, "amplitude": 0.06, "phase": 0.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1410.0, 1450.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 1.9},
			{"frequency": 2, "amplitude": 0.05, "phase": 4.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1810.0, 1690.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.06, "phase": 1.3},
			{"frequency": 2, "amplitude": 0.06, "phase": 1.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1770.0, 1570.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.9},
			{"frequency": 3, "amplitude": 0.05, "phase": 2.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1850.0, 1710.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 5.5},
			{"frequency": 2, "amplitude": 0.04, "phase": 1.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1870.0, 1750.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 0.9},
			{"frequency": 4, "amplitude": 0.05, "phase": 5.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1850.0, 1630.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 0.5},
			{"frequency": 4, "amplitude": 0.05, "phase": 1.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1350.0, 1410.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.1},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1430.0, 1350.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 4.3},
			{"frequency": 4, "amplitude": 0.06, "phase": 5.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1910.0, 1650.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 1.3},
			{"frequency": 4, "amplitude": 0.05, "phase": 2.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1930.0, 1770.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 0.8},
			{"frequency": 2, "amplitude": 0.06, "phase": 3.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1970.0, 1790.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.6},
			{"frequency": 3, "amplitude": 0.06, "phase": 1.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1030.0, 1650.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.5},
			{"frequency": 3, "amplitude": 0.05, "phase": 4.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1990.0, 1710.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 1.6},
			{"frequency": 2, "amplitude": 0.04, "phase": 0.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1230.0, 1330.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 6.0},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1850.0, 2130.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 2.6},
			{"frequency": 3, "amplitude": 0.06, "phase": 0.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1090.0, 1430.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 3.0},
			{"frequency": 3, "amplitude": 0.04, "phase": 2.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(990.0, 1630.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 2.0},
			{"frequency": 4, "amplitude": 0.06, "phase": 1.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2030.0, 1730.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 5.0},
			{"frequency": 2, "amplitude": 0.05, "phase": 2.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2030.0, 1830.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 1.1},
			{"frequency": 2, "amplitude": 0.05, "phase": 3.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1010.0, 1510.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.06, "phase": 5.9},
			{"frequency": 4, "amplitude": 0.05, "phase": 5.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(970.0, 1570.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 0.6},
			{"frequency": 2, "amplitude": 0.06, "phase": 5.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1250.0, 1230.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 1.4},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1150.0, 1270.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 2.9},
			{"frequency": 2, "amplitude": 0.05, "phase": 6.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2050.0, 2010.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 2.0},
			{"frequency": 3, "amplitude": 0.05, "phase": 1.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2090.0, 1990.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 0.4},
			{"frequency": 2, "amplitude": 0.06, "phase": 5.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1190.0, 1190.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 6.2},
			{"frequency": 4, "amplitude": 0.04, "phase": 1.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(870.0, 1550.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 4.7},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2150.0, 1910.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 3.8},
			{"frequency": 4, "amplitude": 0.04, "phase": 1.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(830.0, 1530.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 4.4},
			{"frequency": 4, "amplitude": 0.06, "phase": 5.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2190.0, 1930.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 2.2},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1950.0, 2310.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 1.9},
			{"frequency": 4, "amplitude": 0.05, "phase": 0.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2090.0, 2190.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 2.3},
			{"frequency": 3, "amplitude": 0.05, "phase": 0.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(970.0, 1170.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 0.2},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2270.0, 1990.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 1.2},
			{"frequency": 2, "amplitude": 0.05, "phase": 3.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2090.0, 2310.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.1},
			{"frequency": 3, "amplitude": 0.06, "phase": 2.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2290.0, 2110.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.06, "phase": 2.4},
			{"frequency": 3, "amplitude": 0.05, "phase": 3.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2350.0, 1930.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 0.1},
			{"frequency": 2, "amplitude": 0.05, "phase": 5.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2250.0, 2190.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 4.7},
			{"frequency": 3, "amplitude": 0.06, "phase": 1.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2370.0, 1830.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 5.4},
			{"frequency": 4, "amplitude": 0.06, "phase": 3.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2250.0, 2250.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 6.2},
			{"frequency": 3, "amplitude": 0.05, "phase": 0.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(610.0, 1570.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.06, "phase": 3.3},
			{"frequency": 4, "amplitude": 0.05, "phase": 3.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2230.0, 2290.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 2.3},
			{"frequency": 4, "amplitude": 0.04, "phase": 4.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2410.0, 1690.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 2.4},
			{"frequency": 4, "amplitude": 0.05, "phase": 6.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2390.0, 1950.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 0.0},
			{"frequency": 2, "amplitude": 0.05, "phase": 5.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(650.0, 1410.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 0.6},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2310.0, 2190.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.8},
			{"frequency": 2, "amplitude": 0.05, "phase": 3.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2290.0, 2230.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 3.3},
			{"frequency": 4, "amplitude": 0.06, "phase": 2.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2210.0, 2350.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 4.6},
			{"frequency": 2, "amplitude": 0.04, "phase": 0.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2350.0, 2150.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.8},
			{"frequency": 3, "amplitude": 0.06, "phase": 5.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2370.0, 2130.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 1.3},
			{"frequency": 4, "amplitude": 0.04, "phase": 6.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2390.0, 2110.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.8},
			{"frequency": 3, "amplitude": 0.06, "phase": 0.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2450.0, 1550.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.0},
			{"frequency": 2, "amplitude": 0.06, "phase": 3.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2250.0, 2370.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 4.0},
			{"frequency": 2, "amplitude": 0.05, "phase": 2.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2450.0, 1990.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 3.9},
			{"frequency": 4, "amplitude": 0.05, "phase": 3.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2470.0, 2030.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 4.3},
			{"frequency": 4, "amplitude": 0.06, "phase": 4.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2470.0, 1470.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 6.0},
			{"frequency": 3, "amplitude": 0.04, "phase": 0.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2290.0, 2410.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 4.2},
			{"frequency": 3, "amplitude": 0.06, "phase": 3.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2330.0, 2430.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 1.9},
			{"frequency": 3, "amplitude": 0.06, "phase": 0.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2370.0, 2450.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 1.7},
			{"frequency": 2, "amplitude": 0.06, "phase": 0.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(370.0, 1770.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.5},
			{"frequency": 4, "amplitude": 0.05, "phase": 0.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(370.0, 1710.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 1.3},
			{"frequency": 2, "amplitude": 0.06, "phase": 0.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2530.0, 1270.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 1.9},
			{"frequency": 3, "amplitude": 0.06, "phase": 0.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2410.0, 2470.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 0.5},
			{"frequency": 4, "amplitude": 0.04, "phase": 3.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(350.0, 1590.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 0.7},
			{"frequency": 4, "amplitude": 0.06, "phase": 2.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(330.0, 1450.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 4.8},
			{"frequency": 2, "amplitude": 0.05, "phase": 5.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2630.0, 2210.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 2.8},
			{"frequency": 2, "amplitude": 0.06, "phase": 4.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(590.0, 930.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 5.7},
			{"frequency": 2, "amplitude": 0.06, "phase": 1.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2570.0, 1130.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.9},
			{"frequency": 3, "amplitude": 0.05, "phase": 3.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(650.0, 850.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 3.7},
			{"frequency": 4, "amplitude": 0.05, "phase": 2.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2430.0, 2570.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 2.9},
			{"frequency": 3, "amplitude": 0.06, "phase": 5.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(510.0, 970.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 5.6},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2670.0, 2250.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 1.2},
			{"frequency": 4, "amplitude": 0.06, "phase": 3.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2510.0, 2530.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 1.4},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2470.0, 2590.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 3.0},
			{"frequency": 4, "amplitude": 0.06, "phase": 1.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2590.0, 1050.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 2.4},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2710.0, 2270.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 0.5},
			{"frequency": 3, "amplitude": 0.04, "phase": 4.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2550.0, 2550.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 1.5},
			{"frequency": 2, "amplitude": 0.05, "phase": 1.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(590.0, 790.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 5.7},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2510.0, 2610.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.06, "phase": 6.1},
			{"frequency": 2, "amplitude": 0.06, "phase": 5.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2790.0, 2210.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 0.0},
			{"frequency": 4, "amplitude": 0.05, "phase": 3.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(530.0, 770.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.3},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2770.0, 2310.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.4},
			{"frequency": 3, "amplitude": 0.05, "phase": 1.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2490.0, 2730.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 0.4},
			{"frequency": 2, "amplitude": 0.06, "phase": 1.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2530.0, 2690.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 1.4},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(490.0, 750.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 6.0},
			{"frequency": 3, "amplitude": 0.06, "phase": 5.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(430.0, 810.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.4},
			{"frequency": 2, "amplitude": 0.05, "phase": 5.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2810.0, 2330.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 5.3},
			{"frequency": 2, "amplitude": 0.06, "phase": 0.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(450.0, 710.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.7},
			{"frequency": 2, "amplitude": 0.05, "phase": 3.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2910.0, 2250.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 4.1},
			{"frequency": 2, "amplitude": 0.06, "phase": 4.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(390.0, 690.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.4},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2930.0, 2410.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 0.9},
			{"frequency": 4, "amplitude": 0.06, "phase": 1.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(350.0, 670.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 3.6},
			{"frequency": 2, "amplitude": 0.06, "phase": 0.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2990.0, 2430.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.2},
			{"frequency": 4, "amplitude": 0.05, "phase": 2.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(290.0, 630.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 2.5},
			{"frequency": 2, "amplitude": 0.05, "phase": 2.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(250.0, 610.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 3.5},
			{"frequency": 2, "amplitude": 0.06, "phase": 5.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3050.0, 2470.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 2.4},
			{"frequency": 2, "amplitude": 0.05, "phase": 5.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3090.0, 2510.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 0.9},
			{"frequency": 2, "amplitude": 0.06, "phase": 3.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(150.0, 550.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 4.8},
			{"frequency": 3, "amplitude": 0.05, "phase": 5.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3190.0, 2470.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 3.7},
			{"frequency": 3, "amplitude": 0.05, "phase": 3.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3170.0, 2570.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 2.1},
			{"frequency": 2, "amplitude": 0.05, "phase": 1.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3150.0, 2610.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 3.4},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3230.0, 2510.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 0.1},
			{"frequency": 3, "amplitude": 0.05, "phase": 4.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3230.0, 2590.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 0.5},
			{"frequency": 4, "amplitude": 0.05, "phase": 2.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3290.0, 2530.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 4.3},
			{"frequency": 4, "amplitude": 0.06, "phase": 2.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3310.0, 2650.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.06, "phase": 3.7},
			{"frequency": 4, "amplitude": 0.05, "phase": 3.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3350.0, 2670.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 1.4},
			{"frequency": 2, "amplitude": 0.06, "phase": 6.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3370.0, 2710.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.6},
			{"frequency": 4, "amplitude": 0.04, "phase": 5.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3430.0, 2630.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 0.2},
			{"frequency": 4, "amplitude": 0.06, "phase": 5.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3410.0, 2710.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 1.1},
			{"frequency": 4, "amplitude": 0.06, "phase": 4.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3490.0, 2670.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 2.1},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3470.0, 2750.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 0.5},
			{"frequency": 4, "amplitude": 0.04, "phase": 2.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3550.0, 2710.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 0.7},
			{"frequency": 3, "amplitude": 0.06, "phase": 3.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3530.0, 2790.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 2.4},
			{"frequency": 4, "amplitude": 0.05, "phase": 1.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3590.0, 2730.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 5.0},
			{"frequency": 4, "amplitude": 0.06, "phase": 1.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3570.0, 2810.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 0.8},
			{"frequency": 3, "amplitude": 0.06, "phase": 4.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3630.0, 2770.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.5},
			{"frequency": 3, "amplitude": 0.05, "phase": 3.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3690.0, 2790.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.6},
			{"frequency": 3, "amplitude": 0.05, "phase": 1.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3490.0, 3170.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.8},
			{"frequency": 4, "amplitude": 0.05, "phase": 2.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3730.0, 2810.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 1.1},
			{"frequency": 2, "amplitude": 0.05, "phase": 2.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3750.0, 2850.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 3.6},
			{"frequency": 3, "amplitude": 0.05, "phase": 1.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3790.0, 2830.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 5.9},
			{"frequency": 3, "amplitude": 0.06, "phase": 0.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3770.0, 2930.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 0.6},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3870.0, 2830.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 2.9},
			{"frequency": 3, "amplitude": 0.05, "phase": 3.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3930.0, 2870.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 3.3},
			{"frequency": 3, "amplitude": 0.06, "phase": 1.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3950.0, 2930.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 1.7},
			{"frequency": 3, "amplitude": 0.04, "phase": 6.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3970.0, 2890.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 1.5},
			{"frequency": 3, "amplitude": 0.05, "phase": 1.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3950.0, 2970.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 3.5},
			{"frequency": 2, "amplitude": 0.05, "phase": 5.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4010.0, 2930.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 5.5},
			{"frequency": 3, "amplitude": 0.06, "phase": 0.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4030.0, 2890.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 0.3},
			{"frequency": 2, "amplitude": 0.06, "phase": 4.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4010.0, 2970.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 1.1},
			{"frequency": 4, "amplitude": 0.05, "phase": 1.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4250.0, 2430.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 5.8},
			{"frequency": 3, "amplitude": 0.06, "phase": 3.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4050.0, 2990.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 3.7},
			{"frequency": 3, "amplitude": 0.05, "phase": 5.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4070.0, 2950.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 2.5},
			{"frequency": 4, "amplitude": 0.05, "phase": 2.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4110.0, 2910.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.06, "phase": 0.9},
			{"frequency": 4, "amplitude": 0.05, "phase": 0.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4130.0, 2990.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 2.0},
			{"frequency": 3, "amplitude": 0.05, "phase": 2.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4150.0, 2950.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 5.4},
			{"frequency": 2, "amplitude": 0.05, "phase": 4.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4170.0, 2910.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.1},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4170.0, 3010.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.4},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4250.0, 2870.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 0.0},
			{"frequency": 4, "amplitude": 0.05, "phase": 3.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4230.0, 2930.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 5.7},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4270.0, 2910.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 2.2},
			{"frequency": 3, "amplitude": 0.05, "phase": 5.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4230.0, 3010.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 2.6},
			{"frequency": 4, "amplitude": 0.06, "phase": 0.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4290.0, 2950.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 4.9},
			{"frequency": 4, "amplitude": 0.05, "phase": 0.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4330.0, 2930.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 5.0},
			{"frequency": 3, "amplitude": 0.05, "phase": 3.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4310.0, 3030.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 5.4},
			{"frequency": 2, "amplitude": 0.05, "phase": 1.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4370.0, 2950.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 2.4},
			{"frequency": 3, "amplitude": 0.05, "phase": 5.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4410.0, 2930.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.06, "phase": 6.2},
			{"frequency": 2, "amplitude": 0.06, "phase": 6.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4370.0, 3030.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 1.7},
			{"frequency": 4, "amplitude": 0.04, "phase": 5.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4410.0, 2990.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 2.4},
			{"frequency": 4, "amplitude": 0.06, "phase": 2.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4450.0, 2950.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 1.5},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4430.0, 3030.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 5.1},
			{"frequency": 4, "amplitude": 0.05, "phase": 1.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4510.0, 2950.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 2.6},
			{"frequency": 3, "amplitude": 0.05, "phase": 1.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4490.0, 3050.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 2.1},
			{"frequency": 2, "amplitude": 0.04, "phase": 1.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4570.0, 2970.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 1.0},
			{"frequency": 2, "amplitude": 0.05, "phase": 2.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4550.0, 3050.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 5.9},
			{"frequency": 2, "amplitude": 0.04, "phase": 5.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4630.0, 2970.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.4},
			{"frequency": 4, "amplitude": 0.06, "phase": 4.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4650.0, 3050.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 4.6},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4690.0, 2990.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 2.7},
			{"frequency": 3, "amplitude": 0.05, "phase": 4.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4690.0, 3070.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 2.3},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4770.0, 2990.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 4.1},
			{"frequency": 2, "amplitude": 0.04, "phase": 2.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4750.0, 3070.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 4.0},
			{"frequency": 4, "amplitude": 0.05, "phase": 5.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4830.0, 2990.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 5.1},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4830.0, 3090.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 3.0},
			{"frequency": 2, "amplitude": 0.05, "phase": 5.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4890.0, 3090.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 5.8},
			{"frequency": 3, "amplitude": 0.05, "phase": 4.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4930.0, 3010.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 2.6},
			{"frequency": 4, "amplitude": 0.05, "phase": 5.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4990.0, 3010.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.06, "phase": 4.3},
			{"frequency": 3, "amplitude": 0.05, "phase": 0.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4970.0, 3110.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.6},
			{"frequency": 3, "amplitude": 0.06, "phase": 2.8},
		]}, # tree row / shelterbelt
	],

	"road_width_m": 6.0,
	"road_waypoints_m": [
		Vector2(4900.0, 2975.0),
		Vector2(3805.0, 2809.0),
		Vector2(2494.0, 1997.0),
		Vector2(2164.0, 2365.0),
		Vector2(802.0, 1522.0),
	],

	"player": {
		"deployment_zone": Rect2(150.0 * PIXELS_PER_METER, 100.0 * PIXELS_PER_METER, 2200.0 * PIXELS_PER_METER, 3300.0 * PIXELS_PER_METER),
		"mortar_deployment_zone": Rect2(30.0 * PIXELS_PER_METER, 60.0 * PIXELS_PER_METER, 1950.0 * PIXELS_PER_METER, 3400.0 * PIXELS_PER_METER),
		"spotter_deployment_zone": Rect2(30.0 * PIXELS_PER_METER, 30.0 * PIXELS_PER_METER, 4940.0 * PIXELS_PER_METER, 3440.0 * PIXELS_PER_METER),
		# Chosen by scanning the deployment area with the game's own
		# has_direct_los/elevation model (siting.js): each squad the point
		# within ~350m of the village that sees the most of the real road,
		# clear of the road bed itself and of any building.
		"default_squad_positions": [
			Vector2(1502.0, 2030.0) * PIXELS_PER_METER,
			Vector2(1412.0, 2005.0) * PIXELS_PER_METER,
			Vector2(1313.0, 1976.0) * PIXELS_PER_METER,
		],
		# The least-exposed point found within reach of the village — real
		# flat-to-gently-rolling farmland has no spot hidden from a 5km
		# road end to end, so this is the best available cover, not a
		# guaranteed mask (same standard the mortar's own relocation logic
		# already uses live). Clear of every building block.
		"mortar_default_position": Vector2(1448.0, 1496.0) * PIXELS_PER_METER,
		# Inside a real tree patch, picked for the clearest sightline to
		# the road among every patch within reach of the village.
		"spotter_default_position": Vector2(2309.0, 2190.0) * PIXELS_PER_METER,
	},

	"enemy": {
		"spawn_x": 4900.0 * PIXELS_PER_METER, # matches the road's own easternmost waypoint
		"squad_spread_min_offset_m": -260.0,
		"squad_spread_max_offset_m": 260.0,
		"mortar_rear_x_m": 4700.0, # 200m behind spawn_x, same offset as every other map
		# 1600m span (or as much of it as fits the map's own height) centered
		# on the road's own first waypoint — see the other maps' identical
		# comment for the real citation (FM 7-90 Ch.6, up to 300m between
		# separate firing positions) and why an exact 4-gaps-of-300m layout
		# left no margin at ENEMY_MORTAR_COUNT_MAX.
		"mortar_spread_min_y_m": 2175.0,
		"mortar_spread_max_y_m": 3500.0,
		# Deep enough into the 1500m west flank to be a real flank, same
		# 2/3-in proportion as every other map.
		"flank_waypoint_x": -1000.0 * PIXELS_PER_METER,
		"flank_waypoint_arrival_radius": 350.0 * PIXELS_PER_METER, # must stay > ENEMY_SURROUND_STANDOFF_RADIUS (300m) — see that constant's own doc comment
	},
},

## This map depicts Pishchane, a small settlement in Kalmiuskyi Raion,
## Donetsk Oblast, built from real satellite imagery around the coordinates
## 47.768118, 37.878843 — a real farm/livestock complex, a residential strip
## just north of it, and a stream running through open farmland to the
## south-west. Unlike Moshchun and Pervomaiske, no specific documented
## engagement is claimed for this exact spot — this part of Donetsk Oblast
## has been outside Ukrainian government control since 2014, not a place
## that changed hands in 2022, so there is no real battle to depict here.
## The terrain is real; the engagement fought over it is a hypothetical
## one, same fictional-tactical premise (a Russian assault probing from
## the east) as every other map in this game.
##
## REBUILT from real data (2026-09), the same pipeline as Svystunivka
## Heights (the anchor coordinates are unchanged — this spot was already
## real): SRTM 30m elevation (OpenTopoData, 16 hills fit to it); BUILDINGS
## from OpenStreetMap (ODbL, © OpenStreetMap contributors) PLUS a colour/
## texture detector for the built-up ground OSM had no footprints for
## (only 16 buildings were tagged here at all) — 23 blocks total, covering
## the residential streets and the farm compound; the ROAD is the real
## route (Dijkstra over OSM highways from the map's east edge to the
## village — genuinely EAST TO WEST now, so the long-standing exception
## test_map_integrity.gd carried for this map's road being listed the
## other way is gone); TREE COVER from the same imagery classification
## (240 patches, about 12-13% of the frame — denser than the original
## hand-placed ravine chain). No watercourse runs close enough to the real
## route to matter (checked directly against OSM water data), so this map
## still omits the "river" key, same as before.
##
## Compass north points straight up: the real attack axis (from the open
## farmland to the real east) already matches this game's standing east-
## attacker/west-defender convention, so no rotation is needed.
"pishchane": {
	"name": "Pishchane",
	"location_subtitle": "Kalmiuskyi Raion, Donetsk Oblast",
	# The real coordinates this map was built around — shown on the map's
	# own location readout (see main.gd's _location_label) so a curious
	# player can look the actual place up.
	"coordinates": "47.768118, 37.878843",
	"compass_north_screen_direction": Vector2(0.0, -1.0),

	"width_m": 5000.0,
	"height_m": 3500.0,
	"west_flank_width_m": 1500.0,

	"village_center": Vector2(1425.0, 1728.0) * PIXELS_PER_METER,

	# The fitted model's own constant term — see this dictionary's own doc
	# comment for the real elevation sourcing.
	"elevation_baseline_m": 154.7,

	## Least-squares fit to real SRTM data — see this dictionary's own doc
	## comment. Ordered nearest the village first.
	"hills": [
		{"center_m": Vector2(1600.0, 1850.0), "radius_m": 380.0, "height_m": 7.6, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.12, "phase": 5.5},
			{"frequency": 3, "amplitude": 0.07, "phase": 2.7},
		]},
		{"center_m": Vector2(900.0, 1350.0), "radius_m": 260.0, "height_m": 12.8, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.10, "phase": 2.1},
			{"frequency": 3, "amplitude": 0.09, "phase": 6.1},
		]},
		{"center_m": Vector2(1000.0, 2750.0), "radius_m": 180.0, "height_m": 16.3, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.11, "phase": 2.5},
			{"frequency": 4, "amplitude": 0.08, "phase": 3.8},
		]},
		{"center_m": Vector2(2100.0, 750.0), "radius_m": 550.0, "height_m": 14.7, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.13, "phase": 5.9},
			{"frequency": 2, "amplitude": 0.08, "phase": 5.4},
		]},
		{"center_m": Vector2(1900.0, 2850.0), "radius_m": 380.0, "height_m": 19.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.11, "phase": 4.0},
			{"frequency": 3, "amplitude": 0.08, "phase": 0.1},
		]},
		{"center_m": Vector2(3100.0, 2450.0), "radius_m": 800.0, "height_m": 23.6, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.12, "phase": 3.6},
			{"frequency": 4, "amplitude": 0.09, "phase": 2.1},
		]},
		{"center_m": Vector2(-300.0, 1350.0), "radius_m": 380.0, "height_m": 22.5, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.13, "phase": 6.1},
			{"frequency": 2, "amplitude": 0.10, "phase": 6.1},
		]},
		{"center_m": Vector2(900.0, -150.0), "radius_m": 800.0, "height_m": 51.9, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.10, "phase": 2.7},
			{"frequency": 2, "amplitude": 0.07, "phase": 0.3},
		]},
		{"center_m": Vector2(2400.0, -150.0), "radius_m": 380.0, "height_m": 15.7, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.12, "phase": 5.4},
			{"frequency": 3, "amplitude": 0.08, "phase": 3.7},
		]},
		{"center_m": Vector2(3900.0, 1550.0), "radius_m": 380.0, "height_m": 12.4, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.11, "phase": 2.7},
			{"frequency": 3, "amplitude": 0.09, "phase": 1.9},
		]},
		{"center_m": Vector2(-1200.0, 1550.0), "radius_m": 380.0, "height_m": 11.8, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.13, "phase": 2.2},
			{"frequency": 4, "amplitude": 0.07, "phase": 2.0},
		]},
		{"center_m": Vector2(-900.0, 350.0), "radius_m": 550.0, "height_m": 37.7, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.13, "phase": 5.1},
			{"frequency": 3, "amplitude": 0.08, "phase": 2.7},
		]},
		{"center_m": Vector2(3900.0, -150.0), "radius_m": 1200.0, "height_m": 59.7, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.11, "phase": 4.2},
			{"frequency": 4, "amplitude": 0.09, "phase": 2.3},
		]},
		{"center_m": Vector2(4900.0, 850.0), "radius_m": 260.0, "height_m": 20.1, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.12, "phase": 4.7},
			{"frequency": 3, "amplitude": 0.07, "phase": 5.7},
		]},
		{"center_m": Vector2(5200.0, 1850.0), "radius_m": 550.0, "height_m": 42.2, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.13, "phase": 5.8},
			{"frequency": 4, "amplitude": 0.09, "phase": 6.0},
		]},
		{"center_m": Vector2(5000.0, 3150.0), "radius_m": 380.0, "height_m": 20.9, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.11, "phase": 5.0},
			{"frequency": 4, "amplitude": 0.07, "phase": 4.3},
		]},
	],

	## Building blocks aggregated from real footprints (OpenStreetMap, plus
	## imagery detection where noted in the doc comment above).
	"terrain_zones": [
		{"rect": Rect2(820.0 * PIXELS_PER_METER, 860.0 * PIXELS_PER_METER, 100.0 * PIXELS_PER_METER, 100.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(580.0 * PIXELS_PER_METER, 920.0 * PIXELS_PER_METER, 60.0 * PIXELS_PER_METER, 120.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(520.0 * PIXELS_PER_METER, 1040.0 * PIXELS_PER_METER, 120.0 * PIXELS_PER_METER, 120.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(640.0 * PIXELS_PER_METER, 920.0 * PIXELS_PER_METER, 100.0 * PIXELS_PER_METER, 120.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(640.0 * PIXELS_PER_METER, 1040.0 * PIXELS_PER_METER, 120.0 * PIXELS_PER_METER, 140.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(660.0 * PIXELS_PER_METER, 1180.0 * PIXELS_PER_METER, 120.0 * PIXELS_PER_METER, 40.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(780.0 * PIXELS_PER_METER, 1180.0 * PIXELS_PER_METER, 140.0 * PIXELS_PER_METER, 140.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(900.0 * PIXELS_PER_METER, 1000.0 * PIXELS_PER_METER, 80.0 * PIXELS_PER_METER, 60.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(760.0 * PIXELS_PER_METER, 1060.0 * PIXELS_PER_METER, 160.0 * PIXELS_PER_METER, 120.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(920.0 * PIXELS_PER_METER, 1180.0 * PIXELS_PER_METER, 160.0 * PIXELS_PER_METER, 140.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(1160.0 * PIXELS_PER_METER, 1120.0 * PIXELS_PER_METER, 100.0 * PIXELS_PER_METER, 80.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(600.0 * PIXELS_PER_METER, 1420.0 * PIXELS_PER_METER, 40.0 * PIXELS_PER_METER, 80.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(860.0 * PIXELS_PER_METER, 1440.0 * PIXELS_PER_METER, 100.0 * PIXELS_PER_METER, 120.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(1260.0 * PIXELS_PER_METER, 1700.0 * PIXELS_PER_METER, 100.0 * PIXELS_PER_METER, 160.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(1360.0 * PIXELS_PER_METER, 1540.0 * PIXELS_PER_METER, 120.0 * PIXELS_PER_METER, 160.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(1360.0 * PIXELS_PER_METER, 1700.0 * PIXELS_PER_METER, 120.0 * PIXELS_PER_METER, 120.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(1480.0 * PIXELS_PER_METER, 1640.0 * PIXELS_PER_METER, 60.0 * PIXELS_PER_METER, 60.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(1480.0 * PIXELS_PER_METER, 1700.0 * PIXELS_PER_METER, 120.0 * PIXELS_PER_METER, 60.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(1000.0 * PIXELS_PER_METER, 1840.0 * PIXELS_PER_METER, 80.0 * PIXELS_PER_METER, 60.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(1420.0 * PIXELS_PER_METER, 1840.0 * PIXELS_PER_METER, 80.0 * PIXELS_PER_METER, 100.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(1660.0 * PIXELS_PER_METER, 2060.0 * PIXELS_PER_METER, 80.0 * PIXELS_PER_METER, 100.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(1390.0 * PIXELS_PER_METER, 1320.0 * PIXELS_PER_METER, 105.0 * PIXELS_PER_METER, 110.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(925.0 * PIXELS_PER_METER, 1760.0 * PIXELS_PER_METER, 45.0 * PIXELS_PER_METER, 90.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
	],

	## Patches traced from satellite imagery — see the doc comment: wooded
	## blocks/thickets first, tree rows/shelterbelts after.
	"forest_patches": [
		{"center_m": Vector2(1230.0, 1350.0), "radius_m": 65.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.15, "phase": 1.7},
			{"frequency": 3, "amplitude": 0.08, "phase": 2.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(1330.0, 1190.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.13, "phase": 5.4},
			{"frequency": 2, "amplitude": 0.10, "phase": 0.9},
		]}, # wooded block / thicket
		{"center_m": Vector2(1310.0, 1110.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.12, "phase": 3.6},
			{"frequency": 2, "amplitude": 0.08, "phase": 5.3},
		]}, # wooded block / thicket
		{"center_m": Vector2(1110.0, 1090.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.14, "phase": 1.7},
			{"frequency": 2, "amplitude": 0.11, "phase": 5.3},
		]}, # wooded block / thicket
		{"center_m": Vector2(990.0, 2450.0), "radius_m": 65.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.12, "phase": 0.1},
			{"frequency": 4, "amplitude": 0.11, "phase": 3.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(1050.0, 2490.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.15, "phase": 6.2},
			{"frequency": 4, "amplitude": 0.11, "phase": 0.3},
		]}, # wooded block / thicket
		{"center_m": Vector2(650.0, 2070.0), "radius_m": 57.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.16, "phase": 0.6},
			{"frequency": 4, "amplitude": 0.11, "phase": 5.1},
		]}, # wooded block / thicket
		{"center_m": Vector2(590.0, 1930.0), "radius_m": 73.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 4.0},
			{"frequency": 2, "amplitude": 0.11, "phase": 0.6},
		]}, # wooded block / thicket
		{"center_m": Vector2(570.0, 1850.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.15, "phase": 5.6},
			{"frequency": 4, "amplitude": 0.09, "phase": 1.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(670.0, 1310.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.12, "phase": 5.4},
			{"frequency": 3, "amplitude": 0.11, "phase": 5.1},
		]}, # wooded block / thicket
		{"center_m": Vector2(610.0, 2130.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.14, "phase": 4.9},
			{"frequency": 2, "amplitude": 0.10, "phase": 2.7},
		]}, # wooded block / thicket
		{"center_m": Vector2(530.0, 1750.0), "radius_m": 65.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.15, "phase": 3.2},
			{"frequency": 3, "amplitude": 0.11, "phase": 4.6},
		]}, # wooded block / thicket
		{"center_m": Vector2(570.0, 1470.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 2.5},
			{"frequency": 4, "amplitude": 0.09, "phase": 3.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(690.0, 2330.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.13, "phase": 1.7},
			{"frequency": 2, "amplitude": 0.10, "phase": 5.0},
		]}, # wooded block / thicket
		{"center_m": Vector2(770.0, 1070.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.14, "phase": 0.2},
			{"frequency": 3, "amplitude": 0.09, "phase": 0.9},
		]}, # wooded block / thicket
		{"center_m": Vector2(610.0, 2210.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.15, "phase": 6.0},
			{"frequency": 2, "amplitude": 0.11, "phase": 1.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(510.0, 1930.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.12, "phase": 0.3},
			{"frequency": 4, "amplitude": 0.11, "phase": 3.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(490.0, 1690.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.13, "phase": 3.7},
			{"frequency": 4, "amplitude": 0.09, "phase": 4.7},
		]}, # wooded block / thicket
		{"center_m": Vector2(510.0, 1490.0), "radius_m": 57.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.12, "phase": 5.5},
			{"frequency": 4, "amplitude": 0.09, "phase": 4.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(850.0, 2550.0), "radius_m": 65.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.13, "phase": 4.0},
			{"frequency": 4, "amplitude": 0.10, "phase": 5.6},
		]}, # wooded block / thicket
		{"center_m": Vector2(630.0, 2330.0), "radius_m": 54.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 0.4},
			{"frequency": 4, "amplitude": 0.11, "phase": 4.5},
		]}, # wooded block / thicket
		{"center_m": Vector2(450.0, 1530.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.15, "phase": 5.8},
			{"frequency": 2, "amplitude": 0.11, "phase": 4.5},
		]}, # wooded block / thicket
		{"center_m": Vector2(410.0, 1830.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 0.8},
			{"frequency": 4, "amplitude": 0.10, "phase": 3.7},
		]}, # wooded block / thicket
		{"center_m": Vector2(670.0, 970.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.12, "phase": 0.1},
			{"frequency": 3, "amplitude": 0.09, "phase": 0.9},
		]}, # wooded block / thicket
		{"center_m": Vector2(510.0, 2370.0), "radius_m": 57.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.14, "phase": 0.1},
			{"frequency": 4, "amplitude": 0.10, "phase": 4.4},
		]}, # wooded block / thicket
		{"center_m": Vector2(570.0, 1030.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.14, "phase": 2.5},
			{"frequency": 3, "amplitude": 0.11, "phase": 4.6},
		]}, # wooded block / thicket
		{"center_m": Vector2(330.0, 1930.0), "radius_m": 111.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.13, "phase": 4.7},
			{"frequency": 4, "amplitude": 0.10, "phase": 4.3},
		]}, # wooded block / thicket
		{"center_m": Vector2(430.0, 2410.0), "radius_m": 65.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 5.6},
			{"frequency": 4, "amplitude": 0.12, "phase": 4.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(970.0, 2910.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.15, "phase": 3.0},
			{"frequency": 3, "amplitude": 0.09, "phase": 4.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(210.0, 1970.0), "radius_m": 107.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.15, "phase": 3.4},
			{"frequency": 4, "amplitude": 0.09, "phase": 1.1},
		]}, # wooded block / thicket
		{"center_m": Vector2(350.0, 2410.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 4.0},
			{"frequency": 2, "amplitude": 0.08, "phase": 1.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(1930.0, 470.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.15, "phase": 4.7},
			{"frequency": 2, "amplitude": 0.09, "phase": 4.0},
		]}, # wooded block / thicket
		{"center_m": Vector2(130.0, 1890.0), "radius_m": 57.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.12, "phase": 6.0},
			{"frequency": 2, "amplitude": 0.08, "phase": 4.0},
		]}, # wooded block / thicket
		{"center_m": Vector2(310.0, 2450.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.14, "phase": 0.5},
			{"frequency": 4, "amplitude": 0.11, "phase": 2.1},
		]}, # wooded block / thicket
		{"center_m": Vector2(210.0, 2510.0), "radius_m": 65.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 3.6},
			{"frequency": 4, "amplitude": 0.11, "phase": 0.1},
		]}, # wooded block / thicket
		{"center_m": Vector2(130.0, 2530.0), "radius_m": 57.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.15, "phase": 4.2},
			{"frequency": 4, "amplitude": 0.09, "phase": 3.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(70.0, 2550.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 0.8},
			{"frequency": 4, "amplitude": 0.09, "phase": 0.7},
		]}, # wooded block / thicket
		{"center_m": Vector2(2110.0, 170.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.15, "phase": 4.4},
			{"frequency": 2, "amplitude": 0.09, "phase": 1.0},
		]}, # wooded block / thicket
		{"center_m": Vector2(2210.0, 170.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.14, "phase": 2.8},
			{"frequency": 3, "amplitude": 0.08, "phase": 3.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(1630.0, 10.0), "radius_m": 54.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.15, "phase": 0.8},
			{"frequency": 2, "amplitude": 0.11, "phase": 4.6},
		]}, # wooded block / thicket
		{"center_m": Vector2(-50.0, 2630.0), "radius_m": 73.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.12, "phase": 6.1},
			{"frequency": 2, "amplitude": 0.11, "phase": 5.3},
		]}, # wooded block / thicket
		{"center_m": Vector2(-10.0, 2710.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.15, "phase": 1.6},
			{"frequency": 2, "amplitude": 0.09, "phase": 4.9},
		]}, # wooded block / thicket
		{"center_m": Vector2(-130.0, 2670.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.12, "phase": 4.2},
			{"frequency": 2, "amplitude": 0.09, "phase": 4.9},
		]}, # wooded block / thicket
		{"center_m": Vector2(2850.0, 330.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.15, "phase": 3.9},
			{"frequency": 2, "amplitude": 0.12, "phase": 6.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(-630.0, 1870.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.13, "phase": 2.8},
			{"frequency": 2, "amplitude": 0.10, "phase": 2.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(3430.0, 3030.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.14, "phase": 4.9},
			{"frequency": 2, "amplitude": 0.10, "phase": 3.5},
		]}, # wooded block / thicket
		{"center_m": Vector2(3470.0, 3070.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.13, "phase": 3.2},
			{"frequency": 4, "amplitude": 0.08, "phase": 5.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(3610.0, 530.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.14, "phase": 2.1},
			{"frequency": 3, "amplitude": 0.08, "phase": 1.3},
		]}, # wooded block / thicket
		{"center_m": Vector2(3550.0, 3090.0), "radius_m": 65.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.15, "phase": 5.3},
			{"frequency": 2, "amplitude": 0.09, "phase": 3.6},
		]}, # wooded block / thicket
		{"center_m": Vector2(3550.0, 3170.0), "radius_m": 54.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.15, "phase": 4.9},
			{"frequency": 4, "amplitude": 0.10, "phase": 1.7},
		]}, # wooded block / thicket
		{"center_m": Vector2(3730.0, 530.0), "radius_m": 65.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.13, "phase": 3.5},
			{"frequency": 3, "amplitude": 0.08, "phase": 0.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(3710.0, 410.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.12, "phase": 5.6},
			{"frequency": 2, "amplitude": 0.09, "phase": 1.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(4130.0, 2090.0), "radius_m": 57.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.13, "phase": 4.4},
			{"frequency": 2, "amplitude": 0.10, "phase": 4.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(4170.0, 2210.0), "radius_m": 73.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.13, "phase": 5.6},
			{"frequency": 3, "amplitude": 0.10, "phase": 1.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(4190.0, 2310.0), "radius_m": 73.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.12, "phase": 3.7},
			{"frequency": 3, "amplitude": 0.11, "phase": 6.1},
		]}, # wooded block / thicket
		{"center_m": Vector2(-1350.0, 1450.0), "radius_m": 57.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.13, "phase": 2.3},
			{"frequency": 2, "amplitude": 0.10, "phase": 3.5},
		]}, # wooded block / thicket
		{"center_m": Vector2(4290.0, 2490.0), "radius_m": 57.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.14, "phase": 3.5},
			{"frequency": 3, "amplitude": 0.10, "phase": 2.4},
		]}, # wooded block / thicket
		{"center_m": Vector2(-1370.0, 1390.0), "radius_m": 54.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.15, "phase": 5.5},
			{"frequency": 3, "amplitude": 0.08, "phase": 1.7},
		]}, # wooded block / thicket
		{"center_m": Vector2(-1490.0, 2670.0), "radius_m": 54.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.13, "phase": 4.4},
			{"frequency": 2, "amplitude": 0.10, "phase": 5.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(4670.0, 2910.0), "radius_m": 54.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.14, "phase": 2.7},
			{"frequency": 4, "amplitude": 0.08, "phase": 0.4},
		]}, # wooded block / thicket
		{"center_m": Vector2(1770.0, 1750.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.2},
			{"frequency": 4, "amplitude": 0.05, "phase": 2.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1290.0, 1390.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 4.0},
			{"frequency": 2, "amplitude": 0.05, "phase": 4.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1190.0, 1410.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 3.2},
			{"frequency": 4, "amplitude": 0.06, "phase": 2.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1150.0, 1430.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 0.6},
			{"frequency": 2, "amplitude": 0.04, "phase": 5.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1530.0, 1270.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 1.1},
			{"frequency": 4, "amplitude": 0.04, "phase": 4.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1510.0, 1230.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.1},
			{"frequency": 3, "amplitude": 0.05, "phase": 5.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1110.0, 1370.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 5.2},
			{"frequency": 3, "amplitude": 0.04, "phase": 2.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1470.0, 1170.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 1.4},
			{"frequency": 3, "amplitude": 0.06, "phase": 6.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1270.0, 1190.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 5.1},
			{"frequency": 4, "amplitude": 0.05, "phase": 1.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1450.0, 1130.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 4.3},
			{"frequency": 2, "amplitude": 0.05, "phase": 2.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1410.0, 1130.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 5.0},
			{"frequency": 4, "amplitude": 0.06, "phase": 3.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1090.0, 1270.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.6},
			{"frequency": 3, "amplitude": 0.05, "phase": 1.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1050.0, 1250.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.7},
			{"frequency": 3, "amplitude": 0.06, "phase": 0.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1470.0, 1070.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 1.9},
			{"frequency": 2, "amplitude": 0.05, "phase": 4.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1190.0, 1130.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.06, "phase": 1.3},
			{"frequency": 2, "amplitude": 0.06, "phase": 1.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1490.0, 1030.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.9},
			{"frequency": 3, "amplitude": 0.05, "phase": 2.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(930.0, 1310.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 5.5},
			{"frequency": 2, "amplitude": 0.04, "phase": 1.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1430.0, 1030.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 0.9},
			{"frequency": 4, "amplitude": 0.05, "phase": 5.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(890.0, 1330.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 0.5},
			{"frequency": 4, "amplitude": 0.05, "phase": 1.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(950.0, 1250.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.1},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1510.0, 990.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 4.3},
			{"frequency": 4, "amplitude": 0.06, "phase": 5.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(770.0, 2010.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 1.3},
			{"frequency": 4, "amplitude": 0.05, "phase": 2.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1150.0, 2470.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 0.8},
			{"frequency": 2, "amplitude": 0.06, "phase": 3.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1550.0, 950.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.6},
			{"frequency": 3, "amplitude": 0.06, "phase": 1.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(710.0, 1950.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.5},
			{"frequency": 3, "amplitude": 0.05, "phase": 4.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1030.0, 1070.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 1.6},
			{"frequency": 2, "amplitude": 0.04, "phase": 0.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(670.0, 1810.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 6.0},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(710.0, 2030.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 2.6},
			{"frequency": 3, "amplitude": 0.06, "phase": 0.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1070.0, 1030.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 3.0},
			{"frequency": 3, "amplitude": 0.04, "phase": 2.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1590.0, 910.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 2.0},
			{"frequency": 4, "amplitude": 0.06, "phase": 1.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(670.0, 1930.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 5.0},
			{"frequency": 2, "amplitude": 0.05, "phase": 2.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(730.0, 1390.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 1.1},
			{"frequency": 2, "amplitude": 0.05, "phase": 3.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(650.0, 1770.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.06, "phase": 5.9},
			{"frequency": 4, "amplitude": 0.05, "phase": 5.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(750.0, 1310.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 0.6},
			{"frequency": 2, "amplitude": 0.06, "phase": 5.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(770.0, 1270.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 1.4},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(630.0, 1830.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 2.9},
			{"frequency": 2, "amplitude": 0.05, "phase": 6.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(650.0, 1990.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 2.0},
			{"frequency": 3, "amplitude": 0.05, "phase": 1.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(690.0, 1370.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 0.4},
			{"frequency": 2, "amplitude": 0.06, "phase": 5.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(610.0, 1610.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 6.2},
			{"frequency": 4, "amplitude": 0.04, "phase": 1.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1010.0, 990.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 4.7},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1630.0, 850.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 3.8},
			{"frequency": 4, "amplitude": 0.04, "phase": 1.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(670.0, 2130.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 4.4},
			{"frequency": 4, "amplitude": 0.06, "phase": 5.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(590.0, 1670.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 2.2},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(910.0, 2450.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 1.9},
			{"frequency": 4, "amplitude": 0.05, "phase": 0.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(630.0, 1450.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 2.3},
			{"frequency": 3, "amplitude": 0.05, "phase": 0.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(970.0, 970.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 0.2},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(590.0, 2010.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 1.2},
			{"frequency": 2, "amplitude": 0.05, "phase": 3.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1650.0, 810.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.1},
			{"frequency": 3, "amplitude": 0.06, "phase": 2.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(550.0, 1590.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.06, "phase": 2.4},
			{"frequency": 3, "amplitude": 0.05, "phase": 3.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(570.0, 2050.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 0.1},
			{"frequency": 2, "amplitude": 0.05, "phase": 5.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(830.0, 2470.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 4.7},
			{"frequency": 3, "amplitude": 0.06, "phase": 1.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(510.0, 1830.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 5.4},
			{"frequency": 4, "amplitude": 0.06, "phase": 3.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(610.0, 1290.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 6.2},
			{"frequency": 3, "amplitude": 0.05, "phase": 0.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(490.0, 1630.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.06, "phase": 3.3},
			{"frequency": 4, "amplitude": 0.05, "phase": 3.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1730.0, 750.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 2.3},
			{"frequency": 4, "amplitude": 0.04, "phase": 4.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(470.0, 1790.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 2.4},
			{"frequency": 4, "amplitude": 0.05, "phase": 6.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(650.0, 1150.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 0.0},
			{"frequency": 2, "amplitude": 0.05, "phase": 5.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(470.0, 1590.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 0.6},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(550.0, 2230.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.8},
			{"frequency": 2, "amplitude": 0.05, "phase": 3.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1270.0, 710.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 3.3},
			{"frequency": 4, "amplitude": 0.06, "phase": 2.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1750.0, 710.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 4.6},
			{"frequency": 2, "amplitude": 0.04, "phase": 0.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(570.0, 2350.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.8},
			{"frequency": 3, "amplitude": 0.06, "phase": 5.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(550.0, 1170.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 1.3},
			{"frequency": 4, "amplitude": 0.04, "phase": 6.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(510.0, 1210.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.8},
			{"frequency": 3, "amplitude": 0.06, "phase": 0.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1230.0, 650.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.0},
			{"frequency": 2, "amplitude": 0.06, "phase": 3.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1770.0, 650.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 4.0},
			{"frequency": 2, "amplitude": 0.05, "phase": 2.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(430.0, 1190.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 3.9},
			{"frequency": 4, "amplitude": 0.05, "phase": 3.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1850.0, 590.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 4.3},
			{"frequency": 4, "amplitude": 0.06, "phase": 4.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1870.0, 550.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 6.0},
			{"frequency": 3, "amplitude": 0.04, "phase": 0.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1010.0, 2950.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 4.2},
			{"frequency": 3, "amplitude": 0.06, "phase": 3.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1890.0, 510.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 1.9},
			{"frequency": 3, "amplitude": 0.06, "phase": 0.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(830.0, 630.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 1.7},
			{"frequency": 2, "amplitude": 0.06, "phase": 0.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1970.0, 430.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.5},
			{"frequency": 4, "amplitude": 0.05, "phase": 0.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(230.0, 2370.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 1.3},
			{"frequency": 2, "amplitude": 0.06, "phase": 0.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(250.0, 2450.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 1.9},
			{"frequency": 3, "amplitude": 0.06, "phase": 0.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(90.0, 2050.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 0.5},
			{"frequency": 4, "amplitude": 0.04, "phase": 3.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1990.0, 390.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 0.7},
			{"frequency": 4, "amplitude": 0.06, "phase": 2.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2670.0, 850.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 4.8},
			{"frequency": 2, "amplitude": 0.05, "phase": 5.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(50.0, 2070.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 2.8},
			{"frequency": 2, "amplitude": 0.06, "phase": 4.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2010.0, 350.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 5.7},
			{"frequency": 2, "amplitude": 0.06, "phase": 1.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2690.0, 810.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.9},
			{"frequency": 3, "amplitude": 0.05, "phase": 3.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2050.0, 330.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 3.7},
			{"frequency": 4, "amplitude": 0.05, "phase": 2.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(-10.0, 2090.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 2.9},
			{"frequency": 3, "amplitude": 0.06, "phase": 5.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2090.0, 290.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 5.6},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(30.0, 2390.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 1.2},
			{"frequency": 4, "amplitude": 0.06, "phase": 3.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2750.0, 730.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 1.4},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2110.0, 250.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 3.0},
			{"frequency": 4, "amplitude": 0.06, "phase": 1.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(-90.0, 2110.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 2.4},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(-10.0, 2410.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 0.5},
			{"frequency": 3, "amplitude": 0.04, "phase": 4.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2150.0, 230.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 1.5},
			{"frequency": 2, "amplitude": 0.05, "phase": 1.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1890.0, 110.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 5.7},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2050.0, 150.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.06, "phase": 6.1},
			{"frequency": 2, "amplitude": 0.06, "phase": 5.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2010.0, 130.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 0.0},
			{"frequency": 4, "amplitude": 0.05, "phase": 3.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1750.0, 70.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.3},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1950.0, 110.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.4},
			{"frequency": 3, "amplitude": 0.05, "phase": 1.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1810.0, 70.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 0.4},
			{"frequency": 2, "amplitude": 0.06, "phase": 1.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2810.0, 650.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 1.4},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(-170.0, 2130.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 6.0},
			{"frequency": 3, "amplitude": 0.06, "phase": 5.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1710.0, 50.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.4},
			{"frequency": 2, "amplitude": 0.05, "phase": 5.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2330.0, 250.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 5.3},
			{"frequency": 2, "amplitude": 0.06, "phase": 0.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2290.0, 210.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.7},
			{"frequency": 2, "amplitude": 0.05, "phase": 3.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1570.0, 10.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 4.1},
			{"frequency": 2, "amplitude": 0.06, "phase": 4.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2350.0, 210.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.4},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2430.0, 230.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 0.9},
			{"frequency": 4, "amplitude": 0.06, "phase": 1.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2550.0, 310.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 3.6},
			{"frequency": 2, "amplitude": 0.06, "phase": 0.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2530.0, 290.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.2},
			{"frequency": 4, "amplitude": 0.05, "phase": 2.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2230.0, 110.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 2.5},
			{"frequency": 2, "amplitude": 0.05, "phase": 2.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2870.0, 570.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 3.5},
			{"frequency": 2, "amplitude": 0.06, "phase": 5.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2510.0, 250.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 2.4},
			{"frequency": 2, "amplitude": 0.05, "phase": 5.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(990.0, 10.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 0.9},
			{"frequency": 2, "amplitude": 0.06, "phase": 3.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2690.0, 350.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 4.8},
			{"frequency": 3, "amplitude": 0.05, "phase": 5.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2590.0, 270.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 3.7},
			{"frequency": 3, "amplitude": 0.05, "phase": 3.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2250.0, 70.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 2.1},
			{"frequency": 2, "amplitude": 0.05, "phase": 1.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2650.0, 290.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 3.4},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2910.0, 530.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 0.1},
			{"frequency": 3, "amplitude": 0.05, "phase": 4.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2710.0, 310.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 0.5},
			{"frequency": 4, "amplitude": 0.05, "phase": 2.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2290.0, 30.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 4.3},
			{"frequency": 4, "amplitude": 0.06, "phase": 2.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2770.0, 330.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.06, "phase": 3.7},
			{"frequency": 4, "amplitude": 0.05, "phase": 3.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2930.0, 490.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 1.4},
			{"frequency": 2, "amplitude": 0.06, "phase": 6.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2910.0, 390.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.6},
			{"frequency": 4, "amplitude": 0.04, "phase": 5.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2910.0, 350.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 0.2},
			{"frequency": 4, "amplitude": 0.06, "phase": 5.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2970.0, 370.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 1.1},
			{"frequency": 4, "amplitude": 0.06, "phase": 4.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2870.0, 270.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 2.1},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3010.0, 390.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 0.5},
			{"frequency": 4, "amplitude": 0.04, "phase": 2.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2910.0, 230.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 0.7},
			{"frequency": 3, "amplitude": 0.06, "phase": 3.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3070.0, 390.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 2.4},
			{"frequency": 4, "amplitude": 0.05, "phase": 1.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3130.0, 410.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 5.0},
			{"frequency": 4, "amplitude": 0.06, "phase": 1.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3190.0, 430.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 0.8},
			{"frequency": 3, "amplitude": 0.06, "phase": 4.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2970.0, 150.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.5},
			{"frequency": 3, "amplitude": 0.05, "phase": 3.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3270.0, 450.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.6},
			{"frequency": 3, "amplitude": 0.05, "phase": 1.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3010.0, 110.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.8},
			{"frequency": 4, "amplitude": 0.05, "phase": 2.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3330.0, 470.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 1.1},
			{"frequency": 2, "amplitude": 0.05, "phase": 2.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3030.0, 70.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 3.6},
			{"frequency": 3, "amplitude": 0.05, "phase": 1.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3390.0, 470.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 5.9},
			{"frequency": 3, "amplitude": 0.06, "phase": 0.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3430.0, 490.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 0.6},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3070.0, 30.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 2.9},
			{"frequency": 3, "amplitude": 0.05, "phase": 3.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3510.0, 510.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 3.3},
			{"frequency": 3, "amplitude": 0.06, "phase": 1.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3550.0, 530.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 1.7},
			{"frequency": 3, "amplitude": 0.04, "phase": 6.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3830.0, 990.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 1.5},
			{"frequency": 3, "amplitude": 0.05, "phase": 1.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3690.0, 590.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 3.5},
			{"frequency": 2, "amplitude": 0.05, "phase": 5.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3630.0, 470.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 5.5},
			{"frequency": 3, "amplitude": 0.06, "phase": 0.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3810.0, 630.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 0.3},
			{"frequency": 2, "amplitude": 0.06, "phase": 4.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3790.0, 570.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 1.1},
			{"frequency": 4, "amplitude": 0.05, "phase": 1.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3830.0, 590.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 5.8},
			{"frequency": 3, "amplitude": 0.06, "phase": 3.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3810.0, 530.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 3.7},
			{"frequency": 3, "amplitude": 0.05, "phase": 5.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3810.0, 490.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 2.5},
			{"frequency": 4, "amplitude": 0.05, "phase": 2.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3730.0, 350.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.06, "phase": 0.9},
			{"frequency": 4, "amplitude": 0.05, "phase": 0.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3770.0, 410.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 2.0},
			{"frequency": 3, "amplitude": 0.05, "phase": 2.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3810.0, 430.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 5.4},
			{"frequency": 2, "amplitude": 0.05, "phase": 4.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3750.0, 310.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.1},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3930.0, 610.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.4},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4210.0, 1790.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 0.0},
			{"frequency": 4, "amplitude": 0.05, "phase": 3.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3990.0, 670.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 5.7},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3790.0, 270.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 2.2},
			{"frequency": 3, "amplitude": 0.05, "phase": 5.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4010.0, 630.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 2.6},
			{"frequency": 4, "amplitude": 0.06, "phase": 0.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3810.0, 230.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 4.9},
			{"frequency": 4, "amplitude": 0.05, "phase": 0.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4270.0, 1730.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 5.0},
			{"frequency": 3, "amplitude": 0.05, "phase": 3.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4070.0, 650.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 5.4},
			{"frequency": 2, "amplitude": 0.05, "phase": 1.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3850.0, 190.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 2.4},
			{"frequency": 3, "amplitude": 0.05, "phase": 5.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4150.0, 670.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.06, "phase": 6.2},
			{"frequency": 2, "amplitude": 0.06, "phase": 6.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3890.0, 130.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 1.7},
			{"frequency": 4, "amplitude": 0.04, "phase": 5.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3930.0, 70.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 2.4},
			{"frequency": 4, "amplitude": 0.06, "phase": 2.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4270.0, 690.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 1.5},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3950.0, 30.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 5.1},
			{"frequency": 4, "amplitude": 0.05, "phase": 1.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4310.0, 710.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 2.6},
			{"frequency": 3, "amplitude": 0.05, "phase": 1.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4390.0, 730.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 2.1},
			{"frequency": 2, "amplitude": 0.04, "phase": 1.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4470.0, 790.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 1.0},
			{"frequency": 2, "amplitude": 0.05, "phase": 2.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4490.0, 750.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 5.9},
			{"frequency": 2, "amplitude": 0.04, "phase": 5.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4550.0, 770.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.4},
			{"frequency": 4, "amplitude": 0.06, "phase": 4.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4630.0, 790.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 4.6},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4750.0, 1150.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 2.7},
			{"frequency": 3, "amplitude": 0.05, "phase": 4.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4770.0, 1110.0), "radius_m": 40.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 2.3},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4710.0, 810.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 4.1},
			{"frequency": 2, "amplitude": 0.04, "phase": 2.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4730.0, 870.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 4.0},
			{"frequency": 4, "amplitude": 0.05, "phase": 5.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4810.0, 1050.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 5.1},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4790.0, 830.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 3.0},
			{"frequency": 2, "amplitude": 0.05, "phase": 5.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4870.0, 990.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 5.8},
			{"frequency": 3, "amplitude": 0.05, "phase": 4.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4890.0, 950.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 2.6},
			{"frequency": 4, "amplitude": 0.05, "phase": 5.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4870.0, 850.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.06, "phase": 4.3},
			{"frequency": 3, "amplitude": 0.05, "phase": 0.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4950.0, 870.0), "radius_m": 28.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.6},
			{"frequency": 3, "amplitude": 0.06, "phase": 2.8},
		]}, # tree row / shelterbelt
	],

	"road_width_m": 6.0,
	"road_waypoints_m": [
		Vector2(4900.0, 904.0),
		Vector2(2162.0, 204.0),
		Vector2(1456.0, 1085.0),
		Vector2(1564.0, 1362.0),
		Vector2(1275.0, 1722.0),
		Vector2(1031.0, 1775.0),
		Vector2(952.0, 1732.0),
	],

	"player": {
		"deployment_zone": Rect2(150.0 * PIXELS_PER_METER, 100.0 * PIXELS_PER_METER, 2200.0 * PIXELS_PER_METER, 3300.0 * PIXELS_PER_METER),
		"mortar_deployment_zone": Rect2(30.0 * PIXELS_PER_METER, 60.0 * PIXELS_PER_METER, 1950.0 * PIXELS_PER_METER, 3400.0 * PIXELS_PER_METER),
		"spotter_deployment_zone": Rect2(30.0 * PIXELS_PER_METER, 30.0 * PIXELS_PER_METER, 4940.0 * PIXELS_PER_METER, 3440.0 * PIXELS_PER_METER),
		# Chosen by scanning the deployment area with the game's own
		# has_direct_los/elevation model (siting.js): each squad the point
		# within ~350m of the village that sees the most of the real road,
		# clear of the road bed itself and of any building.
		"default_squad_positions": [
			Vector2(1589.0, 1655.0) * PIXELS_PER_METER,
			Vector2(1548.0, 1558.0) * PIXELS_PER_METER,
			Vector2(1689.0, 1672.0) * PIXELS_PER_METER,
		],
		# The least-exposed point found within reach of the village — real
		# flat-to-gently-rolling farmland has no spot hidden from a 5km
		# road end to end, so this is the best available cover, not a
		# guaranteed mask (same standard the mortar's own relocation logic
		# already uses live). Clear of every building block.
		"mortar_default_position": Vector2(992.0, 1885.0) * PIXELS_PER_METER,
		# Inside a real tree patch, picked for the clearest sightline to
		# the road among every patch within reach of the village.
		"spotter_default_position": Vector2(1209.0, 1329.0) * PIXELS_PER_METER,
	},

	"enemy": {
		"spawn_x": 4900.0 * PIXELS_PER_METER, # matches the road's own easternmost waypoint
		"squad_spread_min_offset_m": -260.0,
		"squad_spread_max_offset_m": 260.0,
		"mortar_rear_x_m": 4700.0, # 200m behind spawn_x, same offset as every other map
		# 1600m span (or as much of it as fits the map's own height) centered
		# on the road's own first waypoint — see the other maps' identical
		# comment for the real citation (FM 7-90 Ch.6, up to 300m between
		# separate firing positions) and why an exact 4-gaps-of-300m layout
		# left no margin at ENEMY_MORTAR_COUNT_MAX.
		"mortar_spread_min_y_m": 104.0,
		"mortar_spread_max_y_m": 1704.0,
		# Deep enough into the 1500m west flank to be a real flank, same
		# 2/3-in proportion as every other map.
		"flank_waypoint_x": -1000.0 * PIXELS_PER_METER,
		"flank_waypoint_arrival_radius": 350.0 * PIXELS_PER_METER, # must stay > ENEMY_SURROUND_STANDOFF_RADIUS (300m) — see that constant's own doc comment
	},
},

## This map depicts the plateau west of Svystunivka, a village in Svatove
## Raion, Luhansk Oblast — the DEFENDERS hold the high ground on the rim of
## a shallow north-south valley (roughly 170m ASL), looking east and down
## across it at the village (in the valley, about 95m ASL, some 2km east
## of the defended position) and beyond it at the T-13-07 road the attackers
## come along. Built from real data around 49.4839, 38.2927, the point on
## the plateau rim the defence is centered on (the village's own
## administrative boundary contains the point 2km east of it). The Svatove
## area was occupied by Russian and Luhansk People's Republic forces in
## early March 2022 (Svatove itself on 3 March, per its Wikipedia article)
## and stayed under Russian control until the September 2022 Ukrainian
## counteroffensive, which came from the west — later than this game's
## early-2022 setting. So, as with every other map, no specific documented
## engagement is claimed for this exact spot: the terrain is real, the
## fight over it is the same hypothetical Russian assault from the east
## (Russian- and LPR-held territory lies east, north-east and south-east
## of here), which also matches this game's standing east-attacker/west-
## defender convention, so no compass rotation is needed.
##
## History: an earlier version of this map put the defenders in the village
## itself, on the valley floor (see git history before the "plateau" commit).
## That was awkward — the attackers began on higher ground looking down at
## them — so it was re-centered 2km west onto the plateau the village sits
## below. Checked before doing so: the plateau is real, gentle farmland
## (about 165-190m, median slope about 2%) with no water and no buildings
## for kilometers, no village within 3km, and the best rim positions see
## 76-86% of the valley and village by line of sight against 53% from the
## old spot; the escarpment between them climbs 70-90m at 8-16% grades over
## roughly 1.5-2km. Nothing found that would not work.
##
## Sources, all real: ELEVATION from SRTM 30m (via OpenTopoData) sampled at
## 100m over the whole map footprint; the 24 hills below are a least-squares
## fit of this engine's Gaussian-bump elevation model to it (about 6.4m RMS
## overall, 4.3m within 1.2km of the defended position — inside SRTM's own
## roughly +/-6-10m vertical error, so small rises are at the edge of what
## that data can resolve; the escarpment itself is 70-90m and solid).
## BUILDINGS from OpenStreetMap (ODbL, (c) OpenStreetMap contributors): the
## real footprints inside the map (the village and the strip of houses up
## the valley to the north-east; none on the plateau), aggregated into the
## 29 block-sized BUILDING zones below (clustered, then split along each
## cluster's own street direction so the blocks follow the real layout).
## TREE COVER is NOT in OpenStreetMap for this area (no tree rows or
## hedges tagged at all), so it was traced from satellite imagery: an
## automatic colour-and-texture classification of the canopy, packed into
## 230 circular patches — 60 wooded blocks (the large forest right on the
## plateau rim that the defence sits beside, the wooded ravine to its
## south-west, the dense valley-floor scrub) and 170 tree rows/shelterbelts along
## field edges (the same technique Pishchane's shelterbelts use; the
## plateau is cut into a grid of parcels with a row along nearly every
## boundary, and those got their own budget). A deliberately capped subset of
## the mapped canopy, not all of it.
##
## Not modeled: the real stream, ponds and wetland belt in the valley
## floor. The river mechanic here is a hard, bounding-box barrier with a
## single crossing, and this stream is a minor, walkable obstacle, so — as
## with Pishchane's pond — CURRENT_MAP omits the "river" key rather than
## misrepresent it. It does mean the attackers' crossing of that wet belt
## costs them nothing here, which real ground would.
"svystunivka": {
	"name": "Svystunivka Heights",
	"location_subtitle": "Svatove Raion, Luhansk Oblast",
	# The real coordinates the defence is centered on (the plateau rim, about
	# 2km west of the village) — shown on the map's location readout.
	"coordinates": "49.4839, 38.2927",
	"compass_north_screen_direction": Vector2(0.0, -1.0),

	"width_m": 5000.0,
	"height_m": 3500.0,
	"west_flank_width_m": 1500.0,

	# The defended position — what the enemy advances toward when no mortar
	# is known — on the plateau rim, not the village down in the valley.
	"village_center": Vector2(1500.0, 1750.0) * PIXELS_PER_METER,

	# The fitted model's own constant term — roughly the valley floor (the
	# real ground runs 83-192m ASL across the footprint; the hills below add
	# the rest, including the whole plateau).
	"elevation_baseline_m": 96.3,

	## Least-squares fit to real SRTM data — see this dictionary's own doc
	## comment. Ordered nearest the defended position first.
	"hills": [
		{"center_m": Vector2(1600.0, 2050.0), "radius_m": 180.0, "height_m": 17.9, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.12, "phase": 5.5},
			{"frequency": 3, "amplitude": 0.07, "phase": 2.7},
		]},
		{"center_m": Vector2(1600.0, 1250.0), "radius_m": 260.0, "height_m": 43.2, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.10, "phase": 2.1},
			{"frequency": 3, "amplitude": 0.09, "phase": 6.1},
		]},
		{"center_m": Vector2(1000.0, 1950.0), "radius_m": 180.0, "height_m": 13.4, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.11, "phase": 2.5},
			{"frequency": 4, "amplitude": 0.08, "phase": 3.8},
		]},
		{"center_m": Vector2(1000.0, 1250.0), "radius_m": 260.0, "height_m": 16.9, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.13, "phase": 5.9},
			{"frequency": 2, "amplitude": 0.08, "phase": 5.4},
		]},
		{"center_m": Vector2(2100.0, 1250.0), "radius_m": 130.0, "height_m": 29.6, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.11, "phase": 4.0},
			{"frequency": 3, "amplitude": 0.08, "phase": 0.1},
		]},
		{"center_m": Vector2(2300.0, 1950.0), "radius_m": 130.0, "height_m": 15.5, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.12, "phase": 3.6},
			{"frequency": 4, "amplitude": 0.09, "phase": 2.1},
		]},
		{"center_m": Vector2(2100.0, 2350.0), "radius_m": 260.0, "height_m": 43.2, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.13, "phase": 6.1},
			{"frequency": 2, "amplitude": 0.10, "phase": 6.1},
		]},
		{"center_m": Vector2(1300.0, 2650.0), "radius_m": 380.0, "height_m": 59.3, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.10, "phase": 2.7},
			{"frequency": 2, "amplitude": 0.07, "phase": 0.3},
		]},
		{"center_m": Vector2(600.0, 2350.0), "radius_m": 260.0, "height_m": 23.6, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.12, "phase": 5.4},
			{"frequency": 3, "amplitude": 0.08, "phase": 3.7},
		]},
		{"center_m": Vector2(1900.0, 2950.0), "radius_m": 180.0, "height_m": 32.3, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.11, "phase": 2.7},
			{"frequency": 3, "amplitude": 0.09, "phase": 1.9},
		]},
		{"center_m": Vector2(2600.0, 2650.0), "radius_m": 180.0, "height_m": 28.6, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.13, "phase": 2.2},
			{"frequency": 4, "amplitude": 0.07, "phase": 2.0},
		]},
		{"center_m": Vector2(1000.0, 250.0), "radius_m": 550.0, "height_m": 81.6, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.13, "phase": 5.1},
			{"frequency": 3, "amplitude": 0.08, "phase": 2.7},
		]},
		{"center_m": Vector2(1000.0, 3350.0), "radius_m": 260.0, "height_m": 21.8, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.11, "phase": 4.2},
			{"frequency": 4, "amplitude": 0.09, "phase": 2.3},
		]},
		{"center_m": Vector2(3200.0, 1150.0), "radius_m": 260.0, "height_m": 39.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.12, "phase": 4.7},
			{"frequency": 3, "amplitude": 0.07, "phase": 5.7},
		]},
		{"center_m": Vector2(-400.0, 1750.0), "radius_m": 1200.0, "height_m": 96.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.13, "phase": 5.8},
			{"frequency": 4, "amplitude": 0.09, "phase": 6.0},
		]},
		{"center_m": Vector2(2800.0, 150.0), "radius_m": 260.0, "height_m": 35.6, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.11, "phase": 5.0},
			{"frequency": 4, "amplitude": 0.07, "phase": 4.3},
		]},
		{"center_m": Vector2(3800.0, 1350.0), "radius_m": 260.0, "height_m": 20.7, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.11, "phase": 1.7},
			{"frequency": 3, "amplitude": 0.08, "phase": 6.2},
		]},
		{"center_m": Vector2(-100.0, 3650.0), "radius_m": 800.0, "height_m": 29.3, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.10, "phase": 5.8},
			{"frequency": 3, "amplitude": 0.08, "phase": 6.1},
		]},
		{"center_m": Vector2(-400.0, -150.0), "radius_m": 380.0, "height_m": 55.3, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.11, "phase": 3.7},
			{"frequency": 3, "amplitude": 0.09, "phase": 3.2},
		]},
		{"center_m": Vector2(3800.0, 250.0), "radius_m": 550.0, "height_m": 86.7, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.12, "phase": 1.9},
			{"frequency": 4, "amplitude": 0.07, "phase": 5.5},
		]},
		{"center_m": Vector2(-1700.0, 650.0), "radius_m": 380.0, "height_m": 38.4, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.12, "phase": 0.3},
			{"frequency": 4, "amplitude": 0.07, "phase": 4.9},
		]},
		{"center_m": Vector2(4800.0, 2850.0), "radius_m": 260.0, "height_m": 52.7, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.11, "phase": 5.3},
			{"frequency": 3, "amplitude": 0.09, "phase": 4.2},
		]},
		{"center_m": Vector2(-1700.0, 3650.0), "radius_m": 550.0, "height_m": 49.5, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.12, "phase": 5.7},
			{"frequency": 2, "amplitude": 0.09, "phase": 3.9},
		]},
		{"center_m": Vector2(4900.0, -150.0), "radius_m": 380.0, "height_m": 66.4, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.11, "phase": 2.8},
			{"frequency": 4, "amplitude": 0.09, "phase": 5.1},
		]},
	],

	## 29 blocks aggregated from real OpenStreetMap footprints — see the
	## doc comment. All in the valley (the village), east of the defence.
	"terrain_zones": [
		{"rect": Rect2(3070.0 * PIXELS_PER_METER, 1605.0 * PIXELS_PER_METER, 130.0 * PIXELS_PER_METER, 130.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(4625.0 * PIXELS_PER_METER, 2050.0 * PIXELS_PER_METER, 120.0 * PIXELS_PER_METER, 135.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(4670.0 * PIXELS_PER_METER, 1880.0 * PIXELS_PER_METER, 170.0 * PIXELS_PER_METER, 185.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(3810.0 * PIXELS_PER_METER, 1960.0 * PIXELS_PER_METER, 100.0 * PIXELS_PER_METER, 90.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(3895.0 * PIXELS_PER_METER, 1895.0 * PIXELS_PER_METER, 85.0 * PIXELS_PER_METER, 85.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(3975.0 * PIXELS_PER_METER, 1800.0 * PIXELS_PER_METER, 105.0 * PIXELS_PER_METER, 100.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(2880.0 * PIXELS_PER_METER, 1595.0 * PIXELS_PER_METER, 95.0 * PIXELS_PER_METER, 115.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(2985.0 * PIXELS_PER_METER, 1720.0 * PIXELS_PER_METER, 85.0 * PIXELS_PER_METER, 85.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(3060.0 * PIXELS_PER_METER, 1800.0 * PIXELS_PER_METER, 80.0 * PIXELS_PER_METER, 80.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(3130.0 * PIXELS_PER_METER, 1880.0 * PIXELS_PER_METER, 100.0 * PIXELS_PER_METER, 115.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(2570.0 * PIXELS_PER_METER, 1175.0 * PIXELS_PER_METER, 40.0 * PIXELS_PER_METER, 75.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(2605.0 * PIXELS_PER_METER, 1250.0 * PIXELS_PER_METER, 70.0 * PIXELS_PER_METER, 95.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(2825.0 * PIXELS_PER_METER, 2220.0 * PIXELS_PER_METER, 130.0 * PIXELS_PER_METER, 115.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(2950.0 * PIXELS_PER_METER, 2330.0 * PIXELS_PER_METER, 135.0 * PIXELS_PER_METER, 70.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(2995.0 * PIXELS_PER_METER, 2445.0 * PIXELS_PER_METER, 85.0 * PIXELS_PER_METER, 160.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(3085.0 * PIXELS_PER_METER, 2425.0 * PIXELS_PER_METER, 155.0 * PIXELS_PER_METER, 80.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(2650.0 * PIXELS_PER_METER, 3065.0 * PIXELS_PER_METER, 70.0 * PIXELS_PER_METER, 100.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(2725.0 * PIXELS_PER_METER, 2945.0 * PIXELS_PER_METER, 80.0 * PIXELS_PER_METER, 100.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(2785.0 * PIXELS_PER_METER, 2840.0 * PIXELS_PER_METER, 75.0 * PIXELS_PER_METER, 110.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(3720.0 * PIXELS_PER_METER, 3090.0 * PIXELS_PER_METER, 95.0 * PIXELS_PER_METER, 85.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(3810.0 * PIXELS_PER_METER, 3010.0 * PIXELS_PER_METER, 60.0 * PIXELS_PER_METER, 75.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(3515.0 * PIXELS_PER_METER, 3205.0 * PIXELS_PER_METER, 80.0 * PIXELS_PER_METER, 120.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(3595.0 * PIXELS_PER_METER, 3125.0 * PIXELS_PER_METER, 75.0 * PIXELS_PER_METER, 85.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(4745.0 * PIXELS_PER_METER, 1640.0 * PIXELS_PER_METER, 160.0 * PIXELS_PER_METER, 85.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(4910.0 * PIXELS_PER_METER, 1575.0 * PIXELS_PER_METER, 95.0 * PIXELS_PER_METER, 135.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(3425.0 * PIXELS_PER_METER, 2025.0 * PIXELS_PER_METER, 195.0 * PIXELS_PER_METER, 140.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(3545.0 * PIXELS_PER_METER, 1890.0 * PIXELS_PER_METER, 180.0 * PIXELS_PER_METER, 155.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(3420.0 * PIXELS_PER_METER, 1735.0 * PIXELS_PER_METER, 335.0 * PIXELS_PER_METER, 180.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
		{"rect": Rect2(3260.0 * PIXELS_PER_METER, 2015.0 * PIXELS_PER_METER, 105.0 * PIXELS_PER_METER, 125.0 * PIXELS_PER_METER), "type": TerrainType.BUILDING},
	],

	## 230 patches traced from satellite imagery — see the doc comment: the
	## first 60 are wooded blocks/thickets (nearest the defence first), the
	## remaining 170 are tree rows/shelterbelts along field edges.
	"forest_patches": [
		{"center_m": Vector2(1510.0, 1710.0), "radius_m": 228.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.15, "phase": 1.7},
			{"frequency": 3, "amplitude": 0.08, "phase": 2.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(1250.0, 1810.0), "radius_m": 114.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.13, "phase": 5.4},
			{"frequency": 2, "amplitude": 0.10, "phase": 0.9},
		]}, # wooded block / thicket
		{"center_m": Vector2(1770.0, 1790.0), "radius_m": 100.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.12, "phase": 3.6},
			{"frequency": 2, "amplitude": 0.08, "phase": 5.3},
		]}, # wooded block / thicket
		{"center_m": Vector2(1310.0, 1530.0), "radius_m": 111.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.14, "phase": 1.7},
			{"frequency": 2, "amplitude": 0.11, "phase": 5.3},
		]}, # wooded block / thicket
		{"center_m": Vector2(1710.0, 1530.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.12, "phase": 0.1},
			{"frequency": 4, "amplitude": 0.11, "phase": 3.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(1130.0, 1870.0), "radius_m": 57.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.15, "phase": 6.2},
			{"frequency": 4, "amplitude": 0.11, "phase": 0.3},
		]}, # wooded block / thicket
		{"center_m": Vector2(1890.0, 1810.0), "radius_m": 73.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.16, "phase": 0.6},
			{"frequency": 4, "amplitude": 0.11, "phase": 5.1},
		]}, # wooded block / thicket
		{"center_m": Vector2(1050.0, 1870.0), "radius_m": 57.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 4.0},
			{"frequency": 2, "amplitude": 0.11, "phase": 0.6},
		]}, # wooded block / thicket
		{"center_m": Vector2(1990.0, 1790.0), "radius_m": 57.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.15, "phase": 5.6},
			{"frequency": 4, "amplitude": 0.09, "phase": 1.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(1030.0, 1590.0), "radius_m": 260.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.12, "phase": 5.4},
			{"frequency": 3, "amplitude": 0.11, "phase": 5.1},
		]}, # wooded block / thicket
		{"center_m": Vector2(2070.0, 1790.0), "radius_m": 54.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.14, "phase": 4.9},
			{"frequency": 2, "amplitude": 0.10, "phase": 2.7},
		]}, # wooded block / thicket
		{"center_m": Vector2(1030.0, 1310.0), "radius_m": 54.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.15, "phase": 3.2},
			{"frequency": 3, "amplitude": 0.11, "phase": 4.6},
		]}, # wooded block / thicket
		{"center_m": Vector2(2170.0, 1770.0), "radius_m": 46.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 2.5},
			{"frequency": 4, "amplitude": 0.09, "phase": 3.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(950.0, 1310.0), "radius_m": 65.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.13, "phase": 1.7},
			{"frequency": 2, "amplitude": 0.10, "phase": 5.0},
		]}, # wooded block / thicket
		{"center_m": Vector2(750.0, 1470.0), "radius_m": 215.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.14, "phase": 0.2},
			{"frequency": 3, "amplitude": 0.09, "phase": 0.9},
		]}, # wooded block / thicket
		{"center_m": Vector2(2110.0, 2430.0), "radius_m": 57.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.15, "phase": 6.0},
			{"frequency": 2, "amplitude": 0.11, "phase": 1.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(1630.0, 830.0), "radius_m": 92.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.12, "phase": 0.3},
			{"frequency": 4, "amplitude": 0.11, "phase": 3.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(2190.0, 2430.0), "radius_m": 57.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.13, "phase": 3.7},
			{"frequency": 4, "amplitude": 0.09, "phase": 4.7},
		]}, # wooded block / thicket
		{"center_m": Vector2(2470.0, 1650.0), "radius_m": 65.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.12, "phase": 5.5},
			{"frequency": 4, "amplitude": 0.09, "phase": 4.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(790.0, 1050.0), "radius_m": 73.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.13, "phase": 4.0},
			{"frequency": 4, "amplitude": 0.10, "phase": 5.6},
		]}, # wooded block / thicket
		{"center_m": Vector2(510.0, 1490.0), "radius_m": 84.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 0.4},
			{"frequency": 4, "amplitude": 0.11, "phase": 4.5},
		]}, # wooded block / thicket
		{"center_m": Vector2(2270.0, 2430.0), "radius_m": 57.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.15, "phase": 5.8},
			{"frequency": 2, "amplitude": 0.11, "phase": 4.5},
		]}, # wooded block / thicket
		{"center_m": Vector2(2550.0, 1810.0), "radius_m": 65.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 0.8},
			{"frequency": 4, "amplitude": 0.10, "phase": 3.7},
		]}, # wooded block / thicket
		{"center_m": Vector2(2430.0, 2410.0), "radius_m": 73.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.12, "phase": 0.1},
			{"frequency": 3, "amplitude": 0.09, "phase": 0.9},
		]}, # wooded block / thicket
		{"center_m": Vector2(1650.0, 610.0), "radius_m": 65.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.14, "phase": 0.1},
			{"frequency": 4, "amplitude": 0.10, "phase": 4.4},
		]}, # wooded block / thicket
		{"center_m": Vector2(2510.0, 1110.0), "radius_m": 65.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.14, "phase": 2.5},
			{"frequency": 3, "amplitude": 0.11, "phase": 4.6},
		]}, # wooded block / thicket
		{"center_m": Vector2(1730.0, 570.0), "radius_m": 65.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.13, "phase": 4.7},
			{"frequency": 4, "amplitude": 0.10, "phase": 4.3},
		]}, # wooded block / thicket
		{"center_m": Vector2(1890.0, 2950.0), "radius_m": 76.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 5.6},
			{"frequency": 4, "amplitude": 0.12, "phase": 4.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(1710.0, 3030.0), "radius_m": 103.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.15, "phase": 3.0},
			{"frequency": 3, "amplitude": 0.09, "phase": 4.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(2630.0, 2390.0), "radius_m": 57.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.15, "phase": 3.4},
			{"frequency": 4, "amplitude": 0.09, "phase": 1.1},
		]}, # wooded block / thicket
		{"center_m": Vector2(1530.0, 3050.0), "radius_m": 95.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 4.0},
			{"frequency": 2, "amplitude": 0.08, "phase": 1.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(1970.0, 510.0), "radius_m": 92.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.15, "phase": 4.7},
			{"frequency": 2, "amplitude": 0.09, "phase": 4.0},
		]}, # wooded block / thicket
		{"center_m": Vector2(1870.0, 450.0), "radius_m": 65.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.12, "phase": 6.0},
			{"frequency": 2, "amplitude": 0.08, "phase": 4.0},
		]}, # wooded block / thicket
		{"center_m": Vector2(2730.0, 2390.0), "radius_m": 65.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.14, "phase": 0.5},
			{"frequency": 4, "amplitude": 0.11, "phase": 2.1},
		]}, # wooded block / thicket
		{"center_m": Vector2(1370.0, 3150.0), "radius_m": 157.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 3.6},
			{"frequency": 4, "amplitude": 0.11, "phase": 0.1},
		]}, # wooded block / thicket
		{"center_m": Vector2(1670.0, 3170.0), "radius_m": 73.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.15, "phase": 4.2},
			{"frequency": 4, "amplitude": 0.09, "phase": 3.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(1170.0, 3170.0), "radius_m": 172.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.14, "phase": 0.8},
			{"frequency": 4, "amplitude": 0.09, "phase": 0.7},
		]}, # wooded block / thicket
		{"center_m": Vector2(1550.0, 3210.0), "radius_m": 84.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.15, "phase": 4.4},
			{"frequency": 2, "amplitude": 0.09, "phase": 1.0},
		]}, # wooded block / thicket
		{"center_m": Vector2(3050.0, 2070.0), "radius_m": 65.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.14, "phase": 2.8},
			{"frequency": 3, "amplitude": 0.08, "phase": 3.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(950.0, 3250.0), "radius_m": 152.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.15, "phase": 0.8},
			{"frequency": 2, "amplitude": 0.11, "phase": 4.6},
		]}, # wooded block / thicket
		{"center_m": Vector2(450.0, 2970.0), "radius_m": 84.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.12, "phase": 6.1},
			{"frequency": 2, "amplitude": 0.11, "phase": 5.3},
		]}, # wooded block / thicket
		{"center_m": Vector2(630.0, 3170.0), "radius_m": 84.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.15, "phase": 1.6},
			{"frequency": 2, "amplitude": 0.09, "phase": 4.9},
		]}, # wooded block / thicket
		{"center_m": Vector2(530.0, 3150.0), "radius_m": 76.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.12, "phase": 4.2},
			{"frequency": 2, "amplitude": 0.09, "phase": 4.9},
		]}, # wooded block / thicket
		{"center_m": Vector2(2810.0, 610.0), "radius_m": 95.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.15, "phase": 3.9},
			{"frequency": 2, "amplitude": 0.12, "phase": 6.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(2510.0, 310.0), "radius_m": 84.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.13, "phase": 2.8},
			{"frequency": 2, "amplitude": 0.10, "phase": 2.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(3230.0, 1370.0), "radius_m": 73.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.14, "phase": 4.9},
			{"frequency": 2, "amplitude": 0.10, "phase": 3.5},
		]}, # wooded block / thicket
		{"center_m": Vector2(2590.0, 3210.0), "radius_m": 84.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.13, "phase": 3.2},
			{"frequency": 4, "amplitude": 0.08, "phase": 5.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(3270.0, 2230.0), "radius_m": 81.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.14, "phase": 2.1},
			{"frequency": 3, "amplitude": 0.08, "phase": 1.3},
		]}, # wooded block / thicket
		{"center_m": Vector2(2890.0, 530.0), "radius_m": 92.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.15, "phase": 5.3},
			{"frequency": 2, "amplitude": 0.09, "phase": 3.6},
		]}, # wooded block / thicket
		{"center_m": Vector2(530.0, 3330.0), "radius_m": 157.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.15, "phase": 4.9},
			{"frequency": 4, "amplitude": 0.10, "phase": 1.7},
		]}, # wooded block / thicket
		{"center_m": Vector2(3350.0, 1470.0), "radius_m": 73.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.13, "phase": 3.5},
			{"frequency": 3, "amplitude": 0.08, "phase": 0.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(3030.0, 610.0), "radius_m": 95.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.12, "phase": 5.6},
			{"frequency": 2, "amplitude": 0.09, "phase": 1.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(3330.0, 2370.0), "radius_m": 84.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.13, "phase": 4.4},
			{"frequency": 2, "amplitude": 0.10, "phase": 4.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(250.0, 3230.0), "radius_m": 260.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.13, "phase": 5.6},
			{"frequency": 3, "amplitude": 0.10, "phase": 1.8},
		]}, # wooded block / thicket
		{"center_m": Vector2(3130.0, 670.0), "radius_m": 73.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.12, "phase": 3.7},
			{"frequency": 3, "amplitude": 0.11, "phase": 6.1},
		]}, # wooded block / thicket
		{"center_m": Vector2(3510.0, 1670.0), "radius_m": 84.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.13, "phase": 2.3},
			{"frequency": 2, "amplitude": 0.10, "phase": 3.5},
		]}, # wooded block / thicket
		{"center_m": Vector2(3450.0, 2470.0), "radius_m": 133.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.14, "phase": 3.5},
			{"frequency": 3, "amplitude": 0.10, "phase": 2.4},
		]}, # wooded block / thicket
		{"center_m": Vector2(3390.0, 2630.0), "radius_m": 73.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.15, "phase": 5.5},
			{"frequency": 3, "amplitude": 0.08, "phase": 1.7},
		]}, # wooded block / thicket
		{"center_m": Vector2(-30.0, 3210.0), "radius_m": 234.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.13, "phase": 4.4},
			{"frequency": 2, "amplitude": 0.10, "phase": 5.2},
		]}, # wooded block / thicket
		{"center_m": Vector2(-290.0, 3250.0), "radius_m": 92.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.14, "phase": 2.7},
			{"frequency": 4, "amplitude": 0.08, "phase": 0.4},
		]}, # wooded block / thicket
		{"center_m": Vector2(1530.0, 2010.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.2},
			{"frequency": 4, "amplitude": 0.05, "phase": 2.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1530.0, 2050.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 4.0},
			{"frequency": 2, "amplitude": 0.05, "phase": 4.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1550.0, 1430.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 3.2},
			{"frequency": 4, "amplitude": 0.06, "phase": 2.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1530.0, 2090.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 0.6},
			{"frequency": 2, "amplitude": 0.04, "phase": 5.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1570.0, 1410.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 1.1},
			{"frequency": 4, "amplitude": 0.04, "phase": 4.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1550.0, 1390.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.1},
			{"frequency": 3, "amplitude": 0.05, "phase": 5.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1550.0, 2110.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 5.2},
			{"frequency": 3, "amplitude": 0.04, "phase": 2.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1530.0, 2130.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 1.4},
			{"frequency": 3, "amplitude": 0.06, "phase": 6.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1570.0, 1370.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 5.1},
			{"frequency": 4, "amplitude": 0.05, "phase": 1.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1550.0, 1350.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 4.3},
			{"frequency": 2, "amplitude": 0.05, "phase": 2.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1550.0, 2150.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 5.0},
			{"frequency": 4, "amplitude": 0.06, "phase": 3.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1530.0, 2170.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.6},
			{"frequency": 3, "amplitude": 0.05, "phase": 1.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1570.0, 1330.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.7},
			{"frequency": 3, "amplitude": 0.06, "phase": 0.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1890.0, 1570.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 1.9},
			{"frequency": 2, "amplitude": 0.05, "phase": 4.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1810.0, 1450.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.06, "phase": 1.3},
			{"frequency": 2, "amplitude": 0.06, "phase": 1.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1550.0, 1310.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.9},
			{"frequency": 3, "amplitude": 0.05, "phase": 2.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1550.0, 2190.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 5.5},
			{"frequency": 2, "amplitude": 0.04, "phase": 1.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1890.0, 1530.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 0.9},
			{"frequency": 4, "amplitude": 0.05, "phase": 5.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1930.0, 1590.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 0.5},
			{"frequency": 4, "amplitude": 0.05, "phase": 1.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1950.0, 1650.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.1},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1530.0, 2210.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 4.3},
			{"frequency": 4, "amplitude": 0.06, "phase": 5.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1570.0, 1290.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 1.3},
			{"frequency": 4, "amplitude": 0.05, "phase": 2.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1890.0, 1490.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 0.8},
			{"frequency": 2, "amplitude": 0.06, "phase": 3.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1930.0, 1550.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.6},
			{"frequency": 3, "amplitude": 0.06, "phase": 1.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1910.0, 1510.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.5},
			{"frequency": 3, "amplitude": 0.05, "phase": 4.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1510.0, 2230.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 1.6},
			{"frequency": 2, "amplitude": 0.04, "phase": 0.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1950.0, 1570.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 6.0},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1970.0, 1630.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 2.6},
			{"frequency": 3, "amplitude": 0.06, "phase": 0.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1870.0, 1430.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 3.0},
			{"frequency": 3, "amplitude": 0.04, "phase": 2.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1950.0, 1530.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 2.0},
			{"frequency": 4, "amplitude": 0.06, "phase": 1.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1530.0, 2250.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 5.0},
			{"frequency": 2, "amplitude": 0.05, "phase": 2.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1930.0, 1490.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 1.1},
			{"frequency": 2, "amplitude": 0.05, "phase": 3.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1990.0, 1610.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.06, "phase": 5.9},
			{"frequency": 4, "amplitude": 0.05, "phase": 5.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1510.0, 2270.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 0.6},
			{"frequency": 2, "amplitude": 0.06, "phase": 5.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1550.0, 1230.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 1.4},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2010.0, 1630.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 2.9},
			{"frequency": 2, "amplitude": 0.05, "phase": 6.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1530.0, 2290.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 2.0},
			{"frequency": 3, "amplitude": 0.05, "phase": 1.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1950.0, 1450.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 0.4},
			{"frequency": 2, "amplitude": 0.06, "phase": 5.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1930.0, 1410.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 6.2},
			{"frequency": 4, "amplitude": 0.04, "phase": 1.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2030.0, 1610.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 4.7},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1510.0, 2310.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 3.8},
			{"frequency": 4, "amplitude": 0.04, "phase": 1.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2050.0, 1630.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 4.4},
			{"frequency": 4, "amplitude": 0.06, "phase": 5.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1970.0, 1430.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 2.2},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1530.0, 2330.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 1.9},
			{"frequency": 4, "amplitude": 0.05, "phase": 0.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1550.0, 1170.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 2.3},
			{"frequency": 3, "amplitude": 0.05, "phase": 0.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2090.0, 1650.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 0.2},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1510.0, 2350.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 1.2},
			{"frequency": 2, "amplitude": 0.05, "phase": 3.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1570.0, 1150.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.1},
			{"frequency": 3, "amplitude": 0.06, "phase": 2.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1530.0, 2370.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.06, "phase": 2.4},
			{"frequency": 3, "amplitude": 0.05, "phase": 3.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2110.0, 1630.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 0.1},
			{"frequency": 2, "amplitude": 0.05, "phase": 5.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1550.0, 1130.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 4.7},
			{"frequency": 3, "amplitude": 0.06, "phase": 1.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2130.0, 1650.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 5.4},
			{"frequency": 4, "amplitude": 0.06, "phase": 3.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1510.0, 2390.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 6.2},
			{"frequency": 3, "amplitude": 0.05, "phase": 0.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1510.0, 1090.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.06, "phase": 3.3},
			{"frequency": 4, "amplitude": 0.05, "phase": 3.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1530.0, 2410.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 2.3},
			{"frequency": 4, "amplitude": 0.04, "phase": 4.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2150.0, 1630.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 2.4},
			{"frequency": 4, "amplitude": 0.05, "phase": 6.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1550.0, 1090.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 0.0},
			{"frequency": 2, "amplitude": 0.05, "phase": 5.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1490.0, 1070.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 0.6},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1510.0, 2430.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.8},
			{"frequency": 2, "amplitude": 0.05, "phase": 3.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1510.0, 2510.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 3.3},
			{"frequency": 4, "amplitude": 0.06, "phase": 2.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2310.0, 1630.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 4.6},
			{"frequency": 2, "amplitude": 0.04, "phase": 0.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2330.0, 1610.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.8},
			{"frequency": 3, "amplitude": 0.06, "phase": 5.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(990.0, 1010.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 1.3},
			{"frequency": 4, "amplitude": 0.04, "phase": 6.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2390.0, 1450.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.8},
			{"frequency": 3, "amplitude": 0.06, "phase": 0.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1830.0, 850.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.0},
			{"frequency": 2, "amplitude": 0.06, "phase": 3.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2450.0, 1450.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 4.0},
			{"frequency": 2, "amplitude": 0.05, "phase": 2.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2250.0, 1030.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 3.9},
			{"frequency": 4, "amplitude": 0.05, "phase": 3.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(470.0, 1290.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 4.3},
			{"frequency": 4, "amplitude": 0.06, "phase": 4.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2150.0, 790.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 6.0},
			{"frequency": 3, "amplitude": 0.04, "phase": 0.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2110.0, 750.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 4.2},
			{"frequency": 3, "amplitude": 0.06, "phase": 3.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(410.0, 1290.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 1.9},
			{"frequency": 3, "amplitude": 0.06, "phase": 0.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2270.0, 850.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 1.7},
			{"frequency": 2, "amplitude": 0.06, "phase": 0.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2690.0, 1610.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.5},
			{"frequency": 4, "amplitude": 0.05, "phase": 0.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2690.0, 1550.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 1.3},
			{"frequency": 2, "amplitude": 0.06, "phase": 0.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2710.0, 1730.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 1.9},
			{"frequency": 3, "amplitude": 0.06, "phase": 0.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2710.0, 1670.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 0.5},
			{"frequency": 4, "amplitude": 0.04, "phase": 3.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2250.0, 790.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 0.7},
			{"frequency": 4, "amplitude": 0.06, "phase": 2.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(370.0, 1290.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 4.8},
			{"frequency": 2, "amplitude": 0.05, "phase": 5.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2210.0, 750.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 2.8},
			{"frequency": 2, "amplitude": 0.06, "phase": 4.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2730.0, 1650.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 5.7},
			{"frequency": 2, "amplitude": 0.06, "phase": 1.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2750.0, 1790.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.9},
			{"frequency": 3, "amplitude": 0.05, "phase": 3.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2770.0, 1750.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 3.7},
			{"frequency": 4, "amplitude": 0.05, "phase": 2.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2230.0, 2790.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 2.9},
			{"frequency": 3, "amplitude": 0.06, "phase": 5.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1130.0, 530.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 5.6},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2270.0, 730.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 1.2},
			{"frequency": 4, "amplitude": 0.06, "phase": 3.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2110.0, 2910.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 1.4},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2150.0, 610.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 3.0},
			{"frequency": 4, "amplitude": 0.06, "phase": 1.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2270.0, 2830.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 2.4},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2230.0, 2870.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 0.5},
			{"frequency": 3, "amplitude": 0.04, "phase": 4.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(230.0, 1290.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 1.5},
			{"frequency": 2, "amplitude": 0.05, "phase": 1.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2510.0, 830.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 5.7},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2870.0, 1710.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.06, "phase": 6.1},
			{"frequency": 2, "amplitude": 0.06, "phase": 5.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2870.0, 1630.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 0.0},
			{"frequency": 4, "amplitude": 0.05, "phase": 3.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2870.0, 1590.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.3},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2570.0, 850.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.4},
			{"frequency": 3, "amplitude": 0.05, "phase": 1.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2050.0, 3050.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 0.4},
			{"frequency": 2, "amplitude": 0.06, "phase": 1.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2910.0, 1630.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 1.4},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2930.0, 1690.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 6.0},
			{"frequency": 3, "amplitude": 0.06, "phase": 5.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(250.0, 2450.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.4},
			{"frequency": 2, "amplitude": 0.05, "phase": 5.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2910.0, 1490.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 5.3},
			{"frequency": 2, "amplitude": 0.06, "phase": 0.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2910.0, 1450.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.7},
			{"frequency": 2, "amplitude": 0.05, "phase": 3.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2970.0, 1790.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 4.1},
			{"frequency": 2, "amplitude": 0.06, "phase": 4.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(110.0, 1270.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.4},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(190.0, 2450.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 0.9},
			{"frequency": 4, "amplitude": 0.06, "phase": 1.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2990.0, 1730.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 3.6},
			{"frequency": 2, "amplitude": 0.06, "phase": 0.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2990.0, 1670.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.2},
			{"frequency": 4, "amplitude": 0.05, "phase": 2.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2070.0, 3130.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 2.5},
			{"frequency": 2, "amplitude": 0.05, "phase": 2.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1910.0, 3190.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 3.5},
			{"frequency": 2, "amplitude": 0.06, "phase": 5.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3010.0, 1750.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 2.4},
			{"frequency": 2, "amplitude": 0.05, "phase": 5.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3010.0, 1650.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 0.9},
			{"frequency": 2, "amplitude": 0.06, "phase": 3.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3050.0, 1730.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 4.8},
			{"frequency": 3, "amplitude": 0.05, "phase": 5.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3050.0, 1790.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 3.7},
			{"frequency": 3, "amplitude": 0.05, "phase": 3.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3050.0, 1830.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 2.1},
			{"frequency": 2, "amplitude": 0.05, "phase": 1.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2950.0, 1170.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 3.4},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3070.0, 1750.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 0.1},
			{"frequency": 3, "amplitude": 0.05, "phase": 4.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3090.0, 1770.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 0.5},
			{"frequency": 4, "amplitude": 0.05, "phase": 2.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3090.0, 1670.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 4.3},
			{"frequency": 4, "amplitude": 0.06, "phase": 2.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1750.0, 3330.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.06, "phase": 3.7},
			{"frequency": 4, "amplitude": 0.05, "phase": 3.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2110.0, 3230.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 1.4},
			{"frequency": 2, "amplitude": 0.06, "phase": 6.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1870.0, 190.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.6},
			{"frequency": 4, "amplitude": 0.04, "phase": 5.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2250.0, 330.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 0.2},
			{"frequency": 4, "amplitude": 0.06, "phase": 5.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3110.0, 1790.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 1.1},
			{"frequency": 4, "amplitude": 0.06, "phase": 4.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3130.0, 1730.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 2.1},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3130.0, 1810.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 0.5},
			{"frequency": 4, "amplitude": 0.04, "phase": 2.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(10.0, 2430.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 0.7},
			{"frequency": 3, "amplitude": 0.06, "phase": 3.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(630.0, 350.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 2.4},
			{"frequency": 4, "amplitude": 0.05, "phase": 1.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1910.0, 150.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 5.0},
			{"frequency": 4, "amplitude": 0.06, "phase": 1.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3170.0, 1750.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 0.8},
			{"frequency": 3, "amplitude": 0.06, "phase": 4.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3170.0, 1710.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 5.5},
			{"frequency": 3, "amplitude": 0.05, "phase": 3.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2250.0, 250.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.6},
			{"frequency": 3, "amplitude": 0.05, "phase": 1.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1870.0, 110.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.8},
			{"frequency": 4, "amplitude": 0.05, "phase": 2.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(-50.0, 2430.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 1.1},
			{"frequency": 2, "amplitude": 0.05, "phase": 2.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3210.0, 1750.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 3.6},
			{"frequency": 3, "amplitude": 0.05, "phase": 1.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(2270.0, 190.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 5.9},
			{"frequency": 3, "amplitude": 0.06, "phase": 0.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(1870.0, 50.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 0.6},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3250.0, 1770.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 2.9},
			{"frequency": 3, "amplitude": 0.05, "phase": 3.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3310.0, 1770.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 3.3},
			{"frequency": 3, "amplitude": 0.06, "phase": 1.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3330.0, 1750.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 1.7},
			{"frequency": 3, "amplitude": 0.04, "phase": 6.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(-250.0, 2410.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 1.5},
			{"frequency": 3, "amplitude": 0.05, "phase": 1.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(-290.0, 1110.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 3.5},
			{"frequency": 2, "amplitude": 0.05, "phase": 5.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(-290.0, 1050.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 5.5},
			{"frequency": 3, "amplitude": 0.06, "phase": 0.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(-310.0, 2410.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 0.3},
			{"frequency": 2, "amplitude": 0.06, "phase": 4.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(-270.0, 930.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 1.1},
			{"frequency": 4, "amplitude": 0.05, "phase": 1.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(-270.0, 870.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 5.8},
			{"frequency": 3, "amplitude": 0.06, "phase": 3.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(-370.0, 2410.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 3.7},
			{"frequency": 3, "amplitude": 0.05, "phase": 5.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(-270.0, 810.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.08, "phase": 2.5},
			{"frequency": 4, "amplitude": 0.05, "phase": 2.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(-70.0, 490.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.06, "phase": 0.9},
			{"frequency": 4, "amplitude": 0.05, "phase": 0.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(-250.0, 690.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 2.0},
			{"frequency": 3, "amplitude": 0.05, "phase": 2.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(-250.0, 590.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 5.4},
			{"frequency": 2, "amplitude": 0.05, "phase": 4.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(-430.0, 2710.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.1},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(-230.0, 450.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 3.4},
			{"frequency": 4, "amplitude": 0.05, "phase": 4.6},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3670.0, 1490.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 0.0},
			{"frequency": 4, "amplitude": 0.05, "phase": 3.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3710.0, 1030.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 5.7},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.3},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3750.0, 2630.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 2.2},
			{"frequency": 3, "amplitude": 0.05, "phase": 5.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(3890.0, 2430.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 2.6},
			{"frequency": 4, "amplitude": 0.06, "phase": 0.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4050.0, 1410.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 4.9},
			{"frequency": 4, "amplitude": 0.05, "phase": 0.1},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4110.0, 1630.0), "radius_m": 24.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 5.0},
			{"frequency": 3, "amplitude": 0.05, "phase": 3.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4150.0, 1590.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 5.4},
			{"frequency": 2, "amplitude": 0.05, "phase": 1.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4130.0, 970.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 2.4},
			{"frequency": 3, "amplitude": 0.05, "phase": 5.0},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4390.0, 1550.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.06, "phase": 6.2},
			{"frequency": 2, "amplitude": 0.06, "phase": 6.2},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4410.0, 1330.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 1.7},
			{"frequency": 4, "amplitude": 0.04, "phase": 5.8},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4470.0, 1510.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.08, "phase": 2.4},
			{"frequency": 4, "amplitude": 0.06, "phase": 2.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4510.0, 1490.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 1.5},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4530.0, 1430.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 5.1},
			{"frequency": 4, "amplitude": 0.05, "phase": 1.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4550.0, 1370.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.08, "phase": 2.6},
			{"frequency": 3, "amplitude": 0.05, "phase": 1.7},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4450.0, 2670.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 2.1},
			{"frequency": 2, "amplitude": 0.04, "phase": 1.9},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4770.0, 2350.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 1.0},
			{"frequency": 2, "amplitude": 0.05, "phase": 2.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4910.0, 1270.0), "radius_m": 44.0, "warp_harmonics": [
			{"frequency": 4, "amplitude": 0.07, "phase": 5.9},
			{"frequency": 2, "amplitude": 0.04, "phase": 5.5},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4910.0, 2350.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 2, "amplitude": 0.07, "phase": 4.4},
			{"frequency": 4, "amplitude": 0.06, "phase": 4.4},
		]}, # tree row / shelterbelt
		{"center_m": Vector2(4950.0, 2370.0), "radius_m": 31.0, "warp_harmonics": [
			{"frequency": 3, "amplitude": 0.07, "phase": 4.6},
			{"frequency": 2, "amplitude": 0.05, "phase": 0.8},
		]}, # tree row / shelterbelt
	],

	"road_width_m": 6.0,
	# East edge along the T-13-07 road, then west along the causeway road
	# across the valley into the village, then up the real track climbing the
	# escarpment toward the plateau — approximate (the real roads bend more).
	"road_waypoints_m": [
		Vector2(4900.0, 1930.0),
		Vector2(4730.0, 1730.0),
		Vector2(4200.0, 1730.0),
		Vector2(3800.0, 1790.0),
		Vector2(3500.0, 1900.0),
		Vector2(2762.0, 1422.0),
		Vector2(2200.0, 1200.0),
		Vector2(1600.0, 1200.0),
	],

	"player": {
		"deployment_zone": Rect2(150.0 * PIXELS_PER_METER, 100.0 * PIXELS_PER_METER, 2200.0 * PIXELS_PER_METER, 3300.0 * PIXELS_PER_METER),
		"mortar_deployment_zone": Rect2(30.0 * PIXELS_PER_METER, 60.0 * PIXELS_PER_METER, 1950.0 * PIXELS_PER_METER, 3400.0 * PIXELS_PER_METER),
		"spotter_deployment_zone": Rect2(30.0 * PIXELS_PER_METER, 30.0 * PIXELS_PER_METER, 4940.0 * PIXELS_PER_METER, 3440.0 * PIXELS_PER_METER),
		# Three squads spaced along the plateau rim in tree cover, ~170m up and 1.5-2km west of the village, each seeing 7-14 of the 28 points along the attackers' route and up to a third of the village blocks (chosen by scanning the deployment area with the game's own line of sight).
		"default_squad_positions": [
			Vector2(1550.0, 1350.0) * PIXELS_PER_METER,
			Vector2(1550.0, 1500.0) * PIXELS_PER_METER,
			Vector2(1600.0, 1850.0) * PIXELS_PER_METER,
		],
		# In trees about 450m behind the rim, masked from every point along the attackers' route and from every village block (scanned the same way) — the mortar covers the valley from cover.
		"mortar_default_position": Vector2(1100.0, 1500.0) * PIXELS_PER_METER,
		# The best tree-covered vantage found on the rim (about 179m): it sees 15 of the 28 route points and 9 of the 29 village blocks.
		"spotter_default_position": Vector2(1550.0, 1300.0) * PIXELS_PER_METER,
	},

	"enemy": {
		"spawn_x": 4900.0 * PIXELS_PER_METER, # matches the road's own easternmost waypoint
		"squad_spread_min_offset_m": -260.0,
		"squad_spread_max_offset_m": 260.0,
		"mortar_rear_x_m": 4700.0, # 200m behind spawn_x, same offset as every other map
		# Same 1600m span as every other map (see their identical comment
		# for the FM 7-90 Ch.6 citation), centered on the road's start.
		"mortar_spread_min_y_m": 1130.0,
		"mortar_spread_max_y_m": 2730.0,
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
	_terrain_grid_built = false
	_hill_cache_built = false
	_canopy_built = false
	_tree_sight_cache.clear()


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
## The id (MAPS key) of the map loaded right now — the stable identity of a
## scenario (a map's display name can change; its id doesn't). CURRENT_MAP is
## always one of MAPS' own values, so this is a plain reverse lookup.
static func current_map_id() -> String:
	for map_id in MAPS:
		if MAPS[map_id] == CURRENT_MAP:
			return map_id
	return DEFAULT_MAP_ID


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
	if not _hill_cache_built:
		_build_hill_cache()
	var x: float = pos_px.x / PIXELS_PER_METER
	var y: float = pos_px.y / PIXELS_PER_METER
	var total: float = _hill_baseline
	for i in _hill_count:
		var dx: float = x - _hill_cx[i]
		var dy: float = y - _hill_cy[i]
		var d2: float = dx * dx + dy * dy
		# Skip a hill whose contribution is provably negligible here: warp
		# amplitudes total well under 0.5 (see _radius_warp — test_map_
		# integrity enforces it), so the effective radius never exceeds
		# 1.5x radius_m, and past d^2 = 90 x radius_m^2 the Gaussian is below
		# exp(-20) ~ 2e-9 of the hill's height — under a millimeter for any
		# real hill.
		if d2 > _hill_cutoff2[i]:
			continue
		var r: float = _hill_radius[i]
		if d2 > 0.0001:
			var theta: float = atan2(dy, dx)
			var w: float = 1.0
			for k in range(_hill_harm_start[i], _hill_harm_start[i + 1]):
				w += _hill_harm_amp[k] * cos(_hill_harm_freq[k] * theta + _hill_harm_phase[k])
			r *= w
		total += _hill_height[i] * exp(-d2 / (2.0 * r * r))
	return total


## elevation_m's own per-map lookup tables — CURRENT_MAP.hills flattened
## into plain numeric arrays once per loaded map (dropped by
## _recompute_map_derived_state), because the same math read straight from
## the hills' Dictionaries spent most of its time on string-keyed lookups: a
## map fitted to real elevation data carries dozens of hills, and every
## line-of-sight check samples elevation many times. Same formula, same
## result to within float rounding (verified against the Dictionary form
## over 60,000 random points per map: under 1e-5 m).
static var _hill_cache_built: bool = false
static var _hill_baseline: float = 0.0
static var _hill_count: int = 0
static var _hill_cx: PackedFloat64Array = PackedFloat64Array()
static var _hill_cy: PackedFloat64Array = PackedFloat64Array()
static var _hill_radius: PackedFloat64Array = PackedFloat64Array()
static var _hill_height: PackedFloat64Array = PackedFloat64Array()
static var _hill_cutoff2: PackedFloat64Array = PackedFloat64Array()
static var _hill_harm_start: PackedInt32Array = PackedInt32Array()
static var _hill_harm_freq: PackedFloat64Array = PackedFloat64Array()
static var _hill_harm_amp: PackedFloat64Array = PackedFloat64Array()
static var _hill_harm_phase: PackedFloat64Array = PackedFloat64Array()


static func _build_hill_cache() -> void:
	_hill_cache_built = true
	_hill_baseline = CURRENT_MAP.get("elevation_baseline_m", 0.0)
	var hills: Array = CURRENT_MAP.hills
	_hill_count = hills.size()
	_hill_cx = PackedFloat64Array()
	_hill_cy = PackedFloat64Array()
	_hill_radius = PackedFloat64Array()
	_hill_height = PackedFloat64Array()
	_hill_cutoff2 = PackedFloat64Array()
	_hill_harm_start = PackedInt32Array()
	_hill_harm_freq = PackedFloat64Array()
	_hill_harm_amp = PackedFloat64Array()
	_hill_harm_phase = PackedFloat64Array()
	for hill in hills:
		_hill_cx.append(hill.center_m.x)
		_hill_cy.append(hill.center_m.y)
		_hill_radius.append(hill.radius_m)
		_hill_height.append(hill.height_m)
		_hill_cutoff2.append(90.0 * hill.radius_m * hill.radius_m)
		_hill_harm_start.append(_hill_harm_freq.size())
		for h in hill.warp_harmonics:
			_hill_harm_freq.append(h.frequency)
			_hill_harm_amp.append(h.amplitude)
			_hill_harm_phase.append(h.phase)
	_hill_harm_start.append(_hill_harm_freq.size())


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
		out.append(_out_of_buildings_m(Vector2(enemy.mortar_rear_x_m, (enemy.mortar_spread_min_y_m + enemy.mortar_spread_max_y_m) / 2.0)))
		return out
	var span: float = enemy.mortar_spread_max_y_m - enemy.mortar_spread_min_y_m
	for i in n:
		out.append(_out_of_buildings_m(Vector2(enemy.mortar_rear_x_m, enemy.mortar_spread_min_y_m + i * span / float(n - 1))))
	return out


## `pos_m` itself if it is clear of every building block, else the nearest
## clear point straight north or south of it (20 m steps, out to 600 m). A
## mortar can't fire from inside a building (no overhead clearance — see
## BattleManager._tick_fire), and the evenly spaced rear positions above know
## nothing about a map's buildings: a live battle spawned its only enemy
## mortar in a building block on Svystunivka Heights, where it sat "holding"
## with a target available and never fired a round.
static func _out_of_buildings_m(pos_m: Vector2) -> Vector2:
	if not is_building_at(pos_m * PIXELS_PER_METER):
		return pos_m
	for step in range(1, 31):
		for dir in [1.0, -1.0]:
			var candidate := Vector2(pos_m.x, clampf(pos_m.y + dir * 20.0 * step, 0.0, MAP_HEIGHT_M))
			if not is_building_at(candidate * PIXELS_PER_METER):
				return candidate
	return pos_m

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

## How much farther than the nearest cover zone overall it's worth walking
## just to stay on retreat_dir's own "correct" side — a real, previously-
## reported failure mode: retreat_dir is a blanket per-team assumption
## ("home is generally this way"), fixed regardless of whether any actual
## threat has ever been seen in the excluded direction — unlike
## _exclude_dangerous, which is grounded in real known enemy positions.
## Enforcing it as a hard veto could force a multi-kilometer detour past
## perfectly good, non-dangerous cover sitting just on the "wrong" side,
## for no real safety benefit (the diagnosed case: a mortar's own
## deployment position had no cover at all on its retreat-ward side,
## sending an ordinary hit-triggered retreat over 2km out — the direct
## mechanism behind a previously-reported "mortar abandons the hilltop"
## complaint that persisted even after the mortar's own self-preservation
## relocation got a home-range leash, since this is a SEPARATE code path).
## A judgment call, not cited — enough to prefer a short, sensible detour
## toward the friendly side without paying for an unreasonable one.
const RETREAT_DIRECTION_MAX_EXTRA_M: float = 500.0

# Tactical seconds (see TIME_SCALE_NORMAL) — ends the battle if reached.
# Real infantry engagements can run for hours; the road march alone eats
# ~2500 tactical seconds (42 min) before contact is even possible, and a
# realistic-paced firefight — punctuated by units breaking for cover at a
# realistic pace too, not instantly re-engaging — needs real room after
# that to actually develop and resolve, not just time out early with both
# sides barely scratched. 12 tactical hours (0600 to 1800; raised from 4 by
# direct user request — a battle that reaches it with both sides still on the
# field is scored a stalemate, see BattleManager._check_battle_end), worst
# case, still caps actual watching time at BATTLE_TIME_LIMIT / TIME_SCALE_NORMAL
# (720 real seconds).
const BATTLE_TIME_LIMIT: float = 43200.0

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
# Re-checked directly rather than left as the original request's own
# uncited "hard to see and hard to hit" framing: the Australian Army's
# own professional-military-education site (The Cove), compiling
# real lessons from this war, reports small reconnaissance drones as
# hardest to detect during the day at 100-300m — 300m sits right at the
# top of that real, cited band, not an arbitrary round number. DJI's own
# factory-default altitude limit for this drone class is lower (400ft /
# ~122m), but field-modified drones exceeding that limit for exactly
# this tactical reason are also documented in this exact conflict.
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

# A homebound drone may fly FASTER than DRONE_CRUISE_SPEED — a real pilot
# fighting a headwind switches to Sport mode rather than crawling home at
# walking pace (a real, reported failure: drones "unable to reach the
# station" in a wind near their fixed cruise speed). DJI's own Mavic 3
# figures: 15 m/s in Normal mode, 21 m/s in Sport (19 m/s in the EU only,
# which this map isn't in) — spec sheet, still air.
const DRONE_MAX_AIRSPEED: float = 21.0 * PIXELS_PER_METER
# The speed DJI's own 46-minute figure was measured at (32.4 km/h, spec
# footnote) — one of the two real points the power model below is fitted to
# (the other is DRONE_CRUISE_SPEED's 30 km range figure).
const DRONE_ENDURANCE_TEST_SPEED_MPS: float = 9.0
const DRONE_RETURN_SPEED_STEP_MPS: float = 0.5
# JUDGMENT: a pilot doesn't change speed for a marginal gain — the homebound
# airspeed is the SLOWEST candidate within this fraction of the best
# battery-per-distance, which keeps a windless return at exactly cruise
# (the true still-air optimum is ~14.6 m/s, only ~0.15% better than 14; a
# 5% gain doesn't appear until roughly a 4 m/s headwind).
const DRONE_RETURN_ENERGY_TOLERANCE: float = 0.05

## Battery drain rate at `airspeed` (px/s), relative to the drain rate at
## DRONE_CRUISE_SPEED (1.0 there). Power = a + b*v^3 (a fixed hover/avionics
## term plus a drag term), fitted EXACTLY to DJI's two published forward-
## flight points: full battery lasts 46 min at 9 m/s and covers 30 km at
## 14 m/s (35.7 min). Everything at or below 14 m/s is interpolation;
## above it (up to DRONE_MAX_AIRSPEED, ~1.7x at 21 m/s) is an extrapolation
## of the cubic drag law — JUDGMENT, DJI publishes no power figure there.
static func drone_power_factor(airspeed: float) -> float:
	var v: float = airspeed / PIXELS_PER_METER
	var v_cruise: float = DRONE_CRUISE_SPEED / PIXELS_PER_METER
	var v_endurance: float = DRONE_ENDURANCE_TEST_SPEED_MPS
	var p_endurance: float = 1.0 / DRONE_MAX_FLIGHT_TIME
	var p_cruise: float = 1.0 / DRONE_FULL_CHARGE_FLIGHT_TIME
	var b: float = (p_cruise - p_endurance) / (pow(v_cruise, 3.0) - pow(v_endurance, 3.0))
	var a: float = p_endurance - b * pow(v_endurance, 3.0)
	return (a + b * pow(v, 3.0)) / p_cruise

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

## A contact the drone (or anything else) has kept in view continuously is
## no longer NEW information, so its pull on nearby search cells fades the
## longer it has been watched without a break: full strength on first sight,
## down to DRONE_CONTACT_WATCH_FLOOR of it after DRONE_CONTACT_WATCH_FADE_S
## tactical seconds, restarting the moment sight is lost. Without this a
## visible squad refreshed its own contact every tick, so the cells around it
## stayed at full bonus for as long as the drone kept looking and the drone
## hopped between them indefinitely (live report: "the previous drone hung
## over the bottom right way too long"). Judgment calls, not cited figures.
const DRONE_CONTACT_WATCH_FADE_S: float = 180.0
const DRONE_CONTACT_WATCH_FLOOR: float = 0.3

## A routine-recon destination the drone is still flying to is dropped
## mid-flight only once its score falls below this fraction of the best
## alternative's (see BattleManager._drone_commitment_has_collapsed).
const DRONE_COMMITMENT_ABANDON_FRACTION: float = 0.25

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
# Split by side rather than one shared figure — the two real 82mm systems
# behind this game's own citations are genuinely different weapons, not
# the same tube with a rounding difference. Previously a single uncited
# 3500m (closer to the older Soviet-era 82-BM-37's own 3040m than either
# side's real current figure), then a single shared 5000m picked as a
# conservative compromise between two different-sided citations. Now each
# side uses its own real, recent (2023-2024) figure from this exact war
# directly, since there's no reason a Ukrainian-fielded tube's real range
# should be constrained to match a Russian one's, or vice versa:
# - PLAYER (Ukraine): reporting on Ukrainian-produced 82mm mortar shells,
#   fired from the Soviet-legacy tubes (2B14 Podnos and older 82-BM-37/41)
#   Ukraine's own military inherited and has kept in service, cites a max
#   range of 4500m.
# - ENEMY (Russia): Russia's currently-issued 2B24 82mm light mortar (a
#   more modern tube than either side's older Soviet-era stock) is rated
#   to 6000m.
# Found to matter concretely, not just cosmetically, when this was still
# a single 3500m figure: a direct empirical check found the median real
# distance between the two sides' own mortar positions on this game's
# current (larger, right-tailed-assault) maps already exceeded it —
# cross-mortar counter-battery duels were geometrically impossible more
# often than any hold/scoot chance tuning could ever compensate for.
const MORTAR_MAX_RANGE_PLAYER: float = 4500.0 * PIXELS_PER_METER
const MORTAR_MAX_RANGE_ENEMY: float = 6000.0 * PIXELS_PER_METER

## The correct MORTAR_MAX_RANGE_* for `team` — every call site that used
## to read a single shared MORTAR_MAX_RANGE now goes through this instead,
## keyed by whichever side's mortar/engagement the check is actually about.
static func mortar_max_range(team: Unit.Team) -> float:
	return MORTAR_MAX_RANGE_PLAYER if team == Unit.Team.PLAYER else MORTAR_MAX_RANGE_ENEMY


## Where the DRONE TEAM (the ground crew that launches and recovers the
## drones — see Unit.Kind.DRONE_TEAM) may deploy: the map's ordinary
## spotter zone, extended west across the whole rear area (the west flank).
## Direct user request: "let's allow the drone team to set up in the rear
## area on all maps" (first phrased about the mortar, then corrected: "not
## the mortar, the drone team"). A drone team is an unarmed rear-echelon
## element that stays well back from the fight anyway — see
## Unit.order_retreat's own handling of a drone team already sitting past
## its safe line — so this only removes the artificial stop at x=0.
## Derived from each map's own spotter zone and flank width rather than
## authored per map, so every map (present and future) gets it. Keeps the
## spotter zone's own 30m margin from the edge; the spotter itself, and
## everything else, keeps the unextended zone.
static func drone_team_deployment_zone() -> Rect2:
	var spotter_zone: Rect2 = CURRENT_MAP.player.spotter_deployment_zone
	var west_x: float = -(CURRENT_MAP.west_flank_width_m - 30.0) * PIXELS_PER_METER
	return Rect2(west_x, spotter_zone.position.y, spotter_zone.end.x - west_x, spotter_zone.size.y)


## Burst fire: replaces the old "always exactly one round per engagement"
## model. Real 82mm crews (2B14/2B24, already cited above) can cycle
## several rounds at close to their max cyclic rate (~20-30rpm — see this
## project's own shoot-and-scoot research) onto the SAME, un-corrected aim
## point before packing up and displacing, not just one. See
## BattleManager._mortar_burst_shot_count for the actual sliding formula;
## these two constants are only the outer ceiling and the close-range
## exception to it.
##
## MORTAR_BURST_MAX_SHOTS is the most rounds any single burst ever fires,
## regardless of how favorable ammo/resupply/retreat conditions are.
const MORTAR_BURST_MAX_SHOTS: int = 4

## Direct user requirement: "cap it at 3 shots if under 1000 meters." At
## short range the crew is well within the range band where the target
## (if it's a squad or another mortar) can plausibly spot or return fire
## on the firing position fastest — a hard ceiling, not a further slide,
## on top of whatever the continuous range/ammo/resupply/retreat scoring
## would otherwise pick.
const MORTAR_BURST_CLOSE_RANGE: float = 1000.0 * PIXELS_PER_METER
const MORTAR_BURST_CLOSE_RANGE_MAX_SHOTS: int = 3


## Direct user request: "I want to check the size of the mortar teams
## against reality for both friendly and enemy mortars." Researched
## directly, same "same caliber, different real weapon system" split
## already established for MORTAR_MAX_RANGE_PLAYER/ENEMY above (and
## MORTAR_SETUP_TEARDOWN_TIME's own citation) — these are genuinely
## different tubes, not the same crew requirement with a rounding
## difference:
## - PLAYER (Ukraine): the Soviet-legacy 2B14 Podnos (the same tube
##   already cited for MORTAR_MAX_RANGE_PLAYER) is documented with a
##   crew of 4 — "the entire system can be broken down into manpack
##   loads to be carried by the four-man crew" (Wikipedia; Military
##   Periscope's own overview page states the same figure, though its
##   fuller specifications are paywalled).
## - ENEMY (Russia): the 2B24 82mm light mortar (the same tube already
##   cited for MORTAR_MAX_RANGE_ENEMY and MORTAR_SETUP_TEARDOWN_TIME) is
##   documented with a crew of 5 — "the overall crew is made of five
##   soldiers, the other three carrying ammunition" (EDR Magazine, the
##   same source already cited for that tube's other two figures).
## User's own explicit direction on a real ambiguity found along the way:
## ammunition carriers should count as part of the team size for this
## game's own purposes, and after reviewing the sourcing directly, both
## cited figures above are being treated as already including them (the
## 2B24's own citation makes this explicit; the 2B14's does not
## explicitly break down roles, but no source found suggests a materially
## larger dedicated ammunition-carrying element on top of its own
## already-cited 4).
const MORTAR_CREW_SIZE_PLAYER: int = 4
const MORTAR_CREW_SIZE_ENEMY: int = 5

## The correct MORTAR_CREW_SIZE_* for `team` — mirrors mortar_max_range's
## own per-team accessor.
static func mortar_crew_size(team: Unit.Team) -> int:
	return MORTAR_CREW_SIZE_PLAYER if team == Unit.Team.PLAYER else MORTAR_CREW_SIZE_ENEMY

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

## That standing priority is the FULL value, held only while a known enemy
## squad is within DRONE_FLANK_WATCH_FADE_START of the friendly mortar (the
## same MORTAR_FLANK_THREAT_RADIUS that already defines "close enough to be
## a real flanking threat"); it fades linearly to DRONE_FLANK_WATCH_FLOOR_
## PRIORITY by DRONE_FLANK_WATCH_FADE_END (1.5x that radius) — see
## BattleManager._flank_watch_standing_priority for the live-battle report
## behind this. Direct user agreement to scale it by threat proximity. The
## floor is deliberately tiny, not zero: with nothing else competing (no
## squad worth tracking) the mortar's flanks still get checked, but any
## squad within roughly 1km of a friendly unit now outranks the check
## (TARGET_PRIORITY_SQUAD_MAX x (1 - dist/SQUAD_DANGER_RANGE) > 1.5). The
## fade distances and floor are judgment calls, not cited figures.
const DRONE_FLANK_WATCH_FADE_START: float = MORTAR_FLANK_THREAT_RADIUS
const DRONE_FLANK_WATCH_FADE_END: float = MORTAR_FLANK_THREAT_RADIUS * 1.5
const DRONE_FLANK_WATCH_FLOOR_PRIORITY: float = 1.5

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
## second full load sitting exposed next to the gun. Still the real hard
## ceiling a delivered run's rounds are capped against (see
## _resolve_resupply_run_arrivals) — MORTAR_RESUPPLY_REORDER_POINT is the
## separate, lower threshold that decides whether a run gets dispatched
## at all in the first place.
const MORTAR_MAX_AMMO_ON_HAND: int = 30

## The real dispatch trigger for a physical resupply run — not "is the
## position already completely full" (MORTAR_MAX_AMMO_ON_HAND), a
## previously-reported gap: a wave scheduled well before combat actually
## draws ammo down could arrive to find the tube barely touched (e.g.
## 29/30) and still send a full cross-map run to deliver a single round.
## Requesting stays proactive (see _update_mortar_resupply_requests — the
## long, ~hour-plus transit time means the request itself can't wait for a
## real shortage), but real logistics doctrine doesn't dispatch a
## vulnerable forward-moving vehicle just because a position isn't
## literally topped off either: FM 7-90's own resupply methods (routine/
## emergency/prestock) stage ammunition based on anticipated need and
## consumption, and its "pull"/in-position technique explicitly avoids
## pushing a real vehicle forward for a marginal delivery, preferring to
## hold at a rear point until the trip is actually worth the exposure. A
## wave held back this way isn't lost — see _update_mortar_resupply's own
## per-wave hold check — it simply never becomes a physical, spottable,
## targetable RESUPPLY_RUN unit at all for that check. Half of a full
## MORTAR_STARTING_AMMO load: low enough that a genuinely under-supplied
## position still gets topped off promptly, high enough that a real
## reserve remains on hand when the run is actually committed.
##
## That "isn't lost" claim above was aspirational for a while, not actual
## behavior — a real, live-reported bug: the code marked a held run
## resolved the instant its transit timer expired regardless of ammo, so
## it WAS effectively lost, silently discarded rather than genuinely
## staged and waiting. Fixed directly in _update_mortar_resupply — see
## that function's own doc comment for the live report and the fix.
const MORTAR_RESUPPLY_REORDER_POINT: int = 10

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

## How many enemy squads can be actively running down a known friendly
## mortar (BattleManager._chasing_mortar_in_hot_pursuit/_chase_mortar_
## directly) at the same time — a direct live correction after ten squads
## all converged on the mortar simultaneously, running past three friendly
## squads in the process: "the enemy might send 2-3 to chase the mortar.
## But the rest would fight the friendly squads." A mortar crew has no
## real close-defense capability at all (see MORTAR_CREW_OVERRUN_DANGER_
## RANGE's own doctrine), so a small handful of attackers is already
## overwhelming — a judgment call, not independently cited, but matching
## the user's own stated range directly. Squads beyond this cap (see
## BattleManager._mortar_hunt_assignments, which always assigns the
## CLOSEST ones first) simply never enter hot pursuit that tick; their
## combat power goes toward the numerically superior threat actually in
## front of them instead.
const MORTAR_HUNT_SQUAD_CAP: int = 3

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

## How the drone's search for a possible enemy mortar is weighed against
## everything else it could be doing — see BattleManager._drone_mortar_
## search_weight. Direct user direction, from a live battle where the drone
## kept flying far-afield mortar sweeps while known dangerous squads were
## nearby: "in real life one wouldn't know for certain a mortar
## reinforcement is not coming. So it could be. But that has to be weighed
## against the known dangerous enemy squads," and the repeated searches
## coming up empty matter too. Gentle, sliding adjustments — none changes
## anything early in a battle (no known squad danger, no empty sweeps yet),
## all only ever shrink the weight:
##
## - DRONE_UNKNOWN_MORTAR_RESIDUAL_CONFIDENCE: with every KNOWN enemy
##   mortar out of action, _mortar_existence_confidence returns a hard 0.0
##   — which reads real ground truth (the crews actually withdrawn), a
##   certainty no real recon element has: an unseen mortar or a
##   reinforcement can't be ruled out. The drone's weighing now never drops
##   below this small residual (deliberately below a squad even modestly
##   close to a friendly unit — TARGET_PRIORITY_SQUAD_MAX x 0.2 = 2 — so it
##   can never outrank tracking a squad that is actually near anyone).
##   _mortar_existence_confidence itself is untouched: the friendly
##   mortar's own hold-fire logic reads it too.
## - DRONE_MORTAR_SEARCH_DANGER_DISCOUNT: at full known-squad danger
##   pressure the mortar-search weight drops by this fraction (0.8 -> to a
##   fifth); proportionally less at lower pressure.
## - DRONE_EMPTY_SWEEP_CONFIDENCE_FACTOR: each sweep cell the drone has
##   reached without any new mortar evidence (a fire detection or a
##   sighting) multiplies the confidence by this — 10 empty cells is about
##   half. Resets the moment fresh evidence appears.
## - DRONE_REAR_ASSET_THREAT_WEIGHT: a known squad near the friendly
##   MORTAR or DRONE TEAM (unarmed, exposed, and what the drone flies
##   from) counts extra — direct user direction: a briefly seen squad in
##   the rear "should be a major concern for the drone team as it threatens
##   both the mortar and the drone team." Danger to them is judged on the
##   same MORTAR_FLANK_THREAT_RADIUS that already defines a real flanking
##   threat, scaled by this weight (capped at 1.0), so a squad within
##   about a third of that radius is already full pressure.
const DRONE_UNKNOWN_MORTAR_RESIDUAL_CONFIDENCE: float = 0.02
const DRONE_MORTAR_SEARCH_DANGER_DISCOUNT: float = 0.8
const DRONE_EMPTY_SWEEP_CONFIDENCE_FACTOR: float = 0.93
const DRONE_REAR_ASSET_THREAT_WEIGHT: float = 1.5

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

# The commander's optional "expend ammo on enemy squads" order for a friendly
# mortar (BattleManager.set_mortar_squad_fire_order). Multiplies every
# hold-fire probability in _pick_target that would otherwise leave the
# mortar doing nothing when its only candidates are squads — so the order
# makes firing MORE likely, never certain, and never changes which target is
# preferred (enemy mortars stay first; squad ranking is untouched). 0.1
# means a hold that would have happened 90% of the time now happens 9%.
# JUDGMENT: no real-world figure exists for this — it is a "much more willing"
# dial; 1.0 would make the order a no-op, 0.0 would make the mortar never hold.
const MORTAR_SQUAD_FIRE_ORDER_HOLD_FACTOR: float = 0.1

# Drone support for that same order (BattleManager._drone_search_target): a
# visible enemy squad inside the ordered mortar's range is worth at least
# this much attention. Level with the CEILING of the speculative sweep for
# undiscovered mortars (which wins only when strictly greater, so this wins
# ties): the commander has said the mortar's job is squads, so watching the
# ones it can shell beats a blind sweep however likely another mortar is. Still
# below every live mortar tier (a real contact, a fresh fire lead, a hunt,
# 120+), so an enemy mortar it can act on still comes first. JUDGMENT.
const DRONE_SQUAD_FIRE_ORDER_WATCH_PRIORITY: float = TARGET_PRIORITY_UNDISCOVERED_MORTAR_SWEEP
# A squad the drone can't see right now but was seen recently is worth this
# fraction of the above — enough to go look for it, less than a live one.
const DRONE_SQUAD_FIRE_ORDER_UNSEEN_FACTOR: float = 0.75
# Under that order the drone stops watching enemy mortars the ordered mortar
# can't reach - unless the crew could walk into range of one within this many
# tactical seconds at its relocation pace (BattleManager.
# _squad_order_permits_mortar_watch), or is already closing on it. JUDGMENT:
# "likely to come in range soon" has no real-world figure; 5 minutes is about
# one reload-and-scoot cycle horizon and ~660 m of walking.
const DRONE_SQUAD_FIRE_ORDER_MORTAR_SOON_S: float = 300.0

# A mortar shell doesn't land the instant it's fired — 40 tactical seconds
# of real flight time (see BattleManager._launch_mortar_shot /
# _resolve_pending_mortar_shots). It's aimed at the target's ANTICIPATED
# position, not a live one — if the target moves more than this far from
# that anticipated spot by the time the shell arrives, the round lands on
# empty ground: an outright miss, no roll needed. Roughly a mortar's
# effective burst radius — close enough and it's still in the beaten
# zone. Reused as MORTAR_BLAST_COLLATERAL_MAX_CHANCE's own outer distance
# too (see that constant's own doc comment) — the same "still in the
# beaten zone" real distance applies equally to a bystander as to the
# target itself.
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

## A real, previously-reported failure mode: shoot_and_scoot is a single,
## fixed per-battle doctrine choice — a "hold position" crew otherwise
## never relocates for this reason regardless of how many enemy mortars
## are actually known to be in striking range right now. The real risk
## compounds fast: with `count` independent enemy mortars each able to
## roll MORTAR_COUNTER_BATTERY_CHANCE against the same shot (see
## _resolve_mortar_counter_battery), the chance at least one answers is
## 1-(1-0.22)^count — 22% for one, but already 39% for two and 63% for
## four, the exact case that got a mortar destroyed for holding position
## in a genuinely dense counter-battery environment. This constant is
## that count threshold, not a cited figure but a direct read of the
## above formula: two independently-confirmed enemy mortars in range
## already means a worse-than-a-third chance of return fire, well past
## the point where any standing "hold position" preference is still a
## reasonable bet. Used by BattleManager._mortar_should_relocate_for_
## safety to override even a hold-position doctrine once met (still
## conditioned on the mortar's own position actually being compromised —
## see that function's own doc comment for the full picture) — see
## _known_enemy_mortars_in_range for how "known" is resolved (never
## omniscient ground truth). Player-only for now, matching this project's
## standing "enemy may differ" convention.
const MORTAR_DENSITY_FORCE_SCOOT_COUNT: int = 2

## A lower bar than MORTAR_DENSITY_FORCE_SCOOT_COUNT above, and a
## deliberately different one — that constant justifies overriding an
## ACTIVE decision (a deliberate hold-position doctrine) with real
## compounding-probability math, since overriding a player's own standing
## choice needs real justification. This constant is the baseline
## requirement in BattleManager._mortar_should_relocate_for_safety: the
## minimum number of known enemy mortars actually in range before a
## compromised position is worth doing anything about AT ALL, regardless
## of doctrine. One confirmed enemy tube in range, with this mortar's own
## position already given away, is already a real, direct reason to move —
## it just isn't yet severe enough to override a deliberate hold-position
## choice (that's what MORTAR_DENSITY_FORCE_SCOOT_COUNT is for). See
## BattleManager._known_enemy_mortars_in_range for how "known" is
## resolved. Player-only, matching the same "enemy may differ" convention
## as the constant above.
const MORTAR_STANDING_THREAT_COUNT: int = 1

# How long a mortar's firing position stays "worth pursuing" for counter-
# battery-range-chasing purposes after being detected (see BattleManager.
# _launch_mortar_shot / _known_friendly_mortar_position) — real counter-
# battery detection is via the outgoing round's muzzle blast/trajectory,
# not visual spotting, so this doesn't require the mortar to stay visually
# exposed. Tactical seconds; comfortably above the counter-battery response
# window's own realistic worst case (see COUNTER_BATTERY_LOCATE_TIME_MAX's
# own doc comment for the full breakdown) — old enough and the mortar has
# almost certainly moved on, not worth chasing a stale fix.
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

# When more than one enemy mortar is simultaneously visible, the closer
# one to our own mortar is preferred — but not on every single tick's
# worth of ordinary positional jitter. Without a real margin, two enemy
# mortars sitting nearly equidistant could flip which one counts as "the"
# known lead back and forth as normal movement nudges one microscopically
# closer than the other, each flip discarding whatever the previous pick's
# hunt was making progress toward — see BattleManager.
# _known_enemy_mortar_lead's own doc comment. A real distance, not a
# fraction of range — a judgment call, picked comfortably larger than a
# single tick's worth of ordinary mortar-relocation movement so genuine
# jitter can never cross it, while a mortar that's actually, clearly
# closer (having relocated meaningfully, or simply always was) still
# takes over.
const MORTAR_LEAD_SWITCH_MARGIN: float = 100.0 * PIXELS_PER_METER

# The PREFERRED ceiling on the friendly mortar's own hunting — see
# BattleManager._friendly_mortar_home_position / _update_joint_mortar_
# hunt / _update_friendly_mortar_hunting. Hunting a known enemy mortar is
# good, but a real crew still won't routinely range indefinitely far
# from wherever they were actually set up just because a drone reports a
# trusted fix — this is how far a hunt's DESTINATION may end up from that
# deployment position under ORDINARY circumstances, regardless of trust
# level, and regardless of whether any enemy squads are known to be
# nearby (that's a SEPARATE concern, already handled by
# _friendly_mortar_hunt_point's own concealment-seeking — this is about
# distance from home, full stop, not about avoiding specific known
# threats along the way). Set to half MORTAR_MAX_RANGE_PLAYER (this
# constant is explicitly the FRIENDLY mortar's own leash, never the
# enemy's) — enough real room to reposition meaningfully for a shot, not
# half the map.
#
# NOT an absolute wall, though — a real, direct correction, after this
# constant's own earlier absolute-ceiling framing produced a live,
# reported bug: a mortar whose only known enemy-mortar fix sat beyond
# this distance from home in every direction was permanently rejecting
# every hunt candidate _friendly_mortar_hunt_point ever proposed, with
# no way to ever get a shot at the single highest-priority target type
# there is. The user's own correction: "the range leash is not an
# absolute thing. The mortar could reasonably go briefly outside of it,
# but then back in to take a shot." See MORTAR_HUNT_EXTENDED_RANGE_
# FROM_HOME for the real, bounded excursion this constant's own
# preference now falls back to rather than refusing outright.
const MORTAR_HUNT_MAX_RANGE_FROM_HOME: float = MORTAR_MAX_RANGE_PLAYER * 0.5

# The real, bounded fallback MORTAR_HUNT_MAX_RANGE_FROM_HOME's own doc
# comment describes — "briefly outside of it, but then back in to take
# a shot," not an unlimited excursion. Set to the mortar's own full,
# uncapped MORTAR_MAX_RANGE_PLAYER (double the preferred leash) —
# genuinely bounded (this is still a real, finite distance, not "the
# whole map"), but far enough to actually reach a known enemy mortar
# that's currently just past the preferred leash, which a real crew
# chasing the single highest-priority target type on the battlefield
# would reasonably do. Only ever consulted as a FALLBACK — see
# _mortar_hunt_destination_for's own two-stage "prefer the tighter
# leash, only reach for this one when nothing within it works at all"
# structure, the same pattern already used throughout this family of
# searches (never an unconditional relaxation of the ordinary leash).
const MORTAR_HUNT_EXTENDED_RANGE_FROM_HOME: float = MORTAR_MAX_RANGE_PLAYER

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
# MORTAR_MAX_RANGE_ENEMY above) states "the transition from traveling to firing
# position, and vice versa, is accomplished in less than 30 seconds" — one
# real figure covering both directions, used here as a floor on Unit.
# seconds_stationary (already tracked for spotting-signature decay — see
# CombatResolver) rather than inventing a separate "set up"/"moving" state
# machine: Unit.Activity's existing STATIONARY/MOVING split, plus how long
# a unit has genuinely BEEN stationary, already is that distinction.
# Gates a mortar's own ability to fire (BattleManager._mortar_shot_this_
# tick) until it's been stationary this long since its last real
# displacement, and a shoot-and-scoot crew doesn't start walking away
# until this long after firing (_queue_mortar_displacement /
# _resolve_pending_mortar_displacement) — that pair together IS "become
# mobile, then actually walk there" for the crew that just fired: this is
# the become-mobile half, real movement at MORTAR_RELOCATE_SPEED over the
# real distance chosen is the other. Reused again below as the SETUP half
# of a counter-battery responder's own readiness, for the same physical
# reason. A mortar that's never moved at all defaults to Unit.
# seconds_stationary = 1e9 (already emplaced since before the battle
# began), so this never delays a hold-position mortar's very first shot.
const MORTAR_SETUP_TEARDOWN_TIME: float = 30.0 # tactical seconds

## A minimum dwell time before a NON-URGENT relocation (BattleManager.
## _relocate_mortar, gated on `not urgent`) is even reconsidered —
## deliberately its own, separate constant from MORTAR_SETUP_TEARDOWN_
## TIME above, not a reuse: that one answers "how long until this crew
## is physically ready to fire again," a real but much SHORTER question
## than "how long is it reasonable to expect this crew to stay in one
## spot before voluntarily moving again." Reusing the shorter figure was
## tried first and measured as barely different from no gate at all — at
## this project's own real tick granularity (TIME_SCALE_NORMAL/FAST_
## FORWARD, 30-150 tactical seconds per tick), 30 tactical seconds can
## already elapse within a SINGLE tick, so a mortar could satisfy that
## gate the instant it arrived, defeating the entire point.
##
## Real reasoning, not an arbitrary bump: this project's own existing
## doc comments already establish that a single relocation LEG can
## legitimately take several real minutes to walk at MORTAR_RELOCATE_
## SPEED over real displacement distances — a crew that just finished
## one leg has no realistic reason to consider a completely fresh one
## sooner than that same rough timescale, confirmed directly as the
## actual missing piece behind a live, reported oscillation: an
## unspotted, unthreatened out-of-ammo mortar re-relocating almost every
## tick, criss-crossing the same handful of points 50-100m apart
## (measured directly — see the design doc's own entry). A genuinely
## URGENT relocation (spotted, a real threat closing, just took counter-
## battery fire) is entirely untouched by this — survival is never
## throttled by how recently the crew last moved.
const MORTAR_VOLUNTARY_RELOCATION_COOLDOWN: float = 180.0 # tactical seconds

## Counter-battery fire isn't instant, and isn't one flat random delay
## either — it's the sum (and, for two of these, the MAX — see below) of
## real component times a responding crew actually goes through, not a
## single directly-stored number (see BattleManager._resolve_mortar_
## counter_battery, which composes these):
##
## 1. LOCATE — the original shot's own muzzle blast/trajectory gives its
##    firing position away instantly (see MORTAR_FIRE_DETECTION_EXPIRY's
##    own doc comment — this isn't visual spotting, it doesn't need eyes
##    on the position), but turning "a shot came from roughly that
##    direction" into an actual usable grid coordinate takes real time.
##    Modern radar-cued counter-battery can generate a fire mission in
##    "a matter of seconds"; this project's own early-war setting has no
##    counter-battery radar at this echelon, so it's slower than that —
##    but still a small unit
##    cross-cueing over radio in a compact battle space, not a formal
##    WWI-style sound-ranging network (which historically took 3-5
##    minutes to pass a location to the intelligence officer, an entirely
##    different, much larger organizational process). A judgment call
##    within that real range, not a single cited figure.
## 2. SETUP — if the responding mortar was itself still displacing (not
##    fully emplaced) at the moment the enemy shot landed/fired, it needs
##    the SAME real transition time as MORTAR_SETUP_TEARDOWN_TIME above
##    (same tube, same physical act) before it can fire back at all;
##    already-emplaced (the common case) costs nothing here.
##
##    LOCATE and SETUP run in PARALLEL, not stacked — confirmed against
##    real fire-direction-center procedure, not assumed: doctrine has the
##    FDO announce "FIRE MISSION" to the gun crews the INSTANT a call for
##    fire comes in, so the crew starts laying/prepping at the same time
##    the fire direction center computes the actual firing data, not
##    after. Different people/systems doing different jobs — a crew
##    physically emplacing a tube doesn't block whoever is figuring out
##    where to aim it, and vice versa. So the two are combined with
##    max(), not +.
## 3. LAY (+ fire) — once BOTH a location and a ready tube exist, actually
##    laying onto that specific azimuth/elevation and firing. Grounded on
##    real reporting that a crew given a fire mission gets its first
##    round downrange within about 10 seconds — this covers that same
##    step, not a separate long process.
## 4. FLIGHT — MORTAR_FLIGHT_TIME, already modeled and reused as-is; the
##    round's own physical time in the air, identical physics to every
##    other mortar shot in this file.
##
## The resulting total (roughly 75-165 tactical seconds react + flight,
## depending on rolls) lands in the same real ballpark independently
## reported for Ukraine-war counter-battery: full radar-cued engagement
## (including flight) at "1-2 minutes, 3 at the outside," and a mortar
## crew has on the order of 90-120 seconds after its last round to
## displace before a radar-cued response catches it. By the time it
## lands, a shoot-and-scoot mortar has likely moved well clear; a
## hold-position mortar is still standing right there. If the mortar is
## still within the blast radius when the shell lands, it can still get
## hit — the odds just fall off with distance from the original firing
## spot.
##
## LOCATE's own range specifically (not SETUP or LAY) was tuned by direct
## measurement, not guessed and left unchecked: an earlier pass (20-90s)
## reproduced a REAL average of ~55s for an already-emplaced responder —
## faster on average than the single flat 60-180s range (the FULL
## detect-to-fire time, not just the reaction portion) this replaced ever
## was for that exact case, since that's the common one (most responders
## are already set up when they get shot at, not mid-relocation) — a
## real, measured 20-30-trial Monte Carlo showed player-mortar
## destruction roughly DOUBLING versus the pre-rework baseline as a
## direct result: counter-battery simply landed sooner, on average,
## against a target that hadn't moved (and often can't, if not on a
## shoot-and-scoot doctrine) at all. Retuned to 30-110s so LOCATE + LAY's
## own average (70 + 10 = 80s) matches the OLD flat range's own average
## reaction time (110s midpoint - 40s flight = 70s... old average was
## actually the midpoint of [20,140], i.e. 80s) for that same common
## case — the decomposition is real and the "if moving" realism is
## still there (SETUP still wins the max() whenever a responder's own
## remaining setup time exceeds however LOCATE happened to roll), it
## just no longer silently makes an already-set-up mortar's own return
## fire arrive faster than before purely as a side effect of picking
## ranges that summed to a smaller number than the range being replaced.
const COUNTER_BATTERY_LOCATE_TIME_MIN: float = 30.0 # tactical seconds
const COUNTER_BATTERY_LOCATE_TIME_MAX: float = 110.0 # tactical seconds
const COUNTER_BATTERY_LAY_TIME_MIN: float = 5.0 # tactical seconds
const COUNTER_BATTERY_LAY_TIME_MAX: float = 15.0 # tactical seconds
## How far a crew needs to actually move to be clear of counter-battery
## fire aimed at its old position — real doctrine cites 75-100m for
## EMERGENCY displacement under pressure to keep firing (short enough that
## the same firing data still applies with only a minor adjustment, not a
## whole fresh fire mission), versus a much shorter 25-30m for a merely
## PLANNED move to an alternate position with no immediate threat driving
## it. This project's own scoot trigger (_mortar_should_relocate_for_
## safety) is always the former case — the position has already been
## detected AND a real known threat is in range — so the lower end of the
## cited emergency range is the right anchor, not an arbitrary number
## between the two doctrine figures. Previously 150m with no real
## citation behind it; real doctrine explicitly frames longer moves as a
## responsiveness cost, not a free safety upgrade ("frequent displacement
## enhances survivability... but can degrade the ability of mortars to
## provide immediate massed fires") — a real, reported symptom this
## grounds: scoots covering hundreds to thousands of meters, several
## times too far even for the doctrine's own worst-case emergency figure,
## and long enough to put other units sited along the way at real risk.
const COUNTER_BATTERY_BLAST_RADIUS: float = 75.0 * PIXELS_PER_METER # beyond this, the old position is safe

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
## Raised from an earlier 600m and its own former direct-LOS requirement
## dropped, after a live incident: an enemy squad given a genuine "run the
## mortar down directly" pursuit (see BattleManager._chasing_mortar_in_
## hot_pursuit) closed in and destroyed the crew before it ever started
## running. Re-checked against FM 7-90 directly rather than guessed at: the
## manual gives no explicit distance for this specific question (crew
## self-defense reaction range to closing infantry), but its own doctrine
## for local security networks around a firing position uses intervisible
## observation posts at roughly 500m intervals specifically to give early
## warning of an approaching force BEFORE it reaches the position — the
## same underlying principle this constant exists to encode. Direct user
## correction, twice over: "It's enough if you know they are there, or
## even if you recently knew they were there" — genuine direct line of
## sight was too strict a bar for THIS specific question. A nearby-but-
## currently-blind known enemy (terrain in the way right now) is still a
## real reason for a crew to displace before it closes the remaining
## distance and gets a clear shot — unlike _pick_target's own hold-fire
## calculus (a different question: "is this specific candidate worth a
## round right now"), self-preservation doesn't get to wait for
## confirmation the danger has already arrived. BattleManager._decide_
## mortar_action's own proactive "is anything closing in on us" check
## (_unwatched_threat_closing) now reads purely off known position and
## distance — no LOS requirement at all. The REACTIVE checks (_mortar_
## crew_holds_position's post-hit hold-or-flee roll, _pick_target's own
## overrun override) never had one to begin with — by the time either of
## those runs, the crew has either already been hit (so something can
## already reach them regardless of this range) or is actively choosing
## whether to spend a round on a candidate already inside normal
## engagement range, a different question than "is anything about to find
## us."
const MORTAR_CREW_OVERRUN_DANGER_RANGE: float = 750.0 * PIXELS_PER_METER

## Direct user clarification of the flee-off-the-map last resort: "If enemy
## squads are chasing the mortar, but it is still far from the map edge, it
## should act to preserve itself. This self preservation may well involve
## retreating towards the map edge. However, full retreat off of the map is
## not yet required at that point. If the enemy squads continue chasing,
## and the mortar gets close to the edge, at that point it would retreat
## offmap." A mortar with nowhere to hide (see BattleManager._mortar_flee_
## as_last_resort) now falls back toward its own edge while still ACTIVE —
## one continuous run of MORTAR_EDGE_RUN_LEG-sized waypoints, at the
## mortar's own retreat speed, ending inside MORTAR_FLEE_COMMIT_DISTANCE of
## the edge — and only commits to the one-way off-map retreat once it's
## there and still cornered. Both are judgment calls, not cited figures:
## the commit distance is roughly the point past which a crew still being
## chased has no meaningful ground left to trade for time; the leg length
## only sets how finely the run bends around buildings/the river and away
## from a chaser, and doesn't change the trip's duration.
const MORTAR_FLEE_COMMIT_DISTANCE: float = 500.0 * PIXELS_PER_METER
const MORTAR_EDGE_RUN_LEG: float = 300.0 * PIXELS_PER_METER

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
# targeted — real militaries avoid bunching up for exactly this reason.
# Side-agnostic: a stray round from small-arms fire doesn't check whose
# side the neighboring squad is on, though it's a small, flat, close-range
# chance (small-arms fire is comparatively discriminating) rather than the
# much larger, distance-scaled one below for actual HE fragmentation. See
# BattleManager._resolve_fire_and_check_bunching / _collateral_victim.
const BUNCHING_RADIUS: float = 30.0 * PIXELS_PER_METER
const BUNCHING_SPILLOVER_CHANCE: float = 0.25

## A real HE mortar round's fragmentation doesn't check whose side anyone
## is on — anybody within the round's actual burst radius has a real
## chance of being caught too, whether they were the intended target, an
## ally standing nearby, or an enemy unit that happened to be close to
## where the round landed.
##
## The distance at which this chance actually falls off is MORTAR_BLAST_
## CASUALTY_RADIUS below, NOT this file's own MORTAR_EVASION_RADIUS —
## despite both being real distances derived from the same 82mm round,
## they answer two different questions. MORTAR_EVASION_RADIUS is about
## whether a shot is close enough to the AIMED-AT point to still register
## as a real near-miss on the primary target (an aiming/ballistics
## concept). This constant is about the round's own actual fragmentation
## reach once it lands — a real physical effect, independent of what it
## was aimed at, that a bystander is exactly as exposed to as the intended
## target. See MORTAR_BLAST_CASUALTY_RADIUS's own doc comment for why they
## used to be conflated and why that mattered.
const MORTAR_BLAST_COLLATERAL_MAX_CHANCE: float = 0.95

## The real, cited distance behind CombatResolver.blast_casualty_chance's
## exponential falloff — NOT a "safe beyond this" wall the way this
## project's blast-radius constants (COUNTER_BATTERY_BLAST_RADIUS,
## MORTAR_EVASION_RADIUS) are used elsewhere. "Casualty radius" is a real,
## specific military-planning term: the distance at which a STATED
## PERCENTAGE — conventionally 50% — of EXPOSED personnel become
## casualties. It is explicitly NOT the outer edge of all possible harm:
## real reporting on HE fragmentation states it plainly — "casualty
## radius is a statistical planning figure, not a wall: fragments kill
## well beyond the published radius, and people survive inside it." That
## is exactly why this project's own blast-chance math used to be wrong —
## both existing call sites (this collateral check and _resolve_pending_
## counter_battery's own impact_chance) modeled a flat LINEAR falloff to
## a hard, certain zero at their radius's edge, which is neither how real
## fragmentation behaves (it decays smoothly, never truly to zero within
## any reachable game distance) nor what "casualty radius" as a term even
## claims to describe (a 50%-point, not a boundary of possibility).
##
## Cited: 82mm Type 67 mortar HE, ~26m lethal-fragment radius — this
## project's own mortar is already modeled as this caliber elsewhere (see
## this constant's own prior use, before this rewrite, citing the same
## source). 81mm rounds generally are reported with a somewhat larger
## ~35-40m effective casualty radius and 120mm rounds in the "tens of
## meters," so 26m sits at the smaller, more conservative end of the real
## range for a mortar this size — a deliberate, explicitly-flagged choice
## rather than an attempt to average multiple different-caliber figures
## into one number.
const MORTAR_BLAST_CASUALTY_RADIUS: float = 26.0 * PIXELS_PER_METER

## The outer radius _collateral_victim actually searches for a bystander
## around a blast — used to be a reuse of MORTAR_EVASION_RADIUS (40m),
## which (see MORTAR_BLAST_COLLATERAL_MAX_CHANCE's own doc comment) exists
## for a different, aiming-related reason and just happened to be a
## convenient existing number. Now sized to give CombatResolver.
## blast_casualty_chance's own smooth exponential tail (see MORTAR_BLAST_
## CASUALTY_RADIUS's doc comment on why it doesn't hit a hard zero) real
## room to actually apply beyond the cited casualty radius, rather than
## cutting it off almost immediately past it — a judgment call on how far
## out that real but low-probability tail is still worth modeling at all,
## not a cited figure of its own.
const MORTAR_BLAST_COLLATERAL_SEARCH_RADIUS: float = 60.0 * PIXELS_PER_METER

## Ballistic dispersion: a mortar's calculated aim point (BattleManager.
## _mortar_aim_point) isn't where the round actually lands — real indirect
## fire has inherent scatter from muzzle-velocity variance, propellant
## temperature, wind, and fin/fuze tolerances, on top of any lead-
## estimation error. Unadjusted ("predicted") fire's dispersion scales with
## range: cited NATO figures put an unguided 120mm mortar's CEP at ~136m at
## max range without an advanced fire control system. This project's 82mm
## mortars have a shorter max range (MORTAR_MAX_RANGE_PLAYER/_ENEMY), so
## the same ~3% CEP-of-range fraction is applied to the ACTUAL shot
## distance each time rather than reusing the 136m figure outright (that
## number is for a different caliber at a longer real max range) — a
## fraction of range works the same regardless of which side's own max
## range it's measured against. See BattleManager._mortar_dispersion_offset.
const MORTAR_DISPERSION_CEP_FRACTION_OF_RANGE: float = 0.03
## Even a short shot isn't perfect — met data, propellant-lot, and lay
## error impose a floor regardless of range. Judgment call, not directly
## cited: kept comfortably below MORTAR_EVASION_RADIUS so short-range shots
## still usually connect.
const MORTAR_DISPERSION_UNADJUSTED_FLOOR: float = 15.0 * PIXELS_PER_METER

## "Walking fire" onto a target: real indirect-fire doctrine (FM 6-30's
## successive-bracketing method) has an observer watch where each round
## lands and radio a correction, converging over a handful of adjusting
## rounds before "fire for effect" — a real forward observer with
## instruments can register a mean point of impact to roughly 20m (FM 6-30
## mortar registration worked example: "MPI ~18-20m R"). Consecutive shots
## at the SAME target converge dispersion toward a floor, geometrically,
## for as long as someone can actually see where rounds are landing (see
## BattleManager._mortar_fire_observation_quality) — with no observer at
## all, fire stays "predicted": no correction is ever possible, full CEP
## forever, exactly like unobserved/map-data-only fire in real doctrine.
##
## Three observer qualities, most to least precise, each its own
## convergence rate and floor:
## - Drone: real-time full-motion video lets a controller see the exact
##   miss and correct almost immediately — reported Ukraine-war drone-
##   corrected fire missions destroying a platoon position in ~9 rounds
##   versus 60-90 unobserved (Ukrainian drone-directed-artillery
##   reporting, spring 2022), an order-of-magnitude efficiency gain this
##   project models as the fastest convergence to the tightest floor.
## - Dedicated spotter (trained FO): doctrine's own baseline case — the
##   ~20m registered-MPI figure above.
## - Self-observing squad (no FO instruments, comms lag, not trained
##   observers): plausible but slower and coarser. Judgment call, not
##   independently cited.
const MORTAR_DISPERSION_DRONE_DECAY: float = 0.15
const MORTAR_DISPERSION_DRONE_FLOOR: float = 6.0 * PIXELS_PER_METER
const MORTAR_DISPERSION_SPOTTER_DECAY: float = 0.35
const MORTAR_DISPERSION_SPOTTER_FLOOR: float = 18.0 * PIXELS_PER_METER
const MORTAR_DISPERSION_SQUAD_DECAY: float = 0.65
const MORTAR_DISPERSION_SQUAD_FLOOR: float = 30.0 * PIXELS_PER_METER

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
	# Cheap reject before the angle and cosine harmonics below: no warp can
	# push the radius past radius_m * (1 + the harmonics' amplitude sum), so
	# anything farther than that is outside for certain — identical result,
	# just far cheaper for the many-patch maps (a query otherwise pays atan2
	# and two cosines for EVERY patch, however far away).
	var max_warp: float = 1.0
	for h in patch.warp_harmonics:
		max_warp += absf(h.amplitude)
	if d > patch.radius_m * max_warp:
		return false
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
	if not _terrain_grid_built:
		_build_terrain_grid()
	var key: int = _terrain_grid_key(pos)
	var zone_ids: Array = _terrain_grid_zones.get(key, [])
	for i in zone_ids:
		if CURRENT_MAP.terrain_zones[i].rect.has_point(pos):
			return TerrainType.BUILDING
	var patch_ids: Array = _terrain_grid_patches.get(key, [])
	for i in patch_ids:
		if _point_in_forest_patch(CURRENT_MAP.forest_patches[i], pos):
			return TerrainType.TREES
	return TerrainType.OPEN


## A coarse spatial index over CURRENT_MAP's BUILDING zones and forest
## patches, so get_terrain_type_at only examines the handful near a point
## instead of every one on the map — a map traced from real imagery can
## carry well over a hundred tree patches, and the plain scan cost every
## query a check against all of them (about 6x a 20-patch map's, measured).
## Each grid cell lists every zone/patch whose bounding box/circle (a
## patch's at its LARGEST possible warped radius) touches it, so a point's
## answer is identical to scanning everything. Built lazily on first query
## and dropped by _recompute_map_derived_state whenever the map changes.
const _TERRAIN_GRID_CELL_PX: float = 40.0
static var _terrain_grid_built: bool = false
static var _building_rects: Array[Rect2] = [] # every BUILDING zone's rect, for the line-crossing checks (has_direct_los, path_crosses_building)
static var _terrain_grid_zones: Dictionary = {} # cell key -> Array of terrain_zones indices (BUILDING only)
static var _terrain_grid_patches: Dictionary = {} # cell key -> Array of forest_patches indices


static func _terrain_grid_key(pos: Vector2) -> int:
	# Offset keeps negative (west flank) cells positive; 4096 columns per
	# row is far wider than any map here.
	return (int(floor(pos.x / _TERRAIN_GRID_CELL_PX)) + 512) + (int(floor(pos.y / _TERRAIN_GRID_CELL_PX)) + 512) * 4096


static func _terrain_grid_add(target: Dictionary, index: int, min_px: Vector2, max_px: Vector2) -> void:
	var x0: int = int(floor(min_px.x / _TERRAIN_GRID_CELL_PX))
	var x1: int = int(floor(max_px.x / _TERRAIN_GRID_CELL_PX))
	var y0: int = int(floor(min_px.y / _TERRAIN_GRID_CELL_PX))
	var y1: int = int(floor(max_px.y / _TERRAIN_GRID_CELL_PX))
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var key: int = (cx + 512) + (cy + 512) * 4096
			if not target.has(key):
				target[key] = []
			target[key].append(index)


static func _build_terrain_grid() -> void:
	_terrain_grid_built = true
	_terrain_grid_zones.clear()
	_terrain_grid_patches.clear()
	_building_rects.clear()
	var zones: Array = CURRENT_MAP.terrain_zones
	for i in zones.size():
		if zones[i].type != TerrainType.BUILDING:
			continue
		var rect: Rect2 = zones[i].rect
		_building_rects.append(rect)
		_terrain_grid_add(_terrain_grid_zones, i, rect.position, rect.end)
	var patches: Array = CURRENT_MAP.forest_patches
	for i in patches.size():
		var patch: Dictionary = patches[i]
		var max_warp: float = 1.0
		for h in patch.warp_harmonics:
			max_warp += absf(h.amplitude)
		var reach_px: float = patch.radius_m * max_warp * PIXELS_PER_METER
		var center_px: Vector2 = patch.center_m * PIXELS_PER_METER
		_terrain_grid_add(_terrain_grid_patches, i, center_px - Vector2(reach_px, reach_px), center_px + Vector2(reach_px, reach_px))


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
	if not _terrain_grid_built:
		_build_terrain_grid()
	var segment_box: Rect2 = Rect2(from, to - from).abs()
	for rect in _building_rects:
		if not rect.intersects(segment_box, true):
			continue # a segment can't cross a rectangle its bounding box doesn't even touch
		if _line_crosses_rect(from, to, rect):
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


static func nearest_cover_point(from: Vector2, retreat_dir: float = 0.0, avoid_buildings: bool = false, avoid_positions: Array[Vector2] = [], known_enemy_positions: Array[Vector2] = [], bunch_avoid_positions: Array[Vector2] = [], no_reversal_positions: Array[Vector2] = [], travel_direction: Vector2 = Vector2.ZERO, firing_point: Vector2 = Vector2.INF, reference_point: Vector2 = Vector2.INF) -> Vector2:
	var candidates: Array[Dictionary] = []
	for zone in _all_cover_zones():
		if avoid_buildings and zone.type == TerrainType.BUILDING:
			continue
		var d: float = from.distance_to(zone.center)
		# See retreat_cover_point_toward's own doc comment on this same
		# principle — cover is a MEANS to reaching `reference_point` (the
		# map edge, for a retreat), not a competing goal: ranking by REAL
		# total trip distance (here to the zone, then on to the edge)
		# instead of raw distance from `from` alone is what stops a zone
		# that's merely closer RIGHT NOW from beating one that's actually
		# on the way, direct user correction after exactly this cost a
		# mortar its life taking a real, avoidable detour instead. Left at
		# its default (Vector2.INF) for every non-retreat caller (a squad
		# diving for cover mid-fight has no "edge" to aim for at all) —
		# only order_retreat's own callers pass a real value.
		if reference_point != Vector2.INF:
			d += zone.center.distance_to(reference_point)
		candidates.append({"zone": zone, "dist": d})
	if candidates.is_empty():
		return from

	# See nearest_hidden_point's own doc comment on `firing_point` — the top
	# priority of a post-fire relocation, checked first and against the
	# full, unfiltered pool so it always wins when any real alternative
	# clears it.
	if firing_point != Vector2.INF:
		var clear_of_firing_point: Array[Dictionary] = candidates.filter(func(c): return c.zone.center.distance_to(firing_point) >= COUNTER_BATTERY_BLAST_RADIUS)
		if not clear_of_firing_point.is_empty():
			candidates = clear_of_firing_point

	candidates = _exclude_dangerous(candidates, known_enemy_positions)
	candidates = _prefer_retreat_direction(candidates, from, retreat_dir)
	candidates = _prefer_clear_path(candidates, from, avoid_buildings)

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

	# See MORTAR_BUNCHING_CRITICAL_RADIUS's own doc comment — a real,
	# separate gap found once _ring_search_hidden_point's own bunching fix
	# was verified against full real battles: whenever a mortar's own
	# relocation has no known threats to route around at all (a real,
	# common case — the enemy's own knowledge of the player's positions,
	# not whether the mortar itself has been spotted), it lands here
	# instead of in the ring search, and `avoid_positions` above only
	# excludes a zone that literally CONTAINS a sibling's position — no
	# help at all when a sibling isn't standing inside any mapped cover
	# zone, exactly the sparse-cover, map-edge case this was measured
	# failing in. A genuine radius-based check, same critical threshold
	# as the ring search, same two-stage "prefer exclusively, fall back
	# only if nothing clears it" pattern — kept as its own parameter
	# rather than folded into `avoid_positions` so the squad-bunching use
	# of that parameter (a different, already-working mechanism) is
	# untouched.
	if not bunch_avoid_positions.is_empty():
		var clear_of_siblings: Array[Dictionary] = []
		for c in candidates:
			var too_close := false
			for p in bunch_avoid_positions:
				if c.zone.center.distance_to(p) < MORTAR_BUNCHING_CRITICAL_RADIUS:
					too_close = true
					break
			if not too_close:
				clear_of_siblings.append(c)
		if not clear_of_siblings.is_empty():
			candidates = clear_of_siblings

		# A second, softer preference on top of the hard critical-radius
		# floor above — see MORTAR_BUNCHING_AVOIDANCE_RADIUS's own doc
		# comment: 300m is a real cited separation GUIDELINE, not an
		# absolute wall, and this used to be a second hard two-stage
		# exclusion here. That reproduced exactly the starvation failure
		# mode _ring_search_hidden_point's own continuous factor was built
		# to avoid (see that function's own doc comment) — per the user's
		# own direct correction, mortars should like closer separation
		# less and less as it shrinks, but must still be allowed to accept
		# it when every mapped cover zone near a cluster of siblings sits
		# within 300m anyway. Scales the effective search distance up
		# smoothly instead of excluding: no penalty once fully clear,
		# growing (never to a hard wall) the closer a zone sits to a
		# sibling — folded into the same `dist` field the sort below
		# already ranks on, so a closer-but-clear zone can still outrank a
		# farther, more-bunched one instead of the two being incomparable.
		for c in candidates:
			var nearest_sibling_dist: float = INF
			for p in bunch_avoid_positions:
				nearest_sibling_dist = min(nearest_sibling_dist, c.zone.center.distance_to(p))
			if nearest_sibling_dist < INF:
				# See mortar_bunch_score_factor's own doc comment.
				c.dist = c.dist / mortar_bunch_score_factor(nearest_sibling_dist)

	# See MORTAR_NO_REVERSAL_RADIUS's own doc comment — this is the path
	# that was silently receiving NO recent-position protection at all
	# (the legacy `avoid_positions` above is zone-containment-based, not
	# radius-based, and a bare remembered point almost never satisfies
	# it). Same two-stage "prefer exclusively, fall back only if nothing
	# clears it" pattern as the bunching checks just above. Checked
	# against the WHOLE remembered history here, not just the single
	# most-recent entry (unlike the ring search's own, narrower use of
	# this same radius — see that function's own doc comment for why):
	# this search draws from every cover zone on the map, not a small
	# local ring, so there's no comparable starvation risk to widening
	# it, and a real, measured gap confirmed protecting only the latest
	# entry still let a mortar return to its SECOND or THIRD most recent
	# spot instead.
	if not no_reversal_positions.is_empty():
		var clear_of_reversal: Array[Dictionary] = []
		for c in candidates:
			var reverses := false
			for p in no_reversal_positions:
				if c.zone.center.distance_to(p) < MORTAR_NO_REVERSAL_RADIUS:
					reverses = true
					break
			if not reverses:
				clear_of_reversal.append(c)
		if not clear_of_reversal.is_empty():
			candidates = clear_of_reversal

	# See MORTAR_REVERSAL_DIRECTION_DOT_THRESHOLD's own doc comment — a
	# genuinely different, complementary check from the position-based
	# one just above: not proximity to a specific old spot, but whether
	# this candidate's own direction from `from` undoes the crew's most
	# recent direction of travel outright.
	if travel_direction != Vector2.ZERO:
		var clear_of_direction_reversal: Array[Dictionary] = []
		for c in candidates:
			var to_candidate: Vector2 = c.zone.center - from
			if to_candidate.length() < 1.0 or to_candidate.normalized().dot(travel_direction) >= MORTAR_REVERSAL_DIRECTION_DOT_THRESHOLD:
				clear_of_direction_reversal.append(c)
		if not clear_of_direction_reversal.is_empty():
			candidates = clear_of_direction_reversal

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
	var chosen_zone: Dictionary = candidates[chosen_index].zone

	# A real, previously-reported gap: the reversal checks above filter
	# by the ZONE'S OWN CENTER, but the actual destination handed back is
	# a randomized point somewhere WITHIN that zone (see
	# _random_point_in_cover_zone) — for a forest patch meaningfully
	# larger than MORTAR_NO_REVERSAL_RADIUS, a zone whose CENTER cleared
	# every check can still hand back an actual point close enough to
	# count as a real reversal, since the random draw inside it has no
	# awareness of either check at all. Confirmed directly via a live
	# trace: the position/direction filters were correctly finding
	# non-reversal candidates, yet the mortar kept reversing anyway.
	# Re-rolled a bounded number of times rather than checked once and
	# given up — a genuinely large zone can need several draws before
	# landing in the part of it that's actually clear.
	var point: Vector2 = _random_point_in_cover_zone(chosen_zone)
	if not no_reversal_positions.is_empty() or travel_direction != Vector2.ZERO:
		for attempt in 5:
			var ok := true
			for p in no_reversal_positions:
				if point.distance_to(p) < MORTAR_NO_REVERSAL_RADIUS:
					ok = false
					break
			if ok and travel_direction != Vector2.ZERO:
				var to_point: Vector2 = point - from
				if to_point.length() >= 1.0 and to_point.normalized().dot(travel_direction) < MORTAR_REVERSAL_DIRECTION_DOT_THRESHOLD:
					ok = false
			if ok:
				break
			point = _random_point_in_cover_zone(chosen_zone)
	return point


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


## Prefers candidates on retreat_dir's own "correct" side, but - unlike a
## hard exclusion - only pays for that preference up to
## RETREAT_DIRECTION_MAX_EXTRA_M past the nearest candidate overall; beyond
## that, falls back to the full set rather than forcing an unreasonable
## detour toward cover that happens to sit on the "wrong" side but poses no
## actual known risk. See RETREAT_DIRECTION_MAX_EXTRA_M's own doc comment.
## Called AFTER _exclude_dangerous, so a "wrong side" candidate this
## returns is still guaranteed non-dangerous, never merely undirected.
##
## Filters candidate-by-candidate against the same budget, not just "is
## there at least one acceptable compliant option" — a genuinely close
## compliant candidate doesn't excuse also keeping some OTHER compliant
## candidate that's still wildly farther out. Without this, a compliant set
## containing both a 638m option and a 2400m+ one (the diagnosed case: both
## technically on the correct side, nothing else nearby is) left the
## eventual weighted-random pick a real chance of the 2400m+ one anyway —
## direction-compliant, but no less an unreasonable walk for a routine hit.
##
## A real, reported failure mode this used to allow: budget was always
## measured from `nearest_overall` — the single closest candidate in ANY
## direction — so whenever the closest cover zone of all happened to sit
## on the WRONG side (common; cover isn't laid out with retreat direction
## in mind), that nearby wrong-side point could set an artificially tight
## budget that then EXCLUDED a real, perfectly reachable correct-side
## option for merely being farther than "wrong-side blip + 500m," while
## RETREAT_DIRECTION_TOLERANCE's small forward allowance let that same
## nearby wrong-side point win outright. Confirmed directly at the
## mortar's own actual map deployment point: ordering a retreat sent it
## walking toward the enemy first (to a cover zone ~90-115m forward) for
## its whole initial "go to cover" leg, before ever starting the real
## retreat dash. Now budgeted separately per pass: the strict (correct-
## side, no tolerance) pass measures its own budget from the nearest
## candidate that's ALREADY on the correct side, not from whatever's
## nearest overall — a real correct-side option no longer gets starved by
## an unrelated nearby wrong-side one. This still protects against the
## originally-diagnosed 638m/2400m case (both correct-side, nothing
## closer): the budget is nearest-COMPLIANT + 500m, so a compliant option
## far past the nearest compliant one is excluded exactly as before.
##
## A SECOND real, reported failure mode, caught only once real battle
## geometry (not just a hand-built scenario) exercised this: when NOTHING
## at all qualifies on the correct side — not even loosely, within
## RETREAT_DIRECTION_TOLERANCE — this used to give up on direction
## ENTIRELY and hand back every remaining candidate completely
## unranked by how wrong-direction each one actually was. A real repro
## against a live battle found exactly this: `_prefer_clear_path` had
## already stripped every correct-side option (a building blocked the
## straight line to each one), leaving only two candidates roughly 1100m
## due EAST — and this function, finding neither one within the small
## 100m tolerance, shrugged and returned both with no preference between
## them, leaving whichever one happened to win a LATER, direction-blind
## tie-break (nearest-to-resupply-corridor) to decide — sending the
## mortar ~950m further toward the enemy than the OTHER candidate in the
## very same returned set would have. "No good option exists" is real,
## but it never justifies being indifferent between two bad options when
## one is closer to correct than the other — the exact same "prefer, but
## budget the detour" logic the strict pass already applies to distance,
## applied here to DIRECTIONAL wrongness instead: find whichever
## candidate is least wrong-direction, then keep anything within
## RETREAT_DIRECTION_MAX_EXTRA_M of that candidate's own wrongness ties
## it, but a badly-wrong outlier riding along in the same unfiltered set
## no longer can. Subsumes the small tolerance check the same way — a
## candidate within the ordinary tolerance is automatically "least wrong"
## already, so there's no separate mechanism to keep in sync.
static func _prefer_retreat_direction(candidates: Array[Dictionary], from: Vector2, retreat_dir: float) -> Array[Dictionary]:
	if retreat_dir == 0.0 or candidates.is_empty():
		return candidates

	var nearest_compliant: float = INF
	for c in candidates:
		if (c.zone.center.x - from.x) * retreat_dir >= 0.0:
			nearest_compliant = min(nearest_compliant, from.distance_to(c.zone.center))
	if nearest_compliant < INF:
		var strict_budget: float = nearest_compliant + RETREAT_DIRECTION_MAX_EXTRA_M * PIXELS_PER_METER
		var strict: Array[Dictionary] = []
		for c in candidates:
			var dist: float = from.distance_to(c.zone.center)
			if dist <= strict_budget and (c.zone.center.x - from.x) * retreat_dir >= 0.0:
				strict.append(c)
		if not strict.is_empty():
			return strict

	# Nothing at all qualifies on the correct side — prefer whichever
	# candidate is LEAST wrong-direction (smallest distance the "wrong"
	# way), budgeted the same way the strict pass budgets distance, so an
	# outlier far worse than the least-wrong option can't ride along in
	# the returned set just because some OTHER downstream tie-break might
	# otherwise pick it.
	var least_wrong: float = INF
	for c in candidates:
		var wrongness: float = (from.x - c.zone.center.x) * retreat_dir # positive = wrong-direction distance
		least_wrong = min(least_wrong, wrongness)
	var wrongness_budget: float = least_wrong + RETREAT_DIRECTION_MAX_EXTRA_M * PIXELS_PER_METER
	var least_wrong_set: Array[Dictionary] = []
	for c in candidates:
		var wrongness: float = (from.x - c.zone.center.x) * retreat_dir
		if wrongness <= wrongness_budget:
			least_wrong_set.append(c)
	return least_wrong_set if not least_wrong_set.is_empty() else candidates


## Same "prefer, don't force an unreasonable detour for" pattern as
## _prefer_retreat_direction, applied to avoid_buildings' OTHER exclusion —
## a candidate whose straight-line path from `from` happens to cross some
## building. That's a real, previously-reported failure mode: a mortar
## deployed inside/near a hamlet had EVERY nearby patch of cover blocked by
## this check purely because the straight line to each one grazed some
## building along the way, forcing an ordinary hit-triggered retreat out
## to whichever distant cluster of trees happened to have a fully clear
## line — several kilometers, not the couple hundred meters actually
## available with a short real-world detour around whatever's in the way.
## The zone-IS-a-building exclusion itself (avoid_buildings' other half,
## in each caller's own candidate-building loop) stays a hard rule — a
## mortar crew genuinely doesn't clear and occupy a structure the way a
## squad might; only the ROUTING assumption here is soft.
##
## Deliberately called AFTER _prefer_retreat_direction in every caller, not
## before — a real, previously-reported (and previously-MISSED) failure
## mode: this function's own budget is measured from `nearest_overall`,
## the closest candidate in ANY direction, exactly the same "wrong-side
## blip sets an artificially tight budget" trap _prefer_retreat_direction
## itself used to have (see that function's own doc comment for the
## original, already-fixed instance of this exact pattern). Running this
## BEFORE direction preference let a nearby WRONG-side candidate's budget
## silently exclude a real, reachable correct-side option for merely
## being farther than "wrong-side blip + 500m" — before direction
## preference ever got a chance to weigh in at all. Confirmed directly: a
## real battle had this strip every correct-side cover option down to two
## candidates roughly 1100m due EAST, sending a general-retreat mortar
## walking hundreds of meters further toward the enemy than necessary.
## Running direction preference FIRST means this function's own budget is
## computed from an already direction-appropriate candidate set, so a
## wrong-side blip can never contaminate it — and if every direction-
## correct candidate still turns out to be building-blocked, falling back
## to a blocked-but-correct-side candidate (this function's own existing
## "give up, return everything" fallback) is a real but minor routing
## inconvenience (an actual detour around a building), never a step
## toward the enemy the way running this first could produce.
static func _prefer_clear_path(candidates: Array[Dictionary], from: Vector2, avoid_buildings: bool) -> Array[Dictionary]:
	if not avoid_buildings or candidates.is_empty():
		return candidates
	var nearest_overall: float = INF
	for c in candidates:
		nearest_overall = min(nearest_overall, from.distance_to(c.zone.center))
	var budget: float = nearest_overall + RETREAT_DIRECTION_MAX_EXTRA_M * PIXELS_PER_METER
	var clear: Array[Dictionary] = []
	for c in candidates:
		var dist: float = from.distance_to(c.zone.center)
		if dist <= budget and not path_crosses_building(from, c.zone.center):
			clear.append(c)
	return clear if not clear.is_empty() else candidates


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
		candidates.append({"zone": zone, "dist_from_self": from.distance_to(zone.center)})
	if candidates.is_empty():
		return from

	candidates = _exclude_dangerous(candidates, known_enemy_positions)
	candidates = _prefer_retreat_direction(candidates, from, retreat_dir)
	candidates = _prefer_clear_path(candidates, from, avoid_buildings)
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


## A cover point picked with an eye toward the resupply corridor, not just
## "safe and X-directionally retreat-ward" — a real, previously-reported
## failure mode: nearest_cover_point's own `retreat_dir` filter only ever
## constrains the X-axis (never walk back TOWARD the enemy), leaving the
## Y-axis (north/south) completely free, so a mortar's own retreat could
## end up drifting far off to one side for no better reason than "that's
## where the nearest still-safe zone happened to be." A crew that isn't
## fighting to hold ground right now (it's retreating) but may still need
## resupply soon has a genuinely better direction to head: generally
## along the same line a resupply run would already be approaching on
## (see BattleManager._resupply_entry_point_for — real ground truth
## already computed the same way, not a guess), not off on an unrelated
## tangent. Same structure as safest_cover_point (hard DANGER_RADIUS
## exclusion, narrow to the nearest few candidates so this doesn't trek
## across the map for a marginal directional gain) with "farthest from
## known enemies" swapped for "closest to `reference_point`" as the
## secondary ranking. With no known enemies, behaves like
## nearest_cover_point, same as safest_cover_point.
##
## `retreat_dir` / `avoid_buildings` — see nearest_cover_point.
static func retreat_cover_point_toward(from: Vector2, reference_point: Vector2, known_enemy_positions: Array[Vector2], retreat_dir: float = 0.0, avoid_buildings: bool = false) -> Vector2:
	if known_enemy_positions.is_empty():
		return nearest_cover_point(from, retreat_dir, avoid_buildings)

	var candidates: Array[Dictionary] = []
	for zone in _all_cover_zones():
		if avoid_buildings and zone.type == TerrainType.BUILDING:
			continue
		candidates.append({"zone": zone, "dist_from_self": from.distance_to(zone.center)})
	if candidates.is_empty():
		return from

	candidates = _exclude_dangerous(candidates, known_enemy_positions)
	candidates = _prefer_retreat_direction(candidates, from, retreat_dir)
	candidates = _prefer_clear_path(candidates, from, avoid_buildings)
	return _random_point_in_cover_zone(_best_cover_zone_by_total_trip(candidates, reference_point).zone)


## Direct user correction, after a mortar was destroyed taking exactly
## this route: "the map edge is better than cover. Cover is simply a
## means to reaching the map edge... a safe retreat path existed. The
## mortar didn't take it." The OLD version here picked the 4 zones
## nearest to `from` FIRST, and only THEN preferred whichever of those
## happened to be closest to `reference_point` (the edge) — cover treated
## as competing with reaching the edge, not a means to it. Once the
## danger exclusion above has already thinned the pool (routine with this
## many known enemy positions scattered around), the 4 nearest-to-self
## zones can all land off to one side with no relation to the edge at
## all, and a zone genuinely on the way there — even one much farther
## from `from` right now — never even entered the shortlist to compete.
## Ranked by REAL total trip distance instead: self to the zone, then the
## zone on to the edge, so a longer first leg only wins when it actually
## shortens the whole journey. Split out from retreat_cover_point_toward
## as its own function purely so it can be tested directly against a
## synthetic candidate list — the real map's own sparse zone layout
## doesn't reliably reproduce the old bug's exact shape on demand.
## `candidates` entries need "zone" and "dist_from_self" (distance from
## the retreating unit's own current position) already set — the same
## shape retreat_cover_point_toward's own candidate list already has
## after the filters above.
static func _best_cover_zone_by_total_trip(candidates: Array[Dictionary], reference_point: Vector2) -> Dictionary:
	var scored: Array[Dictionary] = candidates.duplicate()
	for c in scored:
		c["total_trip"] = c.dist_from_self + c.zone.center.distance_to(reference_point)
	scored.sort_custom(func(a, b): return a.total_trip < b.total_trip)
	return scored[0]


# How far out (and in how many steps) to search for a concealed spot — see
# nearest_hidden_point. Three expanding rings, nearest checked first, so a
# mortar prefers a short hop to cover over a long trek if both work.
#
# Grounded on the same real displacement doctrine as COUNTER_BATTERY_
# BLAST_RADIUS's own doc comment (75-100m emergency, 25-30m planned) —
# every scoot this project models is the emergency case (a real known
# threat, already detected), so both sets stay within that cited band
# rather than the two being split across radically different distances
# the way an early version of this project had them (250-1000m,
# discovered to be 3-10x too far once real figures were actually
# researched — see the design doc's own entry). The routine set's
# smallest ring sits exactly at COUNTER_BATTERY_BLAST_RADIUS, preserving
# nearest_hidden_point's own "clears the blast radius by construction"
# guarantee for BOTH sets, not just the urgent one. The URGENT set (a
# crew that's actually taken counter-battery fire recently, been spotted,
# or has a threat closing — see Unit.evading_counter_battery and
# _decide_mortar_action's own tier-1 urgent branches) still searches
# somewhat farther and moves at MORTAR_RELOCATE_SPEED_URGENT — real
# additional danger buys real additional distance and speed, just not the
# order-of-magnitude gap the old numbers had.
const CONCEALMENT_SEARCH_RINGS_M: Array[float] = [75.0, 100.0, 130.0]
const CONCEALMENT_SEARCH_RINGS_URGENT_M: Array[float] = [100.0, 130.0, 160.0]
const CONCEALMENT_SEARCH_SAMPLES: int = 16

## Extra, farther rings _ring_search_hidden_point samples ONLY when it
## also has a sibling to avoid (bunch_avoid_positions non-empty) — added
## specifically so MORTAR_BUNCHING_AVOIDANCE_RADIUS's real, cited 300m
## separation target is actually reachable by at least some candidates,
## not permanently out of reach of every ring the routine 75-160m sets
## above sample. Without this, the continuous bunching score could never
## get anywhere close to its own full-credit distance, capping its real
## influence at under half strength regardless of how good a candidate
## was — the exact mechanical failure an earlier, abandoned attempt at
## 300m ran into (see that constant's own doc comment). Kept as a
## SEPARATE set rather than folded into the routine rings above:
## ordinary concealment-seeking (no sibling to avoid, or one already
## comfortably clear) has no reason to march this far just to hide from a
## threat — "a real crew doesn't want to march far just to hide" already
## established elsewhere in this file — these only ever get sampled when
## there's an actual bunching problem worth the extra distance to fix.
const CONCEALMENT_SEARCH_RINGS_BUNCHING_EXTRA_M: Array[float] = [200.0, 300.0]

# How far (at most) it's worth walking to reach an actual hill's reverse
# slope rather than settling for a closer, weaker spot — see
# _reverse_slope_candidate. Generous, since real cover (a whole hill
# blocking LOS, not a random point that merely tests clear right now) is
# worth a real walk.
const REVERSE_SLOPE_MAX_TRAVEL_M: float = 1500.0

## Real crews deliberately vary firing positions specifically to avoid
## being predictable — reoccupying the same handful of "good" hiding
## spots defeats the whole point of shooting and scooting, even if each
## individual move technically clears COUNTER_BATTERY_BLAST_RADIUS from
## wherever it just came from (a real, reported symptom: the mortar
## visibly pacing back and forth between the same 2-3 spots over an
## entire engagement, confirmed directly by logging real scoot
## destinations across several full battles). Reuses COUNTER_BATTERY_
## BLAST_RADIUS itself as the exclusion distance around each remembered
## position — the same real justification already established for why a
## position that close still counts as "not actually clear" applies just
## as well to a position the crew itself recently vacated, not just the
## one it's currently standing on. A short, ROLLING memory (oldest
## remembered position forgotten once a new one is added), not permanent
## avoidance: real predictability risk fades enough over an engagement
## that a genuinely excellent position is still worth reoccupying once
## it's no longer one of the last few used, and a fixed cap also avoids
## the relocation search eventually running out of valid candidates
## entirely on a map with only a few good hiding spots relative to a
## fixed threat layout — the exact case the diagnostic run to confirm
## this actually found.
##
## The remembered history is shared across every relocation reason
## (scoot, evade, conceal, ...), not scoot-specific — a mortar reacting
## to an immediate threat (evade/conceal) still shouldn't walk back onto
## its own recently-used ground either. That sharing means a single
## intervening evade/conceal move consumes one of the remembered slots,
## which measurably shortened the effective scoot-to-scoot memory in
## practice (confirmed directly: an evade between two scoots pushed a
## still-relevant scoot position out of the window two steps early,
## letting a later scoot land back within 33m of it). 5, not 3, gives
## real headroom against that without the added complexity of tracking
## per-intent histories separately — a judgment call, not independently
## cited, re-verified empirically after raising it (see this constant's
## own commit history / the design doc's own entry for the before/after
## comparison).
const MORTAR_RECENT_POSITION_MEMORY_COUNT: int = 5

## How close counts as "the same spot" for MORTAR_RECENT_POSITION_MEMORY_
## COUNT's own exclusion — used to reuse COUNTER_BATTERY_BLAST_RADIUS
## directly, back when both concepts operated at the same 150m scale. No
## longer sound once CONCEALMENT_SEARCH_RINGS_* were retuned to their own
## real-world-grounded short-hop distances (75-160m, per real mortar
## displacement doctrine) — reusing COUNTER_BATTERY_BLAST_RADIUS (also
## retuned, to 75m) meant a single remembered position's own exclusion
## disk was comparable in size to the ENTIRE reachable search area, and a
## small handful of them could blanket nearly all of it, confirmed
## directly: a real full-battle diagnostic found the mortar coming up
## with NO relocation at all for over a quarter of every tick it was
## actively compromised. A small fraction of the smallest routine ring
## keeps this doing its real job (don't immediately re-pick the exact
## spot just vacated) without also starving the search of room to work
## in at this much smaller scale.
const MORTAR_RECENT_POSITION_EXCLUSION_RADIUS: float = 20.0 * PIXELS_PER_METER

## A SECOND, separate, much stronger exclusion specifically for the
## single MOST RECENT relocation destination — not a wider version of
## MORTAR_RECENT_POSITION_EXCLUSION_RADIUS above, which stays small and
## shared across all MORTAR_RECENT_POSITION_MEMORY_COUNT remembered
## spots deliberately (widening THAT one starves the search — see its
## own doc comment). A real, reported bug found this still wasn't
## enough: a genuinely spotted mortar's "conceal" relocation was
## revisiting the same handful of points 50-100m apart repeatedly, well
## outside the 20m radius, sometimes reversing its own immediately-prior
## leg outright — the user's own framing: "you might move in different
## directions, but not reversals that take you right back to where you
## were." Root cause, traced directly: `nearest_cover_point` (the
## dominant relocation path whenever there are no known threats to route
## around — see BattleManager._mortar_relocation_plan's own doc comment)
## never received the mortar's own recent-position memory AT ALL — its
## `avoid_positions` parameter checks ZONE CONTAINMENT, not radius,
## which a bare remembered Vector2 essentially never satisfies, so an
## earlier version of this fix (`bunch_avoid_positions`) deliberately
## left that slot alone rather than pass something that wouldn't work
## there anyway. Reuses COUNTER_BATTERY_BLAST_RADIUS directly — the
## exact real distance this project already uses everywhere else for
## "close enough to the old spot to still matter" — applied ONLY to the
## single most-recent destination (not the whole rolling history), so
## the total excluded area stays small enough not to reproduce the
## exact starvation bug MORTAR_RECENT_POSITION_EXCLUSION_RADIUS's own
## history already found and fixed once.
const MORTAR_NO_REVERSAL_RADIUS: float = COUNTER_BATTERY_BLAST_RADIUS

## A genuinely different, complementary check from the position-based
## exclusion just above — the user's own suggestion, after tracing
## showed a position-radius check alone still missed real cases (a
## reversal that doesn't happen to land within MORTAR_NO_REVERSAL_
## RADIUS of any ONE specific remembered point, e.g. several small
## steps in one direction followed by a big step back the way they
## came). Directly targets the actual concept the user named: not
## proximity to a specific old spot, but literally undoing the crew's
## own most recent direction of travel. A new candidate whose direction
## from the mortar's current position has a NEGATIVE dot product against
## the direction of the immediately-prior completed leg (recent[-2] to
## recent[-1]) — i.e. any real backward component at all, not just a
## near-exact 180-degree reversal — gets this strong discouragement
## (the same two-stage "prefer exclusively, fall back only if nothing
## clears it" pattern as every other hard preference in this family of
## searches).
##
## Explicitly EXEMPTED whenever the crew has fired at least once since
## that prior leg (BattleManager._mortar_fired_since_relocation) — the
## user's own direct correction: "if the mortar moves, stops, fires,
## then moves in the opposite direction after firing, that is probably
## OK." A real fire mission between two relocations means the next move
## is a genuine, fresh shoot-and-scoot decision (survivability doesn't
## care which way the crew happened to arrive from), not indecisive
## backtracking — only a reversal with NO fire mission in between is the
## real, reported symptom (a spotted crew relocating repeatedly without
## ever actually getting a shot off in between).
const MORTAR_REVERSAL_DIRECTION_DOT_THRESHOLD: float = 0.0

## How far apart same-side mortars should try hard to stay from each
## other — FM 7-90 Ch.6's own real, cited figure: splitting a mortar
## platoon into separate firing positions "up to 300 meters apart...
## greatly decreases the enemy's chance of neutralizing them with
## countermortar fire." An EARLIER version of this constant reasoned this
## was the wrong scale — that 300m describes whole-SECTION separation,
## not individual-tube spacing, and that this project's own individual
## "enemy mortar" units (each its own tube/crew, not a multi-tube
## section) needed the smaller Ch.7 figure instead ("lateral dispersion
## between mortars equal to the bursting diameter of an HE round," ~52m
## using this project's own cited 82mm lethal-fragment radius). That
## reasoning had it backwards: this project's mortars each act as
## INDEPENDENT firing elements — capable of their own displacement,
## targeting, and survival, never needing centralized voice/fire control
## the way tubes sharing one physical position do — which is exactly the
## separate-SECTIONS scenario Ch.6 describes, not the shared-position
## scenario Ch.7 describes. The user's own original report ("bunched up,"
## implying visible clustering vulnerable to being wiped out together) is
## also about the hazard Ch.6 directly addresses (a countermortar mission
## neutralizing the whole position at once), not the narrower Ch.7 hazard
## (one HE round's fragmentation catching two adjacent tubes) — that
## narrower risk is real too and still worth guarding against absolutely,
## just at a much tighter distance (see MORTAR_BUNCHING_CRITICAL_RADIUS,
## unchanged at 26m, its own separate citation — the two constants
## aren't duplicates, they're a soft doctrinal target layered over a hard
## catastrophic-risk floor).
##
## An earlier attempt at 300m here was reverted after "measurably failing
## to change anything" in a full-battle diagnostic — but that failure was
## a MECHANICAL gap, not evidence the citation was wrong: a single
## relocation hop only ever covered CONCEALMENT_SEARCH_RINGS_*'s own
## 75-160m reach, so no continuous score ever got within striking
## distance of 300m's own full credit, permanently capping this factor's
## real-world influence at under half its intended strength regardless of
## how good a candidate actually was. Re-verified directly against the
## primary source (not just the earlier session's own paraphrase) before
## reinstating this: fixed properly this time by giving
## _ring_search_hidden_point extra, farther rings to sample specifically
## when a sibling needs avoiding (see CONCEALMENT_SEARCH_RINGS_BUNCHING_
## EXTRA_M) rather than quietly settling for a smaller, easier-to-satisfy
## number. Enemy mortar spawn spacing (CURRENT_MAP.enemy's own
## mortar_spread_min/max_y_m) was also widened to guarantee this
## separation from the very first tick, matching Ch.6's own framing —
## real commanders decide separate firing positions in advance, not
## something earned by accumulating small evasive hops under fire.
const MORTAR_BUNCHING_AVOIDANCE_RADIUS: float = 300.0 * PIXELS_PER_METER

## A real, reported regression found the moment the radius above was
## restored to its correct 300m citation: TWO OR MORE mortars each
## re-relocating to maximize distance from the OTHER's CURRENT (also
## constantly shifting) position, with no floor on how close is "close
## enough" to stop bothering, produced rapid, erratic short hops instead
## of one stable move — confirmed directly via a live trace: an enemy
## mortar re-relocating almost every tick, each leg just a few meters,
## chasing a sibling that was itself doing the exact same thing. At the
## old 52m target, this was invisible: nearly every reachable candidate
## already cleared it and scored the same full 1.0 credit, so the
## bunching term barely influenced which candidate won at all. At 300m,
## it became the dominant, most-varying term in the whole score, so a
## sibling's own ordinary movement (or simply which of many similar
## candidates the search's own weighted-random pick happened to draw)
## kept reshuffling which spot looked "best" — the mortar version of two
## people repeatedly side-stepping the same direction in a hallway.
##
## Gates _relocate_mortar's own non-urgent (not force_urgent, not
## reacting to a real threat) calls: once EVERY known sibling is already
## this far away, a fresh relocation isn't even attempted for that reason
## alone — no further improvement is worth the resulting instability.
## Deliberately smaller than MORTAR_BUNCHING_AVOIDANCE_RADIUS itself, not
## equal to it: real doctrine's own "up to 300 meters... greatly
## decreases the enemy's chance of neutralizing them" already frames 300m
## as sufficient, not a number to hover exactly at and re-litigate every
## tick as a sibling drifts a few meters either side of it. A genuinely
## URGENT relocation (spotted, a real threat closing, just took counter-
## battery fire) is untouched by this — survival always still outranks
## sibling separation, regardless of how well-dispersed the crew already
## is.
const MORTAR_BUNCHING_SATISFIED_RADIUS: float = 200.0 * PIXELS_PER_METER

## A THIRD real gap found once the continuous score factor above was
## verified against full, real, uncapped battles rather than short
## samples (see MORTAR_BUNCHING_AVOIDANCE_RADIUS's own doc comment for
## the first two): a purely continuous preference still isn't STRONG
## enough to reliably prevent near-total overlap in the specific
## degenerate case of several mortars pushed onto the same map edge —
## clamp_to_operating_area collapses many of a mortar's own ring samples
## onto nearly the same boundary line regardless of radius, so the
## away-from-threat scoring bonus can dominate a continuous bunching
## penalty that's paying a real but comparatively modest cost. Measured
## directly: 43% of 100 full real battles had mortars land within 15m of
## each other at some point, worst case 0.1m apart — not a rare tail
## case, and reproduced by tracing one directly (both mortars pinned to
## the same map edge, one already stationary firing, the other's own
## relocation search landing almost exactly on top of it anyway).
##
## Reuses MORTAR_BLAST_CASUALTY_RADIUS directly rather than inventing a
## third distance — a real, meaningful choice, not just convenient reuse:
## within the actual cited lethal-fragment radius, a single HE round has
## a real, roughly 50% chance (see CombatResolver.blast_casualty_chance's
## own calibration) of catching BOTH mortars, not merely "somewhat closer
## than ideal." Tracked as its own two-stage hard preference — same
## pattern as this function's own floor_ok — specifically because THIS
## degree of closeness is different in kind, not just degree, from the
## softer 300m preference above: never choose a candidate this close if
## literally any alternative clears it, falling back only when nothing
## does, matching this project's own established "movement must never be
## starved to zero" principle.
const MORTAR_BUNCHING_CRITICAL_RADIUS: float = MORTAR_BLAST_CASUALTY_RADIUS

## Shared by nearest_hidden_point and nearest_cover_point's own bunching
## terms — one function so a mortar's two different relocation search
## paths (the ring search and the cover-zone search) can never drift out
## of sync with each other. Direct user correction after live bunching
## recurred despite the whole mechanism already existing: "you had it
## prevented, but that caused other problems, so you had the code merely
## discourage it... insufficient anti-bunching... need a happy medium."
## Traced directly: the original LINEAR ramp gave a candidate at HALF the
## avoidance radius only a 2x penalty — trivially outweighed by
## `nearest_hidden_point`'s own `hidden` bonus alone (3.0x), let alone
## stacked with its threat-facing bonus (up to 1.5x) on top. Two mortars
## independently gravitating toward the same good concealment spot could
## then win on hidden-ness despite sitting well inside the avoidance
## radius — confirmed directly with a live 20-trial full-battle
## measurement: under the linear curve, 6/20 real battles had enemy
## mortars land within 15m of each other at some point (several under
## 2m — effectively on top of one another), 9/20 within the avoidance
## radius itself. SQUARED roughly quadruples the penalty at that same
## half-radius point (0.25x instead of 0.5x), enough to reliably
## outweigh the concealment bonus alone. Still a genuine CONTINUOUS
## factor, never a hard exclusion (the 0.05 floor is unchanged, so a
## genuinely cornered mortar can still move) — a steeper, harder-to-
## outbid curve, not a new hard gate.
static func mortar_bunch_score_factor(nearest_sibling_dist: float) -> float:
	return clampf(pow(nearest_sibling_dist / MORTAR_BUNCHING_AVOIDANCE_RADIUS, 2.0), 0.05, 1.0)


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


## How much farther than the ring search's own nearest hidden candidate
## it's worth walking for the reverse slope's more DURABLE kind of masking
## (a whole hill blocking LOS, which stays valid even if a threat shifts,
## vs. a point that merely tests clear against today's exact positions —
## see _reverse_slope_candidate's own doc comment for that reasoning). A
## real, previously-reported failure mode: the hill candidate used to win
## UNCONDITIONALLY whenever it found anything at all, with no comparison
## against the ring search's own result — on the diagnosed map, this sent
## an ordinary "spotted, no shot" concealment move over 1100m to a specific
## hill, EVERY time, when a fully-hidden spot 250m away (found by the ring
## search alone) would have done the exact same job. A judgment call, not
## cited — enough to prefer the hill's durability for a modest premium
## without paying for a multi-hundred-meter detour past equally-valid,
## much closer cover.
const CONCEALMENT_HILL_MAX_EXTRA_M: float = 300.0

## `home_position`/`home_leash`: an optional hard cap on how far a
## candidate may sit from a fixed reference point (used for the player
## mortar's own home-range leash — see MORTAR_HUNT_MAX_RANGE_FROM_HOME's
## own doc comment). Applied INSIDE the search, not just checked against
## the final result afterward, so a search that naturally gravitates away
## from threats (the reverse-slope candidate especially, anchored to
## threat bearing rather than the unit's own position) can't repeatedly
## propose a candidate beyond the leash and have the whole attempt fail.
##
## `min_distance_from_home`: the OPPOSITE constraint — a floor, not a
## ceiling, on distance from `home_position`. See BattleManager._mortar_
## max_distance_from_home's own doc comment for why this exists: an
## evade/conceal reaction to some OTHER, unrelated threat has no memory of
## how much distance a previous scoot already put between the mortar and
## the position that got it compromised in the first place, and its own
## search — being just as purely reactive to whatever's nearest right now
## as scoot's — can easily send the mortar right back toward exactly that
## danger. Confirmed directly this way, not theorized: tracing every real
## search call during an actual oscillating battle showed the reverse-
## slope candidate essentially always losing (rejected as "too far" once
## the mortar has moved on), and the ring search — which has NO notion of
## which direction is actually away from where the danger started —
## responsible for the wandering.
##
## All four of these left at their defaults (INF/INF/0.0) preserves every
## existing caller's behavior exactly.
##
## `firing_point`: the real-world reason a mortar relocates in the first
## place after firing — not merely "hidden from known threats," but
## specifically clear of the exact coordinate a counter-battery mission
## will actually be aimed at (see BattleManager._mortar_relocation_plan's
## own doc comment for how this is resolved, and COUNTER_BATTERY_BLAST_
## RADIUS for why that's the real distance that matters — the same one
## _mortar_should_relocate_for_safety's own trigger already uses to decide
## when a crew has moved far ENOUGH). Left at its default (Vector2.INF)
## preserves every existing caller's behavior exactly; only a relocation
## reacting to a crew's own still-live firing signature passes a real
## value.
static func nearest_hidden_point(from: Vector2, threat_positions: Array[Vector2], avoid_buildings: bool = false, urgent: bool = false, avoid_positions: Array[Vector2] = [], home_position: Vector2 = Vector2.INF, home_leash: float = INF, min_distance_from_home: float = 0.0, bunch_avoid_positions: Array[Vector2] = [], no_reversal_positions: Array[Vector2] = [], travel_direction: Vector2 = Vector2.ZERO, firing_point: Vector2 = Vector2.INF, danger_range: float = MORTAR_CREW_OVERRUN_DANGER_RANGE) -> Vector2:
	if threat_positions.is_empty():
		return from

	var hill_spot := _reverse_slope_candidate(from, threat_positions, avoid_buildings, avoid_positions, home_position, home_leash, min_distance_from_home, bunch_avoid_positions, no_reversal_positions, firing_point)
	var ring_spot := _ring_search_hidden_point(from, threat_positions, avoid_buildings, urgent, avoid_positions, home_position, home_leash, min_distance_from_home, bunch_avoid_positions, no_reversal_positions, travel_direction, firing_point, danger_range)

	if hill_spot == from:
		return ring_spot
	if ring_spot == from:
		return hill_spot
	if from.distance_to(hill_spot) > from.distance_to(ring_spot) + CONCEALMENT_HILL_MAX_EXTRA_M * PIXELS_PER_METER:
		return ring_spot
	return hill_spot


## The ring-search half of nearest_hidden_point, split out so it can be
## compared against the reverse-slope candidate above instead of only ever
## running when the hill search finds nothing at all.
##
## A real, explicit correction to how this used to work: MOVEMENT is the
## actual requirement here, not concealment. Especially when the enemy
## can't currently see this unit at all (the ordinary shoot-and-scoot
## case — the whole trigger is "the enemy knows my last position," not
## "I've been spotted"), the crew doesn't need to end up somewhere hidden
## to be safer than where it started; it needs to have genuinely MOVED.
## Real LOS-blocking concealment (a wall, a fold in the ground, a
## treeline) is a real, meaningful factor IN FAVOR of one candidate over
## another, not a pass/fail gate — and a previously-reported, empirically
## confirmed consequence of treating it as a hard gate: real concealment
## simply doesn't always exist within CONCEALMENT_SEARCH_RINGS_*'s own
## short-hop reach (75-160m, per real mortar displacement doctrine), and
## a full battle log found the mortar with NO relocation at all, fully
## exposed, for a third of every tick it was actively compromised.
##
## So every candidate that clears the real HARD constraints below (stays
## on the map, doesn't walk through a building, respects the home leash/
## progress floor, isn't a position just vacated) is a genuinely valid
## answer, SCORED rather than filtered by three real, softer preferences:
## real concealment, real standoff from known threats (MORTAR_CREW_
## OVERRUN_DANGER_RANGE), and facing away from the threat picture rather
## than toward it. The final choice is a weighted-random pick among the
## best-scoring candidates, not a deterministic "the one true best spot"
## — a crew that reliably ran to the single most-hidden location every
## time would itself be a predictable pattern, exactly the thing shoot-
## and-scoot doctrine exists to avoid.
static func _ring_search_hidden_point(from: Vector2, threat_positions: Array[Vector2], avoid_buildings: bool, urgent: bool, avoid_positions: Array[Vector2] = [], home_position: Vector2 = Vector2.INF, home_leash: float = INF, min_distance_from_home: float = 0.0, bunch_avoid_positions: Array[Vector2] = [], no_reversal_positions: Array[Vector2] = [], travel_direction: Vector2 = Vector2.ZERO, firing_point: Vector2 = Vector2.INF, danger_range: float = MORTAR_CREW_OVERRUN_DANGER_RANGE) -> Vector2:
	var rings: Array[float] = CONCEALMENT_SEARCH_RINGS_URGENT_M if urgent else CONCEALMENT_SEARCH_RINGS_M
	# See CONCEALMENT_SEARCH_RINGS_BUNCHING_EXTRA_M's own doc comment —
	# only sampled when there's an actual sibling to create real
	# separation from, so ordinary concealment-seeking never marches
	# farther than it needs to just because another mortar exists.
	if not bunch_avoid_positions.is_empty():
		rings = rings + CONCEALMENT_SEARCH_RINGS_BUNCHING_EXTRA_M

	var avg_threat := Vector2.ZERO
	for t in threat_positions:
		avg_threat += t
	avg_threat /= max(threat_positions.size(), 1)
	var away_from_threat: Vector2 = from - avg_threat
	var away_theta: float = away_from_threat.angle() if away_from_threat.length() > 1.0 else 0.0

	var candidates: Array[Dictionary] = []
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
			# Hard constraints — genuinely required, not preferences: can't
			# walk through a building, can't abandon supporting distance
			# of the position this crew exists to help defend (home_leash
			# — a real tactical limit, not just a preference).
			if avoid_buildings and (is_building_at(candidate) or path_crosses_building(from, candidate)):
				continue
			if home_position.distance_to(candidate) > home_leash:
				continue

			# Soft preferences from here — a real weight in favor, never
			# an absolute requirement, EXCEPT min_distance_from_home
			# (tracked but not filtered out here — see the two-stage
			# selection below). A crucial real gap this closes: at
			# CONCEALMENT_SEARCH_RINGS_*'s short-hop scale, a long-running
			# danger episode can ratchet min_distance_from_home (see its
			# own doc comment — a high-water mark, not a ceiling) up
			# until it leaves almost no room between the floor and
			# home_leash for a fresh ring to land in at all — confirmed
			# via a disposable diagnostic (instrumented rejection counts
			# by cause) to be, by a wide margin, the dominant reason the
			# ring search itself ever came up with literally zero
			# candidates (1225 such ticks across a 20-trial run; zero
			# after switching it from a hard gate to the two-stage
			# preferred-but-not-absolute treatment below). Undoing real
			# progress is a real, meaningful cost — worth excluding
			# whenever a real alternative exists at all, matching this
			# project's own prior, deliberately-tested guarantee (see
			# test_relocation_never_undoes_progress_from_a_different_
			# threat) — but "didn't gain distance from home" must never
			# outrank "didn't move at all" the way an unconditional hard
			# gate did, per the user's own explicit standard for this
			# whole function ("it does need to be moving"). A recently-
			# vacated position is a real but genuinely softer cost (about
			# unpredictability, not safety) — a straight score penalty is
			# enough there.
			var score := 1.0
			var floor_ok: bool = home_position.distance_to(candidate) >= min_distance_from_home
			# See MORTAR_BUNCHING_AVOIDANCE_RADIUS's own doc comment (a real,
			# cited minimum separation, not a guess) — a CONTINUOUS score
			# factor, not a two-stage hard/soft split like floor_ok above.
			# An earlier version of this used the same two-stage pattern
			# (exclude exclusively whenever any fully-clear candidate
			# exists) and it measurably failed in exactly the case that
			# matters most: several mortars all pushed toward the SAME map
			# edge (or all reacting to the same single threat) compresses
			# every mortar's own escape directions down to nearly one
			# dimension, so NONE of a mortar's own candidates fully clear
			# the radius from an already-nearby sibling — and the two-
			# stage version's fallback ("nothing qualifies, so ignore
			# bunching entirely") threw away the real, continuous
			# difference between a candidate that's merely somewhat too
			# close and one that's almost on top of a sibling, letting the
			# worse of the two win just as often as the better one. This
			# scales smoothly instead: full credit once a candidate clears
			# the radius, decaying (never to literal zero, so a genuinely
			# cornered mortar can still move) the closer it is to a
			# sibling — always still preferring more separation over less,
			# with no cliff where the preference just vanishes.
			var nearest_sibling_dist := INF
			for p in bunch_avoid_positions:
				nearest_sibling_dist = min(nearest_sibling_dist, candidate.distance_to(p))
			if nearest_sibling_dist < INF:
				# See mortar_bunch_score_factor's own doc comment for why
				# this is squared, not linear.
				score *= mortar_bunch_score_factor(nearest_sibling_dist)
			# A SECOND real gap found once the continuous factor above was
			# verified against full real battles, not just short samples:
			# when several mortars are all pushed toward the same map
			# edge, clamp_to_operating_area collapses many of their own
			# ring samples onto nearly the same boundary line regardless
			# of ring radius, so the away-from-threat bonus below can
			# dominate a continuous factor that's paying a real but
			# comparatively small penalty — measured directly landing
			# mortars within literally 0.1-2m of each other in 43% of
			# real battles, not a rare tail case. Within
			# MORTAR_BUNCHING_CRITICAL_RADIUS specifically (the real,
			# cited lethal-fragment radius, MORTAR_BLAST_CASUALTY_RADIUS
			# — inside this, a single HE round has a real, roughly
			# coin-flip chance of catching both mortars, not just
			# "somewhat less than ideal separation"), tracked as its own
			# two-stage hard preference, same pattern as floor_ok: never
			# choose a candidate this close if literally any alternative
			# clears it, only falling back when NOTHING does.
			var critically_close: bool = nearest_sibling_dist < MORTAR_BUNCHING_CRITICAL_RADIUS
			var too_close_to_recent := false
			for p in avoid_positions:
				if candidate.distance_to(p) < MORTAR_RECENT_POSITION_EXCLUSION_RADIUS:
					too_close_to_recent = true
					break
			if too_close_to_recent:
				score *= 0.3
			var hidden := true
			var min_threat_dist := INF
			for threat in threat_positions:
				if has_direct_los(candidate, threat):
					hidden = false
				min_threat_dist = min(min_threat_dist, candidate.distance_to(threat))
			if hidden:
				score *= 3.0 # real LOS-blocking concealment — a strong preference, not a requirement
			# A real, reported bug, traced directly from a live battle's own
			# mortar debug history: a single "evade" relocation walked the
			# crew 58 tactical seconds STRAIGHT TOWARD a known enemy squad
			# cluster, getting closer every tick along the way, because this
			# used to be nothing but the plain 0.5x score penalty below —
			# trivially outweighed by the 3x concealment bonus just above and
			# the up-to-1.5x threat-facing bonus just below (a hidden,
			# threat-facing candidate scores 4.5x; a merely-safer, exposed
			# one scores at most 1.5x). Promoted to the same two-stage hard
			# preference already used for floor_ok/critically_close/
			# is_reversal/reverses_direction: prefer a candidate that clears
			# `danger_range` exclusively whenever at least one exists, only
			# falling back to a closer one when every single candidate this
			# pass found is that close. Checked right after firing_point (the
			# one thing allowed to outrank it — a live counter-battery threat
			# at the exact firing coordinate) and ahead of every other
			# preference below: standing off from a known threat's own
			# engagement envelope matters more than home-leash progress,
			# sibling bunching, or reversal avoidance. The plain score
			# penalty stays too, as a tie-breaker within whichever group
			# (clear or not) actually gets used.
			#
			# `danger_range` is a caller-supplied parameter, not hardcoded to
			# MORTAR_CREW_OVERRUN_DANGER_RANGE, because this search is shared
			# by callers with genuinely different danger scales — a real,
			# second bug found the same day this fix first landed: the drone
			# team's own evasion search (_update_drone_team_evasion) routes
			# through this exact function, and 750m (right for "close enough
			# to physically overrun a mortar crew") is far tighter than the
			# 1200m the drone team's own trigger (DRONE_TEAM_EVASION_RANGE)
			# already uses — a destination well outside 750m of a known
			# enemy squad could still read as "walking toward it" at the
			# drone team's own relevant scale, exactly the user's report
			# ("seeing enemy squads in front of it should cause it to
			# reconsider"). Each caller now passes its own scale; the default
			# preserves the mortar's own existing behavior unchanged.
			var too_close_to_known_threat: bool = min_threat_dist < danger_range
			if too_close_to_known_threat:
				score *= 0.5 # still a valid move, just a weaker one this close to a known threat
			# Facing away from the threat picture is worth up to 1.5x;
			# facing directly toward it is worth as little as 0.5x — a
			# real, strong bias, not an absolute exclusion (see this
			# function's own doc comment on why toward-threat still has
			# to remain possible when it's genuinely the best answer).
			var angle_diff: float = absf(wrapf(theta - away_theta, -PI, PI))
			score *= 1.0 + 0.5 * cos(angle_diff)
			# See MORTAR_NO_REVERSAL_RADIUS's own doc comment — a
			# genuinely stronger, HARD (two-stage prefer/fallback, not a
			# score multiplier) exclusion than the ordinary recent-
			# position penalty above: that one only ever costs a
			# candidate a 0.3x score penalty (real, but easily
			# outweighed by concealment/threat-facing bonuses), which
			# measurably wasn't enough to stop a spotted mortar from
			# reversing its own immediately-prior leg outright. Checked
			# against the WHOLE remembered history, not just the single
			# most-recent entry — a real, measured gap found once this
			# went from single-entry to full-history in nearest_cover_
			# point but NOT here: a live trace showed this project's own
			# enemy mortars routing through THIS ring search, not that
			# other function, essentially every time (`threat_positions`
			# is very rarely actually empty once real contact is made),
			# so protecting only one entry here left the exact reported
			# bug almost entirely unaddressed. Safe from the historical
			# starvation failure mode a wider MORTAR_RECENT_POSITION_
			# EXCLUSION_RADIUS caused (see that constant's own doc
			# comment) because this is the same "prefer exclusively,
			# fall back to the full set if NOTHING clears it" two-stage
			# pattern already used for floor_ok/critically_close above —
			# unlike a hard, no-fallback filter, this can never actually
			# reduce the candidate pool to zero.
			var is_reversal: bool = false
			for p in no_reversal_positions:
				if candidate.distance_to(p) < MORTAR_NO_REVERSAL_RADIUS:
					is_reversal = true
					break
			# See MORTAR_REVERSAL_DIRECTION_DOT_THRESHOLD's own doc
			# comment — a genuinely different, complementary check: not
			# proximity to a specific old spot, but whether THIS
			# candidate's own direction from `from` undoes the crew's
			# most recent direction of travel outright.
			var reverses_direction: bool = travel_direction != Vector2.ZERO and (candidate - from).normalized().dot(travel_direction) < MORTAR_REVERSAL_DIRECTION_DOT_THRESHOLD
			# See nearest_hidden_point's own doc comment on `firing_point` —
			# the actual coordinate a counter-battery mission will be aimed
			# at, not just "somewhere hidden from known threats." Checked
			# first, ahead of every other two-stage preference below: per
			# the user's own direct framing, this is the TOP priority of a
			# post-fire relocation, only ever giving way when truly nothing
			# clears it (the map edge, a boxed-in position) or to a higher-
			# priority tier entirely (a closing enemy squad, handled well
			# above this search by the decision ladder itself).
			var too_close_to_firing_point: bool = firing_point != Vector2.INF and candidate.distance_to(firing_point) < COUNTER_BATTERY_BLAST_RADIUS
			candidates.append({"point": candidate, "score": score, "floor_ok": floor_ok, "critically_close": critically_close, "is_reversal": is_reversal, "reverses_direction": reverses_direction, "too_close_to_firing_point": too_close_to_firing_point, "too_close_to_known_threat": too_close_to_known_threat})

	if candidates.is_empty():
		return from

	# See `firing_point`'s own doc comment just above — checked first, ahead
	# of every other preference, so it always wins when any real
	# alternative clears it.
	var clear_of_firing_point: Array[Dictionary] = candidates.filter(func(c): return not c.too_close_to_firing_point)
	if not clear_of_firing_point.is_empty():
		candidates = clear_of_firing_point

	# See too_close_to_known_threat's own doc comment above — the real fix
	# for a reported live bug (an evade walk that only got closer to a known
	# enemy squad cluster). Checked second, right after firing_point, ahead
	# of every preference below.
	var clear_of_known_threat: Array[Dictionary] = candidates.filter(func(c): return not c.too_close_to_known_threat)
	if not clear_of_known_threat.is_empty():
		candidates = clear_of_known_threat

	# Prefer floor-respecting candidates exclusively whenever at least one
	# exists — only fall back to a floor-violating candidate when every
	# single candidate this pass found violates it, i.e. genuinely no
	# other option. See this loop's own doc comment above.
	var floor_respecting: Array[Dictionary] = candidates.filter(func(c): return c.floor_ok)
	if not floor_respecting.is_empty():
		candidates = floor_respecting

	# Same pattern again for the tight bunching-critical zone (see
	# MORTAR_BUNCHING_CRITICAL_RADIUS's own doc comment) — applied AFTER
	# the floor filter above, so a candidate that both respects the floor
	# AND clears the critical radius always wins when one exists.
	var not_critically_close: Array[Dictionary] = candidates.filter(func(c): return not c.critically_close)
	if not not_critically_close.is_empty():
		candidates = not_critically_close

	# Same pattern a third time, for MORTAR_NO_REVERSAL_RADIUS — applied
	# last, after the floor and bunching filters, so a candidate that
	# satisfies all three always wins when one exists.
	var not_a_reversal: Array[Dictionary] = candidates.filter(func(c): return not c.is_reversal)
	if not not_a_reversal.is_empty():
		candidates = not_a_reversal

	# Same pattern a fourth time, for MORTAR_REVERSAL_DIRECTION_DOT_
	# THRESHOLD — a genuinely different axis than the position-based
	# check just above (direction of travel, not proximity to a specific
	# old point), applied last so a candidate satisfying every other
	# preference too always wins when one exists.
	var not_direction_reversal: Array[Dictionary] = candidates.filter(func(c): return not c.reverses_direction)
	if not not_direction_reversal.is_empty():
		candidates = not_direction_reversal

	candidates.sort_custom(func(a, b): return a.score > b.score)
	var pool_size: int = min(5, candidates.size())
	var pool := candidates.slice(0, pool_size)
	var total_weight := 0.0
	for c in pool:
		total_weight += c.score
	var roll: float = randf() * total_weight
	var cumulative := 0.0
	for c in pool:
		cumulative += c.score
		if roll <= cumulative:
			return c.point
	return pool[pool.size() - 1].point


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
static func _reverse_slope_candidate(from: Vector2, threat_positions: Array[Vector2], avoid_buildings: bool, avoid_positions: Array[Vector2] = [], home_position: Vector2 = Vector2.INF, home_leash: float = INF, min_distance_from_home: float = 0.0, bunch_avoid_positions: Array[Vector2] = [], no_reversal_positions: Array[Vector2] = [], firing_point: Vector2 = Vector2.INF) -> Vector2:
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
		# The check above is only ever an approximation of this one (`from`
		# stands in for "the firing point" when the real coordinate isn't
		# known) — when it IS known, the real coordinate is what a counter-
		# battery mission is actually aimed at, not wherever the crew
		# happens to be standing when this search runs.
		if firing_point != Vector2.INF and candidate.distance_to(firing_point) < COUNTER_BATTERY_BLAST_RADIUS:
			continue
		if home_position.distance_to(candidate) > home_leash:
			continue # beyond the leash -- anchored to threat bearing alone, this candidate has no notion of home at all
		if home_position.distance_to(candidate) < min_distance_from_home:
			continue # would undo real progress already made escaping -- see min_distance_from_home's own doc comment
		# This candidate is anchored to the hill/threat-bearing geometry
		# alone, not to `from` — for an unchanged threat picture it's the
		# SAME point every time, which is exactly what let a mortar
		# oscillate right back onto its own last couple of positions (see
		# MORTAR_RECENT_POSITION_MEMORY_COUNT). A hill candidate rejected
		# this way still correctly falls through to the ring search below.
		var too_close_to_recent := false
		for p in avoid_positions:
			if candidate.distance_to(p) < MORTAR_RECENT_POSITION_EXCLUSION_RADIUS:
				too_close_to_recent = true
				break
		if too_close_to_recent:
			continue
		# See MORTAR_NO_REVERSAL_RADIUS's own doc comment — a genuinely
		# stronger version of the same check just above: this candidate
		# is anchored to fixed hill geometry, not to `from`, so for an
		# unchanged threat picture it's the literal SAME point every
		# time regardless of how far the mortar has since moved — exactly
		# the mechanism that let a spotted mortar reverse right back onto
		# a hill it had already used a few relocations ago, well outside
		# the smaller 20m radius just above.
		var is_reversal := false
		for p in no_reversal_positions:
			if candidate.distance_to(p) < MORTAR_NO_REVERSAL_RADIUS:
				is_reversal = true
				break
		if is_reversal:
			continue
		# See MORTAR_BUNCHING_AVOIDANCE_RADIUS's own doc comment — same
		# "falls through to the ring search" reasoning as the recent-
		# position check just above; this candidate is anchored to hill
		# geometry alone, with no room here for the ring search's own
		# two-stage prefer/fallback treatment of the same constraint.
		var too_close_to_sibling := false
		for p in bunch_avoid_positions:
			if candidate.distance_to(p) < MORTAR_BUNCHING_AVOIDANCE_RADIUS:
				too_close_to_sibling = true
				break
		if too_close_to_sibling:
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
	if not _terrain_grid_built:
		_build_terrain_grid()
	var segment_box: Rect2 = Rect2(from, to - from).abs()
	for rect in _building_rects:
		if not rect.intersects(segment_box, true):
			continue # far from the sightline — the four-edge crossing test below can't matter
		if rect.has_point(from) or rect.has_point(to):
			continue # firing from/into this building doesn't block itself
		if _line_crosses_rect(from, to, rect):
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
	if not _terrain_grid_built:
		_build_terrain_grid()
	var segment_box: Rect2 = Rect2(from, to - from).abs()
	for rect in _building_rects:
		if not rect.intersects(segment_box, true):
			continue
		if rect.has_point(from) or rect.has_point(to):
			continue
		if _line_crosses_rect(from, to, rect):
			return false
	return true


## SEEING THROUGH TREES. Trees never block a sightline outright (has_direct_los
## ignores them — a squad can still shoot at what it can see), but woods between
## an observer and a target make the target much harder to notice: real
## leaf-off deciduous woods (this game is set in late winter / early spring)
## are porous, not opaque. Modelled as Beer-Lambert-style attenuation over the
## metres of sightline that actually pass THROUGH canopy:
## tree_sight_transmission = exp(-depth_m / TREE_SIGHT_ATTENUATION_LENGTH_M).
## "Through canopy" respects elevation: a sample point counts only where the
## sightline itself is lower than that ground's height plus TREE_CANOPY_HEIGHT_M,
## so trees in a hollow between two hilltops never matter, and an observer on
## high ground looking down at the far edge of a wood sees over its front rows.
## The constants are judgment calls, not cited figures.
##
## Roll_spot multiplies its chance by this transmission (ground observers only:
## a drone looks down, not through). Keeping an already-seen target is
## deliberately much easier than first noticing it: it needs only
## TREE_SIGHT_KEEP_TRANSMISSION (about 200 m of woods at the default length),
## deterministic, and BattleManager adds TREE_SIGHT_LOSS_GRACE_S of continuous
## failure before it actually drops — so nothing flickers in and out of view on
## a random roll.
const TREE_CANOPY_HEIGHT_M: float = 15.0
const TREE_SIGHT_ATTENUATION_LENGTH_M: float = 80.0
const TREE_SIGHT_KEEP_TRANSMISSION: float = 0.08
const TREE_SIGHT_LOSS_GRACE_S: float = 15.0 # tactical seconds
const _CANOPY_CELL_M: float = 10.0
const _CANOPY_MAX_SAMPLES: int = 140
## A cached pair's transmission is reused until either end has moved this far.
const _TREE_SIGHT_CACHE_MOVE_TOLERANCE_PX: float = 10.0 * PIXELS_PER_METER
const _TREE_SIGHT_CACHE_MAX_OBSERVERS: int = 500

static var _canopy_built: bool = false
static var _canopy_cols: int = 0
static var _canopy_rows: int = 0
static var _canopy_x0_m: float = 0.0
static var _canopy_top: PackedFloat32Array = PackedFloat32Array() # cell -> ground elevation + canopy height, or -1000 with no trees
static var _tree_sight_cache: Dictionary = {} # observer id -> {target id -> [from_px, to_px, transmission]}


## Rasterizes CURRENT_MAP's forest patches once: 10 m cells, each holding the
## height of the canopy top over it (or -1000 where there are no trees). Only
## the cells under a patch's bounding box are tested, so building it costs a
## fraction of scanning the whole map. Called lazily, and from BattleManager.
## start_battle so the one-off cost lands before the fight, not mid-tick.
static func prepare_canopy() -> void:
	_canopy_built = true
	_tree_sight_cache.clear()
	_canopy_x0_m = -WEST_FLANK_WIDTH_M
	_canopy_cols = int((MAP_WIDTH_M - _canopy_x0_m) / _CANOPY_CELL_M) + 1
	_canopy_rows = int(MAP_HEIGHT_M / _CANOPY_CELL_M) + 1
	_canopy_top.resize(_canopy_cols * _canopy_rows)
	_canopy_top.fill(-1000.0)
	for patch in CURRENT_MAP.forest_patches:
		var reach_m: float = patch.radius_m * _forest_patch_max_warp(patch)
		var c0: int = maxi(int(floor((patch.center_m.x - reach_m - _canopy_x0_m) / _CANOPY_CELL_M)), 0)
		var c1: int = mini(int(floor((patch.center_m.x + reach_m - _canopy_x0_m) / _CANOPY_CELL_M)), _canopy_cols - 1)
		var r0: int = maxi(int(floor((patch.center_m.y - reach_m) / _CANOPY_CELL_M)), 0)
		var r1: int = mini(int(floor((patch.center_m.y + reach_m) / _CANOPY_CELL_M)), _canopy_rows - 1)
		for r in range(r0, r1 + 1):
			for c in range(c0, c1 + 1):
				var idx: int = r * _canopy_cols + c
				if _canopy_top[idx] > -999.0:
					continue # another patch already covers this cell
				var p_m := Vector2(_canopy_x0_m + (float(c) + 0.5) * _CANOPY_CELL_M, (float(r) + 0.5) * _CANOPY_CELL_M)
				if _forest_patch_contains_offset_m(patch, p_m - patch.center_m):
					_canopy_top[idx] = elevation_m(p_m * PIXELS_PER_METER) + TREE_CANOPY_HEIGHT_M


## Metres of the sightline from `from` to `to` (pixels) that pass through
## canopy — see the block comment above.
static func tree_sight_depth_m(from: Vector2, to: Vector2) -> float:
	if not _canopy_built:
		prepare_canopy()
	var from_m: Vector2 = from / PIXELS_PER_METER
	var to_m: Vector2 = to / PIXELS_PER_METER
	var dist_m: float = from_m.distance_to(to_m)
	var n: int = clampi(int(dist_m / _CANOPY_CELL_M), 4, _CANOPY_MAX_SAMPLES)
	var inv: float = 1.0 / float(n)
	var from_eye: float = -1000.0
	var to_eye: float = -1000.0
	var inside := 0
	var dx: float = to_m.x - from_m.x
	var dy: float = to_m.y - from_m.y
	for i in n:
		var t: float = (float(i) + 0.5) * inv
		var c: int = int((from_m.x + dx * t - _canopy_x0_m) / _CANOPY_CELL_M)
		var r: int = int((from_m.y + dy * t) / _CANOPY_CELL_M)
		if c < 0 or r < 0 or c >= _canopy_cols or r >= _canopy_rows:
			continue
		var top: float = _canopy_top[r * _canopy_cols + c]
		if top < -999.0:
			continue
		if from_eye < -999.0: # endpoint elevations only once a tree cell is actually met
			from_eye = elevation_m(from) + EYE_HEIGHT_M
			to_eye = elevation_m(to) + EYE_HEIGHT_M
		if from_eye + (to_eye - from_eye) * t < top:
			inside += 1
	return dist_m * float(inside) * inv


## 1.0 (clear) down toward 0.0 (dense woods all the way) — see the block
## comment above. `observer_id`/`target_id` key a small per-pair cache: a pair
## whose ends haven't moved more than _TREE_SIGHT_CACHE_MOVE_TOLERANCE_PX
## since it was last computed reuses that answer, so stationary units (most
## of the defense) cost almost nothing per tick.
static func tree_sight_transmission(observer_id: int, target_id: int, from: Vector2, to: Vector2) -> float:
	var by_target: Dictionary = _tree_sight_cache.get(observer_id, {})
	var entry: Array = by_target.get(target_id, [])
	if not entry.is_empty() and entry[0].distance_to(from) <= _TREE_SIGHT_CACHE_MOVE_TOLERANCE_PX and entry[1].distance_to(to) <= _TREE_SIGHT_CACHE_MOVE_TOLERANCE_PX:
		return entry[2]
	var transmission: float = exp(-tree_sight_depth_m(from, to) / TREE_SIGHT_ATTENUATION_LENGTH_M)
	if _tree_sight_cache.size() > _TREE_SIGHT_CACHE_MAX_OBSERVERS:
		_tree_sight_cache.clear()
		by_target = {}
	by_target[target_id] = [from, to, transmission]
	_tree_sight_cache[observer_id] = by_target
	return transmission


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
static func draw_cover_ring(ci: CanvasItem, radius: float, terrain: TerrainType, center: Vector2 = Vector2.ZERO) -> void:
	var in_cover := is_in_cover(terrain)
	var color: Color = Color(0.25, 1.0, 0.35, 0.9) if in_cover else Color(1.0, 0.3, 0.2, 0.55)
	var width: float = 3.0 if in_cover else 1.5
	ci.draw_arc(center, radius + 5.0, 0.0, TAU, 24, color, width, true)


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
