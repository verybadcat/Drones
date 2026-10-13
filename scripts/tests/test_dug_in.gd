extends SceneTree
## Digging in (docs/designs/posture-and-suppression.md, stage E). A unit that stays where it is digs, in stages, a shell scrape and then a
## fighting position; it loses what it has dug when it goes elsewhere; it cannot dig in a building; at its post in a fighting position it
## has 1/25 of what it would have on its feet in the open (UK WWII: firing from a trench 1/15-1/50), crouched on the fire step half of that
## again, a round that lands in the hole is a direct hit, and a unit on the move has none of it.
##
## Run: godot --headless --path . --script scripts/tests/test_dug_in.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
const TestBattleManagerScript := preload("res://scripts/tests/test_battle_manager.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(x: float, y: float = 0.0) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

func make() -> Dictionary:
	GameConfig.set_active_map("voznesensk")
	GameConfig._build_terrain_grid()
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.scenario_elapsed_time = 1000.0
	return {"bm": bm, "open": m(-5000, -5000), "building": GameConfig._building_rects[0].get_center()}

func unit(c: Dictionary, team: Unit.Team, kind: Unit.Kind, point: Vector2) -> Unit:
	var u: Unit = c.bm._make_unit(team, kind, point)
	if team == Unit.Team.PLAYER:
		c.bm.player_units.append(u)
	else:
		c.bm.enemy_units.append(u)
	return u

func dig(c: Dictionary, seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		var step: float = minf(left, 30.0)
		c.bm._update_entrenchment(step)
		left -= step

func cleanup(c: Dictionary) -> void:
	c.bm.combat_log.free()
	c.bm.free()

func run() -> void:
	var c := make()
	var bm: BattleManager = c.bm
	check(GameConfig.get_terrain_type_at(c.open) == GameConfig.TerrainType.OPEN, "Setup: open ground")
	check(GameConfig.get_terrain_type_at(c.building) == GameConfig.TerrainType.BUILDING, "Setup: a building")

	# 1. the stages, and what loses them
	var squad: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, c.open)
	dig(c, GameConfig.SHELL_SCRAPE_BUILD_S - 60.0)
	check(squad.entrenchment == Unit.Entrenchment.NONE, "Not yet a scrape just short of the time")
	dig(c, 90.0)
	check(squad.entrenchment == Unit.Entrenchment.SCRAPE, "A shell scrape after %d minutes" % int(GameConfig.SHELL_SCRAPE_BUILD_S / 60.0))
	dig(c, GameConfig.FIGHTING_POSITION_BUILD_S - GameConfig.SHELL_SCRAPE_BUILD_S)
	check(squad.entrenchment == Unit.Entrenchment.FIGHTING_POSITION, "A fighting position after %d minutes in all" % int(GameConfig.FIGHTING_POSITION_BUILD_S / 60.0))
	check(GameConfig.FIGHTING_POSITION_BUILD_S > 2.0 * GameConfig.SHELL_SCRAPE_BUILD_S, "...which takes much longer than a scrape")
	squad.position += m(3)
	dig(c, 30.0)
	check(squad.entrenchment == Unit.Entrenchment.FIGHTING_POSITION, "Shifting 3 m keeps what it has dug")
	squad.position += m(40)
	dig(c, 30.0)
	check(squad.entrenchment == Unit.Entrenchment.NONE and squad.digging_seconds < 60.0, "Going 40 m away starts again")
	squad.activity = Unit.Activity.MOVING
	var before: float = squad.digging_seconds
	dig(c, 300.0)
	check(squad.digging_seconds == before, "A unit that is moving does not dig")
	squad.activity = Unit.Activity.STATIONARY
	squad.state = Unit.State.RETREATING
	dig(c, 300.0)
	check(squad.digging_seconds == before, "...nor one that is retreating")
	var indoors: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, c.building)
	dig(c, GameConfig.FIGHTING_POSITION_BUILD_S + 60.0)
	check(indoors.entrenchment == Unit.Entrenchment.NONE, "Nobody digs in a building")

	# 2. what a fighting position is worth against a bullet, at its post and crouched; a scrape to a man lying in the open
	var shooter: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.open + m(0, 500))
	var target: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, c.open + m(300, 500))
	var upright: float = CombatResolver.hit_probability(shooter, target)
	target.gone_to_ground = true
	var lying: float = CombatResolver.hit_probability(shooter, target)
	target.entrenchment = Unit.Entrenchment.SCRAPE
	var in_scrape: float = CombatResolver.hit_probability(shooter, target)
	check(in_scrape < lying and in_scrape > 0.5 * lying, "Lying in a shell scrape is a little better than lying in the open (%.4f against %.4f)" % [in_scrape, lying])
	target.gone_to_ground = false
	check(is_equal_approx(CombatResolver.hit_probability(shooter, target), upright), "A scrape does nothing for a man on his feet (%.4f)" % CombatResolver.hit_probability(shooter, target))
	target.entrenchment = Unit.Entrenchment.FIGHTING_POSITION
	var at_post: float = CombatResolver.hit_probability(shooter, target)
	check(at_post / upright > 0.03 and at_post / upright < 0.05, "At its post in a fighting position: about 1/25 of upright in the open (%.4f against %.4f)" % [at_post, upright])
	target.gone_to_ground = true
	var crouched: float = CombatResolver.hit_probability(shooter, target)
	check(absf(crouched / at_post - 0.5) < 0.02, "...crouched on the fire step, half of that again (%.4f against %.4f)" % [crouched, at_post])
	target.gone_to_ground = false
	target.activity = Unit.Activity.MOVING
	var leaving: float = CombatResolver.hit_probability(shooter, target)
	target.entrenchment = Unit.Entrenchment.NONE
	check(is_equal_approx(leaving, CombatResolver.hit_probability(shooter, target)), "A unit that has left its hole has none of it")
	target.activity = Unit.Activity.STATIONARY
	# a mortar's aimed fire at the position
	var gun: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.MORTAR, c.open + m(1500, 500))
	var against_gun: float = CombatResolver.hit_probability(gun, target)
	target.entrenchment = Unit.Entrenchment.FIGHTING_POSITION
	check(CombatResolver.hit_probability(gun, target) < 0.06 * against_gun, "A mortar's round is as little likely to find it (%.4f against %.4f)" % [CombatResolver.hit_probability(gun, target), against_gun])
	# up close the cover is defeated, as for any cover: trench clearing
	var close_shooter: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.open + m(10, 500) + m(300))
	check(CombatResolver.hit_probability(close_shooter, target) > 10.0 * at_post, "Within 25 m a fighting position is cleared as any cover is")
	target.entrenchment = Unit.Entrenchment.NONE

	# 3. a fragment: a crew at its post in a fighting position at 30 m has about a twenty-fifth of what it has on its feet in the open, a
	# round in the hole none of the protection, and a squad's figure likewise
	var crew: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.MORTAR, c.open + m(0, 1000))
	var open_30: float = CombatResolver.blast_person_chance(crew, m(30).length(), crew.exposure_terrain())
	var open_1: float = CombatResolver.blast_person_chance(crew, m(1).length(), crew.exposure_terrain())
	crew.entrenchment = Unit.Entrenchment.FIGHTING_POSITION
	var hole_30: float = CombatResolver.blast_person_chance(crew, m(30).length(), crew.exposure_terrain())
	var hole_1: float = CombatResolver.blast_person_chance(crew, m(1).length(), crew.exposure_terrain())
	var hole_0: float = CombatResolver.blast_person_chance(crew, 0.0, crew.exposure_terrain())
	check(hole_30 / open_30 > 0.015 and hole_30 / open_30 < 0.045, "A crew in its pit at 30 m: a few percent of what it has in the open (%.4f against %.4f)" % [hole_30, open_30])
	check(hole_1 / open_1 > 0.5, "...but a round 1 m away is nearly as bad as ever (%.3f against %.3f)" % [hole_1, open_1])
	check(hole_0 >= 0.99, "...and one in the hole is a direct hit (%.3f)" % hole_0)
	var line: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, c.open + m(0, 1400))
	var line_open: float = CombatResolver.blast_person_chance(line, m(30).length(), line.exposure_terrain())
	line.entrenchment = Unit.Entrenchment.FIGHTING_POSITION
	var line_hole: float = CombatResolver.blast_person_chance(line, m(30).length(), line.exposure_terrain())
	check(line_hole < 0.05 * line_open, "A squad at its post in fighting positions at 30 m: a few percent of what it has upright in the open (%.4f against %.4f)" % [line_hole, line_open])

	# 4. a crew's direct HE hit, rounds at the casualty radius: dug in costs it a small fraction of what it costs in the open
	var trials := 600
	var open_total := 0
	var hole_total := 0
	for i in trials:
		var a := Unit.new()
		a.setup(Unit.Team.PLAYER, Unit.Kind.MORTAR, c.open)
		a.mortar_rounds_remaining = 0 # no ammunition to cook off: that is a direct hit in the hole, by design
		a._apply_crew_casualties([], [], true, GameConfig.MORTAR_BLAST_CASUALTY_RADIUS)
		open_total += a.crew_casualties
		a.free()
		var d := Unit.new()
		d.setup(Unit.Team.PLAYER, Unit.Kind.MORTAR, c.open)
		d.entrenchment = Unit.Entrenchment.FIGHTING_POSITION
		d.mortar_rounds_remaining = 0
		d._apply_crew_casualties([], [], true, GameConfig.MORTAR_BLAST_CASUALTY_RADIUS)
		hole_total += d.crew_casualties
		d.free()
	check(open_total > 200 and hole_total < 0.1 * open_total, "A crew dug in loses a small fraction of what one in the open does to a round at the casualty radius (%d against %d in %d rounds)" % [hole_total, open_total, trials])
	cleanup(c)

	# 5. the Ukrainian side starts the battle dug in where it is deployed, not inside a building; the Russian side starts with nothing;
	# a unit that leaves its place loses it
	for map_id in GameConfig.MAPS.keys():
		GameConfig.set_active_map(map_id)
		GameConfig._build_terrain_grid()
		var squads: Array[Dictionary] = []
		for pos in GameConfig.CURRENT_MAP.player.default_squad_positions:
			squads.append({"position": pos, "retreat_threshold": 0.5})
		var doctrine := {
			"squads": squads,
			"mortar": {"position": GameConfig.CURRENT_MAP.player.mortar_default_position, "shoot_and_scoot": true},
			"spotter": {"position": GameConfig.CURRENT_MAP.player.spotter_default_position},
			"recon_mode": GameConfig.ReconMode.DRONE_TEAM,
		}
		var battle = TestBattleManagerScript.new()
		root.add_child(battle)
		var log = Log.new()
		battle.start_battle(doctrine, log)
		var dug := 0
		var in_building := 0
		for u in battle.player_units:
			if u.kind == Unit.Kind.DRONE:
				continue
			if GameConfig.is_building_at(u.global_position):
				in_building += 1
				check(u.entrenchment == Unit.Entrenchment.NONE, "%s: a unit deployed in a building has the building, nothing dug" % map_id)
			else:
				dug += 1
				check(u.entrenchment == Unit.Entrenchment.FIGHTING_POSITION, "%s: %s starts in a fighting position" % [map_id, u.unit_label])
		check(dug > 0, "%s: at least one unit of the player's side starts dug in" % map_id)
		for u in battle.enemy_units:
			check(u.entrenchment == Unit.Entrenchment.NONE, "%s: the enemy starts with nothing dug" % map_id)
		battle._update_entrenchment(1.0)
		for u in battle.player_units:
			if u.kind != Unit.Kind.DRONE and not GameConfig.is_building_at(u.global_position):
				check(u.entrenchment == Unit.Entrenchment.FIGHTING_POSITION, "%s: the first tick does not take it away" % map_id)
				u.position += m(30)
				battle._update_entrenchment(1.0)
				check(u.entrenchment == Unit.Entrenchment.NONE, "%s: going 30 m away loses it" % map_id)
				break
		if is_instance_valid(log):
			log.free()
		battle.queue_free()
		await process_frame

	# 6. a unit in its hole counts as in cover: a squad does not walk off to the nearest cover, and does not bolt when a round lands, and a
	# spotter does not leave
	var c6 := make()
	var b6: BattleManager = c6.bm
	var rect: Rect2 = GameConfig._building_rects[0]
	var open_near := Vector2.INF
	for dx in [-45.0, 45.0, -70.0, 70.0]:
		var p: Vector2 = Vector2(rect.position.x if dx < 0.0 else rect.end.x, rect.get_center().y) + Vector2(dx, 0.0) * GameConfig.PIXELS_PER_METER
		if GameConfig.get_terrain_type_at(p) == GameConfig.TerrainType.OPEN:
			open_near = p
			break
	check(not is_inf(open_near.x), "Setup: open ground close to a building")
	var loose: Unit = unit(c6, Unit.Team.PLAYER, Unit.Kind.SQUAD, open_near)
	b6._update_friendly_squad_positioning()
	check(loose.has_move_target and loose.last_order_reason == "Moving into available cover.", "Setup: a squad with no hole, in the open and idle, moves to the cover near it (%s)" % loose.last_order_reason)
	var holed: Unit = unit(c6, Unit.Team.PLAYER, Unit.Kind.SQUAD, open_near + m(0, 120))
	check(GameConfig.get_terrain_type_at(holed.position) == GameConfig.TerrainType.OPEN, "Setup: the squad with a hole is on open ground")
	if GameConfig.get_terrain_type_at(holed.position) == GameConfig.TerrainType.OPEN:
		holed.entrenchment = Unit.Entrenchment.FIGHTING_POSITION
		holed.dig_anchor = holed.position
		b6._update_friendly_squad_positioning()
		check(not holed.has_move_target, "A squad in its fighting position stays in it (%s)" % holed.last_order_reason)
		check(holed.in_cover(), "...it is in cover as far as its own decisions go")
	var bolts_loose := 0
	var bolts_holed := 0
	seed(77)
	for i in 400:
		var a := Unit.new()
		a.setup(Unit.Team.PLAYER, Unit.Kind.SQUAD, open_near)
		a.max_pips = 9
		a.pips = 9
		a.take_hit(true, [], [], 10.0 * GameConfig.PIXELS_PER_METER, 0)
		if a.bolted_for_cover:
			bolts_loose += 1
		a.free()
		var h := Unit.new()
		h.setup(Unit.Team.PLAYER, Unit.Kind.SQUAD, open_near)
		h.max_pips = 9
		h.pips = 9
		h.entrenchment = Unit.Entrenchment.FIGHTING_POSITION
		h.take_hit(true, [], [], 10.0 * GameConfig.PIXELS_PER_METER, 0)
		if h.bolted_for_cover:
			bolts_holed += 1
		h.free()
	check(bolts_loose > 10 and bolts_holed == 0, "A squad in the open sometimes bolts when a round lands; one in its hole never does (%d, %d of 400)" % [bolts_loose, bolts_holed])
	var scout: Unit = unit(c6, Unit.Team.PLAYER, Unit.Kind.SPOTTER, open_near + m(0, 240))
	check(GameConfig.get_terrain_type_at(scout.position) == GameConfig.TerrainType.OPEN, "Setup: the spotter is on open ground")
	if GameConfig.get_terrain_type_at(scout.position) == GameConfig.TerrainType.OPEN:
		scout.entrenchment = Unit.Entrenchment.FIGHTING_POSITION
		scout.dig_anchor = scout.position
		b6._update_spotter_positioning()
		check(not scout.has_move_target, "A spotter in its hole does not leave it for cover")
	cleanup(c6)

	print("Dug-in tests: %d failures" % failures)
	quit(1 if failures else 0)
