# Mortar shot recordings

All six clips (`mortar_shot_1.wav` to `mortar_shot_6.wav`) were cut from **one** recording:

- **Title:** Mortar Shell 2
- **Contributor:** TommyLynn (Pixabay)
- **Site:** Pixabay sound effects, https://pixabay.com/sound-effects/ (found through
  https://pixabay.com/sound-effects/search/mortar/)
- **Pixabay ID:** 371034 (carried in the downloaded file's name)
- **Downloaded file:** `tommylynn-mortar-shell-2-371034.mp3`, downloaded by the developer on
  2026-09-23. A complete MP3: 10.39 s, 256 kbps, 48 kHz stereo, no embedded tags or links.
  It is **not** in the project (it stays in the developer's Downloads folder).

The title and contributor are as Pixabay shows them (the developer's screenshot of the search
results, 2026-10-07; category "Film & special effects", 0:10 long).

- **Page:** https://pixabay.com/sound-effects/film-special-effects-mortar-shell-2-371034/
  (given by the developer, 2026-10-07)

Use of the recording is governed by Pixabay's license terms as published by
Pixabay (see https://pixabay.com/service/license-summary/); this note records where it came
from and has not re-checked those terms.

## What was done to it (2026-09-23)

The recording holds six mortar shots in a row. It was **split at genuine silent points** into six
separate clips, each **made 12 dB quieter** (the same for all, so none clips and every one is well
below the loudest original), and saved as 16-bit 48 kHz stereo WAV. Nothing else was changed (no
filtering, no effects). Together the clips are 10.38 s, i.e. the whole recording.

| File | Length |
| --- | --- |
| `mortar_shot_1.wav` | 0.82 s |
| `mortar_shot_2.wav` | 0.96 s |
| `mortar_shot_3.wav` | 0.99 s |
| `mortar_shot_4.wav` | 2.97 s |
| `mortar_shot_5.wav` | 1.92 s |
| `mortar_shot_6.wav` | 2.72 s |

How the game uses them: `BattleManager._launch_mortar_shot` plays a random one, through a pool of
12 players so overlapping rounds do not cut each other off, for both sides.
