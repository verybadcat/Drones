# Understanding and shaping the battle AI

This implementation gives William a way to inspect decisions, compare fictional commander styles, and identify the next decisions worth improving. It does not establish that a style models a real army or that a high-scoring choice is objectively optimal.

## Try it

1. Choose reconnaissance mode and deploy normally. Scroll down the doctrine sidebar to **Commander profiles**.
2. Choose your commander and the enemy commander independently. **Original doctrine** preserves the previous AI. Other profiles enable four editable player priorities and an optional deterministic targeting policy.
3. Selecting a player profile also sets a suggested casualty threshold. The standing withdrawal slider remains authoritative and can be changed afterward. Enemy profiles use their own suggested threshold; the original enemy retains `GameConfig.ENEMY_RETREAT_THRESHOLD`.
4. Optionally enter a battle seed. Start the battle, then click **Inspect AI (i)**. Use the existing **Pause** button to examine a moment.
5. Select a unit. Live records separate orders/state, target evaluation, and actual firing. Uncheck live records to scrub a frozen copy of that unit's recent decision changes. Inspection remains available after battle.
6. Export JSON to Godot's `user://decision_trace.json`; the inspector displays the actual filesystem path. Each export replaces that file. Enemy records are included only when **Developer view** is enabled.

The existing drone `d` overlay and enemy-knowledge `e` overlay remain available. The new inspector covers both reconnaissance modes, including infantry and mortar decisions.

## Assessment of the existing AI

The code already supports meaningful delegated behavior: team-visible contacts, remembered mortar leads, probabilistic spotting, ammunition and resupply, threshold-based withdrawal, a shared mortar/drone hunt, and movement commitments. It has combat history, drone reasoning, and mortar reasoning snapshots. These are useful foundations.

The main obstacle is that there is no single definition of a good decision. Several mechanisms coexist inside `battle_manager.gd`:

- `_pick_target` filters visible contacts by range and, for squads, line of sight. Original doctrine gives active mortars absolute priority, selects other squad targets uniformly, and selects other mortar targets with weighted randomness.
- `_decide_mortar_action` uses ordered early returns for engagement, committed displacement, self-preservation, and hunting. Firing is evaluated earlier in the tick. The label “preserve self” therefore does not mean every survival concern is compared with every available shot.
- `_drone_search_target` compares reconnaissance priorities while retaining important shared commitments.
- Infantry movement, emergency crew reactions, and commander withdrawal have their own rules. Some immediate reactions live in `unit.gd`.

Consequences:

- Changing a numerical target weight cannot override every early-return rule.
- A unit may make a reasonable choice from its information and still have a bad outcome. Evaluate information and expectations at decision time, separately from final results.
- Random variation is not by itself a model of human behavior. Stable preferences, limited information, reaction delays, and commitment should be separate dimensions.
- The existing battle-history snapshots record positions and states, not the decision evidence needed to explain them. The new recorder fills part of that gap without rerunning the AI.
- The simulation exposes some facts such as `is_visible` directly to decision code. That is existing behavior, not proof that a real commander would know those facts. A future belief model should separate perceived exposure from the engine's true visibility state.

## What the profiles actually change

| Profile | Protect allies | Pressure | Counter mortar | Ammo conservation | Suggested squad withdrawal | Target selection |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Original doctrine | Original rules | Original rules | Absolute mortar priority | Original rules | Player 30%; original enemy constant | Original randomness |
| Cautious | 2.5 | 0.5 | 1.0 | 1.5 | 20% | Weighted random |
| Aggressive | 0.5 | 2.5 | 1.5 | 0.4 | 60% | Weighted random |
| Deliberate evaluator | 1.5 | 1.0 | 1.5 | 1.0 | 35% | Highest score; stable ties |

For non-original profiles, legal firing targets compete on a shared scale:

```
pressure contribution       = 10 × remaining strength fraction × pressure weight
protection contribution     = existing nearby-squad danger score × protection weight
counter-mortar contribution = 10 × counter-mortar weight, for an active mortar
score                       = sum of contributions
```

These are deliberately simple preference heuristics, not expected damage, hit probabilities, or estimates of winning. All legal unit kinds receive a pressure contribution; only active squads receive the nearby-threat contribution. Original doctrine keeps its existing score scale and overrides.

A mortar still considers a remembered opportunity before spending a shot on another kind of target, using profile-adjusted opportunity value. Its ammunition hold probability is multiplied by the conservation preference and clamped to `[0, 1]`. Existing immediate-threat overrides and firing legality remain in effect. The deliberate evaluator uses a fixed 0.5 cutoff for these hold decisions and chooses the highest target score. Other profiles sample weighted choices, so a lower score can legitimately win.

These preferences apply symmetrically to **firing choices on both sides**. They do not change weapon accuracy, health, force size, or perception. Drone reconnaissance, movement selection, emergency mortar displacement, crew survival reactions, and army-level withdrawal still use their existing rules. In particular, “deliberate” is a deterministic targeting policy, not an LLM, a planner, or a fully deterministic army.

## What the inspector can establish

A target record includes the chosen target or hold decision, the actual reason branch, eligible visible alternatives, rejection reasons for visible but illegal targets, score contributions, and probability/roll evidence where applicable. Probabilities shown for weighted picks are conditional on reaching target selection; earlier hold decisions are separate gates. Highest-score ties use candidate order.

Records are captured when the simulation evaluates the choice. The panel never invokes selection again, consumes randomness, or reads hidden contacts to invent an explanation. A **Shot fired** record separately links the targeting evidence used for a real firing action. Orders/state records include strength, squad withdrawal threshold, mortar ammunition and reload, and movement destination when applicable. Major infantry movement orders now record their cause at issuance.

The panel deliberately identifies movement paths without recorded causes. It does not fabricate rejected movement alternatives or forecasts for them. An old target record is timestamped and may be superseded by a later state or order. Historical evidence is a copy of what was recorded, not recomputed from current positions.

Units receive distinct trace numbers so identically named squads can be distinguished. Orders include their captured map position.

The recorder keeps the latest record for each unit/channel and the latest **2,000 decision changes across the battle**. It retains every firing event within that bounded window, but it is not a complete battle replay. Historical review freezes its list while the battle continues. Enemy inspection is an explicit developer option; player-facing target records omit hidden contacts. JSON has schema version 1 and includes the seed, view mode, history limit, and captured events.

## Comparing styles honestly

Use the same deployment, reconnaissance mode, enemy profile, seed set, and fixed simulation timestep. Compare several seeds and inspect surprising decisions. A single seed or a single victory does not establish improvement.

The seed makes a run reproducible with the same code, configuration, and timestep. Interactive frame timing can still differ. Changing a policy changes random-number consumption, so matched seeds do not guarantee identical later combat rolls across different policies. A future evaluation harness should use independent random streams for world generation, combat, and policy sampling.

Useful measures include objective outcome, friendly casualties, resources spent, time spent stationary without a useful task, repeated order reversals, and information available when a choice was made. The existing `characterize_doctrine.gd` already measures several outcome dimensions, but its output paths overwrite the historical pre-rewrite baseline. Do not use that historical report as a pass/fail gate or overwrite it casually.

## Next architecture for broader desires and agent controllers

The first extension should compare **actions**, not just firing targets: keep observing, act now, continue a commitment, reposition, resupply, or withdraw. Keep each change bounded and compare it against the original behavior.

1. **Observation:** build a side-specific immutable snapshot of known contacts, report ages/confidence, own units/resources, orders, and current commitments. Keep engine truth out of the controller input.
2. **Legal actions:** generate concrete alternatives and rejected-action reasons. Constraints such as ammunition, movement feasibility, and forbidden orders belong here rather than being disguised as low preference scores.
3. **Evaluation:** return separate estimated mission progress, force preservation, pressure, information gain, resource/time cost, and uncertainty. Normalize contributions before applying profile weights. This requires forecasts the current target scoring does not provide.
4. **Policy:** choose among the legal alternatives. Human-like archetypes can vary bounded observation errors, reaction delay, risk aversion, and commitment duration as well as objective weights. Add those dimensions explicitly and test them independently.
5. **Execution and evidence:** validate the selected action against current state, issue it once, and record the observation, alternatives, scores, selection rule, and interruption conditions together. Explanations should come from this evidence.

A future agent controller should use that same observation/action contract. Give it a time budget, validate its proposal, and fall back to a local policy when the response is missing, stale, or invalid. Keep its narrative rationale distinct from recorded simulator evidence. External agents should initially propose higher-level orders at a slower cadence; the simulation should retain the fast execution loop. No external agent service is connected by this change.

## Validation

Run:

```sh
godot --headless --editor --path . --quit
godot --headless --path . --script scripts/tests/test_decision_ai.gd
godot --headless --path . --script scripts/tests/test_decision_ui.gd
```

The suite checks preference-driven choices, visibility/range rejection, immutable records, reads that preserve RNG state, a complete seeded battle with and without the inspector, and completion under every profile in both reconnaissance modes. The UI suite also checks profile wiring, frozen review history, enemy filtering on export, and restart cleanup. Four additional fixed-step battles (seeds 7 and 731, both reconnaissance modes) matched the pre-change implementation in final state and firing history.

These are correctness checks, not a claim that the archetypes are balanced or realistic.
