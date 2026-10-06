"""Build each map's mortar-exclusion region: the ground within RADIUS_M of a populated place, where the Ukrainian mortar will not go.

A populated place is a cluster of at least MIN_BUILDINGS footprints (footprints closer than 2 * LINK_M run together). The region is rasterised to
CELL_M cells and written as merged rectangles (meters, map frame) to assets/maps/<id>_mortar_exclusion.json.

Run from the repo root:  python tools/map_pipeline/mortar_exclusion/build.py [map_id ...]
"""
import json, os, sys
import numpy as np
import shapely
from shapely.geometry import Polygon
from shapely.ops import unary_union

RADIUS_M = 200.0
LINK_M = 60.0
MIN_BUILDINGS = 5
CELL_M = 10.0
MAPS = {  # x from the west edge of the west flank to the east edge, y from the north edge to the south edge
    "pervomaiske": (-1500.0, 5000.0, 0.0, 3500.0),
    "pishchane": (-1500.0, 5000.0, 0.0, 3500.0),
    "svystunivka": (-1500.0, 5000.0, 0.0, 3500.0),
    "voznesensk": (-1500.0, 5000.0, 0.0, 2200.0),
}


def build(map_id, bounds, root):
    x0, x1, y0, y1 = bounds
    data = json.load(open(os.path.join(root, "assets", "maps", "%s_buildings.json" % map_id)))["buildings"]
    polys = []
    for r in data:
        p = Polygon([(r[i], r[i + 1]) for i in range(0, len(r), 2)])
        polys.append(p if p.is_valid else p.buffer(0))
    linked = unary_union([p.buffer(LINK_M) for p in polys])
    clusters = list(linked.geoms) if linked.geom_type == "MultiPolygon" else [linked]
    keep = []
    for c in clusters:
        members = [p for p in polys if p.centroid.within(c)]
        if len(members) >= MIN_BUILDINGS:
            keep.extend(members)
    region = unary_union([p.buffer(RADIUS_M, resolution=8) for p in keep])
    nx = int(round((x1 - x0) / CELL_M))
    ny = int(round((y1 - y0) / CELL_M))
    xs = x0 + (np.arange(nx) + 0.5) * CELL_M
    ys = y0 + (np.arange(ny) + 0.5) * CELL_M
    gx, gy = np.meshgrid(xs, ys)
    grid = shapely.contains_xy(region, gx.ravel(), gy.ravel()).reshape(ny, nx)
    # merge: horizontal runs per row, then identical runs stacked vertically
    open_runs = {}
    rects = []
    for j in range(ny + 1):
        row_runs = set()
        if j < ny:
            i = 0
            while i < nx:
                if grid[j, i]:
                    k = i
                    while k < nx and grid[j, k]:
                        k += 1
                    row_runs.add((i, k))
                    i = k
                else:
                    i += 1
        for run in list(open_runs):
            if run not in row_runs:
                start = open_runs.pop(run)
                rects.append((x0 + run[0] * CELL_M, y0 + start * CELL_M, (run[1] - run[0]) * CELL_M, (j - start) * CELL_M))
        for run in row_runs:
            open_runs.setdefault(run, j)
    out = {
        "coordinate_frame": "meters in the map frame (x east, y south; north is up)",
        "rule": "within %d m of a cluster of at least %d building footprints (footprints within %d m of each other run together)" % (RADIUS_M, MIN_BUILDINGS, 2 * LINK_M),
        "cell_m": CELL_M,
        "rects": [[round(v, 1) for v in r] for r in rects],
    }
    path = os.path.join(root, "assets", "maps", "%s_mortar_exclusion.json" % map_id)
    json.dump(out, open(path, "w"), separators=(",", ":"))
    print("%-12s %5d footprints, %4d in %3d populated clusters -> %5d rects, %.0f ha barred (%.0f%% of the map)" % (
        map_id, len(polys), len(keep), sum(1 for c in clusters if len([p for p in polys if p.centroid.within(c)]) >= MIN_BUILDINGS),
        len(rects), grid.sum() * CELL_M * CELL_M / 1e4, 100.0 * grid.sum() / grid.size))
    return grid, bounds


if __name__ == "__main__":
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
    for mid in (sys.argv[1:] or MAPS):
        build(mid, MAPS[mid], root)
