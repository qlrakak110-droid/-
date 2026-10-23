import sys
sys.path.insert(0,'/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev')
from place import load
from collections import Counter
G=load()
def loc(fcf, wp):
    x,y,z=wp[0]-fcf[1],wp[1]-fcf[2],wp[2]-fcf[3]; r=fcf[4]
    return (r[0]*x+r[3]*y+r[6]*z, r[1]*x+r[4]*y+r[7]*z, r[2]*x+r[5]*y+r[8]*z)
stats=Counter(); rows=[]
for i in G.inst[1:]:
    if i['cls']!='Model': continue
    sf=G.child(i['id'],'ShopFloor'); it=G.child(i['id'],'Interior')
    if not sf: continue
    fcf=G.prop(G.inst[sf],'CFrame'); fs=G.prop(G.inst[sf],'Size')
    bw=G.child(i['id'],'ShopBackWall')
    out={}
    for nm in ('ShopBackWall','ShopCeiling','AutoDoor','ShopWindow','Sill','ShopPartition','Door'):
        for c in G.kids[i['id']]:
            ci=G.inst[c]
            if ci['name']==nm:
                cf=G.prop(ci,'CFrame')
                if not cf and ci['cls']=='Model':
                    ps=[G.prop(G.inst[k],'CFrame') for k in G.kids.get(c,[]) if G.prop(G.inst[k],'CFrame')]
                    if ps: cf=('CF',sum(p[1] for p in ps)/len(ps),sum(p[2] for p in ps)/len(ps),sum(p[3] for p in ps)/len(ps),None)
                if cf: out.setdefault(nm,[]).append(tuple(round(v,1) for v in loc(fcf,cf[1:4])))
    bz=out.get('ShopBackWall',[[0,0,0]])[0][2]
    stats['back_neg' if bz<0 else 'back_pos']+=1
    rows.append((i['name'], G.inst[i['parent']]['name'], 'it' if it else '-', [round(fs[1],1),round(fs[2],1),round(fs[3],1)], out.get('ShopBackWall'), out.get('AutoDoor'), out.get('ShopCeiling'), out.get('ShopPartition')))
print(stats)
for r in rows[:12]: print(r)
print([r[:2] for r in rows if r[4] and r[4][0][2]>0][:20])
print('noAutoDoor', [r[:2] for r in rows if not r[5]][:30])
