extends SceneTree
## Direct user report: "Just now, the drone team was cornered by an enemy squad. I know I objected to a
## drone team retreat earlier. But the recent situation is one where they would have retreated even
## without casualties, because they had nowhere else to go to escape."
##
## Root cause: _update_drone_team_evasion's own hiding search (GameConfig.nearest_hidden_point), finding
## no better spot than where the team already stood, used to just `return` — "try again next tick." That
## comment assumed a later attempt might find somewhere better, but a squad actively closing the distance
## every tick doesn't leave a better hiding spot to discover later; it only gets closer. The team just sat
## there until it was overrun.
##
## Fix: when the hiding search comes up completely empty AND the trigger was a real, closing GROUND threat
## (not a bare taking_fire with nothing actually closing in — a mortar shell can land with no one nearby to
## physically overrun the crew, so that case still retries next tick, unchanged), the team now orders a
## full withdrawal instead — mirroring the mortar's own last-resort flee (_mortar_flee_as_last_resort) when
## ITS OWN concealment search comes up empty under real pressure.
##
## Run: godot --headless --path . --script scripts/tests/test_drone_team_cornered_retreats.gd
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
	test_cornered_by_a_closing_squad_with_nowhere_to_hide_retreats()
	test_taking_fire_alone_with_nowhere_to_hide_still_just_retries()
	test_a_closing_squad_with_somewhere_to_hide_still_just_relocates()
	print("Drone team cornered-retreats tests: %d failures" % failures)
	quit(1 if failures else 0)


## GameConfig.nearest_hidden_point's own first line returns `from` unchanged whenever there are no KNOWN
## threat positions to hide from at all — even if something is currently is_visible (the risk trigger's own
## check) but not yet "known" (Unit.player_has_been_sighted, a separate, stickier flag _update_player_intel
## sets later in the SAME tick, after _update_drone_team_evasion already ran — the real, first-contact-tick
## ordering this reproduces, not an artificial gap). That combination — a real, closing, currently-visible
## threat with nothing yet "known" to search a hiding spot away from — is a genuine, reachable "nowhere to
## hide" case on the very tick contact is first made.
func test_cornered_by_a_closing_squad_with_nowhere_to_hide_retreats() -> void:
	var bm = make_battle()
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	var team: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2.ZERO)
	bm.player_units.append(team)
	bm.drone_team = team
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(100.0, 0.0))
	bm.enemy_units.append(enemy)
	enemy.is_visible = true
	enemy.move_target = team.global_position
	enemy.has_move_target = true
	enemy.move_speed = 50.0
	# Deliberately NOT marked player_has_been_sighted/player_known_position — see this test's own doc
	# comment on why that's the real, reachable "nothing known yet to hide from" case.
	seed(4) # the risk trigger is its own accepted risk-weighted roll — pin it so the test doesn't flake
	var retreated := false
	for i in 20:
		bm._update_drone_team_evasion()
		if team.state == Unit.State.RETREATING:
			retreated = true
			break
	check(retreated, "A drone team cornered by a real, closing squad with nowhere to hide retreats, rather than sitting there (state=%s)" % Unit.State.keys()[team.state])
	bm.combat_log.free()
	bm.free()


## The flip side, explicitly guarded: taking_fire alone (a shell landed, nothing physically closing in)
## must NOT escalate to a full retreat just because the hiding search comes up empty — there's no one
## there to actually overrun the crew. It keeps retrying next tick, same as before this fix.
func test_taking_fire_alone_with_nowhere_to_hide_still_just_retries() -> void:
	var bm = make_battle()
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	var team: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2.ZERO)
	bm.player_units.append(team)
	bm.drone_team = team
	team.taking_fire = true
	# No known enemy positions at all (a shell landed; nothing is currently sighted/known) — the same
	# GameConfig.nearest_hidden_point first-line trivial case the squad test above reproduces via the
	# sighting-order gap: with no threats to search a standoff distance from, it returns the team's own
	# current position unchanged, every time, regardless of geometry.
	bm._update_drone_team_evasion()
	check(team.state == Unit.State.ACTIVE, "taking_fire alone, with nowhere to hide, does NOT retreat")
	check(team.taking_fire, "...the flag stays set to retry next tick, exactly as before this fix")
	bm.combat_log.free()
	bm.free()


## Regression guard: a closing squad with a REAL hiding spot available must still just relocate (the
## existing, correct behavior) rather than this fix over-triggering a retreat whenever anything is simply
## closing in.
func test_a_closing_squad_with_somewhere_to_hide_still_just_relocates() -> void:
	var bm = make_battle()
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	var team: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2.ZERO)
	bm.player_units.append(team)
	bm.drone_team = team
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(100.0, 0.0))
	bm.enemy_units.append(enemy)
	enemy.is_visible = true
	enemy.move_target = team.global_position
	enemy.has_move_target = true
	enemy.move_speed = 50.0
	enemy.player_has_been_sighted = true
	enemy.player_known_position = enemy.global_position
	seed(4)
	var moved := false
	for i in 20:
		bm._update_drone_team_evasion()
		if team.has_move_target:
			moved = true
			break
		team.has_move_target = false
	check(moved, "A closing squad with a real hiding spot available still just relocates")
	check(team.state == Unit.State.ACTIVE, "...rather than retreating, when relocating is actually possible")
	bm.combat_log.free()
	bm.free()
