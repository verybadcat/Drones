import math,glob,os,sys
from PIL import Image
import numpy as np
from frame import frame_to_ll
Z=17
def tile_xy(lat,lon,z):
    n=2**z
    return (lon+180)/360*n, (1-math.asinh(math.tan(math.radians(lat)))/math.pi)/2*n
_cache={}
def tile(x,y):
    k=(x,y)
    if k not in _cache:
        p=f"tiles/{Z}_{x}_{y}.jpg"
        _cache[k]=np.asarray(Image.open(p).convert("RGB")) if os.path.exists(p) else None
    return _cache[k]
def render(x0,x1,y0,y1,res):
    """Render the frame region [x0,x1]x[y0,y1] (meters) at `res` meters per pixel, in FRAME orientation."""
    W=int((x1-x0)/res); H=int((y1-y0)/res)
    out=np.zeros((H,W,3),np.uint8)
    xs=x0+(np.arange(W)+0.5)*res; ys=y0+(np.arange(H)+0.5)*res
    for j,yy in enumerate(ys):
        for i0 in range(0,W,1):
            pass
    # vectorised per row
    for j,yy in enumerate(ys):
        lat_lon=[frame_to_ll(xx,yy) for xx in xs]
        px=[tile_xy(la,lo,Z) for la,lo in lat_lon]
        for i,(tx,ty) in enumerate(px):
            t=tile(int(tx),int(ty))
            if t is None: continue
            u=int((tx-int(tx))*256); v=int((ty-int(ty))*256)
            out[j,i]=t[min(v,255),min(u,255)]
    return Image.fromarray(out)
if __name__=="__main__":
    x0,x1,y0,y1,res=map(float,sys.argv[1:6]); out=sys.argv[6]
    render(x0,x1,y0,y1,res).save(out); print("saved",out)
