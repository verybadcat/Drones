extends SceneTree
## Direct user spec for wind sound: 0-4 m/s no sound; 5-7 the soft recording; 8+
## the wind-blowing recording (never the soft one), "significantly less" in
## volume for 8-11 m/s and "slightly less" from 12 up; all from the GROUND-level
## wind speed, gusts ignored; and "we want the user to get the impression of
## increasing sound as the wind gets stronger". It plays during deployment and the
## battle. (Silence interspersed is fine — the recordings just loop.)
##
## Run: godot --headless --path . --script scripts/tests/test_wind_ambience.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func heard(p: Dictionary) -> Array:
	var out := []
	if p.soft_db > WindAmbience.SILENT_DB:
		out.append("soft")
	if p.blowing_db > WindAmbience.SILENT_DB:
		out.append("blowing")
	return out

## One frame of the node and its mixer, as the engine would run them.
func step(wind, dt: float) -> void:
	wind._process(dt)
	wind._mixer._process(dt)

func run() -> void:
	test_the_bands()
	test_the_level_only_rises_with_the_wind()
	test_significantly_less_then_slightly_less()
	test_rounding_and_gusts()
	test_the_node_fades_in_and_out()
	test_the_sound_holds_its_recording_near_a_rounding_edge()
	test_the_real_wind_near_the_edge_rarely_switches()
	test_a_handover_between_recordings_does_not_dip()
	test_the_recordings_and_their_source_are_documented()
	print("Wind ambience tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_the_bands() -> void:
	for mps in [0, 1, 2, 3, 4]:
		check(heard(WindAmbience.plan(float(mps))).is_empty(), "%d m/s: no sound" % mps)
	for mps in [5, 6, 7]:
		check(heard(WindAmbience.plan(float(mps))) == ["soft"], "%d m/s: the soft wind, and only it (got %s)" % [mps, str(heard(WindAmbience.plan(float(mps))))])
	for mps in [8, 9, 10, 11, 12, 13, 15, 20, 30]:
		check(heard(WindAmbience.plan(float(mps))) == ["blowing"], "%d m/s: the blowing file, never the soft one (got %s)" % [mps, str(heard(WindAmbience.plan(float(mps))))])
	check(heard(WindAmbience.plan(-1.0)).is_empty() and heard(WindAmbience.plan(NAN)).is_empty(), "No wind (negative / NaN, as main.gd passes off-screen and after a battle): no sound")


## "The impression of increasing sound as the wind gets stronger": across every
## band boundary too — the soft recording is 10 LU quieter than the blowing one, so
## a naive per-file volume would DROP at 7 -> 8.
func test_the_level_only_rises_with_the_wind() -> void:
	var previous := -INF
	for mps in range(5, 16):
		var level: float = WindAmbience.heard_loudness(float(mps))
		check(level > previous, "The heard level must rise at every step: %d m/s is %.1f LUFS after %.1f" % [mps, level, previous])
		previous = level
	check(WindAmbience.heard_loudness(30.0) >= WindAmbience.heard_loudness(15.0), "...and never falls for stronger wind beyond that")
	check(WindAmbience.heard_loudness(4.0) == -INF, "...from silence up")


## Blowing-file gain relative to the file's own loudness (the whole-mix trim
## removed, so this is the spec's "less" and not the master level).
func test_significantly_less_then_slightly_less() -> void:
	for mps in [8, 9, 10, 11]:
		var rel: float = WindAmbience.plan(float(mps)).blowing_db - WindAmbience.MASTER_TRIM_DB
		check(rel <= -6.0 and rel >= -15.0, "%d m/s: significantly below the file's own level (%.1f dB)" % [mps, rel])
	for mps in [12, 13, 14, 15, 25]:
		var rel: float = WindAmbience.plan(float(mps)).blowing_db - WindAmbience.MASTER_TRIM_DB
		check(rel < 0.0 and rel >= -4.0, "%d m/s: only slightly below the file's own level (%.1f dB)" % [mps, rel])


## Whole m/s exactly as the HUD prints it (roundi), and the ground-level speed
## with no gust factor anywhere.
func test_rounding_and_gusts() -> void:
	check(WindAmbience.plan(4.4) == WindAmbience.plan(4.0), "4.4 m/s reads as 4: silent")
	check(WindAmbience.plan(4.6) == WindAmbience.plan(5.0), "4.6 m/s reads as 5: soft wind")
	check(WindAmbience.plan(7.4) == WindAmbience.plan(7.0) and WindAmbience.plan(7.6) == WindAmbience.plan(8.0), "The soft/blowing switch is at 7.5, like the HUD's rounding")
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	check("wind_ambience.set_wind(Weather.current.wind_speed_10m if weather_audible" in main_src, "main.gd feeds it the ground-level wind_speed_10m")
	check(not ("WIND_GUST_RATIO_PEAK" in FileAccess.get_file_as_string("res://scripts/wind_ambience.gd")), "Gusts appear nowhere in the wind sound")
	check("var weather_audible: bool = Weather.current != null and current_screen.shows_weather() and not current_screen.battle_is_over()" in main_src, "It sounds from deployment (weather rolled) until the battle is over, and not on the level-select screen")


func test_the_node_fades_in_and_out() -> void:
	var wind := WindAmbience.new()
	root.add_child(wind)
	var mixer = wind._mixer
	wind.set_wind(10.0)
	step(wind, 0.1)
	check(mixer.level_db("blowing") < WindAmbience.plan(10.0).blowing_db, "It fades in, it doesn't jump (%.1f dB after 0.1 s)" % mixer.level_db("blowing"))
	step(wind, 30.0)
	check(is_equal_approx(mixer.level_db("blowing"), WindAmbience.plan(10.0).blowing_db) and mixer.is_playing("blowing"), "10 m/s: the blowing recording is playing at its level")
	check(not mixer.is_playing("soft") and mixer.level_db("soft") <= WindAmbience.SILENT_DB + 0.5, "...and the soft one is not")
	wind.set_wind(6.0)
	step(wind, 30.0)
	check(mixer.is_playing("soft") and not mixer.is_playing("blowing"), "Dropping to 6 m/s switches to the soft recording")
	wind.set_wind(2.0)
	step(wind, 30.0)
	check(not mixer.is_playing("soft") and not mixer.is_playing("blowing"), "Dropping to 2 m/s: silence, both stopped")
	check(mixer.loops("soft") and mixer.loops("blowing"), "Both recordings loop")
	wind.free()


## Hovering near 7.5 m/s used to flip soft <-> blowing about 46 times a real minute ("we need
## a fix to keep it from switching back and forth too much like we did with rain"). The whole-m/s
## figure the sound follows is held until the wind is 0.25 m/s beyond the rounding edge.
func test_the_sound_holds_its_recording_near_a_rounding_edge() -> void:
	check(WindAmbience.held_mps(-1, 7.4) == 7 and WindAmbience.held_mps(-1, 7.6) == 8, "With nothing held yet it simply rounds")
	check(WindAmbience.held_mps(7, 7.6) == 7 and WindAmbience.held_mps(7, 7.74) == 7, "Held at 7: 7.6 is past the edge but not by the margin, so it stays")
	check(WindAmbience.held_mps(7, 7.8) == 8, "...and 7.8 (0.3 past the edge) moves it to 8")
	check(WindAmbience.held_mps(8, 7.4) == 8 and WindAmbience.held_mps(8, 7.26) == 8, "Held at 8: 7.4 is under the edge but not by the margin, so it stays")
	check(WindAmbience.held_mps(8, 7.2) == 7, "...and 7.2 moves it back to 7")
	check(WindAmbience.held_mps(7, 12.0) == 12 and WindAmbience.held_mps(12, 3.0) == 3, "A real change of wind follows at once, either way")
	# Through the node: dither across 7.5 does not touch the recording; a real move does.
	var wind := WindAmbience.new()
	root.add_child(wind)
	var mixer = wind._mixer
	wind.set_wind(7.2)
	step(wind, 30.0)
	check(mixer.is_playing("soft") and not mixer.is_playing("blowing"), "7.2 m/s: the soft recording")
	var switches := 0
	var last_heard := "soft"
	for wind_mps in [7.55, 7.45, 7.6, 7.4, 7.7, 7.35, 7.65, 7.5, 7.7, 7.3]:
		wind.set_wind(wind_mps)
		step(wind, 1.0)
		var now := "soft" if mixer.is_playing("soft") and mixer.level_db("soft") > WindAmbience.SILENT_DB + 3.0 else "blowing"
		if now != last_heard:
			switches += 1
			last_heard = now
	check(switches == 0, "Dithering 7.3 to 7.7 m/s never leaves the soft recording (%d switches)" % switches)
	check(not mixer.is_playing("blowing"), "...and never starts the blowing one")
	wind.set_wind(8.0)
	step(wind, 30.0)
	check(mixer.is_playing("blowing") and not mixer.is_playing("soft"), "A genuine 8.0 m/s does switch to the blowing recording")
	for wind_mps in [7.7, 7.55, 7.45, 7.6, 7.3]:
		wind.set_wind(wind_mps)
		step(wind, 30.0)
		check(mixer.is_playing("blowing") and not mixer.is_playing("soft"), "Held at 8: %.2f m/s stays on the blowing recording" % wind_mps)
	wind.set_wind(-1.0)
	step(wind, 30.0)
	wind.set_wind(7.6)
	check(WindAmbience.plan(float(wind._held_mps)) == WindAmbience.plan(8.0), "After silence the hold is forgotten: 7.6 rounds to 8")
	wind.free()


## The real weather model, started at 7.5 m/s (the worst place to be), a real minute at normal
## speed (about one tactical second a frame at 60 frames a second): following the wind's whole-m/s
## figure directly flips soft <-> blowing dozens of times (measured mean 40, worst 140); the held
## figure a handful at most (measured mean 1.2, worst 4).
func test_the_real_wind_near_the_edge_rarely_switches() -> void:
	var lo := -3.0
	var hi := 5.0
	for i in 60:
		var mid := (lo + hi) / 2.0
		if Weather._speed_from_z(mid) < 7.5:
			lo = mid
		else:
			hi = mid
	var raw_switches := 0
	var held_switches := 0
	var trials := 30
	for trial in trials:
		var weather := Weather.roll(trial + 1)
		weather._wind_z = lo
		weather.wind_speed_10m = Weather._speed_from_z(lo)
		var held := -1
		var raw_soft := true
		var held_soft := true
		for frame in 3600:
			weather.advance(1.0)
			held = WindAmbience.held_mps(held, weather.wind_speed_10m)
			var now_raw := roundi(weather.wind_speed_10m) < WindAmbience.BLOWING_MIN_MPS
			var now_held := held < WindAmbience.BLOWING_MIN_MPS
			if frame > 0 and now_raw != raw_soft:
				raw_switches += 1
			if frame > 0 and now_held != held_soft:
				held_switches += 1
			raw_soft = now_raw
			held_soft = now_held
	check(float(raw_switches) / trials > 10.0, "The scenario really is a wind hovering at the edge (unheld: %.1f switches a minute)" % (float(raw_switches) / trials))
	check(float(held_switches) / trials < 3.0, "Held: fewer than 3 soft/blowing switches a real minute (%.2f)" % (float(held_switches) / trials))


## The two recordings hand over with equal power: while one fades out and the other in, the summed
## power stays near the steady level (it used to sag ~13 dB halfway, since both ramped in dB).
func test_a_handover_between_recordings_does_not_dip() -> void:
	var wind := WindAmbience.new()
	root.add_child(wind)
	var mixer = wind._mixer
	wind.set_wind(7.0)
	step(wind, 30.0)
	var soft_level: float = WindAmbience.plan(7.0).soft_db
	var blowing_level: float = WindAmbience.plan(8.0).blowing_db
	wind.set_wind(8.0)
	# Compare against the steadier of the two ends' powers (the levels differ by design):
	# the sum must never fall below the quieter end by more than 1.5 dB.
	var floor_db: float = minf(soft_level, blowing_level) - 1.5
	var worst := INF
	for i in 80:
		step(wind, 0.05)
		var power: float = pow(10.0, mixer.level_db("soft") / 10.0) + pow(10.0, mixer.level_db("blowing") / 10.0)
		worst = minf(worst, 10.0 * log(power) / log(10.0))
	check(worst >= floor_db, "Mid-handover the summed level stays within 1.5 dB of the quieter end (worst %.1f dB, floor %.1f)" % [worst, floor_db])
	wind.free()


func test_the_recordings_and_their_source_are_documented() -> void:
	check(WindAmbience.SOFT_STREAM.get_length() > 10.0 and WindAmbience.BLOWING_STREAM.get_length() > 30.0, "Both recordings load")
	var note := FileAccess.get_file_as_string("res://assets/audio/wind/SOURCES.md")
	check("https://pixabay.com/sound-effects/search/wind/" in note, "The sourcing note gives the Pixabay page the recordings came from")
	check("storegraphic-soft-wind-318856.mp3" in note and "soundreality-wind-blowing-457954-seamless-loop.ogg" in note, "...and names both files")
	# The blowing recording started in silence, swelled for seconds and faded at the end, so every
	# loop had a break ("the break in the wind sound at 8 m/s is distracting"). It is now a seamless
	# loop: the swell cut off, the end crossfaded onto the start (41.75 s file -> about 33.75 s).
	var blowing_length: float = WindAmbience.BLOWING_STREAM.get_length()
	check(blowing_length > 33.0 and blowing_length < 34.5, "The blowing recording is the rebuilt loop (%.2f s; the download was 42.74 s)" % blowing_length)
	check("seamless" in note and "swell" in note and "crossfade" in note, "The note records how the loop was made")
	var dir := DirAccess.open("res://assets/audio/wind")
	var files: Array = []
	for f in dir.get_files():
		if f.ends_with(".mp3") or f.ends_with(".ogg"):
			files.append(f)
	files.sort()
	check(files == ["soundreality-wind-blowing-457954-seamless-loop.ogg", "storegraphic-soft-wind-318856.mp3"], "Only the soft download and the rebuilt loop are in the project (found %s)" % str(files))
