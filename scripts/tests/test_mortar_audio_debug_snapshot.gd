extends SceneTree
## Guards the mortar-fire audio diagnostics added directly in response to a
## real, unresolved report: "sometimes I hear the enemy mortar and sometimes
## I don't... it was not just fast forward. Try to give yourself any
## relevant visibility into what is going on." Nothing in the firing/time-
## scale code read so far explains a missed shot, so BattleManager now logs
## every _play_mortar_fire_sound call (see mortar_audio_debug_snapshot) with
## enough real-world detail (Time.get_ticks_msec, pool-reuse state, tactical
## pace, contact status) to diagnose the next real occurrence directly,
## rather than reasoning about it statically again.
##
## Run: godot --headless --path . --script scripts/tests/test_mortar_audio_debug_snapshot.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	var player_mortar: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.MORTAR, Vector2.ZERO)
	var enemy_mortar: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2.ZERO)

	bm._play_mortar_fire_sound(player_mortar)
	bm._play_mortar_fire_sound(enemy_mortar)
	var snap: Dictionary = bm.mortar_audio_debug_snapshot()

	check(snap.log.size() == 2, "Expected one log entry per shot, got %d" % snap.log.size())
	check(snap.pool_size == BattleManager.MORTAR_FIRE_SOUND_POOL_SIZE, "pool_size should report the real pool size")

	var player_entry: Dictionary = snap.log[0]
	check(player_entry.team == "player", "First entry should be tagged player, got %s" % player_entry.team)
	check(player_entry.mortar == player_mortar.display_name(), "Entry should name the exact firing mortar")
	check(is_equal_approx(player_entry.volume_db, BattleManager.MORTAR_FIRE_SOUND_VOLUME_DB),
		"Player entry's logged volume should match what was actually played")
	check(not player_entry.player_was_already_playing, "A pool player's very first use should not read as already playing")
	check(not player_entry.skipped_not_in_tree, "A real, in-tree BattleManager should never report a skipped shot")

	var enemy_entry: Dictionary = snap.log[1]
	check(enemy_entry.team == "enemy", "Second entry should be tagged enemy, got %s" % enemy_entry.team)
	check(is_equal_approx(enemy_entry.volume_db, BattleManager.MORTAR_FIRE_SOUND_VOLUME_DB + BattleManager.ENEMY_MORTAR_FIRE_SOUND_EXTRA_ATTENUATION_DB),
		"Enemy entry's logged volume should include the extra attenuation")

	# Cycle the WHOLE pool exactly once more (11 more shots, 13 total) so the
	# very next call lands back on the first player used above -- with real
	# clip durations well over a second and this whole loop taking a
	# negligible fraction of a real second, that player must still be mid-
	# clip, which is exactly the "did we just cut off a still-playing shot"
	# signal this log exists to catch.
	for i in BattleManager.MORTAR_FIRE_SOUND_POOL_SIZE - 1:
		bm._play_mortar_fire_sound(player_mortar)
	var wrapped_entry: Dictionary = bm.mortar_audio_debug_snapshot().log[-1]
	check(wrapped_entry.player_was_already_playing,
		"Reusing a pool player before its previous clip could plausibly have finished should read as already playing")

	# The log must stay bounded even across a long stretch of real firing.
	for i in BattleManager.MORTAR_AUDIO_LOG_LIMIT + 20:
		bm._play_mortar_fire_sound(player_mortar)
	check(bm.mortar_audio_debug_snapshot().log.size() == BattleManager.MORTAR_AUDIO_LOG_LIMIT,
		"The audio log must stay capped at MORTAR_AUDIO_LOG_LIMIT, not grow unbounded across a whole battle")

	print("Mortar audio debug snapshot tests: %d failures" % failures)
	quit(1 if failures else 0)
