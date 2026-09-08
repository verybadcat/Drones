extends Unit
class_name TestUnit
## Instrumented Unit used only by the doctrine-characterization test suite
## (scripts/tests/characterize_doctrine.gd) — never used by the actual
## game. Overrides a handful of decision points purely to COUNT what they
## decided, delegating to super() for the real behavior every time, so the
## game logic under test is byte-for-byte what actually ships. This is
## how the suite gets ground-truth counts for decisions that don't leave
## a lasting trace in final unit state (a held mortar crew that's never
## hit again ends the battle looking identical to one that was never
## tested at all; an ammo cook-off flag is deliberately one-shot and
## cleared the moment BattleManager narrates it).
##
## Counters live on the owning TestBattleManager (get_parent() — every
## unit is added there via _make_unit) and are updated directly, right
## here, the instant each decision happens. Deliberately untyped rather
## than `as TestBattleManager`: brand-new class_name scripts aren't in
## Godot's cached global class table until the actual editor scans the
## project, which a headless CLI run never triggers on its own — a static
## type reference to a sibling class_name script added in the same batch
## reliably fails to resolve in that situation. Untyped access (duck
## typing) sidesteps the cache entirely.

func _roll_mortar_ammo_cookoff() -> bool:
	var tbm = get_parent()
	var result: bool = super._roll_mortar_ammo_cookoff()
	if tbm:
		tbm.cookoff_rolls += 1
		if result:
			tbm.cookoff_occurred += 1
	return result


func _mortar_crew_holds_position(known_enemy_positions: Array[Vector2]) -> bool:
	var tbm = get_parent()
	var result: bool = super._mortar_crew_holds_position(known_enemy_positions)
	if tbm:
		var side: String = "player" if team == Team.PLAYER else "enemy"
		tbm.mortar_hold_decisions[side] = tbm.mortar_hold_decisions.get(side, 0) + 1
		if result:
			tbm.mortar_hold_outcomes[side] = tbm.mortar_hold_outcomes.get(side, 0) + 1
	return result


func _resolve_wounded_evacuation(known_enemy_positions: Array[Vector2]) -> float:
	just_abandoned_wounded = false
	just_carried_wounded = false
	var tbm = get_parent()
	var result: float = super._resolve_wounded_evacuation(known_enemy_positions)
	if tbm:
		var side: String = "player" if team == Team.PLAYER else "enemy"
		tbm.wounded_evac_decisions[side] = tbm.wounded_evac_decisions.get(side, 0) + 1
		if just_abandoned_wounded:
			tbm.wounded_abandoned[side] = tbm.wounded_abandoned.get(side, 0) + 1
		elif just_carried_wounded:
			tbm.wounded_carried[side] = tbm.wounded_carried.get(side, 0) + 1
	return result
