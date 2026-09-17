extends SceneTree
## Guards a direct, live-reported bug: "Mortar just let an enemy squad get
## adjacent to it. It should not."
##
## Root cause, traced directly in BattleManager._decide_mortar_action:
## `has_shot` used to trigger an UNCONDITIONAL early return the moment any
## target was selected ("Target available — no new movement order"), with
## no check at all for whether the crew itself was in real danger. This
## directly inverted the function's own explicitly documented priority
## order ("preserve self > destroy enemy mortars > destroy dangerous
## squads > destroy other squads") — the moment an approaching enemy squad
## became a valid, in-range target, the crew locked into "just keep
## firing" for the rest of the engagement, and the same spotted/closing-
## threat checks that already exist one tier down (and already correctly
## trigger relocation when NO shot is available) never ran again.
##
## Fix: `spotted`/`threat_closing` are now computed BEFORE has_shot gets a
## say, and has_shot's own early return is gated on NOT being in that
## overrun-relevant danger — when both are true, the decision falls
## through to the exact same tier-1 relocation logic that already existed
## for the "no shot available" case.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_preserves_self_over_available_shot.gd
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


## The exact reported shape: an enemy squad has closed to within real
## overrun range and is spotted engaging the mortar (is_visible), and the
## mortar ALSO has a valid, in-range shot on that same squad this tick
## (any_overrun forces _pick_target's own hold-fire chance to exactly
## zero, so this is deterministic, no seed needed). The crew must still
## relocate for self-preservation, not just sit and trade fire.
func test_mortar_relocates_despite_a_valid_shot_when_a_threat_is_overrunning() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(0, 0))
	bm.player_units.append(mortar)
	mortar.is_visible = true # spotted

	var squad_pos: Vector2 = Vector2(GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE * 0.3, 0)
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, squad_pos)
	bm.enemy_units.append(squad)
	squad.is_visible = true

	var target: Unit = bm._mortar_shot_this_tick(mortar, bm.enemy_units)
	check(target == squad, "Setup check: the mortar must have a real, resolvable shot on the close squad for this test to mean anything")

	bm._decide_mortar_action(mortar)
	check(mortar.has_move_target,
		"A mortar with an available shot must still relocate when it is spotted and a real threat has closed to overrun range — preserve-self must outrank an available shot, not the other way around")
	var intent: String = bm._mortar_move_intent.get(mortar, "")
	check(intent in ["conceal", "evade"],
		"The relocation must be framed as a genuine self-preservation displacement (conceal/evade), got '%s'" % intent)


## Counterfactual, so this fix doesn't overcorrect into never holding a
## shot at all: a mortar that is NOT spotted and has nothing closing to
## overrun range must still just hold its available shot exactly as
## before — preserve-self only needs to win when there's actually
## something to preserve against.
func test_mortar_still_holds_a_safe_available_shot() -> void:
	var bm = make_battle()
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(0, 0))
	bm.player_units.append(mortar)
	mortar.is_visible = false # not spotted

	# Within mortar range (so it's a real, valid target) but well beyond
	# MORTAR_CREW_OVERRUN_DANGER_RANGE — a real, distant shot, not a threat
	# to the crew itself.
	var squad_pos: Vector2 = Vector2(GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE * 3.0, 0)
	var squad: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, squad_pos)
	bm.enemy_units.append(squad)
	squad.is_visible = true

	var target: Unit = bm._mortar_shot_this_tick(mortar, bm.enemy_units)
	check(target == squad, "Setup check: the mortar must have a real, resolvable shot on the distant squad for this test to mean anything")

	bm._decide_mortar_action(mortar)
	check(not mortar.has_move_target,
		"A mortar with a safe available shot (not spotted, nothing closing to overrun range) must simply hold it, unchanged from before this fix")


func run() -> void:
	test_mortar_relocates_despite_a_valid_shot_when_a_threat_is_overrunning()
	test_mortar_still_holds_a_safe_available_shot()
	print("Mortar preserve-self-over-shot tests: %d failures" % failures)
	quit(1 if failures else 0)
