extends Node2D
## A tiny, dedicated draw layer for HUD elements that must appear ON TOP
## of the map itself (the scale bar, the compass rose) — added as a CHILD
## of main.gd, but specifically AFTER map_container (the SubViewportContainer
## holding the actual battle map), so Godot's own child-draws-after-parent
## compositing puts this content above the map instead of underneath it.
##
## A real, previously-undiscovered bug this fixes: this content used to
## live directly in main.gd's own _draw() — but main.gd IS the parent of
## map_container, and a CanvasItem's own _draw() output always renders
## BEFORE its children (that's what "child draws on top of parent"
## means), so the scale bar and compass were being drawn, then immediately
## painted over by the entire map viewport's own content on top — genuinely
## invisible on screen the whole time, not merely subtle. Reported
## directly: "please put a scale onto the map" from a player who had no
## way to know one already existed in the code.

func _draw() -> void:
	var bar_m := 1000.0
	var bar_px: float = bar_m * GameConfig.PIXELS_PER_METER
	var origin := Vector2(GameConfig.CAMERA_VIEWPORT_WIDTH_PX - 20.0 - bar_px, 34.0) # below main.gd's own _clock_label, which sits at y=4
	draw_line(origin, origin + Vector2(bar_px, 0.0), Color.WHITE, 2.0)
	draw_line(origin, origin + Vector2(0.0, 6.0), Color.WHITE, 2.0)
	draw_line(origin + Vector2(bar_px, 0.0), origin + Vector2(bar_px, 6.0), Color.WHITE, 2.0)
	draw_string(ThemeDB.fallback_font, origin + Vector2(0.0, 20.0), "%d m" % int(bar_m),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

	var compass_center := Vector2(GameConfig.CAMERA_VIEWPORT_WIDTH_PX - 50.0, GameConfig.MAP_HEIGHT_PX - 50.0)
	var compass_radius := 26.0
	var north_dir: Vector2 = GameConfig.CURRENT_MAP.compass_north_screen_direction
	draw_arc(compass_center, compass_radius, 0.0, TAU, 32, Color(1, 1, 1, 0.7), 1.5, true)
	var north_tip: Vector2 = compass_center + north_dir * compass_radius
	draw_line(compass_center, north_tip, Color(1.0, 0.85, 0.2), 2.0)
	draw_string(ThemeDB.fallback_font, north_tip + north_dir * 10.0 - Vector2(5, -5), "N",
		HORIZONTAL_ALIGNMENT_CENTER, -1, 13, Color(1.0, 0.85, 0.2))
