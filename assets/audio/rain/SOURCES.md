# Rain recordings

These came from the same site as the wind recordings (see `../wind/SOURCES.md`):
**Pixabay** sound effects, https://pixabay.com/sound-effects/ . They were downloaded
by the developer on 2026-09-24. The file names carry the contributor handle
(`freesound_community`, `eryliaa`, `boons_freak`) and the sound's Pixabay ID (`23254`, `337279`,
`188158`). The pages (opened and confirmed by the developer, 2026-10-07):

- gentle rain for relaxation and sleep (`eryliaa`, 337279): https://pixabay.com/sound-effects/nature-gentle-rain-for-relaxation-and-sleep-337279/
- drizzle 4perspectives (`freesound_community`, 23254): https://pixabay.com/sound-effects/nature-drizzle-4perspectives-23254/
- rain sound (`boons_freak`, 188158): https://pixabay.com/sound-effects/nature-rain-sound-188158/
- cozy midnight rain 04 (`dragon-studio`, 448568): https://pixabay.com/sound-effects/nature-cozy-midnight-rain-04-448568/
- snow rain (`freesound_community`, 35637): https://pixabay.com/sound-effects/nature-snow-rain-35637/

 Use of the files is governed by Pixabay's license
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
`dragon-studio`, ID `448568`) is in the same style as the Pixabay files above, and the developer
states (2026-10-07) that all of the project's sounds came from Pixabay, so it is recorded as one;
that was not checked independently (the developer later opened its page, listed above). Its license
terms are Pixabay's as published by Pixabay (not re-checked). Its level dips only about
2 dB at the loop point, so it loops without a noticeable seam. It is played at -50 LUFS, 6 dB
under the quietest of the other rain sounds (`RainAmbience.MIDNIGHT_FILE_LUFS` = -39.5 is its
own measured loudness, from `ebur128` as for the others). The class names it by the name
"midnight" in the code; the layer called "drizzle" there is the older `freesound_community`
clip, which plays for MODERATE rain.

**`freesound_community-snow_rain-35637.mp3`** was supplied by the user on 2026-09-26 from their Downloads
folder, for sleet. It is a complete 39.02-second file (mono, 48 kHz), so nothing was trimmed and it has no
`-first30s` in its name. Its name (contributor handle `freesound_community`, ID `35637`) is in the same style as
the Pixabay files above, and the developer states (2026-10-07) that all of the project's sounds came from
Pixabay, so it is recorded as one; the developer later opened its page (listed above). Its license terms
are Pixabay's as published by Pixabay (not re-checked).
Its Pixabay page, given by the developer on 2026-10-07 (copied with a `/zh` language segment, which is dropped
here): https://pixabay.com/sound-effects/nature-snow-rain-35637/ (category Nature).
Measured with `ebur128`: **-32.7 LUFS** integrated (`RainAmbience.SLEET_FILE_LUFS`), peak -1.4 dBFS. It is
steady throughout (about 1.5 dB from end to end, no fade in or out), so it loops without a seam. Sleet plays it
at the same target loudness per class as rain (-50, -44, -40, -34 LUFS from drizzle to heavy), so slow sleet is
barely there and it rises with more.

How the game uses them: `scripts/rain_ambience.gd`.
