import json, os, re, shutil, sys

sys.stdout.reconfigure(encoding="utf8")
HERE = os.path.dirname(os.path.abspath(__file__))
P = r"C:\Code\Drones\scripts\game_config.gd"
s = open(P, encoding="utf8", newline="").read()
crlf = "\r\n" in s
t = s.replace("\r\n", "\n")

NOTE = {
    "pervomaiske": "Myrne's 636 footprints in this frame (the old 21 blocks drew a stylised grid of houses)",
    "pishchane": "474 footprints in this frame (OpenStreetMap had tagged only 16 buildings here, which is why the old blocks were partly guessed from imagery)",
    "svystunivka": "221 footprints in this frame",
}
OFFS = {"pervomaiske": "(-22, +20) m", "pishchane": "(+74, +25) m", "svystunivka": "(0, +5) m"}

for mid in ("pervomaiske", "pishchane", "svystunivka"):
    start = t.index('\n"%s": {' % mid) + 1
    nxt = [t.find('\n"%s": {' % o, start) for o in ("pervomaiske", "pishchane", "svystunivka", "voznesensk")]
    nxt = [n for n in nxt if n > start]
    end = min(nxt) + 1 if nxt else t.index("\n}\n", start) + 1
    block = t[start:end]
    # 1. terrain_zones
    i = block.index('\t"terrain_zones": [\n')
    j = block.index("\n\t],\n", i) + len("\n\t],\n")
    rects = json.load(open(os.path.join(HERE, "%s_blocks.json" % mid)))
    zones = '\t"terrain_zones": [\n' + "".join(
        '\t\t{"rect": Rect2(%d * PIXELS_PER_METER, %d * PIXELS_PER_METER, %d * PIXELS_PER_METER, %d * PIXELS_PER_METER), "type": TerrainType.BUILDING},\n' % tuple(r) for r in rects) + "\t],\n"
    block = block[:i] + zones + block[j:]
    # 2. footprints key after the settlements block
    k = block.index('\t"settlements": [\n')
    k2 = block.index("\n\t],\n", k) + len("\n\t],\n")
    block = block[:k2] + '\n\t# Real building footprints, drawn as they are (see this entry\'s doc comment); terrain_zones below are the coarse\n\t# cover blocks the game logic uses.\n\t"building_footprints_file": "res://assets/maps/%s_buildings.json",\n' % mid + block[k2:]
    t = t[:start] + block + t[end:]
    # 3. doc paragraph, appended to the comment block right above the entry
    key = '\n"%s": {' % mid
    pos = t.index(key)
    note = ("##\n## BUILDINGS REDONE (2026-10), the way the Voznesensk map's were (see its doc comment): the blocks above were OpenStreetMap\n"
            "## footprints aggregated and drawn as stylised houses, which never matched a satellite picture. Now every building is a real\n"
            "## footprint from Overture Maps (Microsoft ML Buildings plus OpenStreetMap), drawn as itself from assets/maps/%s_buildings.json:\n"
            "## %s, checked by overlaying them on Esri World Imagery (they sit on the houses). The frame is unchanged; the footprints were placed\n"
            "## in it by measuring this map's own roads and old blocks against the real ones (an offset of %s). terrain_zones are now\n"
            "## the footprints merged with a 14 m buffer and rasterised to 32 m cells (the game logic's cover blocks); hills, trees, road and\n"
            "## the default unit positions are as they were.\n") % (mid, NOTE[mid], OFFS[mid])
    t = t[:pos] + "\n" + note.rstrip("\n") + t[pos:]
    shutil.copy(os.path.join(HERE, "%s_buildings.json" % mid), r"C:\Code\Drones\assets\maps\%s_buildings.json" % mid)
    print(mid, "zones", len(rects))

if crlf:
    t = t.replace("\n", "\r\n")
open(P, "w", encoding="utf8", newline="").write(t)
print("done")
