extends SceneTree
## A mortar crew's stored rounds cook off only when a round lands near enough to set them off. User: "In four salvoes, our mortar has
## knocked out three enemy mortars. Check what is going on." Found: of the enemy crews our mortar destroyed, 39 of 47 (80 battles' worth
## of crews, 64 battles) were destroyed in the very tick of a cook-off, and the chance of one was the same (0.35 at a full load, then) for a
## round 40 m away that cost the crew one man as for one in the gun pit: the roll ignored where the round landed. It now falls with
## the distance as fragmentation does, and its maximum is 0.1 (the user's decision: no real-world rate was found).
##
## Run: godot --headless --path . --script scripts/tests/test_cookoff_distance.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(x: float) -> float:
	return x * GameConfig.PIXELS_PER_METER

func cooked_off_share(distance_m: float, rounds: int, trials: int) -> float:
	var n := 0
	for i in trials:
		var crew := Unit.new()
		crew.setup(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(m(-5000), m(-5000)))
		crew.mortar_rounds_remaining = rounds
		# a hit that costs nobody, so that only the cook-off can destroy the crew's stored rounds
		crew.take_hit(true, [], [], m(distance_m), 0)
		if crew.mortar_rounds_remaining == 0 and rounds > 0:
			n += 1
		crew.free()
	return float(n) / float(trials)

func run() -> void:
	seed(20261014)
	var full: int = GameConfig.MORTAR_STARTING_AMMO
	var n := 4000
	var at0: float = cooked_off_share(0.0, full, n)
	var at10: float = cooked_off_share(10.0, full, n)
	var at26: float = cooked_off_share(26.0, full, n)
	var at40: float = cooked_off_share(40.0, full, n)
	var at100: float = cooked_off_share(100.0, full, n)
	var half_load_at0: float = cooked_off_share(0.0, full / 2, n)
	# at the gun: the judgment figure (0.1 for a full load; the user's decision, 2026-10-14)
	check(at0 > 0.085 and at0 < 0.115, "round on the gun, full load: %.3f of crews cook off (0.10)" % at0)
	# falling with distance as the fragmentation does: 0.1 x 0.77, x 0.5, x 0.34, x 0.02
	check(at10 > 0.063 and at10 < 0.092, "10 m, full load: %.3f (0.1 x 0.77 = 0.077)" % at10)
	check(at26 > 0.038 and at26 < 0.062, "26 m, full load: %.3f (0.05)" % at26)
	check(at40 > 0.024 and at40 < 0.045, "40 m, full load: %.3f (0.1 x 0.34 = 0.034)" % at40)
	check(at100 < 0.008, "100 m, full load: %.3f (about 0.002)" % at100)
	# still scaled by what is stacked at the gun
	check(half_load_at0 > 0.038 and half_load_at0 < 0.062, "round on the gun, half a load: %.3f (0.05)" % half_load_at0)
	check(cooked_off_share(0.0, 0, 200) == 0.0, "an empty tube cannot cook off")
	print("Cook-off distance tests: %d failures" % failures)
	quit(1 if failures else 0)
