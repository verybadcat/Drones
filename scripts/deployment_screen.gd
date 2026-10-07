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
	for i in GameConfig.CURRENT_MAP.player.default_squad_positions.size():
		var token := UnitToken.new()
		add_child(token)
		token.setup(Unit.Kind.SQUAD, "Squad %d" % (i + 1), GameConfig.CURRENT_MAP.player.default_squad_positions[i], GameConfig.CURRENT_MAP.player.deployment_zone)
		_squad_tokens.append(token)
		_tokens.append(token)

	_mortar_token = UnitToken.new()
	add_child(_mortar_token)
	_mortar_token.setup(Unit.Kind.MORTAR, "Mortar", GameConfig.CURRENT_MAP.player.mortar_default_position, GameConfig.CURRENT_MAP.player.mortar_deployment_zone)
	_tokens.append(_mortar_token)

	# Same deployment zone/default position either way — see GameConfig.
	# PLAYER_SPOTTER_DEPLOYMENT_ZONE's comment.
	_spotter_token = UnitToken.new()
	add_child(_spotter_token)
	var recon_kind: Unit.Kind = Unit.Kind.DRONE_TEAM if recon_mode == GameConfig.ReconMode.DRONE_TEAM else Unit.Kind.SPOTTER
	var recon_label: String = "Drone Team" if recon_mode == GameConfig.ReconMode.DRONE_TEAM else "Spotter"
	_spotter_token.setup(recon_kind, recon_label, GameConfig.CURRENT_MAP.player.spotter_default_position, _recon_deployment_zone())
	_tokens.append(_spotter_token)

	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			begin_drag(get_global_mouse_position())
		else:
			end_drag()
		queue_redraw() # the mortar-exclusion wash shows only while the mortar is being placed
	elif event is InputEventMouseMotion and _dragging != null:
		drag_to(get_global_mouse_position())


## The mortar token's last legal spot on this drag: the place it started, then the latest spot it passed through that the Ukrainian mortar
## may be set up at (not in a building, not in the red area). Where it goes back to if the drag ends somewhere it may not stay.
var _last_legal_position: Vector2 = Vector2.ZERO


func _mortar_may_stand_at(point: Vector2) -> bool:
	return not GameConfig.mortar_barred_at(point, Unit.Team.PLAYER)


func begin_drag(point: Vector2) -> void:
	_dragging = token_at(point)
	if _dragging != null:
		_last_legal_position = _dragging.position


## The dragged token follows the cursor, clamped to its deployment zone. The mortar follows it through buildings and the red area too (a
## drag may pass through them); where it may not be set up it simply must not be left: see end_drag. Direct user instruction: "Let's even
## allow it to be dragged through the red during setup, but not placed. If the user stops dragging inside the red, the mortar goes to the
## last legal spot it passed through."
func drag_to(mouse_pos: Vector2) -> void:
	if _dragging == null:
		return
	var zone := _dragging.deployment_zone
	var candidate := Vector2(
		clamp(mouse_pos.x, zone.position.x, zone.end.x),
		clamp(mouse_pos.y, zone.position.y, zone.end.y)
	)
	if _dragging.kind == Unit.Kind.MORTAR:
		if _mortar_may_stand_at(candidate):
			_last_legal_position = candidate
		else:
			# The cursor moves in jumps: of the stretch it just covered, the latest legal point is the last place the mortar passed through.
			var from: Vector2 = _dragging.position
			for i in range(1, DRAG_LEGAL_SAMPLES + 1):
				var along: Vector2 = from.lerp(candidate, float(i) / float(DRAG_LEGAL_SAMPLES))
				if _mortar_may_stand_at(along):
					_last_legal_position = along
	_dragging.position = candidate
	_dragging.queue_redraw() # cover ring must update live as it crosses terrain


## Where the mortar token ends a drag: where the cursor left it if it may be set up there, otherwise the last legal spot it passed through.
func end_drag() -> void:
	if _dragging != null and _dragging.kind == Unit.Kind.MORTAR and not _mortar_may_stand_at(_dragging.position):
		_dragging.position = _last_legal_position
		_dragging.queue_redraw()
	_dragging = null


const DRAG_LEGAL_SAMPLES: int = 24


## The token a press at `point` picks up: the one whose centre is nearest the press, the one drawn on top (the later one) when two are
## equally near, null if none is under it. Direct user report: "It was difficult to drag my units during setup. I made multiple tries to
## click on a unit." Several tokens start within one token's width of each other (on Voznesensk the spotter sits 9-14 px from two
## squads, circles 32 px across), and the old rule took the FIRST token in the list that the press touched, so a press on the spotter
## on top (drawn last) grabbed a squad underneath it instead.
func token_at(point: Vector2) -> UnitToken:
	var best: UnitToken = null
	var best_distance := INF
	for token in _tokens:
		if not token.contains_point(point):
			continue
		var distance: float = token.position.distance_to(point)
		if distance <= best_distance:
			best = token
			best_distance = distance
	return best


## The recon asset's own zone: the ordinary spotter zone, or — for the drone
## team — that zone extended across the rear area (the west flank); see
## GameConfig.drone_team_deployment_zone.
func _recon_deployment_zone() -> Rect2:
	if recon_mode == GameConfig.ReconMode.DRONE_TEAM:
		return GameConfig.drone_team_deployment_zone()
	return GameConfig.CURRENT_MAP.player.spotter_deployment_zone


## Returns {"squad_positions": [Vector2, Vector2, Vector2], "mortar_position":
## Vector2, "spotter_position": Vector2} for BattleManager's doctrine dict.
## No resupply point any more — a resupply run now spawns at whatever edge
## of the map is currently on screen (see BattleManager.
## _resupply_entry_point_for), not a fixed pre-placed location, so there's
## nothing left for the player to set here.
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
	draw_rect(GameConfig.CURRENT_MAP.player.mortar_deployment_zone, Color(1.0, 0.55, 0.15, 0.5), false, 2.0)
	draw_rect(GameConfig.CURRENT_MAP.player.deployment_zone, Color(1.0, 1.0, 0.2, 0.7), false, 2.0)
	draw_rect(_recon_deployment_zone(), Color(0.3, 1.0, 1.0, 0.6), false, 2.0)
	# The ground the mortar will not go (within 200 m of a populated place) is shown only while the mortar is being
	# placed — direct user request: "The red can be visible only when setting up the mortar."
	if _dragging != null and _dragging.kind == Unit.Kind.MORTAR and not GameConfig.mortar_exclusion_rects().is_empty():
		GameConfig.draw_mortar_exclusion(self)
		var font: Font = ThemeDB.fallback_font
		var at := Vector2(-GameConfig.WEST_FLANK_WIDTH_PX + 12.0, 22.0)
		var text := "Red: the mortar will not go within 200 m of a populated place"
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(1.0, 1.0, 1.0, 0.9))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.05, 0.05))
