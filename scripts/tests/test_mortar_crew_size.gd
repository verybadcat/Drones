extends SceneTree
## Guards a direct user request: "I want to check the size of the mortar
## teams against reality for both friendly and enemy mortars... Is four
## the right number of people?" Researched directly against the same
## real, per-side 82mm systems this codebase already cites for
## MORTAR_MAX_RANGE_PLAYER/ENEMY and MORTAR_SETUP_TEARDOWN_TIME — the two
## sides field genuinely different tubes, not the same crew requirement
## with a rounding difference:
##   - PLAYER (Ukraine, 2B14 Podnos): crew of 4.
##   - ENEMY (Russia, 2B24): crew of 5 (explicitly including 3 ammunition
##     carriers, per the user's own direction that ammunition carriers
##     should count toward team size for this game's purposes).
## See GameConfig.mortar_crew_size's own doc comment for the full citations.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_crew_size.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func test_player_mortar_crew_size_is_four() -> void:
	var mortar := Unit.new()
	mortar.setup(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	check(mortar.crew_size == 4, "The player's own 2B14 Podnos mortar must have a crew of 4, got %d" % mortar.crew_size)
	check(mortar.max_pips == 4, "max_pips must track crew_size for a player mortar, got %d" % mortar.max_pips)
	mortar.free()


func test_enemy_mortar_crew_size_is_five() -> void:
	var mortar := Unit.new()
	mortar.setup(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2.ZERO)
	check(mortar.crew_size == 5, "The enemy's 2B24 mortar must have a crew of 5 (including 3 ammunition carriers), got %d" % mortar.crew_size)
	check(mortar.max_pips == 5, "max_pips must track crew_size for an enemy mortar, got %d" % mortar.max_pips)
	mortar.free()


func run() -> void:
	test_player_mortar_crew_size_is_four()
	test_enemy_mortar_crew_size_is_five()
	print("Mortar crew-size tests: %d failures" % failures)
	quit(1 if failures else 0)
