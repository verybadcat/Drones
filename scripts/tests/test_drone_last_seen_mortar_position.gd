extends SceneTree
## Direct user report: "The drone just briefly saw an enemy mortar. Said mortar then disappeared from
## view. But even this brief sighting should be enough to cause the drone team to be aware of the mortar's
## existence and approximate location. Based on the drone's behavior, I'm questioning whether that is the
## case."
##
## The knowledge itself was already there (player_known_position/player_known_position_time/
## player_has_been_sighted, updated by _update_player_intel the instant it was visible, with no expiry —
## see Unit's own doc comments). The gap was in the drone's OWN search: _drone_search_target's "fresh
## fire-detection lead" tier only ever looked at _last_detected_mortar_fire (a muzzle flash), which is
## never recorded for a mortar that is merely seen and never observed firing — so once it went out of
## sight, nothing sent the drone back to where it was last seen. _known_enemy_mortar_lead already has a
## third fallback for exactly this (player_known_position, no expiry) but that function feeds the
## FRIENDLY MORTAR's own hunt, not the drone's own search directly. The tier now also checks this
## fallback, gated and scored the same way an (untrusted) fire-detection lead already is.
##
## Run: godot --headless --path . --script scripts/tests/test_drone_last_seen_mortar_position.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(x: float, y: float) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

func make_battle():
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(500, 1500))
	bm.player_units.append(mortar)
	bm.drone_team = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, m(-800, 1500))
	bm.player_units.append(bm.drone_team)
	var d: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, m(-500, 1500))
	bm.player_units.append(d)
	d.move_speed = GameConfig.DRONE_CRUISE_SPEED
	d.drone_battery_charge = 0.9
	bm.active_drone = d
	return bm

func cleanup(bm) -> void:
	bm.combat_log.free()
	bm.free()

func run() -> void:
	test_a_brief_sighting_alone_sends_the_drone_back()
	test_a_never_sighted_mortar_gives_no_lead()
	test_a_fire_detection_lead_still_wins_when_fresher()
	test_the_sighting_only_lead_never_expires()
	print("Drone last-seen mortar position tests: %d failures" % failures)
	quit(1 if failures else 0)


## The reported scenario itself: briefly visible, never fired, then lost.
func test_a_brief_sighting_alone_sends_the_drone_back() -> void:
	var bm = make_battle()
	var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4000, 1500)) # within the mortar's 4500 m range
	bm.enemy_units.append(em)
	em.is_visible = true
	bm._update_player_intel() # the brief sighting, recorded
	em.is_visible = false # and now it's gone
	check(em.player_has_been_sighted and not is_inf(em.player_known_position.x), "Set-up: the sighting was recorded")
	check(bm._last_detected_mortar_fire.get(em, {}).is_empty(), "Set-up: it never fired, so there is no muzzle-flash trace")
	var target: Vector2 = bm._drone_search_target()
	check(target.distance_to(em.global_position) < 1.0, "The drone goes back to where it was last seen (%s)" % (target / GameConfig.PIXELS_PER_METER))
	check(bm._drone_pilot_reasoning.get("tier", "") == "Last-seen mortar position", "...reported as a last-seen-position lead (%s)" % str(bm._drone_pilot_reasoning.get("tier", "")))
	cleanup(bm)


func test_a_never_sighted_mortar_gives_no_lead() -> void:
	var bm = make_battle()
	var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4000, 1500))
	bm.enemy_units.append(em)
	em.is_visible = false # never seen at all
	bm._drone_search_target()
	check(bm._drone_pilot_reasoning.get("tier", "") != "Last-seen mortar position", "An enemy mortar never sighted gives the drone nothing to go on (%s)" % str(bm._drone_pilot_reasoning.get("tier", "")))
	cleanup(bm)


## A real, fresher muzzle-flash trace still wins over a stale plain sighting of the same mortar.
func test_a_fire_detection_lead_still_wins_when_fresher() -> void:
	var bm = make_battle()
	var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4000, 1500))
	bm.enemy_units.append(em)
	em.is_visible = true
	bm._update_player_intel()
	em.global_position = m(4100, 1600)
	em.is_visible = false
	bm.scenario_elapsed_time = 100.0
	bm._last_detected_mortar_fire[em] = {"position": em.global_position, "time": bm.scenario_elapsed_time} # fired after the sighting
	var target: Vector2 = bm._drone_search_target()
	check(target.distance_to(em.global_position) < 1.0, "The fresher fire-detection position wins (%s)" % (target / GameConfig.PIXELS_PER_METER))
	check(bm._drone_pilot_reasoning.get("tier", "") == "Fresh mortar fire-detection lead", "...and is reported as the fire-detection tier, not the sighting one (%s)" % str(bm._drone_pilot_reasoning.get("tier", "")))
	cleanup(bm)


## No expiry on the plain sighting, matching _known_enemy_mortar_lead's own third fallback ("a real crew
## doesn't forget where a gun was last seen").
func test_the_sighting_only_lead_never_expires() -> void:
	var bm = make_battle()
	var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4000, 1500))
	bm.enemy_units.append(em)
	em.is_visible = true
	bm._update_player_intel()
	em.is_visible = false
	bm.scenario_elapsed_time += GameConfig.DRONE_MORTAR_FIRE_LEAD_EXPIRY * 10.0 # long past a fire-detection lead's own expiry
	var target: Vector2 = bm._drone_search_target()
	check(target.distance_to(em.global_position) < 1.0, "A plain sighting is still worth going back to check, however long ago (%s)" % (target / GameConfig.PIXELS_PER_METER))
	cleanup(bm)
