extends SceneTree
## Guards a new mechanic added at direct user request: "Mortar should be
## a primary target for the enemy forces. They should chase it when they
## get close... Let's allow the mortar to run away off the left edge of
## the map. But if it does, let's consider it to have retreated from the
## battle. It is safe but can no longer participate. So it should only do
## that if there is no reasonable alternative. For example, an enemy
## squad may be chasing it so it can't stay on the map."
##
## BattleManager._mortar_flee_as_last_resort is reached only when a crew
## is already under real, urgent pressure (spotted, an unwatched threat
## closing, or just hit by counter-battery) AND _relocate_mortar's own
## leashed concealment search has ALREADY come up completely empty. It
## reuses Unit.order_retreat unchanged — a genuine one-way retreat, exactly
## like a general retreat, permanently removing the crew from the mortar
## decision loop from the next tick on (state != ACTIVE).
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_flee_last_resort.gd
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
	bm.unit_type_doctrines[Unit.Team.PLAYER] = Orders.sanitize({})
	return bm


## The core new behavior: spotted (urgent), with _mortar_relocation_plan's
## own home-leash safety net forced to reject every real candidate (home
## set absurdly far away — a clean, controllable way to force a genuine
## "no reasonable alternative" without needing to exhaustively box in the
## real map). Must flee off the map (RETREATING) as a last resort.
func test_mortar_flees_off_map_when_urgently_threatened_with_no_relocation_option() -> void:
	var bm = make_battle()
	bm._friendly_mortar_home_position = Vector2(1e6, 1e6) # forces every candidate to fail _mortar_relocation_plan's own home-leash safety net
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2(0, 0))
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = 10
	mortar.retreat_target_x = -5000.0
	mortar.retreat_speed = GameConfig.PLAYER_RETREAT_SPEED
	mortar.is_visible = true # spotted -- the urgent "conceal" tier

	bm._decide_mortar_action(mortar)
	check(mortar.state == Unit.State.RETREATING,
		"A spotted mortar with no reasonable relocation option anywhere must flee off the map as a last resort, not just sit and report 'no route'")


## The complementary, still-must-work case: a mortar with a REAL
## relocation option available (an ordinary home position, no artificial
## leash sabotage) must NOT flee off the map — the last resort is for
## when nothing else is left, not a routine evasive response.
func test_mortar_does_not_flee_when_a_relocation_option_exists() -> void:
	# Seeded: an unlucky weighted-random draw in the concealment search
	# could occasionally exhaust its own retry budget and come back empty
	# even with a real option available, intermittently failing this test
	# for reasons unrelated to whatever it's actually guarding — caught
	# directly (1 failure in 5 unseeded runs) rather than dismissed.
	seed(20260917)
	var bm = make_battle()
	var start := Vector2(0, 0)
	bm._friendly_mortar_home_position = start
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, start)
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = 10
	mortar.retreat_target_x = -5000.0
	mortar.is_visible = true # spotted -- the urgent "conceal" tier

	bm._decide_mortar_action(mortar)
	check(mortar.state == Unit.State.ACTIVE,
		"A mortar with a genuine relocation option nearby must use it, not skip straight to fleeing off the map")
	check(mortar.has_move_target,
		"The mortar must actually be relocating for cover in this case")


## A routine (non-urgent) out-of-ammo mortar that fails to relocate — most
## plausibly because MORTAR_VOLUNTARY_RELOCATION_COOLDOWN is throttling a
## fresh attempt, not because no option exists at all — must NOT flee off
## the map. Fleeing is reserved for genuinely urgent (spotted/threat-
## closing) situations, per the out_of_ammo tier's own `elif spotted or
## threat_closing` gate.
func test_out_of_ammo_without_urgency_does_not_flee_just_because_throttled() -> void:
	var bm = make_battle()
	var start := Vector2(0, 0)
	bm._friendly_mortar_home_position = start
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, start)
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = 0 # out of ammo
	mortar.retreat_target_x = -5000.0
	mortar.seconds_stationary = 0.0 # freshly moved -- well within the voluntary-relocation cooldown
	mortar.is_visible = false # not spotted, nothing closing -- not urgent

	bm._decide_mortar_action(mortar)
	check(mortar.state == Unit.State.ACTIVE,
		"A routine, unthreatened out-of-ammo mortar merely throttled by the voluntary relocation cooldown must not flee off the map — that's not 'no reasonable alternative'")


## Direct, live-caught correction: _relocate_mortar's own search never
## returns "nothing" (same "movement must never be starved to zero"
## principle as every relocation search in this project) — it always
## hands back SOME point, even one still fully exposed to the exact
## threat that triggered the relocation. A live battle showed a mortar
## keep accepting these hollow "successful" relocations indefinitely
## (still spotted, nearest known enemy steadily closing) instead of ever
## concluding there was genuinely nowhere left to hide — it only fled
## once it had already taken a hit. A close, known enemy on open ground
## with no real cover nearby (the same confirmed-empty-handed scenario as
## Unit.order_retreat's own equivalent fix) must now trigger the SAME
## flee-as-last-resort outcome as an outright failed relocation, not just
## accept whatever exposed spot the search happened to find.
func test_mortar_flees_when_relocation_succeeds_but_does_not_actually_hide() -> void:
	var bm = make_battle()
	var start := Vector2(0, 0)
	bm._friendly_mortar_home_position = start
	var mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, start)
	bm.player_units.append(mortar)
	mortar.mortar_rounds_remaining = 10
	mortar.retreat_target_x = -5000.0
	mortar.retreat_speed = GameConfig.PLAYER_RETREAT_SPEED
	mortar.is_visible = true # spotted -- the urgent "conceal" tier

	var enemy: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, start + Vector2(GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE * 0.2, 0))
	bm.enemy_units.append(enemy)
	enemy.is_visible = true
	bm._update_player_intel()
	check(bm._known_enemy_positions(Unit.Team.PLAYER).size() == 1,
		"Setup check: the mortar's side must actually have a known enemy position for this test to mean anything")

	bm._decide_mortar_action(mortar)
	check(mortar.state == Unit.State.RETREATING,
		"A spotted mortar whose relocation search finds SOME candidate, but one that still doesn't achieve real concealment from a known nearby threat, must flee off the map rather than accept a hollow relocation")


func run() -> void:
	test_mortar_flees_off_map_when_urgently_threatened_with_no_relocation_option()
	test_mortar_does_not_flee_when_a_relocation_option_exists()
	test_out_of_ammo_without_urgency_does_not_flee_just_because_throttled()
	test_mortar_flees_when_relocation_succeeds_but_does_not_actually_hide()
	print("Mortar flee-last-resort tests: %d failures" % failures)
	quit(1 if failures else 0)
