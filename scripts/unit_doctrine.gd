extends RefCounted
## Per-type orders are independent of the commander preset.
const TYPES := ["squad", "mortar", "spotter", "drone_team", "drone", "resupply_run"]
const TYPE_LABELS := ["Infantry squads", "Mortar crews", "Ground spotters", "Drone ground teams", "Airborne drones", "Resupply teams"]
const TARGET_IDS := ["inherit", "nearest", "weakest", "threat", "mortars", "best_chance"]
const TARGET_LABELS := ["Commander priorities", "Nearest target", "Lowest remaining strength", "Threat to allies", "Enemy mortars first", "Best hit chance"]
const RISK_IDS := ["inherit", "preserve", "balanced", "mission_first"]
const RISK_LABELS := ["Existing behavior", "Preserve the unit", "Calculated risk", "Mission first / expendable"]

static func type_key(kind: int) -> String:
	return Unit.Kind.keys()[kind].to_lower()

static func sanitize(input: Dictionary) -> Dictionary:
	var result := {}
	for key in TYPES:
		var raw: Dictionary = input.get(key, {}) if input.get(key, {}) is Dictionary else {}
		var target := str(raw.get("targeting", "inherit"))
		var risk := str(raw.get("risk", "inherit"))
		if not TARGET_IDS.has(target): target = "inherit"
		if not RISK_IDS.has(risk): risk = "inherit"
		# Passive ground sensors and logistics have assigned tasks, not weapons.
		if key in ["spotter", "drone_team", "resupply_run"]: target = "inherit"
		result[key] = {"targeting": target, "risk": risk}
	return result

static func risk_limits(id: String) -> Dictionary:
	match id:
		"preserve": return {"max_loss": 0.10, "max_hit": 0.35, "loss_cost": 2.0}
		"balanced": return {"max_loss": 0.40, "max_hit": 0.80, "loss_cost": 1.0}
		"mission_first": return {"max_loss": 1.0, "max_hit": 1.0, "loss_cost": 0.15}
	return {"max_loss": 1.0, "max_hit": 1.0, "loss_cost": 0.0}

static func accepts(risk: String, forecast: Dictionary) -> bool:
	var limits := risk_limits(risk)
	var success: float = forecast.get("goal_probability", -1.0)
	return forecast.loss_probability <= limits.max_loss and forecast.hit_probability <= limits.max_hit \
		and (success < 0.0 or success >= forecast.loss_probability * limits.loss_cost)
