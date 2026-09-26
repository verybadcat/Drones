extends Control
class_name DoctrinePanel
## The setup screen's sidebar: the one line of instruction and the battle seed. It used to hold
## every preference (orders by unit type, the standing retreat threshold, the mortar's shoot and
## scoot, both commanders' profiles); the user asked to get rid of most of it ("During the setup, I
## want to get rid of most of the part at the right of the screen (the preferences). I do want to
## keep the part below, and also keep the battle seed") and those are now always their defaults:
## the baseline commander profile for both sides (retreat at 50% casualties), no per-type orders,
## and a mortar that shoots and scoots. Starting positions are set on DeploymentScreen (drag and
## drop) — see DeploymentPhase, which reads from both this panel and the deployment screen to build
## the doctrine dict when Start Battle is pressed.

const CommanderProfile = preload("res://scripts/commander_profile.gd")
const UnitDoctrine = preload("res://scripts/unit_doctrine.gd")
var _seed: SpinBox

## The panel's height: what it holds, and the Start Battle button sits just under it.
const PANEL_HEIGHT: float = 150.0


func _ready() -> void:
	custom_minimum_size = Vector2(320, PANEL_HEIGHT)
	size = custom_minimum_size

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var title := GameConfig.make_selectable_label("Holding %s. Drag your units into position on the map, set doctrine below, then start the battle." % GameConfig.CURRENT_MAP.name)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(title)

	root.add_child(GameConfig.make_selectable_label("Battle seed (-1 = random)"))
	_seed = SpinBox.new()
	_seed.min_value = -1
	_seed.max_value = 2147483647
	_seed.value = -1
	root.add_child(_seed)


## The standing retreat order for the whole force: the baseline profile's, 50% casualties.
func get_retreat_threshold() -> float:
	return CommanderProfile.preset("baseline").retreat_threshold


func get_mortar_doctrine() -> Dictionary:
	return {"shoot_and_scoot": true}


func get_commander_doctrine() -> Dictionary:
	return {"player_profile": CommanderProfile.preset("baseline"),
		"enemy_profile": CommanderProfile.preset("baseline"),
		"player_unit_types": UnitDoctrine.sanitize({}),
		"enemy_unit_types": UnitDoctrine.sanitize({}),
		"seed": int(_seed.value)}
