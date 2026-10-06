import json,math,numpy as np,sys
from shapely.geometry import Polygon,box
from shapely.ops import unary_union
fp=[Polygon([(c[i],c[i+1]) for i in range(0,len(c),2)]) for c in json.load(open("footprints.json"))]
core=[p for p in fp if p.centroid.x>=-150]
def make(BUF,CELL,MINAREA,COV):
    u=unary_union([p.buffer(BUF) for p in core])
    polys=list(u.geoms) if u.geom_type=="MultiPolygon" else [u]
    rects=[]
    for pg in polys:
        if pg.area<MINAREA: continue
        minx,miny,maxx,maxy=pg.bounds
        nx=int(math.ceil((maxx-minx)/CELL)); ny=int(math.ceil((maxy-miny)/CELL))
        grid=np.zeros((ny,nx),bool)
        for j in range(ny):
            for i in range(nx):
                c=box(minx+i*CELL,miny+j*CELL,minx+(i+1)*CELL,miny+(j+1)*CELL)
                if pg.intersection(c).area>=COV*CELL*CELL: grid[j,i]=True
        runs={}
        for j in range(ny):
            i=0
            while i<nx:
                if grid[j,i]:
                    k=i
                    while k<nx and grid[j,k]: k+=1
                    runs.setdefault((i,k),[]).append(j); i=k
                else: i+=1
        for (i0,i1),js in runs.items():
            js.sort(); start=js[0]; prev=js[0]
            for j in js[1:]+[None]:
                if j is None or j!=prev+1:
                    rects.append((minx+i0*CELL,miny+start*CELL,(i1-i0)*CELL,(prev-start+1)*CELL))
                    if j is not None: start=j
                if j is not None: prev=j
    return rects,len(polys)
for BUF,CELL,MIN,COV in [(10,24,500,0.35),(12,30,600,0.4),(14,32,800,0.4),(16,40,1000,0.4)]:
    r,n=make(BUF,CELL,MIN,COV)
    a=sum(x[2]*x[3] for x in r)/1e4
    # fraction of footprint area covered by the rects
    from shapely.ops import unary_union as uu
    ru=uu([box(x[0],x[1],x[0]+x[2],x[1]+x[3]) for x in r]) if r else None
    cov=sum(p.intersection(ru).area for p in core)/sum(p.area for p in core) if r else 0
    print("BUF %d CELL %d MINAREA %d COV %.2f -> %d rects (%d blobs), %.1f ha, covers %.0f%% of footprint area"%(BUF,CELL,MIN,COV,len(r),n,a,cov*100))
