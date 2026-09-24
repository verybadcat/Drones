extends SceneTree
## Direct user request, after a live battle in which every friendly squad had
## withdrawn and the enemy squads sat at the village while the friendly mortar
## (out of ammunition, silent) sat 3 km away: "With no friendly squads left in
## action, the enemy squads should definitely be hunting our mortar ... A 3:1
## superiority over friendly squads they are fighting should allow any squads they
## have beyond that to chase the mortar. Otherwise, the existing max can apply.
## In this case, with no friendly squads remaining, all enemy squads would hunt
## the mortar -- though they could still fire at targets of opportunity."
##
## Two parts: (1) the cap on how many squads may chase the mortar at once is
## max(MORTAR_HUNT_SQUAD_CAP, enemy squads - 3 x friendly squads in action), and
## (2) with no friendly squad in action, an enemy whose fix on the mortar has
## lapsed advances toward where it was last known rather than sitting on the village.
##
## Run: godot --headless --path . --script scripts/tests/test_enemy_mortar_hunt_superiority.gd
const Orders = preload("res://scripts/unit_doctrine.gd")
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(v: float) -> float:
	return v * GameConfig.PIXELS_PER_METER

## `enemy` ACTIVE enemy squads, `friendly` ACTIVE friendly squads, `retreating`
## RETREATING friendly squads, and the friendly mortar at the origin (visible, so
## its position is a current fix). Enemy squads sit at increasing distances inside
## hot-pursuit range but beyond engagement range, closest first.
func make_battle(enemy: int, friendly: int, retreating: int = 0):
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.unit_type_doctrines[Unit.Team.ENEMY] = Orders.sanitize({})
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	bm.player_units.append(mortar)
	mortar.is_visible = true
	for i in friendly:
		var f: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(-m(3000), m(200) * i))
		bm.player_units.append(f)
	for i in retreating:
		var r: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(-m(3000), -m(200) * (i + 1)))
		bm.player_units.append(r)
		r.state = Unit.State.RETREATING
	for i in enemy:
		var pos := Vector2(GameConfig.SQUAD_ENGAGEMENT_RANGE * 1.2 + GameConfig.SQUAD_ENGAGEMENT_RANGE * 0.05 * i, 0)
		var s: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, pos)
		s.sought_cover = true
		bm.enemy_units.append(s)
	return bm

func cleanup(bm) -> void:
	bm.combat_log.free()
	bm.free()

func run() -> void:
	test_the_cap_follows_the_superiority()
	test_the_change_never_lowers_the_number_of_hunters()
	test_assignments_use_the_cap_and_the_closest_first()
	test_only_squads_in_action_count()
	test_with_no_friendly_squads_the_enemy_looks_for_the_mortar()
	test_the_current_battle_shape()
	print("Enemy mortar hunt superiority tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_the_cap_follows_the_superiority() -> void:
	var base: int = GameConfig.MORTAR_HUNT_SQUAD_CAP
	# [enemy squads, friendly squads in action, expected cap]
	for c in [[10, 3, base], [12, 3, base], [13, 3, 4], [16, 3, 7], [7, 2, base], [9, 2, base], [10, 2, 4], [8, 0, 8], [1, 0, base], [4, 1, base], [5, 1, 3], [6, 1, 3], [7, 1, 4]]:
		var bm = make_battle(c[0], c[1])
		check(bm._mortar_hunt_cap() == c[2], "%d enemy squads vs %d friendly: cap %d, got %d" % [c[0], c[1], c[2], bm._mortar_hunt_cap()])
		cleanup(bm)


## Direct user constraint: "don't need any change that lowers the number of
## squads that hunt the mortar." The new cap only ever ADDS hunters: it is never
## below the old fixed cap, and never more than the eligible squads there are.
func test_the_change_never_lowers_the_number_of_hunters() -> void:
	var base: int = GameConfig.MORTAR_HUNT_SQUAD_CAP
	for enemy in range(0, 21):
		for friendly in range(0, 9):
			var bm = make_battle(enemy, friendly)
			var cap: int = bm._mortar_hunt_cap()
			check(cap >= base, "%d enemy vs %d friendly: cap %d must never be below the old cap of %d" % [enemy, friendly, cap, base])
			var hunters: int = bm._mortar_hunt_assignments().size()
			check(hunters == mini(enemy, cap), "%d enemy vs %d friendly: %d hunt, expected min(enemy, cap) = %d" % [enemy, friendly, hunters, mini(enemy, cap)])
			check(hunters >= mini(enemy, base), "%d enemy vs %d friendly: %d hunt, never fewer than the old cap would send (%d)" % [enemy, friendly, hunters, mini(enemy, base)])
			cleanup(bm)


func test_assignments_use_the_cap_and_the_closest_first() -> void:
	# The reported case: no friendly squad left, so ALL of them hunt.
	var bm = make_battle(6, 0)
	var n: int = bm._mortar_hunt_assignments().size()
	check(n == 6, "With no friendly squads, every enemy squad hunts the mortar (%d of 6)" % n)
	cleanup(bm)
	# Even outnumbering a single friendly squad by 3:1, the spare ones go.
	bm = make_battle(7, 1)
	var assigned: Dictionary = bm._mortar_hunt_assignments()
	check(assigned.size() == 4, "7 vs 1: 3 are needed against it, 4 are free to chase (got %d)" % assigned.size())
	# ...and they are the ones nearest the mortar (built closest-first).
	var nearest_four := true
	for i in 4:
		if not assigned.has(bm.enemy_units[i]):
			nearest_four = false
	check(nearest_four, "The squads chosen are the closest to the mortar")
	cleanup(bm)
	# Without the superiority the old cap applies unchanged.
	bm = make_battle(6, 2)
	check(bm._mortar_hunt_assignments().size() == GameConfig.MORTAR_HUNT_SQUAD_CAP, "6 vs 2 is only 3:1 with nothing spare: the ordinary cap of %d" % GameConfig.MORTAR_HUNT_SQUAD_CAP)
	cleanup(bm)


## "Friendly squads in action" — retreating ones are targets of opportunity, not
## what the enemy has to be held back against.
func test_only_squads_in_action_count() -> void:
	var bm = make_battle(8, 0, 2)
	check(bm._friendly_squads_in_action() == 0, "Retreating friendly squads are not in action")
	check(bm._mortar_hunt_cap() == 8, "...so with only retreating squads left, all 8 enemy squads may hunt")
	cleanup(bm)
	bm = make_battle(8, 0)
	var gone: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2.ZERO)
	bm.player_units.append(gone)
	gone.state = Unit.State.WITHDRAWN
	check(bm._friendly_squads_in_action() == 0, "Withdrawn squads are not in action either")
	cleanup(bm)


## Part 2: the fix on the mortar lapses after MORTAR_FIRE_DETECTION_EXPIRY; with no
## friendly squad in action the enemy then heads for where it was last known.
func test_with_no_friendly_squads_the_enemy_looks_for_the_mortar() -> void:
	var village: Vector2 = GameConfig.CURRENT_MAP.village_center
	var bm = make_battle(3, 0)
	var mortar: Unit = bm.player_units[0]
	mortar.is_visible = false
	mortar.global_position = Vector2(-m(1400), m(1900))
	var heard_at := Vector2(-m(1200), m(1800))
	bm._last_detected_mortar_fire[mortar] = {"position": heard_at, "time": bm.scenario_elapsed_time}
	bm.scenario_elapsed_time += GameConfig.MORTAR_FIRE_DETECTION_EXPIRY + 600.0
	check(is_inf(bm._known_friendly_mortar_position().x), "Setup: the fix has lapsed")
	check(bm._enemy_advance_objective().distance_to(heard_at) < 1.0, "No friendly squads in action: the objective is where the mortar was last heard, not the village")
	# Seen more recently than heard: the sighting wins.
	mortar.enemy_has_been_sighted = true
	mortar.enemy_known_position = Vector2(-m(1350), m(1880))
	mortar.enemy_known_position_time = bm.scenario_elapsed_time - 100.0
	check(bm._enemy_advance_objective().distance_to(mortar.enemy_known_position) < 1.0, "The freshest of last-seen / last-heard is used")
	# A friendly squad in action: the assault's objective stays the village.
	var f: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(-m(500), m(1700)))
	bm.player_units.append(f)
	check(bm._enemy_advance_objective().distance_to(village) < 1.0, "With a friendly squad still in action the objective is the village, as before")
	f.state = Unit.State.RETREATING
	check(bm._enemy_advance_objective().distance_to(mortar.enemy_known_position) < 1.0, "A retreating one no longer holds them to the village")
	# Nothing ever known: village. Mortar gone: village.
	mortar.enemy_has_been_sighted = false
	bm._last_detected_mortar_fire.clear()
	check(bm._enemy_advance_objective().distance_to(village) < 1.0, "A mortar never seen or heard gives them nothing to look for: the village")
	bm._last_detected_mortar_fire[mortar] = {"position": heard_at, "time": 0.0}
	mortar.state = Unit.State.WITHDRAWN
	check(bm._enemy_advance_objective().distance_to(village) < 1.0, "A mortar that has left the fight is no objective")
	cleanup(bm)


## The reported situation: enemy squads sitting on the village, every friendly
## squad withdrawn, the mortar far to the west and silent. They must set off for
## it instead of holding.
##
## The advance-by-bounds step (_next_advance_point) picks among bent candidate
## directions with a weighted random roll ("usually isn't always": about 3-4% of
## rolls step away from the objective for cover), so "every squad heads toward it"
## cannot be asserted for one roll. What the feature promises is (a) every squad is
## given an advance order and (b) the overwhelming majority of those orders close on
## the mortar's last known position — checked over many trials.
func test_the_current_battle_shape() -> void:
	seed(11)
	var village: Vector2 = GameConfig.CURRENT_MAP.village_center
	var ordered := 0
	var closing := 0
	var total := 0
	var offsets := [Vector2(-370, 54), Vector2(-218, 79), Vector2(-222, 65), Vector2(59, 140)]
	for trial in 40:
		var bm = make_battle(0, 0, 3)
		var mortar: Unit = bm.player_units[0]
		mortar.is_visible = false
		mortar.global_position = Vector2(-m(1457), m(1940))
		bm._last_detected_mortar_fire[mortar] = {"position": Vector2(-m(1300), m(1900)), "time": 0.0}
		bm.scenario_elapsed_time = 5000.0
		var objective: Vector2 = bm._enemy_advance_objective()
		if trial == 0:
			check(objective.distance_to(Vector2(-m(1300), m(1900))) < 1.0, "Setup: their objective is where the mortar was last heard")
		var squads: Array[Unit] = []
		for off in offsets:
			var s: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, village + Vector2(m(off.x), m(off.y)))
			s.sought_cover = true
			bm.enemy_units.append(s)
			squads.append(s)
		bm._update_enemy_squad_advance()
		for s in squads:
			total += 1
			if s.has_move_target:
				ordered += 1
				if s.move_target.distance_to(objective) < s.global_position.distance_to(objective):
					closing += 1
		if trial == 0:
			# Control (once): with a friendly squad still in action they hold the
			# village — squads already standing on it have nothing to advance to.
			var f: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2(-m(900), m(1900)))
			bm.player_units.append(f)
			for s in squads:
				s.global_position = village
				s.has_move_target = false
				s.move_queue.clear()
			bm._update_enemy_squad_advance()
			var moving := 0
			for s in squads:
				if s.has_move_target:
					moving += 1
			check(moving == 0, "Control: with a friendly squad in action they hold the village, as before (%d moved)" % moving)
		cleanup(bm)
	check(ordered == total, "Every enemy squad is given an advance order (%d of %d)" % [ordered, total])
	check(float(closing) / float(total) >= 0.85, "The great majority of the orders close on the mortar's last known position (%d of %d)" % [closing, total])
