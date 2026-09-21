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
static func blast_casualty_chance(distance: float, max_chance: float, terrain: GameConfig.TerrainType) -> float:
	var decay: float = exp(-log(2.0) * distance / GameConfig.MORTAR_BLAST_CASUALTY_RADIUS)
	var cover_factor: float = MORTAR_COVER_MULTIPLIER.get(terrain, 1.0) / MORTAR_COVER_MULTIPLIER[GameConfig.TerrainType.OPEN]
	return clamp(max_chance * decay * cover_factor, 0.0, 1.0)

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
static func roll_spot(observer: Unit, target: Unit, scenario_delta: float) -> bool:
	var observer_is_drone := observer.kind == Unit.Kind.DRONE
	if target.kind == Unit.Kind.DRONE and not observer_is_drone:
		return _roll_ground_notices_drone(observer, target, scenario_delta)

	# Range first: it is a single subtraction, while line of sight samples the
	# terrain — checking it in this order returns the same answers, just far
	# less often paying for a sightline that could never have counted.
	var distance: float = observer.global_position.distance_to(target.global_position)
	var detection_range: float = effective_detection_range(observer, target)
	if distance > detection_range:
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
	var slant_range_m: float = sqrt(horizontal_distance_m * horizontal_distance_m + GameConfig.DRONE_ALTITUDE_M * GameConfig.DRONE_ALTITUDE_M)
	if slant_range_m > GameConfig.DRONE_GROUND_NOTICE_MAX_RANGE_M:
		return false
	var chance_per_tick: float = 1.0 - pow(1.0 - GameConfig.DRONE_GROUND_NOTICE_CHANCE_PER_MINUTE, scenario_delta / 60.0)
	return randf() < chance_per_tick


## True if ANY unit in `observers` currently has clear, in-range line of
## sight to `target` right now. This is what keeps a currently-visible
## target visible (or makes it visible instantly, e.g. when it fires) — the
## moment nobody qualifies any more, the target stops being visible. Uses
## the exact same range rule as roll_spot (effective_detection_range) but
## with no concealment-based chance roll — this asks "could someone be
## watching it right now," not "did anyone just now notice it."
##
## A ground observer's view also has to get through the woods between them
## (GameConfig.tree_sight_transmission) — but only to TREE_SIGHT_KEEP_TRANSMISSION,
## far easier than first noticing the target (see roll_spot). `ignore_trees`
## drops that one test, so BattleManager can tell "lost only because of
## woods" (which gets a grace period before the target really drops) apart
## from "lost to a building, a hill or range" (which is immediate).
static func has_live_observer(target: Unit, observers: Array[Unit], ignore_trees: bool = false) -> bool:
	for observer in observers:
		if observer.state != Unit.State.ACTIVE:
			continue
		var distance: float = observer.global_position.distance_to(target.global_position)
		if distance > effective_detection_range(observer, target):
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
## `drone_directed` — true only for the player's own mortar, and only while
## a friendly drone is actually airborne, per GameConfig.DRONE_DIRECTED_
## MORTAR_ACCURACY_MULTIPLIER's own reasoning — applies a further flat
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
static func hit_probability(attacker: Unit, defender: Unit, drone_directed: bool = false, defender_position: Vector2 = Vector2.INF, attacker_position: Vector2 = Vector2.INF) -> float:
	var point: Vector2 = defender.global_position if is_inf(defender_position.x) else defender_position
	var origin: Vector2 = attacker.global_position if is_inf(attacker_position.x) else attacker_position
	var chance: float
	if defender.kind == Unit.Kind.DRONE:
		chance = 0.0
	else:
		var moving := defender.activity == Unit.Activity.MOVING
		var cover_table: Dictionary = MORTAR_COVER_MULTIPLIER if attacker.kind == Unit.Kind.MORTAR else SQUAD_COVER_MULTIPLIER
		var cover_multiplier: float = 1.0 if moving else cover_table[GameConfig.get_terrain_type_at(point)]
		# A high-ground attacker partially defeats the defender's own cover
		# — see ELEVATION_COVER_DEFEAT_FRACTION's own doc comment for the
		# real doctrine (and its limits) behind this. Direct fire only:
		# a mortar's plunging trajectory already does this regardless of
		# the tube's own elevation (that's what MORTAR_COVER_MULTIPLIER's
		# whole table already represents), and a moving defender already
		# gets no cover benefit to defeat in the first place.
		if attacker.kind != Unit.Kind.MORTAR and not moving:
			if GameConfig.elevation_m(origin) > GameConfig.elevation_m(point) + GameConfig.ELEVATION_ADVANTAGE_THRESHOLD_M:
				cover_multiplier = lerp(cover_multiplier, 1.0, GameConfig.ELEVATION_COVER_DEFEAT_FRACTION)
		chance = attacker.base_hit_chance * cover_multiplier
		if attacker.kind != Unit.Kind.MORTAR:
			var distance: float = origin.distance_to(point)
			var decay: float = exp(-distance / GameConfig.SQUAD_CLOSE_RANGE_DECAY_M)
			chance *= 1.0 + (GameConfig.SQUAD_CLOSE_RANGE_HIT_MULTIPLIER - 1.0) * decay
		if moving:
			if attacker.kind == Unit.Kind.MORTAR:
				chance *= GameConfig.MORTAR_PREDICTABLE_MOVING_MULTIPLIER if defender.movement_predictable else GameConfig.MORTAR_UNPREDICTABLE_MOVING_MULTIPLIER
			else:
				chance *= GameConfig.MOVING_HIT_MULTIPLIER
		if attacker.kind == Unit.Kind.MORTAR and drone_directed:
			chance *= GameConfig.DRONE_DIRECTED_MORTAR_ACCURACY_MULTIPLIER
	return clampf(chance, 0.0, 1.0)


static func resolve_fire(attacker: Unit, defender: Unit, ally_positions: Array[Vector2] = [], known_enemy_positions: Array[Vector2] = [], drone_directed: bool = false, impact_distance: float = 0.0) -> bool:
	var chance := hit_probability(attacker, defender, drone_directed)
	var hit: bool = randf() < chance
	if hit:
		defender.take_hit(attacker.kind == Unit.Kind.MORTAR, ally_positions, known_enemy_positions, impact_distance)
	return hit
