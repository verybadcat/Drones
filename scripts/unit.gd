extends Node2D
class_name Unit
## A single deployable unit: an infantry squad or a mortar crew.
## Pure data + drawing. All combat/spotting/movement/timing logic lives in
## BattleManager and CombatResolver so this stays a dumb, easy-to-inspect object.

enum Team { PLAYER, ENEMY }
enum Kind { SQUAD, MORTAR }
## ACTIVE: fighting. RETREATING: pulling back, still on the field and can
## still take fire. WITHDRAWN: reached safety, no longer part of the fight.
## DESTROYED: out of action for good.
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

# Spotting: is this unit currently visible to the OPPOSING side?
var is_spotted: bool = false

var fire_interval: float = 2.0 # seconds between fire attempts
var fire_timer: float = 0.0

# Mortar-only doctrine fields (unused by SQUAD kind).
var shoot_and_scoot: bool = false
var relocate_cooldown: float = 5.0
var reload_time: float = 3.0
var shots_since_relocate: int = 0
var counter_battery_shot_threshold: int = 2
var counter_battery_tick_chance: float = 0.05 # per 1s tick, once threshold crossed
var counter_battery_timer: float = 0.0

# Movement, used by RETREATING units on both sides and by advancing enemy
# squads. Player squads/mortar never move on their own — only when ordered
# to retreat.
var move_speed: float = 0.0
var retreat_speed: float = 0.0
var advance_stop_x: float = 0.0 # ENEMY SQUAD only
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
	if kind == Kind.MORTAR:
		max_pips = 1
		base_hit_chance = 0.40
		unit_label = "Mortar"
		fire_interval = reload_time
	else:
		max_pips = 4
		base_hit_chance = 0.20
		unit_label = "Squad"
		fire_interval = 2.0
	pips = max_pips
	queue_redraw()


func take_hit() -> void:
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
	# "retreat" state for a mortar. Only squads can be worn down and pull back.
	if kind == Kind.SQUAD:
		_check_retreat()


func _check_retreat() -> void:
	if state != State.ACTIVE:
		return
	var fraction_lost: float = float(max_pips - pips) / float(max_pips)
	if fraction_lost >= retreat_threshold:
		order_retreat()
	elif kind == Kind.SQUAD and not reported_issue and fraction_lost >= concern_threshold:
		reported_issue = true


## Force this unit into a retreat regardless of its threshold — used both by
## the automatic threshold check above and by the player's general retreat
## order (see BattleManager.order_general_retreat).
func order_retreat() -> void:
	if state != State.ACTIVE:
		return
	state = State.RETREATING
	state_changed.emit(self)


func is_targetable() -> bool:
	return state != State.DESTROYED and state != State.WITHDRAWN and is_spotted


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
	if not is_spotted and state != State.DESTROYED:
		color.a = 0.0 if team == Team.ENEMY else 1.0 # unspotted enemies are invisible; player is always drawn
	if state == State.RETREATING:
		color = color.darkened(0.55)
	if state == State.WITHDRAWN:
		color.a = 0.3
	if state == State.DESTROYED:
		color = Color(0.25, 0.25, 0.25)

	if color.a <= 0.0:
		return

	var radius := 14.0 if kind == Kind.SQUAD else 10.0
	draw_circle(Vector2.ZERO, radius, color)

	if kind == Kind.MORTAR:
		draw_circle(Vector2.ZERO, radius * 0.45, Color.BLACK)

	if state == State.WITHDRAWN or state == State.DESTROYED:
		return # no pip bar for a unit that's left the fight one way or another

	# Pip bar above the unit (mortars just show full/empty — no percent bar).
	var bar_width := 28.0
	var bar_y := -radius - 10.0
	draw_rect(Rect2(-bar_width / 2.0, bar_y, bar_width, 4.0), Color(0.15, 0.15, 0.15))
	if max_pips > 0:
		var filled_width: float = bar_width * (float(pips) / float(max_pips))
		draw_rect(Rect2(-bar_width / 2.0, bar_y, filled_width, 4.0), Color(0.2, 0.9, 0.3))
