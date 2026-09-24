extends Control
class_name LevelSelectScreen
## The very first screen the player sees: choose which real place to fight
## over (see GameConfig.MAPS) and which reconnaissance/target-acquisition
## setup to fight with (see GameConfig.ReconMode). main.gd shows this before
## deployment and reads the choices off map_chosen/mode_chosen. Built the
## same programmatic way as every other screen in this game — no separate
## .tscn.

const BattleScore = preload("res://scripts/battle_score.gd")
const BattleScoreLog = preload("res://scripts/battle_score_log.gd")

signal mode_chosen(mode: GameConfig.ReconMode)
## Emitted the moment the map dropdown's selection changes — live, not
## gated behind a separate "Choose" button, since there's nothing to
## commit to first the way there is for recon mode (which shapes the rest
## of deployment). main.gd reacts immediately so this screen's own
## location readout, and everything else GameConfig.CURRENT_MAP-derived,
## is already showing the newly-picked place before the player moves on.
signal map_chosen(map_id: String)

## Index -> map id, in the same order the dropdown lists them — an
## OptionButton only ever hands back an index, never the id string itself.
var _map_ids: Array[String] = []

## The durable score history shown at the bottom (see BattleScoreLog). Public
## so a test can point it at a disposable file BEFORE this screen enters the
## tree; nothing else should reassign it.
var score_log := BattleScoreLog.new()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var root := VBoxContainer.new()
	root.position = Vector2(60, 50)
	root.add_theme_constant_override("separation", 20)
	add_child(root)

	root.add_child(_build_map_picker())

	var title := GameConfig.make_selectable_label("Choose your reconnaissance setup")
	title.add_theme_font_size_override("normal_font_size", 22)
	root.add_child(title)

	root.add_child(_build_option(
		GameConfig.RECON_MODE_LABELS[GameConfig.ReconMode.SPOTTER],
		"The original setup: a small ground team calls in fire on whatever it can see from wherever you post it.",
		GameConfig.ReconMode.SPOTTER
	))
	root.add_child(_build_option(
		GameConfig.RECON_MODE_LABELS[GameConfig.ReconMode.DRONE_TEAM],
		"Replaces the spotter with a 3-person team equipped with four Mavic-3 scout drones, plus spare batteries",
		GameConfig.ReconMode.DRONE_TEAM
	))

	root.add_child(_build_score_history())


## Average battle score per SCENARIO — a scenario being the location plus the
## kind of scouting the player used (user's definition) — from the durable
## history in BattleScoreLog, which survives restarts and code updates.
## Scores are re-scored under the current rubric. Scrolls if it ever outgrows its space (3 locations x 2 setups).
func _build_score_history() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var title := GameConfig.make_selectable_label("Your average scores")
	title.add_theme_font_size_override("normal_font_size", 17)
	box.add_child(title)

	var summaries: Array[Dictionary] = BattleScoreLog.summarize(score_log.load_records())
	if summaries.is_empty():
		box.add_child(GameConfig.make_selectable_label("No battles scored yet."))
		return box

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(820, 150)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 24)
	scroll.add_child(grid)
	for heading in ["Scenario", "Battles", "Average", "Best", "Worst"]:
		grid.add_child(_cell(heading, true))
	for entry in summaries:
		grid.add_child(_cell(scenario_label(entry.map_id, entry.recon_mode), false))
		grid.add_child(_cell(str(entry.count), false))
		grid.add_child(_cell(BattleScore.format(entry.average), false))
		grid.add_child(_cell(BattleScore.format(entry.best), false))
		grid.add_child(_cell(BattleScore.format(entry.worst), false))
	return box


func _cell(text: String, heading: bool) -> Label:
	var label := Label.new()
	label.text = text
	if heading:
		label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	return label


## "Pishchane — Level 1 — Drone Recon". A map or mode this build no longer
## knows (removed or renamed since the record was written) shows its stored
## id instead — old history is never hidden just because the catalog changed.
static func scenario_label(map_id: String, recon_mode: String) -> String:
	var map_name: String = GameConfig.MAPS[map_id].name if GameConfig.MAPS.has(map_id) else map_id
	var mode_label: String = GameConfig.RECON_MODE_LABELS[GameConfig.ReconMode[recon_mode]] if GameConfig.ReconMode.has(recon_mode) else recon_mode
	return "%s — %s" % [map_name, mode_label]


## Every real place in the catalog, by its own place name — GameConfig.
## MAPS' own keys (e.g. "pervomaiske") are internal ids, never shown.
## Defaults to whichever map is already active (the one main.gd's window
## was just sized for), not always the first entry, so opening this screen
## never silently re-picks a different map than what's actually loaded.
func _build_map_picker() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var label := GameConfig.make_selectable_label("Location")
	box.add_child(label)

	var picker := OptionButton.new()
	var selected_index := 0
	for map_id in GameConfig.MAPS:
		if GameConfig.CURRENT_MAP == GameConfig.MAPS[map_id]:
			selected_index = _map_ids.size()
		_map_ids.append(map_id)
		picker.add_item(GameConfig.MAPS[map_id].name)
	picker.select(selected_index)
	picker.item_selected.connect(func(index: int): map_chosen.emit(_map_ids[index]))
	box.add_child(picker)

	return box


func _build_option(title_text: String, body_text: String, mode: GameConfig.ReconMode) -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(820, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.12, 0.92)
	style.set_content_margin_all(16.0)
	style.set_corner_radius_all(6.0)
	box.add_theme_stylebox_override("panel", style)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	box.add_child(inner)

	var option_title := GameConfig.make_selectable_label(title_text)
	option_title.add_theme_font_size_override("normal_font_size", 17)
	inner.add_child(option_title)

	var body := GameConfig.make_selectable_label(body_text)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(780, 0)
	inner.add_child(body)

	var button := Button.new()
	button.text = "Choose"
	button.pressed.connect(func(): mode_chosen.emit(mode))
	inner.add_child(button)

	return box
