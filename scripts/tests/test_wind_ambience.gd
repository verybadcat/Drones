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
	check("var weather_audible: bool = Weather.current != null and not (battle_manager != null and battle_manager.battle_over)" in main_src, "It sounds from deployment (weather rolled) until the battle is over, and not on the level-select screen")


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


func test_the_recordings_and_their_source_are_documented() -> void:
	check(WindAmbience.SOFT_STREAM.get_length() > 10.0 and WindAmbience.BLOWING_STREAM.get_length() > 30.0, "Both recordings load")
	var note := FileAccess.get_file_as_string("res://assets/audio/wind/SOURCES.md")
	check("https://pixabay.com/sound-effects/search/wind/" in note, "The sourcing note gives the Pixabay page the recordings came from")
	check("storegraphic-soft-wind-318856.mp3" in note and "soundreality-wind-blowing-457954.mp3" in note, "...and names both files")
