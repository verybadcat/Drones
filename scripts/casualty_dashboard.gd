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
const MAX_MORTARS_PER_SIDE: int = 2 # the enemy fields two; the player fields one

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
	# Measured directly (a headless layout diagnostic, not a guess), with
	# every row actually showing its full text, including the two cases
	# that wrap to a second line at this panel's 320px width: a mortar row
	# once its status grows a resupply suffix ("in action (22 rounds,
	# resupply ~25m out)"), and — the tallest case by far — the drone fleet
	# row once every one of its status components is populated at once
	# ("1 airborne ..., 1 backup ..., N inbound, N ready ..., N swapping
	# battery, N spare batteries ..., N lost"), a real state normal play can
	# reach given enough battle duration, not a contrived one. That worst
	# case measures 478px real height; 400 was sized for the single-line
	# assumption from before these rows could wrap at all, so it overlapped
	# main.gd's CombatLog (positioned below this panel at a fixed y) by as
	# much as 78px. Sized here with real margin over the measured worst
	# case, not to the exact minimum, since text metrics can shift slightly
	# across fonts/platforms.
	custom_minimum_size = Vector2(320, 500)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.07, 0.9)
	style.set_content_margin_all(10.0)
	style.set_corner_radius_all(4.0)
	add_theme_stylebox_override("panel", style)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	var title := GameConfig.make_selectable_label("CASUALTIES")
	title.add_theme_font_size_override("normal_font_size", 15)
	root.add_child(title)
	root.add_child(HSeparator.new())

	_player_label = GameConfig.make_selectable_label()
	root.add_child(_player_label)
	_player_bar = _build_bar(root, Color(0.3, 0.85, 1.0))
	_player_mortar_rows = _build_mortar_rows(root)

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
	_enemy_mortar_rows = _build_mortar_rows(root)

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
## Pre-allocated up to MAX_MORTARS_PER_SIDE and hidden per-refresh when a
## side has fewer than that.
func _build_mortar_rows(root: VBoxContainer) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for i in MAX_MORTARS_PER_SIDE:
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


func _refresh() -> void:
	if battle_manager == null:
		return
	_update_side(battle_manager.casualty_stats(Unit.Team.PLAYER), _player_label, _player_bar, "Player")
	_update_mortar_rows(battle_manager.player_units, _player_mortar_rows)
	_update_drone_row()
	_update_side(battle_manager.casualty_stats(Unit.Team.ENEMY), _enemy_label, _enemy_bar, "Enemy")
	_update_mortar_rows(battle_manager.enemy_units, _enemy_mortar_rows)


## `stats.estimated` (see BattleManager._compute_side_stats) marks the
## player's own fog-of-war view of the enemy — shown with a "~"/"estimated"
## qualifier so it never reads as an authoritative figure the way the
## player's own, always-fully-known casualty line does.
func _update_side(stats: Dictionary, label: RichTextLabel, bar: ColorRect, side_name: String) -> void:
	if stats.get("estimated", false):
		label.text = "%s: ~%d/%d personnel lost (~%.0f%%)" % [side_name, stats.pips_lost, stats.pips_total, stats.casualty_percent]
	else:
		label.text = "%s: %d/%d personnel lost (%.0f%%)" % [side_name, stats.pips_lost, stats.pips_total, stats.casualty_percent]
	var frac: float = clamp(stats.casualty_percent / 100.0, 0.0, 1.0)
	bar.size = Vector2(BAR_SIZE.x * frac, BAR_SIZE.y)


func _update_mortar_rows(units: Array[Unit], rows: Array[Dictionary]) -> void:
	var mortars: Array[Unit] = []
	for u in units:
		if u.kind == Unit.Kind.MORTAR:
			mortars.append(u)

	for i in rows.size():
		var row: Dictionary = rows[i]
		var label: RichTextLabel = row.label
		var bg: ColorRect = row.bg
		if i >= mortars.size():
			label.visible = false
			bg.visible = false
			continue
		label.visible = true
		bg.visible = true
		var u: Unit = mortars[i]
		label.text = "Mortar: %s" % _mortar_status_text(u)
		var fill: ColorRect = row.fill
		if u.team != Unit.Team.PLAYER and not u.player_has_been_sighted:
			# Detected firing without ever being sighted still reads as
			# genuinely "in action" (green) — only a mortar with neither a
			# sighting nor a recent fire detection is a true unknown (gray).
			fill.color = STATUS_COLOR[Unit.State.ACTIVE] if battle_manager.mortar_recently_detected_firing(u) else UNKNOWN_COLOR
		else:
			fill.color = STATUS_COLOR[u.player_known_state if u.team != Unit.Team.PLAYER else u.state]


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
	match u.state:
		Unit.State.ACTIVE:
			return "in action (%s%s)" % [GameConfig.round_count_text(u.mortar_rounds_remaining), _resupply_status_suffix(u)]
		Unit.State.RETREATING:
			return "abandoned, crew fleeing (%d/%d crew casualties)" % [u.crew_casualties, u.crew_size]
		Unit.State.WITHDRAWN:
			return "withdrew safely" if u.crew_casualties == 0 else "withdrew (%d/%d crew casualties)" % [u.crew_casualties, u.crew_size]
		Unit.State.DESTROYED:
			return "destroyed (%d/%d crew casualties)" % [u.crew_casualties, u.crew_size]
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
			return "fleeing, gun abandoned (%d/%d)" % [known_crew_casualties, u.crew_size]
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
func _resupply_status_suffix(u: Unit) -> String:
	var status: Dictionary = battle_manager.mortar_resupply_status(u)
	if not status.pending:
		return ""
	if status.ready_for_pickup:
		return ", resupply ready for pickup"
	return ", resupply ~%dm out" % int(round(float(status.minutes_until_next)))


## Airframe (airborne/inbound/ready/swapping/grounded/lost) and battery
## (spare/recharging) status for the drone fleet, with the same visual
## weight as the mortar row above — only shown in ReconMode.DRONE_TEAM
## (hidden entirely otherwise). If the ground team itself is out of action,
## that takes over the row instead (no fleet to report on without a team to
## fly it — see BattleManager._update_drone_operations).
func _update_drone_row() -> void:
	var using_drones: bool = battle_manager.recon_mode == GameConfig.ReconMode.DRONE_TEAM
	_drone_label.visible = using_drones
	_drone_bg.visible = using_drones
	if not using_drones:
		return
	var status: Dictionary = battle_manager.drone_fleet_status()
	if not status.team_active:
		_drone_label.text = "Drone team: %s (%d/%d crew casualties)" % [
			_team_state_text(status.team_state), status.team_crew_casualties, status.team_crew_size
		]
		_drone_fill.color = STATUS_COLOR[status.team_state]
		return
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
	_drone_label.text = "Drones: %s" % ", ".join(parts)
	_drone_fill.color = Color(0.25, 0.85, 0.35) if status.airborne else Color(1.0, 0.3, 0.2)


func _team_state_text(state: Unit.State) -> String:
	match state:
		Unit.State.RETREATING:
			return "withdrawing"
		Unit.State.WITHDRAWN:
			return "withdrawn"
		Unit.State.DESTROYED:
			return "destroyed"
	return ""
