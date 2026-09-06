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
	# A drone's camera at DRONE_ALTITUDE_M is a wholly different sensor, not
	# the ground-based one with a bonus bolted on — it replaces the whole
	# calculation, including the elevation-advantage bonus below (a drone is
	# always far higher than literally any point on this map already).
	if observer.kind == Unit.Kind.DRONE:
		return GameConfig.DRONE_DETECTION_RANGE
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
##
## A DRONE observer uses has_aerial_los instead of has_direct_los (see
## GameConfig — no ground-elevation blocking, since it's flying well above
## every hill) and DRONE_CONCEALMENT_MULTIPLIER instead of the ground-level
## CONCEALMENT_MULTIPLIER table (less penalty for TREES specifically — a
## canopy is porous from above in a way it isn't from across open ground —
## more penalty for BUILDING, which fully hides what's under its roof
## either way). A ground observer looking for a DRONE target is an entirely
## different question — "is anyone glancing at the right patch of sky right
## now" — answered separately by _roll_ground_notices_drone below rather
## than by any of this ground-spotting machinery.
static func roll_spot(observer: Unit, target: Unit, delta: float) -> bool:
	var observer_is_drone := observer.kind == Unit.Kind.DRONE
	if target.kind == Unit.Kind.DRONE and not observer_is_drone:
		return _roll_ground_notices_drone(observer, target, delta)

	var has_los: bool = GameConfig.has_aerial_los(observer.global_position, target.global_position) if observer_is_drone \
		else GameConfig.has_direct_los(observer.global_position, target.global_position)
	if not has_los:
		return false

	var distance: float = observer.global_position.distance_to(target.global_position)
	var detection_range: float = effective_detection_range(observer, target)
	if distance > detection_range:
		return false

	var chance: float = GameConfig.SPOT_CHANCE_PER_SECOND
	var concealment_table: Dictionary = GameConfig.DRONE_CONCEALMENT_MULTIPLIER if observer_is_drone else CONCEALMENT_MULTIPLIER
	chance *= concealment_table[target.terrain_type()]
	var target_hidden_spotter := target.kind == Unit.Kind.SPOTTER and GameConfig.is_in_cover(target.terrain_type())
	if target.kind == Unit.Kind.SPOTTER and not target_hidden_spotter:
		chance *= GameConfig.SPOTTER_EXPOSED_CONCEALMENT_MULTIPLIER
	if target.activity == Unit.Activity.MOVING:
		chance *= GameConfig.MOVING_SPOT_MULTIPLIER
	chance *= clamp(1.0 - (distance / detection_range), 0.0, 1.0)
	chance *= delta

	return randf() < chance


## Whether a GROUND unit's own unaided eyes/ears happen to catch a drone
## loitering overhead this tick — see GameConfig.DRONE_GROUND_NOTICE_
## CHANCE_PER_MINUTE for the real-world sourcing behind both constants used
## here. Deliberately bypasses effective_detection_range/concealment/
## MOVING_SPOT_MULTIPLIER entirely: none of that models "an occasional
## glance at the sky," which is what this actually is. Real slant range
## (horizontal distance plus DRONE_ALTITUDE_M, both in real meters) is what
## a person on the ground actually judges distance by, not the flat 2D
## ground distance everything else here uses. Only a building overhead
## still blocks it outright (has_aerial_los) — hills don't; nothing on this
## map's terrain is tall enough to occlude a drone flying above every hill.
static func _roll_ground_notices_drone(observer: Unit, target: Unit, delta: float) -> bool:
	if not GameConfig.has_aerial_los(observer.global_position, target.global_position):
		return false
	var horizontal_distance_m: float = observer.global_position.distance_to(target.global_position) / GameConfig.PIXELS_PER_METER
	var slant_range_m: float = sqrt(horizontal_distance_m * horizontal_distance_m + GameConfig.DRONE_ALTITUDE_M * GameConfig.DRONE_ALTITUDE_M)
	if slant_range_m > GameConfig.DRONE_GROUND_NOTICE_MAX_RANGE_M:
		return false
	var chance_per_tick: float = 1.0 - pow(1.0 - GameConfig.DRONE_GROUND_NOTICE_CHANCE_PER_MINUTE, delta / 60.0)
	return randf() < chance_per_tick


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
		var has_los: bool = GameConfig.has_aerial_los(observer.global_position, target.global_position) if observer.kind == Unit.Kind.DRONE \
			else GameConfig.has_direct_los(observer.global_position, target.global_position)
		if has_los:
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
## `ally_positions` and `known_enemy_positions` are passed straight through
## to `defender.take_hit()` — other same-team units' current positions (so
## a squad breaking for cover after this hit picks a DIFFERENT patch than
## one an ally is already using — see GameConfig.nearest_cover_point's
## avoid_positions) and currently-visible enemy positions from the
## defender's own side's point of view (so that same retreat never heads
## toward, or lands right next to, a threat its own side already knows
## about — see nearest_cover_point's DANGER_RADIUS exclusion).
## A DRONE defender skips the terrain-based cover table entirely — it isn't
## standing on any ground to take cover in — in favor of a flat, severe
## DRONE_HIT_CHANCE_MULTIPLIER: altitude, not a foxhole, is what protects it,
## and that protection doesn't depend on whether it happens to be moving.
static func resolve_fire(attacker: Unit, defender: Unit, ally_positions: Array[Vector2] = [], known_enemy_positions: Array[Vector2] = []) -> bool:
	var chance: float
	if defender.kind == Unit.Kind.DRONE:
		chance = attacker.base_hit_chance * GameConfig.DRONE_HIT_CHANCE_MULTIPLIER
	else:
		var moving := defender.activity == Unit.Activity.MOVING
		var cover_table: Dictionary = MORTAR_COVER_MULTIPLIER if attacker.kind == Unit.Kind.MORTAR else SQUAD_COVER_MULTIPLIER
		var cover_multiplier: float = 1.0 if moving else cover_table[defender.terrain_type()]
		chance = attacker.base_hit_chance * cover_multiplier
		if moving:
			if attacker.kind == Unit.Kind.MORTAR:
				chance *= GameConfig.MORTAR_PREDICTABLE_MOVING_MULTIPLIER if defender.movement_predictable else GameConfig.MORTAR_UNPREDICTABLE_MOVING_MULTIPLIER
			else:
				chance *= GameConfig.MOVING_HIT_MULTIPLIER
	var hit: bool = randf() < chance
	if hit:
		defender.take_hit(attacker.kind == Unit.Kind.MORTAR, ally_positions, known_enemy_positions)
	return hit
