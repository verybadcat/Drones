extends SceneTree
## Direct user request: "change the game to track civilian dead and wounded, using your best estimate. It's a random thing. Most impacts
## don't cause any. When it happens, track whose shell did it. Include the info in the score. Civilian dead and wounded are just as
## negative as military dead and wounded. Also display whose fire caused it, but for score purposes, it should not matter. If there are no
## civilian dead or wounded, don't mention it at all."
##
## Run: godot --headless --path . --script scripts/tests/test_civilian_casualties.gd
const BattleScore = preload("res://scripts/battle_score.gd")
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(x: float, y: float) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

func tally_over(point: Vector2, n: int) -> Dictionary:
	var totals := {"any": 0, "people": 0, "killed": 0, "heavy": 0, "walking": 0}
	var buildings: int = GameConfig.buildings_within(point, GameConfig.CIVILIAN_BLAST_RADIUS_M)
	for i in n:
		var r: Dictionary = GameConfig.civilian_casualties_draw(buildings)
		var people: int = r.killed + r.heavily_wounded + r.walking_wounded
		if people > 0:
			totals.any += 1
		totals.people += people
		totals.killed += r.killed
		totals.heavy += r.heavily_wounded
		totals.walking += r.walking_wounded
	return totals

func run() -> void:
	GameConfig.set_active_map("voznesensk")
	GameConfig._build_terrain_grid()
	# 1. open ground: nobody hurt, ever
	var open_point := Vector2.INF
	for x in range(100, 4900, 100):
		var p: Vector2 = m(float(x), 100.0)
		if GameConfig.buildings_within(p, GameConfig.CIVILIAN_BLAST_RADIUS_M) == 0:
			open_point = p
			break
	check(not is_inf(open_point.x), "Setup: some ground with no building within the blast radius")
	seed(11)
	var open_totals: Dictionary = tally_over(open_point, 3000)
	check(open_totals.people == 0, "A shell with no building within the blast radius hurts no civilian (%d did)" % open_totals.people)

	# 2. close-packed ground (the most blocks within the blast radius): about 0.4 hurt per shell, most shells none
	var dense_point := Vector2.INF
	for rect in GameConfig._building_rects:
		var p: Vector2 = rect.get_center() + m(18.0, 0.0)
		if GameConfig.buildings_within(p, GameConfig.CIVILIAN_BLAST_RADIUS_M) >= GameConfig.CIVILIAN_FULL_DENSITY_BUILDINGS:
			dense_point = p
			break
	check(not is_inf(dense_point.x), "Setup: ground with a full set of building blocks around it")
	seed(12)
	var n := 6000
	var dense: Dictionary = tally_over(dense_point, n)
	var any_share: float = float(dense.any) / float(n)
	var per_shell: float = float(dense.people) / float(n)
	check(any_share > 0.15 and any_share < 0.25, "In the densest ground about one shell in five hurts someone (%.3f)" % any_share)
	check(per_shell > 0.3 and per_shell < 0.5, "...about 0.4 people per shell (%.3f)" % per_shell)
	var people: float = float(dense.people)
	check(absf(float(dense.killed) / people - GameConfig.CIVILIAN_KILLED_SHARE) < 0.03, "...a quarter of those hurt killed (%.3f)" % (float(dense.killed) / people))
	check(absf(float(dense.heavy) / people - GameConfig.CIVILIAN_HEAVILY_WOUNDED_SHARE) < 0.03, "...35%% heavily wounded (%.3f)" % (float(dense.heavy) / people))
	check(dense.walking > 0, "...the rest walking wounded")

	# a single block near is a quarter as dangerous
	var lone := Vector2.INF
	for rect in GameConfig._building_rects:
		var p: Vector2 = rect.get_center() + m(40.0, 0.0)
		if GameConfig.buildings_within(p, GameConfig.CIVILIAN_BLAST_RADIUS_M) == 1:
			lone = p
			break
	check(not is_inf(lone.x), "Setup: ground with a single block within the blast radius")
	if not is_inf(lone.x):
		seed(13)
		var few: Dictionary = tally_over(lone, n)
		check(float(few.people) < float(dense.people) * 0.35 and few.people > 0, "Ground with one block near is much safer than the densest (%d against %d people)" % [few.people, dense.people])

	# the real entry point agrees with the draw (open ground: nothing; a full block: something, over enough shells)
	seed(16)
	var via_point := 0
	for i in 150:
		var r: Dictionary = GameConfig.civilian_casualties_at(dense_point)
		via_point += r.killed + r.heavily_wounded + r.walking_wounded
	check(via_point > 0 and GameConfig.civilian_casualties_at(open_point).killed == 0, "civilian_casualties_at works from a point (%d people in 150 shells into a block)" % via_point)

	# 3. whose shell: the tally goes to the side that fired
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	seed(15)
	for i in 400:
		bm._assess_civilian_casualties(dense_point, Unit.Team.PLAYER)
	check(bm.civilian_casualties_by_shell.player.killed + bm.civilian_casualties_by_shell.player.heavily_wounded + bm.civilian_casualties_by_shell.player.walking_wounded > 0, "Our shells into a block hurt some civilians")
	check(bm.civilian_casualties_by_shell.enemy.killed + bm.civilian_casualties_by_shell.enemy.heavily_wounded + bm.civilian_casualties_by_shell.enemy.walking_wounded == 0, "...and none are put down to the Russians")
	for i in 400:
		bm._assess_civilian_casualties(dense_point, Unit.Team.ENEMY)
	var ru: Dictionary = bm.civilian_casualties_by_shell.enemy
	check(ru.killed + ru.heavily_wounded + ru.walking_wounded > 0, "Russian shells hurt some, put down to the Russians")

	# the battle result carries the totals, the split, and the score counts them
	var stats := {"killed": 0, "captured": 0, "heavily_wounded": 0, "walking_wounded": 0}
	var result: Dictionary = bm._build_battle_result("DEFEAT", false, stats, stats)
	var by: Dictionary = bm.civilian_casualties_by_shell
	check(result.inputs.civilian_killed == by.player.killed + by.enemy.killed and result.inputs.civilian_heavily_wounded == by.player.heavily_wounded + by.enemy.heavily_wounded and result.inputs.civilian_walking_wounded == by.player.walking_wounded + by.enemy.walking_wounded, "The result's civilian totals are the two sides' tallies added")
	check(result.inputs.civilian_by_shell.player.killed == by.player.killed and result.inputs.civilian_by_shell.enemy.killed == by.enemy.killed, "...and the split by whose shell is kept with it")
	var expected: float = -20.0 + (result.inputs.civilian_killed * -10.0 + result.inputs.civilian_heavily_wounded * -4.0 + result.inputs.civilian_walking_wounded * -1.0)
	check(is_equal_approx(result.score, expected), "The score counts civilians like our own dead and wounded (%.1f, expected %.1f)" % [result.score, expected])
	bm.combat_log.free()
	bm.free()

	# a landed shell is assessed in the real flow, ordinary fire and counter-battery both, for the side that fired it
	bm = BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var um: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, m(400, 1500)); bm.player_units.append(um)
	var em: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, m(4000, 1500)); bm.enemy_units.append(em)
	bm.scenario_elapsed_time = 1000.0
	seed(17)
	for i in 200:
		bm._pending_mortar_shots.append({"mortar": um, "target": null, "aim_point": dense_point, "impact_point": dense_point, "impact_time": 900.0})
	bm._resolve_pending_mortar_shots()
	var ours_hurt: int = bm.civilian_casualties_by_shell.player.killed + bm.civilian_casualties_by_shell.player.heavily_wounded + bm.civilian_casualties_by_shell.player.walking_wounded
	var theirs_hurt: int = bm.civilian_casualties_by_shell.enemy.killed + bm.civilian_casualties_by_shell.enemy.heavily_wounded + bm.civilian_casualties_by_shell.enemy.walking_wounded
	check(ours_hurt > 0 and theirs_hurt == 0, "Shells that land in the real flow hurt civilians, put down to the side that fired (%d ours, %d Russian)" % [ours_hurt, theirs_hurt])
	for i in 200:
		bm._pending_counter_battery.append({"attacker": em, "target": um, "impact_position": dense_point, "fire_time": 0.0, "impact_time": 900.0, "fired": true})
	bm._resolve_pending_counter_battery()
	theirs_hurt = bm.civilian_casualties_by_shell.enemy.killed + bm.civilian_casualties_by_shell.enemy.heavily_wounded + bm.civilian_casualties_by_shell.enemy.walking_wounded
	check(theirs_hurt > 0, "Counter-battery shells hurt civilians too, put down to the side that fired (%d Russian)" % theirs_hurt)
	bm.combat_log.free()
	bm.free()

	# 4. the score does not care whose shell it was
	var ours := {"position": "held", "civilian_killed": 2, "civilian_heavily_wounded": 1, "civilian_walking_wounded": 3,
		"civilian_by_shell": {"player": {"killed": 2, "heavily_wounded": 1, "walking_wounded": 3}, "enemy": {"killed": 0, "heavily_wounded": 0, "walking_wounded": 0}}}
	var theirs := {"position": "held", "civilian_killed": 2, "civilian_heavily_wounded": 1, "civilian_walking_wounded": 3,
		"civilian_by_shell": {"player": {"killed": 0, "heavily_wounded": 0, "walking_wounded": 0}, "enemy": {"killed": 2, "heavily_wounded": 1, "walking_wounded": 3}}}
	check(is_equal_approx(BattleScore.score(ours), BattleScore.score(theirs)), "Whose shell hurt the civilians makes no difference to the score")
	check(is_equal_approx(BattleScore.score(ours), 20.0 - 20.0 - 4.0 - 3.0), "Civilians killed -10 each, heavily wounded -4, walking wounded -1: the same as our own people (%.1f)" % BattleScore.score(ours))
	var military := {"position": "held", "player_killed": 2, "player_heavily_wounded": 1, "player_walking_wounded": 3}
	check(is_equal_approx(BattleScore.score(ours), BattleScore.score(military)), "...exactly what the same numbers of our own dead and wounded would cost")

	# 5. display: nothing at all when there were none; the split by shell when there were
	var none := {"position": "held", "player_killed": 1, "civilian_by_shell": {"player": {"killed": 0, "heavily_wounded": 0, "walking_wounded": 0}, "enemy": {"killed": 0, "heavily_wounded": 0, "walking_wounded": 0}}}
	var quiet: String = BattleScore.breakdown_text(none)
	check(not quiet.to_lower().contains("civilian"), "With no civilian dead or wounded the breakdown never mentions civilians")
	var old_record := {"position": "held", "player_killed": 1}
	check(not BattleScore.breakdown_text(old_record).to_lower().contains("civilian") and is_equal_approx(BattleScore.score(old_record), 10.0), "A record from before civilians were tracked scores as before and says nothing of them")
	var shown: String = BattleScore.breakdown_text(ours)
	check(shown.contains("Civilians killed: 2") and shown.contains("Civilians heavily wounded: 1") and shown.contains("Civilians walking wounded: 3"), "With civilians hurt the breakdown lists them")
	check(shown.contains("Civilians hurt by our shells: 2 killed, 4 wounded.") and not shown.contains("Russian shells"), "...and whose shells did it (ours only here)")
	var mixed := {"position": "held", "civilian_killed": 1, "civilian_walking_wounded": 1,
		"civilian_by_shell": {"player": {"killed": 1, "heavily_wounded": 0, "walking_wounded": 0}, "enemy": {"killed": 0, "heavily_wounded": 0, "walking_wounded": 1}}}
	var shown_mixed: String = BattleScore.breakdown_text(mixed)
	check(shown_mixed.contains("Civilians hurt by our shells: 1 killed.") and shown_mixed.contains("Civilians hurt by Russian shells: 1 wounded."), "...each side's own count when both fired")
	print("Civilian casualty tests: %d failures" % failures)
	quit(1 if failures else 0)
