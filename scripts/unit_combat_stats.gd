extends RefCounted
## Separate lifetime totals; bounded decision history must not erase damage.
var rows: Dictionary = {}

func register(unit: Unit, label: String) -> void:
	if rows.has(unit.get_instance_id()): return
	rows[unit.get_instance_id()] = {"unit": label, "team": int(unit.team), "kind": int(unit.kind),
		"shots": 0, "counter_battery": 0, "hits": 0, "casualties": 0, "killed": 0,
		"wounded": 0, "airframes": 0, "targets": {}}

func shot(unit: Unit, counter_battery: bool = false) -> void:
	rows[unit.get_instance_id()]["counter_battery" if counter_battery else "shots"] += 1

static func before_hit(target: Unit) -> Dictionary:
	return {"pips": target.pips, "killed": target.killed_count}

func damage(attacker: Unit, target: Unit, before: Dictionary, target_label: String) -> void:
	var amount := maxi(int(before.pips) - target.pips, 0)
	if amount == 0: return
	var row: Dictionary = rows[attacker.get_instance_id()]
	row.hits += 1
	if target.kind == Unit.Kind.DRONE:
		row.airframes += 1
	else:
		var deaths := clampi(target.killed_count - int(before.killed), 0, amount)
		row.casualties += amount
		row.killed += deaths
		row.wounded += amount - deaths
	row.targets[target_label] = int(row.targets.get(target_label, 0)) + amount

func report_lines() -> PackedStringArray:
	var lines := PackedStringArray(["DAMAGE BY UNIT — EXACT SIMULATION RESULTS",
		"Casualties = people killed or wounded. These totals are separate from battlefield estimates.", ""])
	for side in [Unit.Team.PLAYER, Unit.Team.ENEMY]:
		lines.append("YOUR UNITS" if side == Unit.Team.PLAYER else "ENEMY UNITS")
		var team_rows: Array = rows.values().filter(func(row): return row.team == side)
		team_rows.sort_custom(func(a, b): return a.casualties > b.casualties)
		for row in team_rows:
			if row.kind not in [Unit.Kind.SQUAD, Unit.Kind.MORTAR]: continue
			lines.append("%s: %d casualties / %d shots / %d CB strikes" % [row.unit, row.casualties, row.shots, row.counter_battery])
		lines.append("")
	lines.append("DETAILS (CB = counter-battery; impacts include splash)")
	for row in rows.values():
		if row.kind not in [Unit.Kind.SQUAD, Unit.Kind.MORTAR]:
			lines.append("%s: unarmed support; no weapon damage." % row.unit)
			continue
		lines.append("%s: %d killed, %d wounded, %d drone(s) destroyed; %d damaging impacts." % [row.unit, row.killed, row.wounded, row.airframes, row.hits])
		for target in row.targets:
			lines.append("  Against %s: %d strength lost." % [target, row.targets[target]])
	return lines
