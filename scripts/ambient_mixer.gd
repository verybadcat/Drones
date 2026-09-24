class_name AmbientMixer
extends Node

## A small bed of looping ambience layers (wind, rain ...) sharing one mechanism:
## each layer is a looping recording on its own player; the caller says what level
## (dB) each layer should have, and the mixer moves there smoothly, stops a layer
## entirely while it is silent, and starts it at a random point in the recording
## when it becomes audible (a different stretch each time). WindAmbience and
## RainAmbience decide WHAT the levels should be; this is the one place that plays
## them.

const SILENT_DB: float = -60.0
## How fast a level may move (dB per real second): fades in on the way into a
## battle and follows the weather as it drifts, without ever jumping.
const MAX_DB_PER_SECOND: float = 15.0

var _layers: Dictionary = {} # id -> {"player": AudioStreamPlayer, "db": float, "target": float}


## Adds a layer named `id`, looping `stream` (on a copy: the preloaded resource is
## shared), silent until told otherwise.
func add_layer(id: String, stream: AudioStreamMP3) -> void:
	var looping: AudioStreamMP3 = stream.duplicate()
	looping.loop = true
	var player := AudioStreamPlayer.new()
	player.stream = looping
	player.volume_db = SILENT_DB
	add_child(player)
	_layers[id] = {"player": player, "db": SILENT_DB, "target": SILENT_DB}


## Sets the level every layer should reach (dB): a layer not named is silent.
func set_targets(targets: Dictionary) -> void:
	for id in _layers:
		_layers[id].target = targets.get(id, SILENT_DB)


func level_db(id: String) -> float:
	return _layers[id].db


func is_playing(id: String) -> bool:
	return _layers[id].player.playing


func loops(id: String) -> bool:
	return _layers[id].player.stream.loop


func _process(delta: float) -> void:
	var step: float = MAX_DB_PER_SECOND * delta
	for id in _layers:
		var layer: Dictionary = _layers[id]
		layer.db = move_toward(layer.db, layer.target, step)
		_apply(layer.player, layer.db)


## Stopped entirely while silent; started at a random point when it becomes audible.
func _apply(player: AudioStreamPlayer, level_db: float) -> void:
	if level_db <= SILENT_DB + 0.5:
		if player.playing:
			player.stop()
		return
	if not player.playing:
		player.play(randf() * player.stream.get_length())
	player.volume_db = level_db
