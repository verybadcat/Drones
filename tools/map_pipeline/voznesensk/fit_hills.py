import json,math,numpy as np
from scipy.optimize import nnls
Z=np.load("dem.npy"); ax=json.load(open("dem_axes.json")); xs=np.array(ax["xs"],float); ys=np.array(ax["ys"],float)
X,Y=np.meshgrid(xs,ys)
px=X.ravel(); py=Y.ravel(); z=Z.ravel()
# weights: favour the area around the defended point (anchor frame (1500,1750)); the rest of the map still counts
d_anchor=np.hypot(px-1500,py-1750)
w=np.where(d_anchor<1300,6.0,1.0)
# also weight the playable core (x>=0) over the far west rear
w=w*np.where(px>=-200,1.0,0.4)
base=float(np.percentile(z,3))
r0=z-base
radii=[90,130,190,280,400,560,780,1100,1600]
cent=[(x,y) for x in range(-1600,5101,100) for y in range(-100,3601,100)]
def col(cx,cy,r): return np.exp(-((px-cx)**2+(py-cy)**2)/(2*r*r))
chosen=[]; cols=[]
res=r0.copy()
sw=np.sqrt(w)
for it in range(28):
    best=None
    for r in radii:
        for (cx,cy) in cent:
            c=col(cx,cy,r)
            if c.max()<0.2 or (c*w).sum()<1e-6: continue
            # optimal nonneg height for the weighted LS
            h=max((c*res*w).sum()/((c*c*w).sum()+1e-12),0.0)
            gain=h*h*(c*c*w).sum()
            if best is None or gain>best[0]: best=(gain,cx,cy,r,h)
    chosen.append(best[1:4]); cols.append(col(*best[1:4]))
    A=np.stack(cols,1)*sw[:,None]
    h,_=nnls(A,r0*sw)
    res=r0-(np.stack(cols,1)@h)
    rms=math.sqrt((res**2).mean()); rms_n=math.sqrt((res[d_anchor<1300]**2).mean())
    print(it+1,"hills  rms %.2f  near-anchor rms %.2f  last (%d,%d,r=%d) h=%.1f"%(rms,rms_n,best[1],best[2],best[3],h[-1]))
hills=[{"cx":c[0],"cy":c[1],"r":c[2],"h":float(hh)} for c,hh in zip(chosen,h) if hh>0.4]
json.dump({"baseline":base,"hills":hills,"rms":rms,"rms_near":rms_n},open("hills_fit.json","w"),indent=1)
print(len(hills),"hills kept; baseline %.1f"%base)
