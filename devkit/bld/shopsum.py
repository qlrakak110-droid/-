exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
import json
from collections import Counter
def child(iid, nm):
    for c in kids.get(iid,[]):
        if G.inst[c]['name']==nm: return c
def desc(iid):
    out=[];st=[iid]
    while st:
        x=st.pop()
        for c in kids.get(x,[]):
            out.append(c); st.append(c)
    return out
PARTS=('Part','WedgePart','Seat','CornerWedgePart','TrussPart','MeshPart')
KEYS=['CounterTop','Counter','PosBase','OrderKiosk','KioskScreen','CashDeskTop','FrontDesk','BarTop','EspressoBody','GroupHead','TapPost','CuttingBoard','StockPot','Fryer','TankWater','Gondola_1','Fridge','OpenChiller','Microwave','HotWater','PastryCase','WallRack','MDBoard','Door_restroom','Bin','WaterPurifier','TableTop','ChairSeat','StoolSeat','BarStool','GrillTable','Coals','PlasticTable','LowTable','Cushion','SpoonBox','TubeLamp','ShopCeiling','ShopBackWall','ShopPartition']
rows=[]
for i in G.inst[1:]:
    if i['cls']=='Model' and child(i['id'],'Interior') and child(i['id'],'ShopFloor'):
        sid=i['id']
        sf=G.inst[child(sid,'ShopFloor')]
        cf=G.prop(sf,'CFrame'); sz=G.prop(sf,'Size')
        d=desc(sid)
        names=Counter(G.inst[x]['name'] for x in d)
        intr=child(sid,'Interior')
        ip=[x for x in desc(intr) if G.inst[x]['cls'] in PARTS]
        allp=[x for x in d if G.inst[x]['cls'] in PARTS]
        lights=sum(1 for x in d if G.inst[x]['cls'] in ('PointLight','SpotLight','SurfaceLight'))
        guis=sum(1 for x in d if G.inst[x]['cls']=='SurfaceGui')
        rows.append(dict(name=i['name'], parent=G.inst[i['parent']]['name'], floor=[round(cf[1],1),round(cf[2],2),round(cf[3],1)], floorSize=[round(sz[1],1),round(sz[3],1)], interiorParts=len(ip), totalParts=len(allp), lights=lights, guis=guis, keys={k:names[k] for k in KEYS if names[k]}))
json.dump(rows, open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/systems_streetshops_static.json','w'), ensure_ascii=False, indent=0)
import statistics
ipc=[r['interiorParts'] for r in rows]
print(len(rows), 'interiorParts median', statistics.median(ipc), 'min', min(ipc), 'max', max(ipc))
print('no counter-ish', sum(1 for r in rows if not any(k in r['keys'] for k in ('CounterTop','Counter','PosBase','OrderKiosk','CashDeskTop','FrontDesk','BarTop'))))
print('no lights', sum(1 for r in rows if r['lights']==0), 'lights total', sum(r['lights'] for r in rows))
print('with ShopCeiling', sum(1 for r in rows if 'ShopCeiling' in r['keys']))
print('<=12 interior parts', [ (r['name'],r['interiorParts']) for r in rows if r['interiorParts']<=12])
c=Counter()
for r in rows:
    for k in r['keys']: c[k]+=1
print(c.most_common())
