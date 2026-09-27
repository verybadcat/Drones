extends SceneTree
## Direct user spec for rain sound, by the standard rain class names (drizzle, up to
## 0.5 mm/h, is silent; if that makes most rain silent, that is fine): light rain the first
## 30 s of the "gentle rain" recording, quieter than the file; moderate the "drizzle"
## recording; heavy the "rain sound" recording, but even that quieter than supplied;
## "the total volume perceived by the user [should] increase the heavier the rain is";
## only the first 30 s of each file committed, documented as from the same site as the
## wind recordings. Plays from deployment through the battle, like the wind.
##
## Run: godot --headless --path . --script scripts/tests/test_rain_ambience.gd
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func heard(p: Dictionary) -> Array:
	var out := []
	for id in ["midnight", "gentle", "drizzle", "heavy", "sleet"]:
		if p[id] > RainAmbience.SILENT_DB:
			out.append(id)
	return out

func run() -> void:
	test_which_recording_for_which_rain()
	test_the_level_rises_with_the_rain()
	test_quieter_than_supplied()
	test_only_rain_and_sleet_make_a_sound()
	test_sleet()
	test_the_node_fades_and_switches()
	test_the_project_only_holds_the_first_thirty_seconds_and_says_where_they_came_from()
	print("Rain ambience tests: %d failures" % failures)
	quit(1 if failures else 0)


func test_which_recording_for_which_rain() -> void:
	var rain: int = Weather.Precip.RAIN
	check(heard(RainAmbience.plan(Weather.Intensity.NONE, rain)).is_empty(), "Not raining: no sound")
	check(heard(RainAmbience.plan(Weather.Intensity.NONE, Weather.Precip.NONE)).is_empty(), "No precipitation at all: no sound")
	check(heard(RainAmbience.plan(Weather.Intensity.DRIZZLE, rain)) == ["midnight"], "Drizzle: the midnight rain")
	check(heard(RainAmbience.plan(Weather.Intensity.LIGHT, rain)) == ["gentle"], "Light rain: the gentle rain")
	check(heard(RainAmbience.plan(Weather.Intensity.MODERATE, rain)) == ["drizzle"], "Moderate rain: the drizzle")
	check(heard(RainAmbience.plan(Weather.Intensity.HEAVY, rain)) == ["heavy"], "Heavy rain: the rain sound")


## "The total volume perceived by the user to increase the heavier the rain is" —
## across every class boundary, though the three recordings differ by up to 15 LU in
## their own loudness.
func test_the_level_rises_with_the_rain() -> void:
	check(RainAmbience.heard_loudness(Weather.Intensity.NONE, Weather.Precip.RAIN) == -INF, "Silence when it is not raining")
	var previous := -INF
	for intensity in [Weather.Intensity.DRIZZLE, Weather.Intensity.LIGHT, Weather.Intensity.MODERATE, Weather.Intensity.HEAVY]:
		var level: float = RainAmbience.heard_loudness(intensity, Weather.Precip.RAIN)
		check(level > previous, "Heard level must rise with the class: %s is %.1f LUFS after %.1f" % [Weather.Intensity.keys()[intensity], level, previous])
		previous = level


func test_quieter_than_supplied() -> void:
	var rain: int = Weather.Precip.RAIN
	var light: float = RainAmbience.plan(Weather.Intensity.LIGHT, rain).gentle
	check(light < 0.0, "The gentle rain is quieter than the file (%.1f dB)" % light)
	# Drizzle: quieter than its own file, and quieter than the quietest of the other rain sounds
	# ("even quieter ... it needs to be quieter than the quietest current rain sound").
	var drizzle_gain: float = RainAmbience.plan(Weather.Intensity.DRIZZLE, rain).midnight
	check(drizzle_gain < -6.0, "The midnight rain is played well under its own level (%.1f dB)" % drizzle_gain)
	var quietest_other: float = INF
	for intensity in [Weather.Intensity.LIGHT, Weather.Intensity.MODERATE, Weather.Intensity.HEAVY]:
		quietest_other = minf(quietest_other, RainAmbience.heard_loudness(intensity, rain))
	var drizzle_heard: float = RainAmbience.heard_loudness(Weather.Intensity.DRIZZLE, rain)
	check(drizzle_heard < quietest_other - 3.0, "Drizzle is clearly quieter than the quietest other rain sound (%.1f vs %.1f LUFS)" % [drizzle_heard, quietest_other])
	var heavy: float = RainAmbience.plan(Weather.Intensity.HEAVY, rain).heavy
	check(heavy < 0.0, "Even the 'rain sound' is played quieter than supplied (%.1f dB)" % heavy)
	check(heavy <= -3.0, "...clearly quieter, not a rounding error (%.1f dB)" % heavy)


## Rain and sleet make a sound (sleet its own, tested below); snow makes none.
func test_only_rain_and_sleet_make_a_sound() -> void:
	for intensity in [Weather.Intensity.DRIZZLE, Weather.Intensity.LIGHT, Weather.Intensity.MODERATE, Weather.Intensity.HEAVY]:
		check(heard(RainAmbience.plan(intensity, Weather.Precip.SNOW)).is_empty(), "Snow at %s makes no sound" % Weather.Intensity.keys()[intensity])
	check(heard(RainAmbience.plan(Weather.Intensity.NONE, Weather.Precip.SLEET)).is_empty(), "No sleet, no sound")
	# And main.gd feeds it the weather's own class and type, on the wind's terms.
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	check("rain_ambience.set_rain(" in main_src and "Weather.current.intensity_class() if weather_audible" in main_src and "Weather.current.precip_type() if weather_audible" in main_src, "main.gd feeds the rain sound the weather's class and type while the weather is audible (deployment to battle end)")


func step(rain, dt: float) -> void:
	rain._process(dt)
	rain._mixer._process(dt)

func test_the_node_fades_and_switches() -> void:
	var rain := RainAmbience.new()
	root.add_child(rain)
	var mixer = rain._mixer
	rain.set_rain(Weather.Intensity.MODERATE, Weather.Precip.RAIN)
	step(rain, 0.1)
	check(mixer.level_db("drizzle") < RainAmbience.plan(Weather.Intensity.MODERATE, Weather.Precip.RAIN).drizzle, "It fades in, it doesn't jump")
	step(rain, 30.0)
	check(mixer.is_playing("drizzle") and not mixer.is_playing("gentle") and not mixer.is_playing("heavy"), "Moderate rain: only the drizzle is playing")
	rain.set_rain(Weather.Intensity.HEAVY, Weather.Precip.RAIN)
	step(rain, 30.0)
	check(mixer.is_playing("heavy") and not mixer.is_playing("drizzle"), "Heavier rain switches to the rain sound")
	rain.set_rain(Weather.Intensity.LIGHT, Weather.Precip.RAIN)
	step(rain, 30.0)
	check(mixer.is_playing("gentle") and not mixer.is_playing("heavy"), "Lighter rain switches back to the gentle rain")
	rain.set_rain(Weather.Intensity.DRIZZLE, Weather.Precip.RAIN)
	step(rain, 30.0)
	check(mixer.is_playing("midnight") and not mixer.is_playing("gentle"), "Drizzle switches to the midnight rain")
	rain.set_rain(Weather.Intensity.NONE, Weather.Precip.NONE)
	step(rain, 30.0)
	check(not mixer.is_playing("midnight") and not mixer.is_playing("gentle") and not mixer.is_playing("drizzle") and not mixer.is_playing("heavy"), "No rain: silence, everything stopped")
	rain.set_rain(Weather.Intensity.LIGHT, Weather.Precip.SLEET)
	step(rain, 30.0)
	check(mixer.is_playing("sleet") and not mixer.is_playing("gentle"), "Sleet plays the sleet recording, alone")
	rain.set_rain(Weather.Intensity.NONE, Weather.Precip.NONE)
	step(rain, 30.0)
	check(not mixer.is_playing("sleet"), "...and stops with the sleet")
	check(mixer.loops("midnight") and mixer.loops("gentle") and mixer.loops("drizzle") and mixer.loops("heavy") and mixer.loops("sleet"), "All five recordings loop")
	rain.free()


func test_the_project_only_holds_the_first_thirty_seconds_and_says_where_they_came_from() -> void:
	for stream in [RainAmbience.GENTLE_STREAM, RainAmbience.DRIZZLE_STREAM, RainAmbience.HEAVY_STREAM]:
		var length: float = stream.get_length()
		check(length > 29.0 and length <= 30.5, "Each committed clip is the first 30 seconds only (%.2f s)" % length)
	var dir := DirAccess.open("res://assets/audio/rain")
	var mp3s := 0
	for f in dir.get_files():
		if f.ends_with(".mp3"):
			mp3s += 1
			check("first30s" in f or f == "dragon-studio-cozy-midnight-rain-04-448568.mp3" or f == "freesound_community-snow_rain-35637.mp3", "Only trimmed clips (or the one file that is 30 s whole) are in the project (found %s)" % f)
	check(mp3s == 5, "Exactly the five clips (found %d)" % mp3s)
	check(RainAmbience.SLEET_STREAM.get_length() > 38.0 and RainAmbience.SLEET_STREAM.get_length() < 40.0, "The sleet clip is the complete file (%.2f s)" % RainAmbience.SLEET_STREAM.get_length())
	check(RainAmbience.MIDNIGHT_STREAM.get_length() > 29.0 and RainAmbience.MIDNIGHT_STREAM.get_length() <= 30.5, "The drizzle clip is a complete 30-second file (%.2f s)" % RainAmbience.MIDNIGHT_STREAM.get_length())
	var note := FileAccess.get_file_as_string("res://assets/audio/rain/SOURCES.md")
	check("Pixabay" in note and "same site as the wind" in note, "The note says they came from the same site as the wind recordings (Pixabay)")
	for name in ["eryliaa-gentle-rain-for-relaxation-and-sleep-337279", "freesound_community-drizzle-4perspectives-23254", "boons_freak-rain-sound-188158", "dragon-studio-cozy-midnight-rain-04-448568", "freesound_community-snow_rain-35637"]:
		check(name in note, "The note names %s" % name)
	check("first 30 seconds" in note, "...and says only the first 30 seconds were kept")


## Direct user request: "Let's use this sound file for sleet. As usual, it should start at a low volume if
## the sleet is slow, and increase if there is more."
func test_sleet() -> void:
	var sleet: int = Weather.Precip.SLEET
	var classes := [Weather.Intensity.DRIZZLE, Weather.Intensity.LIGHT, Weather.Intensity.MODERATE, Weather.Intensity.HEAVY]
	for intensity in classes:
		check(heard(RainAmbience.plan(intensity, sleet)) == ["sleet"], "Sleet at %s: the sleet recording, and only it" % Weather.Intensity.keys()[intensity])
	var previous := -INF
	for intensity in classes:
		var level: float = RainAmbience.heard_loudness(intensity, sleet)
		check(level > previous, "Sleet gets louder with each class: %s is %.1f LUFS after %.1f" % [Weather.Intensity.keys()[intensity], level, previous])
		previous = level
	var slow: float = RainAmbience.heard_loudness(Weather.Intensity.DRIZZLE, sleet)
	check(slow <= -45.0, "Slow sleet starts at a low volume (%.1f LUFS, against the file's own %.1f)" % [slow, RainAmbience.SLEET_FILE_LUFS])
	check(RainAmbience.heard_loudness(Weather.Intensity.HEAVY, sleet) <= -30.0, "...and even heavy sleet is a bed under the fight, not over it")
	# The gain is the target minus the file's measured loudness, so the sleet file's own level does not matter.
	var gain: float = RainAmbience.plan(Weather.Intensity.MODERATE, sleet).sleet
	check(is_equal_approx(gain, RainAmbience.LOUDNESS_LUFS[Weather.Intensity.MODERATE] - RainAmbience.SLEET_FILE_LUFS), "The gain is the class's target loudness less the file's own (%.1f dB)" % gain)
	check(gain < -3.0, "Always well under the file as supplied (%.1f dB)" % gain)
	# Sleet and rain follow the same class table, so a sleet class is as loud as the same rain class.
	check(is_equal_approx(RainAmbience.heard_loudness(Weather.Intensity.LIGHT, sleet), RainAmbience.heard_loudness(Weather.Intensity.LIGHT, Weather.Precip.RAIN)), "A class of sleet is as loud as the same class of rain")
