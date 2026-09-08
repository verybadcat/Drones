extends Node2D
class_name BattleHistoryViewer
## Post-battle "drag through time" replay — see main.gd's "Review Battle
## History" button on the AAR screen. Draws a SELF-CONTAINED snapshot of
## recorded unit positions/states (BattleManager.battle_history/
## _record_history_snapshot), not the live Unit nodes themselves: some of
## those (a destroyed drone, a despawned resupply run) may not even exist
## any more by the time the battle ends, so a scrubbable history has to
## stand on its own rather than puppeting nodes it doesn't control the
## lifecycle of. Shows TRUE ground truth (both sides' real positions,
## including anything never actually spotted at the time) rather than the
## player's own historical knowledge — a deliberate choice for this review
## feature, confirmed with the user, unlike the AAR report itself, which
## stays honest to what was actually known at the time.

var history: Array[Dictionary] = []
var current_index: int = 0


func setup(p_history: Array[Dictionary]) -> void:
	history = p_history
	current_index = history.size() - 1 # start at the battle's final moment
	queue_redraw()


func set_index(i: int) -> void:
	current_index = clampi(i, 0, history.size() - 1)
	queue_redraw()


func current_time() -> float:
	if history.is_empty():
		return 0.0
	return history[current_index].time


func _draw() -> void:
	if history.is_empty():
		return
	for u in history[current_index].units:
		_draw_unit(u)


## A simplified, self-contained echo of Unit._draw()'s own color/size
## language — deliberately NOT the is_visible-based hiding that function
## also does, since this view is unconditional ground truth. Sub-icon
## detail (the mortar's dot, the drone's rotor cross, etc.) is skipped for
## now; team/kind color plus state-based dimming is enough to follow how a
## battle actually unfolded, which is what this feature is for.
func _draw_unit(u: Dictionary) -> void:
	var team: Unit.Team = u.team
	var kind: Unit.Kind = u.kind
	var state: Unit.State = u.state
	var pos := Vector2(u.x, u.y)

	var color := Color(0.25, 0.55, 1.0) if team == Unit.Team.PLAYER else Color(1.0, 0.35, 0.25)
	if kind == Unit.Kind.SPOTTER or kind == Unit.Kind.DRONE_TEAM:
		color = Color(0.75, 0.9, 0.2) if team == Unit.Team.PLAYER else Color(0.9, 0.7, 0.15)
	elif kind == Unit.Kind.DRONE:
		color = Color(0.9, 0.97, 1.0) if team == Unit.Team.PLAYER else Color(1.0, 0.55, 0.55)
	elif kind == Unit.Kind.RESUPPLY_RUN:
		color = Color(0.75, 0.65, 0.35) if team == Unit.Team.PLAYER else Color(0.8, 0.55, 0.25)
	if state == Unit.State.RETREATING:
		color = color.darkened(0.55)
	if state == Unit.State.WITHDRAWN:
		color.a = 0.3
	if state == Unit.State.SURRENDERED:
		color = Color.WHITE
		color.a = 0.5
	if state == Unit.State.DESTROYED:
		color = Color(0.25, 0.25, 0.25)

	var radius := 14.0 if kind == Unit.Kind.SQUAD else (8.0 if (kind == Unit.Kind.SPOTTER or kind == Unit.Kind.DRONE_TEAM) else (6.0 if kind == Unit.Kind.RESUPPLY_RUN else (5.0 if kind == Unit.Kind.DRONE else 10.0)))
	if kind == Unit.Kind.RESUPPLY_RUN:
		draw_rect(Rect2(pos - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)), color)
	else:
		draw_circle(pos, radius, color)
