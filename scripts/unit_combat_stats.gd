extends RefCounted
## Separate lifetime totals; bounded decision history must not erase damage.
##
## Rows hold a live Unit reference, not a frozen name string — an enemy
## squad/mortar's own display name can change mid-battle (see BattleManager.
## _assign_discovery_number: enemy units are only numbered once the player
## actually spots them, in the order that happens), and a row created
## before that — e.g. the very shot that gets a unit noticed in the first
## place — must still resolve to the right name once report_lines() is
## actually called, not whatever the unit was called at registration time.
##
## The reference isn't always still alive by then, though — a DRONE is a
## fresh Unit per sortie and does get freed once shot down/returned home
## (see BattleManager._next_drone_number's own doc comment), unlike a
## SQUAD/MORTAR, which stays in the roster even DESTROYED specifically so
## the AAR can still reference it. `_label_fallback`, captured once at
## registration, is what report_lines() falls back to for a reference
## that's since gone invalid — a resolvable name always beats a crash.
var rows: Dictionary = {}

func register(unit: Unit) -> void:
	if rows.has(unit.get_instance_id()): return
	rows[unit.get_instance_id()] = {"unit_ref": unit, "label_fallback": unit.display_name(),
		"team": int(unit.team), "kind": int(unit.kind),
		"shots": 0, "counter_battery": 0, "hits": 0, "casualties": 0, "killed": 0,
		"wounded": 0, "heavily_wounded": 0, "walking_wounded": 0, "airframes": 0,
		"friendly_fire_casualties": 0, "targets": {}}

func shot(unit: Unit, counter_battery: bool = false) -> void:
	rows[unit.get_instance_id()]["counter_battery" if counter_battery else "shots"] += 1

static func before_hit(target: Unit) -> Dictionary:
	return {"pips": target.pips, "killed": target.killed_count,
		"heavily_wounded": target.heavily_wounded_count, "walking_wounded": target.walking_wounded_count}

func damage(attacker: Unit, target: Unit, before: Dictionary) -> void:
	var amount := maxi(int(before.pips) - target.pips, 0)
	if amount == 0: return
	register(target) # a target's own row may not exist yet if this is its first appearance
	var row: Dictionary = rows[attacker.get_instance_id()]
	row.hits += 1
	if target.kind == Unit.Kind.DRONE:
		row.airframes += 1
	else:
		# Same delta-since-`before` approach as `deaths` for each of the
		# three buckets Unit._categorize_casualties actually sorts newly-
		# lost people into — `wounded` (heavily + walking combined) stays
		# alongside them, unchanged, so the existing killed+wounded==
		# casualties reconciliation (see test_unit_doctrine.gd) still holds
		# without having to touch that test.
		var deaths := clampi(target.killed_count - int(before.killed), 0, amount)
		var heavily := clampi(target.heavily_wounded_count - int(before.heavily_wounded), 0, amount)
		var walking := clampi(target.walking_wounded_count - int(before.walking_wounded), 0, amount)
		row.casualties += amount
		row.killed += deaths
		row.heavily_wounded += heavily
		row.walking_wounded += walking
		row.wounded += amount - deaths
		# Collateral damage is side-agnostic (see BattleManager.
		# _collateral_victim's own doc comment) — a unit's "casualties
		# inflicted" can include people it hurt on its OWN side, not just
		# the enemy. Tracked separately so the report can call this out
		# explicitly instead of silently folding friendly fire into a
		# number that reads as "damage dealt to the enemy."
		if attacker.team == target.team:
			row.friendly_fire_casualties += amount
	var target_id := target.get_instance_id()
	row.targets[target_id] = int(row.targets.get(target_id, 0)) + amount

## The live name if the unit is still around to ask (picking up any
## discovery-order renumbering that happened after registration), else
## whatever it was last known as.
static func _resolve_name(row: Dictionary) -> String:
	if is_instance_valid(row.unit_ref):
		return row.unit_ref.display_name()
	return row.label_fallback

## Mortars before squads, each in their own numerical order (matching
## _assign_discovery_number's own "Mortar 1"/"Squad 3"-style labels) —
## a stable, look-up-able roster order rather than one that reshuffles
## with the battle's own damage totals, so a unit named elsewhere (the
## combat log, the map) is easy to find here too. Kind and side are both
## already fixed at registration; only the trailing number is parsed out
## of the resolved display name here, defaulting to 0 for anything
## unnumbered (shouldn't happen for a SQUAD/MORTAR row by report time —
## see BattleManager._number_remaining_undiscovered_enemies — but a
## missing number should still sort first within its kind, not crash).
static func _roster_sort_key(row: Dictionary) -> Array:
	var kind_rank: int = 0 if row.kind == Unit.Kind.MORTAR else (1 if row.kind == Unit.Kind.SQUAD else 2)
	var name: String = _resolve_name(row)
	var parts: PackedStringArray = name.split(" ")
	var number: int = int(parts[parts.size() - 1]) if parts.size() > 0 else 0
	return [row.team, kind_rank, number]

## Team, then kind (mortar/squad/other), then number, in that priority
## order — used for both the per-side lists above (team is already fixed
## per call there, so this only ever breaks ties on kind/number) and the
## combined DETAILS roster below (where team is the first, outermost
## grouping too, same YOUR-UNITS-then-ENEMY-UNITS order as the rest of
## this report).
static func _by_roster_order(a: Dictionary, b: Dictionary) -> bool:
	var ka: Array = _roster_sort_key(a)
	var kb: Array = _roster_sort_key(b)
	for i in ka.size():
		if ka[i] != kb[i]:
			return ka[i] < kb[i]
	return false

func report_lines() -> PackedStringArray:
	var lines := PackedStringArray(["DAMAGE BY UNIT — EXACT SIMULATION RESULTS",
		"Casualties = people this unit killed or wounded (what it dealt out, not what it took) — usually on the enemy, but collateral damage is side-agnostic, so a rare friendly-fire casualty is included too and called out separately when it happens. These totals are separate from battlefield estimates.", ""])
	for side in [Unit.Team.PLAYER, Unit.Team.ENEMY]:
		lines.append("YOUR UNITS" if side == Unit.Team.PLAYER else "ENEMY UNITS")
		var team_rows: Array = rows.values().filter(func(row): return row.team == side)
		team_rows.sort_custom(_by_roster_order)
		var total_killed := 0
		var total_heavily_wounded := 0
		var total_walking_wounded := 0
		var total_airframes := 0
		var total_friendly_fire := 0
		for row in team_rows:
			if row.kind not in [Unit.Kind.SQUAD, Unit.Kind.MORTAR]: continue
			# Only called out when it actually happened — most units never
			# commit friendly fire, and a "(0 friendly fire)" on every
			# line would just be noise.
			var friendly_fire_note: String = " (%d friendly fire)" % row.friendly_fire_casualties if row.friendly_fire_casualties > 0 else ""
			lines.append("%s: %d casualties inflicted%s / %d shots / %d CB strikes" % [_resolve_name(row), row.casualties, friendly_fire_note, row.shots, row.counter_battery])
			total_killed += row.killed
			total_heavily_wounded += row.heavily_wounded
			total_walking_wounded += row.walking_wounded
			total_airframes += row.airframes
			total_friendly_fire += row.friendly_fire_casualties
		# Same "inflicted, not suffered" framing as every other number in
		# this report — this side's total casualties inflicted equal the
		# OTHER side's total casualties suffered PLUS any friendly fire
		# this side inflicted on itself (broken out via total_friendly_
		# fire below, not folded in silently), so both sides' totals
		# together still give the full, exact picture without a separate,
		# fog-of-war-limited figure: this whole report is the exact,
		# omniscient one, unlike _end_battle's own "Player/Enemy casualties"
		# lines elsewhere in the AAR. Heavily wounded vs. walking wounded
		# split out here the same way _end_battle's own casualty lines
		# already do — "wounded" alone hid the difference between a
		# casualty who's out of the fight and one who kept going.
		var total_suffix: String = ""
		if total_airframes > 0:
			total_suffix += ", %d drone(s) destroyed" % total_airframes
		if total_friendly_fire > 0:
			total_suffix += ", %d friendly fire" % total_friendly_fire
		lines.append("TOTAL INFLICTED: %d killed, %d heavily wounded, %d walking wounded (%d total)%s" % [total_killed, total_heavily_wounded, total_walking_wounded, total_killed + total_heavily_wounded + total_walking_wounded, total_suffix])
		lines.append("")
	lines.append("DETAILS (CB = counter-battery; impacts include splash) — each row is what THAT unit dealt out; to see what a unit received, look for it under \"Against ...\" in another unit's own row below")
	var detail_rows: Array = rows.values()
	detail_rows.sort_custom(_by_roster_order)
	for row in detail_rows:
		if row.kind not in [Unit.Kind.SQUAD, Unit.Kind.MORTAR]:
			lines.append("%s: unarmed support; no weapon damage." % _resolve_name(row))
			continue
		lines.append("%s inflicted: %d killed, %d heavily wounded, %d walking wounded, %d drone(s) destroyed; %d damaging impacts." % [_resolve_name(row), row.killed, row.heavily_wounded, row.walking_wounded, row.airframes, row.hits])
		for target_id in row.targets:
			var target_name: String = _resolve_name(rows[target_id]) if rows.has(target_id) else "a unit no longer on record"
			lines.append("  Against %s: %d strength lost." % [target_name, row.targets[target_id]])
	return lines
