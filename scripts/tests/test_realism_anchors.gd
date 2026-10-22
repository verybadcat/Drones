extends SceneTree
## The real-world anchors for indirect fire: figures from the sources found, each with a band the game must stay inside. A change that
## moves the game out of one fails here, loudly, instead of drifting. The ledger of every anchor (source, what the game does, what is not
## modelled) is docs/designs/realism-anchors.md; the battle-level ones (shares of casualties, how often a salvo lands near a crew that does
## not sit still) are in tools/research/realism_anchors_sim.gd, which is run on demand, not here.
##
## User, on mortar accuracy: "the main thing is as much as possible to keep the game results close to the real world ... If you can do
## anything to lock-in so that game results stay believable in terms of the real world, that would be great."
##
## Run: godot --headless --path . --script scripts/tests/test_realism_anchors.gd
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

func make(range_m: float, observer: String) -> Dictionary:
	GameConfig.set_active_map("pishchane")
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.scenario_elapsed_time = 1000.0
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(0, 1500))
	bm.player_units.append(mortar)
	var target: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(range_m, 1500))
	bm.enemy_units.append(target)
	target.is_visible = true
	if observer == "spotter":
		var s: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SPOTTER, target.global_position + m(0, 60))
		bm.player_units.append(s)
	elif observer == "drone":
		var d: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, target.global_position + m(0, 40))
		bm.player_units.append(d)
		bm.active_drone = d
	return {"bm": bm, "mortar": mortar, "target": target}

## The CEP (metres) of the next round after `corrections` observed corrections.
func cep_m(c: Dictionary, corrections: int) -> float:
	return c.bm._mortar_dispersion_spread(c.mortar, c.target, c.target.global_position, corrections).cep / GameConfig.PIXELS_PER_METER

func run() -> void:
	# A1. unadjusted fire at 4 km: a CEP of about 3% of the range (NATO: ~136 m for an unguided 120 mm at its maximum range)
	var c := make(4000.0, "none")
	var unadjusted: float = cep_m(c, 0)
	check(unadjusted > 100.0 and unadjusted < 150.0, "A1: unadjusted CEP at 4 km is about 3%% of the range, 100-150 m (%.0f m)" % unadjusted)
	check(cep_m(c, 12) == unadjusted, "A1: nobody watching, no correction ever helps (still %.0f m after 12)" % cep_m(c, 12))
	# A2. a short shot: the 15 m floor
	var near := make(300.0, "none")
	check(cep_m(near, 0) >= 14.0 and cep_m(near, 0) <= 16.0, "A2: at 300 m an unadjusted round still has a CEP of about 15 m (%.1f)" % cep_m(near, 0))
	near.bm.combat_log.free()
	near.bm.free()
	c.bm.combat_log.free()
	c.bm.free()

	# A3. what observation cannot take out: converged, at 4 km, the CEP is never below the weapon's own scatter (tens of metres), however well
	# the fall of shot is seen
	for observer in ["spotter", "drone"]:
		c = make(4000.0, observer)
		var q: String = c.bm._mortar_fire_observation_quality(c.mortar, c.target)
		check(q != "none", "A3 setup: the %s is seen as an observer (%s)" % [observer, q])
		var converged: float = cep_m(c, 30)
		check(converged >= 15.0 and converged <= 45.0, "A3: %s-observed fire converged at 4 km has a CEP of 15-45 m, not the observer's bare floor (%.0f m)" % [observer, converged])
		check(cep_m(c, 1) < cep_m(c, 0), "A3: one correction helps (%.0f against %.0f m)" % [cep_m(c, 1), cep_m(c, 0)])
		c.bm.combat_log.free()
		c.bm.free()

	# A4. a registered mean point of impact of about 20 m at a short range (FM 6-30): a spotter converged at 500 m
	c = make(500.0, "spotter")
	var registered: float = cep_m(c, 30)
	check(registered >= 15.0 and registered <= 25.0, "A4: a spotter-observed mission converged at 500 m is registered to about 20 m (%.1f)" % registered)
	c.bm.combat_log.free()
	c.bm.free()

	# A5. how often a round lands near an unmoving target at 4 km: first round and an adjusted one (the statistics of A1 and A3 together)
	c = make(4000.0, "spotter")
	var bm: BattleManager = c.bm
	seed(2468)
	var trials := 800
	var first_in_25 := 0
	var adjusted_in_25 := 0
	for i in trials:
		bm._mortar_fire_adjustment.erase(c.mortar)
		var off0: Vector2 = bm._mortar_dispersion_offset(c.mortar, c.target, c.target.global_position)
		if off0.length() <= 25.0 * GameConfig.PIXELS_PER_METER:
			first_in_25 += 1
		for r in 6: # six observed corrections, each landing and seen
			bm.scenario_elapsed_time += 40.0
			bm._note_round_landed(c.mortar, c.target)
		var off6: Vector2 = bm._mortar_dispersion_offset(c.mortar, c.target, c.target.global_position)
		if off6.length() <= 25.0 * GameConfig.PIXELS_PER_METER:
			adjusted_in_25 += 1
	var p_first: float = float(first_in_25) / float(trials)
	var p_adj: float = float(adjusted_in_25) / float(trials)
	check(p_first < 0.08, "A5: a first round at 4 km lands within 25 m of an unmoving target under 8%% of the time (%.1f%%)" % (100.0 * p_first))
	check(p_adj > 0.15 and p_adj < 0.65, "A5: an adjusted round at 4 km lands within 25 m of an unmoving target 15-65%% of the time, not nearly always (%.0f%%)" % (100.0 * p_adj))
	c.bm.combat_log.free()
	c.bm.free()

	# A6. the blast: 50% of exposed men at the cited casualty radius; the far field small; cover (lying 1/3 in the UK WWII figures; a trench
	# a small fraction)
	var r: float = GameConfig.MORTAR_BLAST_CASUALTY_RADIUS
	var open_at_r: float = CombatResolver.blast_casualty_chance(r, 1.0, GameConfig.TerrainType.OPEN)
	check(absf(open_at_r - 0.5) < 0.01, "A6: half of the exposed are casualties at the casualty radius (%.2f)" % open_at_r)
	check(CombatResolver.blast_casualty_chance(0.0, 1.0, GameConfig.TerrainType.OPEN) > 0.99, "A6: certain at the impact point")
	check(CombatResolver.blast_casualty_chance(100.0 * GameConfig.PIXELS_PER_METER, 1.0, GameConfig.TerrainType.OPEN) < 0.03, "A6: under 3%% at 100 m in the open (%.3f)" % CombatResolver.blast_casualty_chance(100.0 * GameConfig.PIXELS_PER_METER, 1.0, GameConfig.TerrainType.OPEN))
	var trees_ratio: float = CombatResolver.blast_casualty_chance(r, 1.0, GameConfig.TerrainType.TREES) / open_at_r
	check(trees_ratio > 0.28 and trees_ratio < 0.5, "A6: trees reduce the risk to about a third (lying men, 1/3): %.2f" % trees_ratio)
	var building_ratio: float = CombatResolver.blast_casualty_chance(r, 1.0, GameConfig.TerrainType.BUILDING) / open_at_r
	check(building_ratio < 0.3, "A6: a building at least as protective as that (%.2f)" % building_ratio)

	# A7. the squad: a round on the centre of a squad of nine. The first anchor (casualty area x squad density: about 1.3-2.1 lying, three times that on
	# their feet) was replaced on 2026-10-22 by the user's three radii (R1 20 m, R2 40 m, R3 60 m: GameConfig.FRAGMENT_R1_M) for people standing and
	# without cover, each man rolled at his own distance over a squad spread of BLAST_SQUAD_SPREAD_M: on their feet nearly all of them are inside R1 or
	# R2, so a round on the centre costs about 8 of 9; lying, a third of the potentials apply to each man.
	GameConfig.set_active_map("voznesensk")
	GameConfig._build_terrain_grid()
	var squad: Unit = Unit.new()
	squad.kind = Unit.Kind.SQUAD
	squad.max_pips = 9
	squad.position = Vector2(-5000.0, -5000.0) * GameConfig.PIXELS_PER_METER # open ground
	check(GameConfig.get_terrain_type_at(squad.position) == GameConfig.TerrainType.OPEN, "A7 setup: open ground")
	seed(11)
	var standing_total := 0
	var lying_total := 0
	var squads := 2000
	for state in [false, true]:
		squad.gone_to_ground = state
		var n := 0
		for i in squads:
			for p in 9:
				var d: float = CombatResolver.person_distance_m(0.0, GameConfig.BLAST_SQUAD_SPREAD_M)
				if CombatResolver.fragment_severity(d, CombatResolver.fragment_exposure(squad, d, GameConfig.TerrainType.OPEN)) > 0:
					n += 1
		if state:
			lying_total = n
		else:
			standing_total = n
	var standing_cas: float = float(standing_total) / squads
	var lying_cas: float = float(lying_total) / squads
	check(standing_cas > 7.6 and standing_cas < 8.6, "A7: a round on the centre of a squad of nine on its feet in the open costs it about 8 (%.2f)" % standing_cas)
	check(lying_cas > 3.0 and lying_cas < 5.5, "A7: ... and lying about half that, 3-5.5 (%.2f)" % lying_cas)
	squad.free()

	print("Realism anchor tests: %d failures" % failures)
	quit(1 if failures else 0)
