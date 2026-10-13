extends SceneTree
## Close quarters: the tools other than rifles. User: "if the enemy gets close enough, I assume tools other than guns become an issue."
## Within 25 m opposing units exchange grenades from their own stock (a third of the people throwing, each grenade doing the casualties its
## target's cover allows, and more in a building or a hole: a confined space), inside 8 m hand to hand besides; both sides at once;
## independent of rifle ammunition; a squad that is dry or has lost half its people may surrender once it is in melee range.
##
## Run: godot --headless --path . --script scripts/tests/test_close_quarters.gd
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

func make() -> Dictionary:
	GameConfig.set_active_map("voznesensk")
	GameConfig._build_terrain_grid()
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.scenario_elapsed_time = 1000.0
	var rect: Rect2 = GameConfig._building_rects[0]
	var open_point := Vector2.INF
	for dx in [-90.0, 90.0, -140.0, 140.0]:
		var p: Vector2 = Vector2(rect.position.x if dx < 0.0 else rect.end.x, rect.get_center().y) + Vector2(dx, 0.0) * GameConfig.PIXELS_PER_METER
		if GameConfig.get_terrain_type_at(p) == GameConfig.TerrainType.OPEN:
			open_point = p
			break
	return {"bm": bm, "open": open_point, "building": rect.get_center()}

func unit(c: Dictionary, team: Unit.Team, kind: Unit.Kind, point: Vector2) -> Unit:
	var u: Unit = c.bm._make_unit(team, kind, point)
	if team == Unit.Team.PLAYER:
		c.bm.player_units.append(u)
	else:
		c.bm.enemy_units.append(u)
	return u

func cleanup(c: Dictionary) -> void:
	c.bm.combat_log.free()
	c.bm.free()

func round_once(c: Dictionary) -> void:
	c.bm._update_close_quarters(GameConfig.CLOSE_QUARTERS_ROUND_S)

## Mean casualties on [ours, theirs] over `trials` fresh pairs `d` metres apart, `setup` run on each (ours, theirs) first.
func mean_losses(c: Dictionary, d: float, trials: int, setup: Callable = Callable()) -> Array:
	var ours := 0.0
	var theirs := 0.0
	for i in trials:
		var a: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, c.open)
		var b: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.open + m(d))
		a.retreat_threshold = 2.0 # never: taking casualties does not trip a retreat in the middle of a measurement
		b.retreat_threshold = 2.0
		if setup.is_valid():
			setup.call(a, b)
		round_once(c)
		ours += float(9 - a.pips)
		theirs += float(9 - b.pips)
		c.bm.player_units.erase(a)
		c.bm.enemy_units.erase(b)
		a.free()
		b.free()
	return [ours / trials, theirs / trials]

func run() -> void:
	var c := make()
	check(not is_inf(c.open.x), "Setup: open ground near a building")
	var cap: int = int(ceil(9.0 * GameConfig.GRENADES_THROWN_FRACTION))
	var per_grenade: float = GameConfig.GRENADE_CASUALTIES_OPEN
	seed(3131)

	# 1. out of reach: nothing; in grenade range: the grenades, a few; in melee range: those and hand to hand
	var far: Array = mean_losses(c, 30.0, 150)
	check(far[0] == 0.0 and far[1] == 0.0, "Beyond 25 m nothing is exchanged (%.2f, %.2f)" % [far[0], far[1]])
	var grenade_range: Array = mean_losses(c, 18.0, 400)
	var expected_grenades: float = float(cap) * per_grenade
	check(absf(grenade_range[0] - expected_grenades) < 0.3 and absf(grenade_range[1] - expected_grenades) < 0.3, "Within 25 m: about %d grenades at %.2f each, a side (%.2f, %.2f against %.2f)" % [cap, per_grenade, grenade_range[0], grenade_range[1], expected_grenades])
	var melee_range: Array = mean_losses(c, 5.0, 400)
	var expected_melee: float = expected_grenades + 9.0 * GameConfig.MELEE_CHANCE_PER_PERSON_PER_ROUND
	check(absf(melee_range[0] - expected_melee) < 0.35 and melee_range[0] > grenade_range[0] + 0.3, "Inside 8 m hand to hand as well (%.2f against %.2f)" % [melee_range[0], expected_melee])

	# 2. the stock: spent, never replenished, and a squad with none left still has hand to hand
	var a: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, c.open)
	var b: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.open + m(5))
	a.retreat_threshold = 2.0
	b.retreat_threshold = 2.0
	check(a.grenades == 9 * GameConfig.GRENADES_PER_PERSON, "A squad starts with %d grenades (%d)" % [9 * GameConfig.GRENADES_PER_PERSON, a.grenades])
	round_once(c)
	check(a.grenades == 9 * GameConfig.GRENADES_PER_PERSON - cap, "A round costs %d grenades (%d left)" % [cap, a.grenades])
	a.grenades = cap # what is left when the stock is down to one more round
	b.grenades = cap
	a.pips = 9
	b.pips = 9
	a.state = Unit.State.ACTIVE
	b.state = Unit.State.ACTIVE
	round_once(c)
	check(a.grenades == 0 and b.grenades == 0, "...and in the end none are left (%d, %d)" % [a.grenades, b.grenades])
	var melee_only := 0.0
	for i in 80:
		a.pips = 9
		b.pips = 9
		a.state = Unit.State.ACTIVE
		b.state = Unit.State.ACTIVE
		round_once(c)
		melee_only += float(9 - b.pips)
	check(a.grenades == 0 and melee_only / 80.0 > 0.3 and melee_only / 80.0 < 1.0, "With no grenades left, hand to hand still goes on (%.2f a round) and nothing is replenished (%d)" % [melee_only / 80.0, a.grenades])
	c.bm.player_units.erase(a)
	c.bm.enemy_units.erase(b)
	a.free()
	b.free()

	# 3. cover does not protect against a grenade thrown into it: a building and a hole are worse than the open
	var in_open: Array = mean_losses(c, 18.0, 500)
	var in_building: Array = mean_losses(c, 18.0, 500, func(x: Unit, y: Unit) -> void:
		y.global_position = c.building
		x.global_position = c.building + m(18))
	check(in_building[1] > in_open[1] + 0.4, "A squad in a building loses more to grenades than one in the open (%.2f against %.2f)" % [in_building[1], in_open[1]])
	var in_hole: Array = mean_losses(c, 18.0, 500, func(x: Unit, y: Unit) -> void:
		y.entrenchment = Unit.Entrenchment.FIGHTING_POSITION)
	check(in_hole[1] > in_open[1] + 0.15 and in_hole[1] < in_building[1], "...a fighting position in between (%.2f)" % in_hole[1])

	# 4. a crew can be on the receiving end, and hits back by hand when close
	var crew_losses := 0.0
	for i in 300:
		var raiders: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, c.open)
		var crew: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.MORTAR, c.open + m(18))
		crew.mortar_rounds_remaining = 0
		round_once(c)
		crew_losses += float(crew.crew_casualties)
		c.bm.player_units.erase(raiders)
		c.bm.enemy_units.erase(crew)
		raiders.free()
		crew.free()
	check(crew_losses / 300.0 > 0.6 and crew_losses / 300.0 < 1.8, "A mortar crew 18 m from a squad loses about as a squad would to its grenades (%.2f)" % (crew_losses / 300.0))

	# 5. overrun: a squad in melee range that is dry or halved may surrender; a healthy one with ammunition does not
	var surrendered_dry := 0
	var surrendered_healthy := 0
	for i in 200:
		var strong: Unit = unit(c, Unit.Team.PLAYER, Unit.Kind.SQUAD, c.open)
		var weak: Unit = unit(c, Unit.Team.ENEMY, Unit.Kind.SQUAD, c.open + m(5))
		weak.rounds = 0
		weak.retreat_threshold = 2.0
		strong.retreat_threshold = 2.0
		round_once(c)
		if weak.state == Unit.State.SURRENDERED:
			surrendered_dry += 1
		if strong.state == Unit.State.SURRENDERED:
			surrendered_healthy += 1
		c.bm.player_units.erase(strong)
		c.bm.enemy_units.erase(weak)
		strong.free()
		weak.free()
	check(surrendered_dry > 20 and surrendered_dry < 190 and surrendered_healthy < 8, "A dry squad overrun often lays down its arms (%d of 200); the one with ammunition and its people almost never does (%d)" % [surrendered_dry, surrendered_healthy])
	cleanup(c)

	print("Close quarters tests: %d failures" % failures)
	quit(1 if failures else 0)
