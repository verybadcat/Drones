extends Control
class_name DoctrinePanel
## Sidebar doctrine controls that aren't a map position: retreat threshold
## per squad, and the mortar's shoot-and-scoot doctrine. Starting positions
## are set on DeploymentScreen instead (drag and drop) — see main.gd, which
## reads from both this panel and the deployment screen to build the
## doctrine dict when Start Battle is pressed.
##
## No retreat-threshold control for the mortar: a mortar crew is either in
## action or knocked out by a single hit, not worn down by percent casualties
## the way a squad is — see Unit.take_hit().

var _squad_thresholds: Array[HSlider] = []
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

	for i in 3:
		root.add_child(_build_squad_section("Squad %d" % (i + 1)))
		root.add_child(HSeparator.new())

	root.add_child(_build_mortar_section())


func _build_squad_section(label_text: String) -> Control:
	var box := VBoxContainer.new()

	var label := GameConfig.make_selectable_label(label_text)
	box.add_child(label)

	var threshold_row := HBoxContainer.new()
	var threshold_label := GameConfig.make_selectable_label("Retreat threshold (%% casualties):")
	# Sitting in an HBoxContainer (the horizontal/main axis, unlike every
	# other converted label here which stretches to a VBoxContainer's full
	# width on the cross axis), this RichTextLabel never gets a real width to
	# wrap against before computing its own minimum size — with autowrap
	# left on, that produced a wildly inflated height (~760px measured,
	# wrapped as if against a near-zero-width column), pushing every section
	# below it off the visible panel. This label was never meant to wrap
	# anyway — it's a short inline caption next to a slider — so turning
	# autowrap off restores exactly the single-line sizing the plain Label
	# it replaced always had.
	threshold_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	threshold_row.add_child(threshold_label)
	var threshold_slider := HSlider.new()
	threshold_slider.min_value = 10
	threshold_slider.max_value = 90
	threshold_slider.step = 5
	threshold_slider.value = 30
	threshold_slider.custom_minimum_size = Vector2(140, 0)
	threshold_row.add_child(threshold_slider)
	box.add_child(threshold_row)

	_squad_thresholds.append(threshold_slider)
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
	scoot_check.text = "Shoot and scoot (relocate after every shot)"
	scoot_row.add_child(scoot_check)
	box.add_child(scoot_row)
	_mortar_shoot_and_scoot = scoot_check

	var scoot_note := GameConfig.make_selectable_label("Relocation itself takes as long as the walk does, at a realistic pace — no separate cooldown to set.")
	scoot_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(scoot_note)

	return box


func get_squad_retreat_thresholds() -> Array[float]:
	var out: Array[float] = []
	for s in _squad_thresholds:
		out.append(s.value / 100.0)
	return out


func get_mortar_doctrine() -> Dictionary:
	return {
		"shoot_and_scoot": _mortar_shoot_and_scoot.button_pressed,
	}
