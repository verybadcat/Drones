import json,time,urllib.request,urllib.parse,sys,os
from frame import frame_to_ll
pts=[]
xs=list(range(-1600,5101,100)); ys=list(range(-1900,-99,100))
for y in ys:
    for x in xs:
        pts.append((x,y)+frame_to_ll(x,y))
print(len(pts),"points")
out={tuple(json.loads(k)):v for k,v in json.load(open("dem.json")).items()}
todo=[p for p in pts if (p[0],p[1]) not in out]
for i in range(0,len(todo),100):
    chunk=todo[i:i+100]
    loc="|".join("%.6f,%.6f"%(p[2],p[3]) for p in chunk)
    url="https://api.opentopodata.org/v1/srtm30m?locations="+urllib.parse.quote(loc,safe=",|")
    for attempt in range(6):
        try:
            req=urllib.request.Request(url,headers={"User-Agent":"drones-game-research/1.0"})
            d=json.load(urllib.request.urlopen(req,timeout=60)); break
        except Exception as e:
            print("retry",e); time.sleep(6)
    else: sys.exit("failed")
    for p,r in zip(chunk,d["results"]): out[(p[0],p[1])]=r["elevation"]
    json.dump({json.dumps(list(k)):v for k,v in out.items()},open("dem.json","w"))
    print(i+len(chunk),"/",len(todo)); time.sleep(1.3)
