extends SceneTree
## Direct user request: "As much as possible, make the code to generate the enemy force independent of
## everything else that is going on. For example, if the same seed is used on a different map or with a
## different recon choice, it still gives the same enemy force. Obviously this will break if we ever set
## things up to have a different range of enemy force compositions for different situations."
##
## Before: the force was drawn from the shared global random stream AFTER every player unit (and, in
## drone-team mode, the first drone) had already consumed draws of their own (`_make_unit` rolls a fire phase
## per unit) — so how many squads a map defaults the player to, and spotter vs. drone team, silently shifted
## every number the enemy force was built from. Now it comes from BattleManager._enemy_rng, seeded from the
## battle seed alone.
##
## What "the same force" means here: the same squad and mortar counts, the same squads designated to flank,
## the same starting fire phases, the same commander breaking point. NOT the same coordinates — positions are
## laid out from each map's own geometry, so the same force stands in different places on different maps (the
## test checks that too, so it cannot pass just because the map never actually changed).
##
## Run: godot --headless --path . --script scripts/tests/test_enemy_force_independent_of_setup.gd
const Profile = preload("res://scripts/commander_profile.gd")
const Log = preload("res://scripts/tests/test_combat_log.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var original_map: String = GameConfig.current_map_id()
	test_the_same_seed_gives_the_same_force_on_every_map_and_recon_choice()
	test_the_players_own_setup_cannot_shift_it()
	test_different_seeds_still_give_different_forces()
	GameConfig.set_active_map(original_map)
	print("Enemy-force-independent-of-setup tests: %d failures" % failures)
	quit(1 if failures else 0)


## Starts a real battle (the real start_battle path, not a re-statement of it) and reads the enemy force off
## the result. `player_squads` < 0 means the map's own default number of player squads.
func start(map_id: String, recon: GameConfig.ReconMode, seed_value: int, player_squads: int = -1) -> Dictionary:
	GameConfig.set_active_map(map_id)
	Weather.current = Weather.roll(seed_value + 7919)
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	var log = Log.new()
	var squads: Array[Dictionary] = []
	var positions: Array = GameConfig.CURRENT_MAP.player.default_squad_positions
	for i in positions.size():
		if player_squads >= 0 and i >= player_squads:
			break
		squads.append({"position": positions[i], "retreat_threshold": 0.5})
	bm.start_battle({"squads": squads,
		"mortar": {"position": GameConfig.CURRENT_MAP.player.mortar_default_position, "shoot_and_scoot": true},
		"spotter": {"position": GameConfig.CURRENT_MAP.player.spotter_default_position}, "recon_mode": recon,
		"player_profile": Profile.preset("baseline"), "enemy_profile": Profile.preset("baseline"), "seed": seed_value}, log)
	var sig := {"squads": 0, "mortars": 0, "flanking": [], "fire_timers": [],
		"threshold": snappedf(bm._enemy_commander_retreat_threshold, 0.000001), "first_position": Vector2.ZERO}
	for u in bm.enemy_units:
		if u.kind == Unit.Kind.SQUAD:
			sig.squads += 1
			sig.flanking.append(u.flanking_route_active)
		elif u.kind == Unit.Kind.MORTAR:
			sig.mortars += 1
		sig.fire_timers.append(snappedf(u.fire_timer, 0.000001))
	sig.first_position = bm.enemy_units[0].position
	bm.free()
	log.free()
	return sig


## The comparison itself: everything but the coordinates.
func same_force(a: Dictionary, b: Dictionary) -> bool:
	return a.squads == b.squads and a.mortars == b.mortars and a.flanking == b.flanking and a.fire_timers == b.fire_timers and a.threshold == b.threshold


func test_the_same_seed_gives_the_same_force_on_every_map_and_recon_choice() -> void:
	var maps: Array = GameConfig.MAPS.keys()
	check(maps.size() >= 2, "Setup: more than one map to compare (%d)" % maps.size())
	for seed_value in [731, 4242]:
		var reference: Dictionary = {}
		var positions_seen: Dictionary = {}
		for map_id in maps:
			for recon in [GameConfig.ReconMode.SPOTTER, GameConfig.ReconMode.DRONE_TEAM]:
				var sig: Dictionary = start(map_id, recon, seed_value)
				positions_seen[sig.first_position] = true
				if reference.is_empty():
					reference = sig
					continue
				check(same_force(reference, sig), "Seed %d, map %s, %s: the same enemy force as the first run (%d squads/%d mortars vs %d/%d)" % [seed_value, map_id, GameConfig.ReconMode.keys()[recon], sig.squads, sig.mortars, reference.squads, reference.mortars])
		# Positions deliberately follow the map — if every map put the first enemy unit in the very same
		# place, this test could be passing without the map ever having actually changed underneath it.
		check(positions_seen.size() > 1, "Seed %d: the maps really did change (the first enemy unit starts in different places on different maps)" % seed_value)


## The other half of "everything else that is going on": the player side's own setup. Fewer player squads
## means fewer player `_make_unit` calls before the enemy is built — which is exactly what used to shift it.
func test_the_players_own_setup_cannot_shift_it() -> void:
	var map_id: String = GameConfig.current_map_id()
	var full: Dictionary = start(map_id, GameConfig.ReconMode.SPOTTER, 731)
	var one_squad: Dictionary = start(map_id, GameConfig.ReconMode.SPOTTER, 731, 1)
	check(same_force(full, one_squad), "The same seed gives the same enemy force whether the player fields every default squad or just one")


## The point of a seed is still that it SELECTS a force: independence from the setup must not have turned the
## force into one fixed constant. Rolled directly from the enemy stream (cheap), across many seeds.
func test_different_seeds_still_give_different_forces() -> void:
	var bm := BattleManager.new()
	root.add_child(bm)
	bm.set_process(false)
	var seen: Dictionary = {}
	for s in range(40):
		bm.battle_seed = s
		bm._seed_enemy_rng()
		var size: Dictionary = bm.roll_enemy_force_size()
		seen["%d/%d" % [size.squads, size.mortars]] = true
	check(seen.size() > 3, "Different seeds give a spread of different forces, not one fixed one (%d distinct squad/mortar combinations across 40 seeds)" % seen.size())
	bm.free()
