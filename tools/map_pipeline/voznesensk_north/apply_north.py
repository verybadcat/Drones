"""Extend the Voznesensk map north by DY metres: shift the whole existing entry down by DY, add the northern strip's hills,
cover blocks, trees and footprints (built in the old frame, y from -1850), grow height_m, rebuild nothing else."""
import json, math, os, random, re, sys

sys.stdout.reconfigure(encoding="utf8")
DY = 1800.0
HERE = os.path.dirname(os.path.abspath(__file__))
P = r"C:\Code\Drones\scripts\game_config.gd"
s = open(P, encoding="utf8", newline="").read()
crlf = "\r\n" in s
t = s.replace("\r\n", "\n")
a = t.index('\n"voznesensk": {') + 1
b = t.index("\n},\n", a)
entry = t[a:b]

num = r"(-?[0-9]+(?:\.[0-9]+)?)"
fmt = lambda v: ("%.1f" % v) if abs(v - round(v)) > 1e-9 else ("%.1f" % v)


def shift_pair_vec(m):
    return "%sVector2(%s, %.1f)" % (m.group(1), m.group(2), float(m.group(3)) + DY)


def must(count, what):
    assert count >= 1, what


# --- scalar keys
entry, n = re.subn(r'"height_m": 2200\.0,', '"height_m": %.1f,' % (2200.0 + DY), entry); must(n, "height")
entry, n = re.subn(r'("village_center": )Vector2\(1500\.0, 1750\.0\)', r'\1Vector2(1500.0, %.1f)' % (1750.0 + DY), entry); must(n, "village")
entry, n = re.subn(r'("position_m": )Vector2\(' + num + ", " + num + r"\)", lambda m: '%sVector2(%s, %.1f)' % (m.group(1), m.group(2), float(m.group(3)) + DY), entry); print("settlements", n)

# --- the data sections: hills .. forest patches (up to road_width_m)
h0 = entry.index('\t"hills": [')
r0 = entry.index('\t"road_width_m"')
sect = entry[h0:r0]
sect, n = re.subn(r'("center_m": )Vector2\(' + num + ", " + num + r"\)", lambda m: '%sVector2(%s, %.1f)' % (m.group(1), m.group(2), float(m.group(3)) + DY), sect)
print("hill + tree centres shifted:", n)

# terrain_zones: replace the whole list with the extended blocks (same algorithm, same parameters)
blocks = json.load(open(os.path.join(HERE, "blocks_ext.json")))
blocks = [x for x in blocks if x[1] + x[3] / 2.0 < 2195.0]
blocks.sort(key=lambda x: (x[1], x[0]))
zi = sect.index('\t"terrain_zones": [\n')
zj = sect.index("\n\t],\n", zi) + len("\n\t],\n")
zones = '\t"terrain_zones": [\n' + "".join(
    '\t\t{"rect": Rect2(%d * PIXELS_PER_METER, %d * PIXELS_PER_METER, %d * PIXELS_PER_METER, %d * PIXELS_PER_METER), "type": TerrainType.BUILDING},\n' % (x[0], x[1] + DY, x[2], x[3]) for x in blocks) + "\t],\n"
print("terrain_zones:", len(blocks))
sect = sect[:zi] + zones + sect[zj:]

# new hills
rnd = random.Random(20261006)


def harm_text(amp_lo, amp_hi, indent="\t\t\t"):
    f = rnd.sample([2, 3, 4], 2)
    hs = [(f[0], round(rnd.uniform(amp_lo, amp_hi), 2), round(rnd.uniform(0, 6.28), 1)), (f[1], round(rnd.uniform(amp_lo * 0.6, amp_hi * 0.8), 2), round(rnd.uniform(0, 6.28), 1))]
    return "[\n" + "".join('%s{"frequency": %d, "amplitude": %.2f, "phase": %.1f},\n' % (indent, h[0], h[1], h[2]) for h in hs) + indent[:-1] + "]"


new_hills = json.load(open(os.path.join(HERE, "hills_north.json")))
hills_txt = "".join('\t\t{"center_m": Vector2(%.1f, %.1f), "radius_m": %.1f, "height_m": %.1f, "warp_harmonics": %s},\n' % (h["cx"], h["cy"] + DY, h["r"], h["h"], harm_text(0.05, 0.13)) for h in new_hills)
hi = sect.index('\t"hills": [\n')
hj = sect.index("\n\t],\n", hi)
sect = sect[:hj + 1] + hills_txt + sect[hj + 1:]
print("new hills:", len(new_hills))

# new trees: only those centred in the new strip (old frame y < 0) join the existing patches
circ = json.load(open(os.path.join(HERE, "tree_circles_ext.json")))
circ = [c for c in circ if c[1] < 0.0]
trees_txt = "".join('\t\t{"center_m": Vector2(%.1f, %.1f), "radius_m": %.1f, "warp_harmonics": %s}, # wooded block / thicket\n' % (c[0], c[1] + DY, c[2], harm_text(0.08, 0.16)) for c in circ)
fi = sect.index('\t"forest_patches": [\n')
fj = sect.index("\n\t],\n", fi)
sect = sect[:fj + 1] + trees_txt + sect[fj + 1:]
print("new tree patches:", len(circ))
entry = entry[:h0] + sect + entry[r0:]

# --- road: every waypoint y
r1 = entry.index('\t"road_waypoints_m": [')
r2 = entry.index("\n\t],\n", r1)
road = entry[r1:r2]
road, n = re.subn(r"Vector2\(" + num + ", " + num + r"\)", lambda m: "Vector2(%s, %d)" % (m.group(1), round(float(m.group(2)) + DY)), road)
print("road waypoints shifted:", n)
entry = entry[:r1] + road + entry[r2:]

# --- player and enemy blocks
p0 = entry.index('\t"player": {')
tail = entry[p0:]
SQ = "PIXELS_PER_METER"
tail = tail.replace('"deployment_zone": Rect2(150.0 * PIXELS_PER_METER, 100.0 * PIXELS_PER_METER, 2200.0 * PIXELS_PER_METER, 1950.0 * PIXELS_PER_METER)',
                    '"deployment_zone": Rect2(150.0 * PIXELS_PER_METER, %.1f * PIXELS_PER_METER, 2200.0 * PIXELS_PER_METER, 1950.0 * PIXELS_PER_METER)' % (100.0 + DY))
assert "%.1f" % (100.0 + DY) in tail
old_m = '"mortar_deployment_zone": Rect2(30.0 * PIXELS_PER_METER, 60.0 * PIXELS_PER_METER, 1950.0 * PIXELS_PER_METER, 2000.0 * PIXELS_PER_METER)'
assert old_m in tail
tail = tail.replace(old_m, '"mortar_deployment_zone": Rect2(30.0 * PIXELS_PER_METER, 60.0 * PIXELS_PER_METER, 1950.0 * PIXELS_PER_METER, %.1f * PIXELS_PER_METER)' % (2000.0 + DY))
old_s = '"spotter_deployment_zone": Rect2(30.0 * PIXELS_PER_METER, 30.0 * PIXELS_PER_METER, 4940.0 * PIXELS_PER_METER, 2030.0 * PIXELS_PER_METER)'
assert old_s in tail
tail = tail.replace(old_s, '"spotter_deployment_zone": Rect2(30.0 * PIXELS_PER_METER, 30.0 * PIXELS_PER_METER, 4940.0 * PIXELS_PER_METER, %.1f * PIXELS_PER_METER)' % (2030.0 + DY))
# default positions: every "Vector2(x, y) * PIXELS_PER_METER" in the player block that is not a zone
q0 = tail.index('"default_squad_positions"')
q1 = tail.index('\t"enemy": {')
pos = tail[q0:q1]
pos, n = re.subn(r"Vector2\(" + num + ", " + num + r"\) \* PIXELS_PER_METER", lambda m: "Vector2(%s, %.1f) * PIXELS_PER_METER" % (m.group(1), float(m.group(2)) + DY), pos)
print("default positions shifted:", n)
tail = tail[:q0] + pos + tail[q1:]
for k in ("mortar_spread_min_y_m", "mortar_spread_max_y_m"):
    tail, n = re.subn(r'("%s": )' % k + num, lambda m: "%s%.1f" % (m.group(1), float(m.group(2)) + DY), tail)
    assert n == 1, k
entry = entry[:p0] + tail

# drone sweep rows for this map: the road row (index 2, the heavy one) sits on the road
entry = entry.replace('\t"road_width_m"', '\t# The drone\'s sweep rows, north to south (see GameConfig.drone_search_rows_m): the heavy third row on the road, the map\'s\n\t# long northern reach covered by the first two.\n\t"drone_search_rows_m": [800.0, 2300.0, %.1f, %.1f, %.1f],\n\t"road_width_m"' % (1750.0 + DY, 1750.0 + DY + 230.0, 1750.0 + DY + 390.0), 1)

t = t[:a] + entry + t[b:]
open(P, "w", encoding="utf8", newline="").write(t.replace("\n", "\r\n") if crlf else t)

# --- footprints resource
fp = json.load(open(os.path.join(HERE, "footprints_ext.json")))
fp = [f for f in fp if min(f[1::2]) <= 2260.0]
out = [[round(v + (DY if i % 2 else 0.0), 1) for i, v in enumerate(f)] for f in fp]
json.dump({"coordinate_frame": "meters in the map frame (x east on screen, y south on screen)", "buildings": out},
          open(r"C:\Code\Drones\assets\maps\voznesensk_buildings.json", "w"), separators=(",", ":"))
print("footprints:", len(out))
print("ok")
