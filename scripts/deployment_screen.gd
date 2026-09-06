extends Node2D
class_name DeploymentScreen
## Pre-battle map view: shows the actual terrain and lets the player drag
## their 3 squads, mortar, and recon asset (artillery spotter or drone
## team — see recon_mode) to starting positions before the battle begins.
## Uses _unhandled_input so clicks over the sidebar's Controls (sliders,
## buttons) never start a drag.

var recon_mode: GameConfig.ReconMode = GameConfig.ReconMode.SPOTTER

var _tokens: Array[UnitToken] = []
var _squad_tokens: Array[UnitToken] = []
var _mortar_token: UnitToken
var _spotter_token: UnitToken
var _dragging: UnitToken = null


func _ready() -> void:
	for i in GameConfig.PLAYER_DEFAULT_POSITIONS.size():
		var token := UnitToken.new()
		add_child(token)
		token.setup(Unit.Kind.SQUAD, "Squad %d" % (i + 1), GameConfig.PLAYER_DEFAULT_POSITIONS[i], GameConfig.PLAYER_DEPLOYMENT_ZONE)
		_squad_tokens.append(token)
		_tokens.append(token)

	_mortar_token = UnitToken.new()
	add_child(_mortar_token)
	_mortar_token.setup(Unit.Kind.MORTAR, "Mortar", GameConfig.PLAYER_MORTAR_DEFAULT_POSITION, GameConfig.PLAYER_MORTAR_DEPLOYMENT_ZONE)
	_tokens.append(_mortar_token)

	# Same deployment zone/default position either way — see GameConfig.
	# PLAYER_SPOTTER_DEPLOYMENT_ZONE's comment.
	_spotter_token = UnitToken.new()
	add_child(_spotter_token)
	var recon_kind: Unit.Kind = Unit.Kind.DRONE_TEAM if recon_mode == GameConfig.ReconMode.DRONE_TEAM else Unit.Kind.SPOTTER
	var recon_label: String = "Drone Team" if recon_mode == GameConfig.ReconMode.DRONE_TEAM else "Spotter"
	_spotter_token.setup(recon_kind, recon_label, GameConfig.PLAYER_SPOTTER_DEFAULT_POSITION, GameConfig.PLAYER_SPOTTER_DEPLOYMENT_ZONE)
	_tokens.append(_spotter_token)

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
		var zone := _dragging.deployment_zone
		var mouse_pos := get_global_mouse_position()
		var candidate := Vector2(
			clamp(mouse_pos.x, zone.position.x, zone.end.x),
			clamp(mouse_pos.y, zone.position.y, zone.end.y)
		)
		# A mortar can never be set up inside a building (no overhead
		# clearance to fire from one) — the token simply stops at the
		# building's edge instead of following the cursor inside it.
		if _dragging.kind == Unit.Kind.MORTAR and GameConfig.is_building_at(candidate):
			return
		_dragging.position = candidate
		_dragging.queue_redraw() # cover ring must update live as it crosses terrain


## Returns {"squad_positions": [Vector2, Vector2, Vector2], "mortar_position":
## Vector2, "spotter_position": Vector2} for BattleManager's doctrine dict.
func get_positions() -> Dictionary:
	var squad_positions: Array[Vector2] = []
	for token in _squad_tokens:
		squad_positions.append(token.position)
	return {
		"squad_positions": squad_positions,
		"mortar_position": _mortar_token.position,
		"spotter_position": _spotter_token.position,
	}


func _draw() -> void:
	GameConfig.draw_terrain(self)
	draw_rect(GameConfig.PLAYER_MORTAR_DEPLOYMENT_ZONE, Color(1.0, 0.55, 0.15, 0.5), false, 2.0)
	draw_rect(GameConfig.PLAYER_DEPLOYMENT_ZONE, Color(1.0, 1.0, 0.2, 0.7), false, 2.0)
	draw_rect(GameConfig.PLAYER_SPOTTER_DEPLOYMENT_ZONE, Color(0.3, 1.0, 1.0, 0.6), false, 2.0)
