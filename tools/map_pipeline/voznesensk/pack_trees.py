import json,math,numpy as np
from shapely.geometry import Polygon,box
from shapely.ops import unary_union
from shapely.prepared import prep
from scipy.ndimage import distance_transform_edt
from PIL import Image,ImageDraw
from frame import ll_to_frame
lc=json.load(open("overture_land_cover.geojson",encoding="utf8"))["features"]
def polys(g):
    if g["type"]=="Polygon": yield g["coordinates"]
    else:
        for c in g["coordinates"]: yield c
X0,X1,Y0,Y1=-1500,5000,0,3500
RES=10.0
W=int((X1-X0)/RES); H=int((Y1-Y0)/RES)
im=Image.new("L",(W,H),0); dr=ImageDraw.Draw(im)
n={"forest":0,"shrub":0}
for f in lc:
    st=f["properties"]["subtype"]
    if st not in ("forest",): continue
    for rings in polys(f["geometry"]):
        pts=[((x-X0)/RES,(y-Y0)/RES) for x,y in (ll_to_frame(p[1],p[0]) for p in rings[0])]
        dr.polygon(pts,fill=255)
        for hole in rings[1:]:
            dr.polygon([((x-X0)/RES,(y-Y0)/RES) for x,y in (ll_to_frame(p[1],p[0]) for p in hole)],fill=0)
        n[st]+=1
mask=np.asarray(im)>0
print("polygons",n,"mask coverage %.1f%% of frame"%(mask.mean()*100))
# do not grow trees over building footprints: carve out buildings (with 3 m margin) from the tree mask
fp=json.load(open("footprints.json"))
bim=Image.new("L",(W,H),0); bd=ImageDraw.Draw(bim)
for c in fp:
    pts=[((c[i]-X0)/RES,(c[i+1]-Y0)/RES) for i in range(0,len(c),2)]
    bd.polygon(pts,fill=255)
bmask=np.asarray(bim)>0
from scipy.ndimage import binary_dilation
mask&=~binary_dilation(bmask,iterations=1)
# greedy circle packing on the distance transform
RMAX=80.0; RMIN=20.0
dt=distance_transform_edt(mask)*RES
yy,xx=np.mgrid[0:H,0:W]
circles=[]
work=mask.copy()
for it in range(900):
    d=distance_transform_edt(work)*RES
    j,i=np.unravel_index(np.argmax(d),d.shape)
    r=d[j,i]
    if r<RMIN: break
    rr=min(r,RMAX)
    circles.append((X0+(i+0.5)*RES,Y0+(j+0.5)*RES,rr*0.95))
    # erase the covered area
    cx,cy=i,j; rad=rr/RES
    y0=max(0,int(cy-rad-1)); y1=min(H,int(cy+rad+2)); x0=max(0,int(cx-rad-1)); x1=min(W,int(cx+rad+2))
    sub=((xx[y0:y1,x0:x1]-cx)**2+(yy[y0:y1,x0:x1]-cy)**2)<=rad*rad
    work[y0:y1,x0:x1][sub]=False
print(len(circles),"circles; radius range %.0f-%.0f m"%(min(c[2] for c in circles),max(c[2] for c in circles)))
cov=sum(math.pi*c[2]**2 for c in circles)/ (mask.sum()*RES*RES)
print("circles cover %.0f%% of the tree mask area (overlap not removed)"%(cov*100))
json.dump([[round(a,1),round(b,1),round(r,1)] for a,b,r in circles],open("tree_circles.json","w"))
