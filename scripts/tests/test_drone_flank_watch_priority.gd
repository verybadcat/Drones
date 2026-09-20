extends SceneTree
## Guards a live-reported drone behavior problem: "in this situation the
## drone is too far afield... it seems to do very little squad watching."
## Diagnosed directly from the running battle's debug snapshot: both enemy
## mortars had withdrawn (mortar-existence confidence 0.00, so no mortar
## searching at all), but the mortar's flank-watch standing duty was a flat
## DRONE_FLANK_WATCH_STANDING_PRIORITY (30.0) — above any squad's tracking
## ceiling (TARGET_PRIORITY_SQUAD_MAX, 10.0) — so with the mortar parked at
## the map edge and every known enemy squad 2km+ away, the drone kept
## flying out to probe its empty flanks while the fight was elsewhere.
## BattleManager._flank_watch_standing_priority now fades that standing
## priority with how close the nearest known enemy squad actually is to the
## mortar. Direct user agreement to the design.
##
## Run: godot --headless --path . --script scripts/tests/test_drone_flank_watch_priority.gd
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

## A friendly mortar at the origin, a friendly squad far away (so a visible
## enemy squad near IT has a real, nonzero danger score), and one visible,
## sighted enemy squad `enemy_dist` from the mortar along +x — or none if
## enemy_dist is INF.
func _setup(bm, enemy_pos: Vector2) -> Unit:
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(0, 0))
	bm.player_units.append(mortar)
	var friendly: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(3000, 0))
	bm.player_units.append(friendly)
	bm.active_drone = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, Vector2(0, 0))
	if is_inf(enemy_pos.x):
		return null
	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, enemy_pos)
	bm.enemy_units.append(enemy)
	enemy.is_visible = true
	bm._update_player_intel()
	return enemy


func test_priority_is_full_when_a_known_squad_is_within_the_threat_radius() -> void:
	var bm = make_battle()
	_setup(bm, Vector2(GameConfig.DRONE_FLANK_WATCH_FADE_START * 0.5, 0))
	check(is_equal_approx(bm._flank_watch_standing_priority(), GameConfig.DRONE_FLANK_WATCH_STANDING_PRIORITY),
		"A known enemy squad inside the flank threat radius must keep the full standing priority (got %.2f)" % bm._flank_watch_standing_priority())


func test_priority_is_full_when_no_enemy_squad_is_known() -> void:
	var bm = make_battle()
	_setup(bm, Vector2(INF, 0))
	check(is_equal_approx(bm._flank_watch_standing_priority(), GameConfig.DRONE_FLANK_WATCH_STANDING_PRIORITY),
		"With no known enemy squad, nothing competes for the drone and unknown enemies are the point — full priority (got %.2f)" % bm._flank_watch_standing_priority())


func test_priority_fades_to_the_floor_when_every_known_squad_is_far() -> void:
	var bm = make_battle()
	_setup(bm, Vector2(GameConfig.DRONE_FLANK_WATCH_FADE_END * 2.0, 0))
	check(is_equal_approx(bm._flank_watch_standing_priority(), GameConfig.DRONE_FLANK_WATCH_FLOOR_PRIORITY),
		"Every known enemy squad far from the mortar must drop the standing priority to the floor (got %.2f)" % bm._flank_watch_standing_priority())


func test_priority_fades_smoothly_in_between() -> void:
	var previous := INF
	for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var bm = make_battle()
		var dist: float = lerp(GameConfig.DRONE_FLANK_WATCH_FADE_START, GameConfig.DRONE_FLANK_WATCH_FADE_END, fraction)
		_setup(bm, Vector2(dist, 0))
		var p: float = bm._flank_watch_standing_priority()
		check(p <= previous, "Priority must never rise as the nearest known squad gets farther (fraction %.2f gave %.2f after %.2f)" % [fraction, p, previous])
		if fraction > 0.0 and fraction < 1.0:
			check(p < GameConfig.DRONE_FLANK_WATCH_STANDING_PRIORITY and p > GameConfig.DRONE_FLANK_WATCH_FLOOR_PRIORITY,
				"Mid-fade must sit strictly between floor and full (fraction %.2f gave %.2f)" % [fraction, p])
		previous = p


## The reported behavior end to end: with the only known squad far from the
## mortar but in real contact with a friendly unit, the drone must track the
## squad instead of flying out to probe the mortar's flanks.
func test_drone_tracks_a_squad_when_the_mortar_is_not_threatened() -> void:
	var bm = make_battle()
	# 100px (500m) from the friendly squad at (3000,0): danger score ~5.8,
	# well above the floor; 3100px from the mortar: far beyond the fade end.
	_setup(bm, Vector2(3100, 0))
	bm._drone_search_target()
	check(bm._drone_pilot_reasoning.tier == "Tracking dangerous squad",
		"With the mortar unthreatened, a squad in real contact must win drone attention over flank-watch (tier was: %s)" % bm._drone_pilot_reasoning.tier)


## The counterpart that must keep working: a known squad actually closing
## on the mortar must still bring the drone back to the flank watch.
func test_drone_still_watches_the_flank_when_a_squad_is_near_the_mortar() -> void:
	var bm = make_battle()
	_setup(bm, Vector2(GameConfig.DRONE_FLANK_WATCH_FADE_START * 0.5, 0))
	bm._drone_search_target()
	check(bm._drone_pilot_reasoning.tier == "Routine background recon",
		"A known squad near the mortar must keep the flank-watch duty above squad tracking (tier was: %s)" % bm._drone_pilot_reasoning.tier)


func run() -> void:
	test_priority_is_full_when_a_known_squad_is_within_the_threat_radius()
	test_priority_is_full_when_no_enemy_squad_is_known()
	test_priority_fades_to_the_floor_when_every_known_squad_is_far()
	test_priority_fades_smoothly_in_between()
	test_drone_tracks_a_squad_when_the_mortar_is_not_threatened()
	test_drone_still_watches_the_flank_when_a_squad_is_near_the_mortar()
	print("Drone flank-watch priority tests: %d failures" % failures)
	quit(1 if failures else 0)
