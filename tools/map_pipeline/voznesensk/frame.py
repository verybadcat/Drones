import math
# Anchor (the Ukrnafta station on the H-24, chosen by the user): real lat/lon <-> game frame (meters).
LAT0, LON0 = 47.5445, 31.3695
ANCHOR_FRAME = (1500.0, 1750.0)          # the defended point sits where it does on every other map
BEARING_X = 113.0                         # real bearing (deg clockwise from north) that points to screen EAST (+x)
M_LAT = 110574.0
M_LON = 111320.0 * math.cos(math.radians(LAT0))
bx = math.radians(BEARING_X)
AX = (math.sin(bx), math.cos(bx))          # +x axis in real (E, N)
AY = (math.sin(bx + math.pi/2), math.cos(bx + math.pi/2))  # +y axis (screen down) in real (E, N)

def ll_to_frame(lat, lon):
    e = (lon - LON0) * M_LON
    n = (lat - LAT0) * M_LAT
    x = e*AX[0] + n*AX[1]
    y = e*AY[0] + n*AY[1]
    return ANCHOR_FRAME[0] + x, ANCHOR_FRAME[1] + y

def frame_to_ll(x, y):
    dx, dy = x - ANCHOR_FRAME[0], y - ANCHOR_FRAME[1]
    e = dx*AX[0] + dy*AY[0]
    n = dx*AX[1] + dy*AY[1]
    return LAT0 + n / M_LAT, LON0 + e / M_LON

# north on screen = direction of real north in frame coordinates
NORTH_ON_SCREEN = (AX[1], AY[1])

if __name__ == "__main__":
    print("north on screen:", NORTH_ON_SCREEN)
    for name,(x,y) in {"west flank NW":(-1500,0),"west flank SW":(-1500,3500),"NE":(5000,0),"SE":(5000,3500),"anchor":(1500,1750),"east mid":(5000,1750)}.items():
        print(name, ["%.5f"%v for v in frame_to_ll(x,y)])
    print("Rakove", ll_to_frame(47.53587,31.39930))
    print("Bolharka", ll_to_frame(47.55586,31.35000))
    print("city pt", ll_to_frame(47.556896,31.343611))
    print("Bolharskyi bridge", ll_to_frame(47.55980,31.34224))
