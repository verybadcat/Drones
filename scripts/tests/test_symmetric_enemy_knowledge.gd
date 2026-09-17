extends SceneTree
## Guards a direct user correction, after investigating a real, live-
## reported asymmetry: "It is not reasonable to assume friendly mortars
## stop fighting after just one walking wounded, while enemy ones
## continue fighting with a greatly reduced crew. Something has to be
## off." Then, once the root cause was found and explained: "You are
## asking if the enemy should track what they know about friendly units?
## If so, the answer is yes."
##
## Root cause: BattleManager._known_enemy_positions resolved the PLAYER's
## own knowledge of the enemy via a real, persistent "ever sighted, frozen
## last-known position" model (Unit.player_has_been_sighted/
## player_known_position), but the ENEMY's own knowledge of the player
## used only LIVE, moment-to-moment is_visible — no persistent memory at
## all. Since almost nothing is is_visible at any given instant, the
## enemy's "known enemy positions" list was almost always empty,
## making Unit._mortar_crew_holds_position's overrun_risk read as ~0
## regardless of real proximity — while the player's own equivalent list
## only ever grows, keeping ITS overrun_risk pinned high. Fixed with a new
## Unit.enemy_has_been_sighted/enemy_known_position pair (mirroring the
## player_* fields exactly) and BattleManager._update_enemy_intel
## (mirroring _update_player_intel exactly).
##
## Run: godot --headless --path . --script scripts/tests/test_symmetric_enemy_knowledge.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func make_battle():
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	return bm


## The core mechanism: once the enemy has seen a player unit, that
## knowledge must persist even after the unit is no longer currently
## visible — the same standard already applied to the player's own
## knowledge of the enemy.
func test_enemy_intel_persists_after_losing_visibility() -> void:
	var bm = make_battle()
	var squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(500, 500))
	bm.player_units.append(squad)

	squad.is_visible = true
	bm._update_enemy_intel()
	check(squad.enemy_has_been_sighted, "The enemy must record having sighted a player unit")
	check(squad.enemy_known_position == Vector2(500, 500), "The enemy's recorded position must match where the unit actually was when last seen")

	# Visibility lost -- a real, live fact (LOS broken, unit moved out of
	# detection range) -- but the KNOWLEDGE that it was there must not
	# vanish along with it.
	squad.is_visible = false
	squad.global_position = Vector2(9999, 9999) # moved since, unknown to the enemy
	var known: Array[Vector2] = bm._known_enemy_positions(Unit.Team.ENEMY)
	check(known.has(Vector2(500, 500)),
		"A player unit sighted moments ago and now merely out of view must still register as a known position — the enemy's knowledge must not un-happen just because is_visible flickered off")
	check(not known.has(Vector2(9999, 9999)),
		"The enemy's known position must be the LAST SEEN location, not the unit's current (unknown to the enemy) position")


## The exact reported asymmetry, verified directly: with a real, but not
## currently visible, known player squad nearby, an enemy mortar with a
## reduced crew must weigh overrun risk the same way a player mortar
## would in the mirror-image situation — not treat the threat as
## nonexistent just because it isn't live-visible at this exact instant.
func test_mortar_crew_holds_position_sees_enemys_own_known_threats() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(0, 0))
	bm.enemy_units.append(mortar)
	mortar.crew_size = 5
	mortar.crew_casualties = 4 # down to a single survivor -- remaining_fraction = 0.2

	var squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(50, 0))
	bm.player_units.append(squad)
	squad.is_visible = true
	bm._update_enemy_intel()
	squad.is_visible = false # no longer live-visible, but the enemy still knows it was just here

	var known: Array[Vector2] = bm._known_enemy_positions(Unit.Team.ENEMY)
	check(known.has(Vector2(50, 0)), "Setup check: the enemy must have a persistent record of this close threat")

	# With a real, known, close threat and almost no crew left, holding
	# position must be extremely unlikely -- the same real self-
	# preservation math a player mortar already gets, now genuinely
	# available to the enemy too.
	var hold_count := 0
	const DRAWS := 200
	for i in DRAWS:
		if mortar._mortar_crew_holds_position(known):
			hold_count += 1
	check(hold_count < DRAWS * 0.1,
		"An enemy mortar crew down to its last survivor, with a real known threat right on top of it, must hold position only rarely (got %d/%d) — not fight on as if nothing were nearby" % [hold_count, DRAWS])


func run() -> void:
	test_enemy_intel_persists_after_losing_visibility()
	test_mortar_crew_holds_position_sees_enemys_own_known_threats()
	print("Symmetric enemy-knowledge tests: %d failures" % failures)
	quit(1 if failures else 0)
