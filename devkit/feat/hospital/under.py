exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
import math, json
PARTS={'Part','WedgePart','MeshPart','Seat','UnionOperation','TrussPart','CornerWedgePart','VehicleSeat','SpawnLocation','IntersectOperation','NegateOperation'}
ws=[i for i in G.inst[1:] if i['cls']=='Workspace'][0]['id']
def inws(iid):
    while iid:
        if iid==ws: return True
        iid=G.inst[iid]['parent']
    return False
rows=[]
for i in G.inst[1:]:
    if i['cls'] not in PARTS: continue
    cf=G.prop(i,'CFrame'); sz=G.prop(i,'Size')
    if not cf or not sz or sz[0]!='V3': continue
    p=cf[1:4]; R=cf[4]; s=sz[1:4]
    h=[s[0]/2,s[1]/2,s[2]/2]
    ex=[abs(R[0])*h[0]+abs(R[1])*h[1]+abs(R[2])*h[2], abs(R[3])*h[0]+abs(R[4])*h[1]+abs(R[5])*h[2], abs(R[6])*h[0]+abs(R[7])*h[1]+abs(R[8])*h[2]]
    mn=[p[k]-ex[k] for k in range(3)]; mx=[p[k]+ex[k] for k in range(3)]
    rows.append((i['id'],mn,mx))
import pickle
pickle.dump(rows,open('aabbs.pkl','wb'))
print(len(rows))
# workspace check later
terr=[i for i in G.inst[1:] if i['cls']=='Terrain']
print('terrain', [(t['id'], list((t.get('props') or {}).keys())[:30]) for t in terr])
