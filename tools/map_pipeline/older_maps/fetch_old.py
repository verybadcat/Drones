import math, subprocess, os, sys
from oldmaps import split_maps, facts

HERE = os.path.dirname(os.path.abspath(__file__))
for mid, block in split_maps().items():
    if mid == "voznesensk":
        continue
    f = facts(block)
    lat0, lon0 = f["lat"], f["lon"]
    vx, vy = f["vc"]
    m_lat = 110574.0
    m_lon = 111320.0 * math.cos(math.radians(lat0))
    margin = 600.0
    west = lon0 + (-1500 - margin - vx) / m_lon
    east = lon0 + (5000 + margin - vx) / m_lon
    north = lat0 - (0 - margin - vy) / m_lat
    south = lat0 - (3500 + margin - vy) / m_lat
    bbox = "%.5f,%.5f,%.5f,%.5f" % (west, south, east, north)
    print(mid, "bbox", bbox)
    for t in ("building", "segment"):
        out = os.path.join(HERE, "old_%s_%s.geojson" % (mid, t))
        if os.path.exists(out) and os.path.getsize(out) > 1000:
            print("  cached", out)
            continue
        r = subprocess.run([sys.executable, "-m", "overturemaps.cli", "download", "--bbox=" + bbox, "-f", "geojson", "--type=" + t, "-o", out],
                           capture_output=True, text=True, timeout=900)
        print("  ", t, os.path.getsize(out) if os.path.exists(out) else "FAILED", r.stderr[-120:].replace("\n", " "))
