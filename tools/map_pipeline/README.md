# Map-building pipeline (as used for the Voznesensk map, October 2026)

Scratch scripts, kept so the next real-data map does not start from nothing. They were written to run from a
working folder (`%TEMP%\vozn` on the machine that built the map) next to the downloaded data, and some paths are
hard-coded to `C:\Code\Drones`; treat them as a recipe, not a tool. Python needs `numpy scipy shapely pyproj pillow
overturemaps pyarrow` (`pip install`). Nothing here is needed to run the game.

Order, with what each step produced:

1. `frame.py` - the map frame: real lat/lon <-> game meters, anchored on the defended point, turned so the real attack
   direction points to screen east. Change `LAT0/LON0/BEARING_X` for another place.
2. `fetch_dem.py` - SRTM 30 m elevation on a 100 m grid (OpenTopoData, 100 points a request, one request a second).
3. `fit_hills.py` - greedy least-squares fit of the game's Gaussian-hill elevation model (28 hills here, about 5.7 m RMS).
4. Buildings: **do not trust OpenStreetMap for rural Ukraine** (330 buildings tagged where the satellite shows
   thousands). `python -m overturemaps.cli download --bbox=W,S,E,N -f geojson --type=building -o x.geojson` gives
   Overture's footprints (Microsoft ML Buildings plus OSM); `--type=segment|water|land_cover|land_use` give roads,
   water and land cover. `build_buildings.py` makes the footprints (drawn as themselves, a resource file under
   `assets/maps/`); `block_params.py`/`make_blocks_final.py` merge them into the coarse cover rectangles the game
   logic uses.
5. `fetch_tiles.py` + `mosaic.py` + `overlay.py` - Esri World Imagery tiles, a mosaic in the map frame, and an overlay of
   the data on it. THIS IS THE VERIFICATION STEP: look at the overlay before trusting any layer.
6. `pack_trees.py` - Overture forest land cover packed into circles (its shrub/grass classes are far too coarse; a
   naive imagery tree classifier flagged 60% of the frame as trees and was dropped).
7. `gen_map.py` + `map_template.txt` + `map_doc.txt` - write the map entry text; `reinsert.py` replaces it in
   `scripts/game_config.gd`.
8. `siting.gd` (default unit positions with the game's own line-of-sight model), `render_map.gd` (renders the real
   `draw_terrain` layer to a PNG, needs `--rendering-driver opengl3`, not headless), `bench_maps.gd` (simulated battles
   per map: ms/tick and how much units hug the edges).

Things learned: the public Overpass servers time out or return an HTML error page (retry across mirrors, or use
Overture); DuckDuckGo puts a captcha in front of scripted searches; the game's river mechanic (one crossing) failed
for a big diagonal river (units crossed it anyway, resupply runs stuck at the bridge), so the Voznesensk map is cut
short just north of the river instead.

## Redoing an existing map's buildings (done for Pervomaiske, Pishchane and Svystunivka, October 2026)

`older_maps/`: `oldmaps.py` (reads a map's anchor, road and blocks out of game_config.gd), `fetch_old.py` (Overture buildings
and roads for the map's frame), `calibrate.py` / `calibrate_bld.py` (find the small offset between the real data and the map's
own frame by matching the old road and the old blocks), `build_old_maps.py` (footprints + cover blocks), `apply_old_maps.py`
(writes them into game_config.gd and copies the footprint files), `verify_old.py` (footprints and old blocks drawn on
Esri imagery: look at it).
