"""Fit the frame offset of each old map: where do the old road waypoints sit relative to Overture's roads?"""
import json, math, sys
import numpy as np
from shapely.geometry import LineString, Point, Polygon
from shapely.strtree import STRtree
from oldmaps import split_maps, facts

sys.stdout.reconfigure(encoding="utf8")


def lines(g):
    if g["type"] == "LineString":
        yield g["coordinates"]
    elif g["type"] == "MultiLineString":
        for c in g["coordinates"]:
            yield c


def frame_fn(lat0, lon0, vc):
    m_lat = 110574.0
    m_lon = 111320.0 * math.cos(math.radians(lat0))
    return lambda lat, lon: ((lon - lon0) * m_lon + vc[0], -(lat - lat0) * m_lat + vc[1])


for mid, block in split_maps().items():
    if mid == "voznesensk":
        continue
    f = facts(block)
    to_frame = frame_fn(f["lat"], f["lon"], f["vc"])
    segs = json.load(open("old_%s_segment.geojson" % mid, encoding="utf8"))["features"]
    roads = []
    for ft in segs:
        if ft["properties"].get("class") in ("motorway", "trunk", "primary", "secondary", "tertiary", "unclassified", "residential", "service", "track"):
            for l in lines(ft["geometry"]):
                roads.append(LineString([to_frame(c[1], c[0]) for c in l]))
    tree = STRtree(roads)
    # densify the old road polyline every 25 m
    old = LineString(f["road"])
    pts = [old.interpolate(d) for d in np.arange(0, old.length, 25.0)]
    P = np.array([[p.x, p.y] for p in pts])

    def score(dx, dy):
        tot = 0.0
        for x, y in P:
            q = Point(x - dx, y - dy)  # moving the old road by (dx,dy) == moving the new data by (-dx,-dy)
            idx = tree.query(q.buffer(120))
            d = min((roads[i].distance(q) for i in idx), default=120.0)
            tot += min(d, 120.0)
        return tot / len(P)

    base = score(0, 0)
    best = (base, 0, 0)
    for dx in range(-150, 151, 15):
        for dy in range(-150, 151, 15):
            sc = score(dx, dy)
            if sc < best[0]:
                best = (sc, dx, dy)
    # refine
    c = best
    for dx in range(c[1] - 14, c[1] + 15, 3):
        for dy in range(c[2] - 14, c[2] + 15, 3):
            sc = score(dx, dy)
            if sc < best[0]:
                best = (sc, dx, dy)
    print("%-12s road points %d  mean distance to the nearest real road: at the assumed frame %.1f m; best %.1f m at an offset of (%d, %d) m" % (mid, len(P), base, best[0], best[1], best[2]))
