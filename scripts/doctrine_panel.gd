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

var _threshold_slider: HSlider
var _mortar_shoot_and_scoot: CheckBox


func _ready() -> void:
	custom_minimum_size = Vector2(320, 500)
	size = custom_minimum_size

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var title := GameConfig.make_selectable_label("Holding the village. Drag your units into position on the map, set doctrine below, then start the battle.")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(title)

	root.add_child(_build_retreat_section())
	root.add_child(HSeparator.new())
	root.add_child(_build_mortar_section())


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
	var threshold_label := GameConfig.make_selectable_label("Retreat threshold (%% casualties):")
	threshold_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(threshold_label)
	var threshold_slider := HSlider.new()
	threshold_slider.min_value = 10
	threshold_slider.max_value = 90
	threshold_slider.step = 5
	threshold_slider.value = 30
	threshold_slider.custom_minimum_size = Vector2(140, 0)
	box.add_child(threshold_slider)

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
