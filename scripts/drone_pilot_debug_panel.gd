extends PanelContainer
class_name DronePilotDebugPanel
## "What is the drone pilot thinking right now, and why" — a player-
## toggleable debug overlay (default OFF, see main.gd's "d" key binding) drawn
## over the map itself rather than in the sidebar, which has no spare
## vertical space left (see main.gd's own comments on the button row).
## Refreshed every engine frame from BattleManager.drone_pilot_debug_
## snapshot() regardless of whether the battle itself is paused — this
## node's own _process is never touched by BattleManager.is_paused, so a
## paused battle just means the same frozen snapshot keeps getting
## re-read and re-displayed unchanged, exactly matching "continue to work
## while paused." Purely a read-only window into existing decision state;
## never influences the battle itself.

var battle_manager: BattleManager
var _label: RichTextLabel


func setup(p_battle_manager: BattleManager) -> void:
	battle_manager = p_battle_manager


func _ready() -> void:
	custom_minimum_size = Vector2(420, 260)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.05, 0.88)
	style.set_content_margin_all(10.0)
	style.set_corner_radius_all(4.0)
	add_theme_stylebox_override("panel", style)

	_label = GameConfig.make_selectable_label()
	_label.custom_minimum_size = Vector2(400, 0)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_label)

	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if battle_manager == null:
		_label.text = "DRONE PILOT DEBUG\n(no battle in progress)"
		return
	var snap: Dictionary = battle_manager.drone_pilot_debug_snapshot()
	_label.text = _format_snapshot(snap)


## Plain text, not bbcode — every value here is either a controlled label
## string this same codebase writes (see BattleManager._drone_pilot_
## reasoning's own assignments) or a number, so there's nothing worth
## escaping, and keeping it plain avoids any risk of stray bracket
## characters being misread as markup.
func _format_snapshot(snap: Dictionary) -> String:
	if not snap.get("active", false):
		return "DRONE PILOT DEBUG\n(no drone currently airborne)"

	var lines: Array[String] = []
	lines.append("DRONE PILOT DEBUG  —  press d to hide")
	lines.append("Position: %s   Battery: %d%%" % [_fmt_pos(snap.drone_position), int(round(snap.drone_battery_charge * 100.0))])
	lines.append("")

	var reasoning: Dictionary = snap.get("current_reasoning", {})
	if reasoning.is_empty():
		lines.append("Current decision: (none recorded yet)")
	else:
		lines.append("Current decision: %s" % reasoning.get("tier", "?"))
		lines.append("  %s" % reasoning.get("detail", ""))
		if reasoning.has("target"):
			lines.append("  Target: %s" % _fmt_pos(reasoning.target))
	lines.append("")

	lines.append("Assumption: no mortar seen in a while means less likely a second one is still out there.")
	lines.append("  Mortar-existence confidence right now: %.2f (1.0 = fresh concern, near 0 = long quiet)" % snap.mortar_existence_confidence)
	lines.append("")

	var contacts: Array = snap.get("recent_enemy_contacts", [])
	if contacts.is_empty():
		lines.append("Recent enemy contacts: none currently remembered")
	else:
		lines.append("Recent enemy contacts (freshest first):")
		for c in contacts:
			lines.append("  %s — %ds ago" % [_fmt_pos(c), c.age_s])
	lines.append("")

	var candidates: Array = snap.get("top_search_candidates", [])
	if not candidates.is_empty():
		lines.append("Where the pilot currently thinks is most worth checking:")
		for c in candidates:
			lines.append("  %s  value %.2f  at %s" % [c.key, c.value, _fmt_pos(c)])

	return "\n".join(lines)


func _fmt_pos(p: Dictionary) -> String:
	return "(%d, %d)m" % [p.x, p.y]
