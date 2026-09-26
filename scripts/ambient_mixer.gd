class_name AmbientMixer
extends Node

## A small bed of looping ambience layers (wind, rain ...) sharing one mechanism:
## each layer is a looping recording on its own player; the caller says what level
## (dB) each layer should have, and the mixer moves there smoothly, stops a layer
## entirely while it is silent, and starts it at a random point in the recording
## when it becomes audible (a different stretch each time). WindAmbience and
## RainAmbience decide WHAT the levels should be; this is the one place that plays
## them.
##
## Two kinds of movement, kept apart:
##  * A change of level within the audible range (the wind picking up a little) ramps
##    at MAX_DB_PER_SECOND.
##  * A layer coming in or going out fades over FADE_S along an equal-POWER curve:
##    the one leaving follows cos(x), the one entering sin(x), so while one recording
##    hands over to another their powers add to a constant and the bed does not dip in
##    the middle. (Both used to ramp in dB at the same rate, from and to silence,
##    which sank the sum by about 13 dB halfway through every hand-over: a break in the
##    sound each time the wind crossed from the soft to the blowing recording.)

const SILENT_DB: float = -60.0
## How fast a level may move within the audible range (dB per real second): follows
## the weather as it drifts, without ever jumping.
const MAX_DB_PER_SECOND: float = 15.0
## How long a layer takes to fade fully in or out (real seconds).
const FADE_S: float = 2.5

# id -> {"player": AudioStreamPlayer, "db": float (the level at full fade), "fade": float
# (0 silent .. 1 full), "target": float}
var _layers: Dictionary = {}


## Adds a layer named `id`, looping `stream` (on a copy: the preloaded resource is
## shared), silent until told otherwise. Any looping recording will do (MP3 or Ogg Vorbis).
func add_layer(id: String, stream: AudioStream) -> void:
	var looping: AudioStream = stream.duplicate()
	looping.set("loop", true)
	var player := AudioStreamPlayer.new()
	player.stream = looping
	player.volume_db = SILENT_DB
	add_child(player)
	_layers[id] = {"player": player, "db": SILENT_DB, "fade": 0.0, "target": SILENT_DB}


## Sets the level every layer should reach (dB): a layer not named is silent.
func set_targets(targets: Dictionary) -> void:
	for id in _layers:
		_layers[id].target = targets.get(id, SILENT_DB)


## The level a layer is at right now, fade included (SILENT_DB when it is not heard).
func level_db(id: String) -> float:
	return _effective_db(_layers[id])


func is_playing(id: String) -> bool:
	return _layers[id].player.playing


func loops(id: String) -> bool:
	return bool(_layers[id].player.stream.get("loop"))


func _process(delta: float) -> void:
	for id in _layers:
		var layer: Dictionary = _layers[id]
		var wanted: bool = layer.target > SILENT_DB + 0.5
		if wanted:
			if layer.db <= SILENT_DB + 0.5:
				layer.db = layer.target # coming in: at its level, under the fade
			else:
				layer.db = move_toward(layer.db, layer.target, MAX_DB_PER_SECOND * delta)
		layer.fade = move_toward(layer.fade, 1.0 if wanted else 0.0, delta / FADE_S)
		if not wanted and layer.fade <= 0.0:
			layer.db = SILENT_DB
		_apply(layer.player, _effective_db(layer), wanted or layer.fade > 0.0)


## The audible level: the layer's own level plus the equal-power fade curve (sin, so a
## layer at half fade is 3 dB down, as its partner in a hand-over is).
func _effective_db(layer: Dictionary) -> float:
	if layer.fade <= 0.0 or layer.db <= SILENT_DB + 0.5:
		return SILENT_DB
	return maxf(layer.db + 20.0 * log(maxf(sin(layer.fade * PI / 2.0), 1e-4)) / log(10.0), SILENT_DB)


## Stopped entirely while silent; started at a random point when it becomes audible.
func _apply(player: AudioStreamPlayer, level_db: float, audible: bool) -> void:
	if not audible:
		if player.playing:
			player.stop()
		return
	if not player.playing:
		player.play(randf() * player.stream.get_length())
	player.volume_db = level_db
