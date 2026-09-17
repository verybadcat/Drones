extends SceneTree
## Guards a real, live incident: the user's own friendly mortar got hit
## shortly after firing. Direct follow-up correction: "Right after firing,
## getting away from firing point should be top priority if there are
## enemy mortars... only nearby enemy squads should [outrank it], or the
## edge of the map." Then: "the top priority of scooting is not being
## close to the point you fired from."
##
## Two distinct gaps, both traced directly against BattleManager._mortar_
## should_relocate_for_safety and _mortar_relocation_plan:
##
##   1. The GATE deciding whether to relocate at all required a KNOWN
##      (detected/sighted) enemy mortar in range, and even then only
##      overrode a deliberate hold-position doctrine once density
##      compounded past MORTAR_DENSITY_FORCE_SCOOT_COUNT — backwards from
##      real shoot-and-scoot doctrine, which assumes counter-battery risk
##      from the mere fact the enemy fields mortars able to reach this
##      position, not from confirmation a specific tube detected this one.
##   2. The SEARCH itself had no explicit notion of "the actual firing
##      point" at all — only of "clear the map's own concealment rings
##      from wherever I'm CURRENTLY standing," which can differ from the
##      real firing coordinate by up to COUNTER_BATTERY_BLAST_RADIUS (see
##      _mortar_should_relocate_for_safety's own stopping condition), so a
##      candidate genuinely far from `from` could still land close to
##      where a counter-battery mission is actually aimed.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_firing_point_avoidance.gd
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
	return bm


## Gap 1: a hold-position doctrine (shoot_and_scoot == false) must still
## relocate once a REAL enemy mortar is within range of a still-live
## firing signature — even though that enemy mortar has never actually
## been sighted or detected (is_visible false, never fired itself, no
## player_has_been_sighted). The old gate required "known," which this
## scenario deliberately never satisfies.
func test_hold_position_doctrine_still_evades_a_real_undetected_threat() -> void:
	var bm = make_battle()
	var start: Vector2 = GameConfig.CURRENT_MAP.player.mortar_default_position
	bm._friendly_mortar_home_position = start
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, start)
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = 10
	mortar.seconds_stationary = 1e9
	mortar.is_visible = false
	mortar.shoot_and_scoot = false # hold-position doctrine
	bm._last_detected_mortar_fire[mortar] = {"position": start, "time": bm.scenario_elapsed_time}

	# A real enemy mortar, well within striking range -- but never sighted,
	# never fired, and never otherwise "known" to the player's side.
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, start + Vector2(400, 0))
	bm.enemy_units.append(enemy)
	enemy.is_visible = false

	bm.unit_type_doctrines[Unit.Team.PLAYER] = Orders.sanitize({})
	bm._decide_mortar_action(mortar)
	check(bm._pending_mortar_displacement.has(mortar),
		"A hold-position mortar whose own firing signature is still live must still relocate once a real enemy mortar is in range, even if that mortar was never actually detected")
	bm.combat_log.free()
	bm.free()


## Gap 2, statistical: a mortar that has already drifted some distance
## from where it actually fired (but not yet clear of COUNTER_BATTERY_
## BLAST_RADIUS -- still "compromised") must have its relocation search
## avoid the REAL firing coordinate, not just search outward from wherever
## it currently stands. Constructed so a real, otherwise-plausible ring-
## search candidate (stepping back toward the firing point) would violate
## this if the new check weren't in place: current position is 50m off
## the firing point, well under the ring search's own ~75m minimum reach,
## so a candidate at that minimum ring, aimed back toward the firing
## point, lands well within blast radius of it.
func test_scoot_avoids_the_actual_firing_point_not_just_current_position() -> void:
	var bm = make_battle()
	var firing_point := Vector2(0, 0)
	bm._friendly_mortar_home_position = firing_point
	var current: Vector2 = firing_point + Vector2(50.0 * GameConfig.PIXELS_PER_METER, 0)
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, current)
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = 10
	bm._last_detected_mortar_fire[mortar] = {"position": firing_point, "time": bm.scenario_elapsed_time}

	# A real known threat so _mortar_relocation_plan routes through the
	# ring search (nearest_hidden_point), not the no-known-threats fallback.
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, current + Vector2(500, 0))
	bm.enemy_units.append(enemy)
	enemy.player_has_been_sighted = true
	enemy.player_known_position = enemy.global_position

	const DRAWS := 60
	var violations := 0
	for i in DRAWS:
		var plan: Dictionary = bm._mortar_relocation_plan(mortar, false)
		check(not plan.is_empty(), "A real relocation must be found here — an open map with real room to maneuver")
		if not plan.is_empty() and plan.destination.distance_to(firing_point) < GameConfig.COUNTER_BATTERY_BLAST_RADIUS:
			violations += 1
	check(violations == 0,
		"%d/%d scoot destinations landed within COUNTER_BATTERY_BLAST_RADIUS of the ACTUAL firing point, even though the search was only ever checking distance from the mortar's current (already-drifted) position" % [violations, DRAWS])
	bm.combat_log.free()
	bm.free()


func run() -> void:
	test_hold_position_doctrine_still_evades_a_real_undetected_threat()
	test_scoot_avoids_the_actual_firing_point_not_just_current_position()
	print("Mortar firing-point-avoidance tests: %d failures" % failures)
	quit(1 if failures else 0)
