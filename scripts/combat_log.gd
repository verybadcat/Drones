extends VBoxContainer
class_name CombatLog
## Scrollable, newest-entry-on-top combat log. Purely templated strings — no
## generative text, per the design doc. No routine per-shot fire log — only
## the moments that actually change the picture: spotted, reveals itself,
## pulls back, reaches safety, goes out of action.

var _scroll: ScrollContainer
var _list: VBoxContainer

const MAX_ENTRIES: int = 200


func _ready() -> void:
	custom_minimum_size = Vector2(300, 600)
	size = custom_minimum_size

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(300, 600)
	_scroll.size = _scroll.custom_minimum_size
	add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)


func add_entry(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(label)
	_list.move_child(label, 0)

	while _list.get_child_count() > MAX_ENTRIES:
		var last := _list.get_child(_list.get_child_count() - 1)
		_list.remove_child(last)
		last.queue_free()


func log_threshold_retreat(unit: Unit) -> void:
	var pips_lost: int = unit.max_pips - unit.pips
	add_entry("%s pulls back: %d/%d casualties exceeded %d%% threshold" % [
		unit.display_name(), pips_lost, unit.max_pips, int(round(unit.retreat_threshold * 100.0))
	])


func log_ordered_retreat(unit: Unit) -> void:
	add_entry("%s pulls back, ordered to retreat" % unit.display_name())


func log_withdrawn(unit: Unit) -> void:
	add_entry("%s has withdrawn from the battle" % unit.display_name())


func log_reports_issue(unit: Unit) -> void:
	add_entry("%s reports heavy resistance" % unit.display_name())


func log_destroyed(unit: Unit) -> void:
	if unit.kind == Unit.Kind.MORTAR:
		add_entry("%s's entire crew is down (%d/%d killed) — the gun is lost" % [
			unit.display_name(), unit.crew_killed, unit.crew_size
		])
	else:
		add_entry("%s %s" % [unit.display_name(), unit.destroyed_verb()])


func log_mortar_abandoned(unit: Unit) -> void:
	add_entry("%s takes a hit — %d/%d crew down, survivors abandon the gun and flee" % [
		unit.display_name(), unit.crew_killed, unit.crew_size
	])


func log_counter_battery_incoming(unit: Unit) -> void:
	add_entry("Counter-battery fire inbound on %s's position" % unit.display_name())


func log_counter_battery(unit: Unit) -> void:
	add_entry("Counter-battery fire found %s" % unit.display_name())


func log_counter_battery_miss(unit: Unit) -> void:
	add_entry("Counter-battery fire lands near %s's old position — no hit" % unit.display_name())


func log_relocate(unit: Unit) -> void:
	add_entry("%s relocated after firing (shoot and scoot)" % unit.display_name())


func log_spotted(unit: Unit) -> void:
	add_entry("%s was spotted" % unit.display_name())


func log_lost_contact(unit: Unit) -> void:
	add_entry("Contact lost with %s" % unit.display_name())


func log_revealed_by_fire(unit: Unit) -> void:
	add_entry("%s opened fire, revealing its position" % unit.display_name())


func log_seeking_cover(unit: Unit) -> void:
	add_entry("%s breaks off and heads for cover" % unit.display_name())


func log_bolts_for_cover(unit: Unit) -> void:
	add_entry("%s bolts for a new position under mortar fire" % unit.display_name())


func log_battle_end(report_text: String) -> void:
	add_entry(report_text)
