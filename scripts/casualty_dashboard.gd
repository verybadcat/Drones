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
}

var battle_manager: BattleManager
var _player_label: Label
var _player_bar: ColorRect
var _player_mortar_rows: Array[Dictionary] = []
var _drone_label: Label
var _drone_bg: ColorRect
var _drone_fill: ColorRect
var _enemy_label: Label
var _enemy_bar: ColorRect
var _enemy_mortar_rows: Array[Dictionary] = []


func setup(p_battle_manager: BattleManager) -> void:
	battle_manager = p_battle_manager


func _ready() -> void:
	custom_minimum_size = Vector2(320, 300) # room for the enemy's two mortar rows, plus the player's drone row

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.07, 0.9)
	style.set_content_margin_all(10.0)
	style.set_corner_radius_all(4.0)
	add_theme_stylebox_override("panel", style)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	var title := Label.new()
	title.text = "CASUALTIES"
	title.add_theme_font_size_override("font_size", 15)
	root.add_child(title)
	root.add_child(HSeparator.new())

	_player_label = Label.new()
	root.add_child(_player_label)
	_player_bar = _build_bar(root, Color(0.3, 0.85, 1.0))
	_player_mortar_rows = _build_mortar_rows(root)

	_drone_label = Label.new()
	root.add_child(_drone_label)
	_drone_bg = ColorRect.new()
	_drone_bg.color = Color(0.2, 0.2, 0.2)
	_drone_bg.custom_minimum_size = BAR_SIZE
	root.add_child(_drone_bg)
	_drone_fill = ColorRect.new()
	_drone_fill.size = Vector2(BAR_SIZE.x, BAR_SIZE.y)
	_drone_bg.add_child(_drone_fill)

	root.add_child(HSeparator.new())

	_enemy_label = Label.new()
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
		var label := Label.new()
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


func _update_side(stats: Dictionary, label: Label, bar: ColorRect, side_name: String) -> void:
	label.text = "%s: %d/%d pips lost (%.0f%%)" % [side_name, stats.pips_lost, stats.pips_total, stats.casualty_percent]
	var frac: float = clamp(stats.casualty_percent / 100.0, 0.0, 1.0)
	bar.size = Vector2(BAR_SIZE.x * frac, BAR_SIZE.y)


func _update_mortar_rows(units: Array[Unit], rows: Array[Dictionary]) -> void:
	var mortars: Array[Unit] = []
	for u in units:
		if u.kind == Unit.Kind.MORTAR:
			mortars.append(u)

	for i in rows.size():
		var row: Dictionary = rows[i]
		var label: Label = row.label
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
		fill.color = STATUS_COLOR[u.state]


## A mortar's own casualty model (an exact crew headcount) does feed into
## the aggregate pip bar above (see Unit.setup's max_pips = crew_size), but
## the exact headcount and WHY it's out of action (abandoned vs. destroyed
## outright) is otherwise buried in that one aggregate number — spelled out
## here instead.
func _mortar_status_text(u: Unit) -> String:
	match u.state:
		Unit.State.ACTIVE:
			return "in action"
		Unit.State.RETREATING:
			return "abandoned, crew fleeing (%d/%d crew killed)" % [u.crew_killed, u.crew_size]
		Unit.State.WITHDRAWN:
			return "withdrew safely" if u.crew_killed == 0 else "withdrew (%d/%d crew killed)" % [u.crew_killed, u.crew_size]
		Unit.State.DESTROYED:
			return "destroyed (%d/%d crew killed)" % [u.crew_killed, u.crew_size]
	return ""


## Airborne/ready/recharging counts for the drone fleet, with the same
## visual weight as the mortar row above — only shown in ReconMode.
## DRONE_TEAM (hidden entirely otherwise). If the ground team itself is out
## of action, that takes over the row instead (no fleet to report on without
## a team to fly it — see BattleManager._update_drone_operations).
func _update_drone_row() -> void:
	var using_drones: bool = battle_manager.recon_mode == GameConfig.ReconMode.DRONE_TEAM
	_drone_label.visible = using_drones
	_drone_bg.visible = using_drones
	if not using_drones:
		return
	var status: Dictionary = battle_manager.drone_fleet_status()
	if not status.team_active:
		_drone_label.text = "Drone team: %s (%d/%d crew killed)" % [
			_team_state_text(status.team_state), status.team_crew_killed, status.team_crew_size
		]
		_drone_fill.color = STATUS_COLOR[status.team_state]
		return
	var parts: PackedStringArray = []
	parts.append("1 airborne" if status.airborne else "NONE AIRBORNE")
	if status.inbound:
		parts.append("1 inbound")
	parts.append("%d ready" % status.ready)
	if status.recovering > 0:
		parts.append("%d recharging (next in %dm)" % [status.recovering, int(ceil(status.next_ready_in / 60.0))])
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
