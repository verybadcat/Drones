extends RefCounted
## A deterministic, fixed-position forecast. Never draws random numbers.
## Eliminated means all remaining strength lost, not necessarily all killed.
const HORIZON_SECONDS := 180.0

static func shot_count(unit: Unit, horizon: float, time_scale: float, own_unit: bool) -> int:
	if unit.kind not in [Unit.Kind.SQUAD, Unit.Kind.MORTAR]: return 0
	var interval: float = unit.reload_time if unit.kind == Unit.Kind.MORTAR else unit.fire_interval * time_scale
	var delay: float = unit.fire_timer * (1.0 if unit.kind == Unit.Kind.MORTAR else time_scale) if own_unit else 0.0
	if unit.kind == Unit.Kind.MORTAR: delay += GameConfig.MORTAR_FLIGHT_TIME
	if delay > horizon: return 0
	var count := clampi(1 + floori((horizon - maxf(delay, 0.0)) / maxf(interval, 1.0)), 0, 12)
	return mini(count, unit.mortar_rounds_remaining) if own_unit and unit.kind == Unit.Kind.MORTAR else count

static func damage_distribution(victim: Unit, threats: Array[Dictionary]) -> Dictionary:
	var states: Array[float] = []
	states.resize(maxi(victim.pips, 0) + 1)
	states.fill(0.0)
	states[maxi(victim.pips, 0)] = 1.0
	var no_hit := 1.0
	for threat in threats:
		var chance := clampf(float(threat.chance), 0.0, 1.0)
		for _shot in int(threat.shots):
			no_hit *= 1.0 - chance
			var next: Array[float] = []
			next.resize(states.size())
			next.fill(0.0)
			next[0] = states[0]
			for health in range(1, states.size()):
				next[health] += states[health] * (1.0 - chance)
				if victim.kind in [Unit.Kind.MORTAR, Unit.Kind.DRONE_TEAM]:
					for damage in range(1, health + 1):
						next[health - damage] += states[health] * chance / health
				else:
					var damage: int = GameConfig.mortar_casualty_count(health) if threat.mortar else 1
					next[maxi(health - damage, 0)] += states[health] * chance
			states = next
	return {"hit_probability": 1.0 - no_hit, "loss_probability": states[0]}
