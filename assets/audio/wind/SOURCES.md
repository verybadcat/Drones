# Wind recordings

Both files came from Pixabay's sound-effects search for "wind":

  https://pixabay.com/sound-effects/search/wind/

They were downloaded by the developer on 2026-09-24. The soft-wind file is used
**exactly as downloaded** (no editing, re-encoding or trimming). The blowing-wind file
has its **last second cut off** (see below); nothing else was changed and it was not
re-encoded (cut with ffmpeg stream copy).

| File | Used for | Length | Measured loudness* |
| --- | --- | --- | --- |
| `storegraphic-soft-wind-318856.mp3` | soft wind, 5-7 m/s | 22.1 s | -40.4 LUFS |
| `soundreality-wind-blowing-457954-minus-last-second.mp3` | wind blowing, 8+ m/s | 41.7 s | -30.2 LUFS |

The names carry the Pixabay contributor handle (`storegraphic`, `soundreality`) and
the sound's Pixabay ID (`318856`, `457954`). Use of the files is governed by
Pixabay's license terms as published by Pixabay (see
https://pixabay.com/service/license-summary/); this note records where they came
from and has not re-checked those terms.

\* Integrated loudness measured with ffmpeg's `ebur128` filter (the blowing file's
figure is unchanged by the trim). The game sets the wind's volume by target loudness
using these two numbers (`WindAmbience.SOFT_FILE_LUFS` / `BLOWING_FILE_LUFS`), so if
either file is ever replaced, re-measure it and update the constants.

## The blowing file's last second

The download (`soundreality-wind-blowing-457954.mp3`, 42.7 s) fades out to silence over
its last ~1.3 s, which was annoying to hear at 9 m/s on every loop. On the developer's
request the last second was cut off (42.7 s -> 41.7 s, from the original download, no
re-encoding), which removes most of the fade. What is left of it is a dip of about 4 dB
over the final quarter-second; the file also still fades in over its first
quarter-second. If the dip is still noticeable, cut another ~0.3 s from the end
(`ffmpeg -i <original download> -t 41.4 -c copy ...`).

How the game uses them: `scripts/wind_ambience.gd`.
