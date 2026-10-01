class_name HelpIcon
extends Label
## A small, quiet "(?)" hover note for a longer explanation that shouldn't sit on screen by default —
## first used by LevelSelectScreen's seed box (see its own doc comment for the full user request/history).
##
## Direct user follow-up, the very next thing reported after the first version shipped: "The help text
## goes off the screen the way you have it... I mouse over and the text is too long for the single line
## that pops up." Root cause: a plain `tooltip_text` assignment on a bare Control uses Godot's DEFAULT
## tooltip, which renders as a single unwrapped line — fine for a short hint, unreadable for a whole
## paragraph. Godot's own fix for this is `_make_custom_tooltip`, a virtual every Control has: return a
## real Control from it and Godot shows THAT instead of the default one-line tooltip. Only reachable by
## actually subclassing (can't override a virtual on a bare built-in Label instance), which is the whole
## reason this is its own class rather than another `GameConfig.make_*` static helper.
##
## Usage: `var help := HelpIcon.new(); help.tooltip_text = "...long explanation..."; parent.add_child(help)`
## — same `tooltip_text` property as any other Control; only how it's SHOWN differs.
const WRAP_WIDTH: float = 420.0

func _init() -> void:
	text = "(?)"
	mouse_filter = Control.MOUSE_FILTER_STOP # a Label ignores the mouse by default; needed for any tooltip (custom or not) to trigger at all
	add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	add_theme_color_override("font_hover_color", Color(1, 1, 1, 0.9)) # same hover-brightens treatment as KeysHelp's own "? Keys" hint


func _make_custom_tooltip(for_text: String) -> Object:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.08, 0.95)
	style.set_content_margin_all(10.0)
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = for_text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(WRAP_WIDTH, 0)
	label.add_theme_color_override("font_color", Color.WHITE)
	panel.add_child(label)
	return panel
