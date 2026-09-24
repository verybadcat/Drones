class_name MortarOrdersPanel
extends PanelContainer

## The commander's orders card for a friendly mortar. Clicking the mortar on
## the map pops it up beside the mortar (BattleManager.mortar_selected);
## clicking the mortar again (or its small x) dismisses it. It follows the mortar if the crew
## moves, and holds only the orders that can be given: today, the standing
## "expend ammo on enemy squads" order (BattleManager.set_mortar_squad_fire_order).
## The switch always mirrors the battle manager's own state, so an order changed
## elsewhere (or a mortar knocked out) can't leave it stale.

const CARD_COLOR := Color(0.10, 0.12, 0.14, 0.94)
const BORDER_COLOR := Color(0.42, 0.50, 0.44, 0.9)
const HEADING_COLOR := Color(0.62, 0.70, 0.64)
const TEXT_COLOR := Color(0.93, 0.95, 0.93)
const ACTIVE_COLOR := Color(0.55, 0.85, 0.55)
const GAP := 26.0 # between the mortar's marker and the card
const ARROW := 8.0 # half-height of the pointer toward the mortar
const EDGE_MARGIN := 6.0

var battle_manager: BattleManager
var mortar: Unit

var _map_viewport: SubViewport
var _map_rect: Rect2
var _order_switch: CheckButton
var _close_button: Button
var _order_label: Label
var _syncing := false
var _card_on_right := true


## `map_viewport` is the SubViewport the mortar's world position lives in (its
## canvas transform maps that to screen); `map_rect` is the on-screen area the
## card must stay inside.
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
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 10
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 2)
	add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	var heading := Label.new()
	heading.text = "ORDERS"
	heading.add_theme_font_size_override("font_size", 11)
	heading.add_theme_color_override("font_color", HEADING_COLOR)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(heading)

	# A small flat "x" in the corner, alongside clicking the mortar again.
	_close_button = Button.new()
	_close_button.text = "×"
	_close_button.flat = true
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.custom_minimum_size = Vector2(22, 20)
	_close_button.tooltip_text = "Close"
	_close_button.add_theme_font_size_override("font_size", 16)
	_close_button.add_theme_color_override("font_color", HEADING_COLOR)
	_close_button.add_theme_color_override("font_hover_color", TEXT_COLOR)
	_close_button.add_theme_color_override("font_pressed_color", TEXT_COLOR)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1, 1, 1, 0.10)
	hover.set_corner_radius_all(4)
	_close_button.add_theme_stylebox_override("hover", hover)
	_close_button.add_theme_stylebox_override("pressed", hover)
	_close_button.pressed.connect(hide_panel)
	header.add_child(_close_button)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)

	_order_label = Label.new()
	_order_label.text = "Expend ammo on\nenemy squads"
	_order_label.add_theme_font_size_override("font_size", 14)
	_order_label.add_theme_color_override("font_color", TEXT_COLOR)
	_order_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_order_label)

	_order_switch = CheckButton.new()
	_order_switch.focus_mode = Control.FOCUS_NONE
	_order_switch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_order_switch.tooltip_text = "Make this mortar much more willing to fire on enemy squads instead of holding its ammunition. Enemy mortars still come first."
	_order_switch.toggled.connect(_on_order_toggled)
	row.add_child(_order_switch)

	# Fit to content once, after the theme/fonts have settled.
	reset_size.call_deferred()


## A click on the mortar: open the card, or close it if it is already showing
## this mortar.
func show_for(m: Unit) -> void:
	if visible and mortar == m:
		hide_panel()
		return
	mortar = m
	visible = true
	_refresh()
	reset_size()
	_reposition()


func hide_panel() -> void:
	visible = false
	mortar = null


func _process(_delta: float) -> void:
	if visible:
		_refresh()
		_reposition()


func _refresh() -> void:
	if mortar == null or not is_instance_valid(mortar) or battle_manager == null or battle_manager.battle_over or mortar.state != Unit.State.ACTIVE:
		hide_panel()
		return
	var ordered: bool = battle_manager.mortar_squad_fire_ordered(mortar)
	if _order_switch.button_pressed != ordered:
		_syncing = true
		_order_switch.button_pressed = ordered
		_syncing = false
	_order_label.add_theme_color_override("font_color", ACTIVE_COLOR if ordered else TEXT_COLOR)


## Beside the mortar — to its right, or its left when there isn't room — and
## clamped inside the map, tracking the mortar's on-screen position each frame.
func _reposition() -> void:
	if mortar == null or _map_viewport == null:
		return
	var anchor: Vector2 = _map_viewport.get_canvas_transform() * mortar.global_position
	var card: Vector2 = size
	_card_on_right = anchor.x + GAP + card.x <= _map_rect.end.x - EDGE_MARGIN
	var x: float = anchor.x + GAP if _card_on_right else anchor.x - GAP - card.x
	var y: float = anchor.y - card.y / 2.0
	x = clampf(x, _map_rect.position.x + EDGE_MARGIN, maxf(_map_rect.end.x - card.x - EDGE_MARGIN, _map_rect.position.x))
	y = clampf(y, _map_rect.position.y + EDGE_MARGIN, maxf(_map_rect.end.y - card.y - EDGE_MARGIN, _map_rect.position.y))
	position = Vector2(x, y)
	# The pointer must aim at the mortar even when the card was clamped.
	_arrow_y = clampf(anchor.y - y, ARROW + 8.0, maxf(card.y - ARROW - 8.0, ARROW + 8.0))
	queue_redraw()


var _arrow_y := 20.0


## A small pointer on the card's edge facing the mortar.
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


func _on_order_toggled(pressed: bool) -> void:
	if _syncing or mortar == null:
		return
	battle_manager.set_mortar_squad_fire_order(mortar, pressed)
