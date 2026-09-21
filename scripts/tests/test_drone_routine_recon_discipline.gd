extends SceneTree
## Guards three live-reported drone problems:
##  - "the drone is flying towards a faraway enemy squad, after passing by
##    close and dangerous squads": (a) a routine-recon destination whose value
##    collapsed after the drone set out (its mortar was destroyed) stayed
##    committed until arrival, and (b) the routine tier was scored at the
##    standing FLANK-WATCH priority even when its pick was a far general-area
##    sweep cell, so it beat tracking a squad near our mortar or forces.
##  - "the previous drone hung over the bottom right way too long": a visible
##    contact refreshed itself every tick, so the cells around it kept full
##    contact bonus for as long as it stayed in view.
##
## Run: godot --headless --path . --script scripts/tests/test_drone_routine_recon_discipline.gd
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

func friendly(bm, kind: Unit.Kind, pos: Vector2) -> Unit:
	var u: Unit = bm._make_unit(Unit.Team.PLAYER, kind, pos)
	bm.player_units.append(u)
	return u

func enemy(bm, kind: Unit.Kind, pos: Vector2, visible := true) -> Unit:
	var u: Unit = bm._make_unit(Unit.Team.ENEMY, kind, pos)
	bm.enemy_units.append(u)
	u.is_visible = visible
	bm._update_player_intel()
	return u

func m(meters: float) -> float:
	return meters * GameConfig.PIXELS_PER_METER


func test_collapsed_commitment_is_dropped_but_a_fair_one_is_kept() -> void:
	var bm = make_battle()
	friendly(bm, Unit.Kind.SQUAD, Vector2(m(2000), m(1500)))
	bm.active_drone = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(m(3500), m(2000)))
	var far := {"key": "sweep:99", "point": Vector2(m(4950), m(2450)), "value": 0.02}
	var good := {"key": "sweep:1", "point": Vector2(m(1550), m(1750)), "value": 0.6}
	check(bm._drone_commitment_has_collapsed(far, [far, good]), "A far cell worth 0.02 against a 0.6 cell must be dropped mid-flight")
	var comparable := {"key": "sweep:2", "point": Vector2(m(4100), m(1750)), "value": 0.5}
	check(not bm._drone_commitment_has_collapsed(comparable, [comparable, good]), "A comparable option must stay committed (no dithering)")
	check(not bm._drone_commitment_has_collapsed(far, [far]), "With no alternative there is nothing to switch to")

	# End to end: the collapsed target is replaced, and is not counted as a visit.
	bm._drone_current_destination_key = "sweep:99"
	var arrivals_before: int = bm._empty_sweep_arrivals
	var pick: Dictionary = bm._drone_routine_recon_target([far, good])
	check(pick.key != "sweep:99", "The routine target must move off a collapsed commitment (got %s)" % pick.key)
	check(bm._empty_sweep_arrivals == arrivals_before, "Dropping a commitment mid-flight is not an empty-sweep visit")
	check(not bm._drone_destination_last_visited.has("sweep:99"), "Nor is it stamped as visited")


## The mortar-flank duty (30) must not carry a far sweep pick past a real squad
## next to the mortar; a real flank check still does.
func test_far_sweep_pick_does_not_outrank_a_squad_near_the_mortar() -> void:
	var bm = make_battle()
	var mortar: Unit = friendly(bm, Unit.Kind.MORTAR, Vector2(m(300), m(1700)))
	friendly(bm, Unit.Kind.SQUAD, Vector2(m(2000), m(1700)))
	enemy(bm, Unit.Kind.SQUAD, Vector2(m(950), m(1700))) # ~650m from the mortar, visible
	bm.active_drone = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(m(1000), m(1700)))
	# Every flank gap was just checked, so the pool's best pick is a sweep cell.
	var flanks: Array = bm._flank_watch_candidates()
	check(not flanks.is_empty(), "Setup check: flank gaps must be on offer")
	for f in flanks:
		bm._drone_destination_last_visited[f.key] = bm.scenario_elapsed_time
	bm._drone_search_target()
	var tier: String = bm._drone_pilot_reasoning.tier
	check(tier == "Tracking dangerous squad",
		"A far sweep must not beat tracking a squad ~650m from our mortar (tier: %s, %s)" % [tier, bm._drone_pilot_reasoning.detail])

	# A real flank check still holds its standing priority over squad tracking.
	var bm2 = make_battle()
	friendly(bm2, Unit.Kind.MORTAR, Vector2(m(300), m(1700)))
	friendly(bm2, Unit.Kind.SQUAD, Vector2(m(2000), m(1700)))
	enemy(bm2, Unit.Kind.SQUAD, Vector2(m(950), m(1700)))
	bm2.active_drone = bm2._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(m(1000), m(1700)))
	for c in bm2._sweep_candidates():
		bm2._drone_destination_last_visited[c.key] = bm2.scenario_elapsed_time # so the flank gap is the pool's best
	bm2._drone_search_target()
	check(bm2._drone_pilot_reasoning.tier == "Routine background recon" and "flank" in bm2._drone_pilot_reasoning.detail,
		"An open flank gap must still take priority (tier: %s, %s)" % [bm2._drone_pilot_reasoning.tier, bm2._drone_pilot_reasoning.detail])


func test_a_contact_in_continuous_view_loses_its_pull() -> void:
	var bm = make_battle()
	friendly(bm, Unit.Kind.SQUAD, Vector2(m(500), m(1700)))
	var squad: Unit = enemy(bm, Unit.Kind.SQUAD, Vector2(m(4500), m(3000)))
	var cell := Vector2(m(4500), m(3000))
	bm.scenario_elapsed_time = 100.0
	bm._update_recent_enemy_contacts()
	var fresh: float = bm._contact_search_bonus(cell)
	check(fresh > GameConfig.DRONE_CONTACT_BONUS_VALUE * 0.9, "First sight gives the full bonus (got %.3f)" % fresh)
	bm.scenario_elapsed_time = 100.0 + GameConfig.DRONE_CONTACT_WATCH_FADE_S
	bm._update_recent_enemy_contacts()
	var watched: float = bm._contact_search_bonus(cell)
	check(watched < fresh * (GameConfig.DRONE_CONTACT_WATCH_FLOOR + 0.05), "After the fade window in continuous view the bonus must be near the floor (%.3f vs %.3f)" % [watched, fresh])
	check(watched > 0.0, "It never fades to nothing")
	# Losing sight restarts the clock: a squad that reappears is fresh news again.
	squad.is_visible = false
	bm.scenario_elapsed_time += 10.0
	bm._update_recent_enemy_contacts()
	squad.is_visible = true
	bm.scenario_elapsed_time += 10.0
	bm._update_recent_enemy_contacts()
	check(bm._contact_search_bonus(cell) > fresh * 0.9, "A contact re-acquired after a break must be at full strength again (got %.3f)" % bm._contact_search_bonus(cell))


func run() -> void:
	test_collapsed_commitment_is_dropped_but_a_fair_one_is_kept()
	test_far_sweep_pick_does_not_outrank_a_squad_near_the_mortar()
	test_a_contact_in_continuous_view_loses_its_pull()
	print("Drone routine recon discipline tests: %d failures" % failures)
	quit(1 if failures else 0)
