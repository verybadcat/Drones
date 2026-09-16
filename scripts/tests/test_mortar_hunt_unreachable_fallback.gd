extends SceneTree
## Guards a real, live bug found directly in the user's own running game
## (via the always-on debug_state/mortar_decision_snapshot.json): a
## mortar whose known enemy-mortar fix sits far enough beyond
## MORTAR_HUNT_MAX_RANGE_FROM_HOME that no angle _friendly_mortar_hunt_
## point tries can ever satisfy the home leash was frozen repeating
## "Wants to close on a known enemy mortar, no acceptable route this
## tick" every single tick, forever — a geometric relationship that
## never changes tick to tick, so retrying identically never helped. The
## user: "I am seeing bad oscillation of the friendly mortar... it looked
## like it was oscillating slightly. But either way, it's bad."
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_hunt_unreachable_fallback.gd
const Orders = preload("res://scripts/unit_doctrine.gd")
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


func test_unreachable_hunt_fix_falls_through_to_holding_instead_of_freezing() -> void:
	var bm = make_battle()
	var home: Vector2 = Vector2(0, 500)
	bm._friendly_mortar_home_position = home
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, home)
	mortar.mortar_rounds_remaining = 10
	mortar.seconds_stationary = 1e9
	bm.player_units.append(mortar)

	# Live and visible, well beyond mortar_max_range(PLAYER)*0.9 +
	# MORTAR_HUNT_MAX_RANGE_FROM_HOME combined from `home` in every
	# direction — no angle _friendly_mortar_hunt_point tries can ever
	# land within the home leash, exactly reproducing the live scenario.
	var enemy_mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, home + Vector2(5000, 0))
	bm.enemy_units.append(enemy_mortar)
	enemy_mortar.is_visible = true

	bm.unit_type_doctrines[Unit.Team.PLAYER] = Orders.sanitize({})

	# The real reported symptom: calling this repeatedly (simulating many
	# ticks of the exact same, unchanging geometry) must NOT get stuck
	# reporting the same "trying to hunt" tier forever.
	for i in 5:
		bm._decide_mortar_action(mortar)
	var reasoning: Dictionary = bm._mortar_reasoning.get(mortar, {})
	check(reasoning.get("tier", "") != "Destroy enemy mortars",
		"A mortar with a permanently unreachable hunt fix must fall through to another tier (Holding) rather than freezing in the hunt tier forever — got tier '%s'" % reasoning.get("tier", "<none>"))
	check(not mortar.has_move_target,
		"A mortar that can't find any real hunt route, evade reason, or displacement need should simply hold in place, not have a stale/no-op move order")


## The user's own direct correction after the fallback above was already
## in place: "The range leash is not an absolute thing. The mortar could
## reasonably go briefly outside of it, but then back in to take a
## shot." A trusted (confirmed, currently-watched) target just beyond
## MORTAR_HUNT_MAX_RANGE_FROM_HOME, but still within the real, bounded
## MORTAR_HUNT_EXTENDED_RANGE_FROM_HOME allowance, must not be rejected.
func test_trusted_target_beyond_ordinary_leash_still_reachable() -> void:
	var bm = make_battle()
	var home: Vector2 = Vector2(0, 500)
	bm._friendly_mortar_home_position = home
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, home)
	bm.player_units.append(mortar)

	# target_distance = mortar_max_range(PLAYER) * 0.9 = 810 — placing the
	# target 1500 units east of home puts the natural (offset 0) hunt
	# candidate at (690, 500): 690 units from home — beyond the 450-unit
	# ordinary leash, comfortably inside the 900-unit extended one.
	var target_pos: Vector2 = home + Vector2(1500, 0)
	var dest: Vector2 = bm._mortar_hunt_destination_for(mortar, target_pos, true)
	check(dest != mortar.global_position,
		"A TRUSTED target just beyond the ordinary hunt leash, but within the extended one, must still produce a real hunt destination, not a refusal")
	check(dest.distance_to(home) <= GameConfig.MORTAR_HUNT_EXTENDED_RANGE_FROM_HOME + 1.0,
		"The hunt destination itself must still respect the extended leash as a real, bounded cap — not an unlimited excursion")


## The mirror case: an UNTRUSTED (bare, unconfirmed) lead at the exact
## same distance must NOT get the extended allowance — matching the same
## real distinction MORTAR_HUNT_UNTRUSTED_MAX_RELOCATE already draws.
func test_untrusted_target_beyond_ordinary_leash_stays_rejected() -> void:
	var bm = make_battle()
	var home: Vector2 = Vector2(0, 500)
	bm._friendly_mortar_home_position = home
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, home)
	bm.player_units.append(mortar)

	var target_pos: Vector2 = home + Vector2(1500, 0)
	var dest: Vector2 = bm._mortar_hunt_destination_for(mortar, target_pos, false)
	check(dest == mortar.global_position,
		"An UNTRUSTED lead beyond the ordinary hunt leash must NOT get the same extended allowance a trusted one does — a real crew won't gamble a long excursion on an unconfirmed position")


func run() -> void:
	test_unreachable_hunt_fix_falls_through_to_holding_instead_of_freezing()
	test_trusted_target_beyond_ordinary_leash_still_reachable()
	test_untrusted_target_beyond_ordinary_leash_stays_rejected()
	print("Mortar hunt-unreachable-fallback tests: %d failures" % failures)
	quit(1 if failures else 0)
