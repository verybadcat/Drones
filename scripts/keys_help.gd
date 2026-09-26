class_name KeysHelp
extends Control
## The list of keys, reachable from the setup screen and from the battle: press "?" (or F1), or click
## the small "? Keys" note in the bottom-left corner. It is deliberately quiet: the note is small and
## dim, low on the screen and away from the top bar (which is for battle orders, and this is not
## one), and the list is a modest panel that closes on the same key, Esc or any click, and does not
## pause anything. It exists because some useful views have no button at all ("Inspect AI doesn't need
## a button ... there should be a screen accessible from the setup page, and also from the battle,
## that shows the various keys. This would include the one that shows the assessment of where the enemy
## might be").
##
## Add one as a child of a screen; it lays itself out over the whole screen without taking mouse clicks
## except while the list is open.

## [key, what it does]. The keys the battle screen listens for (BattleScreen._unhandled_input), then this list's own.
const KEYS: Array = [
	["E", "Show or hide the enemy heat map: our assessment of where the enemy might be."],
	["D", "Show or hide the drone pilot's reasoning: what the drone is doing and why."],
	["I", "Show or hide the AI inspector: the decisions units have made and why."],
	["? or F1", "Show or hide this list."],
	["Esc", "Close this list."],
]
## What the mouse does, for completeness.
const MOUSE: Array = [
	["Drag (setup)", "Move a unit into position on the map."],
	["Click a unit (battle)", "Open its orders card."],
]

var _hint: Button
var _panel: PanelContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE # never in the way of the map underneath

	_hint = Button.new()
	_hint.text = "? Keys"
	_hint.flat = true
	_hint.focus_mode = Control.FOCUS_NONE
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	_hint.add_theme_color_override("font_hover_color", Color(1, 1, 1, 0.9))
	_hint.tooltip_text = "The keys: press ? or F1"
	_hint.pressed.connect(toggle)
	add_child(_hint)

	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.08, 0.92)
	style.set_content_margin_all(16.0)
	style.set_corner_radius_all(6.0)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.visible = false
	add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	box.add_child(_label("Keys", 17))
	box.add_child(_grid(KEYS))
	box.add_child(_label("Mouse", 15))
	box.add_child(_grid(MOUSE))
	var close_note := _label("Press ?, F1 or Esc, or click, to close.", 12)
	close_note.modulate = Color(1, 1, 1, 0.6)
	box.add_child(close_note)

	# The screens are not sized by a parent Control, so lay out from the window itself.
	get_viewport().size_changed.connect(_layout)
	_layout.call_deferred()


## Fits this to the window: the hint at the bottom-left, the list in the middle.
func _layout() -> void:
	var window: Vector2 = get_viewport_rect().size
	size = window
	_hint.reset_size()
	_hint.position = Vector2(6.0, window.y - _hint.size.y - 4.0)
	_panel.reset_size()
	_panel.position = ((window - _panel.size) / 2.0).floor()


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	return label


func _grid(rows: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	for row in rows:
		var key := _label(row[0], 14)
		key.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		grid.add_child(key)
		var what := _label(row[1], 14)
		grid.add_child(what)
	return grid


func is_open() -> bool:
	return _panel != null and _panel.visible


func toggle() -> void:
	if _panel != null:
		_panel.visible = not _panel.visible
		if _panel.visible:
			_layout()


## True if `event` is one that opens or closes the list (? or F1) — or Esc, which only closes it.
func handles_key(event: InputEvent) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return false
	if event.keycode == KEY_F1 or event.keycode == KEY_QUESTION or event.unicode == 63 or (event.keycode == KEY_SLASH and event.shift_pressed):
		return true
	return event.keycode == KEY_ESCAPE and is_open()


func _unhandled_input(event: InputEvent) -> void:
	if handles_key(event):
		if event.keycode == KEY_ESCAPE:
			_panel.visible = false
		else:
			toggle()
		get_viewport().set_input_as_handled()


## While the list is open, any click closes it (and is not passed on to the map).
func _input(event: InputEvent) -> void:
	if is_open() and event is InputEventMouseButton and event.pressed:
		_panel.visible = false
		get_viewport().set_input_as_handled()
