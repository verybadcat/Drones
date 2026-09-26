class_name DeploymentPhase
extends GameScreen
## The deployment screen: the player drags the units into position on the map
## (DeploymentScreen, in the map's SubViewport), optionally sets the battle seed (DoctrinePanel, in
## the sidebar) and presses "Start Battle", which hands the whole thing on as one doctrine
## dictionary (start_requested) — this screen builds it, the battle screen acts on it. A
## loupe (deployment_magnifier.gd) shows the placement being dragged.
##
## main.gd sets `recon_mode` and `map_viewport` BEFORE adding this to the tree.

signal start_requested(doctrine: Dictionary)

var recon_mode: GameConfig.ReconMode = GameConfig.ReconMode.SPOTTER
var map_viewport: SubViewport

var deployment_screen: DeploymentScreen
var doctrine_panel: DoctrinePanel
var start_button: Button
# Loupe overlay shown while dragging a deployment token — see deployment_magnifier.gd's
# own doc comment. Screen-space, so a child of this screen rather than of the map's
# SubViewport: it has to sit in a fixed screen position regardless of the map's own
# (fixed, but separately-scaled) inner camera. Untyped for the brand-new-class_name
# reason (a static type reference isn't resolvable until the editor has rebuilt its
# class cache, which a plain run never triggers).
var deployment_magnifier
# Whichever token the magnifier showed most recently — kept so the loupe can stay on
# screen showing that placement after the drag ends, instead of vanishing the instant the
# player lets go (see _process).
var _magnifier_last_token: UnitToken = null


func _ready() -> void:
	super()
	deployment_screen = DeploymentScreen.new()
	deployment_screen.recon_mode = recon_mode
	add_map_node(map_viewport, deployment_screen)

	deployment_magnifier = preload("res://scripts/deployment_magnifier.gd").new()
	# Top RIGHT of the map, just below the clock and the scale bar
	# (map_hud_overlay.gd draws that at y=34, label to ~y=58): the drone
	# team can now deploy across the whole west rear area, so the old
	# top-left spot sat right on top of where it needs to go.
	deployment_magnifier.position = Vector2(GameConfig.CAMERA_VIEWPORT_WIDTH_PX - deployment_magnifier.WINDOW_SIZE.x - 8.0, 64.0)
	deployment_magnifier.visible = false
	add_child(deployment_magnifier)

	doctrine_panel = DoctrinePanel.new()
	doctrine_panel.position = Vector2(GameConfig.SIDEBAR_X, 20)
	add_child(doctrine_panel)

	start_button = Button.new()
	start_button.text = "Start Battle"
	start_button.position = Vector2(GameConfig.SIDEBAR_X, 20.0 + DoctrinePanel.PANEL_HEIGHT + 10.0) # just under the panel
	start_button.pressed.connect(request_start)
	add_child(start_button)


func map_mouse_world_position() -> Vector2:
	return deployment_screen.get_global_mouse_position() if deployment_screen else Vector2.ZERO


## Stays on screen through the whole setup phase, not just while a token is actively being
## dragged — showing whichever token was placed most recently, so the player can keep
## checking a placement after letting go instead of the loupe vanishing the instant they
## release the mouse. DeploymentScreen's own _dragging is the single source of truth for an
## in-progress drag; _magnifier_last_token carries that over once the drag ends. Nothing to
## show at all until the first token is ever dragged.
func _process(_delta: float) -> void:
	if deployment_magnifier == null:
		return
	var dragging: UnitToken = deployment_screen._dragging if deployment_screen else null
	if dragging != null:
		_magnifier_last_token = dragging
	var shown: UnitToken = dragging if dragging != null else _magnifier_last_token
	deployment_magnifier.visible = shown != null
	if shown != null:
		deployment_magnifier.focus_position = shown.position
		deployment_magnifier.unit_kind = shown.kind
		deployment_magnifier.queue_redraw()


## "Start Battle": gathers the placements and the doctrine into the one dictionary the
## battle is started from, and hands it on.
func request_start() -> void:
	start_requested.emit(build_doctrine())


## The dictionary the battle is started from (see request_start). Separate so a test can start
## a battle from a doctrine the setup screen has no controls for any more.
func build_doctrine() -> Dictionary:
	var positions := deployment_screen.get_positions()
	# One standing order for the whole force, not a separately dialed-in
	# threshold per squad — see DoctrinePanel.get_retreat_threshold's own
	# doc comment for the real-command-authority reasoning behind this.
	var retreat_threshold := doctrine_panel.get_retreat_threshold()

	var squads: Array[Dictionary] = []
	for pos in positions.squad_positions:
		squads.append({
			"position": pos,
			"retreat_threshold": retreat_threshold,
		})

	var mortar_doctrine := doctrine_panel.get_mortar_doctrine()
	mortar_doctrine["position"] = positions.mortar_position

	var doctrine := {
		"squads": squads,
		"mortar": mortar_doctrine,
		"spotter": {"position": positions.spotter_position},
		"recon_mode": recon_mode,
	}

	doctrine.merge(doctrine_panel.get_commander_doctrine())
	return doctrine
