extends SceneTree
## Guards every map in GameConfig.MAPS: structural invariants a hand- or
## script-authored map can silently violate (a mortar or spotter default inside a building,
## spawn/road mismatch, deployment positions outside their own zones), and
## the two lookup caches added so a map traced from real data — dozens of
## hills, well over a hundred tree patches — stays cheap:
## - GameConfig.get_terrain_type_at's spatial grid must return exactly what
##   scanning every zone and patch would;
## - GameConfig.elevation_m's flat hill tables must match the plain
##   Dictionary-form formula (to well under a centimeter), and its far-hill
##   cutoff assumes warp amplitudes total under 0.5 per hill, which is
##   checked here for every hill.
##
## Run: godot --headless --path . --script scripts/tests/test_map_integrity.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")


func _slow_terrain(pos: Vector2) -> int:
	for zone in GameConfig.CURRENT_MAP.terrain_zones:
		if zone.type == GameConfig.TerrainType.BUILDING and zone.rect.has_point(pos):
			return GameConfig.TerrainType.BUILDING
	for patch in GameConfig.CURRENT_MAP.forest_patches:
		var off: Vector2 = pos / GameConfig.PIXELS_PER_METER - patch.center_m
		if off.length() < 0.01 or off.length() <= GameConfig._forest_radius_at(patch, off.angle()):
			return GameConfig.TerrainType.TREES
	return GameConfig.TerrainType.OPEN


func _slow_elevation(pos_px: Vector2) -> float:
	var pos_m: Vector2 = pos_px / GameConfig.PIXELS_PER_METER
	var total: float = GameConfig.CURRENT_MAP.get("elevation_baseline_m", 0.0)
	for hill in GameConfig.CURRENT_MAP.hills:
		var offset: Vector2 = pos_m - hill.center_m
		var d: float = offset.length()
		var r: float = hill.radius_m * (GameConfig._hill_radius_warp(hill, offset.angle()) if d > 0.01 else 1.0)
		total += hill.height_m * exp(-(d * d) / (2.0 * r * r))
	return total


## The original, exhaustive building checks (every zone, no bounding-box
## reject) — what has_direct_los/has_aerial_los/path_crosses_building must
## still agree with exactly.
func _slow_path_crosses_building(from: Vector2, to: Vector2) -> bool:
	for zone in GameConfig.CURRENT_MAP.terrain_zones:
		if zone.type != GameConfig.TerrainType.BUILDING:
			continue
		if GameConfig._line_crosses_rect(from, to, zone.rect):
			return true
	return false


func _slow_direct_los(from: Vector2, to: Vector2) -> bool:
	for zone in GameConfig.CURRENT_MAP.terrain_zones:
		if zone.type != GameConfig.TerrainType.BUILDING:
			continue
		if zone.rect.has_point(from) or zone.rect.has_point(to):
			continue
		if GameConfig._line_crosses_rect(from, to, zone.rect):
			return false
	if GameConfig.path_crosses_river(from, to):
		return false
	var from_eye: float = GameConfig.elevation_m(from) + GameConfig.EYE_HEIGHT_M
	var to_eye: float = GameConfig.elevation_m(to) + GameConfig.EYE_HEIGHT_M
	for i in range(1, GameConfig.LOS_SAMPLE_COUNT):
		var t: float = float(i) / float(GameConfig.LOS_SAMPLE_COUNT)
		if GameConfig.elevation_m(from.lerp(to, t)) > lerp(from_eye, to_eye, t) + GameConfig.LOS_TERRAIN_TOLERANCE_M:
			return false
	return true


func _slow_aerial_los(from: Vector2, to: Vector2) -> bool:
	for zone in GameConfig.CURRENT_MAP.terrain_zones:
		if zone.type != GameConfig.TerrainType.BUILDING:
			continue
		if zone.rect.has_point(from) or zone.rect.has_point(to):
			continue
		if GameConfig._line_crosses_rect(from, to, zone.rect):
			return false
	return true


func _in_map(p: Vector2) -> bool:
	return p.x >= -GameConfig.WEST_FLANK_WIDTH_PX and p.x <= GameConfig.MAP_WIDTH_PX and p.y >= 0.0 and p.y <= GameConfig.MAP_HEIGHT_PX


func check_map(id: String) -> void:
	GameConfig.set_active_map(id)
	var m: Dictionary = GameConfig.CURRENT_MAP
	var tag := "[%s] " % id
	for key in ["name", "location_subtitle", "coordinates", "width_m", "height_m", "west_flank_width_m", "village_center", "elevation_baseline_m", "hills", "terrain_zones", "forest_patches", "road_width_m", "road_waypoints_m", "player", "enemy"]:
		check(m.has(key), tag + "missing required key '%s'" % key)

	for hill in m.hills:
		var amp := 0.0
		for h in hill.warp_harmonics:
			amp += absf(h.amplitude)
		check(amp <= 0.5, tag + "a hill's warp amplitudes total %.2f — elevation_m's far-hill cutoff assumes at most 0.5" % amp)
		check(hill.radius_m > 0.0, tag + "a hill has a non-positive radius")
	for patch in m.forest_patches:
		var amp := 0.0
		for h in patch.warp_harmonics:
			amp += absf(h.amplitude)
		check(amp < 1.0, tag + "a forest patch's warp amplitudes total %.2f — can flip its radius negative" % amp)
		check(patch.radius_m > 0.0, tag + "a forest patch has a non-positive radius")

	var road: Array = m.road_waypoints_m
	check(road.size() >= 2, tag + "road needs at least two waypoints")
	for wp in road:
		check(_in_map(wp * GameConfig.PIXELS_PER_METER), tag + "road waypoint %s lies outside the map" % wp)
	# BattleManager._spawn_enemy_units starts every squad at spawn_x, at the
	# FIRST waypoint's y, and marches the list in order — so the list must
	# run east to west. KNOWN EXCEPTION: pishchane's is listed west to east
	# (found while adding svystunivka; its squads spawn at the road's west
	# end's height instead of on the road) — left as-is here rather than
	# silently changing the default map's behavior; drop this exception when
	# that map's road is reversed.
	if id != "pishchane":
		check(is_equal_approx(road[0].x * GameConfig.PIXELS_PER_METER, m.enemy.spawn_x),
			tag + "enemy spawn_x must equal the road's first waypoint x (the list must run east to west)")
	for off in [m.enemy.squad_spread_min_offset_m, m.enemy.squad_spread_max_offset_m]:
		var y: float = road[0].y + off
		check(y >= 0.0 and y <= m.height_m, tag + "an enemy squad spawn at road offset %.0f falls outside the map (y=%.0f)" % [off, y])
	check(m.enemy.mortar_spread_min_y_m >= 0.0 and m.enemy.mortar_spread_max_y_m <= m.height_m,
		tag + "enemy mortar spread must stay inside the map's height")
	# An enemy mortar can never fire from inside a building (see BattleManager.
	# _tick_fire) - the spawn positions for every possible mortar count must
	# already be clear of them (a live Svystunivka battle spawned its single
	# mortar in a building and it never fired a round).
	for count in range(GameConfig.ENEMY_MORTAR_COUNT_MIN, GameConfig.ENEMY_MORTAR_COUNT_MAX + 1):
		for pos_m in GameConfig.enemy_mortar_positions_m(count):
			check(not GameConfig.is_building_at(pos_m * GameConfig.PIXELS_PER_METER), tag + "an enemy mortar spawn (count %d) at %s is inside a building block" % [count, pos_m])
			check(pos_m.y >= 0.0 and pos_m.y <= m.height_m, tag + "an enemy mortar spawn (count %d) at %s fell outside the map" % [count, pos_m])

	var player: Dictionary = m.player
	for pos in player.default_squad_positions:
		check(player.deployment_zone.has_point(pos), tag + "default squad position %s is outside the deployment zone" % pos)
	check(player.mortar_deployment_zone.has_point(player.mortar_default_position), tag + "default mortar position is outside its deployment zone")
	check(not GameConfig.is_building_at(player.mortar_default_position), tag + "default mortar position is inside a building block")
	check(player.spotter_deployment_zone.has_point(player.spotter_default_position), tag + "default spotter position is outside its deployment zone")
	check(not GameConfig.is_building_at(player.spotter_default_position), tag + "default spotter position is inside a building block")

	seed(4242)
	var terrain_mismatches := 0
	var worst_elev := 0.0
	for i in 3000:
		var p := Vector2(randf_range(-GameConfig.WEST_FLANK_WIDTH_PX, GameConfig.MAP_WIDTH_PX), randf_range(0.0, GameConfig.MAP_HEIGHT_PX))
		if GameConfig.get_terrain_type_at(p) != _slow_terrain(p):
			terrain_mismatches += 1
		worst_elev = maxf(worst_elev, absf(GameConfig.elevation_m(p) - _slow_elevation(p)))
	# Also every authored feature's own center and every default position —
	# exactly where a grid-cell edge case would matter most.
	for patch in m.forest_patches:
		var c: Vector2 = patch.center_m * GameConfig.PIXELS_PER_METER
		if GameConfig.get_terrain_type_at(c) != _slow_terrain(c):
			terrain_mismatches += 1
	for zone in m.terrain_zones:
		for c in [zone.rect.position, zone.rect.end, zone.rect.get_center()]:
			if GameConfig.get_terrain_type_at(c) != _slow_terrain(c):
				terrain_mismatches += 1
	# Line checks: random segments plus ones aimed straight at building
	# blocks (where a crossing test can actually matter).
	var line_mismatches := 0
	var crossings_seen := 0
	for i in 1500:
		var a := Vector2(randf_range(-GameConfig.WEST_FLANK_WIDTH_PX, GameConfig.MAP_WIDTH_PX), randf_range(0.0, GameConfig.MAP_HEIGHT_PX))
		var b: Vector2 = a + Vector2.from_angle(randf() * TAU) * randf_range(5.0, 700.0)
		if i % 2 == 0 and not m.terrain_zones.is_empty():
			var zone: Dictionary = m.terrain_zones[randi() % m.terrain_zones.size()]
			var r: Rect2 = zone.rect
			a = r.get_center() + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 250.0)
			b = r.get_center() + Vector2.from_angle(randf() * TAU) * randf_range(0.0, 250.0)
		var slow_cross: bool = _slow_path_crosses_building(a, b)
		crossings_seen += 1 if slow_cross else 0
		if GameConfig.path_crosses_building(a, b) != slow_cross:
			line_mismatches += 1
		if GameConfig.has_direct_los(a, b) != _slow_direct_los(a, b):
			line_mismatches += 1
		if GameConfig.has_aerial_los(a, b) != _slow_aerial_los(a, b):
			line_mismatches += 1
	check(line_mismatches == 0, tag + "path_crosses_building/has_direct_los/has_aerial_los disagreed with the exhaustive check at %d points" % line_mismatches)
	if not m.terrain_zones.is_empty():
		check(crossings_seen > 20, tag + "setup check: the aimed segments must actually cross building blocks sometimes (only %d did)" % crossings_seen)
	check(terrain_mismatches == 0, tag + "get_terrain_type_at's spatial grid disagreed with a full scan at %d points" % terrain_mismatches)
	check(worst_elev < 0.001, tag + "elevation_m's cached tables differ from the exact formula by up to %.6f m" % worst_elev)


func run() -> void:
	var original: String = ""
	for id in GameConfig.MAPS:
		if GameConfig.CURRENT_MAP == GameConfig.MAPS[id]:
			original = id
	for id in GameConfig.MAPS:
		check_map(id)
	if original != "":
		GameConfig.set_active_map(original)
	print("Map integrity tests: %d failures (%d maps)" % [failures, GameConfig.MAPS.size()])
	quit(1 if failures else 0)
