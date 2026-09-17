extends SceneTree
## Guards the SECOND iteration of the mortar crew-casualty model, this time
## the user's own proposed design, given directly after a research
## discussion on real casualty modeling (Carleton/cookie-cutter damage
## functions): "My approach would be to determine what level of danger is
## posed by a hit, based on its distance from the mortar and on whether or
## not the mortar has cover. Then roll each person independently. The team
## could get lucky and be unaffected by a nearby hit, or get unlucky and be
## hurt at a further distance."
##
## The FIRST iteration (a flat uniform randi_range(1, remaining), then a
## geometric-decay chain with a guaranteed first casualty) is documented in
## GameConfig's own revision history and Unit._roll_crew_casualties' doc
## comment — both replaced outright by this file's model, which reuses
## CombatResolver.blast_casualty_chance (the same distance-and-cover-aware
## fragmentation curve already used everywhere else in this game) and rolls
## each remaining crew member as an independent Bernoulli draw against it.
## No casualty is guaranteed any more, at any distance.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_crew_casualty_distribution.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")


## Right at the impact point, in the open, blast_casualty_chance is exactly
## 1.0 (see test_mortar_blast_chance.gd) — every remaining crew member must
## become a casualty, deterministically, every single time.
func test_point_blank_open_hit_wipes_an_exposed_crew() -> void:
	var mortar := Unit.new()
	for i in 50:
		check(mortar._roll_crew_casualties(5, 0.0, GameConfig.TerrainType.OPEN) == 5,
			"A point-blank hit (distance 0) on an exposed crew in the open must claim the entire remaining crew every time, not just probably")
	mortar.free()


## The core of the user's own stated design: "The team could get lucky and
## be unaffected by a nearby hit." At 4x the real casualty radius, the
## per-person chance is low (~6%), so most hits at this range must produce
## ZERO casualties — a possibility the old model (guaranteed >=1 casualty
## per hit, at ANY distance) could never produce at all.
func test_far_hit_often_produces_zero_casualties() -> void:
	var mortar := Unit.new()
	var far_distance: float = GameConfig.MORTAR_BLAST_CASUALTY_RADIUS * 4.0
	const DRAWS := 300
	var zero_count := 0
	for i in DRAWS:
		if mortar._roll_crew_casualties(5, far_distance, GameConfig.TerrainType.OPEN) == 0:
			zero_count += 1
	check(zero_count > DRAWS * 0.5,
		"At 4x the casualty radius, most hits (got %d/%d) must produce zero casualties — a lucky, unaffected crew must be the common case at real range, not an impossibility" % [zero_count, DRAWS])


## Right at the casualty radius, blast_casualty_chance is calibrated to
## exactly 0.5 (the real, cited definition of "casualty radius"). Rolling
## each of 5 crew members independently at p=0.5 is a real Binomial(5, 0.5)
## — SYMMETRIC around its mean, so losing 0 and losing all 5 must be
## roughly EQUALLY likely, and the average must land near 2.5. This is the
## direct, statistical proof that casualties are now driven by independent
## per-person draws at a real, distance-derived chance, not by any
## artificial front-loading like the earlier geometric-chain model had.
func test_independent_rolls_at_the_casualty_radius_match_binomial() -> void:
	var mortar := Unit.new()
	const DRAWS := 4000
	var histogram: Dictionary = {}
	var total := 0
	for i in DRAWS:
		var n: int = mortar._roll_crew_casualties(5, GameConfig.MORTAR_BLAST_CASUALTY_RADIUS, GameConfig.TerrainType.OPEN)
		histogram[n] = histogram.get(n, 0) + 1
		total += n
	var zero_count: int = histogram.get(0, 0)
	var five_count: int = histogram.get(5, 0)
	var mean: float = float(total) / float(DRAWS)
	check(absf(zero_count - five_count) < DRAWS * 0.05,
		"At exactly the casualty radius (p=0.5 per person), losing 0 and losing all 5 must be statistically close to equally likely (got %d/%d vs %d/%d) — a real independent-per-person model is symmetric here, unlike the old front-loaded chain" % [zero_count, DRAWS, five_count, DRAWS])
	check(absf(mean - 2.5) < 0.25,
		"At p=0.5 per person across 5 crew, the average casualties per hit must land close to 2.5, got %.2f" % mean)
	mortar.free()


## Real cover must measurably reduce expected casualties at the SAME
## distance — the other half of the user's own stated design ("based on
## its distance from the mortar and on whether or not the mortar has
## cover"), for free, by reusing blast_casualty_chance's own already-tested
## MORTAR_COVER_MULTIPLIER table rather than inventing a separate one.
func test_cover_reduces_expected_casualties_at_the_same_distance() -> void:
	var mortar := Unit.new()
	var d: float = GameConfig.MORTAR_BLAST_CASUALTY_RADIUS
	const DRAWS := 2000
	var open_total := 0
	var building_total := 0
	for i in DRAWS:
		open_total += mortar._roll_crew_casualties(5, d, GameConfig.TerrainType.OPEN)
		building_total += mortar._roll_crew_casualties(5, d, GameConfig.TerrainType.BUILDING)
	var open_mean: float = float(open_total) / float(DRAWS)
	var building_mean: float = float(building_total) / float(DRAWS)
	check(building_mean < open_mean * 0.5,
		"A crew under real cover (BUILDING) must take substantially fewer average casualties than one caught in the OPEN at the same distance (got open=%.2f, building=%.2f)" % [open_mean, building_mean]
	)
	mortar.free()


## Defensive sanity floor: a crew with no one left (remaining <= 0 — can
## happen in practice after repeated hits, since crew_casualties is never
## reset mid-battle) must never report MORE casualties out of thin air.
func test_non_positive_remaining_returns_zero() -> void:
	var mortar := Unit.new()
	check(mortar._roll_crew_casualties(0, 0.0, GameConfig.TerrainType.OPEN) == 0,
		"Zero remaining crew must never produce a casualty count above zero")
	check(mortar._roll_crew_casualties(-1, 0.0, GameConfig.TerrainType.OPEN) == 0,
		"A negative remaining count must never produce a casualty count above zero")
	mortar.free()


func run() -> void:
	test_point_blank_open_hit_wipes_an_exposed_crew()
	test_far_hit_often_produces_zero_casualties()
	test_independent_rolls_at_the_casualty_radius_match_binomial()
	test_cover_reduces_expected_casualties_at_the_same_distance()
	test_non_positive_remaining_returns_zero()
	print("Mortar crew casualty-distribution tests: %d failures" % failures)
	quit(1 if failures else 0)
