extends SceneTree
## Direct user follow-up right after the first version of the seed box's hover help shipped: "The help
## text goes off the screen the way you have it... I mouse over and the text is too long for the single
## line that pops up." Root cause: a plain `tooltip_text` on a bare Control uses Godot's default tooltip,
## a single unwrapped line. HelpIcon overrides `_make_custom_tooltip` (a Control virtual Godot calls to
## build the tooltip popup itself) to return a real, word-wrapped, fixed-width panel instead.
##
## Run: godot --headless --path . --script scripts/tests/test_help_icon.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	test_shows_a_quiet_question_mark()
	test_custom_tooltip_wraps_instead_of_one_long_line()
	print("Help icon tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_shows_a_quiet_question_mark() -> void:
	var icon := HelpIcon.new()
	check(icon.text == "(?)", "Shows a quiet question mark")
	check(icon.mouse_filter == Control.MOUSE_FILTER_STOP, "Accepts the mouse (a Label ignores it by default, which would silently block any tooltip, custom or not, from ever triggering)")
	icon.free()


## The whole point: find the actual Label Godot would display inside the custom tooltip panel, and confirm
## it carries the real text AND is set to wrap at a fixed, reasonably screen-sized width -- not however
## wide the single-line text would naturally render.
func test_custom_tooltip_wraps_instead_of_one_long_line() -> void:
	var icon := HelpIcon.new()
	var long_text := "Using the same seed again, on the same location and reconnaissance setup, gives you the same weather and the same enemy force (how many squads and mortars, and where they start), and the game's dice start from the same place. It does not replay the battle: what happens after that depends on what you do and on the exact timing of the game's frames, so the fight will still go its own way."
	icon.tooltip_text = long_text
	var tooltip: Object = icon._make_custom_tooltip(long_text)
	check(tooltip != null and tooltip is Control, "A real Control is returned, not null (null would fall back to Godot's own default one-line tooltip)")
	var label: Label = null
	var stack: Array[Node] = [tooltip]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label:
			label = n
		for c in n.get_children():
			stack.append(c)
	check(label != null, "The returned tooltip contains a Label somewhere")
	if label != null:
		check(label.text == long_text, "...carrying the full text, unabridged")
		check(label.autowrap_mode != TextServer.AUTOWRAP_OFF, "...set to actually wrap, not render as one long line")
		check(label.custom_minimum_size.x > 0.0 and label.custom_minimum_size.x < 600.0, "...at a fixed, screen-reasonable width (got %.0f)" % label.custom_minimum_size.x)
	tooltip.free()
	icon.free()
