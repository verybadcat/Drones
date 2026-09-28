extends SceneTree
## Direct user report: "I hit 'retreat now.' The drone team could have easily gone offmap. Instead
## it is going forwards and down." A retreating unit's cover detour must never take it back toward
## the enemy (east for the player, west for the enemy). The cover search only PREFERS the retreat
## side and falls back to the least-wrong zone, and the west flank has almost no cover, so a unit out
## there could be sent east to reach some.
##
## Run: godot --headless --path . --script scripts/tests/test_retreat_cover_never_goes_backward.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func meters(x: float, y: float) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

func run() -> void:
	test_the_rule()
	test_the_live_report_from_its_own_spot()
	test_cover_on_the_retreat_side_is_still_used()
	test_spotter_cover_detour_does_not_drift_far_in_y()
	print("Retreat direction (cover detour) tests: %d failures" % failures)
	quit(1 if failures else 0)


## Direct user report: "Spotter retreated off the top of the map last battle. That should not be allowed.
## Has to go to the friendly map edge." `safest_cover_point` (the spotter/drone-team retreat's own cover
## search) only ever constrained which SIDE of the map a detour could land on (`retreat_dir`, the same
## X-axis-only preference `nearest_cover_point` has) — nothing at all bounded how far the detour could run
## NORTH or SOUTH chasing "farthest from the known enemy," the exact gap already found and fixed for the
## mortar's own retreat (`retreat_cover_point_toward`'s own doc comment) but never carried over here.
## Engineered so real nearby cover is excluded (enemies placed right around the starting point, well
## within DANGER_RADIUS) — forcing the search to reach much farther out, which is exactly when an
## unconstrained pick is free to run far north or south chasing safety alone.
func test_spotter_cover_detour_does_not_drift_far_in_y() -> void:
	var from := meters(1200.0, 1500.0)
	var enemies: Array[Vector2] = [from, from + meters(200.0, 0.0), from + meters(-200.0, 100.0), from + meters(100.0, -200.0)]
	var without_reference: Vector2 = GameConfig.safest_cover_point(from, enemies, -1.0, false)
	check(absf(without_reference.y - from.y) > 100.0 * GameConfig.PIXELS_PER_METER, "Setup: with no reference point at all, the raw search really does drift far in y (%.0f m) — otherwise this scenario proves nothing" % (absf(without_reference.y - from.y) / GameConfig.PIXELS_PER_METER))

	var reference := Vector2(GameConfig.PLAYER_SAFE_X, from.y)
	var with_reference: Vector2 = GameConfig.safest_cover_point(from, enemies, -1.0, false, reference)
	check(absf(with_reference.y - from.y) < absf(without_reference.y - from.y) * 0.5, "The reference-point fix meaningfully bounds the y drift (%.0f m against %.0f m unbounded)" % [absf(with_reference.y - from.y) / GameConfig.PIXELS_PER_METER, absf(without_reference.y - from.y) / GameConfig.PIXELS_PER_METER])

	# End-to-end through the real order_retreat path (unit.gd), for both kinds that route through
	# safest_cover_point, confirming the actual game code passes the reference point through. Checked on
	# `move_target` directly, not gated on `has_move_target` — that final flag also depends on a separate,
	# unrelated "does this point actually break line of sight" gate (real cover this close to a ring of
	# enemies right on top of the starting point often doesn't), which has nothing to do with what's being
	# tested here: whether the SEARCH ITSELF was reference-bounded, not whether its answer was ultimately
	# accepted.
	for kind in [Unit.Kind.SPOTTER, Unit.Kind.DRONE_TEAM]:
		var u := Unit.new()
		root.add_child(u)
		u.setup(Unit.Team.PLAYER, kind, from)
		u.retreat_target_x = GameConfig.PLAYER_SAFE_X
		u.is_visible = true
		u.order_retreat(enemies, [], "test")
		check(absf(u.move_target.y - from.y) < 100.0 * GameConfig.PIXELS_PER_METER, "%s's real retreat detour must not drift far in y (got %.0f m)" % [u.unit_label, absf(u.move_target.y - from.y) / GameConfig.PIXELS_PER_METER])
		u.free()


func test_the_rule() -> void:
	var from := meters(-500.0, 2000.0)
	check(not Unit.retreat_detour_is_allowed(from, meters(-234.0, 2385.0), -1.0), "The live report's own detour (east and south of a player unit) is refused")
	check(Unit.retreat_detour_is_allowed(from, meters(-900.0, 2400.0), -1.0), "A detour to the west (and south) is allowed for the player")
	check(Unit.retreat_detour_is_allowed(from, meters(-500.0, 2600.0), -1.0), "A detour straight south (no backward travel) is allowed")
	check(Unit.retreat_detour_is_allowed(from, meters(-450.0, 2300.0), -1.0), "...and one that drifts 50 m back (a patch off to one side) is too")
	check(not Unit.retreat_detour_is_allowed(from, meters(-350.0, 2300.0), -1.0), "...but 150 m back is not")
	check(Unit.retreat_detour_is_allowed(from, meters(-234.0, 2385.0), 1.0), "...and east is the enemy's retreat direction, so allowed for it")
	check(not Unit.retreat_detour_is_allowed(from, meters(-900.0, 2400.0), 1.0), "...and west is refused for the enemy")


## Through order_retreat, from the spot of the live report (a visible drone team in the west flank,
## enemies known to the east), the unit never ends up on a leg that leads east.
func test_the_live_report_from_its_own_spot() -> void:
	var known: Array[Vector2] = [meters(1600.0, 1200.0), meters(1600.0, 1400.0), meters(4700.0, 1700.0)]
	var checked := 0
	for kind in [Unit.Kind.DRONE_TEAM, Unit.Kind.SPOTTER, Unit.Kind.MORTAR, Unit.Kind.SQUAD]:
		for x in range(-1200, 200, 100):
			for y in range(600, 3200, 200):
				var u := Unit.new()
				root.add_child(u)
				u.setup(Unit.Team.PLAYER, kind, meters(float(x), float(y)))
				u.retreat_target_x = GameConfig.PLAYER_SAFE_X
				u.is_visible = true
				for trial in 3:
					u.state = Unit.State.ACTIVE
					u.order_retreat(known, [], "test")
					checked += 1
					if u.has_move_target:
						check(u.move_target.x <= u.global_position.x + GameConfig.RETREAT_DETOUR_MAX_BACKWARD_M * GameConfig.PIXELS_PER_METER + 0.001, "%s at (%d, %d) m is sent east to (%.0f, %.0f) m" % [u.unit_label, x, y, u.move_target.x / GameConfig.PIXELS_PER_METER, u.move_target.y / GameConfig.PIXELS_PER_METER])
				u.free()
	check(checked > 1000, "Set-up: many cases ran (%d)" % checked)


## The rule must not switch cover off: somewhere a detour toward the retreat side is still taken.
func test_cover_on_the_retreat_side_is_still_used() -> void:
	var known: Array[Vector2] = [meters(1600.0, 1200.0)]
	var used := 0
	for kind in [Unit.Kind.SQUAD, Unit.Kind.DRONE_TEAM]:
		for x in range(-800, 2400, 100):
			for y in range(200, 3400, 300):
				var u := Unit.new()
				root.add_child(u)
				u.setup(Unit.Team.PLAYER, kind, meters(float(x), float(y)))
				u.retreat_target_x = GameConfig.PLAYER_SAFE_X
				u.is_visible = true
				u.order_retreat(known, [], "test")
				if u.has_move_target and u.move_target.x <= u.global_position.x:
					used += 1
				u.free()
	check(used > 0, "Cover detours toward the retreat side still happen (%d found)" % used)
