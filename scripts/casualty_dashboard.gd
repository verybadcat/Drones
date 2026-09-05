extends PanelContainer
class_name CasualtyDashboard
## Prominent, always-current casualty readout for both sides during a
## battle — pips lost/total and a percentage bar, plus a mortar-specific
## status line (its own casualty model — an exact crew headcount, not
## percent pips — is otherwise invisible at a glance, buried in the same
## aggregate number as the squads). Updated every frame from
## BattleManager.casualty_stats() and its unit lists, the exact same data
## the AAR report is built from. This is the at-a-glance element in the
## sidebar; CombatLog below it is for scrolling back through what
## happened, not for reading the state of the battle in one look.

const BAR_SIZE: Vector2 = Vector2(280.0, 16.0)

var battle_manager: BattleManager
var _player_label: Label
var _player_bar: ColorRect
var _player_mortar_label: Label
var _enemy_label: Label
var _enemy_bar: ColorRect
var _enemy_mortar_label: Label


func setup(p_battle_manager: BattleManager) -> void:
	battle_manager = p_battle_manager


func _ready() -> void:
	custom_minimum_size = Vector2(320, 195) # enemy side can show two mortar status lines

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
	_player_mortar_label = _build_mortar_label(root)

	root.add_child(HSeparator.new())

	_enemy_label = Label.new()
	root.add_child(_enemy_label)
	_enemy_bar = _build_bar(root, Color(1.0, 0.55, 0.15))
	_enemy_mortar_label = _build_mortar_label(root)

	_refresh() # show correct 0% bars immediately, don't wait a frame


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


func _build_mortar_label(root: VBoxContainer) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	root.add_child(label)
	return label


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if battle_manager == null:
		return
	_update_side(battle_manager.casualty_stats(Unit.Team.PLAYER), _player_label, _player_bar, "Player")
	_player_mortar_label.text = _mortar_status_text(battle_manager.player_units)
	_update_side(battle_manager.casualty_stats(Unit.Team.ENEMY), _enemy_label, _enemy_bar, "Enemy")
	_enemy_mortar_label.text = _mortar_status_text(battle_manager.enemy_units)


func _update_side(stats: Dictionary, label: Label, bar: ColorRect, side_name: String) -> void:
	label.text = "%s: %d/%d pips lost (%.0f%%)" % [side_name, stats.pips_lost, stats.pips_total, stats.casualty_percent]
	var frac: float = clamp(stats.casualty_percent / 100.0, 0.0, 1.0)
	bar.size = Vector2(BAR_SIZE.x * frac, BAR_SIZE.y)


## A mortar's own casualty model (an exact crew headcount, abandon-the-gun-
## on-any-hit) doesn't show up meaningfully in the aggregate pip bar above —
## one hit is still just "1 pip" there whether the whole crew died or one
## survivor fled. Called out on its own line instead, one entry per mortar
## (the enemy has two).
func _mortar_status_text(units: Array[Unit]) -> String:
	var lines: Array[String] = []
	for u in units:
		if u.kind != Unit.Kind.MORTAR:
			continue
		var status: String
		match u.state:
			Unit.State.ACTIVE:
				status = "in action"
			Unit.State.RETREATING:
				status = "abandoned, crew fleeing (%d/%d crew killed)" % [u.crew_killed, u.crew_size]
			Unit.State.WITHDRAWN:
				status = "withdrew safely" if u.crew_killed == 0 else "withdrew (%d/%d crew killed)" % [u.crew_killed, u.crew_size]
			Unit.State.DESTROYED:
				status = "destroyed (%d/%d crew killed)" % [u.crew_killed, u.crew_size]
		lines.append("Mortar: %s" % status)
	return "\n".join(lines)
