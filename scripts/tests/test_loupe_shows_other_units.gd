extends SceneTree
## Direct user request: "I want the blow-up diagram during squad placement to show other nearby squads. They should be visibly different from the
## squad being placed." The loupe (DeploymentMagnifier) now takes the other placed units and draws those inside its window as hollow, coloured,
## labelled rings under the placed unit's own translucent disc and crosshair. DeploymentPhase feeds it every frame.
##
## Run: godot --headless --path . --script scripts/tests/test_loupe_shows_other_units.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var half: float = DeploymentMagnifier.WINDOW_SIZE.x / 2.0 / DeploymentMagnifier.ZOOM # map px from the focus to the window's edge
	var focus := Vector2(500.0, 500.0)
	var tokens: Array = [
		{"position": focus + Vector2(20.0, 0.0), "kind": Unit.Kind.SQUAD, "label": "Squad 2"},
		{"position": focus + Vector2(-10.0, 15.0), "kind": Unit.Kind.MORTAR, "label": "Mortar"},
		{"position": focus + Vector2(half * 3.0, 0.0), "kind": Unit.Kind.SQUAD, "label": "Squad 3"},
		{"position": focus + Vector2(0.0, -half * 3.0), "kind": Unit.Kind.SPOTTER, "label": "Spotter"},
	]
	var seen: Array = DeploymentMagnifier.others_in_view(focus, tokens)
	check(seen.size() == 2, "Only the units inside the window are drawn (%d of 4)" % seen.size())
	var labels: Array[String] = []
	for s in seen:
		labels.append(s.label)
	check("Squad 2" in labels and "Mortar" in labels, "...the nearby squad and the mortar (%s)" % str(labels))
	check(not ("Squad 3" in labels) and not ("Spotter" in labels), "...and not those far outside it")
	for s in seen:
		if s.label == "Squad 2":
			check(s.offset.is_equal_approx(Vector2(20.0, 0.0) * DeploymentMagnifier.ZOOM), "A unit 20 map px away is drawn 20 x zoom window px from the centre (%s)" % str(s.offset))
	check(DeploymentMagnifier.others_in_view(focus, []).is_empty(), "With nobody else placed nothing extra is drawn")
	# the phase feeds the loupe: open the real deployment screen, mark a squad as the one shown, and read what the loupe was given
	var main = load("res://scripts/main.gd").new()
	root.add_child(main)
	await process_frame
	main._show_deployment()
	await process_frame
	var phase: DeploymentPhase = main.current_screen
	var shown: UnitToken = phase.deployment_screen._squad_tokens[1]
	phase._magnifier_last_token = shown
	await process_frame
	await process_frame
	var fed: Array = phase.deployment_magnifier.others
	var tokens_total: int = phase.deployment_screen._tokens.size()
	check(fed.size() == tokens_total - 1, "The loupe is given every other token (%d of %d)" % [fed.size(), tokens_total - 1])
	var names: Array[String] = []
	for f in fed:
		names.append(f.label)
	check("Squad 1" in names and "Squad 3" in names and not ("Squad 2" in names), "...the other squads by name, and not the one being placed (%s)" % str(names))
	check(phase.deployment_magnifier.focus_position == shown.position, "...and it is focused on the one being placed")
	print("Loupe shows other units tests: %d failures" % failures)
	quit(1 if failures else 0)
