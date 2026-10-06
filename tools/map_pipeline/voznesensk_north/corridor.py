import json, numpy as np, shapely
from shapely.geometry import Polygon
from shapely.ops import unary_union
from scipy import ndimage
from frame import ll_to_frame
d=json.load(open("overture_buildings.geojson",encoding="utf8"))["features"]
polys=[]
for f in d:
    g=f["geometry"]; rings=[g["coordinates"]] if g["type"]=="Polygon" else g["coordinates"]
    for rg in rings:
        pg=Polygon([ll_to_frame(c[1],c[0]) for c in rg[0]])
        if not pg.is_valid: pg=pg.buffer(0)
        if not pg.is_empty and pg.area>14: polys.append(pg)
print(len(polys))
linked=unary_union([p.buffer(60) for p in polys])
cl=list(linked.geoms) if linked.geom_type=="MultiPolygon" else [linked]
keep=[]
for c in cl:
    mem=[p for p in polys if p.centroid.within(c)]
    if len(mem)>=5: keep+=mem
region=unary_union([p.buffer(200,resolution=6) for p in keep])
X0,X1,Y0,Y1,C=-1500,5000,-2400,2200,20
xs=X0+(np.arange((X1-X0)//C)+.5)*C; ys=Y0+(np.arange((Y1-Y0)//C)+.5)*C
gx,gy=np.meshgrid(xs,ys)
bar=shapely.contains_xy(region,gx.ravel(),gy.ravel()).reshape(gx.shape)
np.save("bar_ext.npy",bar)
def idx(x,y): return int((y-Y0)//C), int((x-X0)//C)
start=idx(1030,1360)
for top in (0,-500,-1000,-1500,-2000,-2400):
    sub=~bar[int((top-Y0)//C):,:]
    lab,_=ndimage.label(sub)
    s=(start[0]-int((top-Y0)//C), start[1])
    comp=lab==lab[s]
    reach_west=comp[:, :int(100//C)+1].any()   # x within 100 m of west edge
    zone=(xs>=30)&(xs<1980)
    zy=(ys>=max(top,top+60))&(ys<2060)
    zfree=(~bar[np.ix_(zy,zone)]).mean()
    # free area in mortar zone that is connected to start
    zc=comp[np.ix_(np.where(zy)[0]-int((top-Y0)//C), np.where(zone)[0])].mean()
    print("top y=%5d  height=%4d  mortar-zone free %.0f%%, reachable-from-default %.0f%%, retreat corridor to west edge: %s"%(top,2200-top,100*zfree,100*zc,reach_west))
