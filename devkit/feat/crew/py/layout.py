exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
import sys, math
targets=sys.argv[1:]
BASEPART={'Part','MeshPart','UnionOperation','WedgePart','Seat','TrussPart','CornerWedgePart'}
def desc(iid):
    out=[];st=[(iid,0)]
    while st:
        x,dp=st.pop()
        for c in kids.get(x,[]):
            out.append((c,dp+1)); st.append((c,dp+1))
    return out
for tg in targets:
    cands=[i for i in G.inst[1:] if i['cls']=='Model' and i['name']==tg and any(G.inst[c]['name']=='ShopFloor' for c in kids.get(i['id'],[]))]
    if not cands:
        cands=[i for i in G.inst[1:] if i['cls']=='Model' and i['name']==tg and 'GwShop' in (i.get('tags') or [])]
    for m in cands[:1]:
        fl=[c for c,_ in desc(m['id']) if G.inst[c]['name']=='ShopFloor'][0]
        fcf=G.prop(G.inst[fl],'CFrame'); fs=G.prop(G.inst[fl],'Size')
        o=(fcf[1],fcf[2]+fs[2]/2,fcf[3]); r=fcf[4]
        # local axes: right = column0 (r[0],r[3],r[6]), look = -column2
        R=(r[0],r[3],r[6]); B=(r[2],r[5],r[8])
        print('=====',path(m['id']),'floor top',round(o[1],2),'size',[round(fs[1],1),round(fs[3],1)],'R',[round(x,2) for x in R],'attrs',{k:G.val(v) for k,v in m['attrs'].items()})
        agg={}
        for c,dp in desc(m['id']):
            x=G.inst[c]
            if x['cls'] not in BASEPART: 
                if x['cls']=='Model' and ('GwShopClerk' in (x.get('tags') or []) or x['name'].startswith('Table') or x['name'] in ('AutoDoor','GrillTable','PlasticTable')):
                    pass
                continue
            cf=G.prop(x,'CFrame'); s=G.prop(x,'Size')
            if not cf: continue
            d=(cf[1]-o[0],cf[2]-o[1],cf[3]-o[2])
            lx=d[0]*R[0]+d[1]*R[1]+d[2]*R[2]; lz=d[0]*B[0]+d[1]*B[1]+d[2]*B[2]
            n=x['name']; par=G.inst[x['parent']]['name']
            key=n
            agg.setdefault(key,[]).append((round(lx,1),round(d[1],1),round(lz,1),round(s[1],1),round(s[2],1),round(s[3],1),par, x['cls']=='Seat', G.prop(x,'CanCollide'), G.prop(x,'Transparency')))
        for k,v in sorted(agg.items(), key=lambda kv: kv[0]):
            big=[e for e in v if max(e[3],e[5])>=1.0 or k in ('ChairSeat','StoolSeat','Seat','PosBase','OrderKiosk','KitchenPass','PassLedge','TapPost','EspressoBody','CuttingBoard','Counter','CounterTop','Door','TableTop','BarTop','Coals','Hood','Door_restroom','DoorLeaf')]
            if not big: continue
            print(' %-18s n=%-3d %s' % (k[:18], len(v), '; '.join('(%s,%s,%s|%sx%sx%s %s%s%s)'%(e[0],e[1],e[2],e[3],e[4],e[5],e[6][:10],' S' if e[7] else '', ' nc' if e[8]==False else '') for e in big[:6])))
