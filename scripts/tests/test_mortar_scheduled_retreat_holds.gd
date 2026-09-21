extends SceneTree
## Guards a live report: "With a retreat now scheduled, it should definitely
## expend ammo ... Conserving for a potential mortar shot is one thing. But here
## we have 26 rounds and 4 minutes." _pick_target's "haven't ruled out another
## enemy mortar" hold (MORTAR_UNKNOWN_ENEMY_HOLD_FIRE_CHANCE x existence
## confidence) was the one ammo-conservation hold that ignored a scheduled
## retreat, so it kept holding fire at squads right up to the retreat. It now
## scales by _scheduled_retreat_ammo_discount like the others.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_scheduled_retreat_holds.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(meters: float) -> float:
	return meters * GameConfig.PIXELS_PER_METER

## A player mortar with 26 rounds, an unseen but ACTIVE enemy mortar (so the
## "another mortar may exist" hold is at its strongest), and one visible squad
## 2 km off — a real, in-range, non-threatening target.
func hold_fraction(schedule_in_s: float, trials: int) -> float:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(m(-1000), m(1500)))
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = 26
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(m(1000), m(1500)))
	bm.enemy_units.append(squad)
	squad.is_visible = true
	var hidden_mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(m(4700), m(1500)))
	bm.enemy_units.append(hidden_mortar)
	bm._update_player_intel()
	if not is_inf(schedule_in_s):
		bm.scheduled_retreat_time = bm.scenario_elapsed_time + schedule_in_s
	var holds := 0
	for i in trials:
		if bm._pick_target(mortar, bm.enemy_units) == null:
			holds += 1
	bm.combat_log.free()
	bm.free()
	return float(holds) / float(trials)


## The four conditions at once, over many ticks through the real fire path: no
## need to evade (unspotted, nothing near, no recent detection), a retreat 4
## minutes away, 26 rounds, and a valid visible target 2 km off. The unseen
## enemy mortar is out of range of the crew, so no scoot-after-shot is owed
## (that would be a legitimate reason not to fire).
func rounds_fired(schedule_in_s: float) -> int:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(m(-1000), m(1500)))
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = 26
	mortar.seconds_stationary = 10000.0
	mortar.fire_timer = 0.0
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(m(1000), m(1500)))
	bm.enemy_units.append(squad)
	squad.is_visible = true
	var hidden_mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(m(9000), m(1500)))
	bm.enemy_units.append(hidden_mortar)
	bm._update_player_intel()
	if not is_inf(schedule_in_s):
		bm.scheduled_retreat_time = bm.scenario_elapsed_time + schedule_in_s
	var dt := 6.0
	for tick in 40: # 240 tactical seconds
		bm.scenario_elapsed_time += dt
		bm._mortar_tick_shot.clear()
		bm._tick_fire(mortar, 1.0, dt, bm.enemy_units)
		bm._update_mortar_decisions()
		bm._tick_movement(dt)
	var fired: int = 26 - mortar.mortar_rounds_remaining
	bm.combat_log.free()
	bm.free()
	return fired


func test_end_to_end_four_conditions() -> void:
	seed(21)
	var scheduled_total := 0
	var control_total := 0
	for trial in 12:
		scheduled_total += rounds_fired(240.0)
		control_total += rounds_fired(INF)
	var scheduled_avg: float = float(scheduled_total) / 12.0
	var control_avg: float = float(control_total) / 12.0
	check(scheduled_avg >= 10.0, "With no need to evade, a retreat 4 minutes off, 26 rounds and a valid target, the crew must spend a real share of its ammo (avg %.1f of 26 in 4 min)" % scheduled_avg)
	check(scheduled_avg > control_avg * 2.0, "It must fire clearly more than with no retreat scheduled (%.1f vs %.1f)" % [scheduled_avg, control_avg])
	print("  end to end, 4 min window: %.1f rounds with a scheduled retreat vs %.1f without" % [scheduled_avg, control_avg])


func run() -> void:
	seed(5)
	var trials := 3000
	var no_schedule: float = hold_fraction(INF, trials)
	var four_minutes: float = hold_fraction(240.0, trials)
	var due_now: float = hold_fraction(0.0, trials)
	check(no_schedule > 0.7, "Setup check: with no schedule the unknown-mortar hold must be strong (held %.2f)" % no_schedule)
	check(four_minutes < no_schedule * 0.6, "26 rounds and 4 minutes to a scheduled retreat must cut the holding sharply (%.2f vs %.2f with no schedule)" % [four_minutes, no_schedule])
	check(due_now < 0.03, "With the retreat due, essentially nothing may be held back (held %.2f)" % due_now)
	test_end_to_end_four_conditions()
	print("Mortar scheduled-retreat hold tests: %d failures (held %.2f no schedule / %.2f at 4 min / %.2f due)" % [failures, no_schedule, four_minutes, due_now])
	quit(1 if failures else 0)
