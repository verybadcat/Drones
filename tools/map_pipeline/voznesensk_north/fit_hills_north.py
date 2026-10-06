import json, math, numpy as np
from scipy.optimize import nnls
dem={tuple(json.loads(k)):v for k,v in json.load(open("dem.json")).items()}
hf=json.load(open("hills_fit.json")); base=hf["baseline"]; print("baseline",base)
xs=sorted({k[0] for k in dem}); ys=sorted({k[1] for k in dem})
Z=np.array([[dem.get((x,y),np.nan) for x in xs] for y in ys])
X,Y=np.meshgrid(xs,ys); px=X.ravel(); py=Y.ravel(); z=Z.ravel()
ok=~np.isnan(z); px,py,z=px[ok],py[ok],z[ok]
def col(cx,cy,r): return np.exp(-((px-cx)**2+(py-cy)**2)/(2*r*r))
model=np.full_like(z,base)
for h in hf["hills"]: model+=h["h"]*col(h["cx"],h["cy"],h["r"])
res0=z-model
strip=py<100
print("existing model over the new strip: rms %.1f m, mean %.1f; over the old area rms %.1f"%(math.sqrt((res0[strip]**2).mean()),res0[strip].mean(),math.sqrt((res0[~strip]**2).mean())))
# weights: the strip counts fully, the old area enough that new hills do not disturb it
w=np.where(strip,1.0,3.0)*np.where(px>=-200,1.0,0.4)
radii=[130,190,280,400,560,780]
cent=[(x,y) for x in range(-1600,5101,100) for y in range(-1900,101,100)]
chosen=[];cols=[];res=res0.copy();sw=np.sqrt(w)
for it in range(14):
    best=None
    for r in radii:
        for (cx,cy) in cent:
            c=col(cx,cy,r)
            if c.max()<0.2: continue
            hh=max((c*res*w).sum()/((c*c*w).sum()+1e-12),0.0)
            gain=hh*hh*(c*c*w).sum()
            if best is None or gain>best[0]: best=(gain,cx,cy,r,hh)
    chosen.append(best[1:4]); cols.append(col(*best[1:4]))
    A=np.stack(cols,1)*sw[:,None]; h,_=nnls(A,res0*sw)
    res=res0-(np.stack(cols,1)@h)
    print(it+1,"new hills: strip rms %.2f  old-area rms %.2f  last (%d,%d,r=%d) h=%.1f"%(math.sqrt((res[strip]**2).mean()),math.sqrt((res[~strip]**2).mean()),best[1],best[2],best[3],h[-1]))
hills=[{"cx":c[0],"cy":c[1],"r":c[2],"h":float(hh)} for c,hh in zip(chosen,h) if hh>0.4]
json.dump(hills,open("hills_north.json","w"),indent=1); print(len(hills),"kept")
