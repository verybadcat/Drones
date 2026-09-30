extends SceneTree
## Guards a direct user correction after a live incident: an enemy squad
## given a genuine "run the mortar down directly" pursuit (this same
## session's own hot-pursuit fix) closed in and destroyed the crew before
## it ever started running. BattleManager._unwatched_threat_closing used
## to additionally require genuine direct line of sight from the known
## threat to the mortar before counting it as "closing" — a squad
## approaching from behind a building or treeline could be well inside
## real danger range without ever registering, so the crew never reacted
## in time.
##
## Direct user correction: "Raise the numeric threshold to 750 meters.
## Also remove the LOS requirement. It's enough if you know they are
## there, or even if you recently knew they were there."
##
## Run: godot --headless --path . --script scripts/tests/test_unwatched_threat_closing.gd
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


## A known enemy within MORTAR_CREW_OVERRUN_DANGER_RANGE (750m) but with
## NO direct line of sight (blocked by a real building on the default
## map) must still count as closing — the core of the fix.
func test_known_threat_blocked_by_los_still_counts_as_closing() -> void:
	var bm = make_battle()
	# A real building on the default map, verified directly to block LOS
	# between these two exact points.
	var mortar_pos := Vector2(262, 350)
	var enemy_pos := Vector2(338, 350)
	check(not GameConfig.has_direct_los(enemy_pos, mortar_pos),
		"Test setup check: these two points must be genuinely LOS-blocked by the building between them for this test to mean anything")
	check(mortar_pos.distance_to(enemy_pos) <= GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE,
		"Test setup check: these two points must be within MORTAR_CREW_OVERRUN_DANGER_RANGE for this test to mean anything")

	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, mortar_pos)
	bm.player_units.append(mortar)
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, enemy_pos)
	bm.enemy_units.append(enemy)
	enemy.player_has_been_sighted = true
	enemy.player_known_position = enemy_pos

	check(bm._unwatched_threat_closing(mortar),
		"A known enemy within real danger range, even one currently blocked by terrain from direct LOS, must still count as an approaching threat")


## A known enemy beyond MORTAR_CREW_OVERRUN_DANGER_RANGE (750m) must not
## count as closing — the range itself is still a real, meaningful bound,
## not removed entirely along with the LOS requirement.
func test_known_threat_beyond_range_does_not_count_as_closing() -> void:
	var bm = make_battle()
	var mortar_pos := Vector2(0, 0)
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, mortar_pos)
	bm.player_units.append(mortar)
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, mortar_pos + Vector2(GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE * 1.5, 0))
	bm.enemy_units.append(enemy)
	enemy.player_has_been_sighted = true
	enemy.player_known_position = enemy.global_position

	check(not bm._unwatched_threat_closing(mortar),
		"A known enemy well beyond MORTAR_CREW_OVERRUN_DANGER_RANGE must not count as closing")


func run() -> void:
	test_known_threat_blocked_by_los_still_counts_as_closing()
	test_known_threat_beyond_range_does_not_count_as_closing()
	test_a_known_spotter_never_counts_as_an_overrun_threat()
	test_a_live_spotter_never_counts_as_an_overrun_threat_either()
	print("Unwatched-threat-closing tests: %d failures" % failures)
	quit(1 if failures else 0)


## Direct user ruling: "If the enemy has not seen the spotter, the spotter should have no effect on their
## actions." Confirmed as still true here for the OTHER direction too: even once seen, a spotter has no
## weapon and cannot overrun a crew any more than a drone can (already excluded from this exact check) —
## so a known spotter well within the same range a squad would trigger this at must never count as closing.
func test_a_known_spotter_never_counts_as_an_overrun_threat() -> void:
	var bm = make_battle()
	var mortar_pos := Vector2(0, 0)
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, mortar_pos)
	bm.player_units.append(mortar)
	var spotter_pos := mortar_pos + Vector2(GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE * 0.3, 0) # well within range
	var spotter: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SPOTTER, spotter_pos)
	bm.enemy_units.append(spotter)
	spotter.player_has_been_sighted = true
	spotter.player_known_position = spotter_pos
	check(not bm._unwatched_threat_closing(mortar), "A known spotter well within overrun-danger range must not count as an approaching threat")
	# Control: a real squad at the identical position and distance does count — confirms the exclusion is
	# specific to the spotter's own kind, not an accidental change to the range or distance math.
	bm.enemy_units.erase(spotter)
	spotter.free()
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, spotter_pos)
	bm.enemy_units.append(squad)
	squad.player_has_been_sighted = true
	squad.player_known_position = spotter_pos
	check(bm._unwatched_threat_closing(mortar), "Control: a real squad at the identical spot and distance does count")


## The same exclusion for the LIVE (this-instant, same-tick) branch of the check, not just the
## remembered-knowledge one above.
func test_a_live_spotter_never_counts_as_an_overrun_threat_either() -> void:
	var bm = make_battle()
	var mortar_pos := Vector2(0, 0)
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, mortar_pos)
	bm.player_units.append(mortar)
	var spotter: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SPOTTER, mortar_pos + Vector2(GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE * 0.3, 0))
	bm.enemy_units.append(spotter)
	spotter.is_visible = true # live, this same tick — no player_known_position set at all
	check(not bm._nearby_opposing_unit_within(mortar, GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE, true), "A live spotter sighting this same tick must not count as an approaching threat")
