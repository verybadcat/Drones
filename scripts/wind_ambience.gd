class_name WindAmbience
extends Node

## The sound of the wind, from the ground-level wind speed on the map's own weather
## block (Weather.wind_speed_10m, gusts ignored, rounded to whole m/s exactly as
## the HUD shows it). Direct user spec:
##   0-4 m/s   no sound
##   5-7 m/s   the soft wind recording
##   8+ m/s    the wind-blowing recording (never the soft one) — at a level
##             "significantly less" than the file's own for 8-11 m/s, and
##             "slightly less" from 12 up
## with the aim that the player hears the wind grow as it gets stronger. It plays
## during deployment as well as the battle (main.gd drives it), and is silent on
## the level-select screen and once the battle is over.
##
## Volumes are set by TARGET LOUDNESS, not per-file dB guesses: the two recordings
## differ by 10 LU (the soft one is far quieter), so a per-file dB table would let
## the level FALL at the 7 -> 8 m/s switch. Each speed has a target loudness
## (LOUDNESS_LUFS below, rising with speed), and the gain applied to a file is that
## target minus the file's own measured loudness — so the audible level rises
## monotonically across every band boundary, and "significantly less" / "slightly
## less" are simply how far below the blowing file's native loudness the targets
## sit (about 7-13 dB, then about 1-3 dB).
##
## Loops: each recording simply loops (AmbientMixer, shared with RainAmbience). The
## blowing one fades out to silence over its last second and in over its first
## quarter-second, so it lulls briefly every 42 s — deliberately left that way
## (user: "it's ok to have some silence interspersed with the wind sound. Wind is
## not constant"). The recordings themselves are used exactly as downloaded (see
## assets/audio/wind/SOURCES.md).

const AmbientMixer = preload("res://scripts/ambient_mixer.gd")

const SOFT_STREAM: AudioStreamMP3 = preload("res://assets/audio/wind/storegraphic-soft-wind-318856.mp3")
const BLOWING_STREAM: AudioStreamMP3 = preload("res://assets/audio/wind/soundreality-wind-blowing-457954.mp3")

## Measured with ffmpeg's ebur128 filter (integrated loudness) on the files as downloaded.
const SOFT_FILE_LUFS: float = -40.4
const BLOWING_FILE_LUFS: float = -30.2

## Whole-mix trim applied to every level below: the one number to move to make all
## wind louder or quieter. With it, the strongest wind sits a few LU under a
## player mortar shot (about -32 LUFS after MORTAR_FIRE_SOUND_VOLUME_DB) and above
## an enemy one — wind is a bed under the fight, not over it. JUDGMENT.
const MASTER_TRIM_DB: float = -4.0

const SILENT_DB: float = AmbientMixer.SILENT_DB

const SOFT_MIN_MPS: int = 5
const BLOWING_MIN_MPS: int = 8

## Target loudness (LUFS, before MASTER_TRIM_DB) per whole m/s. The last entry
## applies to every faster wind. JUDGMENT, shaped by the spec above: each step is
## louder than the last; 8-11 sit well under the blowing file's native -30.2, 12
## and up just under it.
const LOUDNESS_LUFS: Dictionary = {
	5: -50.0, 6: -47.0, 7: -44.0,
	8: -43.0, 9: -41.0, 10: -39.0, 11: -37.0,
	12: -33.0, 13: -32.5, 14: -32.0, 15: -31.5,
}
const LOUDNESS_LUFS_CEILING_MPS: int = 15

var _mixer: AmbientMixer
var _target: Dictionary = {"soft_db": SILENT_DB, "blowing_db": SILENT_DB}


## What the two recordings should be doing at `wind_mps` (ground-level wind,
## gusts ignored; negative or NaN = no wind sound at all): each entry is the
## gain in dB to apply to that file, SILENT_DB when it should not be heard.
static func plan(wind_mps: float) -> Dictionary:
	var off := {"soft_db": SILENT_DB, "blowing_db": SILENT_DB}
	if is_nan(wind_mps) or wind_mps < 0.0:
		return off
	var mps: int = roundi(wind_mps)
	if mps < SOFT_MIN_MPS:
		return off
	var loudness: float = LOUDNESS_LUFS[mini(mps, LOUDNESS_LUFS_CEILING_MPS)]
	if mps < BLOWING_MIN_MPS:
		return {"soft_db": loudness - SOFT_FILE_LUFS + MASTER_TRIM_DB, "blowing_db": SILENT_DB}
	return {"soft_db": SILENT_DB, "blowing_db": loudness - BLOWING_FILE_LUFS + MASTER_TRIM_DB}


## The loudness actually heard at `wind_mps` (LUFS, after the trim), or -INF for
## silence — the audible level implied by plan(), used to check it only rises.
static func heard_loudness(wind_mps: float) -> float:
	var p: Dictionary = plan(wind_mps)
	if p.soft_db > SILENT_DB:
		return p.soft_db + SOFT_FILE_LUFS
	if p.blowing_db > SILENT_DB:
		return p.blowing_db + BLOWING_FILE_LUFS
	return -INF


func _ready() -> void:
	_mixer = AmbientMixer.new()
	add_child(_mixer)
	_mixer.add_layer("soft", SOFT_STREAM)
	_mixer.add_layer("blowing", BLOWING_STREAM)


## Sets the wind to sound like (m/s at ground level; negative = none).
func set_wind(wind_mps: float) -> void:
	_target = plan(wind_mps)


func _process(_delta: float) -> void:
	if _mixer != null:
		_mixer.set_targets({"soft": _target.soft_db, "blowing": _target.blowing_db})
