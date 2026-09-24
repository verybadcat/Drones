extends SceneTree
## Guards a direct user request: "Let's have the enemy mortar be quieter
## than the friendly ones. Try reducing it by 10 decibels when it's an
## enemy mortar firing."
##
## Run: godot --headless --path . --script scripts/tests/test_enemy_mortar_quieter.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

## The pool's most-recently-used player -- _play_mortar_fire_sound already
## advanced the round-robin index past it, so this looks one slot back.
func _last_played_volume(bm: BattleManager) -> float:
	var count: int = bm._mortar_fire_sound_players.size()
	var index: int = (bm._mortar_fire_sound_pool_index - 1 + count) % count
	return bm._mortar_fire_sound_players[index].volume_db

func run() -> void:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)

	bm._play_mortar_fire_sound(Unit.Team.PLAYER)
	var player_vol: float = _last_played_volume(bm)
	bm._play_mortar_fire_sound(Unit.Team.ENEMY)
	var enemy_vol: float = _last_played_volume(bm)

	check(is_equal_approx(player_vol, BattleManager.MORTAR_FIRE_SOUND_VOLUME_DB),
		"A player mortar shot should play at the plain base volume, got %s" % player_vol)
	check(is_equal_approx(enemy_vol, BattleManager.MORTAR_FIRE_SOUND_VOLUME_DB + BattleManager.ENEMY_MORTAR_FIRE_SOUND_EXTRA_ATTENUATION_DB),
		"An enemy mortar shot should play at the base volume plus the extra attenuation, got %s" % enemy_vol)
	check(is_equal_approx(player_vol - enemy_vol, 10.0),
		"The enemy mortar must sound exactly 10dB quieter than the player's, got a %sdB difference" % (player_vol - enemy_vol))

	print("Enemy mortar quieter tests: %d failures" % failures)
	quit(1 if failures else 0)
