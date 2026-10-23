exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/club/py/south.py').read().split("rows=[]")[0])
for i in G.inst[1:]:
    if 'ClubTable' in i['tags']:
        a={k:G.val(v) for k,v in i['attrs'].items()}
        lo=[1e9]*3; hi=[-1e9]*3; sp=None; nums=[]; top=None
        for x in walk(i['id']):
            j=G.inst[x]
            if j['cls'] in ('Part','MeshPart','WedgePart','UnionOperation'):
                bb=aabb(j)
                if bb:
                    for k in range(3): lo[k]=min(lo[k],bb[0][k]); hi[k]=max(hi[k],bb[1][k])
                if j['name']=='ServePoint': sp=[round(v,1) for v in cf(j)[1:4]]
                if 'Number' in j['name'] or 'Sign' in j['name']: nums.append((j['name'],[round(v,1) for v in bb[0]],[round(v,1) for v in bb[1]]))
                if j['name'] in ('TableTop','Top','VIPTableTop','TableSlab'): top=round(bb[1][1],2)
        print(a.get('TableId'), a.get('TableType'), i['name'], [round(v,1) for v in lo],[round(v,1) for v in hi], 'serve',sp, 'top',top, nums[:3])
print('--- npcs')
for i in G.inst[1:]:
    if 'ClubNPC' in i['tags']:
        a={k:G.val(v) for k,v in i['attrs'].items()}
        if a.get('Role') in ('bartender','dj','md','staff'):
            print(i['name'], a.get('Role'), a.get('Anim'), a.get('Zone'), [round(v,1) for v in (cf(i) or [0,0,0,0])[1:4]] if cf(i) else '')
