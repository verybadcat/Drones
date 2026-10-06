"""Rebuild the building layer of the three older maps with the Voznesensk process, in their existing frames."""
import json, math, os, sys
import numpy as np
from shapely.geometry import Polygon, box
from shapely.ops import unary_union
from oldmaps import split_maps, facts

sys.stdout.reconfigure(encoding="utf8")
HERE = os.path.dirname(os.path.abspath(__file__))
# frame offsets measured against the old maps' own roads and building blocks (see the design doc entry)
OFFSET = {"pervomaiske": (-22.0, 20.0), "pishchane": (74.0, 25.0), "svystunivka": (0.0, 5.0)}
BUF, CELL, MINAREA, COV = 14, 32, 800, 0.4


def blocks_from(core):
    u = unary_union([p.buffer(BUF) for p in core])
    polys = list(u.geoms) if u.geom_type == "MultiPolygon" else [u]
    rects = []
    for pg in polys:
        if pg.area < MINAREA:
            continue
        minx, miny, maxx, maxy = pg.bounds
        nx = int(math.ceil((maxx - minx) / CELL))
        ny = int(math.ceil((maxy - miny) / CELL))
        grid = np.zeros((ny, nx), bool)
        for j in range(ny):
            for i in range(nx):
                c = box(minx + i * CELL, miny + j * CELL, minx + (i + 1) * CELL, miny + (j + 1) * CELL)
                if pg.intersection(c).area >= COV * CELL * CELL:
                    grid[j, i] = True
        runs = {}
        for j in range(ny):
            i = 0
            while i < nx:
                if grid[j, i]:
                    k = i
                    while k < nx and grid[j, k]:
                        k += 1
                    runs.setdefault((i, k), []).append(j)
                    i = k
                else:
                    i += 1
        for (i0, i1), js in runs.items():
            js.sort()
            start = js[0]
            prev = js[0]
            for j in js[1:] + [None]:
                if j is None or j != prev + 1:
                    rects.append((minx + i0 * CELL, miny + start * CELL, (i1 - i0) * CELL, (prev - start + 1) * CELL))
                    if j is not None:
                        start = j
                if j is not None:
                    prev = j
    return rects


for mid, block in split_maps().items():
    if mid == "voznesensk":
        continue
    f = facts(block)
    m_lat = 110574.0
    m_lon = 111320.0 * math.cos(math.radians(f["lat"]))
    ox, oy = OFFSET[mid]
    to = lambda lat, lon: ((lon - f["lon"]) * m_lon + f["vc"][0] + ox, -(lat - f["lat"]) * m_lat + f["vc"][1] + oy)
    d = json.load(open(os.path.join(HERE, "old_%s_building.geojson" % mid), encoding="utf8"))["features"]
    polys = []
    for ft in d:
        g = ft["geometry"]
        rings = [g["coordinates"]] if g["type"] == "Polygon" else g["coordinates"]
        for rg in rings:
            pg = Polygon([to(c[1], c[0]) for c in rg[0]])
            if not pg.is_valid:
                pg = pg.buffer(0)
            if pg.is_empty:
                continue
            c = pg.centroid
            if not (-1520 <= c.x <= 5020 and -20 <= c.y <= 3520):
                continue
            if pg.area < 14:
                continue
            polys.append(pg.simplify(0.7))
    polys = [p for p in polys if p.geom_type == "Polygon"]
    rects = blocks_from(polys)
    covered = unary_union([box(r[0], r[1], r[0] + r[2], r[1] + r[3]) for r in rects]) if rects else None
    cov = sum(p.intersection(covered).area for p in polys) / max(sum(p.area for p in polys), 1) if rects else 0
    print("%-12s %4d footprints  -> %3d cover blocks (%.1f ha; old: %d blocks %.1f ha); blocks cover %.0f%% of footprint area" % (
        mid, len(polys), len(rects), sum(r[2] * r[3] for r in rects) / 1e4, len(f["rects"]), sum(r[2] * r[3] for r in f["rects"]) / 1e4, cov * 100))
    os.makedirs(r"C:\Code\Drones\assets\maps", exist_ok=True)
    json.dump({"coordinate_frame": "meters in the map frame (x east, y south; north is up)", "buildings": [[round(c, 1) for xy in p.exterior.coords[:-1] for c in xy] for p in polys]},
              open(os.path.join(HERE, "%s_buildings.json" % mid), "w"), separators=(",", ":"))
    json.dump([[round(v) for v in r] for r in rects], open(os.path.join(HERE, "%s_blocks.json" % mid), "w"))
