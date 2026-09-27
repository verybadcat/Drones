# Rain recordings

These came from the same site as the wind recordings (see `../wind/SOURCES.md`):
**Pixabay** sound effects, https://pixabay.com/sound-effects/ . They were downloaded
by the developer on 2026-09-24. The exact Pixabay page addresses were not recorded;
the file names carry the contributor handle (`freesound_community`, `eryliaa`,
`boons_freak`) and the sound's Pixabay ID (`23254`, `337279`, `188158`), which is
enough to find each one again. Use of the files is governed by Pixabay's license
terms as published by Pixabay (see https://pixabay.com/service/license-summary/); this
note records where they came from and has not re-checked those terms.

Only the **first 30 seconds** of each is in the project (trimmed from the downloads
with ffmpeg stream copy — the audio itself is not re-encoded — before being added;
the rest of each file is not committed). Each 30-second clip simply loops in the game.

| File | Used for | Length | Measured loudness* |
| --- | --- | --- | --- |
| `eryliaa-gentle-rain-for-relaxation-and-sleep-337279-first30s.mp3` | light rain (0.5 to 2.5 mm/h) | 30 s | -36.7 LUFS |
| `freesound_community-drizzle-4perspectives-23254-first30s.mp3` | moderate rain (2.5 to 7.6 mm/h) | 30 s | -37.3 LUFS |
| `boons_freak-rain-sound-188158-first30s.mp3` | heavy rain (above 7.6 mm/h) | 30 s | -21.4 LUFS |
| `dragon-studio-cozy-midnight-rain-04-448568.mp3` | drizzle (up to 0.5 mm/h) | 30 s | -39.5 LUFS |

\* Integrated loudness of the 30-second clip, measured with ffmpeg's `ebur128`
filter. The game sets the rain's volume by target loudness using these three numbers
(`RainAmbience.GENTLE_FILE_LUFS` / `DRIZZLE_FILE_LUFS` / `HEAVY_FILE_LUFS`), so if a
clip is ever replaced, re-measure it and update the constants.

The drizzle and "rain sound" clips fade in over their first half-second, so when they
loop there is a brief lull — acceptable for rain, and left as is.

**`dragon-studio-cozy-midnight-rain-04-448568.mp3`** was supplied by the user on 2026-09-25
from their Downloads folder, for the drizzle class. It is a complete 30.02-second file, so
nothing was trimmed and it has no `-first30s` in its name. Its name (contributor handle
`dragon-studio`, ID `448568`) is in the same style as the Pixabay files above, but where it
came from was not checked and its license terms were not looked up. Its level dips only about
2 dB at the loop point, so it loops without a noticeable seam. It is played at -50 LUFS, 6 dB
under the quietest of the other rain sounds (`RainAmbience.MIDNIGHT_FILE_LUFS` = -39.5 is its
own measured loudness, from `ebur128` as for the others). The class names it by the name
"midnight" in the code; the layer called "drizzle" there is the older `freesound_community`
clip, which plays for MODERATE rain.

**`freesound_community-snow_rain-35637.mp3`** was supplied by the user on 2026-09-26 from their Downloads
folder, for sleet. It is a complete 39.02-second file (mono, 48 kHz), so nothing was trimmed and it has no
`-first30s` in its name. Its name (contributor handle `freesound_community`, ID `35637`) is in the same style as
the Pixabay files above, but where it came from was not checked and its license terms were not looked up.
Measured with `ebur128`: **-32.7 LUFS** integrated (`RainAmbience.SLEET_FILE_LUFS`), peak -1.4 dBFS. It is
steady throughout (about 1.5 dB from end to end, no fade in or out), so it loops without a seam. Sleet plays it
at the same target loudness per class as rain (-50, -44, -40, -34 LUFS from drizzle to heavy), so slow sleet is
barely there and it rises with more.

How the game uses them: `scripts/rain_ambience.gd`.
