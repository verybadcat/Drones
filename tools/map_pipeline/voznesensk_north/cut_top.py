"""Cut CUT metres off the top (north) of the Voznesensk map: every y in the entry moves up by CUT, what falls wholly above the new top is
dropped, height_m shrinks. The map becomes 3,800 m tall = 760 px: exactly the window's standard height."""
import json, os, re, sys

sys.stdout.reconfigure(encoding="utf8")
CUT = 200.0
HERE = os.path.dirname(os.path.abspath(__file__))
P = r"C:\Code\Drones\scripts\game_config.gd"
s = open(P, encoding="utf8", newline="").read()
crlf = "\r\n" in s
t = s.replace("\r\n", "\n")
a = t.index('\n"voznesensk": {') + 1
b = t.index("\n},\n", a)
entry = t[a:b]
num = r"(-?[0-9]+(?:\.[0-9]+)?)"


def up(v):
    return float(v) - CUT


entry, n = re.subn(r'"height_m": 4000\.0,', '"height_m": 3800.0,', entry)
assert n == 1
entry, n = re.subn(r'("village_center": )Vector2\(1500\.0, 3550\.0\)', r'\1Vector2(1500.0, 3350.0)', entry)
assert n == 1
entry, n = re.subn(r'("position_m": )Vector2\(' + num + ", " + num + r"\)", lambda m: "%sVector2(%s, %.1f)" % (m.group(1), m.group(2), up(m.group(3))), entry)
print("settlements", n)

h0 = entry.index('\t"hills": [')
r0 = entry.index('\t# The drone\'s sweep rows')
sect = entry[h0:r0]

# hills: shift all (a hill centred above the new top still shapes the ground inside it)
hi = sect.index('\t"hills": [\n')
hj = sect.index("\n\t],\n", hi)
hills = sect[hi:hj]
hills, n = re.subn(r'("center_m": )Vector2\(' + num + ", " + num + r"\)", lambda m: "%sVector2(%s, %.1f)" % (m.group(1), m.group(2), up(m.group(3))), hills)
print("hills shifted", n)
sect = sect[:hi] + hills + sect[hj:]

# terrain zones: shift, clip to the new top, drop what lies wholly above it
zi = sect.index('\t"terrain_zones": [\n')
zj = sect.index("\n\t],\n", zi) + len("\n\t],\n")
rects = re.findall(r"Rect2\(([-0-9.]+) \* PIXELS_PER_METER, ([-0-9.]+) \* PIXELS_PER_METER, ([-0-9.]+) \* PIXELS_PER_METER, ([-0-9.]+) \* PIXELS_PER_METER\)", sect[zi:zj])
kept = []
dropped = 0
for x, y, w, h in rects:
    x, y, w, h = float(x), up(y), float(w), float(h)
    if y + h <= 0.0:
        dropped += 1
        continue
    if y < 0.0:
        h += y
        y = 0.0
    kept.append((x, y, w, h))
zones = '\t"terrain_zones": [\n' + "".join(
    '\t\t{"rect": Rect2(%d * PIXELS_PER_METER, %d * PIXELS_PER_METER, %d * PIXELS_PER_METER, %d * PIXELS_PER_METER), "type": TerrainType.BUILDING},\n' % z for z in kept) + "\t],\n"
print("terrain_zones kept", len(kept), "dropped", dropped)
sect = sect[:zi] + zones + sect[zj:]

# forest patches: shift, drop a patch whose circle lies wholly above the new top
fi = sect.index('\t"forest_patches": [\n')
fj = sect.index("\n\t],\n", fi) + len("\n\t],\n")
body = sect[fi + len('\t"forest_patches": [\n'):fj - len("\t],\n")]
blocks = re.split(r"(?=\t\t\{\"center_m\")", body)
blocks = [x for x in blocks if x.strip()]
out = []
gone = 0
for blk in blocks:
    m = re.search(r'"center_m": Vector2\(' + num + ", " + num + r'\), "radius_m": ' + num, blk)
    cx, cy, r = float(m.group(1)), up(m.group(2)), float(m.group(3))
    if cy + r * 1.5 <= 0.0:
        gone += 1
        continue
    blk = blk.replace(m.group(0), '"center_m": Vector2(%s, %.1f), "radius_m": %s' % (m.group(1), cy, m.group(3)), 1)
    out.append(blk)
print("forest patches kept", len(out), "dropped", gone)
sect = sect[:fi] + '\t"forest_patches": [\n' + "".join(out) + "\t],\n" + sect[fj:]
entry = entry[:h0] + sect + entry[r0:]

# drone rows, road, player, enemy
entry, n = re.subn(r'"drone_search_rows_m": \[800\.0, 2300\.0, 3550\.0, 3780\.0, 3940\.0\]', '"drone_search_rows_m": [600.0, 2100.0, 3350.0, 3580.0, 3740.0]', entry)
assert n == 1, "rows"
r1 = entry.index('\t"road_waypoints_m": [')
r2 = entry.index("\n\t],\n", r1)
road = entry[r1:r2]
road, n = re.subn(r"Vector2\(" + num + ", " + num + r"\)", lambda m: "Vector2(%s, %d)" % (m.group(1), round(up(m.group(2)))), road)
print("road", n)
entry = entry[:r1] + road + entry[r2:]
p0 = entry.index('\t"player": {')
tail = entry[p0:]


def sub1(old, new):
    global tail
    assert tail.count(old) == 1, old[:70]
    tail = tail.replace(old, new)


sub1('Rect2(150.0 * PIXELS_PER_METER, 1900.0 * PIXELS_PER_METER, 2200.0 * PIXELS_PER_METER, 1950.0 * PIXELS_PER_METER)', 'Rect2(150.0 * PIXELS_PER_METER, 1700.0 * PIXELS_PER_METER, 2200.0 * PIXELS_PER_METER, 1950.0 * PIXELS_PER_METER)')
sub1('Rect2(30.0 * PIXELS_PER_METER, 60.0 * PIXELS_PER_METER, 1950.0 * PIXELS_PER_METER, 3800.0 * PIXELS_PER_METER)', 'Rect2(30.0 * PIXELS_PER_METER, 60.0 * PIXELS_PER_METER, 1950.0 * PIXELS_PER_METER, 3600.0 * PIXELS_PER_METER)')
sub1('Rect2(30.0 * PIXELS_PER_METER, 30.0 * PIXELS_PER_METER, 4940.0 * PIXELS_PER_METER, 3830.0 * PIXELS_PER_METER)', 'Rect2(30.0 * PIXELS_PER_METER, 30.0 * PIXELS_PER_METER, 4940.0 * PIXELS_PER_METER, 3630.0 * PIXELS_PER_METER)')
q0 = tail.index('"default_squad_positions"')
q1 = tail.index('\t"enemy": {')
pos = tail[q0:q1]
pos, n = re.subn(r"Vector2\(" + num + ", " + num + r"\) \* PIXELS_PER_METER", lambda m: "Vector2(%s, %.1f) * PIXELS_PER_METER" % (m.group(1), up(m.group(2))), pos)
print("defaults", n)
tail = tail[:q0] + pos + tail[q1:]
for k in ("mortar_spread_min_y_m", "mortar_spread_max_y_m"):
    tail, n = re.subn(r'("%s": )' % k + num, lambda m: "%s%.1f" % (m.group(1), up(m.group(2))), tail)
    assert n == 1
entry = entry[:p0] + tail

# doc text
entry = entry.replace("buildings come from Overture Maps (Microsoft ML Buildings plus OpenStreetMap): 5,712 real footprints,", "buildings come from Overture Maps (Microsoft ML Buildings plus OpenStreetMap): REPLACE_FOOTPRINTS real footprints,")
t = t[:a] + entry + t[b:]
open(P, "w", encoding="utf8", newline="").write(t.replace("\n", "\r\n") if crlf else t)

# footprints resource
fp = json.load(open(r"C:\Code\Drones\assets\maps\voznesensk_buildings.json"))
out = []
for f in fp["buildings"]:
    ys = f[1::2]
    if max(ys) - CUT <= 0.0:
        continue
    out.append([round(v - (CUT if i % 2 else 0.0), 1) for i, v in enumerate(f)])
fp["buildings"] = out
json.dump(fp, open(r"C:\Code\Drones\assets\maps\voznesensk_buildings.json", "w"), separators=(",", ":"))
print("footprints", len(out))
open(os.path.join(HERE, "cut_top_footprints.txt"), "w").write(str(len(out)))
print("ok")
