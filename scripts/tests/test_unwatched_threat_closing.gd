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
	print("Unwatched-threat-closing tests: %d failures" % failures)
	quit(1 if failures else 0)
