extends Node2D
class_name Unit
## A single deployable unit: an infantry squad or a mortar crew.
## Pure data + drawing. All combat/spotting/timing logic lives in
## BattleManager and CombatResolver so this stays a dumb, easy-to-inspect
## object — with one exception: what a hit does to THIS unit's own state
## (destroyed / retreat / seek cover) is decided right here in take_hit(),
## since that's inherent to the unit reacting to being hit, not to the wider
## battle.

enum Team { PLAYER, ENEMY }
## DRONE_TEAM is the player-deployed ground crew (ReconMode.DRONE_TEAM's
## counterpart to SPOTTER) — never itself airborne, never itself an
## observer. DRONE is the single currently-airborne scout it operates;
## BattleManager creates/frees a DRONE Unit per sortie rather than keeping
## one around for the whole battle — see BattleManager's drone-fleet fields.
enum Kind { SQUAD, MORTAR, SPOTTER, DRONE_TEAM, DRONE, RESUPPLY_RUN }
## ACTIVE: fighting (possibly moving toward move_target). RETREATING: pulling
## back off the field entirely, still on the field and can still take fire.
## WITHDRAWN: reached safety, no longer part of the fight. SURRENDERED: laid
## down arms in place rather than attempting a retreat it judged too risky
## (see BattleManager._squad_surrender_chance) — alive and unharmed, same as
## WITHDRAWN, but a distinct outcome worth reporting separately rather than
## folding into "withdrew safely." DESTROYED: out of action for good.
enum State { ACTIVE, RETREATING, WITHDRAWN, DESTROYED, SURRENDERED }
enum Activity { STATIONARY, MOVING }
## How the unit is carrying itself: upright (walking, running, or standing still) or down (lying or crouched behind whatever is there).
## Every ground unit has one at every moment; see posture() and docs/designs/posture-and-suppression.md.
enum Posture { STANDING, PRONE }
## How far a unit has dug in where it stands (GameConfig.SHELL_SCRAPE_BUILD_S, FIGHTING_POSITION_BUILD_S; BattleManager._update_entrenchment).
enum Entrenchment { NONE, SCRAPE, FIGHTING_POSITION }

var team: Team = Team.PLAYER
var kind: Kind = Kind.SQUAD
var unit_label: String = "Squad"

var max_pips: int = 4
var pips: int = 4
var base_hit_chance: float = 0.20
var retreat_threshold: float = 0.50 # SQUAD only — fraction of pips lost that triggers retreat
## SQUAD only: how thoroughly the fire it is under is keeping its heads down, 0 to 1 (see GameConfig.SUPPRESSION_*), and whether it is pinned
## (from SUPPRESSION_PIN_LEVEL until it falls below SUPPRESSION_RELEASE_LEVEL).
var suppression: float = 0.0
## MORTAR only: true while the mouse is over it in battle, which shows its range circle (for the player's, the same circle the setup screen
## draws; for an enemy's, only while the player can see it). Set by BattleManager.update_hover.
var show_range_ring: bool = false
var pinned: bool = false
var state: State = State.ACTIVE
var activity: Activity = Activity.STATIONARY
# How long (tactical seconds) this unit has been STATIONARY, reset to 0
# the instant it stops MOVING — see BattleManager._tick_movement, which
# maintains this every tick for every unit regardless of side. Feeds
# CombatResolver.roll_spot's decaying "recently moved" signature bonus:
# a unit that's JUST stopped still carries the same elevated signature
# (dust, disturbed foliage, thermal bloom) a currently-moving one does,
# fading back to baseline over GameConfig.RECENT_MOVEMENT_SIGNATURE_
# DECAY_S. Starts effectively infinite — a unit that's never moved at
# all (e.g. still in its initial deployed position) has no recent-
# movement signature to decay from.
var seconds_stationary: float = 1e9
## Posture state (see posture() and BattleManager._update_postures): whether this unit, standing still in the open, has gone to ground
## under fire; when fire last arrived at it and when the current spell of fire began (scenario time); and, for a mortar crew, when it last
## fired a round (a crew serving its gun is on its feet).
var gone_to_ground: bool = false
## Whether this unit has already hesitated, in the present spell of being pinned, before moving (see GameConfig.PINNED_HESITATION_S);
## cleared when it is released.
var pinned_hesitated: bool = false
## SQUAD only: its small-arms ammunition (see GameConfig.SQUAD_ROUNDS_PER_PERSON). `rounds_limited` is set by setup(), so a bare unit
## built some other way is not rationed.
var rounds_limited: bool = false
## SQUAD only: when it last fired a volley (scenario time), and whether it is on its way to close with a position (an assault).
var last_volley_at: float = -1.0e9
var assaulting: bool = false
## SQUAD only: hand grenades left (see GameConfig.GRENADES_PER_PERSON).
var grenades: int = 0
var rounds: int = 0
var rounds_capacity: int = 0
## Digging in: the state, the seconds spent digging at this place, and the place (a unit that goes more than
## GameConfig.ENTRENCHMENT_ANCHOR_RADIUS_M from it starts again).
var entrenchment: Entrenchment = Entrenchment.NONE
var digging_seconds: float = 0.0
var dig_anchor: Vector2 = Vector2.INF
## How long (tactical seconds) a unit that is down has been trying to move, getting up (GameConfig.RISE_DELAY_S).
var rising_for: float = 0.0
var fire_arrived_at: float = -1e9
var fire_episode_started_at: float = -1e9
var last_round_fired_at: float = -1e9

# Is this unit currently visible to the OPPOSING side, right now? This is a
# live, moment-to-moment fact recomputed by BattleManager every tick — not a
# permanent flag. Spotting something once does not make it spotted forever;
# losing line of sight loses visibility too.
var is_visible: bool = false

# The PLAYER side's own knowledge of THIS unit's condition, as of the last
# time it was actually observed (is_visible) — a frozen last report, not a
# live read of the true state, exactly like a real commander's own picture
# of the enemy. Meaningless for the player's own units (their own side is
# always fully known); populated for enemy_units only by BattleManager's
# _update_player_intel. Drives the live CasualtyDashboard's enemy readout
# and, unless the battle ends with the position held or with drone
# coverage (see BattleManager._end_battle), the AAR report too.
var player_has_been_sighted: bool = false
var player_known_pips: int = 0
var player_known_state: State = State.ACTIVE
# Where this unit was standing the last time it was actually observed, and
# when — Vector2.INF / -INF until first sighted. Currently only consulted
# for an enemy MORTAR (see BattleManager._known_enemy_mortar_lead's third,
# untrusted fallback): a real commander doesn't forget where a gun was
# last seen just because it went quiet again, even though it might have
# moved since — that's exactly why this feeds an UNTRUSTED lead, not a
# trusted one.
var player_known_position: Vector2 = Vector2.INF
var player_known_position_time: float = -INF
## Whether the player has actually SEEN this (enemy) mortar's gun abandoned — "the enemy team without
## the gun, or the gun without the team" — as opposed to it merely being true in ground truth
## (mortar_gun_abandoned) with nobody having witnessed it. Direct user correction to
## BattleManager._mortar_existence_confidence: "'Seen gun abandoned' would also be good enough."
var player_known_gun_abandoned: bool = false

# The mirror image of the player_known_* block above: the ENEMY side's own
# knowledge of THIS unit — meaningless for the enemy's own units, populated
# for player_units only by BattleManager._update_enemy_intel. Direct user
# correction after investigating a real, live-reported asymmetry (a
# friendly mortar abandoning the gun after a single light wound while an
# enemy mortar kept fighting with a badly reduced crew): _known_enemy_
# positions used to resolve the player's own knowledge of the enemy via
# this exact persistent-memory pattern, but had no equivalent for the
# enemy's own knowledge of the player at all — only ever checking LIVE
# is_visible, which is almost always false at any given instant. This
# project's own stated knowledge-locality principle ("no decision should
# rely on omniscient truth a real unit couldn't know") was already only
# being honored for one side. See _known_enemy_positions's own doc
# comment for the fix built on top of this.
var enemy_has_been_sighted: bool = false
var enemy_known_pips: int = 0
var enemy_known_state: State = State.ACTIVE
var enemy_known_position: Vector2 = Vector2.INF
var enemy_known_position_time: float = -INF
## The enemy's own mirror of player_known_gun_abandoned above — added once
## BattleManager._mortar_existence_confidence became team-parameterized (direct user instruction: "This
## should apply to both sides", re a spotted mortar's willingness to fire). Same "actually witnessed, not
## just ground truth" bar.
var enemy_known_gun_abandoned: bool = false

var fire_interval: float = 2.0 # seconds between fire attempts
var fire_timer: float = 0.0

# Mortar-only doctrine fields (unused by SQUAD kind).
var shoot_and_scoot: bool = false
# Tactical seconds (see BattleManager.scenario_elapsed_time) — a realistic
# lay-load-fire cycle for a deliberate, spotter-corrected shot, not a raw
# mechanical rate of fire. There's no separate "relocate cooldown" on top of
# this: a shoot-and-scoot mortar's actual walk to its next position is what
# keeps it from firing again (see BattleManager._tick_fire's has_move_target
# check) — real travel time IS the cooldown, not an additional number.
var reload_time: float = 30.0

# Set whenever a counter-battery strike actually lands near this mortar
# (hit or a close miss — either way, shells landed close enough to notice)
# and consumed the next time it relocates: that relocation goes farther and
# faster than a routine one, reflecting a crew that knows it's been found
# and needs real distance, not just its usual displacement. See
# BattleManager._resolve_pending_counter_battery / _relocate_mortar.
var evading_counter_battery: bool = false

# A DRONE_TEAM's own equivalent of the flag above, DELIBERATELY not sharing its name: direct user
# correction — "Fire at the drone team is not counter battery fire." Counter-battery is a specific
# doctrine (a return shot drawn by THIS unit's OWN firing giving its position away); a drone team never
# fires anything at all, so nothing it takes can be "countering" anything. This just marks "a shell
# landed near this crew and it survived," the same trigger _apply_crew_casualties' shared MORTAR/
# DRONE_TEAM branch below already treats as a reason to hold and relocate rather than fully withdraw —
# consumed the next time BattleManager._update_drone_team_evasion actually issues that move.
var taking_fire: bool = false

# General-purpose movement target + queue, used for: an enemy squad's
# initial road march (a real multi-waypoint path — see set_path), either
# side's squad bolting for cover, and a retreat's first leg to cover.
# RETREATING's final leg to safety uses its own retreat_speed/
# retreat_target_x instead (see below).
var move_target: Vector2 = Vector2.ZERO
var has_move_target: bool = false
# Captured where an order is issued; used only by the decision inspector.
var last_order_reason: String = ""
var move_queue: Array[Vector2] = []
var move_speed: float = 40.0
const MOVE_ARRIVE_RADIUS: float = 5.0 * GameConfig.PIXELS_PER_METER # "close enough" to a move target

# RESUPPLY_RUN only: the mortar this run is carrying rounds to. Its
# move_target is refreshed to this mortar's CURRENT position every tick
# (see BattleManager._update_resupply_run_targets) rather than a fixed
# destination set once — this is what lets the mortar itself close some of
# the distance too (a real linkup, see BattleManager's resupply-linkup
# idle behavior) with no extra coordination code on either side.
var resupply_target_mortar: Unit = null

# RESUPPLY_RUN only: has this run already handed off its rounds? False for
# the whole outbound leg; flipped true the instant it delivers (see
# BattleManager._resolve_resupply_run_arrivals), which is also the moment
# its move_target switches from "chase the mortar" to a fixed point back
# at its own side's map edge (BattleManager._resupply_entry_point_for) —
# a resupply truck doesn't blink out of existence the second the crate
# hits the ground, it drives back out the way it came, and only actually
# leaves the battle once it reaches that edge.
var resupply_delivered: bool = false

# True only for the enemy's initial road march — a steady, known path a
# mortar crew can lead-aim against. Anything reactive (diving for cover,
# retreating) is unpredictable and gets marked false the moment it starts —
# see seek_cover() and order_retreat(). Irrelevant while STATIONARY.
var movement_predictable: bool = false

# ENEMY SQUAD only: true once it has broken from the road march toward
# cover after first contact — a one-time reaction, not re-rolled every hit.
# BattleManager polls sought_cover_logged to log the moment exactly once.
var sought_cover: bool = false
var sought_cover_logged: bool = false

# ENEMY SQUAD only: true once it has closed on the village (the objective it advances on when it has
# no fix on the friendly mortar) — from then on its objective is to push west after the defenders
# rather than to sit at the village. One-way, like flanking_route_active flipping false. See
# BattleManager._enemy_advance_objective.
var village_reached: bool = false

# ENEMY SQUAD only: rolled once at spawn (see GameConfig.ENEMY_FLANK_CHANCE)
# — a real assault doesn't send every element on the same axis. Only takes
# effect once the squad breaks from its scripted road march (see
# BattleManager._enemy_advance_objective); flips permanently false once the
# squad arrives near its flank waypoint, so it falls through to the normal
# mortar/village objective from then on, now approaching from the west
# instead of head-on. flank_waypoint_y is fixed at spawn (the squad's own
# road-march y offset) rather than read live, so the route stays a stable
# point to aim at instead of drifting with the squad's own maneuvering.
var flanking_route_active: bool = false
var flank_waypoint_y: float = 0.0

# Set (not cleared) whenever seek_cover() is called for a reason OTHER than
# the one-time road-march break above — i.e. a mortar-fire bolt-for-cover.
# BattleManager polls + clears this to log each occurrence once.
var bolted_for_cover: bool = false

# MORTAR only — set true by _roll_mortar_ammo_cookoff whenever a hit sets
# off this mortar's own stored rounds. Same one-shot poll-and-clear pattern
# as bolted_for_cover above; see BattleManager._log_hit_consequence.
var ammo_cooked_off: bool = false

var retreat_speed: float = 0.0
var retreat_target_x: float = 0.0 # x that means "reached safety" while retreating

# SQUAD only — every pip actually lost (see take_hit) is sorted into exactly
# one of these three (GameConfig.CASUALTY_*_FRACTION) instead of just
# vanishing from `pips` as an undifferentiated loss. KILLED needs nothing
# further. HEAVILY_WOUNDED is alive but immobile — still physically with the
# unit, and the whole reason order_retreat now has a real decision to make
# (see _resolve_wounded_evacuation): bring them (real retreat-speed cost) or
# leave them. WALKING_WOUNDED can move under their own power — no retreat
# cost either way, they just don't shoot as well, which is why some of them
# no longer count toward `pips` even though they were never in danger of
# being left behind.
var killed_count: int = 0
var heavily_wounded_count: int = 0
var walking_wounded_count: int = 0

# Tallies HEAVILY_WOUNDED casualties this unit chose to leave behind rather
# than carry (see _resolve_wounded_evacuation) — reported in the AAR as
# captured/surrendered, not counted among the unit's own ongoing casualties
# any more. Never happens for the player side (see _resolve_wounded_evacuation's
# own doc comment for why this is enemy-only).
var wounded_left_behind_count: int = 0

# One-shot flags, set the instant a retreat's wounded-evacuation decision is
# made and consumed+cleared by BattleManager's own logging pass — same
# established pattern as bolted_for_cover/sought_cover_logged above.
var just_carried_wounded: bool = false
var just_abandoned_wounded: bool = false

# Set once a RETREATING unit has actually had a mortar round resolve against
# it — hit or a near-miss close enough to still be evaded (see
# BattleManager._resolve_pending_mortar_shots) — and never cleared — once you
# know you're under a barrage, you keep juking sideways
# for the rest of the withdrawal, not just for one lucky dodge. Only affects
# the final retreat leg's constant-heading dash (see
# BattleManager._step_retreat) — exactly the leg a mortar can otherwise lead
# cleanly (see _mortar_aim_point), so this is the direct, real countermeasure
# to being led, not just flavor.
var zigzagging: bool = false
var _zigzag_timer: float = 0.0 # tactical seconds until the next direction change
var _zigzag_lateral_velocity: float = 0.0 # current sideways speed (+ or -), re-rolled periodically

# ENEMY SQUAD only: set once, before the real retreat threshold, as a
# lower-severity "this is getting bad" signal. BattleManager polls
# reported_issue_logged to log it exactly once — not acted on mechanically.
var reported_issue: bool = false
var reported_issue_logged: bool = false
var concern_threshold: float = 0.25

# DRONE only: this specific sortie's CURRENTLY INSTALLED battery's charge
# level, 0.0 (empty) to 1.0 (full) — the one thing actually tracked; how
# much flight time or range that implies is a consequence of this, worked
# out on demand (see BattleManager._update_active_drone), not separately
# stored. Set at launch from whatever the ground crew actually had on hand
# (see BattleManager._pop_best_battery) — not always 1.0; the team keeps
# spares, but "always fly on a full battery" isn't guaranteed the way it
# would be if this were still just a flight-time countdown.
var drone_battery_charge: float = 1.0
## Whether the drone team that flies this DRONE is itself on the move (set every tick by
## BattleManager._update_drone_operations): the drone is then operated with degraded
## performance — see GameConfig.DRONE_TEAM_MOVING_*.
var drone_operator_moving: bool = false
var drone_operator_casualties: int = 0 # how many of its team are down: a slightly weaker feed (see GameConfig.DRONE_TEAM_CASUALTY_*)

# MORTAR only: a small crew-served weapon, GameConfig.mortar_crew_size(team)
# people including ammunition carriers — see that function's own doc comment
# for the real, per-side citations (the two sides field genuinely different
# 82mm tubes, not the same crew requirement with a rounding difference).
# Tracked as an exact headcount, not a percent — see _apply_crew_casualties().
# A hit is decisive either way: it either wipes the whole crew (DESTROYED) or
# leaves survivors who abandon the gun on the spot and retreat (see
# order_retreat()) — nobody keeps manning a mortar after taking a hit near
# it. max_pips is set to crew_size (see setup()) so these casualties feed
# into the side's overall pips_total/pips_lost tally (BattleManager.
# _compute_side_stats) exactly like a squad's — the mortar and its crew are
# worth just as much to lose, or to kill, as anyone else.
var crew_size: int = 0
var crew_casualties: int = 0

# MORTAR only: set the moment this crew starts retreating (see
# order_retreat()) — whether the tube itself came out with them or got left
# behind. A crew that's already taken a hit always leaves it (same as
# before this field existed); an untouched crew ordered to retreat
# typically brings it and can still fire on the way out, only leaving it
# behind under genuinely severe danger — see order_retreat's own reasoning.
# Meaningless (stays false) until RETREATING; _tick_fire is what actually
# reads it.
var mortar_gun_abandoned: bool = false

# MORTAR only: real, finite ammunition — see GameConfig.MORTAR_STARTING_AMMO
# and BattleManager's whole request/arrival/pickup resupply pipeline. Never
# reloads on its own; only a completed resupply run (Unit.setup() sets the
# starting count, BattleManager._update_mortar_resupply/_update_mortar_
# resupply_fetch add to it later) changes this.
var mortar_rounds_remaining: int = 0

# SQUAD only: a real 9-person infantry squad, for both sides. Unlike the
# mortar/drone team's crew_size/crew_casualties model (a hit is decisive, killing
# a random handful of a small crew at once), a squad takes casualties one
# soldier at a time per hit (see take_hit's generic `pips = max(pips-1, 0)`)
# — pips already WAS a literal headcount in that sense, just scaled to a
# max of 4; this only changes the number to the real one.
const SQUAD_SIZE: int = 9

signal took_hit(unit)
signal state_changed(unit)


func setup(p_team: Team, p_kind: Kind, p_position: Vector2) -> void:
	team = p_team
	kind = p_kind
	position = p_position
	if kind == Kind.DRONE:
		z_index = DRONE_Z_INDEX # always drawn over every ground unit, never under one
	match kind:
		Kind.MORTAR:
			crew_size = GameConfig.mortar_crew_size(p_team)
			crew_casualties = 0
			max_pips = crew_size # crew casualties count the same as squad pips — see _apply_crew_casualties
			base_hit_chance = 0.40
			unit_label = "Mortar"
			fire_interval = reload_time
			mortar_rounds_remaining = GameConfig.MORTAR_STARTING_AMMO
		Kind.SPOTTER:
			max_pips = 1 # a small, fragile recon team
			base_hit_chance = 0.0 # never fires — see BattleManager._tick_fire
			unit_label = "Spotter"
			fire_interval = 0.0
		Kind.DRONE_TEAM:
			crew_size = GameConfig.DRONE_TEAM_CREW_SIZE
			crew_casualties = 0
			max_pips = crew_size # same crew-casualty accounting as the mortar — see _apply_crew_casualties
			base_hit_chance = 0.0 # never fires — see BattleManager._tick_fire
			unit_label = "Drone Team"
			fire_interval = 0.0
		Kind.DRONE:
			max_pips = 1 # unmanned — one hit shoots it down outright, no crew to lose
			base_hit_chance = 0.0 # never fires — pure reconnaissance, see BattleManager._tick_fire
			unit_label = "Drone"
			fire_interval = 0.0
		Kind.RESUPPLY_RUN:
			# A small, unarmed logistics detail carrying live ammunition across
			# open ground — max_pips=1 means the existing generic take_hit path
			# (below the match) destroys it outright on any hit, same as DRONE,
			# with no special-case branch needed: a single hit on an unarmored
			# vehicle/party carrying mortar rounds is a real loss, not a
			# graduated wound.
			max_pips = 1
			base_hit_chance = 0.0 # never fires — see BattleManager._tick_fire
			unit_label = "Resupply Run"
			fire_interval = 0.0
		_:
			max_pips = SQUAD_SIZE
			# Defenders fight from prepared, pre-ranged positions — their first
			# shots land far more often than an attacker's do.
			base_hit_chance = (0.32 if team == Team.PLAYER else 0.20) * GameConfig.SMALL_ARMS_BASE_EFFECTIVENESS
			unit_label = "Squad"
			fire_interval = 2.0
			rounds_limited = true
			rounds_capacity = SQUAD_SIZE * GameConfig.SQUAD_ROUNDS_PER_PERSON
			rounds = rounds_capacity
			grenades = SQUAD_SIZE * GameConfig.GRENADES_PER_PERSON
	pips = max_pips
	queue_redraw()


## `from_mortar` — did this hit come from a mortar shell rather than direct
## fire? Mortar fire can rattle a squad into relocating even without heavy
## casualties (see RELOCATE_ON_MORTAR_HIT_CHANCE below).
##
## `ally_positions` — other same-team units' current positions, passed
## straight through to seek_cover() so a squad breaking for cover here
## picks a different patch than one an ally is already using.
##
## `known_enemy_positions` — currently-visible enemy positions, from THIS
## unit's own side's point of view. Passed straight through to whatever
## retreat this hit might trigger (_check_retreat / _apply_crew_casualties
## -> order_retreat) so an automatic, threshold-triggered retreat is just as
## enemy-aware as the player's own general-retreat command already is — a
## retreat picked with no idea where the enemy is could otherwise head
## straight for cover the enemy happens to be occupying, or even walk
## toward a known enemy position outright.
##
## `impact_distance` — how far the round's real, physically-dispersed
## impact point landed from THIS unit's own position (0.0 for direct fire,
## which always resolves exactly at the target — see BattleManager.
## _resolve_fire_and_check_bunching's own doc comment). Only meaningful for
## a MORTAR/DRONE_TEAM crew's own casualty roll (_apply_crew_casualties) —
## everyone else's casualty count still comes from GameConfig.
## mortar_casualty_count(pips)/a flat 1, unrelated to how far a round
## actually landed from any one specific person in a multi-person squad.
func take_hit(from_mortar: bool = false, ally_positions: Array[Vector2] = [], known_enemy_positions: Array[Vector2] = [], impact_distance: float = 0.0, blast_casualties: int = -1) -> void:
	if state == State.DESTROYED:
		return
	took_hit.emit(self)
	queue_redraw()

	if kind == Kind.MORTAR or kind == Kind.DRONE_TEAM:
		_apply_crew_casualties(known_enemy_positions, ally_positions, from_mortar, impact_distance, blast_casualties)
		return

	# A rifle round is aimed at one person; a mortar round's fragmentation
	# covers an area — the more people currently in that area, the more it
	# actually costs, not a flat one-for-one regardless of how full the
	# unit still is. Direct fire stays a flat single casualty; only
	# from_mortar scales with the unit's own current strength (see
	# GameConfig.MORTAR_CASUALTY_FRACTION) — a full 9-person squad is a
	# genuinely costlier hit to take than a squad already worn down to a
	# handful, which is exactly why it's also a more attractive TARGET in
	# the first place (see BattleManager._enemy_target_value).
	var casualties: int = GameConfig.mortar_casualty_count(pips) if from_mortar else 1
	if blast_casualties >= 0:
		casualties = mini(blast_casualties, pips) # a round's own count, person by person (BattleManager._apply_shell_blast)
	# SPOTTER (one-hit-fragile, max_pips == 1) gets the same categorization
	# roll as a SQUAD's casualties — no reason a spotter's single casualty
	# should be unconditionally "killed" any more than a mortar crew's are
	# (see _apply_crew_casualties). Also keeps the side-wide breakdown
	# exactly reconciling with pips actually lost for every kind.
	_categorize_casualties(casualties)
	pips = max(pips - casualties, 0)
	if pips <= 0:
		state = State.DESTROYED
		state_changed.emit(self)
		return

	# Only squads can be worn down and pull back, break from an advance
	# toward cover, or bolt under mortar fire (the spotter is one-hit-fragile
	# and never reaches this point; see the pips <= 0 check above).
	if kind != Kind.SQUAD:
		return

	_check_retreat(known_enemy_positions, ally_positions)
	if state != State.ACTIVE:
		return

	if team == Team.ENEMY and not sought_cover:
		sought_cover = true
		if not in_fighting_position():
			seek_cover(ally_positions, known_enemy_positions)
	elif from_mortar and not in_fighting_position() and randf() < GameConfig.RELOCATE_ON_MORTAR_HIT_CHANCE:
		seek_cover(ally_positions, known_enemy_positions)
		bolted_for_cover = true


## Sorts `count` newly-lost pips into killed/heavily-wounded/walking-wounded
## (see the fields' own doc comments) via GameConfig's CASUALTY_*_FRACTION
## weights — one independent roll per person lost, not a single roll for the
## whole hit, so a multi-casualty mortar hit (see GameConfig.
## mortar_casualty_count) naturally produces a believable mix rather than
## every person from the same hit landing in the same bucket.
func _categorize_casualties(count: int) -> void:
	for i in count:
		var roll := randf()
		if roll < GameConfig.CASUALTY_KILLED_FRACTION:
			killed_count += 1
		elif roll < GameConfig.CASUALTY_KILLED_FRACTION + GameConfig.CASUALTY_HEAVILY_WOUNDED_FRACTION:
			heavily_wounded_count += 1
		else:
			walking_wounded_count += 1


func _check_retreat(known_enemy_positions: Array[Vector2] = [], ally_positions: Array[Vector2] = []) -> void:
	if state != State.ACTIVE:
		return
	var fraction_lost: float = float(max_pips - pips) / float(max_pips)
	if fraction_lost >= retreat_threshold:
		order_retreat(known_enemy_positions, ally_positions)
		last_order_reason = "Casualties reached the standing withdrawal threshold."
	elif not reported_issue and fraction_lost >= concern_threshold:
		reported_issue = true


## A mortar crew (or a drone team's ground crew) doesn't shrug off a hit and
## keep working the way a rifle squad absorbs casualties — a round landing
## on/near a small crew is decisive: however many of them go down in this
## one hit (`crew_casualties`, an honest headcount, not a vague percent) are
## OUT OF ACTION for the rest of the battle either way, unlike a squad's
## gradual attrition. Only a hit that accounts for the whole crew actually
## destroys the unit outright.
##
## A surviving MORTAR crew doesn't automatically abandon the gun, though —
## see GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE for the real doctrine and
## reasoning behind this: real crew-served-weapon doctrine favors keeping a
## reduced crew firing over abandoning it outright, and whether that's
## actually viable depends on how much crew is left AND whether the crew
## itself is in real danger of being overrun, not casualties alone. A
## drone-team crew has no equivalent "someone else takes over the gun"
## option (there's no weapon to cross-level, just the ground-control link)
## so it keeps the older unconditional-retreat behavior.
##
## "Out of action" is not the same claim as "dead," though — a crew hit is
## exactly as capable of producing killed vs. wounded survivors as a squad's
## is, so each of these newly-down crew members gets the same _categorize_
## casualties roll a squad's casualties do, instead of every one of them
## being unconditionally tallied as killed_count. This is also what keeps
## _compute_side_stats's killed/heavily_wounded/walking_wounded/
## wounded_left_behind breakdown always summing to the side's actual total
## personnel lost, mortars and drone-team crews included, not just squads.
func _apply_crew_casualties(known_enemy_positions: Array[Vector2] = [], ally_positions: Array[Vector2] = [], from_mortar: bool = true, impact_distance: float = 0.0, blast_casualties: int = -1) -> void:
	var remaining: int = crew_size - crew_casualties
	# Direct/small-arms fire is a single aimed shot at one person, not a
	# blast covering an area — it stays a flat single casualty, exactly
	# like a squad's own from_mortar distinction (see take_hit above).
	# Only a real HE hit rolls the distance-and-cover-aware model below.
	var newly_down: int = _roll_crew_casualties(remaining, impact_distance, exposure_terrain(), posture_factor(), cover_kept(), fighting_position_ratio()) if from_mortar else min(1, remaining)
	if blast_casualties >= 0:
		newly_down = mini(blast_casualties, remaining) # already worked out by the caller, person by person
	crew_casualties += newly_down
	_categorize_casualties(newly_down)
	pips = crew_size - crew_casualties # feeds the side's overall casualty tally exactly like a squad's pips — see setup()
	if crew_casualties >= crew_size:
		state = State.DESTROYED
		state_changed.emit(self)
		return

	var cooked_off := false
	if kind == Kind.MORTAR:
		cooked_off = _roll_mortar_ammo_cookoff()
		pips = crew_size - crew_casualties # a cook-off can add its own casualties on top — keep this in sync
		if crew_casualties >= crew_size:
			state = State.DESTROYED
			state_changed.emit(self)
			return

	if state != State.ACTIVE:
		return
	if (kind == Kind.MORTAR or kind == Kind.DRONE_TEAM) and not cooked_off and _mortar_crew_holds_position(known_enemy_positions):
		# Stays in the fight, wounded but still crewed — a real reason to
		# relocate (shoot-and-scoot after the next shot, the out-of-ammo
		# safety check, or simply being spotted while idle) still applies
		# exactly as it would to an untouched crew; this only means it
		# doesn't pull out of the battle over this hit alone. Marked as if
		# it had just weathered counter-battery fire either way — whatever
		# actually hit it, a crew that chose to stick it out after taking
		# casualties is especially eager not to get caught again.
		#
		# Kind-specific flag, deliberately: a MORTAR genuinely IS evading
		# counter-battery (return fire drawn by its own shot); a DRONE_TEAM
		# never fires anything, so what just hit it can't be "countering"
		# anything — see taking_fire's own doc comment for the distinction.
		if kind == Kind.MORTAR:
			evading_counter_battery = true
		else:
			taking_fire = true
		return
	order_retreat(known_enemy_positions, ally_positions)


## Rolls whether this hit sets off the mortar's own stored rounds in a
## secondary explosion — see GameConfig.MORTAR_AMMO_COOKOFF_MAX_CHANCE for
## the reasoning and the (judgment-call, not cited) probability. A cook-off
## destroys whatever rounds were left (there's no stockpile left to protect
## or carry away) and can knock down more of the surviving crew on top of
## the original hit — a violent secondary blast right at the position is a
## real danger to whoever's still standing there, not just a fireworks
## show. Sets `ammo_cooked_off` (a one-shot flag, same pattern as
## `bolted_for_cover`) for BattleManager to narrate and clear; `nothing to
## cook off` (already dry) always returns false outright.
func _roll_mortar_ammo_cookoff() -> bool:
	if mortar_rounds_remaining <= 0:
		return false
	var chance: float = GameConfig.MORTAR_AMMO_COOKOFF_MAX_CHANCE * clamp(float(mortar_rounds_remaining) / float(GameConfig.MORTAR_STARTING_AMMO), 0.0, 1.0)
	if randf() >= chance:
		return false
	mortar_rounds_remaining = 0
	var remaining: int = crew_size - crew_casualties
	if remaining > 0:
		# The secondary explosion goes off right where the crew already is —
		# a real distance of 0, not the original round's own impact point.
		var newly_down: int = _roll_crew_casualties(remaining, 0.0, exposure_terrain(), posture_factor(), cover_kept(), fighting_position_ratio())
		crew_casualties += newly_down
		_categorize_casualties(newly_down)
	ammo_cooked_off = true
	return true


## Shared by both _apply_crew_casualties (the original hit, a real impact_distance
## from the round's own dispersion) and _roll_mortar_ammo_cookoff (a
## secondary blast right at the crew's own position, impact_distance 0.0),
## since both are asking the identical question: given a real HE blast at
## this distance with this terrain's cover, how many of the remaining crew
## does it actually catch.
##
## Two earlier versions of this were tried and replaced, both caught by
## this function's own regression test before shipping: a flat uniform
## `randi_range(1, remaining)` (lose-one and lose-everyone equally likely);
## then a geometric-decay chain with a guaranteed first casualty (ignored
## how far the round actually landed from the crew entirely). This version
## is the user's own proposed replacement: each remaining crew member is
## an independent Bernoulli draw against the same distance-and-cover-aware
## fragmentation curve every other blast casualty in this game already
## uses, so a crew can get lucky and take nothing from a near miss, or
## unlucky and lose more than one from a hit that scattered wide.
func _roll_crew_casualties(remaining: int, impact_distance: float, terrain: GameConfig.TerrainType, lying_factor: float = 1.0, kept: float = 1.0, dug_ratio: float = 1.0) -> int:
	return CombatResolver.binomial(remaining, clampf(CombatResolver.blast_casualty_chance(impact_distance, 1.0, terrain, kept, dug_ratio) * lying_factor, 0.0, 1.0))


## Whether a wounded crew (crew_size - crew_casualties survivors) keeps its post in the fight rather than
## abandoning it — see GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE for the doctrine this models. Named for
## its original MORTAR-only use, but also called for a DRONE_TEAM now (see take_hit's own shared
## MORTAR/DRONE_TEAM branch, and _apply_crew_casualties' call site below) — a ground station crew facing a
## near-miss with nobody actually hurt and nothing closing to overrun it has exactly the same reason to
## stay put and reposition as an untouched mortar crew does, not to abandon the whole mission over a shell
## that landed clear. Direct user report: "The drone team came under mortar fire. Now it is withdrawing.
## But given that it took no casualties, I don't understand why it is withdrawing. Relocating would be
## reasonable" — traced to _apply_crew_casualties unconditionally retreating any DRONE_TEAM that reached
## its own final branch, with no equivalent to this roll at all, regardless of whether the hit that
## triggered it actually cost it anyone.
##
## A genuine risk-weighted roll, not a hard cutoff, matching this game's standing "real decisions aren't
## perfectly rational" idiom: `remaining_fraction * (1.0 - overrun_risk)`. A full-strength crew with
## nothing threatening it up close holds essentially every time; the same crew with an enemy closing to
## overrun range flees almost regardless of how many hands are still on post — self-preservation from
## being physically overrun beats the tactical value of staying. With nothing known nearby at all,
## overrun_risk is 0 and the decision rests purely on how much crew is actually left.
func _mortar_crew_holds_position(known_enemy_positions: Array[Vector2]) -> bool:
	var remaining_fraction: float = float(crew_size - crew_casualties) / float(crew_size)
	# Direct user instruction: "One casualty should not cause the drone team to withdraw." A drone team's crew is three, so one
	# casualty used to leave a one-in-three chance of withdrawing on that alone (hold chance two-thirds with nothing near). The
	# first casualty no longer counts against holding; an enemy closing to overrun range still does (that is danger, not the hit).
	if kind == Kind.DRONE_TEAM and crew_casualties <= 1:
		remaining_fraction = 1.0
	var nearest_threat_dist := INF
	for p in known_enemy_positions:
		nearest_threat_dist = min(nearest_threat_dist, global_position.distance_to(p))
	var overrun_risk: float = clamp(1.0 - nearest_threat_dist / GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE, 0.0, 1.0)
	var hold_chance: float = remaining_fraction * (1.0 - overrun_risk)
	return randf() < hold_chance


## Force this unit into a retreat regardless of its threshold — used both by
## the automatic threshold check above and by the player's general retreat
## order (see BattleManager.order_general_retreat).
##
## Takes a safe-ish path rather than a beeline: if not already in cover, the
## first leg heads for cover (BattleManager._tick_movement runs this leg via
## the normal move_target system); once there — or immediately, if already
## in cover — the final leg is the straight pull to the safe line
## (BattleManager._step_retreat). A unit tucked behind a building this way
## can also break direct-fire LOS entirely (see GameConfig.has_direct_los).
##
## `known_enemy_positions` (currently visible enemy units, passed in by
## BattleManager — Unit itself has no view of the wider battle) keeps EVERY
## kind's cover leg from heading toward, or landing right next to, a known
## threat — GameConfig.nearest_cover_point hard-excludes any candidate zone
## within its DANGER_RADIUS of one, falling back to the unrestricted set
## only if that would leave nowhere to go. The SPOTTER gets an extra step
## on top of that floor: among whatever's left, safest_cover_point picks
## whichever is farthest from the nearest known threat, not just the
## closest one — it has training and situational awareness a rifle squad
## diving on instinct doesn't.
##
## Either way, the cover leg is ALSO direction-aware: it never detours
## toward the front just because that happens to be the closest patch of
## cover — see GameConfig's retreat_dir parameter. Without that, a mortar
## set up well to the rear (now allowed — see design doc) could "retreat"
## forward first if the nearest cover happened to be back toward the
## village. The two filters together are what rule out a retreat ever
## walking a unit toward, or right past, an enemy it already knows about.
##
## A MORTAR's abandoned crew never heads for a BUILDING specifically — a
## mortar can't be fired from or set up inside one (no overhead clearance
## for the round), so it never enters one in the first place; TREES remain
## fair game for its fleeing crew, same as anyone else.
##
## A DRONE never retreats through here at all — it has no "safe line" to
## walk to; its whole lifecycle (search, return-to-base, being freed) is
## driven directly by BattleManager's drone-fleet logic instead (see
## BattleManager._update_drone_operations).
##
## `avoid_positions` — other same-team units already at, or already headed
## to, a patch of cover — steers this unit's own cover leg away from
## piling into the exact same spot, same as Unit.seek_cover's own
## avoid_positions. Matters most when several units retreat in the SAME
## instant (a general retreat order processes every active unit on a side
## in one pass) — without a caller threading positions/targets through
## here as each one is ordered, every one of them independently computes
## "nearest cover point" from a similar starting position and reliably
## picks the same one, which is exactly what real retreating soldiers
## would NOT do (and exactly what already-visible-elsewhere bunching
## consequences, like BattleManager's spillover-fire mechanic, are named
## for). A single, individually-triggered retreat (one squad's own
## threshold, one mortar crew abandoning its gun) still passes this
## through — see take_hit — since even then there's no reason not to
## avoid an ally's already-current position.
## `reason` is what the debug snapshots show as this unit's last order reason: every
## route into a retreat (a general retreat, a mortar left without squads, a crew
## fleeing as a last resort ...) used to leave the same "Withdrawal ordered.", so
## after the fact there was no telling WHY a unit had pulled out (live report: a
## mortar retreating off the map with a full crew and ammunition, unexplained).
func order_retreat(known_enemy_positions: Array[Vector2] = [], avoid_positions: Array[Vector2] = [], reason: String = "Withdrawal ordered.") -> void:
	if kind == Kind.DRONE:
		return
	if state != State.ACTIVE:
		return
	state = State.RETREATING
	last_order_reason = reason
	movement_predictable = false # pulling out under pressure, not a calm march

	if kind == Kind.MORTAR:
		# A crew that's already taken a hit has already made its own call to
		# flee instead of holding (see _apply_crew_casualties/
		# _mortar_crew_holds_position) — that decision always leaves the gun,
		# same as before this ever branched. An untouched crew being ordered
		# to retreat (a general retreat order, having never taken a hit this
		# battle) hasn't made any such call yet — that's decided fresh here.
		mortar_gun_abandoned = true if crew_casualties > 0 else _mortar_gun_abandoned_on_unhit_retreat(known_enemy_positions)

	var speed_multiplier := 1.0
	if kind == Kind.SQUAD and heavily_wounded_count > 0:
		speed_multiplier = _resolve_wounded_evacuation(known_enemy_positions)
		retreat_speed *= speed_multiplier # permanent for the rest of this (one-way) retreat

	# A real, live-observed failure found alongside the cover-detour one
	# below: a rear-echelon unit (a DRONE_TEAM home base, most often) can
	# already be sitting AT OR PAST its own retreat_target_x — the exact
	# line _step_retreat's own "reached" check uses to mark WITHDRAWN — at
	# the moment a general retreat is ordered, simply because that's where
	# it was already operating from. Every retreat used to unconditionally
	# route through a cover leg first regardless, meaning an already-safe
	# unit could still get sent on a real, sometimes backward, detour to
	# some cover point before ever getting a chance to just recognize "I'm
	# already home" — confirmed directly: a drone team already past its
	# own safe line was routed BACKWARD, toward the enemy, to reach cover
	# distant units were also converging on, before finally reaching
	# safety anyway. Checked before anything else below: no reason to
	# consider cover, known threats, or anything else once the unit is
	# already at its destination.
	var already_safe: bool = (global_position.x <= retreat_target_x) if team == Team.PLAYER else (global_position.x >= retreat_target_x)
	if already_safe:
		has_move_target = false
		state_changed.emit(self)
		return

	# Direct user correction, refined twice over several real incidents:
	# "The primary consideration in retreating is safety. Cover may be a
	# way to achieve safety... People could have just retreated backwards
	# safely" — then, after a mortar was destroyed taking a long detour to
	# reach cover anyway: "The primary consideration should be safety, not
	# cover... We want a safe path. Cover is one way to achieve that. But
	# avoiding the enemy could often be better... I'm concerned that you
	# may be over-emphasizing cover at a basic level."
	#
	# An EARLIER version of this gated cover-seeking on raw distance to
	# the nearest known enemy — closer than this project's own existing
	# "worth reacting to at all" range (the same one _retreat_avoidance_
	# offset uses for its own continuous bending). That was still cover-
	# centric in the wrong way: a known position merely being "in range"
	# doesn't mean this unit is in any active danger from it RIGHT NOW —
	# only that it's known to exist somewhere within a fairly generous
	# radius, quite possibly no longer even watching this unit at all
	# (see the design doc's own live-incident entries on stale player_
	# known_position data). Real cover/concealment earns its real cost
	# (a detour, time exposed getting there) specifically by breaking
	# LINE OF SIGHT to something that can actually see or reach this unit
	# — not merely by existing somewhere nearby. Two real conditions,
	# either one enough:
	#   1. This unit is CURRENTLY visible (is_visible) — actively being
	#      watched/engaged right now, the clearest possible case for real
	#      concealment.
	#   2. A known enemy sits within actual direct-fire/overrun range
	#      (SQUAD_ENGAGEMENT_RANGE — real combat range, not the far more
	#      generous "worth bending away from" SQUAD_DANGER_RANGE; MORTAR_
	#      CREW_OVERRUN_DANGER_RANGE for a mortar crew, same range
	#      _unwatched_threat_closing already uses for this exact
	#      reasoning) AND has actual direct LOS to this unit's position —
	#      close enough and unobstructed enough to plausibly engage even
	#      without a formal "spotted" roll landing yet.
	# Otherwise, the straight retreat itself is already the safe path:
	# _step_retreat's own continuous per-tick bending away from whatever
	# IS known already produces the user's own "slant slightly south" for
	# whichever units actually have something nearby, without committing
	# to a single fixed detour chosen once and then walked blindly
	# regardless of how the situation changes afterward.
	var needs_real_cover: bool = is_visible
	if not needs_real_cover:
		var close_range: float = GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE if kind == Kind.MORTAR else GameConfig.SQUAD_ENGAGEMENT_RANGE
		for p in known_enemy_positions:
			if global_position.distance_to(p) <= close_range and GameConfig.has_direct_los(p, global_position):
				needs_real_cover = true
				break

	if needs_real_cover and not in_cover():
		var retreat_dir: float = -1.0 if team == Team.PLAYER else 1.0
		var avoid_buildings: bool = kind == Kind.MORTAR
		if kind == Kind.MORTAR and not known_enemy_positions.is_empty():
			# A real, previously-reported failure mode: nearest_cover_point's
			# own retreat_dir filter only ever constrains which side of the
			# map is acceptable (X-axis), leaving how far north or south the
			# pick lands completely unconstrained — a mortar's own retreat
			# could drift far off to one side for no better reason than
			# "nearest still-safe zone happened to be there." Heading
			# generally along the resupply corridor (the same entry line a
			# resupply run would already be approaching on — see
			# BattleManager._resupply_entry_point_for's own identical
			# formula) is a genuinely better direction than an arbitrary
			# tangent: real ground worth walking toward, not just away from
			# danger.
			var edge_x: float = -GameConfig.WEST_FLANK_WIDTH_PX if team == Team.PLAYER else GameConfig.MAP_WIDTH_PX
			var resupply_reference := Vector2(edge_x, global_position.y)
			move_target = GameConfig.retreat_cover_point_toward(global_position, resupply_reference, known_enemy_positions, retreat_dir, avoid_buildings)
		elif (kind == Kind.SPOTTER or kind == Kind.DRONE_TEAM) and not known_enemy_positions.is_empty():
			# Direct user report: "Spotter retreated off the top of the map last battle. That should not be
			# allowed. Has to go to the friendly map edge." Same "cover is a MEANS to reaching the edge, not
			# a competing goal" reference-point fix as the plain-squad branch just below (and
			# retreat_cover_point_toward's own, for the mortar) — safest_cover_point's own "nearest few,
			# then safest of those" cut had nothing at all bounding how far the DETOUR itself could run
			# north or south, only which side of the map it stayed on.
			var reference_point := Vector2(retreat_target_x, global_position.y)
			move_target = GameConfig.safest_cover_point(global_position, known_enemy_positions, retreat_dir, avoid_buildings, reference_point)
		else:
			# Same "cover is a MEANS to reaching the edge, not a competing
			# goal" principle as retreat_cover_point_toward's own doc
			# comment — this plain squad path had NO edge-awareness at
			# all before this: a real, previously-reported live failure,
			# several squads converging on the same distant cover zone
			# regardless of how far out of the way it actually was.
			# `retreat_target_x` is the exact same line already_safe/
			# _step_retreat's own "reached" check uses, so this stays
			# consistent with what "the edge" means everywhere else in
			# this function.
			var reference_point := Vector2(retreat_target_x, global_position.y)
			move_target = GameConfig.nearest_cover_point(global_position, retreat_dir, avoid_buildings, avoid_positions, known_enemy_positions, [], [], Vector2.ZERO, Vector2.INF, reference_point)
		# Direct, live-caught correction: none of the cover-point searches
		# above ever return "nothing" (same "movement must never be
		# starved to zero" principle as every other relocation search in
		# this project) — they always hand back SOME point, even one that
		# doesn't actually break LOS from what's already watching this
		# unit. Treating "a candidate exists" as "cover is worth seeking"
		# let a crew that had already spent real time failing to shake a
		# close, LOS-having threat get sent on ANOTHER detour to a spot
		# that doesn't actually help either — confirmed live: a mortar
		# already unable to find genuine concealment nearby, directly
		# engaged by an adjacent enemy squad, got routed to a nearby
		# "cover" point still fully visible to that same squad instead of
		# just running for the exit. If the chosen point doesn't actually
		# achieve real concealment from every currently-known threat, a
		# cover detour has nothing left to offer over the straight retreat
		# it would otherwise be competing with — skip it.
		var actually_hidden: bool = true
		for p in known_enemy_positions:
			if GameConfig.has_direct_los(p, move_target):
				actually_hidden = false
				break
		# Direct user report: "I hit 'retreat now.' The drone team could have easily gone offmap.
		# Instead it is going forwards and down." The cover searches above only PREFER cover on the
		# retreat side (GameConfig._prefer_retreat_direction), and when none qualifies they fall back
		# to the least-wrong zone: the west flank has almost no cover (4 of the map's 263 zones lie
		# west of x = -300 m), so a unit out there can be handed a zone back toward the enemy.
		# Cover is a means to reaching the edge, never a reason to walk away from it.
		if actually_hidden and retreat_detour_is_allowed(global_position, move_target, retreat_dir):
			has_move_target = true
			move_queue.clear()
			move_speed = GameConfig.REPOSITION_SPEED * speed_multiplier
		else:
			has_move_target = false
	else:
		has_move_target = false
	state_changed.emit(self)


## A retreat's cover detour is only taken if it does not lead back toward the enemy: `retreat_dir`
## is -1 for the player (west is away) and +1 for the enemy, as in order_retreat. A little backward
## travel is allowed (GameConfig.RETREAT_DETOUR_MAX_BACKWARD_M): a cover patch straight to one side
## has points a few tens of meters either way, and that is not "going back".
static func retreat_detour_is_allowed(from: Vector2, detour: Vector2, retreat_dir: float) -> bool:
	return (detour.x - from.x) * retreat_dir >= -GameConfig.RETREAT_DETOUR_MAX_BACKWARD_M * GameConfig.PIXELS_PER_METER


## Whether an untouched MORTAR crew (never hit this battle) ordered to
## retreat leaves the gun behind. Real crew-served-weapon doctrine — same
## source as _mortar_crew_holds_position — favors bringing a functional tube
## out rather than ditching it for no reason, so this is biased hard toward
## keeping it: risk scales with the same GameConfig.
## MORTAR_CREW_OVERRUN_DANGER_RANGE proximity _mortar_crew_holds_position
## uses, squared so a merely moderate threat still doesn't cost the gun —
## only something that's actually closed to real overrun range reliably
## does. A genuine roll, not a hard cutoff, matching this game's standing
## "real decisions aren't perfectly rational" idiom.
func _mortar_gun_abandoned_on_unhit_retreat(known_enemy_positions: Array[Vector2]) -> bool:
	var nearest_threat_dist := INF
	for p in known_enemy_positions:
		nearest_threat_dist = min(nearest_threat_dist, global_position.distance_to(p))
	var overrun_risk: float = clamp(1.0 - nearest_threat_dist / GameConfig.MORTAR_CREW_OVERRUN_DANGER_RANGE, 0.0, 1.0)
	var abandon_chance: float = overrun_risk * overrun_risk
	return randf() < abandon_chance


## The one real decision this feature adds: what happens to this SQUAD's own
## HEAVILY_WOUNDED (immobile — see the field's own doc comment) the moment it
## actually starts retreating. "We want to take the wounded with us if
## possible" is the default for BOTH sides — returns a retreat-speed
## multiplier (GameConfig.HEAVILY_WOUNDED_SLOWDOWN_PER_PERSON per person
## carried, floored at HEAVILY_WOUNDED_MIN_RETREAT_SPEED_FRACTION so a badly
## mauled squad doesn't grind to a near-halt) and sets just_carried_wounded
## for BattleManager to log once.
##
## The ENEMY side alone actually WEIGHS this instead of just accepting it —
## "may choose to leave their wounded behind, especially if taking them along
## entails more risk" is an enemy-commander-style judgment call, the same
## flavor as _squad_surrender_chance already being asymmetric between sides;
## the player's own doctrine has no such abandon option today. Risk is judged
## the simple way every other threat-aware routine here does: proximity to
## the nearest KNOWN enemy (here, player) position — closer means a slowed
## column is more likely to actually get caught by it, and more wounded to
## carry (a bigger speed penalty to accept) raises the odds of leaving them
## further still. A genuine roll, not a hard cutoff, matching this game's
## general "real decisions aren't perfectly rational" idiom (see
## _weighted_mortar_target_pick, _weighted_advance_point_pick). Abandoned
## wounded are moved to wounded_left_behind_count (see its own doc comment —
## reported in the AAR as captured, matching "left-behind enemy wounded would
## surrender") and the unit retreats at full, unencumbered speed instead.
func _resolve_wounded_evacuation(known_enemy_positions: Array[Vector2]) -> float:
	if team == Team.ENEMY:
		var nearest_known_dist := INF
		for p in known_enemy_positions:
			nearest_known_dist = min(nearest_known_dist, global_position.distance_to(p))
		if not is_inf(nearest_known_dist):
			var proximity_risk: float = clamp(1.0 - nearest_known_dist / GameConfig.WOUNDED_ABANDON_DANGER_RANGE, 0.0, 1.0)
			var abandon_chance: float = clamp(proximity_risk * GameConfig.WOUNDED_ABANDON_CHANCE_PER_PERSON * heavily_wounded_count, 0.0, GameConfig.WOUNDED_ABANDON_MAX_CHANCE)
			if randf() < abandon_chance:
				wounded_left_behind_count += heavily_wounded_count
				heavily_wounded_count = 0
				just_abandoned_wounded = true
				return 1.0

	just_carried_wounded = true
	return max(1.0 - GameConfig.HEAVILY_WOUNDED_SLOWDOWN_PER_PERSON * heavily_wounded_count, GameConfig.HEAVILY_WOUNDED_MIN_RETREAT_SPEED_FRACTION)


## Walk a real multi-waypoint path (e.g. "get onto the road, then march down
## it") instead of a single beeline. BattleManager._step_toward_target pops
## the next waypoint off move_queue each time one is reached.
func set_path(waypoints: Array[Vector2]) -> void:
	last_order_reason = "Following the assigned march route."
	if waypoints.is_empty():
		has_move_target = false
		move_queue.clear()
		return
	move_target = waypoints[0]
	move_queue = waypoints.slice(1)
	has_move_target = true


## Head for the nearest cover instead of wherever it was going. Used both for
## an enemy squad breaking from its road march and for either side's squad
## bolting under mortar fire. Clears any queued path (e.g. the rest of a
## road march) — cover takes priority over wherever it was headed. Marks the
## movement unpredictable: diving for cover is reactive and erratic, not a
## steady lead-aimable path, so a mortar should have a much harder time
## hitting a unit doing this than one on its own predictable road march.
##
## `avoid_positions` — other same-team units already there or headed there —
## steers away from a patch of cover an ally is already using, so squads
## spread out instead of bunching up (see GameConfig.nearest_cover_point).
##
## `known_enemy_positions` — currently-visible enemy positions, from THIS
## unit's own side's point of view — steers away from cover within
## GameConfig.DANGER_RADIUS of a known threat, same as order_retreat
## already does. Without this, a squad bolting for cover under fire could
## dive for whatever patch is nearest with no regard for who's actually
## standing near it — including, in the worst case, running straight
## toward a cluster of enemy squads it already knows are right there.
func seek_cover(avoid_positions: Array[Vector2] = [], known_enemy_positions: Array[Vector2] = []) -> void:
	last_order_reason = "Seeking cover in response to contact or incoming fire."
	move_target = GameConfig.nearest_cover_point(global_position, 0.0, false, avoid_positions, known_enemy_positions)
	has_move_target = true
	move_queue.clear()
	move_speed = GameConfig.REPOSITION_SPEED
	movement_predictable = false


## ACTIVE or RETREATING — still present, still a real unit in the fight,
## as opposed to DESTROYED/WITHDRAWN/SURRENDERED. Visibility-independent;
## see is_targetable() for the full "can actually be fired at right now"
## check, and BattleManager._known_enemy_positions for the analogous
## "still a threat" standard applied to squad danger elsewhere.
func is_targetable_state() -> bool:
	return state == State.ACTIVE or state == State.RETREATING

func is_targetable() -> bool:
	return is_targetable_state() and is_visible


## The same ACTIVE-or-RETREATING predicate, but against what the PLAYER side currently believes about
## this (necessarily enemy) unit — player_known_state, last updated the tick it was actually visible —
## rather than its real, possibly more current ground truth. For reasoning from a stale lead (a
## last-known position, a fire-detection trace) instead of a live sighting: direct user correction, "the
## drone team should not have known that we hit the enemy mortar. No one saw it ... Every unit should act
## based on what it knows. It cannot act on information that it is not aware of." Meaningless for one of
## the player's own units (a side always has ground truth about itself) — only ever asked of the opposing
## side.
func is_targetable_state_known_to_player() -> bool:
	return player_known_state == State.ACTIVE or player_known_state == State.RETREATING


## Direct user request, part of making the Ukraine-vs-Russia setting explicit: "Ukrainian"/"Russian" here
## specifically — NOT on the map's own on-unit label (Unit._draw draws unit_label directly, with no side
## prefix at all, and stays that way: "Don't put it onto the unit names on the map. It makes them too
## long."). This is the combat log / AAR report / debug-snapshot name instead, where the extra length
## doesn't crowd anything.
func display_name() -> String:
	var side := "Ukrainian" if team == Team.PLAYER else "Russian"
	return "%s %s" % [side, unit_label]


func destroyed_verb() -> String:
	return "was destroyed"


## Real, continuous ground elevation in meters at this unit's position (see
## GameConfig.elevation_m) — not a discrete "on the hill or not" flag.
func elevation() -> float:
	return GameConfig.elevation_m(global_position)


func terrain_type() -> GameConfig.TerrainType:
	return GameConfig.get_terrain_type_at(global_position)


## The unit's posture, at `at` (this unit's own position when omitted; a forecast asks about a place it may be). Direct user ruling:
## "Posture should be something that all units have at all times ... A moving unit has to be standing up." So a unit that is MOVING is
## STANDING whatever else is true: this is how the function is built, nothing has to keep it so. A stationary unit is STANDING (upright:
## at its post, at a window, behind a tree) until fire has arrived and it has gone to ground (`gone_to_ground`, kept by
## BattleManager._update_postures; it only counts for the place the unit is at: asked about another place, a unit would arrive upright).
## Posture is a property of the person, not of the place: a squad inside a building is upright, not lying on the floor, until fire
## gives it a reason; what the place does for it is exposure_terrain, and the two multiply (posture_factor). A DRONE is airborne and has
## no posture to speak of: STANDING.
func posture(at: Vector2 = Vector2.INF) -> Posture:
	if activity == Activity.MOVING or kind == Kind.DRONE:
		return Posture.STANDING
	var here: bool = is_inf(at.x) or at.distance_to(global_position) < 1.0
	return Posture.PRONE if (here and gone_to_ground) else Posture.STANDING


## What being down is worth to this unit, against a bullet or a fragment, on top of the protection of the place it is in (the cover tables,
## which are for a man at his post): GameConfig.PRONE_IN_OPEN_FACTOR in the open (lying against standing), GameConfig.PRONE_IN_COVER_FACTOR
## in cover (crouched below the parapet against firing over it); 1 for a unit that is upright or moving.
func posture_factor(at: Vector2 = Vector2.INF) -> float:
	if posture(at) != Posture.PRONE:
		return 1.0
	if in_fighting_position(at):
		return GameConfig.PRONE_IN_COVER_FACTOR # crouched on the fire step
	var where: Vector2 = global_position if is_inf(at.x) else at
	if GameConfig.get_terrain_type_at(where) == GameConfig.TerrainType.OPEN:
		# lying in the open; in a shell scrape it is a little better (it "soon proved inadequate": a few inches of earth)
		return GameConfig.PRONE_IN_OPEN_FACTOR * (GameConfig.SCRAPE_PROTECTION_FACTOR if entrenchment == Entrenchment.SCRAPE else 1.0)
	return GameConfig.PRONE_IN_COVER_FACTOR


## True for a unit that has a finished fighting position where it is and is not moving from it (asked about another place, no: it would
## arrive without one).
func in_fighting_position(at: Vector2 = Vector2.INF) -> bool:
	if entrenchment != Entrenchment.FIGHTING_POSITION or activity == Activity.MOVING or kind == Kind.DRONE:
		return false
	return is_inf(at.x) or at.distance_to(global_position) < 1.0


## Whether the unit is in cover, for the units' own decisions about whether to look for some: in trees or a building, or in a fighting
## position of its own (which is better than either). A squad in its hole does not walk off to the nearest tree line, and does not bolt
## from it when a round lands.
func in_cover() -> bool:
	return GameConfig.is_in_cover(terrain_type()) or in_fighting_position()


## What a fighting position does for the unit at its post: GameConfig.FIGHTING_POSITION_RATIO of what it would have on its feet in the
## open, as a ratio on the cover tables and the blast curve; 1 for a unit without one.
func fighting_position_ratio(at: Vector2 = Vector2.INF) -> float:
	return GameConfig.FIGHTING_POSITION_RATIO if in_fighting_position(at) else 1.0


## The terrain whose protection this unit has right now: the terrain it is in, moving or still (a drone, airborne, has the open).
## Posture does not decide this: an upright squad in a building has the building. How much of it a unit that is MOVING keeps is
## cover_kept. The one place the question is asked.
func exposure_terrain(at: Vector2 = Vector2.INF) -> GameConfig.TerrainType:
	if kind == Kind.DRONE:
		return GameConfig.TerrainType.OPEN
	return GameConfig.get_terrain_type_at(global_position if is_inf(at.x) else at)


## How much of its terrain's protection the unit has, as the exponent of the ratio the terrain gives it against the open: 1 for a unit that
## is still (all of it), GameConfig.MOVING_COVER_KEPT for the terrain it is in for one that is moving (in the open the ratio is 1 and
## nothing changes). User, on a squad walking through a building: "should have cover from the building ... Ditto for trees."
func cover_kept(at: Vector2 = Vector2.INF) -> float:
	if activity != Activity.MOVING:
		return 1.0
	return GameConfig.MOVING_COVER_KEPT[exposure_terrain(at)]


## A drone flies over everything on the ground: drawn above every other unit, whatever order
## they were created in ("The drone should be drawn on top of all squads. The drone should cover
## up part of the squad, not the reverse.").
const DRONE_Z_INDEX: int = 10


## Where the unit's name is drawn: below it, except a drone's, which goes above so that a drone
## hovering over a ground unit (the squad it is tracking) does not print its name over that unit's.
func label_position() -> Vector2:
	return Vector2(-24, -24) if kind == Kind.DRONE else Vector2(-24, 29)


func _draw() -> void:
	if show_range_ring and kind == Kind.MORTAR and state == State.ACTIVE and (team == Team.PLAYER or is_visible):
		GameConfig.draw_mortar_range_ring(self, GameConfig.mortar_max_range(team), GameConfig.MORTAR_RANGE_RING_COLOR if team == Team.PLAYER else GameConfig.MORTAR_RANGE_RING_COLOR_ENEMY)
	var color := Color(0.25, 0.55, 1.0) if team == Team.PLAYER else Color(1.0, 0.35, 0.25)
	if kind == Kind.SPOTTER or kind == Kind.DRONE_TEAM:
		color = Color(0.75, 0.9, 0.2) if team == Team.PLAYER else Color(0.9, 0.7, 0.15)
	elif kind == Kind.DRONE:
		color = Color(0.9, 0.97, 1.0) if team == Team.PLAYER else Color(1.0, 0.55, 0.55)
	elif kind == Kind.RESUPPLY_RUN:
		# Muted, distinctly non-combat tan, not any fighting unit's color
		# scheme — reinforced by the square shape below (see _draw's own
		# radius/shape branch) reading as "not a combat unit" at a glance.
		color = Color(0.75, 0.65, 0.35) if team == Team.PLAYER else Color(0.8, 0.55, 0.25)
	if not is_visible and state != State.DESTROYED:
		color.a = 0.0 if team == Team.ENEMY else 1.0 # not-currently-visible enemies are hidden; player is always drawn
	if state == State.RETREATING:
		color = color.darkened(0.55)
	if state == State.WITHDRAWN:
		color.a = 0.3
	if state == State.SURRENDERED:
		color = Color.WHITE
		color.a = 0.5
	if state == State.DESTROYED:
		color = Color(0.25, 0.25, 0.25)

	if color.a <= 0.0:
		return

	draw_string(ThemeDB.fallback_font, label_position(), unit_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color.lightened(0.3))

	var radius := 14.0 if kind == Kind.SQUAD else (8.0 if (kind == Kind.SPOTTER or kind == Kind.DRONE_TEAM) else (6.0 if kind == Kind.RESUPPLY_RUN else (5.0 if kind == Kind.DRONE else 10.0)))
	if kind == Kind.RESUPPLY_RUN:
		# A square, not a circle — same non-combat visual language as the
		# deployment-phase resupply token, distinct from every round
		# fighting-unit marker.
		draw_rect(Rect2(-radius, -radius, radius * 2.0, radius * 2.0), color)
	else:
		if kind == Kind.DRONE:
			# A dark rim: a drone tracking an enemy squad hovers right over it, and a small pale disc on
			# a red one is easy to lose ("it says we have a drone airborne, but I can't see it anywhere").
			draw_circle(Vector2.ZERO, radius + 2.0, Color(0.05, 0.05, 0.05, color.a))
		draw_circle(Vector2.ZERO, radius, color)

	if kind == Kind.MORTAR:
		draw_circle(Vector2.ZERO, radius * 0.45, Color.BLACK)
	elif kind == Kind.SPOTTER or kind == Kind.DRONE_TEAM:
		draw_circle(Vector2.ZERO, radius * 0.4, Color(0.1, 0.1, 0.1))
		draw_circle(Vector2.ZERO, radius * 0.18, Color.WHITE)
	elif kind == Kind.DRONE:
		# A small quadcopter "X," distinct from every ground unit's icon —
		# reads instantly as airborne even at a glance.
		draw_line(Vector2(-radius, -radius), Vector2(radius, radius), Color(0.15, 0.15, 0.15), 1.5)
		draw_line(Vector2(-radius, radius), Vector2(radius, -radius), Color(0.15, 0.15, 0.15), 1.5)

	if state == State.WITHDRAWN or state == State.DESTROYED or state == State.SURRENDERED:
		return # no pip bar or cover ring for a unit that's left the fight one way or another

	# Cover ring — visible any time the unit is on the field, so cover status
	# is always readable at a glance during the battle.
	GameConfig.draw_cover_ring(self, radius, terrain_type(), Vector2.ZERO, team)

	# Pip bar above the unit — a mortar's now tracks actual crew strength
	# (max_pips == crew_size, see setup()) same as a squad's; the spotter
	# alone just shows full/empty, being a single 1-pip team.
	var bar_width := 28.0
	var bar_y := -radius - 10.0
	draw_rect(Rect2(-bar_width / 2.0, bar_y, bar_width, 4.0), Color(0.15, 0.15, 0.15))
	if max_pips > 0:
		var filled_width: float = bar_width * (float(pips) / float(max_pips))
		draw_rect(Rect2(-bar_width / 2.0, bar_y, filled_width, 4.0), Color(0.2, 0.9, 0.3))
