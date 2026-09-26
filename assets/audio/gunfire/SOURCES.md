# Gunfire recording

`freesound_community-battle-war-zone-gun-fight-32155.mp3` was supplied by the user on
2026-09-25 from their Downloads folder, as a complete file: nothing was trimmed or
re-encoded. Its name (contributor handle `freesound_community`, ID `32155`) is in the
same style as the Pixabay files in `../rain` and `../wind`, but where it came from was
not checked and its license terms were not looked up.

40.2 s, 24 kHz stereo; measured with ffmpeg's `ebur128` filter: **-21.4 LUFS**
integrated, sample peak **-2.5 dBFS**. It is loud, continuous gunfire that starts at once
and dies away over its last two seconds, so a loop has a short lull at the wrap, which is
left as is.

The game plays it very quietly, as one looping copy that starts at a random point each
time it becomes audible: `scripts/gunfire_ambience.gd` (`FILE_LUFS` and `FILE_PEAK_DBFS`
are the two numbers above; re-measure them if the file is ever replaced).
