# Wind recordings

Both files came from Pixabay's sound-effects search for "wind":

  https://pixabay.com/sound-effects/search/wind/

The two pages (opened and confirmed by the developer, 2026-10-07):

  - soft wind (`storegraphic`, 318856): https://pixabay.com/sound-effects/nature-soft-wind-318856/
  - wind blowing (`soundreality`, 457954): https://pixabay.com/sound-effects/nature-wind-blowing-457954/

They were downloaded by the developer on 2026-09-24. The soft-wind file is used
**exactly as downloaded** (no editing, re-encoding or trimming). The blowing-wind file
was **rebuilt as a seamless loop** (see below).

| File | Used for | Length | Measured loudness* |
| --- | --- | --- | --- |
| `storegraphic-soft-wind-318856.mp3` | soft wind, 5-7 m/s | 22.1 s | -40.4 LUFS |
| `soundreality-wind-blowing-457954-seamless-loop.ogg` | wind blowing, 8+ m/s | 33.75 s | -30.2 LUFS |

The names carry the Pixabay contributor handle (`storegraphic`, `soundreality`) and
the sound's Pixabay ID (`318856`, `457954`). Use of the files is governed by
Pixabay's license terms as published by Pixabay (see
https://pixabay.com/service/license-summary/); this note records where they came
from and has not re-checked those terms.

\* Integrated loudness measured with ffmpeg's `ebur128` filter (the blowing file's
figure is the same before and after the rebuild). The game sets the wind's volume by target loudness
using these two numbers (`WindAmbience.SOFT_FILE_LUFS` / `BLOWING_FILE_LUFS`), so if
either file is ever replaced, re-measure it and update the constants.

## The blowing file: a seamless loop

The download (`soundreality-wind-blowing-457954.mp3`, 42.7 s) is a one-shot: it starts in
about 0.07 s of digital silence, swells over roughly 3 s, creeps up for a few seconds
more, and fades out at the end. Looped as it was, every 42 s the wind dropped to nothing
and swelled back, which the developer found distracting at 8 m/s, where the blowing
recording is quietest. (An earlier fix cut off the last second, 42.7 s -> 41.7 s, which
removed most of the fade-out but left the fade-in and swell.)

The committed file is rebuilt from that 41.75 s cut:

1. drop the first 6.0 s (the swell; the recording has settled by then);
2. crossfade the last 2.0 s of what remains onto its start with an equal-power curve
   (cos on the tail, sin on the head), so the wrap point is inside a steady stretch;
3. encode as Ogg Vorbis (libvorbis, quality 5): 33.75 s.

Checked with ffmpeg: the level of the last half second (-34.9 dB RMS) against the first
(-34.5 dB), and 20 ms either side of the wrap (-36.0 to -36.6 dB), so no step at the seam;
integrated loudness is unchanged at -30.2 LUFS. The source cut is in the git history
(`soundreality-wind-blowing-457954-minus-last-second.mp3`). Not listened to;
the numbers are the evidence.

How the game uses them: `scripts/wind_ambience.gd`.
