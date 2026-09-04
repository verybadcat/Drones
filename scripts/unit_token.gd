extends Node2D
class_name UnitToken
## A draggable marker on the deployment screen, standing in for one unit
## before the battle starts. Purely visual/interactive — DeploymentScreen
## reads each token's final .position to build the doctrine dict.

var kind: Unit.Kind = Unit.Kind.SQUAD
var label_text: String = "Squad"
const RADIUS: float = 16.0


func setup(p_kind: Unit.Kind, p_label: String, p_position: Vector2) -> void:
	kind = p_kind
	label_text = p_label
	position = p_position
	queue_redraw()


func contains_point(p: Vector2) -> bool:
	return position.distance_to(p) <= RADIUS


func _draw() -> void:
	draw_circle(Vector2.ZERO, RADIUS, Color(0.25, 0.55, 1.0, 0.9))
	if kind == Unit.Kind.MORTAR:
		draw_circle(Vector2.ZERO, RADIUS * 0.45, Color.BLACK)
	draw_string(ThemeDB.fallback_font, Vector2(-30, -RADIUS - 6), label_text,
		HORIZONTAL_ALIGNMENT_CENTER, 60, 13, Color.WHITE)
