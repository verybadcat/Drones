extends SceneTree
## Direct user report: "Right now, it says we have a drone airborne, but I can't see it anywhere"
## ("Normally I do see it. Something about the current situation."). The situation, from the live
## snapshot and the user's screenshot: the drone was tracking a dangerous enemy squad and hovering
## a couple of meters from it, so its small pale icon sat inside the squad's red disc and its name
## was printed over the squad's. The drone's name now goes above it (a ground unit's is below), and
## its icon has a dark rim. And ("The drone should be drawn on top of all squads. The drone should cover up
## part of the squad, not the reverse.") it is always drawn over every other unit, by z index rather
## than by the order the units happened to be created in.
##
## Run: godot --headless --path . --script scripts/tests/test_drone_stays_visible_over_a_squad.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var drone := Unit.new()
	drone.setup(Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2.ZERO)
	var squad := Unit.new()
	squad.setup(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2.ZERO)
	var mortar := Unit.new()
	mortar.setup(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	check(squad.label_position().y > 0.0 and mortar.label_position().y > 0.0, "A ground unit's name is below it")
	check(drone.label_position().y < -14.0, "A drone's name is above it, clear of its own pip bar and of a ground unit's name (y=%.0f)" % drone.label_position().y)
	# Hovering over the squad (2 m away) the two names must not land on each other: the squad's is
	# a line below its centre, the drone's a line above its own, more than a text height apart.
	check(absf(drone.label_position().y - squad.label_position().y) > 30.0, "The names of a drone over a squad are far enough apart to be read separately")
	# Drawn over every ground unit, in whatever order they were created (a later-created squad would
	# otherwise be drawn over an earlier drone).
	var others := [squad, mortar]
	for kind in [Unit.Kind.SPOTTER, Unit.Kind.DRONE_TEAM, Unit.Kind.RESUPPLY_RUN]:
		var other := Unit.new()
		other.setup(Unit.Team.PLAYER, kind, Vector2.ZERO)
		others.append(other)
	for other in others:
		check(drone.z_index > other.z_index, "The drone is drawn over a %s (z %d vs %d)" % [other.unit_label, drone.z_index, other.z_index])
	var enemy_drone := Unit.new()
	enemy_drone.setup(Unit.Team.ENEMY, Unit.Kind.DRONE, Vector2.ZERO)
	check(enemy_drone.z_index == drone.z_index, "...whichever side flies it")
	enemy_drone.free()
	for other in others:
		if other != squad and other != mortar:
			other.free()
	drone.free()
	squad.free()
	mortar.free()
	print("Drone visibility tests: %d failures" % failures)
	quit(1 if failures else 0)
