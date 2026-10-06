import json,sys
from PIL import Image,ImageDraw
from frame import ll_to_frame
from mosaic import render
x0,x1,y0,y1,res=map(float,sys.argv[1:6]); out=sys.argv[6]
im=render(x0,x1,y0,y1,res).convert("RGB")
dr=ImageDraw.Draw(im)
d=json.load(open("overture_buildings.geojson",encoding="utf8"))
n=0
for f in d["features"]:
    g=f["geometry"]; rings=[g["coordinates"][0]] if g["type"]=="Polygon" else [p[0] for p in g["coordinates"]]
    for ring in rings:
        pts=[ll_to_frame(p[1],p[0]) for p in ring]
        cx=sum(p[0] for p in pts)/len(pts); cy=sum(p[1] for p in pts)/len(pts)
        if not (x0-50<=cx<=x1+50 and y0-50<=cy<=y1+50): continue
        px=[((p[0]-x0)/res,(p[1]-y0)/res) for p in pts]
        dr.line(px+[px[0]],fill=(255,255,0),width=1); n+=1
im.save(out); print("saved",out,n,"buildings drawn",im.size)
