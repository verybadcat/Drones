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
enum Kind { SQUAD, MORTAR, SPOTTER, DRONE_TEAM, DRONE }
## ACTIVE: fighting (possibly moving toward move_target). RETREATING: pulling
## back off the field entirely, still on the field and can still take fire.
## WITHDRAWN: reached safety, no longer part of the fight. DESTROYED: out of
## action for good.
enum State { ACTIVE, RETREATING, WITHDRAWN, DESTROYED }
enum Activity { STATIONARY, MOVING }

var team: Team = Team.PLAYER
var kind: Kind = Kind.SQUAD
var unit_label: String = "Squad"

var max_pips: int = 4
var pips: int = 4
var base_hit_chance: float = 0.20
var retreat_threshold: float = 0.30 # SQUAD only — fraction of pips lost that triggers retreat
var state: State = State.ACTIVE
var activity: Activity = Activity.STATIONARY

# Is this unit currently visible to the OPPOSING side, right now? This is a
# live, moment-to-moment fact recomputed by BattleManager every tick — not a
# permanent flag. Spotting something once does not make it spotted forever;
# losing line of sight loses visibility too.
var is_visible: bool = false

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

# General-purpose movement target + queue, used for: an enemy squad's
# initial road march (a real multi-waypoint path — see set_path), either
# side's squad bolting for cover, and a retreat's first leg to cover.
# RETREATING's final leg to safety uses its own retreat_speed/
# retreat_target_x instead (see below).
var move_target: Vector2 = Vector2.ZERO
var has_move_target: bool = false
var move_queue: Array[Vector2] = []
var move_speed: float = 40.0
const MOVE_ARRIVE_RADIUS: float = 5.0 * GameConfig.PIXELS_PER_METER # "close enough" to a move target

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

# Set (not cleared) whenever seek_cover() is called for a reason OTHER than
# the one-time road-march break above — i.e. a mortar-fire bolt-for-cover.
# BattleManager polls + clears this to log each occurrence once.
var bolted_for_cover: bool = false

var retreat_speed: float = 0.0
var retreat_target_x: float = 0.0 # x that means "reached safety" while retreating

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

# MORTAR only: a small crew-served weapon, CREW_SIZE people including the
# driver. Tracked as an exact headcount, not a percent — see
# _apply_crew_casualties(). A hit is decisive either way: it either wipes
# the whole crew (DESTROYED) or leaves survivors who abandon the gun on the
# spot and retreat (see order_retreat()) — nobody keeps manning a mortar
# after taking a hit near it. max_pips is set to crew_size (see setup()) so
# these casualties feed into the side's overall pips_total/pips_lost tally
# (BattleManager._compute_side_stats) exactly like a squad's — the mortar
# and its crew are worth just as much to lose, or to kill, as anyone else.
const MORTAR_CREW_SIZE: int = 4
var crew_size: int = 0
var crew_killed: int = 0

# SQUAD only: a real 9-person infantry squad, for both sides. Unlike the
# mortar/drone team's crew_size/crew_killed model (a hit is decisive, killing
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
	match kind:
		Kind.MORTAR:
			crew_size = MORTAR_CREW_SIZE
			crew_killed = 0
			max_pips = crew_size # crew casualties count the same as squad pips — see _apply_crew_casualties
			base_hit_chance = 0.40
			unit_label = "Mortar"
			fire_interval = reload_time
		Kind.SPOTTER:
			max_pips = 1 # a small, fragile recon team
			base_hit_chance = 0.0 # never fires — see BattleManager._tick_fire
			unit_label = "Spotter"
			fire_interval = 0.0
		Kind.DRONE_TEAM:
			crew_size = GameConfig.DRONE_TEAM_CREW_SIZE
			crew_killed = 0
			max_pips = crew_size # same crew-casualty accounting as the mortar — see _apply_crew_casualties
			base_hit_chance = 0.0 # never fires — see BattleManager._tick_fire
			unit_label = "Drone Team"
			fire_interval = 0.0
		Kind.DRONE:
			max_pips = 1 # unmanned — one hit shoots it down outright, no crew to lose
			base_hit_chance = 0.0 # never fires — pure reconnaissance, see BattleManager._tick_fire
			unit_label = "Drone"
			fire_interval = 0.0
		_:
			max_pips = SQUAD_SIZE
			# Defenders fight from prepared, pre-ranged positions — their first
			# shots land far more often than an attacker's do.
			base_hit_chance = 0.32 if team == Team.PLAYER else 0.20
			unit_label = "Squad"
			fire_interval = 2.0
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
func take_hit(from_mortar: bool = false, ally_positions: Array[Vector2] = [], known_enemy_positions: Array[Vector2] = []) -> void:
	if state == State.DESTROYED:
		return
	took_hit.emit(self)
	queue_redraw()

	if kind == Kind.MORTAR or kind == Kind.DRONE_TEAM:
		_apply_crew_casualties(known_enemy_positions)
		return

	pips = max(pips - 1, 0)
	if pips <= 0:
		state = State.DESTROYED
		state_changed.emit(self)
		return

	# Only squads can be worn down and pull back, break from an advance
	# toward cover, or bolt under mortar fire (the spotter is one-hit-fragile
	# and never reaches this point; see the pips <= 0 check above).
	if kind != Kind.SQUAD:
		return

	_check_retreat(known_enemy_positions)
	if state != State.ACTIVE:
		return

	if team == Team.ENEMY and not sought_cover:
		sought_cover = true
		seek_cover(ally_positions)
	elif from_mortar and randf() < GameConfig.RELOCATE_ON_MORTAR_HIT_CHANCE:
		seek_cover(ally_positions)
		bolted_for_cover = true


func _check_retreat(known_enemy_positions: Array[Vector2] = []) -> void:
	if state != State.ACTIVE:
		return
	var fraction_lost: float = float(max_pips - pips) / float(max_pips)
	if fraction_lost >= retreat_threshold:
		order_retreat(known_enemy_positions)
	elif not reported_issue and fraction_lost >= concern_threshold:
		reported_issue = true


## A mortar crew (or a drone team's ground crew) doesn't shrug off a hit and
## keep working the way a rifle squad absorbs casualties — a round landing
## on/near a small crew is decisive. Tracks exactly how many went down (an
## honest headcount, not a vague percent) so the AAR can report a real
## number. If anyone survives, they abandon the position right there — it's
## out of action for the rest of the battle either way — and retreat to try
## to get clear (see order_retreat()); only a hit that gets the whole crew
## actually destroys the unit.
func _apply_crew_casualties(known_enemy_positions: Array[Vector2] = []) -> void:
	var remaining: int = crew_size - crew_killed
	crew_killed += randi_range(1, remaining)
	pips = crew_size - crew_killed # feeds the side's overall casualty tally exactly like a squad's pips — see setup()
	if crew_killed >= crew_size:
		state = State.DESTROYED
		state_changed.emit(self)
		return
	if state == State.ACTIVE:
		order_retreat(known_enemy_positions)


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
func order_retreat(known_enemy_positions: Array[Vector2] = []) -> void:
	if kind == Kind.DRONE:
		return
	if state != State.ACTIVE:
		return
	state = State.RETREATING
	movement_predictable = false # pulling out under pressure, not a calm march
	if not GameConfig.is_in_cover(terrain_type()):
		var retreat_dir: float = -1.0 if team == Team.PLAYER else 1.0
		var avoid_buildings: bool = kind == Kind.MORTAR
		if (kind == Kind.SPOTTER or kind == Kind.DRONE_TEAM) and not known_enemy_positions.is_empty():
			move_target = GameConfig.safest_cover_point(global_position, known_enemy_positions, retreat_dir, avoid_buildings)
		else:
			move_target = GameConfig.nearest_cover_point(global_position, retreat_dir, avoid_buildings, [], known_enemy_positions)
		has_move_target = true
		move_queue.clear()
		move_speed = GameConfig.REPOSITION_SPEED
	else:
		has_move_target = false
	state_changed.emit(self)


## Walk a real multi-waypoint path (e.g. "get onto the road, then march down
## it") instead of a single beeline. BattleManager._step_toward_target pops
## the next waypoint off move_queue each time one is reached.
func set_path(waypoints: Array[Vector2]) -> void:
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
func seek_cover(avoid_positions: Array[Vector2] = []) -> void:
	move_target = GameConfig.nearest_cover_point(global_position, 0.0, false, avoid_positions)
	has_move_target = true
	move_queue.clear()
	move_speed = GameConfig.REPOSITION_SPEED
	movement_predictable = false


func is_targetable() -> bool:
	return state != State.DESTROYED and state != State.WITHDRAWN and is_visible


func display_name() -> String:
	var side := "Player" if team == Team.PLAYER else "Enemy"
	return "%s %s" % [side, unit_label]


func destroyed_verb() -> String:
	return "was destroyed"


## Real, continuous ground elevation in meters at this unit's position (see
## GameConfig.elevation_m) — not a discrete "on the hill or not" flag.
func elevation() -> float:
	return GameConfig.elevation_m(global_position)


func terrain_type() -> GameConfig.TerrainType:
	return GameConfig.get_terrain_type_at(global_position)


func _draw() -> void:
	var color := Color(0.25, 0.55, 1.0) if team == Team.PLAYER else Color(1.0, 0.35, 0.25)
	if kind == Kind.SPOTTER or kind == Kind.DRONE_TEAM:
		color = Color(0.75, 0.9, 0.2) if team == Team.PLAYER else Color(0.9, 0.7, 0.15)
	elif kind == Kind.DRONE:
		color = Color(0.9, 0.97, 1.0) if team == Team.PLAYER else Color(1.0, 0.55, 0.55)
	if not is_visible and state != State.DESTROYED:
		color.a = 0.0 if team == Team.ENEMY else 1.0 # not-currently-visible enemies are hidden; player is always drawn
	if state == State.RETREATING:
		color = color.darkened(0.55)
	if state == State.WITHDRAWN:
		color.a = 0.3
	if state == State.DESTROYED:
		color = Color(0.25, 0.25, 0.25)

	if color.a <= 0.0:
		return

	var radius := 14.0 if kind == Kind.SQUAD else (8.0 if (kind == Kind.SPOTTER or kind == Kind.DRONE_TEAM) else (5.0 if kind == Kind.DRONE else 10.0))
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

	if state == State.WITHDRAWN or state == State.DESTROYED:
		return # no pip bar or cover ring for a unit that's left the fight one way or another

	# Cover ring — visible any time the unit is on the field, so cover status
	# is always readable at a glance during the battle.
	GameConfig.draw_cover_ring(self, radius, terrain_type())

	# Pip bar above the unit — a mortar's now tracks actual crew strength
	# (max_pips == crew_size, see setup()) same as a squad's; the spotter
	# alone just shows full/empty, being a single 1-pip team.
	var bar_width := 28.0
	var bar_y := -radius - 10.0
	draw_rect(Rect2(-bar_width / 2.0, bar_y, bar_width, 4.0), Color(0.15, 0.15, 0.15))
	if max_pips > 0:
		var filled_width: float = bar_width * (float(pips) / float(max_pips))
		draw_rect(Rect2(-bar_width / 2.0, bar_y, filled_width, 4.0), Color(0.2, 0.9, 0.3))
