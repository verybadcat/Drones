extends SceneTree
## Suppression (user, 2026-10-09, after the small-arms research: "Then do a separate commit for suppression"). Fire does more than kill: a
## squad under it keeps its heads down. Every volley aimed at a squad (hit or miss) and every mortar round landing near one raises its
## suppression; it fades with tactical time; at a high level the squad is pinned (an enemy squad does not start a new advance) and its own fire
## is less accurate in proportion. Squads only. See GameConfig.SUPPRESSION_*.
##
## Run: godot --headless --path . --script scripts/tests/test_suppression.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(x: float, y: float = 0.0) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

func make() -> BattleManager:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.scenario_elapsed_time = 1000.0
	return bm

func squad(bm: BattleManager, team: Unit.Team, at: Vector2) -> Unit:
	var u: Unit = bm._make_unit(team, Unit.Kind.SQUAD, at)
	(bm.player_units if team == Unit.Team.PLAYER else bm.enemy_units).append(u)
	return u

func logged(bm: BattleManager, needle: String) -> int:
	var n := 0
	for line in bm.combat_log.captured:
		if needle in line:
			n += 1
	return n

func run() -> void:
	GameConfig.set_active_map("pishchane")
	var per_volley: float = GameConfig.SUPPRESSION_PER_VOLLEY

	# 1. a volley aimed at a squad suppresses it, hit or miss; a mortar round aimed at it does not through this path
	var bm := make()
	var shooter: Unit = squad(bm, Unit.Team.ENEMY, m(2000, 1500))
	var always_added := true
	var hits := 0
	var misses := 0
	seed(31)
	for i in 30:
		var target: Unit = squad(bm, Unit.Team.PLAYER, m(1900, 200 + 100 * i)) # spread out: no bunching spill-over between them
		var before_pips: int = target.pips
		bm._resolve_fire_and_check_bunching(shooter, target, target.global_position)
		if target.pips < before_pips:
			hits += 1
		else:
			misses += 1
		if not is_equal_approx(target.suppression, per_volley):
			always_added = false
	check(hits > 0 and misses > 0, "Setup: the volleys include hits and misses (%d, %d)" % [hits, misses])
	check(always_added, "Every volley at a squad adds %.2f suppression, whether it hits or misses" % per_volley)
	var one: Unit = squad(bm, Unit.Team.PLAYER, m(1500, 1500))
	for i in 6:
		bm._resolve_fire_and_check_bunching(shooter, one, one.global_position)
	check(is_equal_approx(one.suppression, 1.0), "Suppression is capped at 1 (%.2f)" % one.suppression)
	var gun: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4000, 1500)); bm.enemy_units.append(gun)
	var other: Unit = squad(bm, Unit.Team.PLAYER, m(1400, 1500))
	bm._resolve_fire_and_check_bunching(gun, other, other.global_position)
	check(is_zero_approx(other.suppression), "A mortar round aimed at a squad does not suppress it by that path (it does by where it lands)")
	bm.combat_log.free()
	bm.free()

	# 2. a mortar round suppresses the squads near where it lands, more the nearer, on either side, and no one else
	bm = make()
	var point: Vector2 = m(1500, 1500)
	var at10: Unit = squad(bm, Unit.Team.PLAYER, point + m(10, 0))
	var at30: Unit = squad(bm, Unit.Team.ENEMY, point + m(0, 30))
	var at59: Unit = squad(bm, Unit.Team.PLAYER, point + m(-59, 0))
	var at61: Unit = squad(bm, Unit.Team.ENEMY, point + m(0, -61))
	var crew: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, point + m(5, 5)); bm.player_units.append(crew)
	bm._suppress_from_blast(point)
	var full: float = GameConfig.SUPPRESSION_BLAST_MAX
	var radius: float = GameConfig.SUPPRESSION_BLAST_RADIUS_M
	check(is_equal_approx(at10.suppression, full * (1.0 - 10.0 / radius)) and at10.suppression > 0.45, "A squad 10 m from the landing is suppressed strongly (%.2f)" % at10.suppression)
	check(is_equal_approx(at30.suppression, full * (1.0 - 30.0 / radius)) and at30.suppression < at10.suppression, "...one 30 m off less (%.2f), on either side" % at30.suppression)
	check(at59.suppression > 0.0 and at59.suppression < 0.02, "...one 59 m off only a little (%.3f)" % at59.suppression)
	check(is_zero_approx(at61.suppression), "...and one 61 m off not at all")
	check(is_zero_approx(crew.suppression), "A mortar crew is not suppressed (squads only)")

	# 3. it fades with tactical time, and is gone from a unit that is out of the fight
	at10.suppression = 1.0
	bm._update_suppression(90.0)
	check(is_equal_approx(at10.suppression, 0.5), "Half a minute and a half of battle time takes full suppression to a half (%.2f)" % at10.suppression)
	bm._update_suppression(90.0)
	check(is_zero_approx(at10.suppression), "...and three minutes to nothing")
	at30.suppression = 0.9
	at30.state = Unit.State.DESTROYED
	bm._update_suppression(1.0)
	check(is_zero_approx(at30.suppression), "A squad that is out of the fight carries none")
	bm.combat_log.free()
	bm.free()

	# 4. pinned from the pin level, freed only below the release level (no flicker), said in the log once each, for squads the player can see
	bm = make()
	var ours: Unit = squad(bm, Unit.Team.PLAYER, m(1500, 1500))
	var seen_enemy: Unit = squad(bm, Unit.Team.ENEMY, m(2500, 1500)); seen_enemy.is_visible = true
	var unseen_enemy: Unit = squad(bm, Unit.Team.ENEMY, m(2600, 1500)); unseen_enemy.is_visible = false
	for u in [ours, seen_enemy, unseen_enemy]:
		u.suppression = GameConfig.SUPPRESSION_PIN_LEVEL + 0.05
	bm._update_suppression(0.0)
	check(ours.pinned and seen_enemy.pinned and unseen_enemy.pinned, "At the pin level a squad is pinned")
	check(logged(bm, "is pinned down") == 2, "...and the log says so for our squad and the enemy one in sight, not the one out of sight (%d lines)" % logged(bm, "is pinned down"))
	for u in [ours, seen_enemy, unseen_enemy]:
		u.suppression = (GameConfig.SUPPRESSION_PIN_LEVEL + GameConfig.SUPPRESSION_RELEASE_LEVEL) / 2.0
	bm._update_suppression(0.0)
	check(ours.pinned, "Between the two levels it stays pinned (no flicker)")
	check(logged(bm, "is pinned down") == 2 and logged(bm, "no longer pinned") == 0, "...with nothing more in the log")
	for u in [ours, seen_enemy, unseen_enemy]:
		u.suppression = GameConfig.SUPPRESSION_RELEASE_LEVEL - 0.05
	bm._update_suppression(0.0)
	check(not ours.pinned and not seen_enemy.pinned and not unseen_enemy.pinned, "Below the release level it is free again")
	check(logged(bm, "no longer pinned down") == 2, "...and the log says so, again for the two the player can see")

	# 5. a suppressed squad shoots worse, in proportion; mortars are not affected
	var target: Unit = squad(bm, Unit.Team.PLAYER, m(1800, 1500))
	var shooter2: Unit = squad(bm, Unit.Team.ENEMY, m(2000, 1500))
	shooter2.suppression = 0.0
	var steady: float = CombatResolver.hit_probability(shooter2, target)
	shooter2.suppression = 0.5
	var half: float = CombatResolver.hit_probability(shooter2, target)
	shooter2.suppression = 1.0
	var full_supp: float = CombatResolver.hit_probability(shooter2, target)
	check(is_equal_approx(half, steady * (1.0 - 0.5 * GameConfig.SUPPRESSION_MAX_ACCURACY_LOSS)), "Half suppressed, it hits proportionally less often (%.3f of %.3f)" % [half, steady])
	check(is_equal_approx(full_supp, steady * (1.0 - GameConfig.SUPPRESSION_MAX_ACCURACY_LOSS)) and full_supp < half, "...fully suppressed, by the full loss (%.3f)" % full_supp)
	var gun5: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4000, 1500)); bm.enemy_units.append(gun5)
	gun5.suppression = 0.0
	var gun_steady: float = CombatResolver.hit_probability(gun5, target)
	gun5.suppression = 1.0
	check(is_equal_approx(CombatResolver.hit_probability(gun5, target), gun_steady), "A mortar's chance does not depend on suppression")

	# 6. a pinned enemy squad does not start a new advance; a free one does
	var free_squad: Unit = squad(bm, Unit.Team.ENEMY, m(3500, 1500))
	var pinned_squad: Unit = squad(bm, Unit.Team.ENEMY, m(3500, 1700))
	for u in [free_squad, pinned_squad]:
		u.sought_cover = true
		u.sought_cover_logged = true
		u.has_move_target = false
		u.is_visible = false
	pinned_squad.pinned = true
	pinned_squad.suppression = 0.8
	bm.enemy_alerted = true
	bm._update_enemy_squad_advance()
	check(pinned_squad.last_order_reason.begins_with("Pinned down by fire") and not pinned_squad.has_move_target, "A pinned enemy squad stays put: \"%s\"" % pinned_squad.last_order_reason)
	check(free_squad.has_move_target, "...while one that is not pinned starts its next bound (%s)" % free_squad.last_order_reason)
	bm.combat_log.free()
	bm.free()

	# 7. shells that land in the real flow suppress, ordinary and counter-battery both
	bm = make()
	var near_squad: Unit = squad(bm, Unit.Team.PLAYER, m(1500, 1500))
	var near_enemy: Unit = squad(bm, Unit.Team.ENEMY, m(1520, 1500))
	var um: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(400, 1500)); bm.player_units.append(um)
	var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4000, 1500)); bm.enemy_units.append(em)
	bm._pending_mortar_shots.append({"mortar": um, "target": null, "aim_point": m(1510, 1500), "impact_point": m(1510, 1500), "impact_time": 900.0})
	bm._resolve_pending_mortar_shots()
	check(near_squad.suppression > 0.4 and near_enemy.suppression > 0.4, "A round that lands between two squads suppresses both (%.2f, %.2f)" % [near_squad.suppression, near_enemy.suppression])
	near_squad.suppression = 0.0
	near_enemy.suppression = 0.0
	bm._pending_counter_battery.append({"attacker": em, "target": um, "impact_position": m(1500, 1510), "fire_time": 0.0, "impact_time": 900.0, "fired": true})
	bm._resolve_pending_counter_battery()
	check(near_squad.suppression > 0.4, "A counter-battery round landing near a squad suppresses it too (%.2f)" % near_squad.suppression)

	# 8. the unit snapshot shows it
	var snap: Dictionary = bm.general_unit_debug_snapshot()
	var found := false
	for k in snap:
		if snap[k].kind == "SQUAD" and snap[k].has("suppression") and snap[k].has("pinned"):
			found = true
	check(found, "The unit debug snapshot reports each squad's suppression and whether it is pinned")
	bm.combat_log.free()
	bm.free()
	print("Suppression tests: %d failures" % failures)
	quit(1 if failures else 0)
