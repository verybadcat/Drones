# Pre-Rewrite Doctrine Baseline

Generated 2026-09-08T00:43:47, 100 trials per recon mode, tagged `before-tactical-rewrite`.

Captured immediately before the planned tactical-decisionmaking rewrite (see the design doc's own revision log) — a baseline for COMPARISON, not a pass/fail gate. The rewrite is explicitly meant to change some of these numbers by grounding decisions in general principles ("win the battle," "keep our people alive," "cause enemy casualties") instead of individually-tuned thresholds; a changed number here isn't automatically a regression. Re-run `scripts/tests/characterize_doctrine.gd` after the rewrite and compare by eye.

Surrender is called out separately in each section below because it's expected to stay outside the new principled framework entirely — once a squad is surrendering, it has already put its own survival above winning, so there's no "win the battle" principle left to derive that decision from.

## SPOTTER (100 trials)

### Overall outcome
- Held the position: 40.0%
- Verdict `SUCCESSFUL DEFENSE`: 21.0%
- Verdict `DEFEAT`: 60.0%
- Verdict `PYRRHIC DEFENSE`: 19.0%
- Average exchange ratio: 1.08
- Average battle duration: 158.1 tactical minutes
- Average player casualties: 14.7 / 32.0 (46.0%)
- Average enemy casualties (true): 13.4 / 62.0 (21.6%)

### Surrender (expected to remain unchanged by the rewrite — see design doc)
- Player squads surrendered: 0.00 per battle on average
- Enemy squads surrendered: 0.01 per battle on average

### Retreat
- Player units that ever retreated/withdrew: 3.04 per battle
- Of those, escalated to the extended (deep) safe line: 11.5%
- Threat-avoidance steering active (of all checks made): 26.3%

### Targeting (does a squad ever fire on an enemy mortar?)
- Player squad-on-enemy-mortar shots: 0 total (0.000 per battle)
- Enemy squad-on-player-mortar shots: 9 total (0.090 per battle)
- Full targeting distribution this run (attacker_team:attacker_kind->target_kind -> count):
  - `enemy:MORTAR->MORTAR`: 11
  - `enemy:MORTAR->SPOTTER`: 308
  - `enemy:MORTAR->SQUAD`: 3543
  - `enemy:SQUAD->MORTAR`: 9
  - `enemy:SQUAD->SPOTTER`: 379
  - `enemy:SQUAD->SQUAD`: 17272
  - `player:MORTAR->SQUAD`: 651
  - `player:SQUAD->SQUAD`: 14314

### Mortar crew: hold position vs. abandon the gun when hit
- Player: held 32.5% of 80 hit-decisions
- Enemy: held 40.0% of 20 hit-decisions

### Mortar ammo cook-off
- Occurred in 21.9% of 128 rolls

### Wounded evacuation (enemy alone can choose to abandon)
- Player: 192 decisions, carried 100.0%, abandoned 0.0%
- Enemy: 150 decisions, carried 78.7%, abandoned 21.3%

### Mortar resupply
- Player: 0 runs spawned, n/a destroyed in transit, n/a delivered-or-aborted (not distinguished further)
- Enemy: 217 runs spawned, 0.0% destroyed in transit, 100.0% delivered-or-aborted (not distinguished further)

### Enemy flanking maneuver
- Squads ever assigned the flanking route: 1.80 per battle
- Of those, actually reached the flank waypoint and pivoted: 74.4%

## DRONE_TEAM (100 trials)

### Overall outcome
- Held the position: 60.0%
- Verdict `PYRRHIC DEFENSE`: 18.0%
- Verdict `SUCCESSFUL DEFENSE`: 42.0%
- Verdict `DEFEAT`: 40.0%
- Average exchange ratio: 1.50
- Average battle duration: 167.1 tactical minutes
- Average player casualties: 13.9 / 34.0 (40.8%)
- Average enemy casualties (true): 18.3 / 62.0 (29.5%)

### Surrender (expected to remain unchanged by the rewrite — see design doc)
- Player squads surrendered: 0.00 per battle on average
- Enemy squads surrendered: 0.05 per battle on average

### Retreat
- Player units that ever retreated/withdrew: 2.70 per battle
- Of those, escalated to the extended (deep) safe line: 14.4%
- Threat-avoidance steering active (of all checks made): 21.7%

### Targeting (does a squad ever fire on an enemy mortar?)
- Player squad-on-enemy-mortar shots: 0 total (0.000 per battle)
- Enemy squad-on-player-mortar shots: 0 total (0.000 per battle)
- Full targeting distribution this run (attacker_team:attacker_kind->target_kind -> count):
  - `enemy:MORTAR->DRONE_TEAM`: 650
  - `enemy:MORTAR->SQUAD`: 3799
  - `enemy:SQUAD->DRONE_TEAM`: 346
  - `enemy:SQUAD->SQUAD`: 18818
  - `player:MORTAR->MORTAR`: 50
  - `player:MORTAR->SQUAD`: 611
  - `player:SQUAD->SQUAD`: 18135

### Mortar crew: hold position vs. abandon the gun when hit
- Player: held 45.5% of 66 hit-decisions
- Enemy: held 50.0% of 8 hit-decisions

### Mortar ammo cook-off
- Occurred in 28.8% of 104 rolls

### Wounded evacuation (enemy alone can choose to abandon)
- Player: 145 decisions, carried 100.0%, abandoned 0.0%
- Enemy: 228 decisions, carried 81.1%, abandoned 18.9%

### Mortar resupply
- Player: 1 runs spawned, 0.0% destroyed in transit, 100.0% delivered-or-aborted (not distinguished further)
- Enemy: 260 runs spawned, 0.0% destroyed in transit, 100.0% delivered-or-aborted (not distinguished further)

### Enemy flanking maneuver
- Squads ever assigned the flanking route: 1.94 per battle
- Of those, actually reached the flank waypoint and pivoted: 71.6%

### Drone fleet
- Sorties launched per battle: 1.65
- Lost to battery exhaustion per battle: 0.00
- Shot down by the enemy per battle: 0.00
