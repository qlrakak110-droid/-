exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
gw=[x['id'] for x in G.inst[1:] if x['name']=='Gwangalli' and x['cls']=='Model'][0]
print([G.inst[c]['name'] for c in kids[gw]])
found={}
PART={'Part','MeshPart','WedgePart','UnionOperation','TrussPart','CornerWedgePart','Seat','VehicleSeat'}
def nparts(i):
    st=[i]; n=0
    while st:
        x=st.pop()
        for c in kids.get(x,[]):
            if G.inst[c]['cls'] in PART: n+=1
            st.append(c)
    return n
def walk(i):
    for c in kids.get(i,[]):
        x=G.inst[c]
        a=x['attrs']
        if x['cls']=='Model' and 'VehicleKind' in a:
            k=G.val(a['VehicleKind'])
            nd = G.val(a['NoDrive']) if 'NoDrive' in a else None
            p=path(c)
            traffic = 'Traffic' in p
            if k not in found and not nd and not traffic:
                found[k]=(x['name'],p[:120],nparts(c),{kk:G.val(v) for kk,v in a.items()},x['tags'])
        walk(c)
walk(gw)
for k,v in found.items(): print(k,v)
