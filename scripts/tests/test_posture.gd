extends SceneTree
## Posture (docs/designs/posture-and-suppression.md, stages A and C). Direct user ruling: "Posture should be something that all units have at all
## times. Not just tied to particular situations such as mortar fire. A moving unit has to be standing up."
##
## Every ground unit has a posture; a moving one is STANDING whatever else is true; and every place that asks "does this unit have terrain
## protection" asks the one function (Unit.exposure_terrain), so the answers cannot disagree: a direct shot, a shell's blast, a crew's
## casualty roll and the friendly-fire estimate. Posture is the person's and cover is the place's (stage C): a stationary unit has the
## terrain it is in whether it is upright or down, and a unit in a building is upright at its post, not lying on the floor, until fire
## gives it a reason. A unit on the move is upright and keeps part of its terrain's protection: nearly all of a building's, about half
## of the trees' (user: "Inside a building ... almost as good as being not moving. Probably very close. So yes, split by terrain.").
##
## Run: godot --headless --path . --script scripts/tests/test_posture.gd
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

func unit_at(team: Unit.Team, kind: Unit.Kind, point: Vector2, moving: bool) -> Unit:
	var u := Unit.new()
	u.setup(team, kind, point)
	u.activity = Unit.Activity.MOVING if moving else Unit.Activity.STATIONARY
	return u

func run() -> void:
	GameConfig.set_active_map("pishchane")
	var in_trees: Vector2 = m(-20, 2080)
	check(GameConfig.get_terrain_type_at(in_trees) == GameConfig.TerrainType.TREES, "Setup: a point in trees")
	GameConfig.set_active_map("voznesensk")
	GameConfig._build_terrain_grid()
	var in_building: Vector2 = GameConfig._building_rects[0].get_center()
	check(GameConfig.get_terrain_type_at(in_building) == GameConfig.TerrainType.BUILDING, "Setup: a point in a building")
	var open_v: Vector2 = m(-5000, -5000)
	var places := {GameConfig.TerrainType.OPEN: open_v, GameConfig.TerrainType.BUILDING: in_building}
	check(GameConfig.get_terrain_type_at(open_v) == GameConfig.TerrainType.OPEN, "Setup: open ground on the building map")

	# 1. every ground kind, every terrain: moving is standing and keeps part of its terrain's protection (cover_kept: all of it in the open,
	# which is nothing); stationary is upright at its post, with all of the protection of the terrain it is in
	var kinds := [Unit.Kind.SQUAD, Unit.Kind.MORTAR, Unit.Kind.SPOTTER, Unit.Kind.DRONE_TEAM, Unit.Kind.RESUPPLY_RUN]
	for kind in kinds:
		for terrain in places:
			var p: Vector2 = places[terrain]
			var name: String = "%s in %s" % [Unit.Kind.keys()[kind], GameConfig.TerrainType.keys()[terrain]]
			var moving := unit_at(Unit.Team.PLAYER, kind, p, true)
			check(moving.posture() == Unit.Posture.STANDING, "A moving %s is standing" % name)
			check(moving.exposure_terrain() == terrain, "A moving %s is in the terrain it is in" % name)
			var kept: float = moving.cover_kept()
			if terrain == GameConfig.TerrainType.OPEN:
				check(is_equal_approx(kept, 1.0), "A moving %s in the open has the open's nothing to keep" % name)
			else:
				check(kept > 0.8 and kept < 1.0, "A moving %s keeps nearly all of a building's protection (%.2f)" % [name, kept])
			var still := unit_at(Unit.Team.PLAYER, kind, p, false)
			check(still.posture() == Unit.Posture.STANDING, "A stationary %s that nothing has fired at is upright at its post" % name)
			check(is_equal_approx(still.posture_factor(), 1.0), "...so being down is worth nothing to it yet (%s)" % name)
			check(still.exposure_terrain() == terrain and is_equal_approx(still.cover_kept(), 1.0), "A stationary %s has all the protection of its terrain" % name)
			moving.free()
			still.free()
	var drone := unit_at(Unit.Team.PLAYER, Unit.Kind.DRONE, in_building, false)
	check(drone.posture() == Unit.Posture.STANDING and drone.exposure_terrain() == GameConfig.TerrainType.OPEN, "A drone, airborne, has no terrain to be down behind")
	drone.free()
	# a forecast asks about a place the unit is not at
	var elsewhere := unit_at(Unit.Team.PLAYER, Unit.Kind.SQUAD, open_v, false)
	check(elsewhere.posture(in_building) == Unit.Posture.STANDING and elsewhere.exposure_terrain(in_building) == GameConfig.TerrainType.BUILDING, "Asked about a place in a building, a stationary unit would be upright in it and have it")
	elsewhere.activity = Unit.Activity.MOVING
	check(elsewhere.posture(in_building) == Unit.Posture.STANDING, "...and a moving one would not")
	elsewhere.free()

	# 2. a direct shot: a moving unit in a building is hit a little more often than a still one and far less often than one in the open;
	# a still one in cover is far safer than one in the open; standing still in the open is as exposed as being caught moving in it
	# (the existing calibration, SQUAD_COVER_MULTIPLIER's note)
	var shooter := unit_at(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2.ZERO, false)
	var target := unit_at(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2.ZERO, false)
	var from: Vector2 = Vector2(300.0, 0.0) * GameConfig.PIXELS_PER_METER
	target.activity = Unit.Activity.MOVING
	var moving_building: float = CombatResolver.hit_probability(shooter, target, 1.0, in_building, in_building + from)
	var moving_open: float = CombatResolver.hit_probability(shooter, target, 1.0, open_v, open_v + from)
	check(moving_building < 0.2 * moving_open, "A moving squad in a building is far harder to hit than one moving in the open (%.4f against %.4f)" % [moving_building, moving_open])
	target.activity = Unit.Activity.STATIONARY
	var still_building: float = CombatResolver.hit_probability(shooter, target, 1.0, in_building, in_building + from)
	var still_open: float = CombatResolver.hit_probability(shooter, target, 1.0, open_v, open_v + from)
	check(still_building < 0.2 * still_open, "A stationary squad in a building is far harder to hit than one in the open (%.4f against %.4f)" % [still_building, still_open])
	check(is_equal_approx(still_open, moving_open), "Standing still in the open is as exposed as moving (%.4f against %.4f)" % [still_open, moving_open])
	check(moving_building > still_building and moving_building < 1.6 * still_building, "A squad moving in a building is a little easier to hit than a still one, not many times (%.4f against %.4f)" % [moving_building, still_building])
	shooter.free()
	target.free()

	# 3. a shell's blast and the friendly-fire estimate: the same terrain rule. An own squad in a building 20 m from the aim point is
	# endangered more when it is on the move (in trees here).
	GameConfig.set_active_map("pishchane")
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var gun: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(0, 2080))
	bm.player_units.append(gun)
	var foe: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(1500, 2080))
	bm.enemy_units.append(foe)
	foe.is_visible = true
	var own: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, in_trees)
	bm.player_units.append(own)
	var aim: Vector2 = in_trees + m(65, 0) # out where only the weak fragments of the third radius reach (nearer, nine people make the risk nearly 1 either way)
	own.activity = Unit.Activity.STATIONARY
	var risk_down: float = bm._mortar_friendly_fire_check(gun, foe, aim).risk
	own.activity = Unit.Activity.MOVING
	var risk_up: float = bm._mortar_friendly_fire_check(gun, foe, aim).risk
	check(risk_up > 1.5 * risk_down and risk_down > 0.0, "The friendly-fire estimate counts a squad on the move as exposed and one down in trees as protected (%.3f on the move, %.3f in the trees)" % [risk_up, risk_down])
	bm.combat_log.free()
	bm.free()

	# 4. a crew's own casualty roll for a direct HE hit, rounds at the casualty radius so the chances are not 0 or 1: a crew down in trees
	# is protected, one on the move through them has part of it, one in the open has none
	var trials := 600
	var still_total := 0
	var moving_total := 0
	var open_total := 0
	for i in trials:
		var crew := unit_at(Unit.Team.PLAYER, Unit.Kind.MORTAR, in_trees, false)
		crew._apply_crew_casualties([], [], true, GameConfig.MORTAR_BLAST_CASUALTY_RADIUS)
		still_total += crew.crew_casualties
		crew.free()
		var walking := unit_at(Unit.Team.PLAYER, Unit.Kind.MORTAR, in_trees, true)
		walking._apply_crew_casualties([], [], true, GameConfig.MORTAR_BLAST_CASUALTY_RADIUS)
		moving_total += walking.crew_casualties
		walking.free()
		var exposed := unit_at(Unit.Team.PLAYER, Unit.Kind.MORTAR, open_v, false)
		exposed._apply_crew_casualties([], [], true, GameConfig.MORTAR_BLAST_CASUALTY_RADIUS)
		open_total += exposed.crew_casualties
		exposed.free()
	check(still_total > 0 and moving_total > 1.2 * still_total and moving_total < 0.95 * open_total, "A crew moving through trees takes a direct HE hit between a still one in them and one in the open (%d, %d, %d casualties in %d rounds)" % [still_total, moving_total, open_total, trials])

	print("Posture tests: %d failures" % failures)
	quit(1 if failures else 0)
