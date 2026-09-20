extends Control
class_name DeploymentMagnifier
## A "loupe" overlay shown while dragging a deployment token: a fixed,
## clipped screen-space window (top-left corner of the map, over the
## sidebar-free left part of the screen) that redraws the real terrain
## around the token's CURRENT position at real magnification, with the
## token itself drawn small and semi-transparent so the ground underneath
## stays legible — the token's own on-map circle (UnitToken.RADIUS = 16,
## nearly opaque) is exactly what made precise placement hard to judge in
## the first place; this exists specifically so it doesn't repeat that
## mistake at a smaller scale.
##
## Deliberately its own from-scratch draw (GameConfig.draw_terrain again,
## plus a lightweight hand-drawn token marker) rather than a second Camera2D
## sharing the main map's World2D: a shared-world camera would zoom the
## SAME UnitToken node the main view already draws, scaling its circle UP
## right along with the terrain — the opposite of "smaller and more
## transparent" this feature exists to provide. main.gd owns showing/
## hiding this and keeping focus_position/unit_kind in sync with whichever
## token DeploymentScreen currently has in `_dragging` — see its own
## _process.

const WINDOW_SIZE: Vector2 = Vector2(200, 200)
const ZOOM: float = 4.0
const TOKEN_RADIUS: float = UnitToken.RADIUS * 0.5
const TOKEN_ALPHA: float = 0.55

const TerrainLayerScript = preload("res://scripts/terrain_layer.gd")

var focus_position: Vector2 = Vector2.ZERO
var unit_kind: Unit.Kind = Unit.Kind.SQUAD

## The whole map's terrain, drawn ONCE (see terrain_layer.gd) at ZOOM x and
## then just moved each frame so the focus sits at the window's center —
## this used to be re-drawn from scratch on every frame the loupe was shown
## (main.gd asks for a redraw every frame while a token is selected), which
## rebuilt every contour segment, building and tree: ~10ms on the older maps
## and ~67ms on a real-data one, the reported "a second to follow my drag".
var _terrain: Node2D
var _overlay: Control


## The token marker, cover ring, crosshair and border — the only parts that
## change frame to frame, and cheap. A child drawn AFTER the terrain layer
## so it sits on top (a Control's own _draw runs before its children's).
class Overlay extends Control:
	var magnifier: Control
	func _draw() -> void:
		magnifier.draw_overlay(self)


func _init() -> void:
	custom_minimum_size = WINDOW_SIZE
	size = WINDOW_SIZE
	clip_contents = true # the whole reason this is a Control, not a bare Node2D — terrain drawn at 4x would otherwise spill past the window's own edges
	_terrain = TerrainLayerScript.new()
	_terrain.scale = Vector2(ZOOM, ZOOM)
	add_child(_terrain)
	_overlay = Overlay.new()
	_overlay.magnifier = self
	_overlay.size = WINDOW_SIZE
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, WINDOW_SIZE), Color(0.05, 0.05, 0.05, 1.0))
	# Re-centers the (already drawn) terrain on the focus — a transform
	# change, not a redraw.
	_terrain.position = WINDOW_SIZE / 2.0 - focus_position * ZOOM
	_overlay.queue_redraw()


func draw_overlay(ci: CanvasItem) -> void:
	var center: Vector2 = WINDOW_SIZE / 2.0

	# The token itself, small and translucent — real placement precision
	# comes from the zoomed TERRAIN underneath, not from the marker, which
	# only needs to be legible enough to confirm "yes, this is the unit
	# I'm placing," not to dominate the view the way its full-size, near-
	# opaque on-map circle does.
	var color := Color(0.25, 0.55, 1.0, TOKEN_ALPHA)
	if unit_kind == Unit.Kind.SPOTTER or unit_kind == Unit.Kind.DRONE_TEAM:
		color = Color(0.75, 0.9, 0.2, TOKEN_ALPHA)
	ci.draw_circle(center, TOKEN_RADIUS, color)
	if unit_kind == Unit.Kind.MORTAR:
		ci.draw_circle(center, TOKEN_RADIUS * 0.45, Color(0.0, 0.0, 0.0, TOKEN_ALPHA))
	elif unit_kind == Unit.Kind.SPOTTER or unit_kind == Unit.Kind.DRONE_TEAM:
		ci.draw_circle(center, TOKEN_RADIUS * 0.4, Color(0.1, 0.1, 0.1, TOKEN_ALPHA))
		ci.draw_circle(center, TOKEN_RADIUS * 0.18, Color(1.0, 1.0, 1.0, TOKEN_ALPHA))
	GameConfig.draw_cover_ring(ci, TOKEN_RADIUS, GameConfig.get_terrain_type_at(focus_position), center)

	# A thin crosshair pinpoints the exact placement point independently of
	# the token marker's own visual weight, however small/transparent —
	# "exactly where I am putting the unit" is a single point, not a blob.
	var crosshair_color := Color(1.0, 1.0, 1.0, 0.85)
	ci.draw_line(center - Vector2(6, 0), center + Vector2(6, 0), crosshair_color, 1.0)
	ci.draw_line(center - Vector2(0, 6), center + Vector2(0, 6), crosshair_color, 1.0)

	ci.draw_rect(Rect2(Vector2.ZERO, WINDOW_SIZE), Color(1.0, 1.0, 1.0, 0.6), false, 2.0)
