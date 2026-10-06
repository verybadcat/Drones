"""Fetch Esri z16 tiles for an old map's frame and draw new footprints (yellow) and the old blocks (red) on a crop."""
import json, math, os, sys, time, urllib.request
import numpy as np
from concurrent.futures import ThreadPoolExecutor
from PIL import Image, ImageDraw
from oldmaps import split_maps, facts

sys.stdout.reconfigure(encoding="utf8")
HERE = os.path.dirname(os.path.abspath(__file__))
OFFSET = {"pervomaiske": (-22.0, 20.0), "pishchane": (74.0, 25.0), "svystunivka": (0.0, 5.0)}
Z = 16
os.makedirs(os.path.join(HERE, "tiles_old"), exist_ok=True)


def tile_xy(lat, lon, z):
    n = 2 ** z
    return (lon + 180) / 360 * n, (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n


mid = sys.argv[1]
cx0, cx1, cy0, cy1 = map(float, sys.argv[2:6])
res = float(sys.argv[6])
out = sys.argv[7]
f = facts(split_maps()[mid])
m_lat = 110574.0
m_lon = 111320.0 * math.cos(math.radians(f["lat"]))
ox, oy = OFFSET[mid]


def frame_to_ll(x, y):
    lon = f["lon"] + (x - f["vc"][0] - ox) / m_lon
    lat = f["lat"] - (y - f["vc"][1] - oy) / m_lat
    return lat, lon


need = set()
for x in np.arange(cx0 - 100, cx1 + 100, 80):
    for y in np.arange(cy0 - 100, cy1 + 100, 80):
        tx, ty = tile_xy(*frame_to_ll(x, y), Z)
        need.add((int(tx), int(ty)))


def get(t):
    p = os.path.join(HERE, "tiles_old", "%d_%d_%d.jpg" % (Z, t[0], t[1]))
    if os.path.exists(p) and os.path.getsize(p) > 500:
        return
    url = "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/%d/%d/%d" % (Z, t[1], t[0])
    for a in range(4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "drones-game-research/1.0"})
            open(p, "wb").write(urllib.request.urlopen(req, timeout=40).read())
            return
        except Exception:
            time.sleep(2)


with ThreadPoolExecutor(6) as ex:
    list(ex.map(get, sorted(need)))
cache = {}


def tile(x, y):
    k = (x, y)
    if k not in cache:
        p = os.path.join(HERE, "tiles_old", "%d_%d_%d.jpg" % (Z, x, y))
        cache[k] = np.asarray(Image.open(p).convert("RGB")) if os.path.exists(p) else None
    return cache[k]


W = int((cx1 - cx0) / res)
H = int((cy1 - cy0) / res)
arr = np.zeros((H, W, 3), np.uint8)
for j in range(H):
    y = cy0 + (j + 0.5) * res
    for i in range(W):
        x = cx0 + (i + 0.5) * res
        tx, ty = tile_xy(*frame_to_ll(x, y), Z)
        t = tile(int(tx), int(ty))
        if t is not None:
            arr[j, i] = t[min(int((ty - int(ty)) * 256), 255), min(int((tx - int(tx)) * 256), 255)]
im = Image.fromarray(arr)
dr = ImageDraw.Draw(im)
for rg in json.load(open(os.path.join(HERE, "%s_buildings.json" % mid)))["buildings"]:
    pts = [((rg[k] - cx0) / res, (rg[k + 1] - cy0) / res) for k in range(0, len(rg), 2)]
    if all(-5 <= p[0] <= W + 5 and -5 <= p[1] <= H + 5 for p in pts[:1]):
        dr.line(pts + [pts[0]], fill=(255, 255, 0), width=1)
for r in f["rects"]:
    dr.rectangle([(r[0] - cx0) / res, (r[1] - cy0) / res, (r[0] + r[2] - cx0) / res, (r[1] + r[3] - cy0) / res], outline=(255, 60, 60))
im.save(os.path.join(HERE, out))
print("saved", out, im.size)
