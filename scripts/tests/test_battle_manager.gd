extends BattleManager
class_name TestBattleManager
## Instrumented BattleManager used only by the doctrine-characterization
## test suite (scripts/tests/characterize_doctrine.gd) — never used by the
## actual game. Same principle as TestUnit: every override exists purely
## to COUNT what a decision point actually did, delegating to super() for
## the real behavior, so the game logic under test is exactly what ships.
##
## Counters are plain Dictionaries/ints, reset per trial by the harness
## constructing a fresh TestBattleManager for every battle (no manual
## reset method needed — nothing here is meant to accumulate across
## trials; the harness reads these fields once per battle and folds them
## into its own running totals).

const TestUnitScript := preload("res://scripts/tests/test_unit.gd")

# _pick_target: (attacker_kind_name, attacker_team_name, target_kind_name) -> count.
# Answers "do squads actually fire on enemy mortars" directly, plus gives
# a full targeting distribution for free.
var target_picks: Dictionary = {}

# Resupply lifecycle, per side ("player"/"enemy").
var resupply_spawned: Dictionary = {}
var resupply_destroyed_in_transit: Dictionary = {}

# Enemy flanking maneuver. flanking_units_seen is a working Set (Unit ->
# true) used only to detect the true->false transition on
# flanking_route_active and avoid double-counting a single unit's
# arrival — units are erased from it the moment arrival is counted, so
# its live .size() is NOT "how many were ever assigned" (a unit that
# arrives early in a long battle won't be in it any more when the battle
# ends). flanking_units_assigned_total is the real, monotonic count of
# distinct squads ever seen flanking at all, incremented exactly once
# per unit regardless of how many times _enemy_advance_objective is
# called for it while still flanking.
var flanking_units_seen: Dictionary = {} # Unit -> true (working set, see above)
var flanking_units_assigned_total: int = 0
var flanking_arrivals: int = 0

# Retreat threat-avoidance steering (_retreat_avoidance_offset): how often
# it's actually asked for a correction vs. how often it returns a real
# (nonzero) steering value.
var retreat_avoidance_checks: int = 0
var retreat_avoidance_active: int = 0

# Mortar crew hold-vs-flee and ammo cook-off (set from TestUnit, which
# reaches back into whichever TestBattleManager is its own get_parent()).
var mortar_hold_decisions: Dictionary = {} # side -> total times the decision was actually made
var mortar_hold_outcomes: Dictionary = {} # side -> how many of those came back "hold"
var cookoff_rolls: int = 0
var cookoff_occurred: int = 0

# Wounded evacuation (enemy alone can choose to abandon).
var wounded_evac_decisions: Dictionary = {}
var wounded_abandoned: Dictionary = {}
var wounded_carried: Dictionary = {}

# Drone sorties/losses (DRONE_TEAM recon mode only). Two distinct loss
# causes: _crash_drone fires when a battery simply runs dry (a
# self-inflicted, non-combat loss — see BattleManager's own doc comment
# on it), while a genuine enemy shoot-down goes through the generic
# take_hit -> state=DESTROYED -> state_changed path instead, handled by
# _on_drone_state_changed.
var drone_sorties_launched: int = 0
var drone_lost_to_battery: int = 0
var drone_shot_down_by_enemy: int = 0


func _make_unit(team: Unit.Team, kind: Unit.Kind, pos: Vector2) -> Unit:
	var unit: Unit = TestUnitScript.new()
	add_child(unit)
	unit.setup(team, kind, pos)
	unit.fire_timer = randf_range(0.0, unit.fire_interval)
	return unit


func _pick_target(unit: Unit, enemies: Array[Unit]) -> Unit:
	var target := super._pick_target(unit, enemies)
	if target != null:
		var attacker_team: String = "player" if unit.team == Unit.Team.PLAYER else "enemy"
		var key: String = "%s:%s->%s" % [attacker_team, Unit.Kind.keys()[unit.kind], Unit.Kind.keys()[target.kind]]
		target_picks[key] = target_picks.get(key, 0) + 1
	return target


func _spawn_resupply_run(mortar: Unit) -> void:
	var side: String = "player" if mortar.team == Unit.Team.PLAYER else "enemy"
	resupply_spawned[side] = resupply_spawned.get(side, 0) + 1
	super._spawn_resupply_run(mortar)


func _on_resupply_run_state_changed(unit: Unit) -> void:
	if unit.kind == Unit.Kind.RESUPPLY_RUN and unit.state == Unit.State.DESTROYED:
		var side: String = "player" if unit.team == Unit.Team.PLAYER else "enemy"
		resupply_destroyed_in_transit[side] = resupply_destroyed_in_transit.get(side, 0) + 1
	super._on_resupply_run_state_changed(unit)


func _enemy_advance_objective(u: Unit = null) -> Vector2:
	if u != null and u.flanking_route_active and not flanking_units_seen.has(u):
		flanking_units_seen[u] = true
		flanking_units_assigned_total += 1
	var result := super._enemy_advance_objective(u)
	if u != null and flanking_units_seen.has(u) and not u.flanking_route_active:
		# It was flanking a moment ago (checked above, before super() ran
		# its own arrival check) and isn't any more -> this call is the
		# actual arrival/pivot.
		flanking_arrivals += 1
		flanking_units_seen.erase(u) # counted once; no need to track further
	return result


func _retreat_avoidance_offset(unit: Unit) -> float:
	retreat_avoidance_checks += 1
	var offset := super._retreat_avoidance_offset(unit)
	if offset != 0.0:
		retreat_avoidance_active += 1
	return offset


func _launch_drone() -> void:
	drone_sorties_launched += 1
	super._launch_drone()


func _launch_backup_drone(watched: Unit) -> void:
	drone_sorties_launched += 1
	super._launch_backup_drone(watched)


func _crash_drone(d: Unit, watched: Unit = null) -> void:
	drone_lost_to_battery += 1
	super._crash_drone(d, watched)


func _on_drone_state_changed(unit: Unit) -> void:
	if unit.state == Unit.State.DESTROYED:
		drone_shot_down_by_enemy += 1
	super._on_drone_state_changed(unit)
