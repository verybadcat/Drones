extends SceneTree
## Direct user report: "Drones got themselves into a situation where they are repeatedly launching with
## very little charge." Root cause: a battery was pulled out of the charging pool and staged the instant a
## drone LANDED (BattleManager._update_returning_drones), whatever charge happened to be best in the pool
## at that moment — during a quiet stretch with nothing to launch for, that partly-charged battery just
## sat staged, frozen, instead of continuing to recharge in the pool, and the very next launch trigger
## (still gated on nothing but "is anything staged at all") grabbed it and flew with almost nothing.
##
## Fix, worked out directly with the user over several corrections:
## - A landing no longer auto-stages anything — a spent battery just goes back into the pool.
## - Any pool battery that reaches full charge gets staged anyway, unconditionally, every tick
##   (_stage_best_battery_if_at_least(1.0)) — "if a battery is charged, you can swap it onto a drone even
##   if we don't need to launch yet."
## - A still-charging battery is only ever pulled out of the pool EARLY when a launch is actually wanted:
##   quiet (no known enemy mortar fire) holds out for a full battery; a known mortar needing a look launches
##   on the real round-trip cost to reach it (_drone_required_launch_charge), scaled down for a closer
##   target, but never below GameConfig.DRONE_MIN_LAUNCH_CHARGE_FLOOR ("never launch below 20%").
## - The backup-drone launch (second sortie for double coverage) deliberately keeps its OLD requirement — a
##   battery already sitting pre-staged in _drones_ready — rather than reactively staging from the pool like
##   the primary launch: its own dispatch timing assumes a near-instant launch, and a fresh swap takes
##   longer than the RTB window it's racing against.
##
## Run: godot --headless --path . --script scripts/tests/test_drone_launch_charge_discipline.gd
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func m(v: float) -> float:
	return v * GameConfig.PIXELS_PER_METER

func calm_weather() -> Weather:
	var w := Weather.new()
	w.wind_speed_10m = 0.0
	w.temperature_c = 10.0
	w._gust_z = 0.0
	w.rng.seed = 5
	return w

## A grounded drone-team battle: nothing airborne yet, ready to test the launch decision itself.
func make_battle() -> BattleManager:
	Weather.current = calm_weather()
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	bm.combat_log = Log.new()
	bm.recon_mode = GameConfig.ReconMode.DRONE_TEAM
	var team: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE_TEAM, Vector2(m(-800.0), m(1500.0)))
	bm.player_units.append(team)
	bm.drone_team = team
	bm._drones_ready.clear()
	bm._drones_swapping.clear()
	bm._battery_pool.clear()
	bm._airframes_awaiting_battery = 1 # one airframe on the ground with no battery in it, for a staged battery to go into
	return bm

func enemy_mortar(bm: BattleManager, pos: Vector2) -> Unit:
	var e: Unit = bm._make_unit(Unit.Team.ENEMY, Unit.Kind.MORTAR, pos)
	bm.enemy_units.append(e)
	e.is_visible = true
	return e

func run() -> void:
	test_landing_does_not_auto_stage_a_partial_battery()
	test_a_full_pool_battery_gets_staged_passively_with_nothing_to_launch_for()
	test_quiet_does_not_launch_on_a_partial_battery()
	test_urgent_close_target_launches_on_a_partial_battery()
	test_never_launches_below_the_absolute_floor()
	test_backup_drone_does_not_reactively_stage_from_a_cold_pool()
	test_ready_never_exceeds_the_fleet_however_many_batteries_there_are()
	test_the_dashboard_reports_the_bare_airframes()
	print("Drone launch-charge-discipline tests: %d failures" % failures)
	quit(1 if failures else 0)


## _update_returning_drones' own redesign: a landed drone's spent charge goes back into the pool and
## NOTHING gets automatically staged from it — the old behavior popped the pool's own best battery into
## _drones_swapping right here, which is exactly the mechanism the user's report traced this bug to.
func test_landing_does_not_auto_stage_a_partial_battery() -> void:
	var bm := make_battle()
	var d: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, bm.drone_team.global_position)
	bm.player_units.append(d)
	d.drone_battery_charge = 0.35
	d.has_move_target = false # already arrived — the "land it for real" branch
	bm.returning_drones.append(d)
	bm._battery_pool.append(1.0) # a fully-charged spare already sitting in the pool
	bm._update_returning_drones(0.1)
	check(bm._drones_swapping.is_empty(), "Landing itself starts no swap")
	check(bm._drones_ready.is_empty(), "Landing itself stages nothing")
	check(bm._battery_pool.size() == 2, "The landed battery (minus landing cost) just joins the pool")
	check(bm._airframes_awaiting_battery == 2, "The landed airframe itself is still counted, bare, on the ground")
	bm.combat_log.free()
	bm.free()


## The passive per-tick pass: a battery that reaches 1.0 in the pool gets staged regardless of whether
## anything actually needs to launch — no quiet/urgent gating applies to an ALREADY-full battery. And once
## it finishes staging, with active_drone still null, it launches right away: "quiet" only ever holds back
## pulling a PARTIAL battery out early, never a already-full one that's sitting ready with nothing to wait
## for — a routine recon sortie during a quiet stretch is completely normal.
func test_a_full_pool_battery_gets_staged_passively_with_nothing_to_launch_for() -> void:
	var bm := make_battle()
	bm._battery_pool.append(1.0)
	bm._battery_pool.append(0.4) # not full — must NOT also get swept up
	for i in 30:
		bm._update_drone_operations(10.0)
	check(bm.active_drone != null, "The full battery ends up launched, not just sitting ready forever")
	# Still recharging normally the whole time (300 tactical seconds here, against a 6000s full recharge)
	# — not equal to its starting 0.4 any more, but nowhere near pulled/staged either.
	check(bm._battery_pool.size() == 1 and bm._battery_pool[0] > 0.4 and bm._battery_pool[0] < 0.5, "The partial battery was left alone in the pool, only ever recharging normally")
	bm.combat_log.free()
	bm.free()


## The core reported bug: quiet (no known enemy mortar at all), a partially-charged pool battery must NOT
## get launched on — it should hold out for a full charge instead.
func test_quiet_does_not_launch_on_a_partial_battery() -> void:
	var bm := make_battle()
	bm._battery_pool.append(0.6)
	for i in 50:
		bm._update_drone_operations(10.0)
	check(bm.active_drone == null, "No launch while quiet with nothing but a partial battery on hand")
	check(bm._drones_ready.is_empty() and bm._drones_swapping.is_empty(), "The partial battery was never pulled out of the pool at all")
	bm.combat_log.free()
	bm.free()


## A known enemy mortar close enough that the real round-trip cost is comfortably under what's on hand —
## the drone team launches on it well short of a full charge.
func test_urgent_close_target_launches_on_a_partial_battery() -> void:
	var bm := make_battle()
	enemy_mortar(bm, bm.drone_team.global_position + Vector2(m(200.0), 0.0)) # close
	bm._battery_pool.append(0.5)
	var launched := false
	for i in 50:
		bm._update_drone_operations(10.0)
		if bm.active_drone != null:
			launched = true
			break
	check(launched, "Launches on the partial battery once a close, known mortar needs spotting")
	if launched:
		check(bm.active_drone.drone_battery_charge < 0.5, "Actually flew on less than a full charge (climb cost already spent)")
	bm.combat_log.free()
	bm.free()


## Direct user ruling: "Never launch below 20%" — even a genuinely urgent, very close target must not
## launch on a battery below GameConfig.DRONE_MIN_LAUNCH_CHARGE_FLOOR. Short loop, deliberately: the pool's
## own passive recharge (GameConfig.DRONE_RECHARGE_DURATION) would eventually carry this battery PAST the
## floor on its own given enough tactical time, which would just be the ordinary "wait for it to charge
## up" case working as intended, not a test of the floor itself — this only checks that it does NOT launch
## on it immediately, well before that recharge could plausibly close a 0.05 gap against a 6000s duration.
func test_never_launches_below_the_absolute_floor() -> void:
	var bm := make_battle()
	enemy_mortar(bm, bm.drone_team.global_position + Vector2(m(5.0), 0.0)) # about as close as it gets
	bm._battery_pool.append(GameConfig.DRONE_MIN_LAUNCH_CHARGE_FLOOR - 0.05)
	for i in 5:
		bm._update_drone_operations(10.0)
	check(bm.active_drone == null, "Never launches below the absolute floor, no matter how close the target")
	check(bm._drones_ready.is_empty() and bm._drones_swapping.is_empty(), "The under-floor battery was never pulled out of the pool")
	bm.combat_log.free()
	bm.free()


## Regression guard: backup-drone dispatch is deliberately NOT given the same reactive pool-staging the
## primary launch gets (see _update_drone_operations' own comment on the backup path — the dispatch timing
## assumes a near-instant launch, and a fresh swap-from-pool takes longer than the RTB window it's racing
## against). With nothing already staged in _drones_ready, a backup must NOT launch at all, no matter how
## urgent or how charged the pool is — confirms this session's charge-discipline changes didn't
## accidentally start reactively staging for it too.
func test_backup_drone_does_not_reactively_stage_from_a_cold_pool() -> void:
	var bm := make_battle()
	var watched: Unit = enemy_mortar(bm, bm.drone_team.global_position + Vector2(m(300.0), 0.0))
	var active: Unit = bm._make_unit(Unit.Team.PLAYER, Unit.Kind.DRONE, watched.global_position)
	bm.player_units.append(active)
	active.state_changed.connect(bm._on_drone_state_changed)
	# Enough charge that it won't crash or self-RTB away mid-test, but still inside the backup-dispatch
	# window (time_until_rtb <= backup_travel_time) from the very first tick.
	var needed_home: float = bm._drone_leg_charge(watched.global_position, bm.drone_team.global_position) + bm._drone_arrival_reserve_charge()
	active.drone_battery_charge = needed_home + 1.0 / bm._drone_full_charge_flight_time()
	active.move_speed = GameConfig.DRONE_CRUISE_SPEED
	active.move_target = watched.global_position
	active.has_move_target = true
	bm.active_drone = active
	bm._battery_pool.append(1.0) # plenty charged, but nothing pre-staged in _drones_ready
	for i in 5:
		bm._update_drone_operations(10.0)
	check(bm.backup_drone == null, "No backup launches from a cold pool, however charged, without something already pre-staged")
	bm.combat_log.free()
	bm.free()


## Direct user report: "The sidebar says there are 7 drones ready. That's impossible as the team only has 4
## drones" — "It may be inappropriately lumping drones and batteries." The fleet is 4 AIRFRAMES but 8
## BATTERIES. Every airframe is exactly one of: airborne, backup, inbound, ready (battery in), swapping
## (battery going in), awaiting a battery (landed, bare), or destroyed — so those seven must always add up to
## GameConfig.DRONE_FLEET_SIZE no matter how the batteries pile up. The real bug: landing sent the battery to
## the pool and forgot the airframe, so staging a battery conjured a "ready" drone out of nothing.
func fleet_total(status: Dictionary) -> int:
	return int(status.airborne) + int(status.backup) + status.inbound + status.ready + status.swapping + status.awaiting_battery + status.destroyed

func test_ready_never_exceeds_the_fleet_however_many_batteries_there_are() -> void:
	var bm := make_battle()
	# The real start-of-battle fleet: 4 ready airframes, 4 spare batteries in the pool (start_battle does this).
	for i in GameConfig.DRONE_FLEET_SIZE:
		bm._drones_ready.append(1.0)
	bm._airframes_awaiting_battery = 0
	for i in GameConfig.DRONE_SPARE_BATTERIES:
		bm._battery_pool.append(1.0)
	bm._launch_drone()
	var worst_ready := 0
	var worst_total_error := 0
	# A long, quiet stretch: the drone flies, comes home, lands, a fresh battery goes on, it flies again —
	# many full cycles, every tick checked.
	for i in 6000:
		bm._update_drone_operations(10.0)
		var status: Dictionary = bm.drone_fleet_status()
		worst_ready = maxi(worst_ready, status.ready)
		worst_total_error = maxi(worst_total_error, absi(fleet_total(status) - GameConfig.DRONE_FLEET_SIZE))
	check(bm._battery_pool.size() + bm._drones_ready.size() + bm._drones_swapping.size() + int(bm.active_drone != null) + int(bm.backup_drone != null) + bm.returning_drones.size() <= GameConfig.DRONE_FLEET_SIZE + GameConfig.DRONE_SPARE_BATTERIES, "Batteries are never conjured either")
	check(worst_ready <= GameConfig.DRONE_FLEET_SIZE, "Never more drones ready than the team owns (worst seen: %d)" % worst_ready)
	check(worst_total_error == 0, "Every airframe is accounted for, every tick (worst miscount: %d)" % worst_total_error)
	bm.combat_log.free()
	bm.free()


func test_the_dashboard_reports_the_bare_airframes() -> void:
	var dash := CasualtyDashboard.new()
	var status := {"team_active": true, "team_state": Unit.State.ACTIVE, "team_crew_casualties": 0, "team_crew_size": 4,
		"airborne": true, "airborne_charge": 0.8, "backup": false, "backup_charge": -1.0, "inbound": 0,
		"ready": 1, "ready_best_charge": 1.0, "swapping": 0, "awaiting_battery": 2,
		"spare_batteries": 3, "spare_best_charge": 0.5, "destroyed": 0}
	var row: Dictionary = dash._drone_row_data(true, status)
	check("2 awaiting battery" in row.text, "The sidebar names airframes waiting on a battery instead of leaving them uncounted: %s" % row.text)
	dash.free()
