extends SceneTree
## Direct user request: "Let's make the casualty threshold for enemy retreats random. Instead of a fixed
## 40%, let's randomize it at 35-50%. Keep it secret from the player." Previously
## GameConfig.ENEMY_COMMANDER_RETREAT_THRESHOLD was one fixed 0.4 for every battle, used by
## BattleManager._enemy_situation_hopeless (the enemy commander's own whole-force "the attack has failed"
## judgment) — a value a player could eventually learn to read like a rulebook.
##
## Now rolled once per battle, in start_battle, AFTER the battle's own seed is applied (so the same seed
## still reproduces the same battle, per this project's established convention), into a new
## BattleManager._enemy_commander_retreat_threshold instance field, within GameConfig.
## ENEMY_COMMANDER_RETREAT_THRESHOLD_MIN/MAX (0.35/0.50). Never logged or otherwise surfaced anywhere the
## player can see it — see test_combat_log_hides_the_unseen.gd's own "no banner for the enemy commander's
## decision" coverage, unchanged by this fix.
##
## Run: godot --headless --path . --script scripts/tests/test_enemy_commander_retreat_threshold_randomized.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

## Mirrors exactly the two statements start_battle itself runs for this (seed the battle, THEN roll) —
## this project's own established test style constructs BattleManager state directly rather than driving
## the full start_battle pipeline (unit spawning, doctrine sanitizing, map setup), which no existing test
## in this codebase invokes at all. The roll's actual placement in start_battle (immediately after
## `seed(battle_seed)`) was checked directly in the diff.
func rolled_threshold(battle_seed: int) -> float:
	seed(battle_seed)
	return randf_range(GameConfig.ENEMY_COMMANDER_RETREAT_THRESHOLD_MIN, GameConfig.ENEMY_COMMANDER_RETREAT_THRESHOLD_MAX)

func run() -> void:
	test_the_threshold_is_rolled_within_the_stated_range()
	test_the_same_seed_reproduces_the_same_threshold()
	test_different_seeds_produce_different_thresholds()
	test_hopeless_check_uses_the_rolled_value_not_a_fixed_one()
	print("Enemy-commander-retreat-threshold-randomized tests: %d failures" % failures)
	quit(1 if failures else 0)


## Rolled across many seeds, every single one must land in [0.35, 0.50] — never outside the stated range,
## in either direction.
func test_the_threshold_is_rolled_within_the_stated_range() -> void:
	for s in range(50):
		var t: float = rolled_threshold(s)
		check(t >= GameConfig.ENEMY_COMMANDER_RETREAT_THRESHOLD_MIN, "Seed %d: threshold %.4f is not below the stated minimum" % [s, t])
		check(t <= GameConfig.ENEMY_COMMANDER_RETREAT_THRESHOLD_MAX, "Seed %d: threshold %.4f is not above the stated maximum" % [s, t])


## Direct project convention: the roll happens AFTER the battle's own seed is applied in start_battle, so
## replaying the same seed reproduces the exact same battle, this threshold included.
func test_the_same_seed_reproduces_the_same_threshold() -> void:
	var a := rolled_threshold(777)
	var b := rolled_threshold(777)
	check(a == b, "The same battle seed (777) rolls the identical threshold every time (%.6f vs %.6f)" % [a, b])


## The whole point of the request: it must not be the same fixed number every battle. Checked across many
## seeds rather than just two, since two unlucky seeds could coincidentally roll close together.
func test_different_seeds_produce_different_thresholds() -> void:
	var values: Dictionary = {}
	for s in range(20):
		values[rolled_threshold(s)] = true
	check(values.size() > 1, "At least two different seeds must roll different thresholds — got the exact same value every time")


## _enemy_situation_hopeless must actually read the rolled per-battle value, not a fixed constant left
## behind as dead code — set casualties to fall clearly on ONE side of a specific rolled threshold and
## confirm the hopeless check agrees.
func test_hopeless_check_uses_the_rolled_value_not_a_fixed_one() -> void:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm._enemy_commander_retreat_threshold = 0.45
	var whole: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2.ZERO)
	whole.max_pips = 10
	whole.pips = 6 # exactly 40% casualties: below a 0.45 threshold, above the old fixed 0.4
	bm.enemy_units.append(whole)
	check(not bm._enemy_situation_hopeless(), "40%% casualties is NOT hopeless against a rolled 0.45 threshold")
	bm._enemy_commander_retreat_threshold = 0.35
	check(bm._enemy_situation_hopeless(), "The same 40%% casualties IS hopeless against a rolled 0.35 threshold")
	bm.combat_log.free()
	bm.free()
