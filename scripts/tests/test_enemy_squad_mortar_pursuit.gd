extends SceneTree
## Guards a new behavior added at direct user request: "Mortar should be
## a primary target for the enemy forces. They should chase it when they
## get close. In the latest battle, they were dancing back and forth, but
## not really chasing."
##
## Root cause, traced directly: _next_advance_point's own bent-angle,
## cover/encirclement-scored candidates and its own ENEMY_SURROUND_
## STANDOFF_RADIUS stop distance are the right model for a squad closing
## on a STATIC objective (the village) under fire — not for running down
## a MOVING, actively evading one. Each fresh bound only gets recomputed
## once has_move_target clears, aimed at wherever the mortar happened to
## be at that moment — a mortar that keeps relocating between
## reassessments produces exactly the reported "dancing," with no
## guarantee of ever actually converging.
##
## Fix: BattleManager._chasing_mortar_in_hot_pursuit / _chase_mortar_
## directly — once a squad is within SQUAD_DANGER_RANGE of a known,
## ACTIVE friendly mortar, it re-aims directly at the mortar's CURRENT
## position every tick (bypassing the has_move_target gate entirely, the
## same "re-aims every tick" idiom already established for actual
## mortar-hunts-mortar pursuit), with no bent angle and no standoff
## distance, stopping only once within real engagement range.
##
## Run: godot --headless --path . --script scripts/tests/test_enemy_squad_mortar_pursuit.gd
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
	bm.unit_type_doctrines[Unit.Team.ENEMY] = Orders.sanitize({})
	return bm


## The exact reported shape: a squad already close to a known, active
## mortar must aim DIRECTLY at its current position, not a bent-angle
## advance-by-bounds candidate.
func test_close_squad_chases_mortar_directly() -> void:
	var bm = make_battle()
	var mortar_pos := Vector2(0, 0)
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, mortar_pos)
	bm.player_units.append(mortar)
	mortar.is_visible = true

	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, mortar_pos + Vector2(GameConfig.SQUAD_DANGER_RANGE * 0.5, 0))
	bm.enemy_units.append(squad)
	squad.sought_cover = true

	bm._update_enemy_squad_advance()
	check(squad.has_move_target, "A squad close to a known active mortar must be actively moving toward it")
	check(squad.move_target.distance_to(mortar_pos) < 1.0,
		"A squad in hot pursuit must aim directly at the mortar's own current position, not a bent-angle advance candidate (got %s)" % [squad.move_target])


## A squad far from the mortar (beyond SQUAD_DANGER_RANGE) must still use
## the ordinary measured advance-by-bounds — hot pursuit is specifically
## for a squad already close enough that running the target down
## outranks a cautious, cover-seeking approach.
func test_distant_squad_still_uses_bent_advance() -> void:
	var bm = make_battle()
	var mortar_pos := Vector2(0, 0)
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, mortar_pos)
	bm.player_units.append(mortar)
	mortar.is_visible = true

	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, mortar_pos + Vector2(GameConfig.SQUAD_DANGER_RANGE * 3.0, 0))
	bm.enemy_units.append(squad)
	squad.sought_cover = true

	bm._update_enemy_squad_advance()
	check(squad.has_move_target, "A distant squad with an objective must still advance")
	check(squad.move_target.distance_to(mortar_pos) > 1.0,
		"A squad far from the mortar must use the ordinary bent-angle advance candidate, not a direct hot-pursuit line to the mortar's exact position")


## A squad still executing its own wide flanking route must not switch to
## hot pursuit just because it happens to pass near the mortar en route —
## see _enemy_advance_objective's own doc comment: it hasn't actually
## arrived at the point where the mortar becomes its real objective yet.
func test_flanking_squad_does_not_hot_pursue() -> void:
	var bm = make_battle()
	var mortar_pos := Vector2(0, 0)
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, mortar_pos)
	bm.player_units.append(mortar)
	mortar.is_visible = true

	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, mortar_pos + Vector2(GameConfig.SQUAD_DANGER_RANGE * 0.5, 0))
	bm.enemy_units.append(squad)
	squad.sought_cover = true
	squad.flanking_route_active = true

	check(not bm._chasing_mortar_in_hot_pursuit(squad),
		"A squad still executing its own flanking route must not switch to hot pursuit of the mortar just because it's nearby")


## Real multi-tick verification, per this project's own established
## lesson: a single-call check can prove the AIM is correct without ever
## proving the squad actually GAINS on a moving target. Simulates the
## mortar relocating partway through the chase (exactly the reported
## scenario) and confirms the squad's own distance to it strictly
## decreases overall, rather than oscillating without real progress.
func test_hot_pursuit_actually_closes_the_gap_as_mortar_moves() -> void:
	var bm = make_battle()
	var mortar_pos := Vector2(0, 0)
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, mortar_pos)
	bm.player_units.append(mortar)
	mortar.is_visible = true

	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, mortar_pos + Vector2(GameConfig.SQUAD_DANGER_RANGE * 0.8, 0))
	bm.enemy_units.append(squad)
	squad.sought_cover = true
	squad.move_speed = GameConfig.ENEMY_ADVANCE_SPEED

	var start_dist: float = squad.global_position.distance_to(mortar.global_position)
	var ticks := 0
	# _tick_movement takes tactical scenario_delta, not raw real delta —
	# same real-per-frame-pacing trap this project's own mortar tests have
	# already hit (see test_mortar_evasion_balance.gd's own doc comment):
	# a coarse or unscaled delta here would need thousands of ticks to
	# cover any real distance at this project's own real m/s speeds.
	while ticks < 3000 and squad.global_position.distance_to(mortar.global_position) > GameConfig.SQUAD_ENGAGEMENT_RANGE:
		bm._update_enemy_squad_advance()
		bm._tick_movement((1.0 / 60.0) * bm._current_time_scale())
		# The mortar itself relocates partway through, exactly like a real
		# fleeing crew — the squad must keep re-aiming at its NEW position,
		# not the stale one it first saw.
		if ticks == 20:
			mortar.global_position += Vector2(-GameConfig.SQUAD_DANGER_RANGE * 0.3, 40)
		ticks += 1

	check(ticks < 3000, "The squad must actually close to engagement range on the mortar within a generous tick budget, not chase indefinitely")
	var end_dist: float = squad.global_position.distance_to(mortar.global_position)
	check(end_dist < start_dist,
		"The squad must end up genuinely closer to the mortar than it started (start=%.0f, end=%.0f) — real progress, not back-and-forth dancing" % [start_dist, end_dist])


func run() -> void:
	test_close_squad_chases_mortar_directly()
	test_distant_squad_still_uses_bent_advance()
	test_flanking_squad_does_not_hot_pursue()
	test_hot_pursuit_actually_closes_the_gap_as_mortar_moves()
	print("Enemy squad mortar-pursuit tests: %d failures" % failures)
	quit(1 if failures else 0)
