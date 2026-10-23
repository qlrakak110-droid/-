import sys
exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
PART={'Part','MeshPart','WedgePart','UnionOperation','TrussPart','CornerWedgePart','Seat','VehicleSeat'}
def desc(i):
    st=[i]; n=0; mp=0
    while st:
        x=st.pop()
        for c in kids.get(x,[]):
            cl=G.inst[c]['cls']
            if cl in PART: n+=1
            if cl=='MeshPart': mp+=1
            st.append(c)
    return n,mp
names=('GwangalliCarModels','GwangalliDriveTemplates','GwangalliShowroom','GwangalliBikes','GwangalliBikeShop','GwangalliPlayerCars','GwangalliTaxis','Cars','Vehicles')
for x in G.inst[1:]:
    if x['name'] in names:
        print(x['id'],x['cls'],path(x['id']),len(kids.get(x['id'],[])))
        for c in kids.get(x['id'],[])[:40]:
            ci=G.inst[c]; n,mp=desc(c)
            print('   ',ci['cls'],ci['name'],'parts',n,'mesh',mp,{k:G.val(v) for k,v in ci['attrs'].items()},{k:v for k,v in ci.items() if k in ('tags',)})
