extends SceneTree
## Guards a real report: "I heard nothing on either enemy mortar shot just
## now." The mortar audio log (added to diagnose exactly this) showed zero
## enemy entries while the enemy's counter-battery replies were visibly
## landing: _resolve_pending_counter_battery is a SECOND firing path that
## shows the muzzle flash and writes the log line but never asked for the
## shot's sound (only _launch_mortar_shot did).
##
## Run: godot --headless --path . --script scripts/tests/test_counter_battery_fire_sound.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func _reply_sound_entries(responder_team: Unit.Team) -> Array:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	var target: Unit = bm._make_unit(Unit.Team.PLAYER if responder_team == Unit.Team.ENEMY else Unit.Team.ENEMY, Unit.Kind.MORTAR, Vector2(0, 0))
	var responder: Unit = bm._make_unit(responder_team, Unit.Kind.MORTAR, Vector2(500, 0))
	bm._pending_counter_battery.append({
		"attacker": responder,
		"target": target,
		"impact_position": target.global_position,
		"fire_time": 0.0,
		"impact_time": 1000000.0,
		"fired": false,
	})
	bm._resolve_pending_counter_battery()
	return bm.mortar_audio_debug_snapshot().log

func run() -> void:
	var enemy_log: Array = _reply_sound_entries(Unit.Team.ENEMY)
	check(enemy_log.size() == 1, "An enemy counter-battery reply must play exactly one shot sound, got %d" % enemy_log.size())
	if enemy_log.size() == 1:
		check(enemy_log[0].team == "enemy", "The reply's sound must be attributed to the enemy responder")
		check(is_equal_approx(enemy_log[0].volume_db, BattleManager.MORTAR_FIRE_SOUND_VOLUME_DB + BattleManager.ENEMY_MORTAR_FIRE_SOUND_EXTRA_ATTENUATION_DB),
			"An enemy reply must get the same quieter enemy volume as its ordinary fire")

	var player_log: Array = _reply_sound_entries(Unit.Team.PLAYER)
	check(player_log.size() == 1, "A player counter-battery reply must play exactly one shot sound too, got %d" % player_log.size())

	print("Counter-battery fire sound tests: %d failures" % failures)
	quit(1 if failures else 0)
