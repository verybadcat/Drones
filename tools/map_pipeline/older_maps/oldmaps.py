"""Parse the three existing maps' frame facts out of game_config.gd."""
import re, json, math

SRC = r"C:\Code\Drones\scripts\game_config.gd"
PPM = 0.2


def split_maps():
    s = open(SRC, encoding="utf8").read().replace("\r\n", "\n")
    out = {}
    ids = ["pervomaiske", "pishchane", "svystunivka", "voznesensk"]
    pos = []
    for i in ids:
        m = re.search(r'^"%s": \{' % i, s, re.M)
        pos.append((i, m.start() if m else None))
    for k, (i, st) in enumerate(pos):
        if st is None:
            continue
        en = len(s)
        for (_, st2) in pos[k + 1:]:
            if st2 is not None:
                en = st2
                break
        out[i] = s[st:en]
    return out


def vec_list(block, key):
    m = re.search(r'"%s": \[\n(.*?)\n\t\],' % key, block, re.S)
    return [(float(a), float(b)) for a, b in re.findall(r'Vector2\((-?[\d.]+), (-?[\d.]+)\)', m.group(1))] if m else []


def facts(block):
    f = {}
    m = re.search(r'"coordinates": "([\d.]+), ([\d.]+)"', block)
    f["lat"], f["lon"] = float(m.group(1)), float(m.group(2))
    m = re.search(r'"village_center": Vector2\(([\d.]+), ([\d.]+)\)', block)
    f["vc"] = (float(m.group(1)), float(m.group(2)))
    f["road"] = vec_list(block, "road_waypoints_m")
    rects = []
    for m in re.finditer(r'Rect2\((-?[\d.]+) \* PIXELS_PER_METER, (-?[\d.]+) \* PIXELS_PER_METER, ([\d.]+) \* PIXELS_PER_METER, ([\d.]+) \* PIXELS_PER_METER\), "type": TerrainType\.BUILDING', block):
        rects.append(tuple(float(x) for x in m.groups()))
    f["rects"] = rects
    m = re.search(r'"compass_north_screen_direction": Vector2\((-?[\d.]+), (-?[\d.]+)\)', block)
    f["north"] = (float(m.group(1)), float(m.group(2)))
    return f


if __name__ == "__main__":
    for i, b in split_maps().items():
        f = facts(b)
        print(i, f["lat"], f["lon"], f["vc"], "road pts", len(f["road"]), "rects", len(f["rects"]), "north", f["north"])
