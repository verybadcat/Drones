extends SceneTree
## Direct user request, with the Voznesensk map: "Try to get the buildings to match what is seen on Google Maps.
## Your past maps have not matched buildings to reality particularly well." The older maps aggregate OpenStreetMap
## footprints into a few dozen blocks that are DRAWN as stylised houses; OpenStreetMap is nearly empty at
## Voznesensk (about 330 buildings where the satellite shows thousands), so that map takes its footprints from
## Overture Maps (Microsoft ML Buildings plus OpenStreetMap), draws every one as itself
## (CURRENT_MAP.building_footprints_file) and keeps the coarse terrain_zones only as the game logic's cover blocks.
##
## What this checks: a map with the key loads thousands of real polygons; the cover blocks match the picture (every
## footprint where the logic applies is inside a block, and no block stands where nothing is drawn); a map without
## the key still draws its old stylised blocks; and a bad path draws nothing instead of failing.
##
## Run: godot --headless --path . --script scripts/tests/test_map_building_footprints.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var original: String = GameConfig.current_map_id()
	GameConfig.set_active_map("voznesensk")
	var m: Dictionary = GameConfig.CURRENT_MAP
	check(m.has("building_footprints_file"), "The Voznesensk map names its footprints file")
	var polys: Array = GameConfig._footprint_polygons()
	check(polys.size() > 4000, "It loads thousands of real building footprints (%d)" % polys.size())
	var bad := 0
	for p in polys:
		if p.size() < 3:
			bad += 1
	check(bad == 0, "...every one a real polygon (%d with fewer than 3 points)" % bad)
	test_logic_blocks_match_the_picture(polys)
	# The footprints stay inside the map the player sees (a margin for buildings that straddle an edge).
	var ppm: float = GameConfig.PIXELS_PER_METER
	var outside := 0
	for p in polys:
		var c := Vector2.ZERO
		for v in p:
			c += v
		c /= float(p.size())
		var cm: Vector2 = c / ppm
		if cm.x < -1600.0 or cm.x > 5100.0 or cm.y < -100.0 or cm.y > 2400.0:
			outside += 1
	check(outside == 0, "...and none far outside the map (%d)" % outside)
	# A map without the key keeps its stylised blocks: no footprints, nothing changes for it.
	GameConfig.set_active_map("pishchane")
	check(GameConfig._footprint_polygons().is_empty(), "A map without footprints draws its old blocks (no footprint polygons)")
	# A bad path draws nothing rather than failing.
	check(GameConfig._load_footprint_file("res://assets/maps/does_not_exist.json").is_empty(), "A missing footprints file gives no polygons instead of an error")
	check(GameConfig._load_footprint_file("").is_empty(), "No file named means no polygons")
	GameConfig.set_active_map(original)
	print("Map building footprint tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_logic_blocks_match_the_picture(polys: Array) -> void:
	var ppm: float = GameConfig.PIXELS_PER_METER
	var rects: Array[Rect2] = []
	for zone in GameConfig.CURRENT_MAP.terrain_zones:
		if zone.type == GameConfig.TerrainType.BUILDING:
			rects.append(zone.rect)
	# Every footprint in the region the game logic covers (x >= -150 m, on the map) is inside a cover block.
	var in_region := 0
	var uncovered := 0
	for p in polys:
		var c := Vector2.ZERO
		for v in p:
			c += v
		c /= float(p.size())
		var cm: Vector2 = c / ppm
		if cm.x < -150.0 or cm.y > GameConfig.MAP_HEIGHT_M - 10.0 or cm.y < 0.0:
			continue
		in_region += 1
		var hit := false
		for r in rects:
			if r.has_point(c):
				hit = true
				break
		if not hit:
			uncovered += 1
	check(in_region > 1500, "Setup: a good number of footprints in the logic region (%d)" % in_region)
	check(float(uncovered) / float(max(in_region, 1)) < 0.03, "Footprints sit inside the cover blocks: %d of %d do not (under 3%% allowed)" % [uncovered, in_region])
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
	check(phantom == 0, "Every cover block has a real building in it (%d phantom blocks of %d)" % [phantom, rects.size()])
