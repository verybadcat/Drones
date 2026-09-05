extends Node
class_name CombatResolver
## Hit resolution + spotting/detection. Terrain effects come from
## GameConfig's terrain zones (elevation, concealment, cover) rather than a
## physics raycast, so this logic is easy to read and verify without running
## the engine.

# Cover against DIRECT fire (squads): a tremendous swing. In the open, a
# squad is exposed and takes an outright penalty (1.3x) on top of having no
# protection at all — brutal. In trees or a building, fire almost never
# lands. This is the whole point of holding the village.
const SQUAD_COVER_MULTIPLIER := {
	GameConfig.TerrainType.OPEN: 1.3,
	GameConfig.TerrainType.TREES: 0.2,
	GameConfig.TerrainType.BUILDING: 0.1,
}

# Cover against MORTAR fire: much weaker — a mortar's plunging fire is the
# thing that punishes cover that stops rifles. Not impossible, just easier.
# The open-exposure penalty still applies — a mortar hits an exposed target
# harder too, same as direct fire does.
const MORTAR_COVER_MULTIPLIER := {
	GameConfig.TerrainType.OPEN: 1.3,
	GameConfig.TerrainType.TREES: 0.85,
	GameConfig.TerrainType.BUILDING: 0.7,
}

# Concealment: reduces the chance of being spotted in the first place.
const CONCEALMENT_MULTIPLIER := {
	GameConfig.TerrainType.OPEN: 1.0,
	GameConfig.TerrainType.TREES: 0.5,
	GameConfig.TerrainType.BUILDING: 0.7,
}


## The detection range between a specific observer/target pair — shared by
## both roll_spot (becoming visible) and has_live_observer (staying visible)
## so the two can never disagree about how far someone can be seen. A hidden
## spotter overrides everything else: elevation and a spotter's own extended
## range don't help you find someone hunkered down and hidden.
static func effective_detection_range(observer: Unit, target: Unit) -> float:
	if target.kind == Unit.Kind.SPOTTER and GameConfig.is_in_cover(target.terrain_type()):
		return GameConfig.SPOTTER_HIDDEN_DETECTION_RANGE
	var detection_range: float = GameConfig.DETECTION_BASE_RANGE
	if observer.kind == Unit.Kind.SPOTTER:
		detection_range += GameConfig.SPOTTER_DETECTION_RANGE_BONUS
	if observer.elevation() > target.elevation() + GameConfig.ELEVATION_ADVANTAGE_THRESHOLD_M:
		detection_range += GameConfig.DETECTION_ELEVATION_BONUS
	return detection_range


## One spotting roll for `observer` trying to notice `target` this tick.
## Returns true if `target` becomes visible this tick. Call this only for
## targets not already visible — BattleManager separately handles a
## currently-visible target LOSING visibility (see has_live_observer) once
## nobody has eyes on it any more; visibility is a live, moment-to-moment
## fact, not a permanent flag (see Unit.is_visible).
##
## Line of sight does not go through buildings — a building between observer
## and target blocks the roll outright, same rule as direct fire (see
## GameConfig.has_direct_los). This applies to anyone doing the looking,
## squad or spotter alike; seeing and shooting are blocked the same way.
##
## The artillery spotter sees further than a rifle squad does (its whole
## job). Its OWN concealment is two very different stories: hidden in cover,
## the enemy effectively can't find it beyond point-blank range; standing in
## the open, it's found close to normally.
static func roll_spot(observer: Unit, target: Unit, delta: float) -> bool:
	if not GameConfig.has_direct_los(observer.global_position, target.global_position):
		return false

	var distance: float = observer.global_position.distance_to(target.global_position)
	var detection_range: float = effective_detection_range(observer, target)
	if distance > detection_range:
		return false

	var target_hidden_spotter := target.kind == Unit.Kind.SPOTTER and GameConfig.is_in_cover(target.terrain_type())
	var chance: float = GameConfig.SPOT_CHANCE_PER_SECOND
	chance *= CONCEALMENT_MULTIPLIER[target.terrain_type()]
	if target.kind == Unit.Kind.SPOTTER and not target_hidden_spotter:
		chance *= GameConfig.SPOTTER_EXPOSED_CONCEALMENT_MULTIPLIER
	if target.activity == Unit.Activity.MOVING:
		chance *= GameConfig.MOVING_SPOT_MULTIPLIER
	chance *= clamp(1.0 - (distance / detection_range), 0.0, 1.0)
	chance *= delta

	return randf() < chance


## True if ANY unit in `observers` currently has clear, in-range line of
## sight to `target` right now. This is what keeps a currently-visible
## target visible (or makes it visible instantly, e.g. when it fires) — the
## moment nobody qualifies any more, the target stops being visible. Uses
## the exact same range rule as roll_spot (effective_detection_range) but
## with no concealment-based chance roll — this asks "could someone be
## watching it right now," not "did anyone just now notice it."
static func has_live_observer(target: Unit, observers: Array[Unit]) -> bool:
	for observer in observers:
		if observer.state != Unit.State.ACTIVE:
			continue
		var distance: float = observer.global_position.distance_to(target.global_position)
		if distance > effective_detection_range(observer, target):
			continue
		if GameConfig.has_direct_los(observer.global_position, target.global_position):
			return true
	return false


## Resolves one shot from `attacker` at `defender`. Both must already be
## spotted by the other side — that is enforced by Unit.is_targetable(),
## checked before this is called.
##
## A defender caught MOVING gets no benefit from terrain cover at all (you
## can't use a foxhole while you're up and running for the next one) — that
## part is universal. What moving does to hit CHANCE differs by weapon:
## direct fire (squads) sees a moving target more easily and hits it harder,
## same as ever. Indirect fire (mortars) is the opposite — hitting something
## that's moving means predicting where it will be, which only works if the
## movement is predictable (Unit.movement_predictable — the enemy's steady
## road march). Reactive, erratic movement (diving for cover, retreating) is
## hard to lead-aim against and gets a real hit-chance PENALTY, not just "no
## bonus."
##
## `ally_positions` is passed straight through to `defender.take_hit()` —
## other same-team units' current positions, so a squad breaking for cover
## after this hit picks a DIFFERENT patch than one an ally is already using
## (see GameConfig.nearest_cover_point's avoid_positions).
static func resolve_fire(attacker: Unit, defender: Unit, ally_positions: Array[Vector2] = []) -> bool:
	var moving := defender.activity == Unit.Activity.MOVING
	var cover_table: Dictionary = MORTAR_COVER_MULTIPLIER if attacker.kind == Unit.Kind.MORTAR else SQUAD_COVER_MULTIPLIER
	var cover_multiplier: float = 1.0 if moving else cover_table[defender.terrain_type()]
	var chance: float = attacker.base_hit_chance * cover_multiplier
	if moving:
		if attacker.kind == Unit.Kind.MORTAR:
			chance *= GameConfig.MORTAR_PREDICTABLE_MOVING_MULTIPLIER if defender.movement_predictable else GameConfig.MORTAR_UNPREDICTABLE_MOVING_MULTIPLIER
		else:
			chance *= GameConfig.MOVING_HIT_MULTIPLIER
	var hit: bool = randf() < chance
	if hit:
		defender.take_hit(attacker.kind == Unit.Kind.MORTAR, ally_positions)
	return hit
