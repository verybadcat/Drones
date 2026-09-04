extends Node2D
class_name DeploymentScreen
## Pre-battle map view: shows the actual terrain and lets the player drag
## their 3 squads + mortar to starting positions inside the village before
## the battle begins. Uses _unhandled_input so clicks over the sidebar's
## Controls (sliders, buttons) never start a drag.

var _tokens: Array[UnitToken] = []
var _squad_tokens: Array[UnitToken] = []
var _mortar_token: UnitToken
var _dragging: UnitToken = null


func _ready() -> void:
	for i in GameConfig.PLAYER_DEFAULT_POSITIONS.size():
		var token := UnitToken.new()
		add_child(token)
		token.setup(Unit.Kind.SQUAD, "Squad %d" % (i + 1), GameConfig.PLAYER_DEFAULT_POSITIONS[i])
		_squad_tokens.append(token)
		_tokens.append(token)

	_mortar_token = UnitToken.new()
	add_child(_mortar_token)
	_mortar_token.setup(Unit.Kind.MORTAR, "Mortar", GameConfig.PLAYER_MORTAR_DEFAULT_POSITION)
	_tokens.append(_mortar_token)

	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var mouse_pos := get_global_mouse_position()
			for token in _tokens:
				if token.contains_point(mouse_pos):
					_dragging = token
					break
		else:
			_dragging = null
	elif event is InputEventMouseMotion and _dragging != null:
		var zone := GameConfig.PLAYER_DEPLOYMENT_ZONE
		var mouse_pos := get_global_mouse_position()
		_dragging.position = Vector2(
			clamp(mouse_pos.x, zone.position.x, zone.end.x),
			clamp(mouse_pos.y, zone.position.y, zone.end.y)
		)


## Returns {"squad_positions": [Vector2, Vector2, Vector2], "mortar_position": Vector2}
## for BattleManager to build the doctrine dict from.
func get_positions() -> Dictionary:
	var squad_positions: Array[Vector2] = []
	for token in _squad_tokens:
		squad_positions.append(token.position)
	return {
		"squad_positions": squad_positions,
		"mortar_position": _mortar_token.position,
	}


func _draw() -> void:
	GameConfig.draw_terrain(self)
	draw_rect(GameConfig.PLAYER_DEPLOYMENT_ZONE, Color(1.0, 1.0, 0.2, 0.7), false, 2.0)
