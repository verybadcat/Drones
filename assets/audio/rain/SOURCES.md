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
| `eryliaa-gentle-rain-for-relaxation-and-sleep-337279-first30s.mp3` | light and light-moderate rain | 30 s | -36.7 LUFS |
| `freesound_community-drizzle-4perspectives-23254-first30s.mp3` | moderate rain | 30 s | -37.3 LUFS |
| `boons_freak-rain-sound-188158-first30s.mp3` | heavy rain (above moderate) | 30 s | -21.4 LUFS |

\* Integrated loudness of the 30-second clip, measured with ffmpeg's `ebur128`
filter. The game sets the rain's volume by target loudness using these three numbers
(`RainAmbience.GENTLE_FILE_LUFS` / `DRIZZLE_FILE_LUFS` / `HEAVY_FILE_LUFS`), so if a
clip is ever replaced, re-measure it and update the constants.

The drizzle and "rain sound" clips fade in over their first half-second, so when they
loop there is a brief lull — acceptable for rain, and left as is.

How the game uses them: `scripts/rain_ambience.gd`.
