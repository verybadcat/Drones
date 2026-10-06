extends SceneTree
# Picks default unit positions for the new map with the game's own line-of-sight / elevation / terrain model.
# Squads: near the station, each the point that sees the most of the real road; mortar: least exposed to the road;
# spotter: inside a tree patch with the clearest view of the road.
const PPM := 0.2
var out_path := ""

func _initialize():
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out_path = a.substr(6)
	call_deferred("run")

func road_samples() -> Array[Vector2]:
	var pts: Array[Vector2] = []
	var wp: Array = GameConfig.CURRENT_MAP.road_waypoints_m
	for i in wp.size() - 1:
		var a: Vector2 = wp[i]
		var b: Vector2 = wp[i + 1]
		var n := int(a.distance_to(b) / 25.0)
		for k in n + 1:
			var p: Vector2 = a.lerp(b, float(k) / float(max(n, 1)))
			if p.x >= 1000.0 and p.x <= 4600.0:
				pts.append(p)
	return pts

func dist_to_road(p: Vector2) -> float:
	var wp: Array = GameConfig.CURRENT_MAP.road_waypoints_m
	var best := INF
	for i in wp.size() - 1:
		var a: Vector2 = wp[i]
		var b: Vector2 = wp[i + 1]
		var cp := Geometry2D.get_closest_point_to_segment(p, a, b)
		best = min(best, p.distance_to(cp))
	return best

func visible_count(p_m: Vector2, road: Array[Vector2], within_m: float = 420.0) -> int:
	# road samples within squad engagement range that the point can see
	var n := 0
	for r in road:
		if p_m.distance_to(r) > within_m:
			continue
		if GameConfig.has_direct_los(p_m * PPM, r * PPM):
			n += 1
	return n

func in_rect(p: Vector2, r: Rect2) -> bool:
	return r.has_point(p * PPM)

func run():
	GameConfig.set_active_map("voznesensk")
	var m = GameConfig.CURRENT_MAP
	var road := road_samples()
	var center: Vector2 = m.village_center / PPM
	var zone: Rect2 = m.player.deployment_zone
	var cands: Array = []
	for dx in range(-350, 351, 25):
		for dy in range(-350, 351, 25):
			var p := center + Vector2(dx, dy)
			if p.distance_to(center) > 350.0: continue
			if not in_rect(p, zone): continue
			if GameConfig.is_building_at(p * PPM): continue
			if dist_to_road(p) < 14.0: continue
			if GameConfig.get_terrain_type_at(p * PPM) == GameConfig.TerrainType.BUILDING: continue
			cands.append(p)
	print("squad candidates: ", cands.size(), "  road samples: ", road.size())
	var scored: Array = []
	for p in cands:
		scored.append([visible_count(p, road), p])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	var squads: Array = []
	for s in scored:
		var ok := true
		for q in squads:
			if q.distance_to(s[1]) < 90.0: ok = false
		if ok: squads.append(s[1])
		if squads.size() == 3: break
	print("squads: ", squads, " visible: ", [scored[0][0]])
	# mortar: least exposed, 250..700 m from the station, west of it, inside the mortar zone, not in a building
	var mz: Rect2 = m.player.mortar_deployment_zone
	var best_m := Vector2.ZERO
	var best_m_score := 1 << 30
	for dx in range(-700, 0, 25):
		for dy in range(-500, 501, 25):
			var p := center + Vector2(dx, dy)
			var d := p.distance_to(center)
			if d < 250.0 or d > 700.0: continue
			if not in_rect(p, mz): continue
			if GameConfig.is_building_at(p * PPM): continue
			if dist_to_road(p) < 20.0: continue
			var v := visible_count(p, road)
			if v < best_m_score:
				best_m_score = v
				best_m = p
	print("mortar: ", best_m, " exposure ", best_m_score)
	# spotter: inside a tree patch within 700 m of the station, best view of the road
	var best_s := Vector2.ZERO
	var best_s_score := -1
	for patch in m.forest_patches:
		var c: Vector2 = patch.center_m
		if c.distance_to(center) > 700.0: continue
		if not in_rect(c, m.player.spotter_deployment_zone): continue
		if GameConfig.get_terrain_type_at(c * PPM) != GameConfig.TerrainType.TREES: continue
		if dist_to_road(c) < 14.0: continue
		var v := visible_count(c, road)
		if v > best_s_score:
			best_s_score = v
			best_s = c
	print("spotter: ", best_s, " sees ", best_s_score, " of ", road.size())
	var out := {
		"squads": squads.map(func(p): return [roundi(p.x), roundi(p.y)]),
		"mortar": [roundi(best_m.x), roundi(best_m.y)],
		"spotter": [roundi(best_s.x), roundi(best_s.y)],
	}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	quit()
