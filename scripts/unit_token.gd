extends Node2D
class_name UnitToken
## A draggable marker on the deployment screen, standing in for one unit
## before the battle starts. Purely visual/interactive — DeploymentScreen
## reads each token's final .position to build the doctrine dict, and
## clamps drags to `deployment_zone` (different for the spotter than for
## squads/mortar — see GameConfig).

var kind: Unit.Kind = Unit.Kind.SQUAD
var label_text: String = "Squad"
var deployment_zone: Rect2
const RADIUS: float = 16.0

## Not a real Unit at all — the resupply point is a logistics location, not
## a combat asset (see BattleManager's own resupply request/travel logic) —
## so this is a separate flag rather than adding a bogus entry to Unit.Kind
## that would need excluding from every switch/match over real unit kinds
## elsewhere. When true, `kind` is never read for drawing purposes at all.
var is_resupply_point: bool = false


func setup(p_kind: Unit.Kind, p_label: String, p_position: Vector2, p_zone: Rect2) -> void:
	kind = p_kind
	label_text = p_label
	position = p_position
	deployment_zone = p_zone
	queue_redraw()


func setup_resupply_point(p_label: String, p_position: Vector2, p_zone: Rect2) -> void:
	is_resupply_point = true
	label_text = p_label
	position = p_position
	deployment_zone = p_zone
	queue_redraw()


func contains_point(p: Vector2) -> bool:
	return position.distance_to(p) <= RADIUS


func _draw() -> void:
	if is_resupply_point:
		# A square, not a circle — reads as distinctly "not a combat unit"
		# at a glance among the round squad/mortar/recon tokens.
		var half := RADIUS * 0.8
		draw_rect(Rect2(Vector2(-half, -half), Vector2(half, half) * 2.0), Color(0.85, 0.75, 0.2, 0.9))
		draw_rect(Rect2(Vector2(-half, -half), Vector2(half, half) * 2.0), Color(0.1, 0.1, 0.1), false, 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(-45, -RADIUS - 6), label_text,
			HORIZONTAL_ALIGNMENT_CENTER, 90, 13, Color.WHITE)
		return

	# The mortar's real max range (3500m) is a hard cutoff now, not
	# unlimited — show it during deployment so its placement is an informed
	# choice, not a guess.
	if kind == Unit.Kind.MORTAR:
		draw_arc(Vector2.ZERO, GameConfig.MORTAR_MAX_RANGE, 0.0, TAU, 64, Color(1.0, 0.55, 0.15, 0.35), 1.5, true)

	var color := Color(0.25, 0.55, 1.0, 0.9)
	if kind == Unit.Kind.SPOTTER or kind == Unit.Kind.DRONE_TEAM:
		color = Color(0.75, 0.9, 0.2, 0.9)
	draw_circle(Vector2.ZERO, RADIUS, color)
	if kind == Unit.Kind.MORTAR:
		draw_circle(Vector2.ZERO, RADIUS * 0.45, Color.BLACK)
	elif kind == Unit.Kind.SPOTTER or kind == Unit.Kind.DRONE_TEAM:
		draw_circle(Vector2.ZERO, RADIUS * 0.4, Color(0.1, 0.1, 0.1))
		draw_circle(Vector2.ZERO, RADIUS * 0.18, Color.WHITE)

	# Cover status is visible during setup too, not just once the battle starts.
	GameConfig.draw_cover_ring(self, RADIUS, GameConfig.get_terrain_type_at(position))

	# Wide enough for the longest label actually used ("Drone Team") at this
	# font size without clipping — 60px cut it off mid-word.
	draw_string(ThemeDB.fallback_font, Vector2(-45, -RADIUS - 6), label_text,
		HORIZONTAL_ALIGNMENT_CENTER, 90, 13, Color.WHITE)
