import json, math, random, sys, os
import numpy as np
from shapely.geometry import LineString

sys.stdout.reconfigure(encoding="utf8")
rnd = random.Random(20260607)
HERE = os.path.dirname(os.path.abspath(__file__))


def vec(x, y):
    return "Vector2(%.1f, %.1f)" % (x, y)


def harmonics(amp_lo=0.05, amp_hi=0.13):
    f = rnd.sample([2, 3, 4], 2)
    return [
        {"frequency": f[0], "amplitude": round(rnd.uniform(amp_lo, amp_hi), 2), "phase": round(rnd.uniform(0, 6.28), 1)},
        {"frequency": f[1], "amplitude": round(rnd.uniform(amp_lo * 0.6, amp_hi * 0.8), 2), "phase": round(rnd.uniform(0, 6.28), 1)},
    ]


def harm_text(hs, indent="\t\t\t"):
    return "[\n" + "".join('%s{"frequency": %d, "amplitude": %.2f, "phase": %.1f},\n' % (indent, h["frequency"], h["amplitude"], h["phase"]) for h in hs) + indent[:-1] + "]"


# ---- hills
hf = json.load(open(os.path.join(HERE, "hills_fit.json")))
hills = sorted(hf["hills"], key=lambda h: math.hypot(h["cx"] - 1500, h["cy"] - 1750))
hills_txt = "".join(
    '\t\t{"center_m": %s, "radius_m": %.1f, "height_m": %.1f, "warp_harmonics": %s},\n' % (vec(h["cx"], h["cy"]), h["r"], h["h"], harm_text(harmonics()))
    for h in hills)

# ---- building logic rects and footprints resource
fp = json.load(open(os.path.join(HERE, "footprints.json")))
blocks = json.load(open(os.path.join(HERE, "blocks_final.json")))
river = json.load(open(os.path.join(HERE, "river_path.json")))
_rx = [p[0] for p in river]
_ry = [p[1] for p in river]


def south_of_river(x, y):
    return y > 2200.0 - 5.0   # below the (shortened) map: the ground south of the cut is left out


_nb = len(blocks)
blocks = [b for b in blocks if not south_of_river(b[0] + b[2] / 2.0, b[1] + b[3] / 2.0)]
print("blocks south of the river dropped:", _nb - len(blocks))
zones_txt = "".join(
    '\t\t{"rect": Rect2(%.0f * PIXELS_PER_METER, %.0f * PIXELS_PER_METER, %.0f * PIXELS_PER_METER, %.0f * PIXELS_PER_METER), "type": TerrainType.BUILDING},\n' % tuple(b)
    for b in blocks)
os.makedirs(r"C:\Code\Drones\assets\maps", exist_ok=True)
fp = [b for b in fp if min(b[1::2]) <= 2260.0]   # the footprints that reach the (shortened) map
print("footprints kept:", len(fp))
json.dump({"coordinate_frame": "meters in the map frame (x east on screen, y south on screen)", "buildings": fp},
          open(r"C:\Code\Drones\assets\maps\voznesensk_buildings.json", "w"), separators=(",", ":"))

# ---- trees
circ = json.load(open(os.path.join(HERE, "tree_circles_clean.json")))
_nc = len(circ)
circ = [c for c in circ if not south_of_river(c[0], c[1])]
print("tree patches south of the river dropped:", _nc - len(circ))
river_txt = "".join("\t\t\tVector2(%d, %d),\n" % (p[0], p[1]) for p in river)
trees_txt = "".join('\t\t{"center_m": %s, "radius_m": %.1f, "warp_harmonics": %s}, # wooded block / thicket\n' % (vec(c[0], c[1]), c[2], harm_text(harmonics(0.08, 0.16))) for c in circ)

# ---- road
h24 = json.load(open(os.path.join(HERE, "h24.json")))
xs = [p[0] for p in h24]
ys = [p[1] for p in h24]
line = LineString([(x, y) for x, y in zip(xs, ys) if 700 <= x <= 4900])
pts = list(line.simplify(18.0).coords)
if pts[0][0] < pts[-1][0]:
    pts = pts[::-1]
pts[0] = (4900.0, float(np.interp(4900, xs, ys)))
road_txt = "".join("\t\tVector2(%.0f, %.0f),\n" % p for p in pts)
road0 = pts[0][1]
print("road waypoints:", len(pts), "first y %.0f last (%.0f,%.0f)" % (road0, pts[-1][0], pts[-1][1]))

siting_path = os.path.join(HERE, "siting.json")
siting = json.load(open(siting_path)) if os.path.exists(siting_path) else {"squads": [[1500, 1700], [1480, 1600], [1560, 1650]], "mortar": [900, 1500], "spotter": [1300, 1500]}
sq_txt = "".join("\t\t\tVector2(%.0f, %.0f) * PIXELS_PER_METER,\n" % tuple(p) for p in siting["squads"])

doc = open(os.path.join(HERE, "map_doc.txt"), encoding="utf8").read()
body = open(os.path.join(HERE, "map_template.txt"), encoding="utf8").read()
txt = doc + body.replace("@@BASELINE@@", "%.1f" % hf["baseline"]) \
    .replace("@@HILLS@@", hills_txt).replace("@@ZONES@@", zones_txt).replace("@@TREES@@", trees_txt) \
    .replace("@@ROAD@@", road_txt).replace("@@SQUADS@@", sq_txt) \
    .replace("@@MORTAR@@", vec(*siting["mortar"])).replace("@@SPOTTER@@", vec(*siting["spotter"])) \
    .replace("@@MORTAR_MIN_Y@@", "%.1f" % (road0 - 1200)).replace("@@MORTAR_MAX_Y@@", "%.1f" % (road0 + 100))
open(os.path.join(HERE, "map_entry.gd.txt"), "w", encoding="utf8").write(txt)
print("entry text chars:", len(txt), "zones", len(blocks), "patches", len(circ), "hills", len(hills))
