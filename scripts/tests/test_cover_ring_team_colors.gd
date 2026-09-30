extends SceneTree
## Direct user request, the first concrete step toward an explicit Ukraine-vs-Russia theme: a friendly
## (Ukrainian, blue) unit's in-cover ring is yellow now, not the same green every unit used before — read
## together, blue-and-yellow is the Ukrainian flag. GameConfig.draw_cover_ring is called from four places
## (Unit._draw, BattleHistoryViewer._draw_unit, UnitToken._draw, DeploymentMagnifier — all of which only
## ever show PLAYER units) and is a real rendering call, so the color choice itself is tested through the
## small pure helper it was split out into, GameConfig.cover_ring_color, rather than through actual drawing.
##
## Run: godot --headless --path . --script scripts/tests/test_cover_ring_team_colors.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	test_player_in_cover_is_yellow_not_green()
	test_enemy_in_cover_is_still_green()
	test_exposed_is_the_same_red_for_both_sides()
	test_default_team_param_fails_safe_to_the_old_scheme()
	print("Cover-ring team-color tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_player_in_cover_is_yellow_not_green() -> void:
	var c: Color = GameConfig.cover_ring_color(true, Unit.Team.PLAYER)
	check(c != Color(0.25, 1.0, 0.35, 0.9), "A player unit's in-cover ring is no longer the old green")
	check(c.r > 0.9 and c.g > 0.7 and c.b < 0.3, "A player unit's in-cover ring reads as yellow (%s)" % c)


func test_enemy_in_cover_is_still_green() -> void:
	var c: Color = GameConfig.cover_ring_color(true, Unit.Team.ENEMY)
	check(c == Color(0.25, 1.0, 0.35, 0.9), "An enemy unit's in-cover ring is unchanged (still green) (%s)" % c)


func test_exposed_is_the_same_red_for_both_sides() -> void:
	check(GameConfig.cover_ring_color(false, Unit.Team.PLAYER) == GameConfig.cover_ring_color(false, Unit.Team.ENEMY), "Team never affects the exposed (not-in-cover) ring color")


## GameConfig.draw_cover_ring's own `team` parameter defaults to ENEMY specifically so a call site that
## forgot to pass one draws the OLD green/red scheme rather than silently colouring an unknown unit as if
## it were the player's own.
func test_default_team_param_fails_safe_to_the_old_scheme() -> void:
	check(GameConfig.cover_ring_color(true, Unit.Team.ENEMY) == Color(0.25, 1.0, 0.35, 0.9), "The ENEMY default (used when a caller passes no team) matches the pre-existing green")
