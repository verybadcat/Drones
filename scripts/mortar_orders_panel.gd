class_name MortarOrdersPanel
extends PanelContainer

## The commander's orders panel for one friendly mortar, opened by clicking
## the mortar on the map (BattleManager.mortar_selected). Shows what the
## mortar is doing and holds the standing "expend ammunition on enemy
## squads" order as a checkbox: ticking it issues the order, unticking
## countermands it (BattleManager.set_mortar_squad_fire_order). The
## checkbox always reflects the battle manager's own state, so an order
## changed elsewhere (or a mortar knocked out) can't leave it stale.

var battle_manager: BattleManager
var mortar: Unit

var _title: Label
var _status: Label
var _order_check: CheckButton
var _note: Label
var _syncing := false


func setup(bm: BattleManager) -> void:
	battle_manager = bm
	custom_minimum_size = Vector2(320, 0)
	visible = false

	var box := VBoxContainer.new()
	add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close := Button.new()
	close.text = "X"
	close.pressed.connect(hide_panel)
	header.add_child(close)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(300, 0)
	box.add_child(_status)

	_order_check = CheckButton.new()
	_order_check.text = "Expend ammo on enemy squads"
	_order_check.toggled.connect(_on_order_toggled)
	box.add_child(_order_check)

	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(300, 0)
	_note.add_theme_font_size_override("font_size", 12)
	_note.text = "Enemy mortars still come first. This only makes the mortar more willing to fire at squads instead of holding its ammunition. Untick to countermand."
	box.add_child(_note)


func show_for(m: Unit) -> void:
	mortar = m
	visible = true
	_refresh()


func hide_panel() -> void:
	visible = false
	mortar = null


func _process(_delta: float) -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	if mortar == null or not is_instance_valid(mortar) or battle_manager == null or battle_manager.battle_over or mortar.state != Unit.State.ACTIVE:
		hide_panel()
		return
	_title.text = mortar.display_name()
	var snap: Dictionary = battle_manager.mortar_decision_debug_snapshot().get(mortar.display_name(), {})
	var reasoning: Dictionary = snap.get("reasoning", {})
	_status.text = "Rounds remaining: %d\n%s" % [mortar.mortar_rounds_remaining, str(reasoning.get("detail", ""))]
	var ordered: bool = battle_manager.mortar_squad_fire_ordered(mortar)
	if _order_check.button_pressed != ordered:
		_syncing = true
		_order_check.button_pressed = ordered
		_syncing = false


func _on_order_toggled(pressed: bool) -> void:
	if _syncing or mortar == null:
		return
	battle_manager.set_mortar_squad_fire_order(mortar, pressed)
