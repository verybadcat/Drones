class_name RainAmbience
extends Node

## The sound of rain, chosen by the weather's own rain class (Weather.
## intensity_class, the same classes the map's weather block labels). Direct user
## spec:
##   drizzle (up to 0.5 mm/h)        the "cozy midnight rain" recording, far quieter than its own
##                                   level and quieter than any other rain sound
##   light rain (0.5 to 2.5 mm/h)    the "gentle rain" recording, quieter than its own level
##   moderate (2.5 to 7.6)           the "drizzle" recording
##   heavy (above 7.6)               the "rain sound" recording — but even that
##                                   played quieter than the file as supplied
## (The classes are the standard rain scale, see Weather; the sound follows the class NAME,
## by the user's decision, so most of the rain this map produces is drizzle or light rain:
## the barely-there midnight rain, or the gentle recording.) Drizzle used to be silent; the
## user then supplied a recording for it: "make it even quieter. Also, it needs to be quieter
## than the quietest current rain sound."
## and "we want the total volume perceived by the user to increase the heavier the
## rain is". Plays during deployment as well as the battle, like the wind (main.gd
## drives it), and is silent on the level-select screen and once the battle is over.
##
## Rain and SLEET make a sound (Weather.precip_type); snow makes none. Sleet has its own recording and
## follows the same class table as rain ("Let's use this sound file for sleet. As usual, it should start at
## a low volume if the sleet is slow, and increase if there is more"): the same target loudness at each
## class, so slow sleet is barely there and heavy sleet is a bed under the fight like heavy rain.
##
## Same approach as WindAmbience, for the same reason: the recordings differ hugely
## in native loudness (the "rain sound" is 15 LU louder than the other two), so each
## class has a TARGET loudness (LOUDNESS_LUFS, rising with the class) and a layer's
## gain is that target minus the recording's own measured loudness — the heard level
## rises at every class boundary, and "quieter than supplied" is simply a target
## below the recording's own level. The recordings are the first 30 seconds of the
## files as downloaded (nothing else committed) and simply loop; see
## assets/audio/rain/SOURCES.md.

const AmbientMixer = preload("res://scripts/ambient_mixer.gd")

const GENTLE_STREAM: AudioStreamMP3 = preload("res://assets/audio/rain/eryliaa-gentle-rain-for-relaxation-and-sleep-337279-first30s.mp3")
const DRIZZLE_STREAM: AudioStreamMP3 = preload("res://assets/audio/rain/freesound_community-drizzle-4perspectives-23254-first30s.mp3")
const HEAVY_STREAM: AudioStreamMP3 = preload("res://assets/audio/rain/boons_freak-rain-sound-188158-first30s.mp3")
## For drizzle. A complete 30-second file as supplied (nothing to trim), so no "-first30s".
const MIDNIGHT_STREAM: AudioStreamMP3 = preload("res://assets/audio/rain/dragon-studio-cozy-midnight-rain-04-448568.mp3")
## For sleet: a complete 39-second file as supplied, steady all the way through (its level varies
## by about 1.5 dB from end to end and it neither fades in nor out), so it loops without a seam.
const SLEET_STREAM: AudioStreamMP3 = preload("res://assets/audio/rain/freesound_community-snow_rain-35637.mp3")

## Measured with ffmpeg's ebur128 filter (integrated loudness) on the 30-second
## clips as committed.
const GENTLE_FILE_LUFS: float = -36.7
const DRIZZLE_FILE_LUFS: float = -37.3
const HEAVY_FILE_LUFS: float = -21.4
const MIDNIGHT_FILE_LUFS: float = -39.5
const SLEET_FILE_LUFS: float = -32.7

const SILENT_DB: float = AmbientMixer.SILENT_DB

## Target heard loudness (LUFS) per rain class. Each is louder than the last; drizzle sits 10.5 dB
## under the midnight-rain recording's own level (and 6 dB under light rain, the next quietest),
## light rain 7 dB under the gentle-rain recording's own level, moderate 3 dB under the "drizzle"
## recording's, and heavy 13 dB under the "rain sound"'s. JUDGMENT throughout (the ordering and
## the "quieter" are the user's; the numbers are mine, set with the wind in mind — the
## strongest wind is about -36 LUFS, a player mortar shot about -32 — so even heavy
## rain is a bed under the fight, not over it).
const LOUDNESS_LUFS: Dictionary = {
	Weather.Intensity.DRIZZLE: -50.0, # 6 dB under the quietest of the others (light rain): the user's rule
	Weather.Intensity.LIGHT: -44.0,
	Weather.Intensity.MODERATE: -40.0,
	Weather.Intensity.HEAVY: -34.0,
}

var _mixer: AmbientMixer
var _target: Dictionary = {}


## The gain (dB) each recording should have for this rain or sleet, SILENT_DB where it
## should not be heard: {"midnight", "gentle", "drizzle", "heavy", "sleet"}. `intensity` is a Weather.
## Intensity, `precip_type` a Weather.Precip.
static func plan(intensity: int, precip_type: int) -> Dictionary:
	var off := {"midnight": SILENT_DB, "gentle": SILENT_DB, "drizzle": SILENT_DB, "heavy": SILENT_DB, "sleet": SILENT_DB}
	if not LOUDNESS_LUFS.has(intensity):
		return off
	if precip_type == Weather.Precip.SLEET:
		off.sleet = LOUDNESS_LUFS[intensity] - SLEET_FILE_LUFS
		return off
	if precip_type != Weather.Precip.RAIN:
		return off
	var loudness: float = LOUDNESS_LUFS[intensity]
	match intensity:
		Weather.Intensity.DRIZZLE:
			off.midnight = loudness - MIDNIGHT_FILE_LUFS
			return off
		Weather.Intensity.LIGHT:
			off.gentle = loudness - GENTLE_FILE_LUFS
			return off
		Weather.Intensity.MODERATE:
			off.drizzle = loudness - DRIZZLE_FILE_LUFS
			return off
	off.heavy = loudness - HEAVY_FILE_LUFS
	return off


## The loudness actually heard for this rain (LUFS), or -INF for silence.
static func heard_loudness(intensity: int, precip_type: int) -> float:
	var p: Dictionary = plan(intensity, precip_type)
	if p.midnight > SILENT_DB:
		return p.midnight + MIDNIGHT_FILE_LUFS
	if p.gentle > SILENT_DB:
		return p.gentle + GENTLE_FILE_LUFS
	if p.drizzle > SILENT_DB:
		return p.drizzle + DRIZZLE_FILE_LUFS
	if p.heavy > SILENT_DB:
		return p.heavy + HEAVY_FILE_LUFS
	if p.sleet > SILENT_DB:
		return p.sleet + SLEET_FILE_LUFS
	return -INF


func _ready() -> void:
	_mixer = AmbientMixer.new()
	add_child(_mixer)
	_mixer.add_layer("midnight", MIDNIGHT_STREAM)
	_mixer.add_layer("gentle", GENTLE_STREAM)
	_mixer.add_layer("drizzle", DRIZZLE_STREAM)
	_mixer.add_layer("heavy", HEAVY_STREAM)
	_mixer.add_layer("sleet", SLEET_STREAM)


## Sets the rain (or sleet) to sound like: a Weather.Intensity and Weather.Precip.
func set_rain(intensity: int, precip_type: int) -> void:
	_target = plan(intensity, precip_type)


func _process(_delta: float) -> void:
	if _mixer != null:
		_mixer.set_targets(_target)
