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
	_draw_weather(compass_center)


## Wind and precipitation, in a block just left of the compass: an arrow
## pointing the way the wind BLOWS (longer = stronger), the speed, the
## temperature and gusts,
## and — only while it is actually happening — a rain/sleet/snow icon and
## label. A line says when the drones are grounded by it.
func _draw_weather(compass_center: Vector2) -> void:
	var w: Weather = Weather.current
	if w == null:
		return
	var font := ThemeDB.fallback_font
	var white := Color(1, 1, 1, 0.85)
	var accent := Color(0.55, 0.85, 1.0)
	var wind_center := compass_center - Vector2(150.0, 0.0)
	draw_arc(wind_center, 26.0, 0.0, TAU, 32, Color(1, 1, 1, 0.35), 1.0, true)
	var toward: Vector2 = w.wind_velocity_mps(10.0, false).normalized()
	var arrow_len: float = clampf(6.0 + 2.6 * w.wind_speed_10m, 8.0, 24.0)
	var tail: Vector2 = wind_center - toward * arrow_len
	var head: Vector2 = wind_center + toward * arrow_len
	draw_line(tail, head, accent, 2.5)
	var side: Vector2 = toward.orthogonal()
	draw_line(head, head - toward * 7.0 + side * 4.5, accent, 2.5)
	draw_line(head, head - toward * 7.0 - side * 4.5, accent, 2.5)
	draw_string(font, wind_center + Vector2(-44.0, 44.0), "%d m/s from %s, %s" % [roundi(w.wind_speed_10m), Weather.compass_name(w.wind_from_deg), w.temperature_label()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, white)
	draw_string(font, wind_center + Vector2(-44.0, 58.0), "gusts %d, aloft %d" % [roundi(w.wind_speed_10m * Weather.WIND_GUST_RATIO_PEAK), roundi(w.wind_speed_at(300.0))],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, white)

	if w.is_precipitating():
		var label_origin := wind_center + Vector2(-44.0, -36.0)
		_draw_precip_icon(label_origin + Vector2(-6.0, -4.0), w.precip_type())
		draw_string(font, label_origin + Vector2(10.0, 0.0), "%s (%.1f mm/h)" % [w.precip_label(), w.precip_mm_h],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, accent)
		if w.drone_vision_blocked():
			draw_string(font, label_origin + Vector2(0.0, -16.0), "Drones grounded — cannot see", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.6, 0.4))


func _draw_precip_icon(at: Vector2, kind: int) -> void:
	var accent := Color(0.55, 0.85, 1.0)
	if kind == Weather.Precip.SNOW:
		for angle in [0.0, PI / 3.0, 2.0 * PI / 3.0]:
			var d := Vector2.from_angle(angle) * 6.0
			draw_line(at - d, at + d, Color.WHITE, 1.5)
	else:
		for i in 3:
			var x: float = at.x - 4.0 + 4.0 * i
			draw_line(Vector2(x + 2.0, at.y - 6.0), Vector2(x - 1.0, at.y + 5.0), accent if kind == Weather.Precip.RAIN else Color(0.75, 0.85, 1.0), 1.5)
