# Real-world research notes

Where the real-world facts the game is held to are kept, so they are found again instead of re-researched. The ledger of **what the game does
against each figure** is `docs/designs/realism-anchors.md`; the dated reasoning is in `docs/designs/tactical-commander-doctrine.md`. This file is
the **sources and findings**, by topic, with what was NOT found. A figure with no source is marked JUDGMENT in the ledger.

The user's standing instruction: "as much as possible to keep the game results close to the real world", and, when a result looks off, "research
the real world and compare".

## How to research (what works, what does not) — 2026-10-21

* **Use the gstack browser** (`$HOME/.claude/skills/gstack/browse/dist/browse`, commands `goto <url>`, `text`, `links`); never the Chrome tools.
* **Search engines refuse automated queries**: DuckDuckGo (bot check; do not try to get past it), Mojeek (403); Bing returns unrelated pages. So
  there is **no web search**; go to a known URL.
* **Wikipedia by direct URL works** (`https://en.wikipedia.org/wiki/<Title>`; use quotes round titles with brackets). Its own search
  (`/w/index.php?search=...&fulltext=1`) only lists Wikipedia pages.
* **US field manuals on globalsecurity.org work, chapter by chapter**: `https://www.globalsecurity.org/military/library/policy/army/fm/7-90/Ch7.htm`
  (FM 7-90 *Tactical Employment of Mortars*, 1992; chapters `Ch1`..`Ch9`, appendices `Appa`..`Appm`; the same text is MCWP 3-15.2) and
  `.../fm/23-90/ch4.htm` (FM 23-90 *Mortars*, 2000; `ch1`..`ch9`, `appa`, `appb`). Fetch the index page, `links` it for the chapter URLs, `text` each
  into a file and `grep`. The text is behind a "free preview" banner but the body comes through.
* **Not retrievable**: the RUSI report on the 2022 war (the PDF link returns only the landing page); anything paywalled; the JMEM tables
  (classified). Ukraine-war practice for mortar crews (crew sizes in use, displacement times, survival) was **not reached**.
* Wikipedia and the manuals are secondary or general: treat their figures as order-of-magnitude, and say so in the ledger.

## Mortar crews and serving the gun

* Crews: 60 mm M224 has 3; 82 mm 2B14 Podnos has 4 (the entire system "can be broken down into manpack loads to be carried by the four-man crew");
  81 mm M252 has 5 (squad leader, gunner, assistant gunner, two ammunition bearers); Soltam K6 120 mm has 5 (Wikipedia). "A mortar squad consists of
  three to five mortarmen, depending on the system" (FM 23-90, ch. 1).
* Roles per round (FM 23-90): the gunner lays the sight and fires; the assistant gunner loads and helps lay; an ammunition bearer sets the charge and
  fuze and passes the round; the squad leader supervises.
* The 60 mm M224 can be fired **handheld by one soldier** (M8 baseplate; low charges; FM 23-90 ch. 3, Wikipedia). Carried by one, two or three
  (FM 23-90); on a road march "the three-man carry" (FM 7-90, ch. 8).
* Weights: 2B14 system 41.88 kg (Wikipedia); round 3.14 kg HE. The US 81 mm M252 (41.3 kg): cannon 16, mount 12, baseplate 13, sight 1.1 kg
  (Wikipedia). The 2B24's weights and the 2B14's piece weights were **not found**.
* Carrying: "50 pounds can be carried easily, and more than 100 pounds can be transported for moderate distances" on a packboard; not more than
  35 pounds per sling (FM 7-90, 8-16).
* Rates of fire (full crew): 2B14 24-30 rounds a minute (Wikipedia); M252 15 sustained, 30 for two minutes (FM 23-90 ch. 4); M224 20 sustained
  (Wikipedia).
* **Not found**: any minimum crew, or the rate of fire of a reduced crew. FM 7-90 only says "understrength mortar squads can be consolidated and
  rested" and that "under extreme circumstances" a commander may leave one mortar behind so its ammunition can be carried for the other.

## Counter-battery and how crews avoid it

* Detection (FM 7-90, ch. 7, 7-1): visual observers with laser rangefinders locate a mortar from up to 3 km to under 50 m; sound ranging locates a
  firing mortar from up to 20 km to about 100 m; the ARK-1 radar has about 20 km range; radio direction-finding can bring countermortar fire "within
  two to six minutes". Mortars are "not the first priority" for enemy target acquisition but the leader "must assume the enemy will use them".
* Defence (ch. 7): shoot-and-hide positions (the crew waits in a covered, concealed hide position and comes to the gun for a mission; baseplates
  and aiming posts can be left set up), frequent displacement ("the timing and number of moves are key to survival"; it costs responsiveness and
  fatigue), firing the lowest charge and elevation (harder to detect), a roving gun, offset registration, massing fires, dug-in positions, buildings
  as shields, positions up to 300 m apart (ch. 6).
* "It is difficult to knock out a battery"; "neutralization" (suppressing it, forcing it to move) is the lower bar and lasts only while fire falls
  (Wikipedia, Counter-battery fire).
* **Not found**: counter-battery kill rates per round or per salvo for a mortar crew; real displacement times; what a partial crew does.

## Effects of rounds on people (the key quantity for the mortar duel)

What was found:

* **FM 7-90, Appendix B** (target effects; the JMEM tables themselves are classified and were not reached):
  * B-3 f: against a **standing platoon-size unit, a 60 mm section firing five rounds per mortar should inflict about 20 percent casualties; if the
    enemy is prone, under 10 percent.** (Two mortars, ten rounds, an area target.)
  * B-5 a: surprise fire is always more effective than fire at an enemy that is warned and seeks cover: recent studies found a high casualty rate
    achievable with only **two rounds** on a standing platoon in the open, and needed **10 to 15 rounds** to match it when the platoon had been
    warned by adjusting rounds and sought cover. Prone troops cut the effect sharply: fire at standing forces is "almost twice
    as effective" as at prone; proximity (airburst) fuzes add about 40 percent against prone troops; troops in open fighting positions are far less
    affected (proximity rounds are 10 percent as effective as against troops in the open); overhead cover defeats all but direct hits.
  * B-4: one foot of soft ground, mud or sand, or 3 feet of snow, can cut the effect of a surface-burst round by up to 80 percent; hard rocky soil
    raises it; dense woods turn impact rounds into airbursts (wooden splinters make severe wounds).
  * For planning, each HE round has "a circular lethal bursting area" (Figure B-5, Table B-1 give areas in square metres; not in the text reached).
* Radii: US 81 mm M252 HE round "effective kill radius of 35 m" (Wikipedia); the ledger's 26 m for 50 percent of exposed men for an 82 mm round (Type 67,
  cited in `game_config.gd`). M67 hand grenade (180 g of Comp B): fatality radius 5 m, injury radius 15 m, fragments to 230 m (Wikipedia).
* Posture, from UK WWII researchers via Wikipedia's Artillery article ("citation needed"): relative risk to impact-fuzed shells: standing 1, lying
  1/3, firing from a trench 1/15-1/50, crouching in one 1/25-1/100. Most casualties come in the first 10-15 seconds, before troops improve posture.
* Definitions: a casualty is "any person lost to a unit", "not someone who sustains injuries which do not prevent them from fighting" (Wikipedia).

Larger radii: searched harder on 2026-10-22; **no source gives a probability of casualty at 2-4 times the casualty radius.** What there is:

* Radii by round: US 81 mm M252 "effective kill radius" 35 m; US 120 mm M120 "lethality radius" 69 m (Wikipedia, citing US Army); 82 mm Type 67 26 m for 50 percent
  (in `game_config.gd`).
* The hand grenade is the one small-charge case with three figures: M67 (about 180 g of Comp B): fatality radius 5 m, injury radius 15 m, fragments
  to 230 m (Wikipedia). Injuries to three times the fatal radius, and some fragments far beyond. M16 bounding mine: injuries up to 200 m; PADMINE:
  lethal out to 50 m; Claymore: "100-meter blast radius" (Wikipedia).
* Doctrine: 60 mm fire supporting an assault allows the assaulting troops to close to "about 50 meters (minimum safe distance)" (FM 7-90, ch. 8). The
  JMEM lethal-area and safe-distance tables (FM 101-62-1, -2/1, -3) are classified (listed in FM 7-90's references). FM 6-30: "danger close" is a
  procedural limit, within 600 m of friendly troops for mortars and artillery, not a casualty figure.
* Tried and empty: FM 7-90, 23-90, 6-30, 6-40, 6-20-40 text searches for radius, casualty, safe distance, fragment range; Wikipedia pages for
  fragmentation, mortars (M224, M252, M120, M30, M29, L16, Stokes, 2B11, M-43), shells, grenades, mines, Claymore, indirect fire.
* So the shape of the fall-off beyond the 50 percent radius is **not verified** by anything reached. Three shapes through the same 26 m point, per
  exposed standing person, for comparison only (my calculation; the Gaussian is the textbook "Carleton" function from memory, not checked):

  | distance | the game | fragment density 1/r² | Gaussian |
  |---|---|---|---|
  | 15 m | 67% | 87% | 79% |
  | 26 m | 50% | 50% | 50% |
  | 40 m | 34% | 25% | 19% |
  | 50 m | 26% | 17% | 8% |
  | 65 m | 12% | 10% | 1% |
  | 80 m | 6% | 7% | 0.1% |
  | 100 m | 2% | 5% | ~0 |

  The game's curve lies between the other two from 40 m to 65 m and is below the 1/r² curve beyond 80 m. **An earlier remark (2026-10-21) that the game is
  generous at 35-70 m is withdrawn**: it rested on the Gaussian, which the grenade figures (injuries to three times the fatal radius, fragments far
  beyond) do not favour.
* **Everything that bears on the drop-off, proven or not** (2026-10-22; each item marked):
  1. *Sourced.* A small round's injuries reach three times its fatal radius and some fragments fly far beyond it (M67: fatal 5 m, injury 15 m,
     fragments to 230 m; Wikipedia). So casualties do not stop at the kill radius; the amount at 2-4 times the radius is not given.
  2. *Sourced.* Kill radii: 81 mm 35 m, 120 mm 69 m (Wikipedia, citing US Army); 82 mm Type 67 casualty radius 26 m (cited in `game_config.gd`; an
     "effective kill radius" and a 50 percent casualty radius are not the same thing, and the casualty radius is the larger).
  3. *Sourced, but not a probability.* Troops assaulting under 60 mm fire may close to "about 50 meters (minimum safe distance)" (FM 7-90, ch. 8): a risk
     accepted for a small round at about 2-3 times its casualty radius. The risk level behind a "minimum safe distance" was not found.
  4. *Unproven, general physics.* From a point burst the fragments spread over a sphere (or hemisphere on the ground), so the number passing through a
     given area falls as 1/r²; air drag slows the small ones but heavy ones keep their energy for hundreds of metres. The chance that a person is hit by
     a fragment that incapacitates is then about density x presented area x chance a hit incapacitates, which is the 1/r² column above in the far field.
     The Gaussian ("Carleton") form is a planning convenience for short ranges (from memory; not verified).
  5. *Sourced.* A steep fall makes the pattern close to circular and more effective ("the steeper the angle of the fall of the round, the more effective
     it is"; FM 7-90, B-2 and B-5), which is why mortar lethal areas are planned as circles.
  6. *Sourced in direction.* Posture changes the drop-off: standing is almost twice as vulnerable as prone (FM 7-90, B-5; the UK WWII figures give
     1:3). Fragments in the far field travel low, so lying down should help more far out than near the burst (unproven).
  7. *Sourced.* Soft ground cuts a surface burst's effect by up to 80 percent (FM 7-90, B-4): ground matters for the whole pattern, not only the far field.
  8. *Unproven.* A "casualty" is a person lost to the unit; far-field fragments are slower and smaller, so more of the wounds at long range should be
     light ones that leave the person at their post. The share was not found.
  9. *Unattributed.* The game's code quotes "casualty radius is a statistical planning figure, not a wall: fragments kill well beyond the published radius,
     and people survive inside it" as real reporting; the source is not named and was not found again.
* **Severity by distance** (killed / seriously wounded / lightly wounded, and the share of the lightly wounded who stay at their post) was not found.
  The game sorts every casualty 30/35/35 killed/heavily/walking whatever the distance, and counts every casualty as lost to the unit.
* What a **single casualty does to a crew**: doctrine's answer (from the 2026-09-07 entry, FM 7-90 and Korean-war-era positions built to
  "continue to fight, even during intense enemy countermortar fire") is to man the weapon and cross-level, not to leave. The game's hold chance
  after a hit is the share of the crew left, so a crew of five leaves one time in five after a single casualty, and (since 2026-10-18) always
  once fewer than two are left.

## Blast overpressure alone (fragments ignored), 2026-10-22

* **Thresholds for people** (Wikipedia, Overpressure, citing a Toxicological Sciences article and a DTIC document; long-duration loads unless stated; the
  sources themselves were not read): window glass shatters and light injuries from debris at 1 psi (6.9 kPa); eardrum rupture in about 1 percent at 5 psi
  (34 kPa), 50 percent at 15 psi (103 kPa), 99 percent at 45 psi (310 kPa); the threshold for lung damage about 15 psi; 1 percent fatalities at 35-45 psi
  (240-310 kPa), 99 percent at 55-65 psi. For short, "instantaneous" peak pressure (the DTIC figures): severe injury at 70-100 psi, a 50:50 chance of
  surviving 500 psi; a standing man is blown away at about 10 ft/s by 25 psi. (Wikipedia, Effects of nuclear explosions: lung damage about 70 kPa, some
  eardrums rupturing around 22 kPa.) Short pulses are less injurious than long ones at the same peak pressure; a small round's pulse lasts a
  millisecond or two.
* **Distance, derived by me, not a source.** With the Kinney-Graham free-air formula (from memory, unverified), a ground burst counted as 1.8 times the
  charge (hemispherical reflection), and a filler of 0.7 kg TNT-equivalent (the M252's 0.7 kg of explosive; the 82 mm round's filler was not found, 0.4 to
  0.9 kg gives the same picture): 1 psi at about 15 m (0.4 kg: 12 m; 0.9 kg: 16 m); 2 psi at 8.5 m; 5 psi (eardrums 1 percent) at 5 m; 15 psi (lung
  threshold, eardrums 50 percent) at 3 m; 35 psi (1 percent fatal) at 2 m; 70 psi at 1.5 m. Peak overpressure at 26 m is about 0.5 psi.
  So on these figures **blast alone is not likely to do major harm beyond about 5 m, and nothing worse than light injuries beyond about 15 m;
  the 26 m casualty radius is fragments.** Confined spaces (a pit, a bunker, a building) raise the pressure a good deal (Weibull's formula on the same
  Wikipedia page), so a crew in a fighting position is closer to these radii than one in the open.

### Sanity check of the blast radius against real casualties (2026-10-22)

* **No dataset of people killed by mortar rounds, with their distances from the burst and cause of death, was reached** (cause-of-death series and
  autopsy studies are in journals and DTIC reports that the browser could not search for; Wikipedia has no such table).
* What the reachable sources say: "most casualties are caused by secondary injuries" (fragments), and fragments "affect a larger area than the primary
  blast area"; primary (overpressure) injuries are "especially likely when a person is close to an exploding munition, such as a land mine"; tertiary
  injuries are people thrown by the blast wind (Wikipedia, Blast injury); explosions in confined spaces or with structural collapse "usually produce more
  deaths and injuries" (same page); an offensive grenade's "concussion effect, rather than any expelled fragments, is the effective killer" in
  confined spaces such as buildings and fortifications (Wikipedia, Hand grenade). The M67 grenade's fatality radius (5 m) is several times what its 180 g of
  explosive can do by blast alone (about 1-2 m on the same formulas), which is fragments again.
* Incident with numbers but no distances: the first Markale market shelling, one 120 mm round into a crowded open-air market, 68 killed and 144 wounded
  (Wikipedia). With a filler of a few kilograms the blast-only fatal radius is about 4 m on the formulas above, so most of those deaths must have been
  fragments at greater distances (an inference; no autopsy breakdown was found).
* **Second formula as a check on the derived radii.** Sadovsky's empirical formula (from memory, unverified) gives, for the same 0.7 kg ground burst:
  1 psi at 19 m, 2 psi at 11 m, 5 psi (1 percent eardrum) at 6.3 m, 15 psi at 3.5 m, 35 psi (1 percent fatal) at 2.4 m; Kinney-Graham gave 14.5, 8.5, 5.0,
  2.9 and 2.0 m. So the two disagree by about 25 percent: **the eardrum radius is about 5-6 m, the lung-damage radius about 3-3.5 m, light injury about
  15-19 m.** For a 120 mm round (filler assumed 3 kg): eardrum about 10 m, lung about 6 m, 1 percent fatal about 4 m.
* Limits of "blast is unlikely to cause major harm beyond about 5 m": it is for a person standing in the open and for peak overpressure; it does not
  cover a person in a pit, bunker or building (higher pressure), the blast-wind throw (25 psi, about 2.5 m, is where a standing man is blown away at
  10 ft/s on the DTIC figure), or mild blast-induced brain injury, whose thresholds depend on more than peak pressure and were not found.

## Vegetation, soil and cover between a burst and people (2026-10-22)

* FM 7-90, B-4: soft ground (a foot of soft soil, mud or sand, or 3 feet of snow) can cut the effect of a surface-burst round by up to 80 percent; hard
  rocky soil raises it. **Dense woods make impact rounds burst in the trees (airbursts), which are dangerous to exposed troops below: wooden
  splinters add to the metal fragments and the wounds are often severe**; in extremely dense woods (triple canopy) most rounds burst high and
  have little effect at ground level. Trees are therefore not simply protection: overhead vegetation can raise the harm to people under it.
* FM 7-90, ch. 7: the German Infantry School's 1976 test (mannequins, fire at the intensity of Soviet doctrine): troops prone in the open, 100
  percent casualties; in open fighting positions without overhead cover, 30 percent; dug in with overhead cover, under 10 percent, mostly from
  direct hits. At Khe Sanh (February 1968) 350-500 82 mm rounds hit one rifle company's position in two hours with only moderate damage once
  fortified. 18 inches of earth stops fragments; three layers of sandbags and a steel plank stop a direct 82 mm hit.
* FM 7-90, ch. 7: a tall building's dead space shields a position from low-angle fire; mortars' steep fall makes that dead space small.
* **Not found**: any figure for how much vegetation standing between a burst and a person attenuates fragments (light brush is assumed negligible and
  trunks of 15-30 cm or more significant, from general knowledge, not a source).
* In the game: protection is by the terrain the person is **standing in** (`MORTAR_COVER_MULTIPLIER`: open 1.3, trees 0.5, building 0.3, with the
  ratio raised to the power distance/26 m beyond 26 m, so cover counts for more at range). Nothing between the burst and the person (a belt of trees, a
  wall) shields them, and trees are treated as protective even though FM 7-90 says tree bursts are dangerous to those below.

## Wounded, walking wounded, prisoners

* Walking wounded are the low-priority triage class: conscious, able to walk, and "may sometimes be called upon to assist ... with other tasks"
  (Wikipedia, Walking wounded). In the game they are casualties, lost to the unit (user ruling, 2026-10-18).
* Wounded left behind in a retreat are captured (user ruling, 2026-10-21); a person who counts in more than one way counts once, as the highest
  (user ruling, 2026-10-21).
* Real ratios of killed to wounded, and the share of the wounded who remain fit for duty, were not researched.

## Other sources already used (see the ledger)

* FM 7-8 and Wikipedia (Fire team, Platoon): squad and platoon dispersion and frontage. Wikipedia (AK-74, RPK): ammunition carried. Wikipedia
  (Hand grenade, Close-quarters battle, Fire and movement, Encirclement, Pocket, Morale, Combat effectiveness): close quarters, assault, cohesion.
  Wikipedia (Sympathetic detonation, Cooking off, Insensitive munition): stored-round cook-off (no rate for a mortar position found).
