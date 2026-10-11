class_name UnitOrdersPanel
extends PanelContainer

## The commander's orders card for a friendly unit. Clicking a unit on the map (a
## squad, the mortar, the spotter, the drone team — BattleManager.unit_selected)
## pops it up beside the unit; any click outside the card dismisses it (see _input),
## including a click on the unit itself. It follows the unit if it moves, and holds
## only the orders that can be given:
##   - every unit: a "Fall back" button (BattleManager.set_fall_back_order) — a
##     one-shot order: pressing it gives the order and dismisses the card
##   - the mortar also: an "Expend ammo on enemy squads" switch
##     (BattleManager.set_mortar_squad_fire_order), a standing order that always
##     mirrors the battle manager's own state
##   - every unit: a "Blow-up window" button, which asks the screen to show (or hide) the
##     magnified view around the unit (`blowup_requested`)
##
## Each of these has a hotkey, the first letter of the order, shown on the card: F, E (the
## mortar only) and B. While the card is open they take the key before anything else on the
## screen does (the heat map's E included) — direct user request: "The hotkey can be the first
## letter of the order. It can override any other meaning the key may have."

const CARD_COLOR := Color(0.10, 0.12, 0.14, 0.94)
const BORDER_COLOR := Color(0.42, 0.50, 0.44, 0.9)
const HEADING_COLOR := Color(0.62, 0.70, 0.64)
const TEXT_COLOR := Color(0.93, 0.95, 0.93)
const ACTIVE_COLOR := Color(0.55, 0.85, 0.55)
const GAP := 26.0 # between the unit's marker and the card
const ARROW := 8.0 # half-height of the pointer toward the unit
const EDGE_MARGIN := 6.0

## The B key or the card's blow-up button: the screen shows the magnified window around `unit`, or takes it away.
signal blowup_requested

var battle_manager: BattleManager
var unit: Unit

var _map_viewport: SubViewport
var _map_rect: Rect2
var _fire_row: HBoxContainer
var _fire_label: Label
var _fire_switch: CheckButton
var _fall_back_button: Button
var _blowup_button: Button
var _syncing := false
var _card_on_right := true
# The process frame in which a click outside just dismissed the card — a click on the
# unit itself is both "outside the card" and "select the unit", and must dismiss, not
# dismiss-then-reopen (show_for ignores the same frame).
var _dismissed_frame := -1
var _arrow_y := 20.0


## `map_viewport` is the SubViewport the unit's world position lives in (its canvas
## transform maps that to screen); `map_rect` is the on-screen area the card must
## stay inside.
func setup(bm: BattleManager, map_viewport: SubViewport, map_rect: Rect2) -> void:
	battle_manager = bm
	_map_viewport = map_viewport
	_map_rect = map_rect
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = CARD_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 9
	style.content_margin_bottom = 10
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 2)
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	var heading := Label.new()
	heading.text = "ORDERS"
	heading.add_theme_font_size_override("font_size", 11)
	heading.add_theme_color_override("font_color", HEADING_COLOR)
	box.add_child(heading)

	# The mortar's own order — only shown for a mortar.
	_fire_row = HBoxContainer.new()
	_fire_row.add_theme_constant_override("separation", 10)
	box.add_child(_fire_row)
	_fire_label = _add_row_label(_fire_row, "Expend ammo on\nenemy squads  [E]")
	_fire_switch = _add_row_switch(_fire_row, "Make this mortar much more willing to fire on enemy squads instead of holding its ammunition. Enemy mortars still come first.")
	_fire_switch.toggled.connect(_on_fire_toggled)

	# Every unit's order: a button, not a switch — it is given once and the card goes.
	_fall_back_button = Button.new()
	_fall_back_button.text = "Fall back  [F]"
	_fall_back_button.focus_mode = Control.FOCUS_NONE
	_fall_back_button.add_theme_font_size_override("font_size", 14)
	_fall_back_button.tooltip_text = "Move back toward your edge of the map — usually 500 to 1000 m, to a better position along the way if there is one. The unit then holds there rather than advancing. Not a retreat off the map, and it does nothing if the unit is already very close to the edge."
	_fall_back_button.pressed.connect(_on_fall_back_pressed)
	box.add_child(_fall_back_button)

	# Every unit: the magnified view of the ground around it, the same window as on the setup screen.
	_blowup_button = Button.new()
	_blowup_button.text = "Blow-up window  [B]"
	_blowup_button.focus_mode = Control.FOCUS_NONE
	_blowup_button.add_theme_font_size_override("font_size", 14)
	_blowup_button.tooltip_text = "Show a magnified view of the ground around this unit, following it. Press again, or deselect the unit, to take it away."
	_blowup_button.pressed.connect(_on_blowup_pressed)
	box.add_child(_blowup_button)

	# Fit to content once, after the theme/fonts have settled.
	reset_size.call_deferred()


func _add_row_label(row: HBoxContainer, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return label


func _add_row_switch(row: HBoxContainer, tooltip: String) -> CheckButton:
	var sw := CheckButton.new()
	sw.focus_mode = Control.FOCUS_NONE
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.tooltip_text = tooltip
	row.add_child(sw)
	return sw


## A click on a unit: open the card (unless that very click has just dismissed it —
## see _input).
func show_for(u: Unit) -> void:
	if Engine.get_process_frames() == _dismissed_frame:
		return
	unit = u
	visible = true
	_fire_row.visible = u.kind == Unit.Kind.MORTAR
	_refresh()
	reset_size()
	_reposition()


## Any mouse click outside the card dismisses it; a click inside (a switch, the
## card's own background) leaves it alone. Runs before the map sees the click, so a
## click on the unit closes the card first and show_for then ignores the same click.
func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey:
		_handle_key(event)
		return
	if not visible or not (event is InputEventMouseButton and event.pressed):
		return
	if get_global_rect().has_point(event.position):
		return
	_dismissed_frame = Engine.get_process_frames()
	hide_panel()


## The hotkeys, while the card is open: F gives the fall-back order, E (the mortar only) flips its
## expend-ammo order, B shows or hides the blow-up window. Each is consumed, so it does not also do
## what the key means elsewhere (the heat map's E). With Ctrl, Alt or Meta held the key is left alone.
func _handle_key(event: InputEventKey) -> bool:
	if not event.pressed or event.echo or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return false
	if unit == null:
		return false
	var used := false
	match event.keycode:
		KEY_F:
			used = true
			_on_fall_back_pressed()
		KEY_E:
			if unit.kind == Unit.Kind.MORTAR:
				used = true
				_fire_switch.button_pressed = not _fire_switch.button_pressed # its handler gives or lifts the order
		KEY_B:
			used = true
			_on_blowup_pressed()
	if used and is_inside_tree():
		get_viewport().set_input_as_handled()
	return used


func hide_panel() -> void:
	visible = false
	unit = null


func _process(_delta: float) -> void:
	if visible:
		_refresh()
		_reposition()


func _refresh() -> void:
	if unit == null or not is_instance_valid(unit) or battle_manager == null or battle_manager.battle_over or unit.state != Unit.State.ACTIVE:
		hide_panel()
		return
	if unit.kind == Unit.Kind.MORTAR:
		_mirror(_fire_switch, _fire_label, battle_manager.mortar_squad_fire_ordered(unit))


## Makes a switch (and its label's colour) show `on` without firing its handler.
func _mirror(sw: CheckButton, label: Label, on: bool) -> void:
	if sw.button_pressed != on:
		_syncing = true
		sw.button_pressed = on
		_syncing = false
	label.add_theme_color_override("font_color", ACTIVE_COLOR if on else TEXT_COLOR)


## Beside the unit — to its right, or its left when there isn't room — and clamped
## inside the map, tracking the unit's on-screen position each frame.
func _reposition() -> void:
	if unit == null or _map_viewport == null:
		return
	var anchor: Vector2 = _map_viewport.get_canvas_transform() * unit.global_position
	var card: Vector2 = size
	_card_on_right = anchor.x + GAP + card.x <= _map_rect.end.x - EDGE_MARGIN
	var x: float = anchor.x + GAP if _card_on_right else anchor.x - GAP - card.x
	var y: float = anchor.y - card.y / 2.0
	x = clampf(x, _map_rect.position.x + EDGE_MARGIN, maxf(_map_rect.end.x - card.x - EDGE_MARGIN, _map_rect.position.x))
	y = clampf(y, _map_rect.position.y + EDGE_MARGIN, maxf(_map_rect.end.y - card.y - EDGE_MARGIN, _map_rect.position.y))
	position = Vector2(x, y)
	# The pointer must aim at the unit even when the card was clamped.
	_arrow_y = clampf(anchor.y - y, ARROW + 8.0, maxf(card.y - ARROW - 8.0, ARROW + 8.0))
	queue_redraw()


## A small pointer on the card's edge facing the unit.
func _draw() -> void:
	var base_x: float = 0.0 if _card_on_right else size.x
	var tip_x: float = -ARROW if _card_on_right else size.x + ARROW
	var pts := PackedVector2Array([
		Vector2(base_x, _arrow_y - ARROW),
		Vector2(tip_x, _arrow_y),
		Vector2(base_x, _arrow_y + ARROW),
	])
	draw_colored_polygon(pts, CARD_COLOR)
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2]]), BORDER_COLOR, 1.0)


func _on_fire_toggled(pressed: bool) -> void:
	if _syncing or unit == null:
		return
	battle_manager.set_mortar_squad_fire_order(unit, pressed)


func _on_blowup_pressed() -> void:
	if unit != null:
		blowup_requested.emit()


## Gives the order and dismisses the card. An order the unit can't carry out (nowhere
## safer) is refused and says so in the combat log; the card goes either way.
func _on_fall_back_pressed() -> void:
	if unit == null:
		return
	battle_manager.set_fall_back_order(unit, true)
	hide_panel()
