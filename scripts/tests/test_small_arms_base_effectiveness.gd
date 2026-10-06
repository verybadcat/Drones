extends SceneTree
## Direct user ruling, right after the crossfire multiplier went in: "this change made small arms fire more
## deadly and I am making it slightly less so" — a squad's base hit chance is 80% of what it was
## (GameConfig.SMALL_ARMS_BASE_EFFECTIVENESS). "If you are taking fire from widely separated angles, you are
## still much worse off than before the recent changes. If you are taking small arms fire from one direction
## only, you are better off than before we did anything." Mortars are not small arms and keep their value.
##
## Run: godot --headless --path . --script scripts/tests/test_small_arms_base_effectiveness.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func near(a: float, b: float, eps: float = 0.0001) -> bool:
	return absf(a - b) <= eps

func m(x: float, y: float) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

func run() -> void:
	test_squad_base_chances_are_eighty_percent_of_the_old_ones()
	test_the_whole_picture_against_the_pre_crossfire_game()
	print("Small arms base effectiveness tests: %d failures" % failures)
	quit(1 if failures else 0)


func make_unit(kind: Unit.Kind, team: Unit.Team) -> Unit:
	var u := Unit.new()
	root.add_child(u)
	u.setup(team, kind, Vector2.ZERO)
	return u


func test_squad_base_chances_are_eighty_percent_of_the_old_ones() -> void:
	check(near(GameConfig.SMALL_ARMS_BASE_EFFECTIVENESS, 0.8), "The constant is the 80% the user asked for")
	var player_squad := make_unit(Unit.Kind.SQUAD, Unit.Team.PLAYER)
	var enemy_squad := make_unit(Unit.Kind.SQUAD, Unit.Team.ENEMY)
	check(near(player_squad.base_hit_chance, 0.32 * 0.8), "A defending (player) squad: 0.32 became %.4f" % player_squad.base_hit_chance)
	check(near(enemy_squad.base_hit_chance, 0.20 * 0.8), "An attacking (enemy) squad: 0.20 became %.4f" % enemy_squad.base_hit_chance)
	var mortar := make_unit(Unit.Kind.MORTAR, Unit.Team.PLAYER)
	check(near(mortar.base_hit_chance, 0.40), "Mortars are not small arms: still 0.40 (%.4f)" % mortar.base_hit_chance)
	for u in [player_squad, enemy_squad, mortar]:
		u.free()


## A squad shooting at a stationary squad in the open, in the three situations the user described.
func test_the_whole_picture_against_the_pre_crossfire_game() -> void:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var target: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, m(0.0, 0.0))
	bm.player_units.append(target)
	var shooter: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, m(0.0, -300.0))
	bm.enemy_units.append(shooter)
	var now: float = CombatResolver.hit_probability(shooter, target)
	shooter.base_hit_chance = 0.20 # the value before this change
	var before_any_change: float = CombatResolver.hit_probability(shooter, target)
	check(near(now / before_any_change, 0.8), "One shooter, one direction: exactly 80%% of the old chance (%.3f vs %.3f)" % [now, before_any_change])
	check(now < before_any_change, "...so a unit fired on from one direction only is better off than before we did anything")
	var two_sides: float = now * CombatResolver.crossfire_multiplier(180.0)
	check(two_sides > before_any_change * 1.9, "Two opposite sides: about twice the old chance (x%.2f)" % (two_sides / before_any_change))
	var four_sides: float = now * CombatResolver.crossfire_multiplier(90.0)
	check(four_sides > before_any_change * 2.5, "All four sides: about two and a half times the old chance (x%.2f)" % (four_sides / before_any_change))
	# Break-even with the old game: the multiplier that cancels 0.8 is 1.25, i.e. a 330 degree safe arc.
	check(near(now * CombatResolver.crossfire_multiplier(330.0), before_any_change), "A 330 degree safe arc is exactly where the two changes cancel")
	bm.combat_log.free()
	bm.free()
