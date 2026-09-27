extends SceneTree
## Direct user report, live: "drone was going back and forth a lot just now." Confirmed against the user's
## own actual running battle (this project's established diagnostic method — reading the live debug
## snapshots), not a synthetic guess: the drone, mid-leg on an ordinary routine-recon commitment, abruptly
## reversed toward an enemy squad's last-known position under the tier "Regaining contact with a lost
## squad," then reversed right back to routine recon again within a handful of seconds, the squad never
## having actually stayed lost.
##
## Root cause: `_lost_squad_contacts` drops a squad from its list the instant it is `is_visible` again —
## correct on its own (it genuinely isn't "lost" that exact tick) — but that makes its "lost:%d" key vanish
## from `_drone_routine_recon_target`'s shared candidate pool for that one tick. `_drone_commitment_has_
## collapsed`'s sticky-until-arrival protection only ever runs when the CURRENT committed key is still
## present to compare against (see `_drone_routine_recon_target`'s own `current.is_empty()` branch) — a
## vanished key skips that check entirely and forces a fresh, unprotected pick. The instant the squad drops
## from sight again (often the very next tick — a real, ordinary LOS blink through a tree edge, a building
## corner, or the edge of detection range, not a malfunction), `player_known_position_time` resets to that
## instant, so it reappears in the pool as if freshly lost all over again, at LOST_CONTACT_VALUE_MAX — well
## above an ordinary sweep cell — legitimately winning the next fresh pick outright.
##
## Fix: `LOST_CONTACT_MIN_AGE_S` — a bare, momentary loss (age under this) is not yet eligible as a lost-
## contact candidate at all, the same "give a signal a moment to prove itself" reasoning
## TREE_SIGHT_LOSS_GRACE_S already applies to what counts as still seeing a target, generalized here to the
## drone's own reaction to losing one.
##
## Run: godot --headless --path . --script scripts/tests/test_drone_lost_contact_flicker.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(v: float) -> float:
	return v * GameConfig.PIXELS_PER_METER

## No friendly mortar (so _flank_watch_candidates is empty, matching test_drone_no_dithering.gd's own
## setup) — an ordinary sweep-only routine recon commitment is all that's needed to reproduce this.
func make_battle():
	var w := Weather.new()
	w.wind_speed_10m = 0.0
	w.temperature_c = 10.0
	w._gust_z = 0.0
	w.rng.seed = 1
	Weather.current = w
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.weather = w
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	bm.drone_team = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2(m(-800), m(1500)))
	bm.player_units.append(bm.drone_team)
	var d: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(m(0), m(1500)))
	bm.player_units.append(d)
	d.drone_battery_charge = 0.9
	bm.active_drone = d
	bm.scenario_elapsed_time = 2000.0
	return bm

func cleanup(bm) -> void:
	bm.combat_log.free()
	bm.free()

func run() -> void:
	test_a_bare_momentary_loss_is_not_immediately_chased()
	test_a_sustained_loss_past_the_minimum_is_still_chased()
	test_rapid_flicker_never_interrupts_a_committed_recon_leg()
	test_a_genuinely_sustained_loss_can_still_interrupt_recon()
	print("Drone lost-contact flicker tests: %d failures" % failures)
	quit(1 if failures else 0)


## The direct, isolated case: a squad that went out of sight a fraction of a second ago must not
## immediately read as a "lost contact" worth flying to, however good a candidate it would otherwise be.
func test_a_bare_momentary_loss_is_not_immediately_chased() -> void:
	var bm = make_battle()
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(m(2200), m(1500))) # near our forces
	bm.enemy_units.append(squad)
	squad.is_visible = false
	squad.player_has_been_sighted = true
	squad.player_known_position = squad.global_position
	squad.player_known_state = Unit.State.ACTIVE
	squad.player_known_position_time = bm.scenario_elapsed_time - 0.5 # lost half a second ago
	check(bm._lost_squad_contacts().is_empty(), "A bare, half-second-old loss must not appear as a lost contact at all")
	bm._drone_search_target()
	check(bm._drone_pilot_reasoning.get("tier", "") != "Regaining contact with a lost squad", "...and must not win the tier either (%s)" % str(bm._drone_pilot_reasoning.get("tier", "")))
	cleanup(bm)


## Once the loss has actually persisted past the minimum, it is a real lead again — unchanged behavior for
## everything past the new floor (the existing suite's own much-older-sighting cases already cover this,
## this just nails down the boundary itself).
func test_a_sustained_loss_past_the_minimum_is_still_chased() -> void:
	var bm = make_battle()
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(m(2200), m(1500)))
	bm.enemy_units.append(squad)
	squad.is_visible = false
	squad.player_has_been_sighted = true
	squad.player_known_position = squad.global_position
	squad.player_known_state = Unit.State.ACTIVE
	squad.player_known_position_time = bm.scenario_elapsed_time - (BattleManager.LOST_CONTACT_MIN_AGE_S + 1.0)
	check(not bm._lost_squad_contacts().is_empty(), "Setup: a loss safely past the minimum age must appear as a lost contact")
	bm._drone_search_target()
	check(bm._drone_pilot_reasoning.get("tier", "") == "Regaining contact with a lost squad", "...and win the tier when nothing else outranks it (%s)" % str(bm._drone_pilot_reasoning.get("tier", "")))
	cleanup(bm)


## The actual reported shape, reproduced directly: the drone flying a real, committed sweep leg while a
## nearby enemy squad flickers in and out of sight every few (simulated) seconds — always well under the
## minimum age between blinks, so it never accumulates a real loss. Same reversal-counting methodology as
## test_drone_no_dithering.gd's own live-report reproduction.
func test_rapid_flicker_never_interrupts_a_committed_recon_leg() -> void:
	var bm = make_battle()
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(m(2200), m(1500)))
	bm.enemy_units.append(squad)
	squad.player_has_been_sighted = true
	squad.player_known_state = Unit.State.ACTIVE
	squad.is_visible = false
	squad.player_known_position = squad.global_position
	squad.player_known_position_time = bm.scenario_elapsed_time # starts "just lost"

	var d: Unit = bm.active_drone
	var last := ""
	var switches := 0
	var steps_since_switch := 0
	var shortest_leg := 9999
	for i in 400:
		bm.scenario_elapsed_time += 1.0
		# Flickers visible every 5 simulated seconds, comfortably under LOST_CONTACT_MIN_AGE_S (8s) — a
		# real squad's momentary reappearance through a tree gap or around a corner, not a sustained loss.
		var visible_this_tick: bool = i % 5 == 0
		squad.is_visible = visible_this_tick
		if visible_this_tick:
			squad.player_known_position = squad.global_position
			squad.player_known_position_time = bm.scenario_elapsed_time
		var pick: Dictionary = bm._drone_routine_recon_target(bm._flank_watch_candidates())
		if pick.is_empty():
			break
		check(not pick.key.begins_with("lost:"), "A flicker that never accumulates past the minimum age must never win as a lost contact (tick %d, key %s)" % [i, pick.key])
		if pick.key != last:
			if last != "":
				switches += 1
				shortest_leg = mini(shortest_leg, steps_since_switch)
			steps_since_switch = 0
			last = pick.key
		steps_since_switch += 1
		var to: Vector2 = pick.point - d.global_position
		d.global_position += to.normalized() * minf(m(25.0), to.length())
	check(switches <= 15, "The drone must fly real legs despite the flicker, not dither: %d destination changes in 400 steps" % switches)
	check(shortest_leg >= 10, "No leg may be abandoned within a few steps of being chosen because of the flicker (shortest %d steps)" % shortest_leg)
	cleanup(bm)


## The other side of the same fix: a squad that flickers only rarely enough that a real gap opens up past
## the minimum age is still allowed to pull the drone's attention — the fix narrows the window that counts
## as "lost," it does not disable the mechanism.
func test_a_genuinely_sustained_loss_can_still_interrupt_recon() -> void:
	var bm = make_battle()
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(m(2200), m(1500)))
	bm.enemy_units.append(squad)
	squad.player_has_been_sighted = true
	squad.player_known_state = Unit.State.ACTIVE
	squad.is_visible = false
	squad.player_known_position = squad.global_position
	squad.player_known_position_time = bm.scenario_elapsed_time

	var d: Unit = bm.active_drone
	var saw_lost_tier := false
	for i in 60:
		bm.scenario_elapsed_time += 1.0
		var pick: Dictionary = bm._drone_routine_recon_target(bm._flank_watch_candidates())
		if pick.is_empty():
			break
		if pick.key.begins_with("lost:"):
			saw_lost_tier = true
			break
		var to: Vector2 = pick.point - d.global_position
		d.global_position += to.normalized() * minf(m(25.0), to.length())
	check(saw_lost_tier, "A squad that stays genuinely lost (never reappearing at all) must still eventually pull the drone's attention")
	cleanup(bm)
