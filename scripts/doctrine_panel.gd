extends Control
class_name DoctrinePanel
## Sidebar doctrine controls that aren't a map position: one shared retreat
## threshold for the whole force, and the mortar's shoot-and-scoot doctrine.
## Starting positions are set on DeploymentScreen instead (drag and drop) —
## see main.gd, which reads from both this panel and the deployment screen
## to build the doctrine dict when Start Battle is pressed.
##
## No retreat-threshold control for the mortar: a mortar crew is either in
## action or knocked out by a single hit, not worn down by percent casualties
## the way a squad is — see Unit.take_hit().

const CommanderProfile = preload("res://scripts/commander_profile.gd")
var _player_profile: OptionButton
var _enemy_profile: OptionButton
var _profile_note: RichTextLabel
var _weights: Dictionary = {}
var _deterministic: CheckBox
var _seed: SpinBox
var _threshold_value: Label
var _threshold_slider: HSlider
var _mortar_shoot_and_scoot: CheckBox


func _ready() -> void:
	custom_minimum_size = Vector2(320, 500)
	size = custom_minimum_size

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	scroll.add_child(root)

	var title := GameConfig.make_selectable_label("Holding the village. Drag your units into position on the map, set doctrine below, then start the battle.")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(title)

	root.add_child(_build_retreat_section())
	root.add_child(HSeparator.new())
	root.add_child(_build_mortar_section())
	root.add_child(HSeparator.new())
	root.add_child(_build_profiles())


## ONE standing order for the whole force, not a separate breaking point
## negotiated per squad — real infantry doctrine is explicit that a unit
## "never withdraws except upon the verified order of higher authority"
## (FM 3-21.8): a squad doesn't decide for itself, from its own casualties
## alone, that it's time to pull out — that call belongs to command. This
## slider IS that order, a single coherent piece of commander's intent
## ("hold as long as you can" vs. "don't get decisively engaged, pull back
## early to preserve the force") given up front as part of the defensive
## plan, applied identically to every squad — not three separately dialed-
## in percentages as if each squad negotiated its own terms with command.
## Giving it in advance, rather than only live, means nobody has to get a
## radio call through mid-fight to do something already authorized — the
## General Retreat button remains the same authority's live override on
## top of it, a further, later order from the same source.
func _build_retreat_section() -> Control:
	var box := VBoxContainer.new()

	var label := GameConfig.make_selectable_label("Standing order, whole force")
	box.add_child(label)

	# Stacked (label above, slider below) rather than side by side — packed
	# into an HBoxContainer, the label's own single-line width (~264px) plus
	# the slider's 140px minimum summed to more than this panel's fixed
	# 320px width, with nothing clipping the overflow: the excess just drew
	# straight past the sidebar and off the right edge of the window. Each
	# on its own line comfortably fits the panel's width alone.
	var threshold_label := GameConfig.make_selectable_label("Retreat threshold (% casualties):")
	threshold_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(threshold_label)
	var threshold_slider := HSlider.new()
	threshold_slider.min_value = 10
	threshold_slider.max_value = 90
	threshold_slider.step = 5
	threshold_slider.value = 30
	threshold_slider.custom_minimum_size = Vector2(140, 0)
	box.add_child(threshold_slider)

	_threshold_value = Label.new()
	_threshold_value.text = "30% casualties"
	box.add_child(_threshold_value)
	threshold_slider.value_changed.connect(func(value): _threshold_value.text = "%d%% casualties" % int(value))
	_threshold_slider = threshold_slider
	return box


func _build_mortar_section() -> Control:
	var box := VBoxContainer.new()

	var label := GameConfig.make_selectable_label("Mortar")
	box.add_child(label)

	var note := GameConfig.make_selectable_label("A mortar crew is either in action or knocked out by a hit — no retreat threshold to set.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)

	var scoot_row := HBoxContainer.new()
	var scoot_check := CheckBox.new()
	# Kept short deliberately — a CheckBox draws its own text on one line
	# with no wrapping, and the fuller "(relocate after every shot)" phrasing
	# used to push this past the panel's width with nothing to clip the
	# overflow. The detail lives in the note below instead.
	scoot_check.text = "Shoot and scoot"
	scoot_row.add_child(scoot_check)
	box.add_child(scoot_row)
	_mortar_shoot_and_scoot = scoot_check

	var scoot_note := GameConfig.make_selectable_label("Relocates after every shot. The walk itself takes as long as it takes, at a realistic pace — no separate cooldown to set.")
	scoot_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(scoot_note)

	return box


func get_retreat_threshold() -> float:
	return _threshold_slider.value / 100.0


func get_mortar_doctrine() -> Dictionary:
	return {
		"shoot_and_scoot": _mortar_shoot_and_scoot.button_pressed,
	}


func _build_profiles() -> Control:
	var box := VBoxContainer.new()
	box.add_child(GameConfig.make_selectable_label("Commander profiles"))
	box.add_child(GameConfig.make_selectable_label("Your commander"))
	_player_profile = OptionButton.new()
	_enemy_profile = OptionButton.new()
	for label in CommanderProfile.LABELS:
		_player_profile.add_item(label)
		_enemy_profile.add_item(label)
	box.add_child(_player_profile)
	_profile_note = GameConfig.make_selectable_label()
	_profile_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_profile_note)
	for i in CommanderProfile.AXES.size():
		box.add_child(GameConfig.make_selectable_label(CommanderProfile.AXIS_LABELS[i]))
		var spin := SpinBox.new()
		spin.min_value = 0.1
		spin.max_value = 3.0
		spin.step = 0.1
		spin.value = 1.0
		_weights[CommanderProfile.AXES[i]] = spin
		box.add_child(spin)
	_deterministic = CheckBox.new()
	_deterministic.text = "Deterministic target choices"
	box.add_child(_deterministic)
	box.add_child(GameConfig.make_selectable_label("Enemy commander"))
	box.add_child(_enemy_profile)
	var note := GameConfig.make_selectable_label("Profiles tune firing preferences. Retreat follows the standing threshold above. Movement and emergency rules still apply. Archetypes are fictional; the deliberate evaluator is a local scoring policy.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	box.add_child(GameConfig.make_selectable_label("Battle seed (-1 = random)"))
	_seed = SpinBox.new()
	_seed.min_value = -1
	_seed.max_value = 2147483647
	_seed.value = -1
	box.add_child(_seed)
	_player_profile.item_selected.connect(_on_profile_selected)
	_on_profile_selected(0)
	return box


func _on_profile_selected(index: int) -> void:
	var p: Dictionary = CommanderProfile.preset(CommanderProfile.IDS[index])
	_profile_note.text = CommanderProfile.description(p.id)
	_threshold_slider.value = p.retreat_threshold * 100.0
	for axis in CommanderProfile.AXES:
		_weights[axis].value = p[axis]
		_weights[axis].editable = p.id != "baseline"
	_deterministic.button_pressed = p.deterministic
	_deterministic.disabled = p.id == "baseline"


func get_commander_doctrine() -> Dictionary:
	var p: Dictionary = CommanderProfile.preset(CommanderProfile.IDS[_player_profile.selected])
	for axis in CommanderProfile.AXES:
		p[axis] = _weights[axis].value
	p.deterministic = _deterministic.button_pressed
	p.retreat_threshold = get_retreat_threshold()
	return {"player_profile": p,
		"enemy_profile": CommanderProfile.preset(CommanderProfile.IDS[_enemy_profile.selected]),
		"seed": int(_seed.value)}
