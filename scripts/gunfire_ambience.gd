class_name GunfireAmbience
extends Node

## The sound of squads shooting at each other. Direct user spec: "They should not be loud.
## Definitely quieter than mortars. Friendly squads firing should be louder than enemy ones,
## but still not loud. Use this file. Have gunfire start at a random place in the file each
## time. Also, only have one copy of the file playing at any given time." And: "if both sides
## are firing, you do it at the higher volume, and also if only friendlies are firing".
##
## One looping recording on one AmbientMixer layer, so there is only ever one copy playing, and
## the mixer starts it at a random point each time it becomes audible (after a silence). BattleManager
## calls report_shot(team) for every direct-fire shot; the recording is audible while a shot has been
## fired within HOLD_S real seconds (squads fire every 2 s, so a firefight is continuous and it fades
## out about three seconds after the last shot). Its level is the friendly one while any player squad
## has fired within that window, whatever the enemy is doing, else the enemy one.
##
## Levels (target heard loudness, as for wind and rain): the mortar clips are normalised to a peak of
## -12 dBFS and played at MORTAR_FIRE_SOUND_VOLUME_DB, so a friendly mortar's peak is -22 dBFS and an
## enemy mortar's -32 (BattleManager). This file's own peak is -2.5 dBFS at -21.4 LUFS, so its peak in the
## mix is the target LUFS + 18.9 dB. Friendly gunfire sits at -48 LUFS (peak about -29 dBFS, 7 dB under a
## friendly mortar's), enemy gunfire at -57 (peak about -38 dBFS, 6 dB under an enemy mortar's, and 9 dB
## under the friendly gunfire). JUDGMENT, not by ear: the enemy figure is near what wind and rain can mask,
## so it is the first thing to retune if enemy fire cannot be heard.

const STREAM: AudioStreamMP3 = preload("res://assets/audio/gunfire/freesound_community-battle-war-zone-gun-fight-32155.mp3")
## The file's own integrated loudness (ffmpeg ebur128), and its sample peak relative to it.
const FILE_LUFS: float = -21.4
const FILE_PEAK_DBFS: float = -2.5
const FRIENDLY_LUFS: float = -48.0
const ENEMY_LUFS: float = -57.0
## How long after a shot the recording keeps sounding (real seconds): a little more than the 2 s
## between a squad's shots, so a continuing fight never stutters.
const HOLD_S: float = 3.0
const SILENT_DB: float = AmbientMixer.SILENT_DB

var _mixer: AmbientMixer
var _since_friendly_shot: float = INF
var _since_enemy_shot: float = INF


## The gain (dB) for the recording given how long ago each side last fired (real seconds).
static func plan(since_friendly_s: float, since_enemy_s: float) -> float:
	if since_friendly_s <= HOLD_S:
		return FRIENDLY_LUFS - FILE_LUFS
	if since_enemy_s <= HOLD_S:
		return ENEMY_LUFS - FILE_LUFS
	return SILENT_DB


func _ready() -> void:
	_mixer = AmbientMixer.new()
	add_child(_mixer)
	_mixer.add_layer("gunfire", STREAM)


## A squad of `team` (Unit.Team) has just fired.
func report_shot(team: int) -> void:
	if team == Unit.Team.PLAYER:
		_since_friendly_shot = 0.0
	else:
		_since_enemy_shot = 0.0


func is_playing() -> bool:
	return _mixer != null and _mixer.is_playing("gunfire")


func _process(delta: float) -> void:
	_since_friendly_shot += delta
	_since_enemy_shot += delta
	if _mixer != null:
		_mixer.set_targets({"gunfire": plan(_since_friendly_shot, _since_enemy_shot)})
