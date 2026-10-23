exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
import collections,re
PART={'Part','MeshPart','WedgePart','UnionOperation','TrussPart','CornerWedgePart','Seat','VehicleSeat'}
def nparts(i):
    st=[i]; n=0
    while st:
        x=st.pop()
        for c in kids.get(x,[]):
            if G.inst[c]['cls'] in PART: n+=1
            st.append(c)
    return n
cm=collections.Counter(); ex={}
for x in G.inst[1:]:
    a=x['attrs']
    if x['cls']=='Model' and ('VehicleKind' in a or 'CarModel' in a or 'GwCarModel' in a):
        p=path(x['id'])
        key=((G.val(a['VehicleKind']) if 'VehicleKind' in a else None), (G.val(a['CarModel']) if 'CarModel' in a else (G.val(a['GwCarModel']) if 'GwCarModel' in a else None)), x['name'][:20] if 'LotCar' not in x['name'] else 'LotCar_*', '/'.join(p.split('/')[:4]))
        cm[key]+=1
        if key not in ex: ex[key]=(x['id'],nparts(x['id']))
for k,v in sorted(cm.items(), key=lambda t:-t[1])[:60]: print(v,k,ex[k])
print('---- dealer-ish names')
pat=re.compile('중고|렌터|렌트|오토바이|바이크|모터|Motor|Bike|Dealer|딜러|대리점|매매|Rent|Scooter|스쿠터')
seen=set()
for x in G.inst[1:]:
    if pat.search(x['name']) and x['cls'] in ('Model','Folder','Part','MeshPart'):
        p=path(x['id'])
        k='/'.join(p.split('/')[:5])
        if k in seen: continue
        seen.add(k); print(x['cls'],p[:160])
