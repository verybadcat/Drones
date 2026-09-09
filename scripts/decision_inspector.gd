extends PanelContainer
## Reads recorded evidence only. Never asks the battle AI to decide again.
const CommanderProfile = preload("res://scripts/commander_profile.gd")
var battle_manager: BattleManager
var _units: OptionButton
var _developer: CheckBox
var _live: CheckBox
var _history: HSlider
var _text: RichTextLabel
var _export_status: Label
var _unit_ids: Array[int] = []
var _elapsed := 0.0
var _review_entries: Array[Dictionary] = []

func setup(manager: BattleManager) -> void:
	battle_manager = manager

func _ready() -> void:
	custom_minimum_size = Vector2(600, 600)
	size = custom_minimum_size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.06, 0.08, 0.97)
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var heading := HBoxContainer.new()
	root.add_child(heading)
	var title := Label.new()
	title.text = "BATTLE AI / DECISION INSPECTOR"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close := Button.new()
	close.text = "Close (i)"
	close.pressed.connect(func(): hide())
	heading.add_child(close)
	_developer = CheckBox.new()
	_developer.text = "Developer view: reveal enemy decisions"
	_developer.toggled.connect(func(_on): _unit_ids.clear(); _refresh())
	root.add_child(_developer)
	_units = OptionButton.new()
	_units.item_selected.connect(func(_index): _live.button_pressed = true; _refresh())
	root.add_child(_units)
	_live = CheckBox.new()
	_live.text = "Live records (uncheck to review decision changes)"
	_live.button_pressed = true
	_live.toggled.connect(func(on):
		if not on and not _unit_ids.is_empty():
			_review_entries = battle_manager.decisions.history_for(_unit_ids[_units.selected])
		_refresh())
	root.add_child(_live)
	_history = HSlider.new()
	_history.step = 1
	_history.value_changed.connect(func(_value): _refresh())
	root.add_child(_history)
	_text = RichTextLabel.new()
	_text.selection_enabled = true
	_text.bbcode_enabled = false
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size = Vector2(570, 390)
	root.add_child(_text)
	var export_button := Button.new()
	export_button.text = "Export recorded decisions (JSON)"
	export_button.pressed.connect(_export)
	root.add_child(export_button)
	_export_status = Label.new()
	_export_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_export_status)
	_refresh()

func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed += delta
	if _elapsed >= 0.25:
		_elapsed = 0.0
		_refresh()

func _refresh() -> void:
	if _text == null or battle_manager == null:
		return
	var known: Dictionary = {}
	for entry in battle_manager.decisions.latest.values():
		if entry.team == Unit.Team.PLAYER or _developer.button_pressed:
			known[entry.unit_id] = entry.unit
	var ids: Array[int] = []
	for id in known:
		ids.append(int(id))
	if ids != _unit_ids:
		var selected_id: int = _unit_ids[_units.selected] if _units.selected >= 0 and _units.selected < _unit_ids.size() else -1
		_unit_ids = ids
		_units.clear()
		for id in ids:
			_units.add_item(known[id])
		if ids.has(selected_id):
			_units.select(ids.find(selected_id))
	if _unit_ids.is_empty():
		_text.text = "No decisions recorded yet. Start or resume the battle."
		return
	var id: int = _unit_ids[_units.selected]
	var history: Array[Dictionary] = battle_manager.decisions.history_for(id) if _live.button_pressed else _review_entries
	_history.editable = not _live.button_pressed
	_history.set_block_signals(true)
	_history.max_value = max(history.size() - 1, 0)
	if _live.button_pressed:
		_history.value = _history.max_value
	_history.set_block_signals(false)
	var entries: Array[Dictionary] = battle_manager.decisions.records_for(id)
	entries.sort_custom(func(a, b): return a.channel == "Orders / state" and b.channel != "Orders / state")
	if not _live.button_pressed and not history.is_empty():
		entries = [history[int(_history.value)]]
	var lines: Array[String] = []
	lines.append("%s | seed %s" % [battle_manager.clock_string(), str(battle_manager.battle_seed) if battle_manager.battle_seed >= 0 else "random"])
	lines.append("Target evaluation is a choice, not proof a shot fired. Records keep their decision-time evidence.")
	lines.append("History: latest %d changes across all units; current orders take precedence over older target evaluations." % battle_manager.decisions.MAX_EVENTS)
	for entry in entries:
		lines.append("")
		lines.append("%s at %s" % [entry.channel, battle_manager.clock_string(entry.time)])
		lines.append("Choice: %s\nWhy: %s" % [entry.choice, entry.reason])
		if entry.has("profile"):
			var p: Dictionary = entry.profile
			lines.append("Profile: %s | protection %.1f, pressure %.1f, counter mortar %.1f, conservation %.1f" % [CommanderProfile.label(p), p.protection, p.pressure, p.counter_mortar, p.conservation])
			lines.append("Scores are preference weights, not win probabilities. Original rules may override scores." if p.id == "baseline" else "Scores are preference weights, not win probabilities.")
		if entry.has("target_evaluation"):
			lines.append("Target choice at firing: %s" % entry.target_evaluation.get("reason", "No evaluation recorded."))
		if entry.has("pips"):
			lines.append("Strength at capture: %d/%d" % [entry.pips, entry.max_pips])
			if entry.get("rounds", -1) >= 0:
				lines.append("Ammunition: %d | reload remaining: %.1f tactical seconds" % [entry.rounds, entry.reload_remaining])
			if entry.retreat_threshold >= 0.0:
				lines.append("Standing withdrawal threshold: %d%% casualties" % roundi(entry.retreat_threshold * 100))
		if entry.has("position"):
			lines.append("Position at capture: %s m" % str(entry.position))
		if not entry.get("destination", {}).is_empty():
			lines.append("Ordered destination: %s m" % str(entry.destination))
		for key in entry.get("evidence", {}):
			lines.append("%s: %s" % [str(key).replace("_", " "), str(entry.evidence[key])])
		for candidate in entry.get("candidates", []):
			if candidate.eligible:
				lines.append("  %s: %.2f (%s)" % [candidate.target, candidate.score, str(candidate.components)])
			else:
				lines.append("  %s: rejected / %s" % [candidate.target, candidate.rejection])
	_text.text = "\n".join(lines)

func _export(path: String = "user://decision_trace.json") -> void:
	var events: Array[Dictionary] = []
	for entry in battle_manager.decisions.events:
		if entry.team == Unit.Team.PLAYER or _developer.button_pressed:
			events.append(entry.duplicate(true))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_export_status.text = "Could not write decision trace: %s" % error_string(FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify({"schema_version": 1, "seed": battle_manager.battle_seed,
		"developer_view": _developer.button_pressed, "history_limit": battle_manager.decisions.MAX_EVENTS,
		"events": events}, "\t"))
	file.close()
	_export_status.text = "Saved: " + ProjectSettings.globalize_path(path)
