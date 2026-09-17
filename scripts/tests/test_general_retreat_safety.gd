extends SceneTree
## Guards a real, live-observed general-retreat failure, refined across
## several real incidents in the same session. User's own words, in order:
##
## 1. "The primary consideration in retreating is safety. Cover may be a
##    way to achieve safety. But in this case, I don't think it was. The
##    locations of the enemy squads was known. People could have just
##    retreated backwards safely." Confirmed directly from a real battle
##    replay: several squads with no known enemy anywhere near them all
##    detoured to the SAME distant tree before ever starting the straight
##    pull home.
## 2. After a mortar was destroyed taking a long detour to reach cover
##    anyway: "The primary consideration should be safety, not cover...
##    We want a safe path. Cover is one way to achieve that. But avoiding
##    the enemy could often be better. I'm concerned that you may be
##    over-emphasizing cover at a basic level."
##
## Root cause, in its final form: Unit.order_retreat used to send a unit
## to seek actual cover whenever ANY known enemy position sat within a
## fairly generous "worth reacting to at all" radius (the same one
## BattleManager._retreat_avoidance_offset uses for its own continuous
## bending) — treating a merely-known position as reason enough for a
## real, single, fixed detour. Real cover/concealment earns its cost by
## breaking LINE OF SIGHT to something that can actually see or reach this
## unit right now, not by a position merely existing somewhere nearby.
## Fixed: a unit now only seeks real cover if it is CURRENTLY VISIBLE, or
## a known enemy is within actual direct-fire/overrun range AND has real
## direct LOS to it. Otherwise it retreats straight home, relying on
## _step_retreat's own continuous per-tick bending for anything known but
## not actually an immediate threat.
##
## Run: godot --headless --path . --script scripts/tests/test_general_retreat_safety.gd
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


## real battle setup (_set_retreat_profile) always gives a unit a real
## retreat_target_x far from wherever it's actually deployed — _make_unit
## alone doesn't, leaving the field at its own default (0.0), which every
## test position below would otherwise satisfy by sheer coincidence and
## falsely trigger the "already safe" fix regardless of what's actually
## being tested. Every squad in this file goes through this instead of a
## bare _make_unit call.
func _make_retreating_squad(bm, pos: Vector2) -> Unit:
	var squad: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, pos)
	squad.retreat_target_x = -5000.0
	bm.player_units.append(squad)
	return squad


## The exact reported shape: no known enemy anywhere near this unit. It
## must retreat straight home — no cover-seeking detour at all.
func test_no_known_threat_skips_cover_detour_entirely() -> void:
	var bm = make_battle()
	var squad: Unit = _make_retreating_squad(bm, Vector2(0, 0))
	squad.order_retreat([], [])
	check(not squad.has_move_target,
		"A squad with no known enemy anywhere near it must skip the cover-seeking detour and retreat straight home, not walk toward some cover point first")


## The core of the SECOND correction: a known enemy position that is
## neither close (within SQUAD_ENGAGEMENT_RANGE) nor currently watching
## this unit must NOT force a cover detour — a merely-known position,
## even one inside the older (too generous) SQUAD_DANGER_RANGE, is not by
## itself a reason to break from the straight retreat.
func test_known_but_not_close_and_not_visible_does_not_force_cover() -> void:
	var bm = make_battle()
	var squad: Unit = _make_retreating_squad(bm, Vector2(0, 0))
	squad.is_visible = false
	# Well inside the old SQUAD_DANGER_RANGE (240px) but well outside the
	# real SQUAD_ENGAGEMENT_RANGE (80px) this fix now uses instead.
	var known: Array[Vector2] = [Vector2(200, 0)]
	squad.order_retreat(known, [])
	check(not squad.has_move_target,
		"A known enemy that is neither close enough to actually engage nor currently watching this unit must not force a cover detour")


## Currently VISIBLE — actively being watched/engaged right now — is, on
## its own, always a real reason to seek cover, regardless of distance to
## any specific known position.
func test_currently_visible_seeks_cover() -> void:
	var bm = make_battle()
	var squad: Unit = _make_retreating_squad(bm, Vector2(0, 0))
	squad.is_visible = true
	squad.order_retreat([], [])
	check(squad.has_move_target,
		"A unit currently visible to the enemy must seek real cover, even with no specific known enemy position on record")


## A known enemy within actual direct-fire/overrun range AND with real
## line of sight is a real, immediate threat even without a formal
## "spotted" roll landing yet — must still seek cover.
func test_close_enemy_with_los_seeks_cover_even_if_not_yet_spotted() -> void:
	var bm = make_battle()
	var squad: Unit = _make_retreating_squad(bm, Vector2(0, 0))
	squad.is_visible = false
	var known: Array[Vector2] = [Vector2(GameConfig.SQUAD_ENGAGEMENT_RANGE * 0.5, 0)] # close, open ground -- real LOS
	squad.order_retreat(known, [])
	check(squad.has_move_target,
		"A known enemy within real engagement range and direct LOS must still trigger cover-seeking, even without this unit having been formally spotted yet")


## A second, independent live-observed failure found in the same
## incident: a rear-echelon unit (a DRONE_TEAM home base, confirmed
## directly from the live battle) can already be sitting AT OR PAST its
## own retreat_target_x — the exact line _step_retreat's own "reached"
## check uses to mark WITHDRAWN — the moment a general retreat is
## ordered, simply because that's where it was already operating. Every
## retreat used to route through a cover leg first regardless, so an
## already-safe unit could get sent BACKWARD, toward the enemy, to reach
## some cover point distant units were also converging on — confirmed
## directly: exactly that happened in the live battle. Made currently
## visible here specifically to prove "already safe" wins outright over
## the separate cover-need check above, not just that an empty threat
## list trivially skips everything.
func test_already_past_retreat_line_never_detours_regardless_of_threat() -> void:
	var bm = make_battle()
	var squad: Unit = _make_retreating_squad(bm, Vector2(-5000, 0))
	squad.is_visible = true # would otherwise trigger cover-seeking outright
	squad.order_retreat([], [])
	check(not squad.has_move_target,
		"A unit already at or past its own retreat_target_x must never detour to cover, even while currently visible — it's already home")


## The exact mixed scenario from the live report: several squads with
## nothing near them, one actually being watched. The safe ones must NOT
## all converge on the same shared cover point (the visible symptom
## reported: "they all head to the tree in the lower left") because they
## never seek cover at all; only the genuinely threatened one does.
func test_mixed_squads_only_the_threatened_one_detours() -> void:
	var bm = make_battle()
	var safe_positions: Array[Vector2] = [Vector2(0, 0), Vector2(300, 200), Vector2(300, -200), Vector2(600, 100)]
	var safe_squads: Array[Unit] = []
	for p in safe_positions:
		safe_squads.append(_make_retreating_squad(bm, p))
	var threatened_squad: Unit = _make_retreating_squad(bm, Vector2(-800, 0))
	threatened_squad.is_visible = true

	for s in safe_squads:
		s.order_retreat([], [])
	threatened_squad.order_retreat([], [])

	for i in safe_squads.size():
		check(not safe_squads[i].has_move_target,
			"Safe squad %d (not visible, nothing close) must retreat straight home, not detour to cover" % i)
	check(threatened_squad.has_move_target,
		"The one squad actually being watched must still seek cover")


## Real multi-tick verification, per this project's own established
## lesson (a single-call check can prove the flag is right without ever
## proving the unit actually GOES anywhere): a safe squad must make real,
## continuous westward progress tick after tick via the ordinary
## _step_retreat dash, not sit still because no move_target was ever set.
func test_safe_retreat_actually_makes_progress_toward_home() -> void:
	var bm = make_battle()
	var squad: Unit = _make_retreating_squad(bm, Vector2(0, 0))
	squad.retreat_speed = GameConfig.PLAYER_RETREAT_SPEED # normally set during real battle setup, not by _make_unit alone
	squad.order_retreat([], [])
	check(not squad.has_move_target, "Setup check: this squad must be in the no-cover-needed path for the rest of this test to mean anything")

	var start_x: float = squad.global_position.x
	for i in 60: # one real second at 60fps, real per-frame pacing via the full _process (applies the same time-scale multiplier the actual game uses)
		bm._process(1.0 / 60.0)
	check(squad.global_position.x < start_x - 1.0,
		"A safe squad with no move_target must still make real westward progress via the ordinary retreat dash — it must not just sit still")


## The other real live incident this session: a mortar ordered by
## retreat_cover_point_toward to a cover zone required a huge,
## disproportionate detour (mostly perpendicular to the edge direction)
## and was destroyed before completing it — a real, avoidable cost.
## Directly reproduces the OLD bug's exact shape with a synthetic
## candidate list (the real map's own sparse zone layout doesn't reliably
## reproduce it via a plain end-to-end call — verified by direct
## exploration) — see GameConfig._best_cover_zone_by_total_trip's own doc
## comment for why the scoring was split out specifically to make this
## testable: 4 zones clustered near `from` (what the OLD "nearest 4 to
## self" shortlist would have been stuck with) and one zone much farther
## from `from` but genuinely on the way to the edge, which the OLD
## algorithm's shortlist would never even have considered.
func test_best_cover_zone_prefers_real_total_trip_over_nearest_to_self() -> void:
	var from := Vector2(0, 0)
	var reference_point := Vector2(-2000, 0) # the map edge, straight west
	var candidates: Array[Dictionary] = [
		{"zone": {"center": Vector2(50, 400)}, "dist_from_self": from.distance_to(Vector2(50, 400))},
		{"zone": {"center": Vector2(-50, 420)}, "dist_from_self": from.distance_to(Vector2(-50, 420))},
		{"zone": {"center": Vector2(30, -410)}, "dist_from_self": from.distance_to(Vector2(30, -410))},
		{"zone": {"center": Vector2(-40, -430)}, "dist_from_self": from.distance_to(Vector2(-40, -430))},
		{"zone": {"center": Vector2(-1200, 30)}, "dist_from_self": from.distance_to(Vector2(-1200, 30))}, # far from `from`, but genuinely on the way to reference_point
	]
	var best: Dictionary = GameConfig._best_cover_zone_by_total_trip(candidates, reference_point)
	check(best.zone.center == Vector2(-1200, 30),
		"The zone genuinely on the way to the edge must win on real total trip distance, even though it's the FARTHEST of the five from the unit's own current position — got %s instead" % [best.zone.center])

	# Sanity check on the metric itself, not just the winner: the OLD
	# algorithm (nearest 4 to self, i.e. every candidate here EXCEPT the
	# far one, then best-of-those toward the edge) would have picked
	# whichever of the four ~400-420-unit clustered zones is closest to
	# reference_point — a real, measurable worse total trip than the one
	# actually chosen.
	var old_style_pool: Array[Dictionary] = candidates.slice(0, 4)
	old_style_pool.sort_custom(func(a, b): return a.zone.center.distance_to(reference_point) < b.zone.center.distance_to(reference_point))
	var old_pick: Vector2 = old_style_pool[0].zone.center
	var old_trip: float = from.distance_to(old_pick) + old_pick.distance_to(reference_point)
	var new_trip: float = best.total_trip
	check(new_trip < old_trip,
		"The new total-trip pick (%.0f) must cost less than the old nearest-4-then-edge pick (%.0f) — otherwise this test isn't actually exercising the fix" % [new_trip, old_trip])


func run() -> void:
	test_no_known_threat_skips_cover_detour_entirely()
	test_known_but_not_close_and_not_visible_does_not_force_cover()
	test_currently_visible_seeks_cover()
	test_close_enemy_with_los_seeks_cover_even_if_not_yet_spotted()
	test_already_past_retreat_line_never_detours_regardless_of_threat()
	test_mixed_squads_only_the_threatened_one_detours()
	test_safe_retreat_actually_makes_progress_toward_home()
	test_best_cover_zone_prefers_real_total_trip_over_nearest_to_self()
	print("General-retreat safety tests: %d failures" % failures)
	quit(1 if failures else 0)
