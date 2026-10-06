extends SceneTree
## Direct user request, with the Voznesensk map: "Try to get the buildings to match what is seen on Google Maps.
## Your past maps have not matched buildings to reality particularly well." Then: "whatever process you used to
## make this map, use it to redo the others". The older maps aggregated OpenStreetMap footprints into a few dozen
## blocks that were DRAWN as stylised houses, and OpenStreetMap is nearly empty in these places; every map now takes
## its footprints from Overture Maps (Microsoft ML Buildings plus OpenStreetMap), draws each as itself
## (CURRENT_MAP.building_footprints_file) and keeps the coarse terrain_zones only as the game logic's cover blocks.
##
## What this checks, on every map: it loads a real set of footprint polygons; the cover blocks match the picture (every
## footprint where the logic applies is inside a block, and no block stands where nothing is drawn); and a bad path
## draws nothing instead of failing.
##
## Run: godot --headless --path . --script scripts/tests/test_map_building_footprints.gd
var failures := 0

# How many footprints each map should have loaded at least, and the west edge of the region where the game logic has
# cover blocks (Voznesensk's far-west town is only a picture).
const EXPECT := {
	"pervomaiske": {"min": 400, "logic_from_x_m": -1600.0},
	"pishchane": {"min": 300, "logic_from_x_m": -1600.0},
	"svystunivka": {"min": 150, "logic_from_x_m": -1600.0},
	"voznesensk": {"min": 4000, "logic_from_x_m": -150.0},
}

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var original: String = GameConfig.current_map_id()
	check(EXPECT.size() == GameConfig.MAPS.size(), "Setup: this test knows every map (%d of %d)" % [EXPECT.size(), GameConfig.MAPS.size()])
	for map_id in GameConfig.MAPS.keys():
		GameConfig.set_active_map(map_id)
		var expect: Dictionary = EXPECT.get(map_id, {"min": 1, "logic_from_x_m": -1600.0})
		var m: Dictionary = GameConfig.CURRENT_MAP
		check(m.has("building_footprints_file"), "%s: the map names its footprints file" % map_id)
		var polys: Array = GameConfig._footprint_polygons()
		check(polys.size() >= int(expect.min), "%s: it loads real building footprints (%d, at least %d)" % [map_id, polys.size(), int(expect.min)])
		var bad := 0
		for p in polys:
			if p.size() < 3:
				bad += 1
		check(bad == 0, "%s: ...every one a real polygon (%d with fewer than 3 points)" % [map_id, bad])
		test_logic_blocks_match_the_picture(map_id, polys, float(expect.logic_from_x_m))
		# The footprints stay inside the map the player sees (a margin for buildings that straddle an edge).
		var ppm: float = GameConfig.PIXELS_PER_METER
		var outside := 0
		for p in polys:
			var c := Vector2.ZERO
			for v in p:
				c += v
			c /= float(p.size())
			var cm: Vector2 = c / ppm
			if cm.x < -GameConfig.WEST_FLANK_WIDTH_M - 100.0 or cm.x > GameConfig.MAP_WIDTH_M + 100.0 or cm.y < -100.0 or cm.y > GameConfig.MAP_HEIGHT_M + 100.0:
				outside += 1
		check(outside == 0, "%s: ...and none far outside the map (%d)" % [map_id, outside])
	# A bad path draws nothing rather than failing.
	check(GameConfig._load_footprint_file("res://assets/maps/does_not_exist.json").is_empty(), "A missing footprints file gives no polygons instead of an error")
	check(GameConfig._load_footprint_file("").is_empty(), "No file named means no polygons")
	GameConfig.set_active_map(original)
	print("Map building footprint tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_logic_blocks_match_the_picture(map_id: String, polys: Array, logic_from_x_m: float) -> void:
	var ppm: float = GameConfig.PIXELS_PER_METER
	var rects: Array[Rect2] = []
	for zone in GameConfig.CURRENT_MAP.terrain_zones:
		if zone.type == GameConfig.TerrainType.BUILDING:
			rects.append(zone.rect)
	# Every footprint in the region the game logic covers (and on the map) is inside a cover block.
	var in_region := 0
	var uncovered := 0
	for p in polys:
		var c := Vector2.ZERO
		for v in p:
			c += v
		c /= float(p.size())
		var cm: Vector2 = c / ppm
		if cm.x < logic_from_x_m or cm.y > GameConfig.MAP_HEIGHT_M - 10.0 or cm.y < 0.0 or cm.x > GameConfig.MAP_WIDTH_M:
			continue
		in_region += 1
		var hit := false
		for r in rects:
			if r.has_point(c):
				hit = true
				break
		if not hit:
			uncovered += 1
	check(in_region > 100, "%s: setup: a good number of footprints in the logic region (%d)" % [map_id, in_region])
	check(float(uncovered) / float(max(in_region, 1)) < 0.03, "%s: footprints sit inside the cover blocks: %d of %d do not (under 3%% allowed)" % [map_id, uncovered, in_region])
	# No phantom block: every cover block has at least one real footprint touching it.
	var phantom := 0
	for r in rects:
		var touched := false
		for p in polys:
			var box := Rect2(p[0], Vector2.ZERO)
			for v in p:
				box = box.expand(v)
			if box.intersects(r):
				touched = true
				break
		if not touched:
			phantom += 1
	check(phantom == 0, "%s: every cover block has a real building in it (%d phantom blocks of %d)" % [map_id, phantom, rects.size()])
