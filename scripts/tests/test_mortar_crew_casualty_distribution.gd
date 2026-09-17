extends SceneTree
## Guards a direct user correction, after investigating how mortar crews
## react to hits: "Please do research and implement real-world casualty
## distribution data."
##
## Unit._apply_crew_casualties used to draw the number of newly-down crew
## via `randi_range(1, remaining)` — a UNIFORM roll, meaning "lose one
## person" and "lose the entire crew" were treated as EQUALLY likely
## outcomes of the same hit (a full 25% chance of instant total loss on
## every single hit for a 4-person crew). Real HE fragmentation lethality
## decays smoothly with distance — this project's own already-cited
## "casualty radius" convention (the distance at which a STATED
## PERCENTAGE, conventionally 50%, of EXPOSED personnel become
## casualties — see GameConfig.MORTAR_BLAST_CASUALTY_RADIUS) is the real
## figure reused here: the first casualty is guaranteed (whoever's
## nearest the impact), and each additional survivor is an independent
## 50-50 draw, producing a real, front-loaded distribution instead of a
## flat one.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_crew_casualty_distribution.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

## The core statistical claim: losing exactly 1 crew member must be
## measurably MORE common than losing the entire crew — the opposite of
## the old uniform model, where both were exactly equally likely.
func test_casualty_distribution_is_front_loaded_not_uniform() -> void:
	var mortar := Unit.new()
	mortar.crew_size = 5
	const DRAWS := 2000
	var histogram: Dictionary = {}
	for i in DRAWS:
		var n: int = mortar._roll_crew_casualties(5)
		histogram[n] = histogram.get(n, 0) + 1
	var one_count: int = histogram.get(1, 0)
	var all_count: int = histogram.get(5, 0)
	check(one_count > all_count * 3,
		"Losing exactly 1 crew member (%d/%d) must be substantially more common than losing the entire crew (%d/%d) — got roughly the same rate, which is what the old uniform model would produce" % [one_count, DRAWS, all_count, DRAWS])
	check(one_count > DRAWS * 0.25,
		"Losing exactly 1 must be the single most common outcome for a 5-person crew, not merely one of five equally-likely ones (got %d/%d, expected well over the old uniform model's own 20%%)" % [one_count, DRAWS]
	)
	mortar.free()


## Sanity floor: the first casualty is always guaranteed — a real "hit"
## must never produce zero casualties.
func test_at_least_one_casualty_always() -> void:
	var mortar := Unit.new()
	mortar.crew_size = 4
	for i in 200:
		check(mortar._roll_crew_casualties(4) >= 1, "A registered hit must always cost at least one crew member")
	mortar.free()


## The distribution must still be capable of reaching a full wipe (not
## capped below crew_size) — a real, if rare, outcome, not an outright
## impossibility.
func test_full_crew_loss_still_possible() -> void:
	var mortar := Unit.new()
	mortar.crew_size = 4
	var saw_full_loss := false
	for i in 500:
		if mortar._roll_crew_casualties(4) == 4:
			saw_full_loss = true
			break
	check(saw_full_loss, "Losing the entire crew in one hit must still be possible, just rarer than losing fewer — never saw it in 500 draws")
	mortar.free()


func run() -> void:
	test_casualty_distribution_is_front_loaded_not_uniform()
	test_at_least_one_casualty_always()
	test_full_crew_loss_still_possible()
	print("Mortar crew casualty-distribution tests: %d failures" % failures)
	quit(1 if failures else 0)
