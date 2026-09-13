extends SceneTree
## Guards against BOTH directions of a self-preservation-vs-productivity
## failure in BattleManager._decide_mortar_action's standing "known enemy
## mortar in range" precaution (the MORTAR_STANDING_THREAT_COUNT tier):
##
##   1. UNDER-evasion: an idle mortar (no shot, not spotted, no threat
##      closing) with a known enemy mortar in range must still take SOME
##      self-preservation action instead of just sitting there — the
##      originally-reported gap ("mortar fired away at enemy mortars
##      multiple times, with no visible scoot at all").
##   2. OVER-evasion: a mortar with a real, repeatable shot opportunity
##      must still actually manage to fire sometimes despite a
##      persistent known enemy mortar, rather than perpetually
##      relocating and never accumulating enough stationary time to
##      become fire-eligible at all — "the mortar is always scooting and
##      never shooting."
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_evasion_balance.gd
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


## Isolated, direct-call version of the under-evasion contract — doesn't
## need a full battle running, just the tier-ladder decision itself.
func test_idle_mortar_still_evades_a_known_threat() -> void:
	var bm = make_battle()
	var start: Vector2 = GameConfig.CURRENT_MAP.player.mortar_default_position
	bm._friendly_mortar_home_position = start
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, start)
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = 10
	mortar.seconds_stationary = 1e9 # already emplaced — free to fire or relocate right away
	mortar.is_visible = false

	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, start + Vector2(400, 0))
	bm.enemy_units.append(enemy)
	enemy.is_visible = false
	enemy.player_has_been_sighted = true
	enemy.player_known_position = enemy.global_position

	bm.unit_type_doctrines[Unit.Team.PLAYER] = Orders.sanitize({})
	bm._decide_mortar_action(mortar)
	check(mortar.has_move_target and bm._mortar_move_intent.get(mortar, "") == "evade",
		"An idle mortar with even one known enemy mortar in range must still relocate as a precaution, not hold in place")
	bm.combat_log.free()
	bm.free()


## Runs the real _process() pipeline (movement, the mortar tier ladder,
## _mortar_tick_shot clearing — everything the standing precaution and
## fire-eligibility actually depend on) with ONLY the player's mortar and
## one persistently "known" (not currently visible/targetable) enemy
## mortar in the field — deliberately no other units, so there is never
## an easy, always-available shot to interrupt-and-fire on (that would
## mask the bug this guards against: a real shot opportunity DOES
## correctly override an in-progress evade, per _tick_fire's own
## interrupt logic, which is a separate, already-covered behavior, not
## what's under test here). The direct, unambiguous signature of the bug
## is whether `seconds_stationary` EVER reaches MORTAR_SETUP_TEARDOWN_TIME
## — the exact floor _mortar_shot_this_tick itself requires before it will
## even ATTEMPT to pick a target — not whether a shot happens to land,
## which also depends on target availability (a confound).
func test_mortar_eventually_settles_long_enough_to_become_fire_eligible() -> void:
	var bm = make_battle()
	var start: Vector2 = GameConfig.CURRENT_MAP.player.mortar_default_position
	bm._friendly_mortar_home_position = start
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, start)
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = 10
	mortar.is_visible = false
	# Simulates having JUST arrived from a relocation — Unit's own default
	# (a huge value, "already emplaced since before the battle began") would
	# trivially satisfy fire-eligibility from tick zero and never exercise
	# the actual risk this test is about: can the mortar EVER re-accumulate
	# a full settle window once that clock has been reset to 0, or does a
	# persistent known threat perpetually reset it before it gets there?
	mortar.seconds_stationary = 0.0

	var enemy_mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, start + Vector2(400, 0))
	bm.enemy_units.append(enemy_mortar)
	enemy_mortar.is_visible = false
	enemy_mortar.player_has_been_sighted = true
	enemy_mortar.player_known_position = enemy_mortar.global_position

	# BattleManager._current_time_scale fast-forwards tactical time whenever
	# _any_contact() is false (nothing currently visible to either side) —
	# realistic for a quiet lull, but it also means a single _process() tick
	# would jump scenario time by hundreds of tactical seconds at once,
	# which would trivially "settle" seconds_stationary in one tick and
	# never actually exercise the tick-by-tick evasion cycling this test is
	# about. A visible-but-unreachable enemy squad (well beyond
	# MORTAR_MAX_RANGE, so it can never actually BE the mortar's target —
	# that would reintroduce the interrupt-to-fire confound) keeps the
	# simulation at real, granular tactical pacing, matching what a player
	# actually experiences during an active engagement — which is exactly
	# the reported circumstance ("mortar fired away at enemy mortars
	# multiple times"), not a quiet lull.
	var distant_squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, start + Vector2(GameConfig.MORTAR_MAX_RANGE * 3.0, 0))
	bm.enemy_units.append(distant_squad)
	distant_squad.is_visible = true

	# risk left at its "inherit" default — every tier-1 discretionary
	# check (including the one under test) only ever runs for that value,
	# and it's also the realistic default: a real player's mortar has no
	# risk-override UI at all (see DoctrinePanel._build_mortar_section —
	# just the shoot-and-scoot checkbox).
	bm.unit_type_doctrines[Unit.Team.PLAYER] = Orders.sanitize({})

	# A per-frame-sized delta, not a large lump — BattleManager._process
	# scales delta by TIME_SCALE_NORMAL (60, "1 real second = 1 tactical
	# minute" under live contact — see that constant's own doc comment),
	# so a big per-call delta here would jump scenario time by MORE than
	# MORTAR_SETUP_TEARDOWN_TIME in a single call, trivially "settling" the
	# clock in one step and never actually exercising the tick-by-tick
	# reset-and-recheck dynamic this test exists to catch. 1/60 real
	# seconds (an ordinary 60fps frame) yields exactly 1 tactical second
	# of scenario time per call under live contact — fine-grained enough
	# to actually resolve it.
	var reached_eligibility := false
	var ticks := 0
	while ticks < 3000 and not bm.battle_over and not reached_eligibility:
		# Keep the "known" fix persistently fresh, matching a real,
		# ongoing (not stale) sighting — the harder version of this test,
		# since a genuinely fading/expiring detection would make this
		# easier to pass without proving anything.
		enemy_mortar.player_known_position = enemy_mortar.global_position
		bm._process(1.0 / 60.0)
		if is_instance_valid(mortar) and mortar.seconds_stationary >= GameConfig.MORTAR_SETUP_TEARDOWN_TIME:
			reached_eligibility = true
		ticks += 1

	check(reached_eligibility, "A mortar must eventually settle long enough to become fire-eligible (seconds_stationary >= MORTAR_SETUP_TEARDOWN_TIME) even with a persistent known enemy mortar in range the whole time — got stuck perpetually relocating instead (%d ticks)" % ticks)
	bm.combat_log.free()
	bm.free()


func run() -> void:
	test_idle_mortar_still_evades_a_known_threat()
	test_mortar_eventually_settles_long_enough_to_become_fire_eligible()
	print("Mortar evasion-balance tests: %d failures" % failures)
	quit(1 if failures else 0)
