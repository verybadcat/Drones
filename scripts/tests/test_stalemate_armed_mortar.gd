extends SceneTree
## Guards a direct user correction from a real battle: "the stalemate code
## must have triggered. But does the enemy still have a mortar? ... If the
## enemy has a mortar, the stalemate should not trigger." STAGNATION_TIMEOUT's
## own doc comment already assumed the stalemate case meant "both mortars
## gone" without the code ever checking it — an ACTIVE mortar with rounds
## left can sit stationary and hold fire (no target, conserving ammo) for far
## longer than the 15-second timeout without the battle actually being
## decided: it can still fire the instant a target appears. BattleManager.
## _check_battle_end now also requires no ACTIVE mortar, either side, still
## has rounds before calling it a stalemate.
##
## Run: godot --headless --path . --script scripts/tests/test_stalemate_armed_mortar.gd
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

## A completely static scene: one ACTIVE player squad, one ACTIVE enemy
## squad, neither moving nor able to fire (out of range of each other), so
## _anyone_moving() is false and no shots ever land — the only thing that
## can still distinguish "genuine stalemate" from "an armed mortar is
## waiting" is the mortar itself.
func setup_static_standoff(bm) -> void:
	var p_squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(0, 0))
	bm.player_units.append(p_squad)
	var e_squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(10000, 0)) # far out of engagement range
	bm.enemy_units.append(e_squad)
	bm._seconds_since_last_shot = BattleManager.STAGNATION_TIMEOUT + 1.0


func test_no_stalemate_while_an_active_mortar_still_has_rounds() -> void:
	var bm = make_battle()
	setup_static_standoff(bm)
	var mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(9500, 0))
	bm.enemy_units.append(mortar)
	mortar.mortar_rounds_remaining = 6
	check(not bm._anyone_moving(), "Setup check: nothing is moving")
	bm._check_battle_end()
	check(not bm.battle_over, "An ACTIVE enemy mortar with rounds left must not let a stalemate end the battle")


func test_a_player_mortar_with_rounds_also_blocks_the_stalemate() -> void:
	var bm = make_battle()
	setup_static_standoff(bm)
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(-500, 0))
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = 20
	bm._check_battle_end()
	check(not bm.battle_over, "The same standard applies to the player's own armed mortar")


func test_stalemate_still_ends_once_the_mortar_is_dry() -> void:
	var bm = make_battle()
	setup_static_standoff(bm)
	var mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(9500, 0))
	bm.enemy_units.append(mortar)
	mortar.mortar_rounds_remaining = 0
	bm._check_battle_end()
	check(bm.battle_over, "With no ammo left anywhere, a genuine stalemate must still end the battle as before")


func test_a_destroyed_or_withdrawn_mortar_does_not_count_even_with_rounds_on_the_books() -> void:
	var bm = make_battle()
	setup_static_standoff(bm)
	var destroyed_mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(9500, 0))
	bm.enemy_units.append(destroyed_mortar)
	destroyed_mortar.mortar_rounds_remaining = 6
	destroyed_mortar.state = Unit.State.DESTROYED
	var withdrawn_mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(-500, 0))
	bm.player_units.append(withdrawn_mortar)
	withdrawn_mortar.mortar_rounds_remaining = 20
	withdrawn_mortar.state = Unit.State.WITHDRAWN
	check(not bm._any_armed_mortar_remains(), "Setup check: a destroyed crew or a mortar safely off the field can never fire again, regardless of rounds on the books")
	bm._check_battle_end()
	check(bm.battle_over, "Ammo left on a mortar that can no longer fire (destroyed or withdrawn) must not itself block the stalemate")


## Direct user correction from a later real battle: "The player has a mortar. It
## is currently out of ammo, but that's not a reason to let stalemate happen."
## A dry ACTIVE crew is waiting on its resupply (always on order once contact is
## made) and will fire again, so the battle is not decided.
func test_a_dry_mortar_with_a_resupply_on_order_blocks_the_stalemate() -> void:
	for team in [Unit.Team.PLAYER, Unit.Team.ENEMY]:
		var bm = make_battle()
		setup_static_standoff(bm)
		var mortar: Unit = bm._make_unit(team, Unit.Kind.MORTAR, Vector2(-500, 0) if team == Unit.Team.PLAYER else Vector2(9500, 0))
		(bm.player_units if team == Unit.Team.PLAYER else bm.enemy_units).append(mortar)
		mortar.mortar_rounds_remaining = 0
		bm._mortar_resupply[mortar] = {"arrival_time": bm.scenario_elapsed_time + 3000.0, "warning_time": 0.0, "warned": false, "staged": false}
		var side := "player" if team == Unit.Team.PLAYER else "enemy"
		check(bm._any_armed_mortar_remains(), "%s: an out-of-ammo ACTIVE mortar with a resupply on order still counts as in the fight" % side)
		bm._check_battle_end()
		check(not bm.battle_over, "%s: out of ammunition, with resupply coming, is not a reason to call a stalemate" % side)


## ...through the real pipeline, for either side (user: "an enemy mortar waiting
## for ammo would also prevent a stalemate"): contact made, the request goes out,
## and a dry mortar is then protected until the crew is gone.
func test_the_real_resupply_request_is_what_protects_a_dry_mortar() -> void:
	for team in [Unit.Team.PLAYER, Unit.Team.ENEMY]:
		var side := "player" if team == Unit.Team.PLAYER else "enemy"
		var bm = make_battle()
		setup_static_standoff(bm)
		var mortar: Unit = bm._make_unit(team, Unit.Kind.MORTAR, Vector2(-500, 0) if team == Unit.Team.PLAYER else Vector2(9500, 0))
		(bm.player_units if team == Unit.Team.PLAYER else bm.enemy_units).append(mortar)
		mortar.mortar_rounds_remaining = 0
		check(not bm._any_armed_mortar_remains(), "%s: setup: dry, and no contact yet so nothing on order: not armed" % side)
		if team == Unit.Team.PLAYER:
			bm._player_sighted_enemy = true
		else:
			bm._enemy_sighted_enemy = true
		check(bm.request_mortar_resupply(mortar), "%s: setup: with contact, the request goes out" % side)
		check(bm._any_armed_mortar_remains(), "%s: a dry mortar with the requested resupply counts" % side)
		bm._check_battle_end()
		check(not bm.battle_over, "%s: ...so the standoff is not a stalemate" % side)
		mortar.state = Unit.State.DESTROYED
		check(not bm._any_armed_mortar_remains(), "%s: once the crew is gone the pending resupply no longer counts" % side)
		bm._check_battle_end()
		check(bm.battle_over, "%s: ...and the stalemate can end the battle as before" % side)


func run() -> void:
	test_a_dry_mortar_with_a_resupply_on_order_blocks_the_stalemate()
	test_the_real_resupply_request_is_what_protects_a_dry_mortar()
	test_no_stalemate_while_an_active_mortar_still_has_rounds()
	test_a_player_mortar_with_rounds_also_blocks_the_stalemate()
	test_stalemate_still_ends_once_the_mortar_is_dry()
	test_a_destroyed_or_withdrawn_mortar_does_not_count_even_with_rounds_on_the_books()
	print("Stalemate armed-mortar tests: %d failures" % failures)
	quit(1 if failures else 0)
