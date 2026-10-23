exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
import json, math, sys
SEAT={'ChairSeat','StoolSeat','Stool','Seat','Cushion','SeatCushion','StoolTop','BarStool'}
TABLE={'TableTop':'table','LowTableTop':'low','LowTable':'low','CommunalTable':'table','Table':'table','BarTop':'bar','WindowBar':'bar','Ledge':'bar','CounterTop':'counter','PassTop':'counter','BarCounter':'bar'}
ORDER={'OrderKiosk','KioskScreen','PosBase','CustomerDisplay','PosScreen','CashDeskTop','PosScreenBack','CardReader'}
COOK=["EspressoBody","GroupHead","TapPost","CuttingBoard","FryBasket","Fryer","StockPot","Broth","Burner","KitchenPass","PassLedge","Hood","Grinder","GelatoTub","WaffleIron","SteamerCase"]
PASS={'PassLedge','PassTop','PassTray','KitchenPass','PassCounter','DripTray'}
ANCH=["PosBase","CashierPanel","OrderKiosk","FrontDesk","BackBar","POS","BarCounter","바 카운터","안내 · 접수 카운터","Counter"]
def desc(iid):
    out=[];st=[iid]
    while st:
        x=st.pop()
        for c in kids.get(x,[]):
            out.append(c); st.append(c)
    return out
def pos(i):
    cf=G.prop(i,'CFrame')
    return (cf[1],cf[2],cf[3]) if cf else None
def size(i):
    s=G.prop(i,'Size'); return (s[1],s[2],s[3]) if s else None
def aabb(i):
    cf=G.prop(i,'CFrame'); s=G.prop(i,'Size')
    if not cf or not s: return None
    r=cf[4]; hx,hy,hz=s[1]/2,s[2]/2,s[3]/2
    # r is row-major 3x3 : R00 R01 R02 R10 ...
    ex=abs(r[0])*hx+abs(r[1])*hy+abs(r[2])*hz
    ey=abs(r[3])*hx+abs(r[4])*hy+abs(r[5])*hz
    ez=abs(r[6])*hx+abs(r[7])*hy+abs(r[8])*hz
    c=(cf[1],cf[2],cf[3])
    return (c[0]-ex,c[1]-ey,c[2]-ez),(c[0]+ex,c[1]+ey,c[2]+ez)
BASEPART={'Part','MeshPart','UnionOperation','WedgePart','Seat','TrussPart','CornerWedgePart','VehicleSeat'}
res=[]
for i in G.inst[1:]:
    if i['cls']!='Model': continue
    ch={G.inst[c]['name']:c for c in kids.get(i['id'],[])}
    gws = 'GwShop' in (i.get('tags') or [])
    if not (('Interior' in ch and 'ShopFloor' in ch) or gws): continue
    fl = ch.get('ShopFloor')
    if fl is None:
        for d in desc(i['id']):
            if G.inst[d]['name']=='ShopFloor': fl=d;break
    if fl is None: continue
    fb=aabb(G.inst[fl]); floorY=fb[1][1]
    D=desc(i['id'])
    names={}
    seats=[];tables=[];clerks=[];hums=[];doors=[];anchor=None;arank=99
    for d in D:
        x=G.inst[d]; n=x['name']
        if x['cls'] in BASEPART:
            names[n]=names.get(n,0)+1
            if n in SEAT or x['cls']=='Seat':
                seats.append(d)
            tk=TABLE.get(n)
            if n=='Top' and G.inst[x['parent']]['name']=='PlasticTable': tk='table'
            if tk: tables.append((d,tk))
            if n in ANCH and ANCH.index(n)<arank: arank=ANCH.index(n); anchor=d
        if x['cls']=='Model':
            tg=x.get('tags') or []
            if 'GwShopClerk' in tg: clerks.append(d)
            if n in ('AutoDoor','AutoDoor_GS25') or 'AutoDoor' in tg: doors.append(d)
        if x['cls']=='Humanoid': hums.append(x['parent'])
    # tables valid
    tv=[]
    for d,tk in tables:
        bb=aabb(G.inst[d])
        if not bb: continue
        mn,mx=bb; area=(mx[0]-mn[0])*(mx[2]-mn[2])
        if area>=1.2 and 1.2<mx[1]-floorY<5.5: tv.append({'id':d,'kind':tk,'mn':mn,'mx':mx,'seats':[]})
    for s in seats:
        bb=aabb(G.inst[s]);
        if not bb: continue
        mn,mx=bb; top=((mn[0]+mx[0])/2,mx[1],(mn[2]+mx[2])/2)
        if top[1]-floorY>4.5 or top[1]-floorY<-0.5: continue
        best=None;bd=1e9
        for t in tv:
            dy=t['mx'][1]-top[1]
            if 0.15<dy<3.2:
                cx=min(max(top[0],t['mn'][0]),t['mx'][0]); cz=min(max(top[2],t['mn'][2]),t['mx'][2])
                dd=math.hypot(cx-top[0],cz-top[2]); lim=2.6 if t['kind'] in('counter','bar') else 3.0
                if dd<lim and dd<bd: best=t;bd=dd
        if best: best['seats'].append(s)
    used=[t for t in tv if t['seats']]
    cook=[n for n in COOK if n in names]
    rec={'name':i['name'],'path':path(i['id']),'gwshop':gws,'attrs':{k:str(G.val(v)) for k,v in i['attrs'].items()},
      'floor':[round(v,1) for v in pos(G.inst[fl])],'floorSize':[round(v,1) for v in size(G.inst[fl])],'floorY':round(floorY,2),
      'nSeats':len(seats),'tables':[(t['kind'],len(t['seats']),[round(v,1) for v in ((t['mn'][0]+t['mx'][0])/2,t['mx'][1],(t['mn'][2]+t['mx'][2])/2)]) for t in used],
      'order':[n for n in ORDER if n in names],'cook':cook,'pass':[n for n in PASS if n in names],
      'anchor':(G.inst[anchor]['name'],[round(v,1) for v in pos(G.inst[anchor])]) if anchor else None,
      'clerks':[(G.inst[c]['name'],{k:str(G.val(v)) for k,v in G.inst[c]['attrs'].items()}) for c in clerks],
      'humanoids':[G.inst[h]['name'] for h in hums][:6],
      'doors':len(doors),
      'misc':{n:names[n] for n in ['Counter','CounterTop','FrontDesk','BackBar','BarCounter','TapPost','TapHandle','TankWater','GrillTable','Coals','Gondola_1','OpenChiller','Fridge','ShopBackWall','Door_restroom','WaterPurifier','TrashBin','Bin','MDBoard','Sign_MENU','DisplayCase','PastryCase','SalonChair','Mirror','처방약장','WorkDesk'] if n in names}}
    res.append(rec)
json.dump(res,open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/crew/py/shops_scan.json','w'),ensure_ascii=False,indent=0)
print(len(res))
