extends "res://scripts/battle_manager.gd"
## Test helper (not a test): a BattleManager whose fall-back scoring is set by hand —
## the current position scores `here_score`, every other point `candidate_score` — so
## the "worth moving for" threshold can be tested on its own, independent of the map.
var here_score: float = 1.0
var candidate_score: float = 0.9

func _fall_back_score(unit: Unit, point: Vector2, _known: Array[Vector2], _advancing: Array[Vector2] = [], _assume_compromised: bool = false) -> float:
	return here_score if point.distance_to(unit.global_position) < 1.0 else candidate_score
