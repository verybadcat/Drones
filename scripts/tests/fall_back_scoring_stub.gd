extends "res://scripts/battle_manager.gd"
## Test helper (not a test): a BattleManager whose fall-back safety scoring is set by hand —
## every point scores 0 except `bonus_point`, which scores `bonus` (negative is better) —
## so the choice of distance can be tested on its own, independent of the map.
var bonus_point: Vector2 = Vector2.INF
var bonus: float = 0.0
var last_advancing_count: int = -1

func _fall_back_score(_unit: Unit, point: Vector2, _known: Array[Vector2], advancing: Array[Vector2] = []) -> float:
	last_advancing_count = advancing.size()
	return bonus if point.distance_to(bonus_point) < 1.0 else 0.0
