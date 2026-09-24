# Wind recordings

Both files came from Pixabay's sound-effects search for "wind":

  https://pixabay.com/sound-effects/search/wind/

They were downloaded by the developer on 2026-09-24 and are used **exactly as
downloaded** (no editing, re-encoding or trimming), under their original file names.

| File | Used for | Length | Measured loudness* |
| --- | --- | --- | --- |
| `storegraphic-soft-wind-318856.mp3` | soft wind, 5-7 m/s | 22.1 s | -40.4 LUFS |
| `soundreality-wind-blowing-457954.mp3` | wind blowing, 8+ m/s | 42.7 s | -30.2 LUFS |

The names carry the Pixabay contributor handle (`storegraphic`, `soundreality`) and
the sound's Pixabay ID (`318856`, `457954`). Use of the files is governed by
Pixabay's license terms as published by Pixabay (see
https://pixabay.com/service/license-summary/); this note records where they came
from and has not re-checked those terms.

\* Integrated loudness measured with ffmpeg's `ebur128` filter. The game sets the
wind's volume by target loudness using these two numbers
(`WindAmbience.SOFT_FILE_LUFS` / `BLOWING_FILE_LUFS`), so if either file is ever
replaced, re-measure it and update the constants.

The blowing recording fades in over its first ~0.3 s and out over its last ~1.3 s,
so when it loops there is a short lull — acceptable for wind, and left as is.

How the game uses them: `scripts/wind_ambience.gd`.
