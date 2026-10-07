extends SceneTree
## Direct user instruction: "Let's even allow it to be dragged through the red during setup, but not placed. If the user stops dragging
## inside the red, the mortar goes to the last legal spot it passed through."
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_drag_setup.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(x: float, y: float = 0.0) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

## [open ground just west of the red, a point 150 m into it, open ground beyond it], along one row of Pishchane.
func row() -> Array:
	var y: float = m(0.0, 1400.0).y
	var first := -1.0
	var last := -1.0
	for xm in range(0, 3000, 5):
		if GameConfig.mortar_excluded_at(Vector2(m(float(xm)).x, y)):
			if first < 0.0:
				first = float(xm)
			last = float(xm)
	return [Vector2(m(first - 25.0).x, y), Vector2(m(first + 150.0).x, y), Vector2(m(last + 25.0).x, y), first, last]


func make_screen() -> DeploymentScreen:
	var screen := DeploymentScreen.new()
	root.add_child(screen)
	return screen

func run() -> void:
	GameConfig.set_active_map("pishchane")
	var r := row()
	var west: Vector2 = r[0]
	var inside: Vector2 = r[1]
	var beyond: Vector2 = r[2]
	var zone: Rect2 = GameConfig.CURRENT_MAP.player.mortar_deployment_zone
	check(zone.has_point(west) and zone.has_point(inside), "Setup: the test row lies inside the mortar's deployment zone")
	check(GameConfig.mortar_excluded_at(inside) and not GameConfig.mortar_excluded_at(west) and not GameConfig.mortar_excluded_at(beyond), "Setup: west is open, inside is red, beyond is open")

	# 1. Dragged into the red and let go there: back to the last legal spot it passed through, at the edge.
	var screen := make_screen()
	var mortar: UnitToken = screen._mortar_token
	mortar.position = west
	screen.begin_drag(west)
	check(screen._dragging == mortar, "Setup: the press picks up the mortar")
	screen.drag_to(inside)
	check(mortar.position.distance_to(inside) < 0.5, "While the drag goes on the mortar token follows the cursor into the red")
	screen.end_drag()
	check(not GameConfig.mortar_excluded_at(mortar.position), "Let go inside the red, the mortar is not left there")
	var edge_x_m: float = float(r[3])
	check(absf(mortar.position.x / GameConfig.PIXELS_PER_METER - edge_x_m) < 15.0 and mortar.position.x < m(edge_x_m).x, "...it goes to the last legal spot it passed through: the edge of the red (x %.0f m, the red begins at %.0f)" % [mortar.position.x / GameConfig.PIXELS_PER_METER, edge_x_m])
	check(screen._dragging == null, "The drag is over")
	screen.free()

	# 2. Dragged all the way through the red to open ground beyond: it stays where it was let go.
	screen = make_screen()
	mortar = screen._mortar_token
	mortar.position = west
	screen.begin_drag(west)
	for i in range(1, 41):
		screen.drag_to(west.lerp(beyond, float(i) / 40.0))
	screen.end_drag()
	check(mortar.position.distance_to(beyond) < 0.5, "Dragged through the red and let go on open ground beyond it, the mortar stays there")
	screen.free()

	# 2b. The red layer shows only while the mortar is held (a layer shown or hidden, not the whole screen redrawn: that took about a second).
	screen = make_screen()
	check(not screen._red_layer.visible, "The red is not shown before anything is picked up")
	screen.begin_drag(screen._squad_tokens[1].position)
	check(not screen._red_layer.visible, "...nor while a squad is held")
	screen.end_drag()
	screen.begin_drag(screen._mortar_token.position)
	check(screen._red_layer.visible, "...but is shown while the mortar is held")
	screen.end_drag()
	check(not screen._red_layer.visible, "...and hidden again when it is let go")
	screen.free()

	# 3. A squad is not held to any of it: it may be set down in the red.
	screen = make_screen()
	var squad: UnitToken = screen._squad_tokens[0]
	squad.position = west
	screen.begin_drag(west)
	check(screen._dragging == squad or screen._dragging != null, "Setup: a press picks something up")
	screen._dragging = squad
	screen.drag_to(inside)
	screen.end_drag()
	check(squad.position.distance_to(inside) < 0.5, "A squad can be set down in the red")
	screen.free()

	# 4. A building: dragged into one and let go, the mortar goes back to the last spot outside it.
	screen = make_screen()
	mortar = screen._mortar_token
	var block := Rect2()
	for z in GameConfig.CURRENT_MAP.terrain_zones:
		if z.type == GameConfig.TerrainType.BUILDING and zone.has_point(z.rect.get_center()) and z.rect.size.x > m(30.0).x:
			block = z.rect
			break
	if block.size.x > 0.0:
		var outside := Vector2(block.position.x - m(20.0).x, block.get_center().y)
		if not GameConfig.is_building_at(outside) and zone.has_point(outside):
			mortar.position = outside
			screen.begin_drag(outside)
			screen.drag_to(block.get_center())
			check(GameConfig.is_building_at(mortar.position), "Setup: the drag has taken the token into a building")
			screen.end_drag()
			check(not GameConfig.is_building_at(mortar.position), "Let go inside a building, the mortar goes back to the last spot outside it")
	screen.free()
	print("Mortar drag setup tests: %d failures" % failures)
	quit(1 if failures else 0)
