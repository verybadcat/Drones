extends SceneTree
## Direct user report: "It was difficult to drag my units during setup. I made multiple tries to click on a unit." Cause: units start
## close together (on Voznesensk the spotter's centre is 9 px from one squad's and 14 px from another's, circles 32 px across) and a
## press took the first token in the list that it touched, so pressing on the spotter, drawn on top, grabbed a squad underneath it.
## A press now picks the token whose centre is nearest, and the one drawn on top when two are equally near.
##
## Run: godot --headless --path . --script scripts/tests/test_deployment_token_pick.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var original: String = GameConfig.current_map_id()
	for map_id in GameConfig.MAPS.keys():
		GameConfig.set_active_map(map_id)
		var screen := DeploymentScreen.new()
		root.add_child(screen)
		var tokens: Array = screen._tokens
		check(tokens.size() == 5, "%s: three squads, a mortar and a recon token (%d)" % [map_id, tokens.size()])
		for token in tokens:
			check(screen.token_at(token.position) == token, "%s: pressing on the centre of %s picks %s up (got %s)" % [map_id, token.label_text, token.label_text, str(screen.token_at(token.position).label_text) if screen.token_at(token.position) != null else "nothing"])
			# a few pixels off the centre, towards the open side, still picks the same one when nothing else is nearer
			var nudged: Vector2 = token.position + Vector2(3.0, -2.0)
			var got: UnitToken = screen.token_at(nudged)
			var nearest: UnitToken = null
			var nearest_d := INF
			for other in tokens:
				if other.position.distance_to(nudged) < nearest_d:
					nearest_d = other.position.distance_to(nudged)
					nearest = other
			check(got == nearest, "%s: a press 3 px off %s picks the nearest token" % [map_id, token.label_text])
		check(screen.token_at(Vector2(-99999.0, -99999.0)) == null, "%s: a press on nothing picks nothing" % map_id)
		# No two tokens start closer than a token is wide (and a little more): inside that, a press on one lands on its neighbour about half the
		# time even with the nearest-centre rule. Direct user report: "when I click squad 2 to drag it, it only responds about half the time".
		var too_close := 0
		for a in tokens.size():
			for b in range(a + 1, tokens.size()):
				if tokens[a].position.distance_to(tokens[b].position) < 2.0 * UnitToken.RADIUS + 4.0:
					too_close += 1
		check(too_close == 0, "%s: no two tokens start closer than 36 px (%d pairs do)" % [map_id, too_close])
		screen.free()
	# Two tokens exactly on top of each other: the one drawn on top (the later) wins.
	GameConfig.set_active_map("pishchane")
	var stacked := DeploymentScreen.new()
	root.add_child(stacked)
	stacked._tokens[0].position = stacked._tokens[4].position
	check(stacked.token_at(stacked._tokens[4].position) == stacked._tokens[4], "Two tokens at the very same spot: the one on top is picked")
	stacked.free()
	GameConfig.set_active_map(original)
	print("Deployment token pick tests: %d failures" % failures)
	quit(1 if failures else 0)
