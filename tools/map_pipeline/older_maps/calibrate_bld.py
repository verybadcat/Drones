"""Cross-check the frame offset with the old building blocks: shift the Overture footprints until they fall inside them."""
import json, math, sys
import numpy as np
from oldmaps import split_maps, facts

sys.stdout.reconfigure(encoding="utf8")
for mid, block in split_maps().items():
    if mid == "voznesensk":
        continue
    f = facts(block)
    m_lat = 110574.0
    m_lon = 111320.0 * math.cos(math.radians(f["lat"]))
    to = lambda lat, lon: ((lon - f["lon"]) * m_lon + f["vc"][0], -(lat - f["lat"]) * m_lat + f["vc"][1])
    d = json.load(open("old_%s_building.geojson" % mid, encoding="utf8"))["features"]
    pts = []
    for ft in d:
        g = ft["geometry"]
        ring = g["coordinates"][0] if g["type"] == "Polygon" else g["coordinates"][0][0]
        xy = [to(c[1], c[0]) for c in ring]
        pts.append((sum(p[0] for p in xy) / len(xy), sum(p[1] for p in xy) / len(xy)))
    P = np.array(pts)
    
    # old rects: stored as (x*PPM...) in the text as meters*? parse gave meters already (values like 695.0 before "* PIXELS_PER_METER")
    R = np.array(f["rects"])
    area = float((R[:, 2] * R[:, 3]).sum())

    def inside(dx, dy):
        Q = P - np.array([dx, dy])
        n = 0
        for x0, y0, w, h in R:
            n += int(((Q[:, 0] >= x0) & (Q[:, 0] <= x0 + w) & (Q[:, 1] >= y0) & (Q[:, 1] <= y0 + h)).sum())
        return n

    base = inside(0, 0)
    best = (base, 0, 0)
    for dx in range(-400, 401, 20):
        for dy in range(-400, 401, 20):
            n = inside(dx, dy)
            if n > best[0]:
                best = (n, dx, dy)
    for dx in range(best[1] - 20, best[1] + 21, 5):
        for dy in range(best[2] - 20, best[2] + 21, 5):
            n = inside(dx, dy)
            if n > best[0]:
                best = (n, dx, dy)
    print("%-12s Overture buildings %d, old blocks %d (%.1f ha): footprints inside the old blocks: %d at the assumed frame; best %d at an offset of (%d, %d) m" % (mid, len(P), len(R), area / 1e4, base, best[0], best[1], best[2]))
