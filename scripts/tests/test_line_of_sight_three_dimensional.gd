extends SceneTree
## Direct user instruction: "In general, line of sight should respect 3 dimensional math." It came from the drone that hovered 290 m from an
## enemy mortar it could not see: has_aerial_los refused the shot because a cover block lay somewhere along the line, however high the
## drone was. A sightline is a straight line in three dimensions, and a building bars it only where the line passes below its roof.
##
## What this checks, on Voznesensk (many cover blocks): a drone 300 m up looking across a building at a target well beyond it sees it; at a
## target a metre behind the building's edge it sees it too (user: "For drone vision, I think we can just ignore buildings as obstacles ...
## other than units INSIDE the building"), though a unit inside a building is hidden from it; a ground observer at eye level is barred by
## the same building as before; a ground observer high enough above the roof is not; and the drone's look still respects a hill beside its
## target (a steep slanting line).
##
## Run: godot --headless --path . --script scripts/tests/test_line_of_sight_three_dimensional.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(x: float, y: float) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER


## A wide building block with open ground on both sides along a west-east line through its middle: [rect, a point west of it, a point east].
func find_block() -> Array:
	for zone in GameConfig.CURRENT_MAP.terrain_zones:
		if zone.type != GameConfig.TerrainType.BUILDING:
			continue
		var r: Rect2 = zone.rect
		if r.size.x < 60.0 * GameConfig.PIXELS_PER_METER or r.position.x < m(200, 0).x:
			continue
		var y: float = r.position.y + r.size.y * 0.5
		var west := Vector2(r.position.x - m(40, 0).x, y)
		var east := Vector2(r.end.x + m(40, 0).x, y)
		if GameConfig.is_building_at(west) or GameConfig.is_building_at(east):
			continue
		return [r, west, east]
	return []


func test_a_drone_sees_across_a_building_but_not_from_right_behind_it() -> void:
	GameConfig.set_active_map("voznesensk")
	var found := find_block()
	check(found.size() == 3, "Setup: a building block with open ground on both sides")
	if found.size() < 3:
		return
	var rect: Rect2 = found[0]
	var west: Vector2 = found[1]
	# The drone is 290 m up-range on the west side; the target is just over 40 m beyond the east edge. Walk the target along the line.
	var drone := Vector2(rect.position.x - m(290, 0).x, west.y)
	var far := Vector2(rect.end.x + m(60, 0).x, west.y)
	check(GameConfig.has_aerial_los(drone, far), "A drone 300 m up sees a target 60 m beyond a building (a 6 m roof shades only a few metres)")
	check(not GameConfig.has_direct_los(west, far), "...which a man at ground level could not")
	# Right behind the edge: buildings are no obstacle to the drone at all (user: "For drone vision, I think we can just ignore buildings as
	# obstacles ... other than units INSIDE the building"). Only a unit under the roof is hidden.
	var behind := Vector2(rect.end.x + m(1.0, 0).x, west.y)
	check(GameConfig.has_aerial_los(drone, behind), "A target 1 m behind the building's edge is seen by the drone: buildings are no obstacle to it")
	check(GameConfig.has_aerial_los(drone, rect.get_center()), "...and even a point inside the block is not cut off by the line itself")


func test_height_decides_a_ground_sightline_over_a_building() -> void:
	GameConfig.set_active_map("voznesensk")
	var found := find_block()
	if found.size() < 3:
		return
	var rect: Rect2 = found[0]
	var a: Vector2 = found[1]
	var b: Vector2 = found[2]
	var low: float = GameConfig.elevation_m(a) + GameConfig.EYE_HEIGHT_M
	var low_b: float = GameConfig.elevation_m(b) + GameConfig.EYE_HEIGHT_M
	check(GameConfig._building_blocks_sightline(a, b, rect, low, low_b), "At eye level a building across the line bars it")
	check(not GameConfig._building_blocks_sightline(a, b, rect, GameConfig.elevation_m(a) + 60.0, low_b), "From 60 m above the ground a line over the building clears the roof")
	check(not GameConfig._building_blocks_sightline(a, a + m(0, 30), rect, low, low), "A line that never meets the building is not barred")
	# the clipping helper itself
	var span: Vector2 = GameConfig._segment_rect_range(a, b, rect)
	check(span.x > 0.0 and span.y < 1.0 and span.x < span.y, "The line enters and leaves the block between its ends (%s)" % str(span))
	var miss: Vector2 = GameConfig._segment_rect_range(a, a + m(0, 30), rect)
	check(miss.x > miss.y, "A line that misses the block clips to nothing")


## Units INSIDE a building are the one thing a roof hides from the drone.
func test_a_unit_inside_a_building_is_not_seen_by_the_drone() -> void:
	GameConfig.set_active_map("voznesensk")
	var found := find_block()
	if found.size() < 3:
		return
	var rect: Rect2 = found[0]
	var inside: Vector2 = rect.get_center()
	var outside: Vector2 = Vector2(rect.end.x + m(30.0, 0).x, rect.get_center().y)
	check(GameConfig.is_building_at(inside) and not GameConfig.is_building_at(outside), "Setup: one point inside a building block, one outside it")
	var drone := Unit.new()
	drone.kind = Unit.Kind.DRONE
	drone.team = Unit.Team.PLAYER
	drone.global_position = outside + m(-300.0, 0)
	var hidden_squad := Unit.new()
	hidden_squad.kind = Unit.Kind.SQUAD
	hidden_squad.team = Unit.Team.ENEMY
	hidden_squad.global_position = inside
	var open_squad := Unit.new()
	open_squad.kind = Unit.Kind.SQUAD
	open_squad.team = Unit.Team.ENEMY
	open_squad.global_position = outside
	for u in [drone, hidden_squad, open_squad]:
		root.add_child(u)
	check(CombatResolver.hidden_from_drone(drone, hidden_squad), "A squad inside a building is hidden from a drone")
	check(not CombatResolver.hidden_from_drone(drone, open_squad), "...one beside it is not")
	check(not CombatResolver.hidden_from_drone(hidden_squad, open_squad), "...and the rule is about drones only (a ground observer is not affected by it)")
	seed(5)
	var seen_inside := 0
	var seen_outside := 0
	for i in 1500:
		if CombatResolver.roll_spot(drone, hidden_squad, 30.0):
			seen_inside += 1
		if CombatResolver.roll_spot(drone, open_squad, 30.0):
			seen_outside += 1
	check(seen_outside > 100, "Setup: the drone does notice the squad beside the building (%d of 1500)" % seen_outside)
	check(seen_inside == 0, "...and never the one inside it (%d of 1500)" % seen_inside)
	var watchers: Array[Unit] = [drone]
	check(not CombatResolver.has_live_observer(hidden_squad, watchers), "A squad already seen that steps inside a building is lost to the drone")
	check(CombatResolver.has_live_observer(open_squad, watchers), "...while one beside it is kept")
	for u in [drone, hidden_squad, open_squad]:
		u.free()


func run() -> void:
	test_a_drone_sees_across_a_building_but_not_from_right_behind_it()
	test_height_decides_a_ground_sightline_over_a_building()
	test_a_unit_inside_a_building_is_not_seen_by_the_drone()
	GameConfig.set_active_map("pishchane")
	print("Three-dimensional line of sight tests: %d failures" % failures)
	quit(1 if failures else 0)
