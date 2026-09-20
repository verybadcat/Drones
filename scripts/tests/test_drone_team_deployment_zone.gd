extends SceneTree
## Guards a direct user request: "let's allow the drone team to set up in
## the rear area on all maps" (first phrased about the mortar, then
## corrected: "not the mortar, the drone team"). The drone team shares the
## spotter's per-map deployment zone, which stops at the core map's west
## edge (x=0); in drone-team mode the recon token's zone now extends across
## the whole rear area (the west flank) — GameConfig.drone_team_deployment_
## zone, derived per map — while a SPOTTER and everything else keep their
## own, unextended zones.
##
## Run: godot --headless --path . --script scripts/tests/test_drone_team_deployment_zone.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")


func _make_screen(mode: GameConfig.ReconMode) -> DeploymentScreen:
	var screen := DeploymentScreen.new()
	screen.recon_mode = mode
	root.add_child(screen)
	return screen


func check_map(id: String) -> void:
	GameConfig.set_active_map(id)
	var tag := "[%s] " % id
	var base: Rect2 = GameConfig.CURRENT_MAP.player.spotter_deployment_zone
	var zone: Rect2 = GameConfig.drone_team_deployment_zone()

	check(zone.position.x < 0.0, tag + "the drone team's zone must reach into the rear area (x < 0)")
	check(is_equal_approx(zone.position.x, -(GameConfig.WEST_FLANK_WIDTH_M - 30.0) * GameConfig.PIXELS_PER_METER),
		tag + "the zone must reach the far west of the rear area, keeping the spotter zone's own 30m edge margin")
	check(zone.has_point(Vector2(GameConfig.PLAYER_SAFE_X, base.position.y + 10.0)),
		tag + "the drone team must be allowed to deploy right up to (and past) the retreat safe line")
	check(zone.has_point(base.position) and zone.has_point(base.end - Vector2(1.0, 1.0)),
		tag + "the extended zone must still contain the whole ordinary spotter zone")
	check(is_equal_approx(zone.end.x, base.end.x) and is_equal_approx(zone.position.y, base.position.y) and is_equal_approx(zone.size.y, base.size.y),
		tag + "only the west edge may move — the east edge and the north/south extent stay the spotter zone's")

	var drone_screen := _make_screen(GameConfig.ReconMode.DRONE_TEAM)
	check(drone_screen._spotter_token.kind == Unit.Kind.DRONE_TEAM, tag + "setup check: drone-team mode must produce a drone team token")
	check(drone_screen._spotter_token.deployment_zone == zone, tag + "in drone-team mode the recon token must use the extended zone")
	check(drone_screen._mortar_token.deployment_zone == GameConfig.CURRENT_MAP.player.mortar_deployment_zone,
		tag + "the mortar's zone must NOT change (the request was corrected: not the mortar)")
	for token in drone_screen._squad_tokens:
		check(token.deployment_zone == GameConfig.CURRENT_MAP.player.deployment_zone, tag + "squad zones must not change")
	drone_screen.free()

	var spotter_screen := _make_screen(GameConfig.ReconMode.SPOTTER)
	check(spotter_screen._spotter_token.kind == Unit.Kind.SPOTTER, tag + "setup check: spotter mode must produce a spotter token")
	check(spotter_screen._spotter_token.deployment_zone == base, tag + "a SPOTTER keeps the ordinary, unextended zone")
	spotter_screen.free()


func run() -> void:
	var original: String = ""
	for id in GameConfig.MAPS:
		if GameConfig.CURRENT_MAP == GameConfig.MAPS[id]:
			original = id
	for id in GameConfig.MAPS:
		check_map(id)
	if original != "":
		GameConfig.set_active_map(original)
	print("Drone team deployment zone tests: %d failures (%d maps)" % [failures, GameConfig.MAPS.size()])
	quit(1 if failures else 0)
