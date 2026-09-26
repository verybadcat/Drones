extends SceneTree
## Direct user spec for the sound of squads shooting: quiet, "definitely quieter than mortars";
## friendly squads louder than enemy ones, "but still not loud"; "have gunfire start at a random place
## in the file each time"; "only have one copy of the file playing at any given time"; and "if both
## sides are firing, you do it at the higher volume, and also if only friendlies are firing".
##
## Run: godot --headless --path . --script scripts/tests/test_gunfire_ambience.gd
const TestCombatLogScript := preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	test_which_side_sets_the_level()
	test_quieter_than_the_mortars()
	test_one_copy_at_a_random_place_and_it_fades_out()
	test_the_battle_reports_squad_shots()
	test_the_recording_is_documented()
	print("Gunfire ambience tests: %d failures" % failures)
	quit(1 if failures else 0)


## The mortar clips' sample peak as they are on disk (16-bit), in dBFS.
func mortar_clip_peak_dbfs() -> float:
	var peak := 0
	for stream in BattleManager.MORTAR_FIRE_SOUNDS:
		# The imported resource is compressed (QOA); read the file itself as plain 16-bit samples.
		var wav := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(stream.resource_path))
		var data: PackedByteArray = wav.data
		for i in range(0, data.size() - 1, 2):
			var sample := data.decode_s16(i)
			peak = maxi(peak, absi(sample))
	return 20.0 * log(float(peak) / 32768.0) / log(10.0)


func gunfire_peak_dbfs(gain_db: float) -> float:
	return GunfireAmbience.FILE_PEAK_DBFS + gain_db


func test_which_side_sets_the_level() -> void:
	var hold := GunfireAmbience.HOLD_S
	var friendly: float = GunfireAmbience.plan(0.0, INF)
	var enemy: float = GunfireAmbience.plan(INF, 0.0)
	check(friendly > enemy, "Friendly gunfire is louder than enemy gunfire (%.1f vs %.1f dB)" % [friendly, enemy])
	check(GunfireAmbience.plan(0.0, 0.0) == friendly, "Both sides firing: the higher (friendly) volume")
	check(GunfireAmbience.plan(hold - 0.1, 0.0) == friendly, "...and while friendlies are still within the hold window")
	check(GunfireAmbience.plan(hold + 0.1, 0.0) == enemy, "Friendlies quiet, enemy firing: the enemy volume")
	check(GunfireAmbience.plan(hold + 0.1, hold - 0.1) == enemy, "...")
	check(GunfireAmbience.plan(hold + 0.1, hold + 0.1) == GunfireAmbience.SILENT_DB, "Nobody has fired lately: silence")
	check(GunfireAmbience.plan(INF, INF) == GunfireAmbience.SILENT_DB, "Nobody has fired yet: silence")
	check(GunfireAmbience.FRIENDLY_LUFS - GunfireAmbience.ENEMY_LUFS >= 5.0, "Enemy fire is clearly quieter than friendly (%.1f dB apart)" % (GunfireAmbience.FRIENDLY_LUFS - GunfireAmbience.ENEMY_LUFS))
	check(GunfireAmbience.HOLD_S > Unit.new().fire_interval, "The hold window outlasts a squad's 2 s between shots, so a fight never stutters")


## "Definitely quieter than mortars", each side against its own mortars: the mortar clips'
## peak (read from the files) less the playback gain BattleManager gives that side, against
## the gunfire's peak at its level; 6 dB clear, and nothing near full scale.
func test_quieter_than_the_mortars() -> void:
	var clip_peak := mortar_clip_peak_dbfs()
	check(clip_peak > -13.0 and clip_peak < -11.0, "The mortar clips peak near -12 dBFS (read %.2f)" % clip_peak)
	var friendly_mortar_peak: float = clip_peak + BattleManager.MORTAR_FIRE_SOUND_VOLUME_DB
	var enemy_mortar_peak: float = friendly_mortar_peak + BattleManager.ENEMY_MORTAR_FIRE_SOUND_EXTRA_ATTENUATION_DB
	var friendly_peak := gunfire_peak_dbfs(GunfireAmbience.plan(0.0, INF))
	var enemy_peak := gunfire_peak_dbfs(GunfireAmbience.plan(INF, 0.0))
	check(friendly_peak <= friendly_mortar_peak - 6.0, "Friendly gunfire's peak (%.1f dBFS) is at least 6 dB under a friendly mortar's (%.1f)" % [friendly_peak, friendly_mortar_peak])
	check(enemy_peak <= enemy_mortar_peak - 6.0, "Enemy gunfire's peak (%.1f dBFS) is at least 6 dB under an enemy mortar's (%.1f)" % [enemy_peak, enemy_mortar_peak])
	check(friendly_peak < -20.0, "Not loud: even friendly gunfire's peak is below -20 dBFS (%.1f)" % friendly_peak)


func test_one_copy_at_a_random_place_and_it_fades_out() -> void:
	var gunfire := GunfireAmbience.new()
	root.add_child(gunfire)
	var mixer: AmbientMixer = gunfire._mixer
	check(not gunfire.is_playing(), "Silent until something fires")
	# Fire, and let time pass a frame at a time as the engine would.
	var starts: Array[float] = []
	for cycle in 8:
		gunfire.report_shot(Unit.Team.PLAYER)
		gunfire._process(0.1)
		mixer._process(0.1)
		check(gunfire.is_playing(), "A shot starts the recording")
		var players := 0
		for child in mixer.get_children():
			if child is AudioStreamPlayer and child.playing:
				players += 1
		check(players == 1, "Exactly one copy playing (%d)" % players)
		starts.append(mixer.get_child(0).get_playback_position())
		# Shots keep coming for a while (two a second here): still the one copy, not restarted.
		var position_before: float = mixer.get_child(0).get_playback_position()
		for i in 10:
			gunfire.report_shot(Unit.Team.ENEMY if i % 2 == 0 else Unit.Team.PLAYER)
			gunfire._process(0.5)
			mixer._process(0.5)
		var players_after := 0
		for child in mixer.get_children():
			if child is AudioStreamPlayer and child.playing:
				players_after += 1
		check(players_after == 1 and gunfire.is_playing(), "A running fight keeps the one copy going")
		# The shooting stops: it fades out and stops.
		for i in 20:
			gunfire._process(0.5)
			mixer._process(0.5)
		check(not gunfire.is_playing(), "Some seconds after the last shot it has stopped")
	var distinct := {}
	for s in starts:
		distinct[snappedf(s, 0.001)] = true
	check(distinct.size() >= 4, "Each new burst of fire starts at a different place in the file (%d different of 8)" % distinct.size())
	check(mixer.loops("gunfire"), "It loops for a long fight")
	gunfire.free()


## The real firing path: a squad's shot tells the sound which side fired.
func test_the_battle_reports_squad_shots() -> void:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = TestCombatLogScript.new()
	check(bm._gunfire_ambience != null and bm._gunfire_ambience.get_parent() == bm, "The battle has a gunfire sound")
	var mine: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.SQUAD, Vector2.ZERO)
	var theirs: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.SQUAD, Vector2(200.0 * GameConfig.PIXELS_PER_METER, 0))
	mine.is_visible = true # each side can see the other, so each has something to shoot at
	theirs.is_visible = true
	bm.player_units.append(mine)
	bm.enemy_units.append(theirs)
	seed(3)
	var gun: GunfireAmbience = bm._gunfire_ambience
	var fired_player := false
	var fired_enemy := false
	for i in 40:
		mine.fire_timer = 0.0
		theirs.fire_timer = 0.0
		var before_f: float = gun._since_friendly_shot
		var before_e: float = gun._since_enemy_shot
		gun._since_friendly_shot = 100.0
		gun._since_enemy_shot = 100.0
		bm._tick_fire(mine, 0.1, 6.0, bm.enemy_units)
		if gun._since_friendly_shot == 0.0:
			fired_player = true
		check(gun._since_enemy_shot == 100.0, "A player squad's shot does not report an enemy shot")
		gun._since_friendly_shot = 100.0
		bm._tick_fire(theirs, 0.1, 6.0, bm.player_units)
		if gun._since_enemy_shot == 0.0:
			fired_enemy = true
		check(gun._since_friendly_shot == 100.0, "An enemy squad's shot does not report a friendly shot")
	check(fired_player and fired_enemy, "Both sides' squads reach the shooting path in this setup (player %s, enemy %s)" % [fired_player, fired_enemy])
	bm.combat_log.free()
	bm.free()


func test_the_recording_is_documented() -> void:
	check(GunfireAmbience.STREAM.get_length() > 39.0 and GunfireAmbience.STREAM.get_length() < 41.0, "The recording loads (%.1f s)" % GunfireAmbience.STREAM.get_length())
	var note := FileAccess.get_file_as_string("res://assets/audio/gunfire/SOURCES.md")
	check("freesound_community-battle-war-zone-gun-fight-32155.mp3" in note and "-21.4 LUFS" in note, "The sourcing note names the file and its loudness")
