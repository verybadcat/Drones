extends SceneTree
## Guards a new behavior added at direct user request: "Mortar should be
## a primary target for the enemy forces. They should chase it when they
## get close. In the latest battle, they were dancing back and forth, but
## not really chasing."
##
## Root cause, traced directly: _next_advance_point's own bent-angle,
## cover/encirclement-scored candidates and its own ENEMY_SURROUND_
## STANDOFF_RADIUS stop distance are the right model for a squad closing
## on a STATIC objective (the village) under fire — not for running down
## a MOVING, actively evading one. Each fresh bound only gets recomputed
## once has_move_target clears, aimed at wherever the mortar happened to
## be at that moment — a mortar that keeps relocating between
## reassessments produces exactly the reported "dancing," with no
## guarantee of ever actually converging.
##
## Fix: BattleManager._chasing_mortar_in_hot_pursuit / _chase_mortar_
## directly — once a squad is within SQUAD_DANGER_RANGE of a known,
## ACTIVE friendly mortar, it re-aims directly at the mortar's CURRENT
## position every tick (bypassing the has_move_target gate entirely, the
## same "re-aims every tick" idiom already established for actual
## mortar-hunts-mortar pursuit), with no bent angle and no standoff
## distance, stopping only once within real engagement range.
##
## Run: godot --headless --path . --script scripts/tests/test_enemy_squad_mortar_pursuit.gd
const Orders = preload("res://scripts/unit_doctrine.gd")
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
	bm.unit_type_doctrines[Unit.Team.ENEMY] = Orders.sanitize({})
	return bm


## The exact reported shape: a squad already close to a known, active
## mortar must aim DIRECTLY at its current position, not a bent-angle
## advance-by-bounds candidate.
func test_close_squad_chases_mortar_directly() -> void:
	var bm = make_battle()
	var mortar_pos := Vector2(0, 0)
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, mortar_pos)
	bm.player_units.append(mortar)
	mortar.is_visible = true

	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, mortar_pos + Vector2(GameConfig.SQUAD_DANGER_RANGE * 0.5, 0))
	bm.enemy_units.append(squad)
	squad.sought_cover = true

	bm._update_enemy_squad_advance()
	check(squad.has_move_target, "A squad close to a known active mortar must be actively moving toward it")
	check(squad.move_target.distance_to(mortar_pos) < 1.0,
		"A squad in hot pursuit must aim directly at the mortar's own current position, not a bent-angle advance candidate (got %s)" % [squad.move_target])


## A squad far from the mortar (beyond SQUAD_DANGER_RANGE) must still use
## the ordinary measured advance-by-bounds — hot pursuit is specifically
## for a squad already close enough that running the target down
## outranks a cautious, cover-seeking approach.
func test_distant_squad_still_uses_bent_advance() -> void:
	var bm = make_battle()
	var mortar_pos := Vector2(0, 0)
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, mortar_pos)
	bm.player_units.append(mortar)
	mortar.is_visible = true

	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, mortar_pos + Vector2(GameConfig.SQUAD_DANGER_RANGE * 3.0, 0))
	bm.enemy_units.append(squad)
	squad.sought_cover = true

	bm._update_enemy_squad_advance()
	check(squad.has_move_target, "A distant squad with an objective must still advance")
	check(squad.move_target.distance_to(mortar_pos) > 1.0,
		"A squad far from the mortar must use the ordinary bent-angle advance candidate, not a direct hot-pursuit line to the mortar's exact position")


## A squad still executing its own wide flanking route must not switch to
## hot pursuit just because it happens to pass near the mortar en route —
## see _enemy_advance_objective's own doc comment: it hasn't actually
## arrived at the point where the mortar becomes its real objective yet.
func test_flanking_squad_does_not_hot_pursue() -> void:
	var bm = make_battle()
	var mortar_pos := Vector2(0, 0)
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, mortar_pos)
	bm.player_units.append(mortar)
	mortar.is_visible = true

	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, mortar_pos + Vector2(GameConfig.SQUAD_DANGER_RANGE * 0.5, 0))
	bm.enemy_units.append(squad)
	squad.sought_cover = true
	squad.flanking_route_active = true

	check(not bm._chasing_mortar_in_hot_pursuit(squad),
		"A squad still executing its own flanking route must not switch to hot pursuit of the mortar just because it's nearby")


## Real multi-tick verification, per this project's own established
## lesson: a single-call check can prove the AIM is correct without ever
## proving the squad actually GAINS on a moving target. Simulates the
## mortar relocating partway through the chase (exactly the reported
## scenario) and confirms the squad's own distance to it strictly
## decreases overall, rather than oscillating without real progress.
func test_hot_pursuit_actually_closes_the_gap_as_mortar_moves() -> void:
	var bm = make_battle()
	var mortar_pos := Vector2(0, 0)
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, mortar_pos)
	bm.player_units.append(mortar)
	mortar.is_visible = true

	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, mortar_pos + Vector2(GameConfig.SQUAD_DANGER_RANGE * 0.8, 0))
	bm.enemy_units.append(squad)
	squad.sought_cover = true
	squad.move_speed = GameConfig.ENEMY_ADVANCE_SPEED

	var start_dist: float = squad.global_position.distance_to(mortar.global_position)
	var ticks := 0
	# _tick_movement takes tactical scenario_delta, not raw real delta —
	# same real-per-frame-pacing trap this project's own mortar tests have
	# already hit (see test_mortar_evasion_balance.gd's own doc comment):
	# a coarse or unscaled delta here would need thousands of ticks to
	# cover any real distance at this project's own real m/s speeds.
	while ticks < 3000 and squad.global_position.distance_to(mortar.global_position) > GameConfig.SQUAD_ENGAGEMENT_RANGE:
		bm._update_enemy_squad_advance()
		bm._tick_movement((1.0 / 60.0) * bm._current_time_scale())
		# The mortar itself relocates partway through, exactly like a real
		# fleeing crew — the squad must keep re-aiming at its NEW position,
		# not the stale one it first saw.
		if ticks == 20:
			mortar.global_position += Vector2(-GameConfig.SQUAD_DANGER_RANGE * 0.3, 40)
		ticks += 1

	check(ticks < 3000, "The squad must actually close to engagement range on the mortar within a generous tick budget, not chase indefinitely")
	var end_dist: float = squad.global_position.distance_to(mortar.global_position)
	check(end_dist < start_dist,
		"The squad must end up genuinely closer to the mortar than it started (start=%.0f, end=%.0f) — real progress, not back-and-forth dancing" % [start_dist, end_dist])


## A second, live-reported bug alongside the first: "once it was adjacent,
## the enemy squad let the mortar get away... unless the enemy squad is
## under some sort of pressure (fire, etc), which it was not." Root cause:
## `_pick_target(u, player_units) != null` used to short-circuit this
## whole tier the instant the squad had ANY valid shot at all — including
## one at some UNARMED, non-threatening player unit merely nearby (a
## SPOTTER here — see test_division_of_labor_squad_stays_to_fight_real_
## threat below for the different, correct outcome once the "lesser"
## target is a real armed squad), not the mortar it was actively running
## down. A squad already in hot pursuit of a known mortar must keep
## closing on it even with an incidental, non-squad target also in range,
## rather than freezing on that and letting the mortar simply walk off
## unpursued.
func test_hot_pursuit_outranks_a_non_squad_shot_available() -> void:
	var bm = make_battle()
	var mortar_pos := Vector2(0, 0)
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, mortar_pos)
	bm.player_units.append(mortar)
	mortar.is_visible = true

	var squad_pos: Vector2 = mortar_pos + Vector2(GameConfig.SQUAD_DANGER_RANGE * 0.5, 0)
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, squad_pos)
	bm.enemy_units.append(squad)
	squad.sought_cover = true

	# An unarmed spotter well within engagement range and LOS — a real,
	# currently-shootable target, but not a real armed threat, and not the
	# mortar this squad is actively running down.
	var decoy: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, squad_pos + Vector2(GameConfig.SQUAD_ENGAGEMENT_RANGE * 0.2, 0))
	bm.player_units.append(decoy)
	decoy.is_visible = true

	check(bm._pick_target(squad, bm.player_units) != null,
		"Setup check: the decoy spotter must actually be a valid, in-range shot for this test to mean anything")

	bm._update_enemy_squad_advance()
	check(squad.has_move_target and squad.move_target.distance_to(mortar_pos) < 1.0,
		"A squad already in hot pursuit of a known mortar must keep closing directly on it even with a non-squad target also in range, not freeze on that and let the mortar go")


## Direct live follow-up: "Ten enemy squads were all chasing the mortar
## with friendly squads behind them. In a situation like that, it would be
## reasonable to have division of labor, with some enemy squads chasing
## the mortar and others fighting against the friendly squads." Unlike the
## spotter above, a real player SQUAD in range/LOS is a genuine armed
## threat — real infantry doesn't turn its back on a live firefight
## already in progress just to run past toward a different objective. This
## squad must stay and fight the real threat instead of chasing past it,
## even though it's also within hot-pursuit range of a known mortar.
func test_division_of_labor_squad_stays_to_fight_real_threat() -> void:
	var bm = make_battle()
	var mortar_pos := Vector2(0, 0)
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, mortar_pos)
	bm.player_units.append(mortar)
	mortar.is_visible = true

	var squad_pos: Vector2 = mortar_pos + Vector2(GameConfig.SQUAD_DANGER_RANGE * 0.5, 0)
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, squad_pos)
	bm.enemy_units.append(squad)
	squad.sought_cover = true

	var blocker: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, squad_pos + Vector2(GameConfig.SQUAD_ENGAGEMENT_RANGE * 0.2, 0))
	bm.player_units.append(blocker)
	blocker.is_visible = true

	check(bm._pick_target(squad, bm.player_units) == blocker,
		"Setup check: the blocking squad must actually be the resolved, in-range shot for this test to mean anything")
	check(bm._chasing_mortar_in_hot_pursuit(squad),
		"Setup check: this squad must also genuinely be within hot-pursuit range of the mortar — the real point of this test is that a real threat wins even then")

	bm._update_enemy_squad_advance()
	check(not squad.has_move_target,
		"A squad facing a real, in-range armed player squad must stay and fight it rather than pressing past toward the mortar, even while in hot-pursuit range")
	check(squad.last_order_reason.find(blocker.display_name()) != -1,
		"The squad's reason for holding must name the actual blocking squad, got '%s'" % squad.last_order_reason)


## The other half of division of labor: a DIFFERENT squad with no real
## armed threat actually contesting it must still press on toward the
## mortar — the fix above must not make every squad defensive just
## because a fight is happening somewhere else in the battle.
func test_division_of_labor_unengaged_squad_still_chases() -> void:
	var bm = make_battle()
	var mortar_pos := Vector2(0, 0)
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, mortar_pos)
	bm.player_units.append(mortar)
	mortar.is_visible = true

	# Within hot-pursuit range of the mortar, and with no other player unit
	# anywhere nearby to contest it.
	var squad_pos: Vector2 = mortar_pos + Vector2(GameConfig.SQUAD_DANGER_RANGE * 0.5, 0)
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, squad_pos)
	bm.enemy_units.append(squad)
	squad.sought_cover = true

	check(bm._pick_target(squad, bm.player_units) == null,
		"Setup check: this squad must have nothing in range to shoot at all for this test to mean anything")

	bm._update_enemy_squad_advance()
	check(squad.has_move_target and squad.move_target.distance_to(mortar_pos) < 1.0,
		"A squad with no real armed threat contesting it must still press its hot pursuit of the mortar")


## A direct live follow-up right after the fix above landed: "shooting at
## the mortar might make sense. But I'm not sure it was." There was no way
## to check — a squad holding to fight left no record of WHAT it was
## actually engaging. `_update_enemy_squad_advance` now names the real
## target directly in `last_order_reason` (already exposed by
## general_unit_debug_snapshot() for every unit) instead of leaving the
## reason blank/stale whenever this branch fires.
func test_staying_to_fight_names_the_actual_target() -> void:
	var bm = make_battle()
	var squad_pos := Vector2(0, 0)
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, squad_pos)
	bm.enemy_units.append(squad)
	squad.sought_cover = true

	var target: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, squad_pos + Vector2(GameConfig.SQUAD_ENGAGEMENT_RANGE * 0.2, 0))
	bm.player_units.append(target)
	target.is_visible = true

	check(bm._pick_target(squad, bm.player_units) == target,
		"Setup check: this must be a real, resolvable shot for the test to mean anything")

	bm._update_enemy_squad_advance()
	check(not squad.has_move_target, "Setup check: with nothing to chase and a real shot available, the squad must hold rather than advance")
	check(squad.last_order_reason.find(target.display_name()) != -1,
		"A squad holding to fight must name the actual target it's engaging in last_order_reason, not leave it blank or stale — got '%s'" % squad.last_order_reason)


## Direct live correction to the division-of-labor fix above: "Ten enemy
## squads were all chasing the mortar with friendly squads behind them...
## the enemy might send 2-3 to chase the mortar. But the rest would fight
## the friendly squads." With no friendly squad anywhere nearby to trigger
## the SQUAD-kind hold above, five squads all independently qualify for
## hot pursuit — only the closest MORTAR_HUNT_SQUAD_CAP (3) may actually
## be assigned to it; the other two must fall through to the ordinary
## advance-by-bounds logic instead of also converging on the mortar.
func test_mortar_hunt_caps_how_many_squads_chase_at_once() -> void:
	var bm = make_battle()
	var mortar_pos := Vector2(0, 0)
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, mortar_pos)
	bm.player_units.append(mortar)
	mortar.is_visible = true

	var squads: Array[Unit] = []
	for i in 5:
		# Distinct distances, all within SQUAD_DANGER_RANGE (hot-pursuit
		# range) but beyond SQUAD_ENGAGEMENT_RANGE — none of these five have
		# actually "arrived" yet (_chase_mortar_directly would otherwise
		# stop them outright once within engagement range, which would
		# defeat the point of this test), so ranking by distance to the
		# mortar is both unambiguous and meaningful.
		var pos: Vector2 = mortar_pos + Vector2(GameConfig.SQUAD_ENGAGEMENT_RANGE * 1.2 + GameConfig.SQUAD_ENGAGEMENT_RANGE * 0.4 * i, 0)
		var s: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, pos)
		s.sought_cover = true
		bm.enemy_units.append(s)
		squads.append(s)
		check(bm._chasing_mortar_in_hot_pursuit(s),
			"Setup check: squad %d must itself qualify for hot pursuit for this test to mean anything" % i)

	bm._update_enemy_squad_advance()

	var chasing_count := 0
	for i in squads.size():
		var s: Unit = squads[i]
		var is_chasing: bool = s.has_move_target and s.move_target.distance_to(mortar_pos) < 1.0
		if is_chasing:
			chasing_count += 1
		# Squads were built closest-to-farthest, so index order IS distance
		# order — the closest three (indices 0-2) must be the ones chasing.
		var should_chase: bool = i < GameConfig.MORTAR_HUNT_SQUAD_CAP
		check(is_chasing == should_chase,
			"Squad %d (the %s-closest to the mortar) chasing status was %s, expected %s" % [i, str(i + 1), is_chasing, should_chase])
	check(chasing_count == GameConfig.MORTAR_HUNT_SQUAD_CAP,
		"Exactly MORTAR_HUNT_SQUAD_CAP (%d) squads must be chasing the mortar at once, got %d" % [GameConfig.MORTAR_HUNT_SQUAD_CAP, chasing_count])


func run() -> void:
	test_close_squad_chases_mortar_directly()
	test_distant_squad_still_uses_bent_advance()
	test_flanking_squad_does_not_hot_pursue()
	test_hot_pursuit_actually_closes_the_gap_as_mortar_moves()
	test_hot_pursuit_outranks_a_non_squad_shot_available()
	test_division_of_labor_squad_stays_to_fight_real_threat()
	test_division_of_labor_unengaged_squad_still_chases()
	test_staying_to_fight_names_the_actual_target()
	test_mortar_hunt_caps_how_many_squads_chase_at_once()
	print("Enemy squad mortar-pursuit tests: %d failures" % failures)
	quit(1 if failures else 0)
