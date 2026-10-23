extends Node
class_name CombatResolver
## Hit resolution + spotting/detection. Terrain effects come from
## GameConfig's terrain zones (elevation, concealment, cover) rather than a
## physics raycast, so this logic is easy to read and verify without running
## the engine.

# Cover against DIRECT fire (squads): a tremendous swing. In the open, a
# squad is exposed and takes an outright penalty (1.6x, matching
# MOVING_HIT_MULTIPLIER — standing exposed in the open is now exactly as
# dangerous as being caught moving, not notably safer) on top of having no
# protection at all — brutal, especially combined with the close-range
# lethality bonus below. In trees or a building, fire almost never lands.
# This is the whole point of holding the village.
const SQUAD_COVER_MULTIPLIER := {
	GameConfig.TerrainType.OPEN: 1.6,
	GameConfig.TerrainType.TREES: 0.2,
	GameConfig.TerrainType.BUILDING: 0.1,
}

# Cover against MORTAR fire: weaker than direct fire's own cover table
# (SQUAD_COVER_MULTIPLIER above) — a mortar's plunging fire is the thing
# that punishes cover built to stop a flat rifle trajectory, so it's still
# meaningfully easier to survive incoming mortar fire in the open vs. under
# cover than direct fire's near-total block. But NOT nearly as weak as this
# table used to claim: US Army FM 7-90 planning figures put a STANDING,
# exposed platoon under sustained 60mm mortar fire at roughly 20% casualties,
# a PRONE one under 10%, and one dug in with overhead cover under 10% and
# "mostly by direct hits" — a real, several-fold protective effect from
# cover and posture, not the ~1.9x spread (1.3 vs 0.7) this table used to
# have between fully exposed and inside a building. Retuned to a roughly
# 4x OPEN-to-BUILDING spread (matching "mostly direct hits only" under
# overhead cover) and TREES roughly halfway there — undergrowth breaks up
# fragment paths and forces some rounds to detonate in the canopy rather
# than at ground level, real but well short of a hard roof overhead. The
# open-exposure penalty still applies on top — a mortar hits an exposed
# target harder too, same as direct fire does.
const MORTAR_COVER_MULTIPLIER := {
	GameConfig.TerrainType.OPEN: 1.3,
	GameConfig.TerrainType.TREES: 0.5,
	GameConfig.TerrainType.BUILDING: 0.3,
}

## The real chance a mortar blast causes a casualty at `distance` from the
## impact point — used for both collateral bystanders and a counter-
## battery strike's own target, replacing what used to be a flat LINEAR
## falloff to a hard, certain zero at some fixed radius. See GameConfig.
## MORTAR_BLAST_CASUALTY_RADIUS's own doc comment for why that was wrong:
## a real "casualty radius" is conventionally the distance at which HALF
## of exposed personnel become casualties, not a wall beyond which harm
## stops being possible. Modeled as exponential decay calibrated so
## chance(MORTAR_BLAST_CASUALTY_RADIUS) is exactly half of `max_chance`
## (the chance right at the impact point itself), continuing smoothly
## outward rather than hitting a hard zero. `terrain` applies this same
## file's own MORTAR_COVER_MULTIPLIER table (already real-world-grounded
## — see its own doc comment citing FM 7-90's exposed/prone/dug-in
## casualty figures) normalized against OPEN, so a victim standing in the
## open gets exactly the bare exponential curve and cover reduces it
## proportionally — a direct answer to "cover would also matter."
static func blast_casualty_chance(distance: float, max_chance: float, terrain: GameConfig.TerrainType, kept: float = 1.0, dug_ratio: float = 1.0) -> float:
	var radius: float = GameConfig.MORTAR_BLAST_CASUALTY_RADIUS
	# Inside twice the casualty radius the cited exponential (halving every `radius`); beyond it the fragments are slowed and thinned
	# and the chance falls faster (halving every half a radius). Cover, which near the burst only reduces the chance, stops the weak
	# far-field fragments almost altogether, so it counts for more with distance (its factor to the power of distance over the radius).
	var decay: float
	if distance <= 2.0 * radius:
		decay = exp(-log(2.0) * distance / radius)
	else:
		decay = 0.25 * exp(-log(2.0) * (distance - 2.0 * radius) / (0.5 * radius))
	return clamp(max_chance * decay * cover_factor(distance, radius, terrain, kept, dug_ratio), 0.0, 1.0)


## How much of the fragments a unit's cover lets through, 1 for none (distances in pixels): the terrain's own ratio against the open (a unit on
## the move keeps only part of it, Unit.cover_kept), or a finished fighting position's ratio if that is better (and none of it for a round that
## lands in the hole), to the power of distance over `falloff` when that is more than 1: cover, which near the burst only reduces the chance,
## stops the weak far-field fragments almost altogether.
static func cover_factor(distance: float, falloff: float, terrain: GameConfig.TerrainType, kept: float = 1.0, dug_ratio: float = 1.0) -> float:
	var factor: float = MORTAR_COVER_MULTIPLIER.get(terrain, 1.0) / MORTAR_COVER_MULTIPLIER[GameConfig.TerrainType.OPEN]
	factor = pow(factor, kept) # a unit on the move keeps only part of it (Unit.cover_kept)
	if dug_ratio < 1.0:
		# a finished fighting position (Unit.fighting_position_ratio): its ratio, and none of it for a round that lands in the hole
		var near: float = clampf(distance / (GameConfig.FIGHTING_POSITION_DIRECT_HIT_M * GameConfig.PIXELS_PER_METER), 0.0, 1.0)
		factor = minf(factor, lerpf(1.0, dug_ratio, near))
	return pow(factor, maxf(1.0, distance / falloff))


## Fragment wounds, as the user's three classes (GameConfig.FRAGMENT_R1_M): the levels are the severities below (0 none, 1 walking wounded, 2 seriously
## wounded, 3 dead); each class is the potential of its level, with its own radius, the one at which a person is hit by it half the time: lethal R1, serious
## R2, light R3.
static func fragment_class_radius_m(level: int) -> float:
	var r1: float = GameConfig.FRAGMENT_R1_M
	if level >= BLAST_DEAD:
		return r1
	if level == BLAST_SERIOUS:
		return r1 * GameConfig.FRAGMENT_R2_FACTOR
	return r1 * GameConfig.FRAGMENT_R3_FACTOR


## The chance that an exposed person `distance_m` from the burst is hit by a fragment of class `level`: 50 percent at the class's radius, falling as 1/r^2
## beyond it and rising to certain at the burst (a Poisson hit chance with the density a 1/r^2 spread gives); none past GameConfig.FRAGMENT_REACH_M.
static func fragment_hit_chance(distance_m: float, level: int) -> float:
	if distance_m > GameConfig.FRAGMENT_REACH_M:
		return 0.0
	if distance_m < 0.001:
		return 1.0
	var ratio: float = fragment_class_radius_m(level) / distance_m
	return 1.0 - pow(1.0 - GameConfig.FRAGMENT_HIT_AT_RADIUS, ratio * ratio)


## The chance that anything at all reaches ONE PERSON of `unit` from a round `distance_m` from him, before what is between them: 1 for a man standing;
## a finished fighting position (none of it for a round in the hole, more of it with distance) and lying down (Unit.posture_factor: a third in the open,
## a half in cover) reduce it, as they reduced the old curve. It is rolled once for all the classes of fragment. What stands between the burst and him is
## GameConfig.fragment_transmission.
static func fragment_exposure(unit: Unit, distance_m: float) -> float:
	var position_cover: float = cover_factor(distance_m * GameConfig.PIXELS_PER_METER, GameConfig.MORTAR_BLAST_CASUALTY_RADIUS, GameConfig.TerrainType.OPEN, 1.0, unit.fighting_position_ratio())
	return position_cover * unit.posture_factor()


## The same for a person at `person` (pixels) when the burst is at `burst`: the exposure above, and the trees and walls between them.
static func fragment_person_exposure(unit: Unit, burst: Vector2, person: Vector2, step_m: float = 1.0) -> float:
	var distance_m: float = burst.distance_to(person) / GameConfig.PIXELS_PER_METER
	var exposure: float = fragment_exposure(unit, distance_m)
	if exposure <= 0.0 or distance_m > GameConfig.FRAGMENT_REACH_M:
		return 0.0
	return exposure * GameConfig.fragment_transmission(burst, person, step_m)


## One fragment of class `level` that has hit a person, actually done to him: as it is with FRAGMENT_AS_POTENTIAL, one level lower with FRAGMENT_ONE_LOWER, else two lower
## (never below none). `roll` is a uniform draw in [0, 1).
static func fragment_reduced(level: int, roll: float) -> int:
	if roll < GameConfig.FRAGMENT_AS_POTENTIAL:
		return level
	if roll < GameConfig.FRAGMENT_AS_POTENTIAL + GameConfig.FRAGMENT_ONE_LOWER:
		return maxi(level - 1, 0)
	return maxi(level - 2, 0)


## The fragment wound of one person `distance_m` from a burst, `exposure` being the chance that anything reaches him (his screening, posture and position,
## rolled once for all the classes): then every class is rolled for a hit, a class that hits is reduced, and only the worst outcome counts.
static func fragment_severity(distance_m: float, exposure: float = 1.0) -> int:
	if exposure < 1.0 and randf() >= exposure:
		return BLAST_NONE
	var worst: int = BLAST_NONE
	for level in [BLAST_WALKING, BLAST_SERIOUS, BLAST_DEAD]:
		if randf() < fragment_hit_chance(distance_m, level):
			worst = maxi(worst, fragment_reduced(level, randf()))
	return worst


## The chances of each fragment wound for one person, worked out rather than rolled: [none, walking, serious, dead] (index = severity), the classes
## being independent once he is exposed, so the worst of them has the product of their chances of being no worse.
static func fragment_distribution(distance_m: float, exposure: float = 1.0) -> Array[float]:
	var at_most: Array[float] = [1.0, 1.0, 1.0, 1.0] # chance that the worst outcome is no worse than [index], given he is exposed
	for level in [BLAST_WALKING, BLAST_SERIOUS, BLAST_DEAD]:
		var hit: float = fragment_hit_chance(distance_m, level)
		var outcome: Array[float] = [1.0 - hit, 0.0, 0.0, 0.0]
		outcome[level] += hit * GameConfig.FRAGMENT_AS_POTENTIAL
		outcome[maxi(level - 1, 0)] += hit * GameConfig.FRAGMENT_ONE_LOWER
		outcome[maxi(level - 2, 0)] += hit * (1.0 - GameConfig.FRAGMENT_AS_POTENTIAL - GameConfig.FRAGMENT_ONE_LOWER)
		var running := 0.0
		for severity in 4:
			running += outcome[severity]
			at_most[severity] *= running
	var exposed: Array[float] = [at_most[0], 0.0, 0.0, 0.0]
	for severity in range(1, 4):
		exposed[severity] = at_most[severity] - at_most[severity - 1]
	var result: Array[float] = [1.0 - exposure + exposure * exposed[0], exposure * exposed[1], exposure * exposed[2], exposure * exposed[3]]
	return result


## The chance a person `distance_m` from a burst, with `exposure` (1 standing in the open with nothing between), is hurt at all by the fragments.
static func fragment_casualty_chance(distance_m: float, exposure: float = 1.0) -> float:
	return 1.0 - fragment_distribution(distance_m, exposure)[BLAST_NONE]


## Blast injury severities (BLAST_*): 0 none, 1 walking wounded, 2 seriously wounded (heavily wounded), 3 dead.
const BLAST_NONE := 0
const BLAST_WALKING := 1
const BLAST_SERIOUS := 2
const BLAST_DEAD := 3


## The blast injury of one person `distance_m` from a burst, `roll` being a uniform draw in [0, 1): the user's bands (GameConfig.BLAST_*): dead up to
## 1 m, serious from 2 to 4 m, walking from 5 to 10 m, a straight-line mix between the bands (at 1.4 m, 60 percent dead and 40 serious), none beyond.
static func blast_severity(distance_m: float, roll: float) -> int:
	if distance_m <= GameConfig.BLAST_DEAD_M:
		return BLAST_DEAD
	if distance_m < GameConfig.BLAST_SERIOUS_FROM_M:
		var dead_share: float = (GameConfig.BLAST_SERIOUS_FROM_M - distance_m) / (GameConfig.BLAST_SERIOUS_FROM_M - GameConfig.BLAST_DEAD_M)
		return BLAST_DEAD if roll < dead_share else BLAST_SERIOUS
	if distance_m <= GameConfig.BLAST_SERIOUS_TO_M:
		return BLAST_SERIOUS
	if distance_m < GameConfig.BLAST_WALKING_FROM_M:
		var serious_share: float = (GameConfig.BLAST_WALKING_FROM_M - distance_m) / (GameConfig.BLAST_WALKING_FROM_M - GameConfig.BLAST_SERIOUS_TO_M)
		return BLAST_SERIOUS if roll < serious_share else BLAST_WALKING
	if distance_m <= GameConfig.BLAST_WALKING_TO_M:
		return BLAST_WALKING
	return BLAST_NONE


## The chance that a person completely escapes the blast because of the terrain they are in: GameConfig.BLAST_ESCAPE_IN_TREES in vegetation,
## BLAST_ESCAPE_IN_BUILDING in a building, none in the open. A unit on the move (`kept` below 1, see Unit.cover_kept) keeps the same share of its
## cover as for everything else: the chance of being caught is raised to the power `kept`.
static func blast_escape_chance(terrain: GameConfig.TerrainType, kept: float = 1.0) -> float:
	var base := 0.0
	if terrain == GameConfig.TerrainType.TREES:
		base = GameConfig.BLAST_ESCAPE_IN_TREES
	elif terrain == GameConfig.TerrainType.BUILDING:
		base = GameConfig.BLAST_ESCAPE_IN_BUILDING
	return 1.0 - pow(1.0 - base, kept)


## The radius of the disc a unit's people are spread over round its centre, for the blast: a squad 30 m, a mortar crew or a drone team 4 m, a lone
## person none.
static func blast_spread_m(unit: Unit) -> float:
	if unit.kind == Unit.Kind.MORTAR or unit.kind == Unit.Kind.DRONE_TEAM:
		return GameConfig.BLAST_CREW_SPREAD_M
	if unit.max_pips > 1:
		return GameConfig.BLAST_SQUAD_SPREAD_M
	return 0.0


## Where one person of a unit centred at `center` stands, at a uniformly random place on a disc of radius `spread_m` (metres) round it.
static func person_point_px(center: Vector2, spread_m: float) -> Vector2:
	if spread_m <= 0.0:
		return center
	var rho: float = spread_m * sqrt(randf()) * GameConfig.PIXELS_PER_METER
	return center + Vector2.from_angle(TAU * randf()) * rho


## One person's distance from a burst `center_m` from the unit's centre (see person_point_px).
static func person_distance_m(center_m: float, spread_m: float) -> float:
	if spread_m <= 0.0:
		return center_m
	var centre := Vector2(center_m * GameConfig.PIXELS_PER_METER, 0.0)
	return person_point_px(centre, spread_m).length() / GameConfig.PIXELS_PER_METER


## How many of `people` become casualties when each is one with probability `p`, independently (a binomial draw; for a large number the
## normal approximation, so a million-man test unit costs nothing).
static func binomial(people: int, p: float) -> int:
	if people <= 0 or p <= 0.0:
		return 0
	if p >= 1.0:
		return people
	if people <= 48:
		var n := 0
		for i in people:
			if randf() < p:
				n += 1
		return n
	var mean: float = float(people) * p
	var sd: float = sqrt(float(people) * p * (1.0 - p))
	return clampi(int(round(mean + sd * randfn(0.0, 1.0))), 0, people)

# Concealment: reduces the chance of being spotted in the first place.
const CONCEALMENT_MULTIPLIER := {
	GameConfig.TerrainType.OPEN: 1.0,
	GameConfig.TerrainType.TREES: 0.5,
	GameConfig.TerrainType.BUILDING: 0.7,
}


## The detection range between a specific observer/target pair — shared by
## both roll_spot (becoming visible) and has_live_observer (staying visible)
## so the two can never disagree about how far someone can be seen. A hidden
## spotter or mortar overrides everything else: elevation and a spotter's
## own extended range don't help you find someone hunkered down and hidden.
static func effective_detection_range(observer: Unit, target: Unit) -> float:
	if target.kind == Unit.Kind.SPOTTER and GameConfig.is_in_cover(target.terrain_type()):
		return GameConfig.SPOTTER_HIDDEN_DETECTION_RANGE
	if target.kind == Unit.Kind.MORTAR and GameConfig.is_in_cover(target.terrain_type()):
		return GameConfig.MORTAR_HIDDEN_DETECTION_RANGE
	# A drone's camera at DRONE_ALTITUDE_M is a wholly different sensor, not
	# the ground-based one with a bonus bolted on — it replaces the whole
	# calculation, including the elevation-advantage bonus below (a drone is
	# always far higher than literally any point on this map already).
	# Weather (see Weather): a drone's range scales with the altitude it has to
	# fly at to see through rain, and is ZERO once rain/snow is moderate or
	# worse; a ground observer's shrinks with any precipitation.
	if observer.kind == Unit.Kind.DRONE:
		return GameConfig.DRONE_DETECTION_RANGE * (Weather.current.drone_detection_scale() if Weather.current != null else 1.0)
	var detection_range: float = GameConfig.DETECTION_BASE_RANGE
	if observer.kind == Unit.Kind.SPOTTER:
		detection_range += GameConfig.SPOTTER_DETECTION_RANGE_BONUS
	if observer.elevation() > target.elevation() + GameConfig.ELEVATION_ADVANTAGE_THRESHOLD_M:
		detection_range += GameConfig.DETECTION_ELEVATION_BONUS
	if Weather.current != null:
		detection_range *= Weather.current.ground_detection_scale()
	return detection_range


## One spotting roll for `observer` trying to notice `target` this tick.
## Returns true if `target` becomes visible this tick. Call this only for
## targets not already visible — BattleManager separately handles a
## currently-visible target LOSING visibility (see has_live_observer) once
## nobody has eyes on it any more; visibility is a live, moment-to-moment
## fact, not a permanent flag (see Unit.is_visible).
##
## `scenario_delta` must be tactical seconds, matching GameConfig.
## SPOT_CHANCE_PER_TACTICAL_SECOND — every other rate constant in this
## game is calibrated against the tactical clock, not real wall-clock time.
## BattleManager._update_spotting used to pass real elapsed_time here
## instead, which at TIME_SCALE_NORMAL (60x) alone meant a target sitting
## in plain view for a real 10 seconds — 30 tactical MINUTES — could still
## go entirely unspotted, since the roll only accumulated real-world
## seconds' worth of chance while tactical time raced ahead 60x faster.
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
## A mortar crew gets the same hidden/exposed treatment (GameConfig.
## MORTAR_HIDDEN_DETECTION_RANGE/MORTAR_EXPOSED_CONCEALMENT_MULTIPLIER) —
## real siting/camouflage doctrine makes a well-hidden gun genuinely hard
## to spot, but never categorically impossible the way an absolute "never
## visible" rule would claim. This is a probabilistic layer underneath the
## hard geometric one has_direct_los already provides: a mortar masked by
## a hill is fully protected regardless of any of this (the roll never
## even happens, LOS is blocked outright above); this only decides how
## hard the crew is to spot once LOS is genuinely clear.
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
## A drone cannot see a unit INSIDE a building (under its roof), whatever its range or the weather: buildings are otherwise no obstacle to
## it (GameConfig.has_aerial_los). Direct user instruction: "other than units INSIDE the building, which would indeed not be seen by the
## drone." A drone is itself never hidden this way (it is in the air).
static func hidden_from_drone(observer: Unit, target: Unit) -> bool:
	return observer.kind == Unit.Kind.DRONE and target.kind != Unit.Kind.DRONE and GameConfig.is_building_at(target.global_position)


static func roll_spot(observer: Unit, target: Unit, scenario_delta: float) -> bool:
	var observer_is_drone := observer.kind == Unit.Kind.DRONE
	if hidden_from_drone(observer, target):
		return false
	if target.kind == Unit.Kind.DRONE and not observer_is_drone:
		return _roll_ground_notices_drone(observer, target, scenario_delta)

	# Range first: it is a single subtraction, while line of sight samples the
	# terrain — checking it in this order returns the same answers, just far
	# less often paying for a sightline that could never have counted.
	var distance: float = observer.global_position.distance_to(target.global_position)
	var detection_range: float = effective_detection_range(observer, target)
	if distance > detection_range or detection_range <= 0.0:
		return false

	var has_los: bool = GameConfig.has_aerial_los(observer.global_position, target.global_position) if observer_is_drone \
		else GameConfig.has_direct_los(observer.global_position, target.global_position)
	if not has_los:
		return false

	var chance: float = GameConfig.SPOT_CHANCE_PER_TACTICAL_SECOND
	# Woods between a ground observer and its target make the target much
	# harder to notice (see GameConfig.tree_sight_transmission). A drone looks
	# down rather than through them, so it is exempt.
	if not observer_is_drone:
		chance *= GameConfig.tree_sight_transmission(observer.get_instance_id(), target.get_instance_id(), observer.global_position, target.global_position)
	var concealment_table: Dictionary = GameConfig.DRONE_CONCEALMENT_MULTIPLIER if observer_is_drone else CONCEALMENT_MULTIPLIER
	chance *= concealment_table[target.terrain_type()]
	# A man lying in the open is harder to notice from the ground (GameConfig.LYING_SPOT_MULTIPLIER). Not for a drone looking down; not for
	# the spotter, whose own multiplier below is already a man going prone and keeping still; not in cover, where the terrain's own
	# concealment is the effect.
	if not observer_is_drone and target.kind != Unit.Kind.SPOTTER and target.posture() == Unit.Posture.PRONE \
			and target.terrain_type() == GameConfig.TerrainType.OPEN:
		chance *= GameConfig.LYING_SPOT_MULTIPLIER
	# A drone whose team is itself on the move is flown with divided attention and a shakier
	# feed: slightly less likely to notice what is in its view.
	if observer_is_drone and observer.drone_operator_moving:
		chance *= GameConfig.DRONE_TEAM_MOVING_SPOT_CHANCE_MULTIPLIER
	if observer_is_drone and observer.drone_operator_casualties > 0:
		chance *= pow(GameConfig.DRONE_TEAM_CASUALTY_SPOT_MULTIPLIER, float(observer.drone_operator_casualties))
	var target_hidden_spotter := target.kind == Unit.Kind.SPOTTER and GameConfig.is_in_cover(target.terrain_type())
	if target.kind == Unit.Kind.SPOTTER and not target_hidden_spotter:
		chance *= GameConfig.SPOTTER_EXPOSED_CONCEALMENT_MULTIPLIER
	var target_hidden_mortar := target.kind == Unit.Kind.MORTAR and GameConfig.is_in_cover(target.terrain_type())
	if target.kind == Unit.Kind.MORTAR and not target_hidden_mortar:
		chance *= GameConfig.MORTAR_EXPOSED_CONCEALMENT_MULTIPLIER
	# A unit that's JUST stopped moving hasn't thereby become as hard to
	# spot as one that's been sitting still the whole time — real movement
	# leaves a lingering signature (settling dust, a thermal bloom,
	# disturbed foliage) that fades rather than vanishing the instant the
	# unit halts. Full MOVING_SPOT_MULTIPLIER while actually moving
	# (seconds_stationary is reset to 0 every tick it moves — see
	# BattleManager._tick_movement), decaying linearly back to no bonus
	# at all over GameConfig.RECENT_MOVEMENT_SIGNATURE_DECAY_S. This can
	# still never make a concealed-but-recently-moved target easier to
	# spot than one caught fully in the open: the concealment multiplier
	# above already applies first, and OPEN's own multiplier is 1.0 with
	# no further discount, so a concealed target's combined chance stays
	# below an open one's as long as the concealment discount is stronger
	# than this bonus can offset (true for every concealment value in
	# either table below the full recency bonus itself).
	var recency_t: float = clamp(target.seconds_stationary / GameConfig.RECENT_MOVEMENT_SIGNATURE_DECAY_S, 0.0, 1.0)
	chance *= lerp(GameConfig.MOVING_SPOT_MULTIPLIER, 1.0, recency_t)
	# Distance falloff is steeper than linear for a DRONE specifically:
	# an overhead sensor's own footprint is a cone, not a flat disk — near
	# the center (close to directly overhead) the look angle is steep and
	# resolution is at its best across the whole footprint; toward the
	# edge of that footprint the same target is seen from a far more
	# oblique angle, where residual foliage/structure much more easily
	# breaks the sightline even within nominal detection range. Squaring
	# the linear falloff keeps the near-full-strength "core" directly
	# under the drone narrower and drops off faster toward the edge,
	# rather than a uniform straight-line decline across the whole
	# footprint. A ground observer's own falloff is about eye/optics
	# range, not sensor-cone geometry, so it stays linear.
	var falloff: float = clamp(1.0 - (distance / detection_range), 0.0, 1.0)
	chance *= falloff * falloff if observer_is_drone else falloff
	chance *= scenario_delta

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
static func _roll_ground_notices_drone(observer: Unit, target: Unit, scenario_delta: float) -> bool:
	if not GameConfig.has_aerial_los(observer.global_position, target.global_position):
		return false
	var horizontal_distance_m: float = observer.global_position.distance_to(target.global_position) / GameConfig.PIXELS_PER_METER
	# A drone flying lower to see through rain is closer to the ground (see Weather).
	var altitude_m: float = Weather.current.drone_operating_altitude_m() if Weather.current != null else GameConfig.DRONE_ALTITUDE_M
	var slant_range_m: float = sqrt(horizontal_distance_m * horizontal_distance_m + altitude_m * altitude_m)
	if slant_range_m > GameConfig.DRONE_GROUND_NOTICE_MAX_RANGE_M:
		return false
	var chance_per_tick: float = 1.0 - pow(1.0 - GameConfig.DRONE_GROUND_NOTICE_CHANCE_PER_MINUTE, scenario_delta / 60.0)
	return randf() < chance_per_tick


## True if ANY unit in `observers` currently has clear, in-range line of
## sight to `target` right now. This is what keeps a currently-visible
## target visible — the moment nobody qualifies any more, the target stops
## being visible. Uses the exact same range rule as roll_spot (effective_
## detection_range), optionally widened by `retained` — see its own doc
## comment below — but with no concealment-based chance roll — this asks
## "could someone be watching it right now," not "did anyone just now
## notice it."
##
## A ground observer's view also has to get through the woods between them
## (GameConfig.tree_sight_transmission) — but only to TREE_SIGHT_KEEP_TRANSMISSION,
## far easier than first noticing the target (see roll_spot). `ignore_trees`
## drops that one test, so BattleManager can tell "lost only because of
## woods" (which gets a grace period before the target really drops) apart
## from "lost to a building, a hill or range" (which is immediate).
##
## `retained` — true only when checking whether an ALREADY-visible target
## should stay that way (BattleManager._refresh_visibility's own "is_visible"
## branch). Direct user report: "Enemy squads were just flashing visibility
## at our retreating squads when the enemies fired... once a unit has been
## spotted, let's have it stay spotted up to 150% of the range to spot it in
## the first place. Once you've seen someone, it is easier to track them,
## even if they get further away." Widens the pure RANGE test by
## GameConfig.VISIBILITY_RETAIN_RANGE_FRACTION; never touches the hard
## geometric LOS block (has_direct_los/has_aerial_los), which still drops a
## target at once behind a building or a hill either way, exactly as before.
## Every other caller here is asking a different, present-tense question
## ("is anyone watching RIGHT NOW," for fire-adjustment quality or a
## drone-only-sighting check) rather than "has this contact been kept," and
## leaves this false, unaffected.
static func has_live_observer(target: Unit, observers: Array[Unit], ignore_trees: bool = false, retained: bool = false) -> bool:
	for observer in observers:
		if observer.state != Unit.State.ACTIVE:
			continue
		var distance: float = observer.global_position.distance_to(target.global_position)
		var live_range: float = effective_detection_range(observer, target)
		if retained:
			live_range *= GameConfig.VISIBILITY_RETAIN_RANGE_FRACTION
		if distance > live_range or live_range <= 0.0:
			continue
		if hidden_from_drone(observer, target):
			continue
		var has_los: bool = GameConfig.has_aerial_los(observer.global_position, target.global_position) if observer.kind == Unit.Kind.DRONE \
			else GameConfig.has_direct_los(observer.global_position, target.global_position)
		if not has_los:
			continue
		if not ignore_trees and observer.kind != Unit.Kind.DRONE:
			var transmission: float = GameConfig.tree_sight_transmission(observer.get_instance_id(), target.get_instance_id(), observer.global_position, target.global_position)
			if transmission < GameConfig.TREE_SIGHT_KEEP_TRANSMISSION:
				continue
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
## Direct fire ALSO gets a real, range-dependent lethality bonus — see
## GameConfig.SQUAD_CLOSE_RANGE_HIT_MULTIPLIER for the real-world combat
## data behind both the existence and the SHAPE of this curve — independent
## of and stacked on top of the cover/moving multipliers above: closer
## range means an easier shot regardless of what the target is or isn't
## hiding behind or whether it's on the move. Exponential decay, not a
## straight line — most of the bonus concentrated at genuinely close range,
## a rapid initial falloff, then a long, nearly-flat tail approaching (but
## never quite reaching) a neutral 1.0x — matching how real rifle hit
## probability actually falls off with distance. Indirect (mortar) fire
## doesn't get this — a lobbed shell's accuracy isn't a function of how
## close the target happens to be to the tube.
##
## `drone_directing_multiplier` — 1.0 (no effect) except for the player's own mortar
## while a friendly drone is actually airborne, per GameConfig.DRONE_DIRECTED_
## MORTAR_ACCURACY_MULTIPLIER's own reasoning: then the multiplier BattleManager
## _drone_directing_multiplier works out (the full bonus with a stationary drone team, a
## smaller one with a team on the move) — applies a further flat
## accuracy bonus on top of everything else above. A continuous overhead
## video feed corrects the next round off the last one's actual impact in
## a way a ground spotter's limited, single-position view never can; cover
## still does its job regardless (this is an accuracy multiplier, not a
## way to see through a roof).
##
## A genuinely higher-up DIRECT-fire attacker (GameConfig.
## ELEVATION_ADVANTAGE_THRESHOLD_M, the same gate the detection-range
## bonus already uses) partially defeats whatever cover the defender is
## using — see GameConfig.ELEVATION_COVER_DEFEAT_FRACTION's own doc
## comment for the real doctrine (plunging fire into a position from
## above, the entire reason a "reverse slope defense" exists) and for why
## this is deliberately NOT modeled as an independent flat accuracy bonus.
## Mortar fire is excluded — its trajectory already plunges regardless of
## the tube's own elevation, which is exactly what its own, separately
## weaker MORTAR_COVER_MULTIPLIER table already represents.
##
## `ally_positions` and `known_enemy_positions` are passed straight through
## to `defender.take_hit()` — other same-team units' current positions (so
## a squad breaking for cover after this hit picks a DIFFERENT patch than
## one an ally is already using — see GameConfig.nearest_cover_point's
## avoid_positions) and currently-visible enemy positions from the
## defender's own side's point of view (so that same retreat never heads
## toward, or lands right next to, a threat its own side already knows
## about — see nearest_cover_point's DANGER_RADIUS exclusion).
##
## `impact_distance` — likewise passed straight through to `take_hit`: how
## far the round's real impact point (a mortar's own dispersion, or the
## defender's own position for direct fire — see BattleManager.
## _resolve_fire_and_check_bunching's own doc comment) landed from the
## defender. Only a MORTAR/DRONE_TEAM defender's own crew-casualty roll
## ever reads it (Unit._apply_crew_casualties); everyone else's casualty
## count is unrelated to this specific number.
## A DRONE defender is a hard, unconditional zero — not merely a severe
## reduction — regardless of who's firing. Real-world sourcing (see the
## design doc's own revision-log entry, prompted by a live bug report of
## an enemy mortar firing an HE round at a drone hundreds of meters away)
## found no plausible engagement exists in this scenario's era: a mortar's
## plunging fire has no way to aim at or fuze against a small moving
## aerial point target at all, and ordinary infantry small arms — no
## shotgun loads or fire-control optics here — are reported as unable to
## even track and hit something this small and fast, altitude aside. It
## isn't standing on any ground to take cover in either way, so the
## terrain-based cover table below never applies to it regardless.
## `_pick_target`/`_forecast_target` already exclude DRONE from ever being
## chosen as a real target — this is the same conclusion applied to the
## read-only risk-forecast path (BattleManager._risk_forecast can still
## ask "what's the risk to this drone," and the honest answer is now none
## from ground fire), so the two paths can't silently disagree.
## The same hit model used for resolution and read-only forecasts.
static func hit_probability(attacker: Unit, defender: Unit, drone_directing_multiplier: float = 1.0, defender_position: Vector2 = Vector2.INF, attacker_position: Vector2 = Vector2.INF, crossfire_multiplier: float = 1.0) -> float:
	var point: Vector2 = defender.global_position if is_inf(defender_position.x) else defender_position
	var origin: Vector2 = attacker.global_position if is_inf(attacker_position.x) else attacker_position
	var chance: float
	if defender.kind == Unit.Kind.DRONE:
		chance = 0.0
	else:
		var moving := defender.activity == Unit.Activity.MOVING
		var cover_table: Dictionary = MORTAR_COVER_MULTIPLIER if attacker.kind == Unit.Kind.MORTAR else SQUAD_COVER_MULTIPLIER
		# What the terrain does for it: all of the table's value for a unit that is still; for one that is moving, only part of it (the
		# ratio to the open, to the power MOVING_COVER_KEPT of its terrain: walls and trunks are still between it and the shooter), on top
		# of the price of being a moving target below. In the open the ratio is 1 and a moving unit is as it was.
		var terrain: GameConfig.TerrainType = defender.exposure_terrain(point)
		var cover_multiplier: float = cover_table[terrain]
		if moving:
			cover_multiplier = pow(cover_table[terrain] / cover_table[GameConfig.TerrainType.OPEN], defender.cover_kept(point))
		elif defender.in_fighting_position(point):
			# at its post in a finished fighting position: the better of the terrain and the hole
			cover_multiplier = minf(cover_multiplier, cover_table[GameConfig.TerrainType.OPEN] * GameConfig.FIGHTING_POSITION_RATIO)
		# A high-ground attacker partially defeats the defender's own cover
		# — see ELEVATION_COVER_DEFEAT_FRACTION's own doc comment for the
		# real doctrine (and its limits) behind this. Direct fire only:
		# a mortar's plunging trajectory already does this regardless of
		# the tube's own elevation (that's what MORTAR_COVER_MULTIPLIER's
		# whole table already represents). A moving defender has part of
		# its cover to defeat, as a still one has all of it.
		if attacker.kind != Unit.Kind.MORTAR:
			if GameConfig.elevation_m(origin) > GameConfig.elevation_m(point) + GameConfig.ELEVATION_ADVANTAGE_THRESHOLD_M:
				cover_multiplier = lerp(cover_multiplier, 1.0, GameConfig.ELEVATION_COVER_DEFEAT_FRACTION)
			# Inside CLOSE_RANGE_COVER_DEFEAT_M the shooter is within reach of grenades and of clearing a room or a trench line: cover no
			# longer protects (a target in the open keeps its exposure penalty, which is above 1).
			if origin.distance_to(point) <= GameConfig.CLOSE_RANGE_COVER_DEFEAT_M * GameConfig.PIXELS_PER_METER:
				cover_multiplier = maxf(cover_multiplier, 1.0)
		# A man who has gone to ground is a smaller, harder target than one at his post (Unit.posture_factor: a third in the open, a half in
		# cover on top of the table above; 1 for anyone upright or moving).
		chance = attacker.base_hit_chance * cover_multiplier * defender.posture_factor(point)
		if attacker.kind != Unit.Kind.MORTAR:
			var distance: float = origin.distance_to(point)
			var decay: float = exp(-distance / GameConfig.SQUAD_CLOSE_RANGE_DECAY_M)
			chance *= 1.0 + (GameConfig.SQUAD_CLOSE_RANGE_HIT_MULTIPLIER - 1.0) * decay
		if moving:
			if attacker.kind == Unit.Kind.MORTAR:
				chance *= GameConfig.MORTAR_PREDICTABLE_MOVING_MULTIPLIER if defender.movement_predictable else GameConfig.MORTAR_UNPREDICTABLE_MOVING_MULTIPLIER
			else:
				chance *= GameConfig.MOVING_HIT_MULTIPLIER
		if attacker.kind == Unit.Kind.MORTAR:
			chance *= drone_directing_multiplier
		# A squad that is being suppressed shoots worse (see GameConfig.SUPPRESSION_MAX_ACCURACY_LOSS).
		if attacker.kind != Unit.Kind.MORTAR:
			chance *= 1.0 - GameConfig.SUPPRESSION_MAX_ACCURACY_LOSS * clampf(attacker.suppression, 0.0, 1.0)
			# ... and a squad that is pinned, heads down, can hardly engage a man moving in the open: that is what covering fire is for.
			if attacker.pinned and moving:
				chance *= GameConfig.PINNED_VS_MOVING_FIRE_MULTIPLIER
		# Being fired on from several directions at once multiplies the expected damage taken from DIRECT fire —
		# see safe_arc_deg/crossfire_multiplier. Direct user ruling: "Mortar hits should be totally
		# unaffected" — a plunging round has no direction to be caught in crossfire from. A chance already at
		# 1.0 (a moving target at point-blank) cannot go higher: one shot is at most one hit.
		if attacker.kind != Unit.Kind.MORTAR:
			chance *= crossfire_multiplier
	return clampf(chance, 0.0, 1.0)


static func resolve_fire(attacker: Unit, defender: Unit, ally_positions: Array[Vector2] = [], known_enemy_positions: Array[Vector2] = [], drone_directing_multiplier: float = 1.0, impact_distance: float = 0.0, crossfire_multiplier: float = 1.0) -> bool:
	var chance := hit_probability(attacker, defender, drone_directing_multiplier, Vector2.INF, Vector2.INF, crossfire_multiplier)
	var hit: bool = randf() < chance
	if hit:
		defender.take_hit(attacker.kind == Unit.Kind.MORTAR, ally_positions, known_enemy_positions, impact_distance)
	return hit


## The largest circular arc, in degrees, around `defender_position` from which no shooter is firing: the
## biggest gap between the bearings of `shooter_positions` as seen from the defender. No shooter, or one
## (all in one direction), leaves the whole circle: 360. Two opposite sides leave 180, four evenly spaced
## sides 90. A shooter standing on the defender's own spot has no bearing and is ignored.
static func safe_arc_deg(defender_position: Vector2, shooter_positions: Array) -> float:
	var bearings: Array[float] = []
	for p in shooter_positions:
		var offset: Vector2 = p - defender_position
		if offset.length_squared() < 0.0001:
			continue
		bearings.append(rad_to_deg(offset.angle()))
	if bearings.size() <= 1:
		return GameConfig.CROSSFIRE_FULL_ARC_DEG
	bearings.sort()
	var widest: float = bearings[0] + 360.0 - bearings[bearings.size() - 1] # the wrap-around gap
	for i in range(1, bearings.size()):
		widest = maxf(widest, bearings[i] - bearings[i - 1])
	return clampf(widest, 0.0, GameConfig.CROSSFIRE_FULL_ARC_DEG)


## Expected-damage multiplier for a given safe arc: x1 at 360, x2 at 240, x3 at 120, x4 at 0 (linear).
static func crossfire_multiplier(safe_arc: float) -> float:
	var arc: float = clampf(safe_arc, 0.0, GameConfig.CROSSFIRE_FULL_ARC_DEG)
	return 1.0 + (GameConfig.CROSSFIRE_FULL_ARC_DEG - arc) / GameConfig.CROSSFIRE_ARC_PER_EXTRA_MULTIPLE_DEG
