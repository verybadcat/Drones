extends SceneTree
## Guards a real, reported bug: with more than one enemy mortar visible
## at once, the drone (and the friendly mortar's own hunt) was tracking
## whichever happened to come first in enemy_units (spawn order), not the
## one actually closest to our own mortar — "the drone is tracking the
## furthest enemy mortar." Also guards the two accompanying requirements:
## a small hysteresis margin so nearly-equidistant candidates don't flip
## the pick back and forth on ordinary movement jitter, and a RETREATING
## (gun-abandoned) mortar staying lower priority than an ACTIVE one
## regardless of which is closer.
##
## Run: godot --headless --path . --script scripts/tests/test_closest_enemy_mortar_lead.gd
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


func test_prefers_the_closer_of_two_active_visible_mortars() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(0, 0))
	bm.player_units.append(mortar)
	# Farther one placed FIRST in enemy_units — the previously-reported
	# bug picked whichever came first, so this must not just coincidentally
	# pass because the closer one happens to be first.
	var far_enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(1000, 0))
	far_enemy.is_visible = true
	bm.enemy_units.append(far_enemy)
	var near_enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(200, 0))
	near_enemy.is_visible = true
	bm.enemy_units.append(near_enemy)

	var lead: Dictionary = bm._known_enemy_mortar_lead()
	check(lead.get("unit", null) == near_enemy,
		"With two active visible enemy mortars, the CLOSER one to our own mortar must win, not whichever came first in enemy_units")

	var priority: Dictionary = bm._priority_visible_enemy_mortar()
	check(priority.get("unit", null) == near_enemy,
		"The drone's own priority-mortar pick must agree with the hunt lead: closer, not first-in-array")


func test_does_not_flip_on_a_marginal_difference() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(0, 0))
	bm.player_units.append(mortar)
	var a: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(500, 0))
	a.is_visible = true
	bm.enemy_units.append(a)
	var b: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(500 + GameConfig.MORTAR_LEAD_SWITCH_MARGIN * 0.5, 0))
	b.is_visible = true
	bm.enemy_units.append(b)

	var first_pick: Unit = bm._known_enemy_mortar_lead().unit
	check(first_pick == a, "With nothing yet locked in, the genuinely closer candidate should win the first pick")

	# Nudge `a` slightly farther than `b`, but by LESS than the switch
	# margin — the sticky pick must not flip for a difference this small.
	a.global_position = Vector2(500 + GameConfig.MORTAR_LEAD_SWITCH_MARGIN * 0.3, 0)
	var second_pick: Unit = bm._known_enemy_mortar_lead().unit
	check(second_pick == a,
		"A marginal difference (well under MORTAR_LEAD_SWITCH_MARGIN) must not flip the sticky pick away from the mortar already being tracked")

	# Now push `a` CLEARLY farther — comfortably past the margin — and
	# confirm the pick does switch once the difference is real.
	a.global_position = Vector2(500 + GameConfig.MORTAR_LEAD_SWITCH_MARGIN * 3.0, 0)
	var third_pick: Unit = bm._known_enemy_mortar_lead().unit
	check(third_pick == b,
		"Once a candidate is CLEARLY closer (beyond the switch margin), the pick must actually switch, not stay stuck forever")


func test_retreating_mortar_stays_lower_priority_even_if_closer() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(0, 0))
	bm.player_units.append(mortar)
	# The RETREATING one is placed much closer than the ACTIVE one — must
	# still lose, matching the user's own explicit caveat.
	var retreating_near: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(100, 0))
	retreating_near.is_visible = true
	retreating_near.state = Unit.State.RETREATING
	bm.enemy_units.append(retreating_near)
	var active_far: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(900, 0))
	active_far.is_visible = true
	bm.enemy_units.append(active_far)

	var lead: Dictionary = bm._known_enemy_mortar_lead()
	check(lead.get("unit", null) == active_far,
		"An ACTIVE mortar must outrank a RETREATING one regardless of which is closer")


func run() -> void:
	test_prefers_the_closer_of_two_active_visible_mortars()
	test_does_not_flip_on_a_marginal_difference()
	test_retreating_mortar_stays_lower_priority_even_if_closer()
	print("Closest-enemy-mortar-lead tests: %d failures" % failures)
	quit(1 if failures else 0)
