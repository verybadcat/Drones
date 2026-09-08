# Pre-Rewrite Doctrine Baseline

Generated 2026-09-08T01:18:54, 100 trials per recon mode, tagged `before-tactical-rewrite`.

Captured immediately before the planned tactical-decisionmaking rewrite (see the design doc's own revision log) — a baseline for COMPARISON, not a pass/fail gate. The rewrite is explicitly meant to change some of these numbers by grounding decisions in general principles ("win the battle," "keep our people alive," "cause enemy casualties") instead of individually-tuned thresholds; a changed number here isn't automatically a regression. Re-run `scripts/tests/characterize_doctrine.gd` after the rewrite and compare by eye.

Surrender is called out separately in each section below because it's expected to stay outside the new principled framework entirely — once a squad is surrendering, it has already put its own survival above winning, so there's no "win the battle" principle left to derive that decision from.

## SPOTTER (100 trials)

### Overall outcome
- Held the position: 34.0%
- Verdict `DEFEAT`: 66.0%
- Verdict `PYRRHIC DEFENSE`: 15.0%
- Verdict `SUCCESSFUL DEFENSE`: 19.0%
- Average exchange ratio: 0.97
- Average battle duration: 153.0 tactical minutes
- Average player casualties: 14.5 / 32.0 (45.3%)
- Average enemy casualties (true): 12.5 / 62.0 (20.2%)

### Battle-outcome score (see design doc for the fixed rubric)
Two separate numbers per battle: the TRUE score (ground truth — what an actual decision-making framework should be evaluated against) and the ESTIMATED score (the player's own best-guess figures — what would actually justify a displayed verdict). These are expected to diverge sometimes; that's intentional, not an error.
- Average true score: -44.23
- Average estimated (best-guess) score: -77.45
- By current verdict label (still held+exchange_ratio-based, NOT yet derived from this score):
  - `DEFEAT` (66 battles): true score avg -73.2 (range -136.0 to -16.0), estimated score avg -97.1 (range -148.0 to -55.0)
  - `PYRRHIC DEFENSE` (15 battles): true score avg -15.4 (range -53.0 to 11.5), estimated score avg -47.7 (range -73.0 to -16.0)
  - `SUCCESSFUL DEFENSE` (19 battles): true score avg 33.5 (range -43.0 to 89.5), estimated score avg -32.7 (range -87.0 to 8.0)

### Surrender (expected to remain unchanged by the rewrite — see design doc)
- Player squads surrendered: 0.00 per battle on average
- Enemy squads surrendered: 0.00 per battle on average

### Retreat
- Player units that ever retreated/withdrew: 3.05 per battle
- Of those, escalated to the extended (deep) safe line: 9.2%
- Threat-avoidance steering active (of all checks made): 25.1%

### Targeting (does a squad ever fire on an enemy mortar?)
- Player squad-on-enemy-mortar shots: 0 total (0.000 per battle)
- Enemy squad-on-player-mortar shots: 0 total (0.000 per battle)
- Full targeting distribution this run (attacker_team:attacker_kind->target_kind -> count):
  - `enemy:MORTAR->MORTAR`: 7
  - `enemy:MORTAR->SPOTTER`: 318
  - `enemy:MORTAR->SQUAD`: 3670
  - `enemy:SQUAD->SPOTTER`: 346
  - `enemy:SQUAD->SQUAD`: 15903
  - `player:MORTAR->SQUAD`: 677
  - `player:SQUAD->SQUAD`: 13047

### Mortar crew: hold position vs. abandon the gun when hit
- Player: held 42.4% of 66 hit-decisions
- Enemy: held 47.4% of 19 hit-decisions

### Mortar ammo cook-off
- Occurred in 24.1% of 112 rolls

### Wounded evacuation (enemy alone can choose to abandon)
- Player: 187 decisions, carried 100.0%, abandoned 0.0%
- Enemy: 141 decisions, carried 77.3%, abandoned 22.7%

### Mortar resupply
- Player: 2 runs spawned, 0.0% destroyed in transit, 100.0% delivered-or-aborted (not distinguished further)
- Enemy: 219 runs spawned, 0.0% destroyed in transit, 100.0% delivered-or-aborted (not distinguished further)

### Enemy flanking maneuver
- Squads ever assigned the flanking route: 2.07 per battle
- Of those, actually reached the flank waypoint and pivoted: 70.5%

## DRONE_TEAM (100 trials)

### Overall outcome
- Held the position: 59.0%
- Verdict `DEFEAT`: 41.0%
- Verdict `SUCCESSFUL DEFENSE`: 44.0%
- Verdict `PYRRHIC DEFENSE`: 15.0%
- Average exchange ratio: 1.63
- Average battle duration: 164.9 tactical minutes
- Average player casualties: 13.5 / 34.0 (39.8%)
- Average enemy casualties (true): 19.6 / 62.0 (31.5%)

### Battle-outcome score (see design doc for the fixed rubric)
Two separate numbers per battle: the TRUE score (ground truth — what an actual decision-making framework should be evaluated against) and the ESTIMATED score (the player's own best-guess figures — what would actually justify a displayed verdict). These are expected to diverge sometimes; that's intentional, not an error.
- Average true score: -5.46
- Average estimated (best-guess) score: -54.99
- By current verdict label (still held+exchange_ratio-based, NOT yet derived from this score):
  - `DEFEAT` (41 battles): true score avg -64.3 (range -145.5 to -15.5), estimated score avg -101.1 (range -171.0 to -63.0)
  - `SUCCESSFUL DEFENSE` (44 battles): true score avg 46.8 (range -8.5 to 103.5), estimated score avg -19.4 (range -68.0 to 44.0)
  - `PYRRHIC DEFENSE` (15 battles): true score avg 2.3 (range -33.5 to 39.5), estimated score avg -33.2 (range -54.0 to -5.0)

### Surrender (expected to remain unchanged by the rewrite — see design doc)
- Player squads surrendered: 0.00 per battle on average
- Enemy squads surrendered: 0.03 per battle on average

### Retreat
- Player units that ever retreated/withdrew: 2.70 per battle
- Of those, escalated to the extended (deep) safe line: 14.1%
- Threat-avoidance steering active (of all checks made): 22.0%

### Targeting (does a squad ever fire on an enemy mortar?)
- Player squad-on-enemy-mortar shots: 0 total (0.000 per battle)
- Enemy squad-on-player-mortar shots: 0 total (0.000 per battle)
- Full targeting distribution this run (attacker_team:attacker_kind->target_kind -> count):
  - `enemy:MORTAR->DRONE_TEAM`: 591
  - `enemy:MORTAR->SQUAD`: 3754
  - `enemy:SQUAD->DRONE_TEAM`: 312
  - `enemy:SQUAD->SQUAD`: 16147
  - `player:MORTAR->MORTAR`: 44
  - `player:MORTAR->SQUAD`: 587
  - `player:SQUAD->SQUAD`: 17143

### Mortar crew: hold position vs. abandon the gun when hit
- Player: held 40.8% of 71 hit-decisions
- Enemy: held 66.7% of 6 hit-decisions

### Mortar ammo cook-off
- Occurred in 27.4% of 106 rolls

### Wounded evacuation (enemy alone can choose to abandon)
- Player: 144 decisions, carried 100.0%, abandoned 0.0%
- Enemy: 256 decisions, carried 74.2%, abandoned 25.8%

### Mortar resupply
- Player: 0 runs spawned, n/a destroyed in transit, n/a delivered-or-aborted (not distinguished further)
- Enemy: 269 runs spawned, 0.0% destroyed in transit, 100.0% delivered-or-aborted (not distinguished further)

### Enemy flanking maneuver
- Squads ever assigned the flanking route: 1.99 per battle
- Of those, actually reached the flank waypoint and pivoted: 63.8%

### Drone fleet
- Sorties launched per battle: 1.68
- Lost to battery exhaustion per battle: 0.00
- Shot down by the enemy per battle: 0.00
