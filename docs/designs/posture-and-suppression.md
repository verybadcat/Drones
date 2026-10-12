# Posture and suppression

Status: design, 2026-10-12. Stage A (below) is the only part built when this was written.

## What was asked for

User, 2026-10-12: posture and suppression are tied together, and "Posture should be something that all units have at all times. Not just
tied to particular situations such as mortar fire. A moving unit has to be standing up." Earlier: "If we add posture, it can't just be under
fire. It would have to be throughout the game. I assume it would affect other interactions, too." Standing instruction for the whole combat
model: stay as close to the real world as possible (`docs/designs/realism-anchors.md`).

## What the real sources say (all secondary: Wikipedia's summaries; the manuals were not reached)

* Risk to troops from impact-fuzed shells by posture, UK WWII researchers ("citation needed" on the page): standing 1; lying 1/3; firing from
  trenches 1/15-1/50; crouching in trenches 1/25-1/100.
* Most casualties from a barrage come in the first 10-15 s, before troops improve their posture.
* US Army FM 7-90 planning figures, as already cited in `combat_resolver.gd`: a standing, exposed platoon under sustained 60 mm fire about
  20% casualties; prone under 10%; dug in with overhead cover under 10%, mostly direct hits.
* Fire and movement: one element's fire keeps the enemy's heads down so another can move; a fixing force pins the defender.
* No figure found for how long it takes to go to ground, how long troops stay down, or how large suppression is. Those are JUDGMENT below.

## Where "exposed" is encoded today (the inventory)

There is no posture field. Exposure is `Unit.activity` (STATIONARY or MOVING) crossed with the terrain under the unit, in these places:

| Where | What it does | Posture it implies |
|---|---|---|
| `CombatResolver.hit_probability` | A moving defender gets no terrain cover (multiplier 1.0) and then `MOVING_HIT_MULTIPLIER` 1.6 for small arms (mortar: 1.1 predictable, 0.25 unpredictable). A stationary one gets `SQUAD_COVER_MULTIPLIER` (open 1.6, trees 0.2, building 0.1) or, against a mortar, `MORTAR_COVER_MULTIPLIER` (1.3, 0.5, 0.3) | moving = standing; stationary in the open = standing (the comment says exactly that: "standing exposed in the open is exactly as dangerous as being caught moving"); stationary in cover = down behind it |
| `BattleManager._apply_shell_blast`, `_mortar_friendly_fire_check` | terrain is OPEN if the unit is moving, else the terrain under it | same |
| `Unit._roll_crew_casualties` (crews) | the terrain under the crew | down in cover |
| `CombatResolver.blast_person_chance` | a squad member is 0.2 of the blast chance ("dispersed and often prone"; `MORTAR_CASUALTY_FRACTION`) | prone, always, whatever the squad is doing: the one place posture is hard-wired, and wrong for a squad caught on the move |
| `CombatResolver.roll_spot` | terrain concealment, `MOVING_SPOT_MULTIPLIER` 3.0 decaying over 240 s (`seconds_stationary`), exposed spotter 0.4 and crew 0.8 when not in cover | movement signature only; no effect of lying down |
| Suppression (`unit.suppression`, `pinned`) | a volley adds 0.25, a round within 60 m up to 0.6, decays in 180 s; pinned at 0.6 until under 0.35; a suppressed squad shoots up to 50% worse; a pinned enemy squad does not start a new advance, and our pinned squad does not take a standoff initiative | no effect on exposure, movement or posture |
| `Unit.take_hit` | an enemy squad seeks cover on its first hit; a squad hit by mortar fire bolts for cover with a chance | the move to cover is a separate order, not a change of posture |

Consequences: the calibration of the cover tables already contains posture (the 4x open-to-building spread for mortars is FM 7-90's
standing/prone/dug-in spread), so adding a posture factor on top without taking it out of the tables would count it twice. And a squad
caught moving takes a mortar round at 0.2 per person, as if it were lying down: a first round on a squad in the open is understated by
about 3x.

## The model

**One posture per ground unit, always.** Squads, mortar crews, spotters and drone teams. A drone is airborne and has none.

* STANDING: upright, whether walking, running or standing still.
* PRONE: down (lying or crouched), behind whatever is there.
* DUG_IN: in a prepared position (stage E). Reserved, not built before then.

**Invariant: a moving unit is STANDING.** It is built so it cannot be violated: `Unit.posture()` returns STANDING whenever `activity` is
MOVING, whatever was stored. A unit that is told to move while PRONE spends a rise time (JUDGMENT, 2-3 s) STANDING and not yet moving.

**Protection is the product of two things that were one number**: what is around the unit (terrain: open, trees, building) and how the unit
is lying in it (posture). Terrain protection is not posture: walls stop bullets for a man standing behind them.

**Posture changes** (stage B and after): a stationary unit goes PRONE a reaction time after fire arrives (a volley aimed at it, a round
landing near it, suppression above a level); it stays down while the fire lasts and for a while after; it is STANDING again when ordered to
move, when it has been unmolested for long enough, or by its own initiative. Going down is quick; getting up costs time. The first
arrivals of a barrage catch a standing unit, which is the "first 10-15 s" effect without a special case.

## Interactions, by stage

| Stage | Change | What it replaces | Expected effect on the model |
|---|---|---|---|
| A | `Unit.posture()` and `Unit.exposure_terrain()`; every consumer above asks one function whether the unit has terrain cover. Posture is derived: moving = standing; stationary in trees or a building = prone; stationary in the open = standing | the repeated `OPEN if moving else terrain` | none, asserted for every (activity, terrain) pair against the old rule |
| B | Stored state: a stationary unit goes to ground under fire (a reaction time), and rises. Protection becomes terrain x posture; PRONE in the open is 1/3 (the UK figure) of standing in the open. The squad's 0.2 splits into a dispersion factor and the prone factor, so a standing squad takes about 3x | the 0.2 hard-wired "often prone"; stationary-in-the-open treated as standing for ever | mortar and small-arms lethality against units that stop in the open falls after the first rounds; a first round on a squad caught moving rises 3x. The share of casualties from artillery (71% today, band 45-75%) will move: measure before and after |
| C | Posture reaches the other interactions: concealment (a man lying is harder to see), the rise delay before a move, shooting from prone (accuracy, arc), crossfire | the exposed/in-cover tests in `roll_spot` | spotting of still units in the open falls; moving off costs a few seconds |
| D | Suppression drives posture: suppression above a level puts a unit down and keeps it down; a pinned unit rises only when it eases. Deliberate use: a mortar fire mission or base of fire to pin a squad, and squads that wait for cover before a bound | "suppression exists but nobody uses it on purpose" | covering fire becomes a real tool for both sides; a new anchor is needed (rate of advance under covering fire) and none has been found yet |
| E | DUG_IN: a prepared position, with a build time, a posture factor of 1/15-1/50 of standing | no category | defenders who hold a position for long are far safer from indirect fire, as in the real figures |

## Order, and what is measured at each step

Each stage: root cause, change, a test that reproduces the scenario, a sensitivity check (revert, see it fail), the related tests, the full
suite, a log entry in `tactical-commander-doctrine.md`, a commit. After B, C, D and E the battle-level anchors are re-run with
`tools/research/realism_anchors_sim.gd`, and the result is recorded in `realism-anchors.md`: the artillery share of casualties, and the
casualty ratio of the two sides. A change that moves a band is a decision to be made explicitly, not drift.

## JUDGMENT (no source found; each is a number to be set, flagged and ranged when it is)

* Time to go to ground after fire arrives (2-6 s), time to rise (2-3 s), time to stay down after fire stops (10-60 s).
* How much a lying man is protected from small arms (the 1/3 above is for shells; for bullets the smaller silhouette is the cause, and the
  figure may be near it).
* The size of suppression (already judgment), and what level puts a unit down.
* How the Russian side's reaction time and initiative differ (`ENEMY_STANDOFF_INITIATIVE_CHANCE_PER_MIN` is already a judgment).
