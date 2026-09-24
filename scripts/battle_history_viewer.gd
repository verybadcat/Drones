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
##
## Two ways to move through it: manual scrubbing (main.gd's slider calls
## set_index) or the "Play" button (main.gd calls toggle_play, then ticks
## advance_playback every frame) — see GameConfig.HISTORY_PLAYBACK_TIME_
## SCALE for the replay pace. playback_time is the single source of truth
## for "what moment is currently displayed" either way; set_index just
## snaps it to a recorded snapshot's exact time and pauses.

var history: Array[Dictionary] = []
var fire_events: Array[Dictionary] = []
var current_index: int = 0
var playback_time: float = 0.0
var is_playing: bool = false


func setup(p_history: Array[Dictionary], p_fire_events: Array[Dictionary]) -> void:
	history = p_history
	fire_events = p_fire_events
	current_index = history.size() - 1 # start at the battle's final moment
	playback_time = history[current_index].time if not history.is_empty() else 0.0
	is_playing = false
	queue_redraw()


func set_index(i: int) -> void:
	current_index = clampi(i, 0, history.size() - 1)
	if not history.is_empty():
		playback_time = history[current_index].time
	is_playing = false # a manual scrub pauses playback, same as any video player's seek bar
	queue_redraw()


## Toggles Play/Pause. Restarts from the beginning if pressed while already
## sitting at the final moment — otherwise "Play" at the end would do
## nothing, which isn't what pressing it clearly means.
func toggle_play() -> void:
	if history.is_empty():
		return
	if is_playing:
		is_playing = false
		return
	if current_index >= history.size() - 1:
		current_index = 0
		playback_time = history[0].time
	is_playing = true


## Called every frame from main.gd's own _process while is_playing.
## delta_real is real engine seconds, same as any other _process delta —
## converted to tactical time at the replay's own fixed pace (unrelated to
## whatever time scale was actually in effect during the live battle, which
## varied and wasn't recorded per snapshot).
func advance_playback(delta_real: float) -> void:
	if not is_playing or history.is_empty():
		return
	playback_time += delta_real * GameConfig.HISTORY_PLAYBACK_TIME_SCALE
	var last_time: float = history[-1].time
	if playback_time >= last_time:
		playback_time = last_time
		current_index = history.size() - 1
		is_playing = false
	else:
		current_index = _index_for_time(playback_time)
	queue_redraw()


## Largest index whose recorded time is <= t (binary search — history can
## run to a couple thousand entries for a long battle at HISTORY_SNAPSHOT_
## INTERVAL_S, called once per frame during playback).
func _index_for_time(t: float) -> int:
	var lo := 0
	var hi := history.size() - 1
	while lo < hi:
		var mid: int = (lo + hi + 1) / 2
		if history[mid].time <= t:
			lo = mid
		else:
			hi = mid - 1
	return lo


func current_time() -> float:
	return playback_time


## Ground-truth casualty pip counts for `team` at the snapshot CURRENTLY
## displayed (current_index) — for CasualtyDashboard's own casualties bar
## while scrubbing/playing this replay, so it reads "what were casualties
## at this moment" instead of the live battle's final, frozen totals. Mirrors
## BattleManager._compute_side_stats' own ground-truth math (a DRONE is
## equipment, not personnel; a RESUPPLY_RUN is a transient logistics
## element; neither counts. A SURRENDERED unit's still-intact `pips` count
## as an extra loss on top of whatever it had already taken, since
## surrendering itself doesn't reduce `pips`) but reads it from this
## viewer's own recorded snapshot fields rather than live Unit state —
## ground truth for BOTH sides, same as every other reading in this file,
## not the fog-of-war-limited "estimated" view the live dashboard's enemy
## side otherwise shows (see this file's own doc comment on why that's a
## deliberate, confirmed difference for this feature specifically).
func casualty_pips_at_current_index(team: Unit.Team) -> Dictionary:
	var pips_total := 0
	var pips_lost := 0
	var captured := 0
	if not history.is_empty():
		for u in history[current_index].units:
			if u.team != team:
				continue
			if u.kind == Unit.Kind.DRONE or u.kind == Unit.Kind.RESUPPLY_RUN:
				continue
			var max_pips: int = u.get("max_pips", 0)
			var pips: int = u.get("pips", 0)
			pips_total += max_pips
			pips_lost += max_pips - pips
			if u.state == Unit.State.SURRENDERED:
				pips_lost += pips
				captured += pips # same "captured is captured" fold-in as BattleManager._compute_side_stats
	var casualty_percent: float = (float(pips_lost) / float(pips_total) * 100.0) if pips_total > 0 else 0.0
	return {"pips_total": pips_total, "pips_lost": pips_lost, "casualty_percent": casualty_percent, "estimated": false, "captured": captured}


## The recorded status views (BattleManager.mortar_status_view) of `team`'s
## mortars at the snapshot currently displayed — for CasualtyDashboard's mortar
## rows during replay, so ammunition, crew and resupply read as they were at
## this moment rather than as the battle ended. Ground truth, like everything
## else in this viewer.
func mortar_views_at_current_index(team: Unit.Team) -> Array[Dictionary]:
	var views: Array[Dictionary] = []
	if history.is_empty():
		return views
	for u in history[current_index].units:
		if u.team == team and u.kind == Unit.Kind.MORTAR and u.has("mortar"):
			views.append(u.mortar)
	return views


## The drone fleet status (BattleManager.drone_fleet_status) recorded at the
## snapshot currently displayed; {} if none was recorded (not the drone-team
## recon mode).
func drone_fleet_at_current_index() -> Dictionary:
	if history.is_empty():
		return {}
	return history[current_index].get("drone_fleet", {})


func _draw() -> void:
	if history.is_empty():
		return
	for u in history[current_index].units:
		_draw_unit(u)
	for f in fire_events:
		_draw_fire_event(f)


## A self-contained echo of Unit._draw()'s own full visual language,
## offset by each unit's own recorded `pos` instead of relying on a
## per-unit node's own local origin (this is one shared node drawing
## every unit in a single _draw() call) — labels, sub-icon detail, the
## cover ring, and the strength bar all included now, so a replay looks
## the same as the live game modulo controls, per the user's own explicit
## ask, not just a same-color blob standing in for each unit. Terrain for
## the cover ring is looked up fresh from `pos` (see _record_history_
## snapshot's own doc comment for why that's not snapshotted). Still
## deliberately NOT the is_visible-based hiding Unit._draw() also does,
## since this view is unconditional ground truth by design.
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

	draw_string(ThemeDB.fallback_font, pos + Vector2(-24, 29), u.get("unit_label", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color.lightened(0.3))

	var radius := 14.0 if kind == Unit.Kind.SQUAD else (8.0 if (kind == Unit.Kind.SPOTTER or kind == Unit.Kind.DRONE_TEAM) else (6.0 if kind == Unit.Kind.RESUPPLY_RUN else (5.0 if kind == Unit.Kind.DRONE else 10.0)))
	if kind == Unit.Kind.RESUPPLY_RUN:
		draw_rect(Rect2(pos - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)), color)
	else:
		draw_circle(pos, radius, color)

	if kind == Unit.Kind.MORTAR:
		draw_circle(pos, radius * 0.45, Color.BLACK)
	elif kind == Unit.Kind.SPOTTER or kind == Unit.Kind.DRONE_TEAM:
		draw_circle(pos, radius * 0.4, Color(0.1, 0.1, 0.1))
		draw_circle(pos, radius * 0.18, Color.WHITE)
	elif kind == Unit.Kind.DRONE:
		draw_line(pos + Vector2(-radius, -radius), pos + Vector2(radius, radius), Color(0.15, 0.15, 0.15), 1.5)
		draw_line(pos + Vector2(-radius, radius), pos + Vector2(radius, -radius), Color(0.15, 0.15, 0.15), 1.5)

	if state == Unit.State.WITHDRAWN or state == Unit.State.DESTROYED or state == Unit.State.SURRENDERED:
		return

	GameConfig.draw_cover_ring(self, radius, GameConfig.get_terrain_type_at(pos), pos)

	var bar_width := 28.0
	var bar_y := pos.y - radius - 10.0
	draw_rect(Rect2(pos.x - bar_width / 2.0, bar_y, bar_width, 4.0), Color(0.15, 0.15, 0.15))
	var max_pips: int = u.get("max_pips", 0)
	if max_pips > 0:
		var filled_width: float = bar_width * (float(u.get("pips", 0)) / float(max_pips))
		draw_rect(Rect2(pos.x - bar_width / 2.0, bar_y, filled_width, 4.0), Color(0.2, 0.9, 0.3))


## A self-contained echo of BattleManager._draw()'s own fire-flash
## rendering, keyed on playback_time (tactical) rather than elapsed_time
## (real) — see fire_events' own doc comment on BattleManager for why a
## separate recording was needed rather than reusing the live _fire_flashes
## list. Shows regardless of whether currently playing, so scrubbing the
## slider to land near a shot's moment shows it too, not just Play.
func _draw_fire_event(f: Dictionary) -> void:
	var age: float = playback_time - f.time
	if age < 0.0 or age > GameConfig.HISTORY_FIRE_FLASH_DURATION_TACTICAL_S:
		return
	var alpha: float = 1.0 - age / GameConfig.HISTORY_FIRE_FLASH_DURATION_TACTICAL_S
	var color: Color = Color(1.0, 0.85, 0.2, alpha) if f.team == Unit.Team.ENEMY else Color(0.3, 0.85, 1.0, alpha)
	if f.is_mortar:
		_draw_arc_tracer(f.from, f.to, color)
	else:
		draw_line(f.from, f.to, color, 2.0)
	draw_circle(f.from, 5.0, Color(1.0, 1.0, 0.6, alpha))


func _draw_arc_tracer(from: Vector2, to: Vector2, color: Color) -> void:
	var apex: Vector2 = (from + to) / 2.0 - Vector2(0.0, from.distance_to(to) * 0.2)
	var points := PackedVector2Array()
	var segments := 12
	for i in segments + 1:
		var t: float = float(i) / float(segments)
		var one_minus_t: float = 1.0 - t
		points.append(from * (one_minus_t * one_minus_t) + apex * (2.0 * one_minus_t * t) + to * (t * t))
	draw_polyline(points, color, 2.0, true)
