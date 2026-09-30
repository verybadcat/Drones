extends SceneTree
## Direct user report: "The drone team came under mortar fire. Now it is withdrawing. But given that it
## took no casualties, I don't understand why it is withdrawing. Relocating would be reasonable." Root
## cause: Unit._apply_crew_casualties' shared MORTAR/DRONE_TEAM branch only ever gave a MORTAR crew the
## option to hold position and relocate instead of fully withdrawing (_mortar_crew_holds_position) — a
## DRONE_TEAM fell straight through to order_retreat unconditionally, regardless of whether the hit that
## triggered it cost it anyone at all.
##
## Then, a direct correction on the first fix: "Fire at the drone team is not counter battery fire." The
## first attempt reused Unit.evading_counter_battery (a MORTAR-specific doctrine — a return shot drawn by
## its OWN firing) for the drone team's identical-shaped "hold and relocate" signal. Fixed with a
## separate, correctly-named Unit.taking_fire instead, used only for a DRONE_TEAM.
##
## Run: godot --headless --path . --script scripts/tests/test_drone_team_holds_after_harmless_hit.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
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
	bm.combat_log = Log.new()
	return bm

func run() -> void:
	test_a_harmless_hit_holds_position_not_a_full_retreat()
	test_the_drone_team_specific_flag_is_used_not_the_mortar_one()
	test_taking_fire_forces_relocation_even_with_no_visible_closing_threat()
	test_ordinary_evasion_trigger_still_works_without_taking_fire()
	print("Drone team holds-after-harmless-hit tests: %d failures" % failures)
	quit(1 if failures else 0)


## impact_distance = 1.0e6 (light-years past any real blast radius) makes _roll_crew_casualties'
## underlying blast_casualty_chance underflow to exactly 0.0 — deterministically zero casualties, not
## just an overwhelmingly likely one, so this test can never flake on the roll. No known enemy positions
## makes _mortar_crew_holds_position's own hold_chance exactly 1.0 (a full-strength crew, zero overrun
## risk) for the same reason.
func test_a_harmless_hit_holds_position_not_a_full_retreat() -> void:
	var bm = make_battle()
	var team: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2.ZERO)
	bm.player_units.append(team)
	check(team.crew_casualties == 0, "Set-up: untouched so far")
	team.take_hit(true, [], [], 1.0e6)
	check(team.crew_casualties == 0, "The hit genuinely cost it nobody")
	check(team.state == Unit.State.ACTIVE, "It holds position rather than withdrawing over a hit that hurt nobody")
	bm.combat_log.free()
	bm.free()


func test_the_drone_team_specific_flag_is_used_not_the_mortar_one() -> void:
	var bm = make_battle()
	var team: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2.ZERO)
	bm.player_units.append(team)
	team.take_hit(true, [], [], 1.0e6)
	check(team.taking_fire, "Sets its own taking_fire flag")
	check(not team.evading_counter_battery, "...and NOT evading_counter_battery — a drone team never fires anything, so nothing it takes is 'countering' a shot of its own")
	bm.combat_log.free()
	bm.free()


## _update_drone_team_evasion's own ordinary trigger only reacts to a currently VISIBLE, closing GROUND
## threat — a mortar shell lands from a tube that is very often neither. Without taking_fire forcing the
## issue, a crew that correctly held position after a harmless hit would otherwise just sit there forever,
## never actually relocating — "relocating would be reasonable" needs a real move order, not just "did not
## withdraw."
func test_taking_fire_forces_relocation_even_with_no_visible_closing_threat() -> void:
	var bm = make_battle()
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	var team: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2.ZERO)
	bm.player_units.append(team)
	bm.drone_team = team
	team.taking_fire = true
	# A known (but NOT currently visible, NOT closing) enemy mortar position — exactly what a shell landing
	# out of nowhere leaves behind: you know roughly where it came from, not a live, tracked threat closing in.
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(400.0, 0.0))
	bm.enemy_units.append(enemy)
	enemy.player_has_been_sighted = true
	enemy.player_known_position = enemy.global_position
	bm._update_drone_team_evasion()
	check(team.has_move_target, "It actually relocates, not just 'doesn't withdraw' (%s)" % team.last_order_reason)
	check(not team.taking_fire, "...and the flag is consumed once acted on")
	bm.combat_log.free()
	bm.free()


## Sanity/regression guard: the pre-existing trigger (a visible, closing ground threat) must still work
## on its own, with taking_fire false throughout.
func test_ordinary_evasion_trigger_still_works_without_taking_fire() -> void:
	var bm = make_battle()
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	var team: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2.ZERO)
	bm.player_units.append(team)
	bm.drone_team = team
	check(not team.taking_fire, "Set-up: untouched")
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(100.0, 0.0))
	bm.enemy_units.append(enemy)
	enemy.is_visible = true
	enemy.move_target = team.global_position
	enemy.has_move_target = true
	enemy.move_speed = 50.0
	# Also "known" (not just visible), so nearest_hidden_point's own destination search has something to
	# hide from — without this, the risk-roll can succeed but the search still comes up empty and no move
	# ever gets issued, for a reason that has nothing to do with the thing actually under test here.
	enemy.player_has_been_sighted = true
	enemy.player_known_position = enemy.global_position
	seed(4) # this trigger is itself a real, accepted risk-weighted roll — pin it so the test doesn't flake
	var moved := false
	for i in 20:
		bm._update_drone_team_evasion()
		if team.has_move_target:
			moved = true
			break
		team.has_move_target = false # in case a no-op branch set it without a real destination
	check(moved, "A visible, closing ground threat still triggers ordinary evasion with taking_fire never involved")
	bm.combat_log.free()
	bm.free()
