extends SceneTree
## Research harness (the folder is ignored by Godot: copy it under scripts/ to run): what an assault costs the attackers on the approach.
## User: "Approach should be costly unless the defenders are suppressed." One defending squad of nine (our side; dug in, in a building or in
## the open), and one to four enemy squads of nine starting 250 m away, each ordered to close to 20 m. The approach is run until every
## attacker has reached 25 m (or been put out of the fight), BEFORE grenades and hand to hand have any say: close quarters are switched
## off by distance (the run stops the moment the first attacker is within 25 m). Defenders unsuppressed, or pinned.
const TestBattleManagerScript := preload("res://scripts/tests/test_battle_manager.gd")
const TestCombatLogScript := preload("res://scripts/tests/test_combat_log.gd")

const TRIALS := 24
const TICK_DELTA := 0.1 # 6 s of battle time a tick: finer than the battles' 30 s, an approach is a minute or two

func _initialize() -> void:
	call_deferred("run")

func m(x: float, y: float = 0.0) -> Vector2:
	return Vector2(x, y) * GameConfig.PIXELS_PER_METER

func place_for(kind: String) -> Vector2:
	GameConfig.set_active_map("voznesensk")
	GameConfig._build_terrain_grid()
	var rect: Rect2 = GameConfig._building_rects[0]
	if kind == "building":
		return rect.get_center()
	for dx in [-90.0, 90.0, -140.0, 140.0]:
		var p: Vector2 = Vector2(rect.position.x if dx < 0.0 else rect.end.x, rect.get_center().y) + Vector2(dx, 0.0) * GameConfig.PIXELS_PER_METER
		if GameConfig.get_terrain_type_at(p) == GameConfig.TerrainType.OPEN:
			return p
	return Vector2.INF

func run() -> void:
	for kind in ["open", "building"]:
		for dug in [false, true]:
			if kind == "building" and dug:
				continue
			for attackers in [1, 4]:
				for pinned in [false, true]:
					var where: Vector2 = place_for(kind)
					var lost_total := 0.0
					var arrive_total := 0.0
					var arrived_any := 0
					var defender_fired := 0.0
					for t in TRIALS:
						seed(9100 + t)
						var bm = TestBattleManagerScript.new()
						root.add_child(bm)
						var log = TestCombatLogScript.new()
						var doctrine := {
							"squads": [{"position": where, "retreat_threshold": 3.0}],
							"mortar": {"position": GameConfig.CURRENT_MAP.player.mortar_default_position, "shoot_and_scoot": true},
							"spotter": {"position": GameConfig.CURRENT_MAP.player.spotter_default_position},
							"recon_mode": GameConfig.ReconMode.DRONE_TEAM,
						}
						bm.start_battle(doctrine, log)
						var defender: Unit = null
						for u in bm.player_units:
							if u.kind == Unit.Kind.SQUAD and defender == null:
								defender = u
							elif u.kind != Unit.Kind.DRONE:
								u.state = Unit.State.WITHDRAWN
						defender.global_position = where
						defender.retreat_threshold = 3.0
						if not dug:
							defender.entrenchment = Unit.Entrenchment.NONE
							defender.digging_seconds = 0.0
						defender.dig_anchor = where
						var ring: Array[Unit] = []
						var bearings := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
						for e in bm.enemy_units:
							if e.kind == Unit.Kind.SQUAD and ring.size() < attackers:
								e.global_position = where + bearings[ring.size()] * m(250).x
								e.sought_cover = true
								e.retreat_threshold = 3.0
								e.entrenchment = Unit.Entrenchment.NONE
								e.dig_anchor = e.global_position
								# ordered to close, as the assault does
								var away: Vector2 = e.global_position - where
								e.move_target = where + away.normalized() * m(20).x
								e.has_move_target = true
								e.assaulting = true
								e.move_speed = GameConfig.ENEMY_ADVANCE_SPEED
								ring.append(e)
							else:
								e.state = Unit.State.WITHDRAWN
						# Enemies are visible to the defender (they are in plain sight), and the defender is not suppressed unless said
						for e in ring:
							e.is_visible = true
						var start_pips := 0
						for e in ring:
							start_pips += e.pips
						var ticks := 0
						var first_in := -1.0
						var shots_before: int = bm._history_fire_events.size()
						while ticks < 600:
							if pinned:
								defender.suppression = 1.0
								defender.pinned = true
							bm._process(TICK_DELTA)
							ticks += 1
							var any_within := false
							for e in ring:
								if e.state == Unit.State.ACTIVE and e.global_position.distance_to(where) <= m(25).x:
									any_within = true
							if any_within:
								first_in = bm.scenario_elapsed_time
								break
							var any_moving := false
							for e in ring:
								if e.state == Unit.State.ACTIVE and e.has_move_target:
									any_moving = true
							if not any_moving:
								break
						var left := 0
						for e in ring:
							left += e.pips
						lost_total += float(start_pips - left)
						if first_in >= 0.0:
							arrived_any += 1
							arrive_total += first_in
						defender_fired += float(bm._history_fire_events.size() - shots_before)
						if is_instance_valid(log):
							log.free()
						bm.queue_free()
						await process_frame
					print("%-8s %-8s %d attacker%s, defenders %-12s: attackers lost %.1f of %d before reaching 25 m (%.0f%%); reached in %d of %d; defenders fired %.1f volleys" % [
						kind, "dug in" if dug else "not dug", attackers, "" if attackers == 1 else "s", "pinned" if pinned else "unsuppressed",
						lost_total / TRIALS, attackers * 9, 100.0 * lost_total / TRIALS / float(attackers * 9), arrived_any, TRIALS, defender_fired / TRIALS])
	quit()
