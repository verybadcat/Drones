extends SceneTree
## Direct user requests: "'Enemy commander orders a general retreat' should not be visible to the
## player during the battle" and "In general, enemy actions should not be [logged] unless they are
## seen. This one would not be. One might see individual squads retreating however."
##
## Run: godot --headless --path . --script scripts/tests/test_combat_log_hides_the_unseen.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func entries(log: CombatLog) -> Array:
	var out := []
	for label in log._list.get_children():
		out.append(label.text)
	return out

func run() -> void:
	test_enemy_lines_need_the_unit_to_be_seen()
	test_the_enemy_commanders_retreat_leaves_no_banner()
	test_no_enemy_banner_is_left_in_the_code()
	print("Combat log visibility tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_enemy_lines_need_the_unit_to_be_seen() -> void:
	var log := CombatLog.new()
	root.add_child(log)
	var seen := Unit.new()
	seen.setup(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2.ZERO)
	seen.is_visible = true
	var hidden := Unit.new()
	hidden.setup(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2.ZERO)
	hidden.is_visible = false
	var mine := Unit.new()
	mine.setup(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2.ZERO)
	mine.is_visible = false # our own units are never "unseen"
	log.log_ordered_retreat(seen)
	check(entries(log).size() == 1, "A seen enemy squad's retreat is logged")
	log.log_ordered_retreat(hidden)
	log.log_threshold_retreat(hidden)
	log.log_destroyed(hidden)
	log.log_seeking_cover(hidden)
	log.log_squad_surrendered(hidden)
	check(entries(log).size() == 1, "...an unseen one's is not, however it is phrased (%s)" % str(entries(log)))
	log.log_ordered_retreat(mine)
	check(entries(log).size() == 2, "Our own units are always logged")
	# Lines that name two units need both seen.
	log.log_blast_collateral(seen, hidden)
	log.log_bunching_spillover(hidden, seen)
	check(entries(log).size() == 2, "A line naming an unseen enemy as either party is not logged")
	log.log_blast_collateral(mine, seen)
	check(entries(log).size() == 3, "...one naming only seen or own units is")
	# Being spotted, and contact being lost, are the seeing itself.
	log.log_spotted(hidden)
	log.log_lost_contact(hidden)
	check(entries(log).size() == 5, "Being spotted and losing contact are always logged")
	log.free()
	seen.free()
	hidden.free()
	mine.free()


## The commander's decision has no line; squads that are seen retreating do.
func test_the_enemy_commanders_retreat_leaves_no_banner() -> void:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	var log := CombatLog.new()
	root.add_child(log)
	bm.combat_log = log
	var seen: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(4000, 500))
	var hidden: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(4200, 900))
	seen.is_visible = true
	hidden.is_visible = false
	seen.pips = 1
	hidden.pips = 1 # a force that has lost nearly everything: the commander gives up
	bm.enemy_units.append(seen)
	bm.enemy_units.append(hidden)
	check(bm._enemy_situation_hopeless(), "Set-up: the enemy's situation is hopeless")
	seed(5)
	bm._check_enemy_commander_retreat()
	check(bm.enemy_general_retreat_ordered, "The commander did order the retreat (the order itself still happens)")
	for text in entries(log):
		check(not ("commander" in text.to_lower()), "No line about the enemy commander (%s)" % text)
	var lines := entries(log)
	# Both squads have the same display name ("Enemy Squad"), so what tells them apart is the count:
	# one seen squad, one line at most (a surrender or a pull-back), never two.
	check(lines.size() <= 1, "Only the squad that is seen is reported, not the one that is not (%s)" % str(lines))
	check(lines.size() == 1, "...and that one is (%s)" % str(lines))
	log.free()
	bm.free()


func test_no_enemy_banner_is_left_in_the_code() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/battle_manager.gd")
	for phrase in ["Enemy commander orders", "Enemy is alerted:", "the enemy mortar(s) pull back too"]:
		check(not (phrase in src), "The banner '%s' is gone" % phrase)
