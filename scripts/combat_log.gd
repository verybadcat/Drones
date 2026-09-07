extends VBoxContainer
class_name CombatLog
## Scrollable, newest-entry-on-top combat log. Purely templated strings — no
## generative text, per the design doc. No routine per-shot fire log — only
## the moments that actually change the picture: spotted, reveals itself,
## pulls back, reaches safety, goes out of action.
##
## Deliberately sized to a fraction of the sidebar, not the dominant
## element on screen — the log stays fully available (scrollable, same
## content as ever) but the CasualtyDashboard above it is the prominent,
## at-a-glance readout now; the log is for scrolling back through what
## happened, not for reading at a glance.
##
## Height is genuinely budget-constrained, not just a style choice: the
## whole window is a fixed 700px tall (see project.godot), the dashboard
## above this now legitimately needs ~400px with every row showing
## (DRONE_TEAM recon mode, enemy's 2 mortars both still active — see
## CasualtyDashboard._ready), and main.gd positions this panel below it,
## below the one button row (general retreat) above the dashboard in turn —
## there simply isn't room for this to be as tall as it once was without
## something overlapping something else.
var _scroll: ScrollContainer
var _list: VBoxContainer

const MAX_ENTRIES: int = 200
const SIZE: Vector2 = Vector2(300, 220)


func _ready() -> void:
	custom_minimum_size = SIZE
	size = SIZE

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = SIZE
	_scroll.size = SIZE
	add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)


func add_entry(text: String) -> void:
	var label := GameConfig.make_selectable_label(text)
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


func log_squad_surrendered(unit: Unit) -> void:
	add_entry("%s lays down arms rather than risk the retreat — surrendered" % unit.display_name())


func log_wounded_carried(unit: Unit, count: int) -> void:
	add_entry("%s pulls back slowed, carrying %d wounded" % [unit.display_name(), count])


func log_wounded_abandoned(unit: Unit, count: int) -> void:
	add_entry("%s leaves %d wounded behind rather than risk a slower retreat" % [unit.display_name(), count])


func log_reports_issue(unit: Unit) -> void:
	add_entry("%s reports heavy resistance" % unit.display_name())


func log_destroyed(unit: Unit) -> void:
	if unit.kind == Unit.Kind.MORTAR or unit.kind == Unit.Kind.DRONE_TEAM:
		var what := "the gun" if unit.kind == Unit.Kind.MORTAR else "the operation"
		add_entry("%s's entire crew is down (%d/%d casualties) — %s is lost" % [
			unit.display_name(), unit.crew_casualties, unit.crew_size, what
		])
	else:
		add_entry("%s %s" % [unit.display_name(), unit.destroyed_verb()])


func log_crew_abandoned(unit: Unit) -> void:
	var what := "the gun" if unit.kind == Unit.Kind.MORTAR else "operations"
	add_entry("%s takes a hit — %d/%d crew down, survivors abandon %s and flee" % [
		unit.display_name(), unit.crew_casualties, unit.crew_size, what
	])


func log_drone_launched(unit: Unit) -> void:
	add_entry("%s launches" % unit.display_name())


func log_drone_backup_launched(unit: Unit, watched: Unit) -> void:
	add_entry("%s launches as backup, shadowing %s for continuous coverage" % [unit.display_name(), watched.display_name()])


func log_drone_shot_down(unit: Unit) -> void:
	add_entry("%s is shot down" % unit.display_name())


func log_drone_returning(unit: Unit) -> void:
	add_entry("%s returns to base" % unit.display_name())


func log_drone_sacrificed(unit: Unit, watched: Unit) -> void:
	add_entry("%s's battery gives out while holding station over %s — the airframe is lost" % [unit.display_name(), watched.display_name()])


func log_drone_battery_died(unit: Unit) -> void:
	add_entry("%s's battery dies mid-flight — the airframe falls" % unit.display_name())


func log_bunching_spillover(defender: Unit, spillover: Unit) -> void:
	add_entry("%s was bunched up with %s — the fire catches both" % [defender.display_name(), spillover.display_name()])


func log_mortar_shot_evaded(mortar: Unit, target: Unit) -> void:
	add_entry("%s's round lands on empty ground — %s had already moved on" % [mortar.display_name(), target.display_name()])


func log_counter_battery_incoming(unit: Unit) -> void:
	add_entry("Counter-battery fire inbound on %s's position" % unit.display_name())


func log_counter_battery(unit: Unit) -> void:
	add_entry("Counter-battery fire found %s" % unit.display_name())


func log_counter_battery_miss(unit: Unit) -> void:
	add_entry("Counter-battery fire lands near %s's old position — no hit" % unit.display_name())


func log_relocate(unit: Unit, urgent: bool = false) -> void:
	if urgent:
		add_entry("%s relocates after firing — farther and faster, still shaking off recent counter-battery fire" % unit.display_name())
	else:
		add_entry("%s relocates after firing (shoot and scoot)" % unit.display_name())


func log_mortar_resupply_requested(unit: Unit) -> void:
	add_entry("%s requests ammunition resupply — first shipment due in the rear area" % unit.display_name())


## "Roughly" is the whole point — see GameConfig.MORTAR_RESUPPLY_ETA_WARNING_
## MEDIAN's own comment. This is a real ETA estimate, not a guaranteed one.
func log_mortar_resupply_eta_warning(unit: Unit) -> void:
	add_entry("%s: resupply convoy reports roughly 15 minutes out" % unit.display_name())


func log_mortar_resupply_arrived(unit: Unit, rounds: int) -> void:
	add_entry("%s: resupply run gets through — %d rounds waiting at the resupply point" % [unit.display_name(), rounds])


func log_mortar_resupply_failed(unit: Unit) -> void:
	add_entry("%s: resupply run failed to get through — request again when ready" % unit.display_name())


func log_mortar_resupply_departing(unit: Unit) -> void:
	add_entry("%s heads to the resupply point to collect waiting ammunition" % unit.display_name())


func log_mortar_resupply_collected(unit: Unit, rounds: int) -> void:
	add_entry("%s collects %d rounds (%d now on hand) and heads back" % [unit.display_name(), rounds, unit.mortar_rounds_remaining])


func log_squad_blocking_flank(unit: Unit) -> void:
	add_entry("%s moves to block an approach toward the mortar" % unit.display_name())


func log_squad_consolidating(unit: Unit) -> void:
	add_entry("%s pulls back toward the rest of the line rather than risk being surrounded" % unit.display_name())


func log_mortar_relocating_for_cover(unit: Unit) -> void:
	add_entry("%s spotted — abandons position for better cover" % unit.display_name())


func log_mortar_hunting(unit: Unit, trusted: bool) -> void:
	if trusted:
		add_entry("%s repositions for a tracked shot at the enemy mortar" % unit.display_name())
	else:
		add_entry("%s repositions, gambling on a stale fix on the enemy mortar" % unit.display_name())


func log_joint_mortar_hunt(target: Unit) -> void:
	add_entry("Mortar and drone team commit to a coordinated hunt for %s" % target.display_name())


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
