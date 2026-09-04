extends Node
class_name CombatResolver
## Hit resolution + spotting/detection. Terrain effects come from
## GameConfig's terrain zones (elevation, concealment, cover) rather than a
## physics raycast, so this logic is easy to read and verify without running
## the engine.

# Cover: reduces hit chance once a target IS spotted and fired upon.
const COVER_MULTIPLIER := {
	GameConfig.TerrainType.OPEN: 1.0,
	GameConfig.TerrainType.HIGH_GROUND: 1.0,
	GameConfig.TerrainType.TREES: 0.6,
	GameConfig.TerrainType.BUILDING: 0.4,
}

# Concealment: reduces the chance of being spotted in the first place.
const CONCEALMENT_MULTIPLIER := {
	GameConfig.TerrainType.OPEN: 1.0,
	GameConfig.TerrainType.HIGH_GROUND: 1.0,
	GameConfig.TerrainType.TREES: 0.5,
	GameConfig.TerrainType.BUILDING: 0.7,
}


## One spotting roll for `spotter` trying to notice `target` this tick.
## Returns true if `target` becomes (or remains) spotted. Call this only for
## targets not already spotted — an already-spotted unit stays spotted until
## it is removed from play (no "losing" a spot in v1, to keep this legible).
static func roll_spot(spotter: Unit, target: Unit, delta: float) -> bool:
	var distance: float = spotter.global_position.distance_to(target.global_position)
	var detection_range: float = GameConfig.DETECTION_BASE_RANGE
	if spotter.elevation() > target.elevation():
		detection_range += GameConfig.DETECTION_ELEVATION_BONUS
	if distance > detection_range:
		return false

	var chance: float = GameConfig.SPOT_CHANCE_PER_SECOND
	chance *= CONCEALMENT_MULTIPLIER[target.terrain_type()]
	if target.activity == Unit.Activity.MOVING:
		chance *= GameConfig.MOVING_SPOT_MULTIPLIER
	chance *= clamp(1.0 - (distance / detection_range), 0.0, 1.0)
	chance *= delta

	return randf() < chance


## Resolves one shot from `attacker` at `defender`. Both must already be
## spotted by the other side — that is enforced by Unit.is_targetable(),
## checked before this is called.
##
## A defender caught MOVING gets no benefit from terrain cover (you can't use
## a foxhole while you're up and running for the next one) and is hit harder
## overall — this is the mechanical bite behind "an attacking squad advancing
## in the open takes heavy casualties," and it applies just as much to a
## player unit retreating under fire.
static func resolve_fire(attacker: Unit, defender: Unit) -> bool:
	var moving := defender.activity == Unit.Activity.MOVING
	var cover_multiplier: float = 1.0 if moving else COVER_MULTIPLIER[defender.terrain_type()]
	var chance: float = attacker.base_hit_chance * cover_multiplier
	if moving:
		chance *= GameConfig.MOVING_HIT_MULTIPLIER
	var hit: bool = randf() < chance
	if hit:
		defender.take_hit()
	return hit
