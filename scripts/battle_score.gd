extends RefCounted
class_name BattleScore
## The battle-outcome score: one number for how well or poorly a battle went.
##
## The rubric is the user's own, fixed on 2026-09-08 (see the design doc's
## "A fixed battle-outcome scoring rubric"), the concrete operationalization
## of "win the battle / keep our people alive / cause enemy casualties".
## It scores FINAL outcomes only: deliberately no "recon asset lost" term —
## a drone-team casualty is already counted as an ordinary friendly death or
## wound, same as any squad's, since losing recon capability mid-battle is an
## intermediate, replaceable effect, not a final result. Deaths are
## asymmetric on purpose (a friendly life costs more than an enemy death is
## worth); captures are symmetric. The two mortar terms price the loss or
## denial of the weapon system itself, ON TOP of whatever its crew already
## cost through the terms above.
##
## ONE score, from the TRUE results (user, 2026-09-24: "The score can go
## based off of the true results" — this replaces the earlier plan for a
## separate best-guess score to display; the after-action report's own enemy
## casualty figures stay fog-of-war-limited, the score deliberately isn't).
## Casualties count by WHOSE SIDE they fall on, never by what caused them:
## every friendly casualty counts against the player and every enemy casualty
## in the player's favor, friendly fire included ("regardless of the
## source"). That is why the inputs are the victims' own per-side casualty
## counts (BattleManager._compute_side_stats), never anything like "kills
## inflicted".
##
## Everything here is a pure function of a plain counts dictionary (see
## `inputs` below), which is exactly what BattleScoreLog stores for every
## battle — so a stored battle can be RE-SCORED if this rubric is ever tuned
## (bump RUBRIC_VERSION when it is, so old records stay identifiable).

## Bump whenever any value below (or the meaning of an input) changes.
const RUBRIC_VERSION: int = 1

const POSITION_HELD := 20.0
const POSITION_LOST := -20.0
## A stalemate (the fight called off after nothing happened for too long) was
## never decided either way — the user's ruling on the verdict wording ("Don't
## say that the position was held, or that it was lost. Neither is true.")
## applies to the score too: neither the +20 nor the -20.
const POSITION_STALEMATE := 0.0
const FRIENDLY_DEATH := -10.0
const ENEMY_DEATH := 5.0
const FRIENDLY_CAPTURED := -8.0
const ENEMY_CAPTURED := 8.0
const FRIENDLY_HEAVILY_WOUNDED := -4.0
const ENEMY_HEAVILY_WOUNDED := 2.0
const FRIENDLY_WALKING_WOUNDED := -1.0
const ENEMY_WALKING_WOUNDED := 0.5
const FRIENDLY_MORTAR_LOST := -5.0 # the gun itself, on top of whatever its crew already cost above
const ENEMY_MORTAR_OUT := 2.5 # destroyed, or abandoned on ground the player ends up holding

const POSITION_HELD_KEY := "held"
const POSITION_LOST_KEY := "lost"
const POSITION_STALEMATE_KEY := "stalemate"


## Every scored term other than the position, in the order they are shown:
## [inputs key, label shown to the player, points per event]. The single table
## score() AND line_items() both read, so the breakdown the player sees can
## never disagree with the number.
const TERMS: Array = [
	["player_killed", "Our personnel killed", FRIENDLY_DEATH],
	["player_captured", "Our personnel captured", FRIENDLY_CAPTURED],
	["player_heavily_wounded", "Our heavily wounded", FRIENDLY_HEAVILY_WOUNDED],
	["player_walking_wounded", "Our walking wounded", FRIENDLY_WALKING_WOUNDED],
	["player_mortar_lost", "Our mortar lost", FRIENDLY_MORTAR_LOST],
	["enemy_killed", "Enemy killed", ENEMY_DEATH],
	["enemy_captured", "Enemy captured", ENEMY_CAPTURED],
	["enemy_heavily_wounded", "Enemy heavily wounded", ENEMY_HEAVILY_WOUNDED],
	["enemy_walking_wounded", "Enemy walking wounded", ENEMY_WALKING_WOUNDED],
	["enemy_mortar_out", "Enemy mortar destroyed or abandoned", ENEMY_MORTAR_OUT],
]


## `inputs`: {"position": "held" | "lost" | "stalemate", and integer counts
## player_killed, player_captured, player_heavily_wounded,
## player_walking_wounded, player_mortar_lost, enemy_killed, enemy_captured,
## enemy_heavily_wounded, enemy_walking_wounded, enemy_mortar_out}. Anything
## missing counts as zero (a stored record from an older build may not have
## every field); an unrecognized position scores like a stalemate.
static func score(inputs: Dictionary) -> float:
	var total := 0.0
	for item in line_items(inputs):
		total += item.points
	return total


## The score broken into its line items, position first, then every term in
## TERMS order (including those with a zero count — callers decide whether to
## show those): {key, label, count, value, points}, where points = count *
## value. The points always sum to score().
static func line_items(inputs: Dictionary) -> Array[Dictionary]:
	var position_points: float = POSITION_STALEMATE
	var position_label := "Stalemate (neither side held or lost the position)"
	match str(inputs.get("position", POSITION_STALEMATE_KEY)):
		POSITION_HELD_KEY:
			position_points = POSITION_HELD
			position_label = "Position held"
		POSITION_LOST_KEY:
			position_points = POSITION_LOST
			position_label = "Position lost"
	var items: Array[Dictionary] = [{"key": "position", "label": position_label, "count": 1, "value": position_points, "points": position_points}]
	for term in TERMS:
		var count: int = int(inputs.get(term[0], 0))
		items.append({"key": term[0], "label": term[1], "count": count, "value": term[2], "points": term[2] * count})
	return items


## The Score tab of the end-of-battle report: the total, then every term that
## actually happened as "label: count x points-each = points" (position always
## shown), then the total again. `scenario_line` (the running scenario
## average) goes under the headline if given.
static func breakdown_text(inputs: Dictionary, scenario_line: String = "") -> String:
	var lines: PackedStringArray = []
	lines.append("Battle score: %s" % format(score(inputs)))
	if not scenario_line.is_empty():
		lines.append(scenario_line)
	lines.append("")
	lines.append("How it was scored:")
	for item in line_items(inputs):
		if item.key == "position":
			lines.append("  %s: %s" % [item.label, format(item.points)])
		elif item.count != 0:
			lines.append("  %s: %d × %s = %s" % [item.label, item.count, _format_value(item.value), format(item.points)])
	lines.append("")
	lines.append("Total: %s" % format(score(inputs)))
	return "
".join(lines)


static func position_key(held: bool, stalemate: bool) -> String:
	if stalemate:
		return POSITION_STALEMATE_KEY
	return POSITION_HELD_KEY if held else POSITION_LOST_KEY


## A per-event value as it appears in a line item: "-10", "+5", "+0.5" —
## whole numbers without a decimal, fractions with one.
static func _format_value(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%+d" % int(value)
	return "%+.1f" % value


## "+42.5" / "-17.0" — always signed, so a score reads as a swing, not a count.
static func format(value: float) -> String:
	return "%+.1f" % value


## Is `mortar` actually out — destroyed, or abandoned on ground the player
## ends up holding? The "abandoned on held ground" half ties to the AAR's own
## "holding lets you confirm what was left behind" mechanic — a withdrawn or
## retreating crew only counts once the position itself is held, not merely
## because it happened to flee. Ground truth, like everything else here.
static func enemy_mortar_out(mortar: Unit, held: bool) -> bool:
	if mortar.state == Unit.State.DESTROYED:
		return true
	return held and (mortar.state == Unit.State.WITHDRAWN or mortar.state == Unit.State.RETREATING)
