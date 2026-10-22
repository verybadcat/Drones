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

What was NOT found, and a calculation worth knowing (mine, not a source):

* **How the chance of a casualty falls away beyond the 50 percent radius.** The game uses 50 percent at 26 m, halving every 26 m to 52 m, then every
  13 m (`CombatResolver.blast_casualty_chance`, per exposed standing person). Three shapes through the same 26 m point, per person:

  | distance | the game | fragment density 1/r² | Gaussian (textbook "Carleton" damage function, from memory, not verified) |
  |---|---|---|---|
  | 15 m | 67% | 87% | 79% |
  | 26 m | 50% | 50% | 50% |
  | 40 m | 34% | 25% | 19% |
  | 50 m | 26% | 17% | 8% |
  | 65 m | 12% | 10% | 1% |
  | 80 m | 6% | 7% | 0.1% |
  | 100 m | 2% | 5% | ~0 |

  A crew of five standing, chance of at least one casualty at 50 m: game 78%, 1/r² 61%, Gaussian 33%. So the game's casualty curve is generous
  between about 35 and 70 m compared with either alternative. Which shape is right for a mortar round was not established.
* **Severity by distance** (killed / seriously wounded / lightly wounded, and the share of the lightly wounded who stay at their post) was not found.
  The game sorts every casualty 30/35/35 killed/heavily/walking whatever the distance, and counts every casualty as lost to the unit.
* What a **single casualty does to a crew**: doctrine's answer (from the 2026-09-07 entry, FM 7-90 and Korean-war-era positions built to
  "continue to fight, even during intense enemy countermortar fire") is to man the weapon and cross-level, not to leave. The game's hold chance
  after a hit is the share of the crew left, so a crew of five leaves one time in five after a single casualty, and (since 2026-10-18) always
  once fewer than two are left.

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
