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
enum Kind { SQUAD, MORTAR, SPOTTER }
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
var relocate_cooldown: float = 5.0
var reload_time: float = 3.0

# General-purpose movement target + queue, used for: an enemy squad's
# initial road march (a real multi-waypoint path — see set_path), either
# side's squad bolting for cover, and a retreat's first leg to cover.
# RETREATING's final leg to safety uses its own retreat_speed/
# retreat_target_x instead (see below).
var move_target: Vector2 = Vector2.ZERO
var has_move_target: bool = false
var move_queue: Array[Vector2] = []
var move_speed: float = 40.0
const MOVE_ARRIVE_RADIUS: float = 8.0

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

# ENEMY SQUAD only: set once, before the real retreat threshold, as a
# lower-severity "this is getting bad" signal. BattleManager polls
# reported_issue_logged to log it exactly once — not acted on mechanically.
var reported_issue: bool = false
var reported_issue_logged: bool = false
var concern_threshold: float = 0.25

# Set once, when a MORTAR is put out of action — flavor only, for the AAR
# report. There is no percent-casualties tracking while the mortar is active:
# a hit either knocks it out or it does not.
var crew_casualty_percent: int = 0

signal took_hit(unit)
signal state_changed(unit)


func setup(p_team: Team, p_kind: Kind, p_position: Vector2) -> void:
	team = p_team
	kind = p_kind
	position = p_position
	match kind:
		Kind.MORTAR:
			max_pips = 1
			base_hit_chance = 0.40
			unit_label = "Mortar"
			fire_interval = reload_time
		Kind.SPOTTER:
			max_pips = 1 # a small, fragile recon team
			base_hit_chance = 0.0 # never fires — see BattleManager._tick_fire
			unit_label = "Spotter"
			fire_interval = 0.0
		_:
			max_pips = 4
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
func take_hit(from_mortar: bool = false) -> void:
	if state == State.DESTROYED:
		return
	pips -= 1
	took_hit.emit(self)
	queue_redraw()
	if pips <= 0:
		pips = 0
		state = State.DESTROYED
		if kind == Kind.MORTAR:
			crew_casualty_percent = randi_range(25, 100)
		state_changed.emit(self)
		return

	# A mortar crew is either in action or it is not — no percent-casualties
	# "retreat" state for a mortar. Only squads can be worn down and pull back,
	# break from an advance toward cover, or bolt under mortar fire.
	if kind != Kind.SQUAD:
		return

	_check_retreat()
	if state != State.ACTIVE:
		return

	if team == Team.ENEMY and not sought_cover:
		sought_cover = true
		seek_cover()
	elif from_mortar and randf() < GameConfig.RELOCATE_ON_MORTAR_HIT_CHANCE:
		seek_cover()
		bolted_for_cover = true


func _check_retreat() -> void:
	if state != State.ACTIVE:
		return
	var fraction_lost: float = float(max_pips - pips) / float(max_pips)
	if fraction_lost >= retreat_threshold:
		order_retreat()
	elif not reported_issue and fraction_lost >= concern_threshold:
		reported_issue = true


## Force this unit into a retreat regardless of its threshold — used both by
## the automatic threshold check above and by the player's general retreat
## order (see BattleManager.order_general_retreat).
##
## Takes a safe-ish path rather than a beeline: if not already in cover, the
## first leg heads for the nearest cover (BattleManager._tick_movement runs
## this leg via the normal move_target system); once there — or immediately,
## if already in cover — the final leg is the straight pull to the safe
## line (BattleManager._step_retreat). A unit tucked behind a building this
## way can also break direct-fire LOS entirely (see GameConfig.has_direct_los).
func order_retreat() -> void:
	if state != State.ACTIVE:
		return
	state = State.RETREATING
	if not GameConfig.is_in_cover(terrain_type()):
		seek_cover()
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
## road march) — cover takes priority over wherever it was headed.
func seek_cover() -> void:
	move_target = GameConfig.nearest_cover_point(global_position)
	has_move_target = true
	move_queue.clear()
	move_speed = GameConfig.REPOSITION_SPEED


func is_targetable() -> bool:
	return state != State.DESTROYED and state != State.WITHDRAWN and is_visible


func display_name() -> String:
	var side := "Player" if team == Team.PLAYER else "Enemy"
	return "%s %s" % [side, unit_label]


func destroyed_verb() -> String:
	return "was put out of action" if kind == Kind.MORTAR else "was destroyed"


func elevation() -> int:
	return GameConfig.get_elevation_at(global_position)


func terrain_type() -> GameConfig.TerrainType:
	return GameConfig.get_terrain_type_at(global_position)


func _draw() -> void:
	var color := Color(0.25, 0.55, 1.0) if team == Team.PLAYER else Color(1.0, 0.35, 0.25)
	if kind == Kind.SPOTTER:
		color = Color(0.75, 0.9, 0.2) if team == Team.PLAYER else Color(0.9, 0.7, 0.15)
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

	var radius := 14.0 if kind == Kind.SQUAD else (8.0 if kind == Kind.SPOTTER else 10.0)
	draw_circle(Vector2.ZERO, radius, color)

	if kind == Kind.MORTAR:
		draw_circle(Vector2.ZERO, radius * 0.45, Color.BLACK)
	elif kind == Kind.SPOTTER:
		draw_circle(Vector2.ZERO, radius * 0.4, Color(0.1, 0.1, 0.1))
		draw_circle(Vector2.ZERO, radius * 0.18, Color.WHITE)

	if state == State.WITHDRAWN or state == State.DESTROYED:
		return # no pip bar or cover ring for a unit that's left the fight one way or another

	# Cover ring — visible any time the unit is on the field, so cover status
	# is always readable at a glance during the battle.
	GameConfig.draw_cover_ring(self, radius, terrain_type())

	# Pip bar above the unit (mortars/spotter just show full/empty — no
	# percent bar; both are 1 pip).
	var bar_width := 28.0
	var bar_y := -radius - 10.0
	draw_rect(Rect2(-bar_width / 2.0, bar_y, bar_width, 4.0), Color(0.15, 0.15, 0.15))
	if max_pips > 0:
		var filled_width: float = bar_width * (float(pips) / float(max_pips))
		draw_rect(Rect2(-bar_width / 2.0, bar_y, filled_width, 4.0), Color(0.2, 0.9, 0.3))
