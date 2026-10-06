import json,math,numpy as np
from shapely.geometry import Polygon,box,MultiPolygon
from shapely.ops import unary_union
from shapely import affinity
from frame import ll_to_frame
d=json.load(open("overture_buildings.geojson",encoding="utf8"))["features"]
X0,X1,Y0,Y1=-1500,5000,-1850,3500
polys=[]
for f in d:
    g=f["geometry"]
    rings=[g["coordinates"]] if g["type"]=="Polygon" else g["coordinates"]
    for rg in rings:
        pts=[ll_to_frame(p[1],p[0]) for p in rg[0]]
        try: pg=Polygon(pts)
        except Exception: continue
        if not pg.is_valid: pg=pg.buffer(0)
        if pg.is_empty: continue
        c=pg.centroid
        if not (X0-20<=c.x<=X1+20 and Y0-20<=c.y<=Y1+20): continue
        if pg.area<14: continue   # sheds / sub-pixel fragments
        polys.append(pg.simplify(0.7))
print(len(polys),"footprints kept in the frame")
json.dump([[round(c,1) for xy in p.exterior.coords[:-1] for c in xy] for p in polys if p.geom_type=="Polygon"],open("footprints_ext.json","w"))
import collections
a=[p.area for p in polys]; print("area m2: median %.0f p90 %.0f max %.0f"%(np.median(a),np.percentile(a,90),max(a)))
