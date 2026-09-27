extends SceneTree
## Direct user report from a live battle: "drone is now chasing fleeing mortar. It
## should not do that when there are squads." The drone's "Supporting important
## friendly action" tier backs up whatever enemy mortar the friendly mortar has
## committed to hunting at full mortar priority — including one that is already
## RETREATING, which pulled the drone off four enemy squads still in the fight. A
## fleeing mortar is a mop-up: with squads still fighting the tier stands down (the
## ordinary tiers, squads first, decide); with no squad left it is all there is to
## support, as before.
##
## Run: godot --headless --path . --script scripts/tests/test_drone_fleeing_mortar_vs_squads.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
const SUPPORT_TIER := "Supporting important friendly action"
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(v: float) -> float:
	return v * GameConfig.PIXELS_PER_METER

## Friendly mortar (hunting), the drone team and an airborne drone; an enemy mortar
## in `mortar_state`, visible; and, if `squad_state` is given, an enemy squad in that
## state and visibility.
func make_battle(mortar_state: Unit.State, squad_state = null, squad_visible: bool = true):
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
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(m(-1000), m(1500)))
	bm.player_units.append(mortar)
	bm.drone_team = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2(m(-1500), m(1500)))
	bm.player_units.append(bm.drone_team)
	var d: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(m(-800), m(1500)))
	bm.player_units.append(d)
	d.move_speed = GameConfig.DRONE_CRUISE_SPEED
	d.drone_battery_charge = 0.9
	bm.active_drone = d
	var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(m(3500), m(600)))
	bm.enemy_units.append(em)
	em.is_visible = true
	em.state = mortar_state
	if squad_state != null:
		var sq: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(m(1500), m(1500)))
		bm.enemy_units.append(sq)
		sq.is_visible = squad_visible
		sq.state = squad_state
	bm._mortar_move_intent[mortar] = "hunt" # the friendly mortar has committed to closing on it
	bm._update_player_intel() # real play always runs this the same tick anything becomes visible; _mortar_existence_confidence now depends on it
	return bm

func tier(bm) -> String:
	bm._drone_search_target()
	return str(bm._drone_pilot_reasoning.get("tier", ""))

func cleanup(bm) -> void:
	bm.combat_log.free()
	bm.free()

func run() -> void:
	test_a_fleeing_mortar_does_not_pull_the_drone_off_squads()
	test_with_no_squads_left_the_chase_is_supported_as_before()
	test_an_active_hunted_mortar_is_still_supported()
	test_squads_out_of_view_but_recently_seen_count()
	print("Drone fleeing-mortar vs squads tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_a_fleeing_mortar_does_not_pull_the_drone_off_squads() -> void:
	var bm = make_battle(Unit.State.RETREATING, Unit.State.ACTIVE)
	var fix: Dictionary = bm._mortar_hunt_fix_for(bm.player_units[0])
	check(not fix.is_empty() and fix.get("unit", null) == bm.enemy_units[0], "Setup: the friendly mortar has a hunt fix on the fleeing mortar")
	var t: String = tier(bm)
	check(t != SUPPORT_TIER, "With enemy squads in the fight the drone must not follow the fleeing mortar (tier was %s)" % t)
	check(t != "Finishing a retreating contact", "...nor does it drop into the low-priority retreating-contact chase (tier was %s)" % t)
	var target: Vector2 = bm._drone_pilot_reasoning.get("target", Vector2.INF)
	check(target.distance_to(bm.enemy_units[0].global_position) > m(500.0), "...and its target is not the fleeing mortar's position (%s)" % str(target))
	cleanup(bm)
	# The squads are what it goes for when they are a live danger to something of ours.
	bm = make_battle(Unit.State.RETREATING, Unit.State.ACTIVE)
	bm.enemy_units[1].global_position = bm.player_units[0].global_position + Vector2(m(600), 0)
	t = tier(bm)
	check(t == "Tracking dangerous squad", "With a squad close to our mortar the drone watches it instead of the fleeing mortar (tier was %s)" % t)
	cleanup(bm)


func test_with_no_squads_left_the_chase_is_supported_as_before() -> void:
	var bm = make_battle(Unit.State.RETREATING)
	check(tier(bm) == SUPPORT_TIER, "No squads at all: backing up the mortar's chase is what's left")
	cleanup(bm)
	# A squad that has itself withdrawn, or is retreating, is not in the fight either.
	for state in [Unit.State.RETREATING, Unit.State.WITHDRAWN, Unit.State.DESTROYED]:
		bm = make_battle(Unit.State.RETREATING, state)
		check(tier(bm) == SUPPORT_TIER, "A squad in state %s does not keep the drone off the chase" % Unit.State.keys()[state])
		cleanup(bm)


## Only a FLEEING hunted mortar is stood down for: one still ACTIVE is the threat
## the tier exists for, squads or not. Known only from its muzzle flash (not in view,
## so the live-contact tier is out of the picture and this tier is what decides).
func test_an_active_hunted_mortar_is_still_supported() -> void:
	var bm = make_battle(Unit.State.ACTIVE, Unit.State.ACTIVE)
	var em: Unit = bm.enemy_units[0]
	em.is_visible = false
	bm._last_detected_mortar_fire[em] = {"position": em.global_position, "time": bm.scenario_elapsed_time}
	var fix: Dictionary = bm._mortar_hunt_fix_for(bm.player_units[0])
	check(not fix.is_empty() and fix.get("unit", null) == em, "Setup: the friendly mortar is hunting the ACTIVE mortar it heard")
	var t: String = tier(bm)
	check(t == SUPPORT_TIER, "An ACTIVE hunted mortar is still backed up even with squads in the fight (tier was %s)" % t)
	cleanup(bm)


## A squad the drone just lost sight of still counts for the same horizon as any
## other recent contact — and stops counting once that lapses.
func test_squads_out_of_view_but_recently_seen_count() -> void:
	var bm = make_battle(Unit.State.RETREATING, Unit.State.ACTIVE, true)
	bm._update_recent_enemy_contacts()
	bm.enemy_units[1].is_visible = false
	check(bm._enemy_squads_still_in_the_fight(), "A squad seen moments ago is still in the fight")
	bm.scenario_elapsed_time += GameConfig.DRONE_CONTACT_BONUS_EXPIRY + 1.0
	check(not bm._enemy_squads_still_in_the_fight(), "...until the sighting is stale")
	cleanup(bm)
