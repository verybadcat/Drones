import math,os,sys,time,urllib.request
from concurrent.futures import ThreadPoolExecutor
from frame import frame_to_ll
Z=int(sys.argv[1]) if len(sys.argv)>1 else 17
def tile_xy(lat,lon,z):
    n=2**z
    x=(lon+180)/360*n
    y=(1-math.asinh(math.tan(math.radians(lat)))/math.pi)/2*n
    return x,y
# tiles touching the (rotated) frame: sample the frame densely
need=set()
for fx in range(-1600,5101,60):
    for fy in range(-100,3601,60):
        lat,lon=frame_to_ll(fx,fy)
        x,y=tile_xy(lat,lon,Z)
        need.add((int(x),int(y)))
print(len(need),"tiles at zoom",Z)
def get(t):
    x,y=t
    p=f"tiles/{Z}_{x}_{y}.jpg"
    if os.path.exists(p) and os.path.getsize(p)>500: return 0
    url=f"https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{Z}/{y}/{x}"
    for a in range(4):
        try:
            req=urllib.request.Request(url,headers={"User-Agent":"drones-game-research/1.0"})
            data=urllib.request.urlopen(req,timeout=40).read()
            open(p,"wb").write(data); return 1
        except Exception as e:
            time.sleep(2)
    return -1
with ThreadPoolExecutor(6) as ex:
    res=list(ex.map(get,sorted(need)))
print("downloaded",res.count(1),"cached",res.count(0),"failed",res.count(-1))
