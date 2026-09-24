extends PanelContainer
class_name CasualtyDashboard
## Prominent, always-current readout for both sides during a battle — pips
## lost/total with a percentage bar, AND a mortar status row of equal visual
## weight (same text size, its own colored status bar) right below it. A
## mortar's own casualty model (an exact crew headcount, abandon-the-gun-
## on-any-hit) is otherwise easy to lose track of alongside the squads' own
## pip losses in the same aggregate number — it gets equal billing here, not
## a smaller, dimmer afterthought. In ReconMode.DRONE_TEAM, a drone-fleet
## row (see _update_drone_row) gets the same treatment: airborne/ready/
## recharging counts, not just a single pip number. Updated every frame from
## BattleManager.casualty_stats()/drone_fleet_status(), the exact same data
## the AAR report is built from. This is the at-a-glance element in the
## sidebar; CombatLog below it is for scrolling back through what happened,
## not for reading the state of the battle in one look.

const BAR_SIZE: Vector2 = Vector2(280.0, 16.0)
# The player always fields exactly one mortar (see BattleManager.
# _spawn_player_units); the enemy's own count is rolled per battle (see
# GameConfig.roll_enemy_force_size) up to ENEMY_MORTAR_COUNT_MAX — read
# directly from there rather than a separate local constant, so this can
# never again silently drift out of sync with the real spawn-side maximum.
const MAX_PLAYER_MORTARS: int = 1

const STATUS_COLOR := {
	Unit.State.ACTIVE: Color(0.25, 0.85, 0.35),
	Unit.State.RETREATING: Color(1.0, 0.65, 0.15),
	Unit.State.WITHDRAWN: Color(0.6, 0.6, 0.6),
	Unit.State.DESTROYED: Color(0.75, 0.2, 0.2),
	Unit.State.SURRENDERED: Color(0.9, 0.9, 0.9),
}

## A dedicated color for an enemy mortar never yet sighted — distinct from
## every real STATUS_COLOR entry (including WITHDRAWN's own gray) so
## "we genuinely don't know" never gets mistaken for a real, confirmed
## status at a glance.
const UNKNOWN_COLOR := Color(0.35, 0.35, 0.4)

var battle_manager: BattleManager
## Set/cleared directly by main.gd exactly when Review Battle History
## opens/closes (untyped — same brand-new-class_name reason main.gd's own
## history_viewer field is untyped). While set, the two casualty bars read
## from THIS viewer's currently-scrubbed snapshot instead of the live,
## final battle_manager.casualty_stats() — see _refresh's own doc comment.
var history_viewer = null
var _player_label: RichTextLabel
var _player_bar: ColorRect
var _player_mortar_rows: Array[Dictionary] = []
var _drone_label: RichTextLabel
var _drone_bg: ColorRect
var _drone_fill: ColorRect
var _enemy_label: RichTextLabel
var _enemy_bar: ColorRect
var _enemy_mortar_rows: Array[Dictionary] = []


func setup(p_battle_manager: BattleManager) -> void:
	battle_manager = p_battle_manager


func _ready() -> void:
	# Fixed at a size that comfortably fits the COMMON case — measured
	# directly (a headless layout diagnostic, not a guess) with every row
	# showing its full worst-case text, including cases that wrap to a
	# second line at this panel's 320px width: a mortar row once its
	# status grows a resupply suffix ("in action (22 rounds, resupply ~25m
	# out)"), the drone fleet row once every one of its status components
	# is populated at once, and up to 3 known enemy mortar rows at once.
	# GameConfig.ENEMY_MORTAR_COUNT_MAX can go as high as 5 now (the
	# right-tail assault-size widening — see BattleManager.
	# roll_enemy_force_size), but a battle actually fielding 4-5 enemy
	# mortars is a rare, large-assault outcome, not the common case this
	# panel's OWN fixed footprint should be tuned to — rather than
	# growing the whole sidebar (and the window under it) to fit a worst
	# case most battles never reach, the content below scrolls internally
	# past this height instead, the same tradeoff CombatLog already makes.
	custom_minimum_size = Vector2(320, 550)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.07, 0.9)
	style.set_content_margin_all(10.0)
	style.set_corner_radius_all(4.0)
	add_theme_stylebox_override("panel", style)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	var title := GameConfig.make_selectable_label("CASUALTIES")
	title.add_theme_font_size_override("normal_font_size", 15)
	root.add_child(title)
	root.add_child(HSeparator.new())

	_player_label = GameConfig.make_selectable_label()
	root.add_child(_player_label)
	_player_bar = _build_bar(root, Color(0.3, 0.85, 1.0))
	_player_mortar_rows = _build_mortar_rows(root, MAX_PLAYER_MORTARS)

	_drone_label = GameConfig.make_selectable_label()
	root.add_child(_drone_label)
	_drone_bg = ColorRect.new()
	_drone_bg.color = Color(0.2, 0.2, 0.2)
	_drone_bg.custom_minimum_size = BAR_SIZE
	root.add_child(_drone_bg)
	_drone_fill = ColorRect.new()
	_drone_fill.size = Vector2(BAR_SIZE.x, BAR_SIZE.y)
	_drone_bg.add_child(_drone_fill)

	root.add_child(HSeparator.new())

	_enemy_label = GameConfig.make_selectable_label()
	root.add_child(_enemy_label)
	_enemy_bar = _build_bar(root, Color(1.0, 0.55, 0.15))
	_enemy_mortar_rows = _build_mortar_rows(root, GameConfig.ENEMY_MORTAR_COUNT_MAX)

	_refresh() # show correct values immediately, don't wait a frame


func _build_bar(root: VBoxContainer, fill_color: Color) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = Color(0.2, 0.2, 0.2)
	bg.custom_minimum_size = BAR_SIZE
	root.add_child(bg)
	var fill := ColorRect.new()
	fill.color = fill_color
	fill.size = Vector2(0.0, BAR_SIZE.y)
	bg.add_child(fill)
	return fill


## One row per possible mortar on a side: a label (SAME size/weight as the
## casualty label above it — no smaller, no dimmer) plus its own colored
## status bar (same size as the casualty percentage bar) instead of a raw
## percentage — green/orange/gray/red for active/fleeing/withdrawn/destroyed.
## Pre-allocated up to `max_rows` and hidden per-refresh when a side
## actually has fewer than that many KNOWN mortars right now (see
## _update_mortar_rows — for the enemy side, "known" excludes any mortar
## the player's side hasn't actually discovered yet, not just however many
## the enemy happens to field).
func _build_mortar_rows(root: VBoxContainer, max_rows: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for i in max_rows:
		var label := GameConfig.make_selectable_label()
		root.add_child(label)
		var bg := ColorRect.new()
		bg.color = Color(0.2, 0.2, 0.2)
		bg.custom_minimum_size = BAR_SIZE
		root.add_child(bg)
		var fill := ColorRect.new()
		fill.size = Vector2(BAR_SIZE.x, BAR_SIZE.y)
		bg.add_child(fill)
		rows.append({"label": label, "bg": bg, "fill": fill})
	return rows


func _process(_delta: float) -> void:
	_refresh()


## While Review Battle History is open (history_viewer set), the two
## casualty bars track wherever the replay is currently scrubbed/playing to
## instead of the live battle's final, frozen totals — direct user
## requirement: "the casualties bar should start at zero and show
## casualties as they happen [during replay]. If the user scrolls forwards
## or backwards, the casualties should show what they were at wherever the
## user scrolls to." The mortar and drone rows follow the replay too (user
## report: "When replaying the battle history, it is not updating mortar
## status ... Rounds of ammo available"; and "Consider whether the whole
## board should be in a single code path"): each snapshot records
## BattleManager.mortar_status_view / drone_fleet_status, and the board is
## built from either source into the same data (_live_board/_replay_board)
## and drawn by one _render, with one text function per row.
func _refresh() -> void:
	if battle_manager == null:
		return
	_render(_replay_board() if history_viewer != null else _live_board())


## THE board, as plain data — the one shape both providers below produce and
## _render draws: {"player"/"enemy": {"stats", "mortars": [{text, color}]},
## "drone": {"visible", "text", "color"}}. Live and replay differ only in
## where the data comes from (and, deliberately, in the enemy side's
## fog-of-war), never in how it's laid out or worded.
func _live_board() -> Dictionary:
	return {
		"player": {"stats": battle_manager.casualty_stats(Unit.Team.PLAYER), "mortars": _live_mortar_row_data(battle_manager.player_units, false)},
		"drone": _drone_row_data(battle_manager.recon_mode == GameConfig.ReconMode.DRONE_TEAM, battle_manager.drone_fleet_status()),
		"enemy": {"stats": battle_manager.casualty_stats(Unit.Team.ENEMY), "mortars": _live_mortar_row_data(battle_manager.enemy_units, true)},
	}


## The same board as recorded at the replay's current moment — ground truth for
## both sides (the replay is omniscient, like the rest of BattleHistoryViewer,
## a deliberate choice confirmed with the user), so no fog-of-war filtering
## and no "last seen" wording.
func _replay_board() -> Dictionary:
	return {
		"player": {"stats": history_viewer.casualty_pips_at_current_index(Unit.Team.PLAYER), "mortars": _replay_mortar_row_data(Unit.Team.PLAYER)},
		"drone": _drone_row_data(battle_manager.recon_mode == GameConfig.ReconMode.DRONE_TEAM, history_viewer.drone_fleet_at_current_index()),
		"enemy": {"stats": history_viewer.casualty_pips_at_current_index(Unit.Team.ENEMY), "mortars": _replay_mortar_row_data(Unit.Team.ENEMY)},
	}


func _render(board: Dictionary) -> void:
	_update_side(board.player.stats, _player_label, _player_bar, "Player")
	_apply_mortar_rows(_player_mortar_rows, board.player.mortars)
	_apply_drone_row(board.drone)
	_update_side(board.enemy.stats, _enemy_label, _enemy_bar, "Enemy")
	_apply_mortar_rows(_enemy_mortar_rows, board.enemy.mortars)


## `stats.estimated` (see BattleManager._compute_side_stats) marks the
## player's own fog-of-war view of the enemy — shown with a "~"/"estimated"
## qualifier so it never reads as an authoritative figure the way the
## player's own, always-fully-known casualty line does.
func _update_side(stats: Dictionary, label: RichTextLabel, bar: ColorRect, side_name: String) -> void:
	# `pips_lost` folds captured personnel in with real combat casualties
	# (see _compute_side_stats's own doc comment on why: a surrendered
	# unit's `pips` are never reduced by fire, so its whole remaining
	# strength has to be added in explicitly, or it would look like it
	# suffered nothing) — a direct, reported point of confusion, since
	# nothing on this line said so ("How can we have taken 16 casualties
	# when the damage by unit shows [7]?" — the other 9 were a surrendered
	# squad). Only mentioned when it's actually nonzero — no "0 captured"
	# noise on the ordinary battle that never has any.
	var captured_suffix: String = ", %d captured" % stats.captured if stats.captured > 0 else ""
	if stats.get("estimated", false):
		label.text = "%s: ~%d/%d personnel lost (~%.0f%%%s)" % [side_name, stats.pips_lost, stats.pips_total, stats.casualty_percent, captured_suffix]
	else:
		label.text = "%s: %d/%d personnel lost (%.0f%%%s)" % [side_name, stats.pips_lost, stats.pips_total, stats.casualty_percent, captured_suffix]
	var frac: float = clamp(stats.casualty_percent / 100.0, 0.0, 1.0)
	bar.size = Vector2(BAR_SIZE.x * frac, BAR_SIZE.y)


## `units` is the whole side's roster (player_units or enemy_units); only
## MORTAR-kind ones are pulled out. For the ENEMY side specifically, a
## mortar the player's side hasn't actually discovered yet — never sighted
## (Unit.player_has_been_sighted, set by _refresh_visibility for ANY
## player-side observer that spots it, a drone's own detection included,
## not just ground-unit LOS) and never even caught firing once
## (BattleManager.mortar_ever_detected_firing) — is dropped entirely
## rather than shown as an "unknown" row: the row's mere presence would
## itself reveal that a mortar exists there, exactly the omniscience this
## dashboard otherwise avoids for the enemy side. The player's own mortar
## needs no such filter — there's no fog of war on your own units.
func _live_mortar_row_data(units: Array[Unit], is_enemy: bool) -> Array[Dictionary]:
	var data: Array[Dictionary] = []
	for u in units:
		if u.kind != Unit.Kind.MORTAR:
			continue
		if is_enemy and not u.player_has_been_sighted and not battle_manager.mortar_ever_detected_firing(u):
			continue
		var color: Color
		if u.team != Unit.Team.PLAYER and not u.player_has_been_sighted:
			# Detected firing without ever being sighted still reads as
			# genuinely "in action" (green) — only a mortar with neither a
			# sighting nor a recent fire detection is a true unknown (gray).
			color = STATUS_COLOR[Unit.State.ACTIVE] if battle_manager.mortar_recently_detected_firing(u) else UNKNOWN_COLOR
		else:
			color = STATUS_COLOR[u.player_known_state if u.team != Unit.Team.PLAYER else u.state]
		data.append({"text": "Mortar: %s" % _mortar_status_text(u), "color": color})
	return data


## Replay rows: every mortar of `team` as recorded at the current moment,
## worded by _mortar_view_text — the same text function the live player row uses.
func _replay_mortar_row_data(team: Unit.Team) -> Array[Dictionary]:
	var data: Array[Dictionary] = []
	for view in history_viewer.mortar_views_at_current_index(team):
		data.append({"text": "Mortar: %s" % _mortar_view_text(view), "color": STATUS_COLOR[view.state]})
	return data


## Shows `data` ({text, color} per row, in order) on the pre-allocated rows and
## hides the rest.
func _apply_mortar_rows(rows: Array[Dictionary], data: Array[Dictionary]) -> void:
	for i in rows.size():
		var row: Dictionary = rows[i]
		var label: RichTextLabel = row.label
		var bg: ColorRect = row.bg
		if i >= data.size():
			label.visible = false
			bg.visible = false
			continue
		label.visible = true
		bg.visible = true
		label.text = data[i].text
		var fill: ColorRect = row.fill
		fill.color = data[i].color


## A mortar's own casualty model (an exact crew headcount) does feed into
## the aggregate pip bar above (see Unit.setup's max_pips = crew_size), but
## the exact headcount and WHY it's out of action (abandoned vs. destroyed
## outright) is otherwise buried in that one aggregate number — spelled out
## here instead. Says "casualties," not "killed" — a crew hit produces a real
## mix of killed/wounded same as a squad's does (see Unit.
## _apply_crew_casualties), so labeling the live, at-a-glance readout
## "killed" would overstate it; the AAR breaks the mix down properly once
## the battle's over (see BattleManager._crew_survivor_label/
## _compute_side_stats).
func _mortar_status_text(u: Unit) -> String:
	if u.team != Unit.Team.PLAYER:
		return _enemy_mortar_status_text(u)
	return _mortar_view_text(battle_manager.mortar_status_view(u))


## A mortar's status from its plain-data view (BattleManager.mortar_status_view
## — live for the board, recorded per moment for the history replay). The one
## place this wording lives.
func _mortar_view_text(view: Dictionary) -> String:
	match view.state:
		Unit.State.ACTIVE:
			return "in action (%s%s)" % [GameConfig.round_count_text(view.rounds), _resupply_status_suffix(view.resupply)]
		Unit.State.RETREATING:
			if view.gun_abandoned:
				return "abandoned, crew fleeing (%d/%d crew casualties)" % [view.crew_casualties, view.crew_size]
			return "falling back with the gun" if view.crew_casualties == 0 else "falling back with the gun (%d/%d crew casualties)" % [view.crew_casualties, view.crew_size]
		Unit.State.WITHDRAWN:
			return "withdrew safely" if view.crew_casualties == 0 else "withdrew (%d/%d crew casualties)" % [view.crew_casualties, view.crew_size]
		Unit.State.DESTROYED:
			return "destroyed (%d/%d crew casualties)" % [view.crew_casualties, view.crew_size]
	return ""


## The enemy mortar's row shows the PLAYER's own last-known picture of it
## (Unit.player_known_state/_known_pips/_has_been_sighted — see
## BattleManager._update_player_intel), never its true live state. Never
## actually sighted at all reads as genuine "status unknown" — UNLESS it's
## fired recently enough to be caught by muzzle-flash/trajectory detection
## (BattleManager.mortar_recently_detected_firing), the same mechanism the
## enemy's own counter-battery chase already relies on to find the
## friendly mortar without ever seeing it: a mortar that's shooting at you
## is obviously "in action" whether or not anyone's laid eyes on it, even
## though firing alone reveals nothing about its remaining strength — no
## casualty count gets attached to that case. Once actually sighted, crew
## casualties are derived from the known-pips snapshot (crew_size -
## known_pips), not the live crew_casualties field, and can be nonzero even
## while ACTIVE now that a wounded crew may hold its position instead of
## automatically abandoning the gun (see Unit._apply_crew_casualties) —
## "last seen" framing throughout, since none of this is live, unlike the
## player's own mortar row above.
func _enemy_mortar_status_text(u: Unit) -> String:
	if not u.player_has_been_sighted:
		if battle_manager.mortar_recently_detected_firing(u):
			var minutes_ago: float = battle_manager.mortar_minutes_since_detected_firing(u)
			return "in action (detected firing ~%dm ago)" % int(round(minutes_ago))
		return "status unknown"
	var known_crew_casualties: int = u.crew_size - u.player_known_pips
	match u.player_known_state:
		Unit.State.ACTIVE:
			return "in action" if known_crew_casualties == 0 else "in action (%d/%d, last seen)" % [known_crew_casualties, u.crew_size]
		Unit.State.RETREATING:
			if u.mortar_gun_abandoned:
				return "fleeing, gun abandoned (%d/%d)" % [known_crew_casualties, u.crew_size]
			return "falling back with the gun (%d/%d)" % [known_crew_casualties, u.crew_size]
		Unit.State.WITHDRAWN:
			return "withdrew safely" if known_crew_casualties == 0 else "withdrew (%d/%d)" % [known_crew_casualties, u.crew_size]
		Unit.State.DESTROYED:
			# Always crew_size/crew_size once DESTROYED (see Unit._apply_
			# crew_casualties) — showing the count would just repeat the
			# word "destroyed" in numbers, so it's dropped here entirely.
			return "confirmed destroyed"
	return ""


## Right next to the rounds count, per the request — the same live status
## (BattleManager.mortar_resupply_status) that drives the actual sliding-
## scale hold-fire decision (_mortar_resupply_urgency), so what the player
## sees here always matches why the mortar is or isn't holding fire on a
## squad right now. Empty string (no suffix at all) when nothing's pending,
## so a mortar that's never requested resupply doesn't clutter its own row.
func _resupply_status_suffix(status: Dictionary) -> String:
	if not status.pending:
		return ""
	if status.in_transit:
		return ", resupply run en route"
	if status.get("staged", false):
		return ", resupply staged, ready when needed"
	return ", resupply ~%dm out" % int(round(float(status.minutes_until_next)))


## Airframe (airborne/inbound/ready/swapping/grounded/lost) and battery
## (spare/recharging) status for the drone fleet, with the same visual
## weight as the mortar row above — only shown in ReconMode.DRONE_TEAM
## (hidden entirely otherwise). If the ground team itself is out of action,
## that takes over the row instead (no fleet to report on without a team to
## fly it — see BattleManager._update_drone_operations).
func _drone_row_data(using_drones: bool, status: Dictionary) -> Dictionary:
	if not using_drones or status.is_empty():
		return {"visible": false, "text": "", "color": Color.WHITE}
	if not status.team_active:
		return {"visible": true, "color": STATUS_COLOR[status.team_state], "text": "Drone team: %s (%d/%d crew casualties)" % [
			_team_state_text(status.team_state), status.team_crew_casualties, status.team_crew_size
		]}
	var parts: PackedStringArray = []
	parts.append("1 airborne (%d%% charge)" % int(round(status.airborne_charge * 100.0)) if status.airborne else "NONE AIRBORNE")
	if status.backup:
		parts.append("1 backup (%d%% charge)" % int(round(status.backup_charge * 100.0)))
	if status.inbound > 0:
		parts.append("%d inbound" % status.inbound)
	if status.ready > 0:
		parts.append("%d ready (best %d%%)" % [status.ready, int(round(status.ready_best_charge * 100.0))])
	else:
		parts.append("0 ready")
	if status.swapping > 0:
		parts.append("%d swapping battery" % status.swapping)
	if status.spare_batteries > 0:
		parts.append("%d spare batteries (best %d%%)" % [status.spare_batteries, int(round(status.spare_best_charge * 100.0))])
	if status.destroyed > 0:
		parts.append("%d lost" % status.destroyed)
	return {"visible": true, "text": "Drones: %s" % ", ".join(parts), "color": Color(0.25, 0.85, 0.35) if status.airborne else Color(1.0, 0.3, 0.2)}


func _apply_drone_row(row: Dictionary) -> void:
	_drone_label.visible = row.visible
	_drone_bg.visible = row.visible
	if not row.visible:
		return
	_drone_label.text = row.text
	_drone_fill.color = row.color


func _team_state_text(state: Unit.State) -> String:
	match state:
		Unit.State.RETREATING:
			return "withdrawing"
		Unit.State.WITHDRAWN:
			return "withdrawn"
		Unit.State.DESTROYED:
			return "destroyed"
	return ""
