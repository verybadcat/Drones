extends SceneTree
## Direct user report: "Enemy mortar just charged into our rear area. That's crazy." and "Does the enemy
## mortar stop moving when it fires? It should have the same constraints as the friendly mortar." The
## live snapshot: an enemy mortar (deployed around x = 4300, y = 125 m) at (-1124, 92), inside our rear
## area, on a "conceal" relocation; enemy mortars had no home leash on relocations and no infantry-screen
## or leash limits on hunting, which the friendly mortar has. (Both sides already share the firing rules:
## a crew must have sat still 30 tactical seconds before it fires, and a shot available while it is
## walking stops the walk; those are in _mortar_shot_this_tick and _tick_fire, neither of which asks
## whose mortar it is.)
##
## Run: godot --headless --path . --script scripts/tests/test_enemy_mortar_same_constraints.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(x: float, y: float) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

func make_battle():
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	return bm

func cleanup(bm) -> void:
	bm.combat_log.free()
	bm.free()

func run() -> void:
	test_the_leash_is_the_same_fraction_of_each_sides_range()
	test_an_enemy_mortar_may_not_hunt_ahead_of_its_own_squads()
	test_an_enemy_mortar_hunt_is_held_to_its_leash()
	test_an_enemy_mortar_hiding_stays_within_its_leash()
	test_both_sides_share_the_firing_rules()
	print("Enemy mortar constraint tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_the_leash_is_the_same_fraction_of_each_sides_range() -> void:
	check(is_equal_approx(GameConfig.mortar_home_leash(Unit.Team.PLAYER), GameConfig.MORTAR_HUNT_MAX_RANGE_FROM_HOME), "The player's ordinary leash is what it always was")
	check(is_equal_approx(GameConfig.mortar_home_leash(Unit.Team.PLAYER, true), GameConfig.MORTAR_HUNT_EXTENDED_RANGE_FROM_HOME), "...and its extended one")
	for team in [Unit.Team.PLAYER, Unit.Team.ENEMY]:
		check(is_equal_approx(GameConfig.mortar_home_leash(team) / GameConfig.mortar_max_range(team), 0.5) and is_equal_approx(GameConfig.mortar_home_leash(team, true) / GameConfig.mortar_max_range(team), 1.0), "Each side's leash is the same fraction of its own weapon's range")


## An enemy mortar hunting our mortar may not be sent newly ahead of its own squads (west of the westmost).
func test_an_enemy_mortar_may_not_hunt_ahead_of_its_own_squads() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4300, 1200))
	bm.enemy_units.append(mortar)
	bm._enemy_mortar_homes[mortar] = mortar.global_position
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(3000, 1200))
	bm.enemy_units.append(squad) # the westmost enemy squad: the line
	check(bm._friendly_mortar_hunt_destination_is_reckless(mortar, m(2500, 1200)), "A hunt destination west of the enemy's own westmost squad is reckless for it")
	check(not bm._friendly_mortar_hunt_destination_is_reckless(mortar, m(3500, 1200)), "...one behind that line is not")
	check(bm._friendly_mortar_hunt_destination_is_reckless(mortar, m(3500, 2000)), "...and one outside the band its squads hold is (newly outside it)")
	# The player's rule is unchanged: east of its own squads is ahead.
	var pm: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(500, 1200))
	bm.player_units.append(pm)
	var ps: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(1500, 1200))
	bm.player_units.append(ps)
	check(bm._friendly_mortar_hunt_destination_is_reckless(pm, m(2000, 1200)) and not bm._friendly_mortar_hunt_destination_is_reckless(pm, m(1000, 1200)), "The player's is as before: east of its squads is ahead")
	# Through the real destination function: our mortar far west, out of range; the enemy's advance would
	# take it past its squads, so it goes nowhere.
	squad.global_position = m(3800, 1200) # the line is now east of where a hunt of a far-west mortar would put it
	var dest: Vector2 = bm._mortar_hunt_destination_for(mortar, m(-2500, 1200), true) # 6800 m out: needs an advance
	check(dest == mortar.global_position, "Hunting a mortar far west, it is not sent past its own squads: it stays put (dest %s)" % (dest / GameConfig.PIXELS_PER_METER))
	squad.global_position = m(2500, 1200) # its squads are well ahead of where the advance would put it
	dest = bm._mortar_hunt_destination_for(mortar, m(-2500, 1200), true)
	check(dest != mortar.global_position and dest.x < mortar.global_position.x, "...but with its squads ahead of the place it would go, it does advance (dest %s)" % (dest / GameConfig.PIXELS_PER_METER))
	cleanup(bm)


func test_an_enemy_mortar_hunt_is_held_to_its_leash() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4300, 1200))
	bm.enemy_units.append(mortar)
	bm._enemy_mortar_homes[mortar] = m(4900, 1200) # deployed far back
	bm._enemy_mortar_homes[mortar] = m(-3500, 1200) # (an odd home, to put the advance point beyond the leash)
	var dest: Vector2 = bm._mortar_hunt_destination_for(mortar, m(-2500, 1200), true) # no squads left to screen it
	check(dest == mortar.global_position, "With no squads to hold it back, the leash from where it was deployed still does (dest %s)" % (dest / GameConfig.PIXELS_PER_METER))
	bm._enemy_mortar_homes[mortar] = m(4300, 1200)
	dest = bm._mortar_hunt_destination_for(mortar, m(-2500, 1200), true)
	check(dest != mortar.global_position, "...while from a home it is within reach of, it advances (dest %s)" % (dest / GameConfig.PIXELS_PER_METER))
	check(bm._mortar_home_position(mortar) == m(4300, 1200), "An enemy mortar's home is where it was deployed")
	cleanup(bm)


## The live case: an enemy mortar hiding from our fire drifted clear across the map. Whatever relocation
## plan it gets must end within the leash of where it was deployed.
func test_an_enemy_mortar_hiding_stays_within_its_leash() -> void:
	var leash: float = GameConfig.mortar_home_leash(Unit.Team.ENEMY)
	var plans := 0
	var beyond := 0
	seed(11)
	for trial in 30:
		var bm = make_battle()
		var home := m(4300.0, 125.0 + 60.0 * trial)
		var mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, home + m(-2990.0, 0.0)) # right at the end of its leash, to the west: a plan that goes further west breaks it
		bm.enemy_units.append(mortar)
		bm._enemy_mortar_homes[mortar] = home
		mortar.is_visible = true
		for p in [m(1500, 1000 + 40 * trial), m(1700, 1500)]:
			var ours: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, p)
			ours.enemy_has_been_sighted = true
			ours.enemy_known_position = p
			ours.enemy_known_state = Unit.State.ACTIVE
			bm.player_units.append(ours)
		var plan: Dictionary = bm._mortar_relocation_plan(mortar, trial % 2 == 0)
		if not plan.is_empty():
			plans += 1
			if plan.destination.distance_to(home) > leash + 1.0:
				beyond += 1
		cleanup(bm)
	check(plans > 5, "Set-up: the search does produce relocation plans (%d of 30)" % plans)
	check(beyond == 0, "No enemy relocation plan ends beyond the leash from where it was deployed (%d of %d did)" % [beyond, plans])


## Firing is not different for the enemy: same code.
func test_both_sides_share_the_firing_rules() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/battle_manager.gd")
	var start: int = src.find("func _mortar_shot_this_tick(")
	var body: String = src.substr(start, 1800)
	check("seconds_stationary >= GameConfig.MORTAR_SETUP_TEARDOWN_TIME" in body and not ("Team.ENEMY" in body) and not ("Team.PLAYER" in body), "The 30-second setup rule before a shot is not conditioned on which side's mortar it is")
	var tf: int = src.find("func _tick_fire(")
	var fire_body: String = src.substr(tf, 6500)
	check("_clear_mortar_move(unit)" in fire_body and "if unit.has_move_target:" in fire_body, "A mortar with a shot available stops its walk to fire, whichever side it is")
