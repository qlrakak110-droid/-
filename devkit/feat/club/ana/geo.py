exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
def pv(i,k):
    v=i['props'].get(k)
    return G.val(v[1]) if v else None
def pos(i):
    cf=pv(i,'CFrame')
    if cf and cf[0]=='CF': return tuple(round(x,1) for x in cf[1:4])
    return None
def size(i):
    s=pv(i,'size') or pv(i,'Size')
    if s and s[0]=='V3': return tuple(round(x,2) for x in s[1:4])
    return None
club=None
for i in G.inst[1:]:
    if 'ClubVenue' in i['tags']: club=i['id']
def under(iid, root):
    while iid:
        if iid==root: return True
        iid=G.inst[iid]['parent']
    return False
# kinds of ClubLight
kinds={}
for i in G.inst[1:]:
    if 'ClubLight' in i['tags']:
        k=G.val(i['attrs'].get('Kind')) if i['attrs'].get('Kind') else None
        kinds.setdefault(str(k),[]).append(i)
for k,v in sorted(kinds.items(), key=lambda x:-len(x[1])):
    ps=[pos(x) for x in v if pos(x)]
    xs=[p[0] for p in ps]; ys=[p[1] for p in ps]; zs=[p[2] for p in ps]
    print('Kind',k,len(v), 'x %.1f..%.1f y %.1f..%.1f z %.1f..%.1f'%(min(xs),max(xs),min(ys),max(ys),min(zs),max(zs)) if ps else '', 'eg', path(v[0]['id'])[-90:], {a:G.val(b) for a,b in v[0]['attrs'].items()})
print('--- lasers')
for i in G.inst[1:]:
    if 'ClubLaser' in i['tags']:
        par=G.inst[i['parent']]
        print(i['cls'], path(i['id'])[-80:], {a:G.val(b) for a,b in i['attrs'].items()}); break
for i in G.inst[1:]:
    if i['cls'] in('Part','MeshPart') and under(i['id'],club) and ('Laser' in i['name']):
        print(' L', path(i['id'])[-80:], pos(i), size(i), {a:G.val(b) for a,b in i['attrs'].items()}, i['tags'])
print('--- route')
for i in G.inst[1:]:
    if i['name'].startswith('WP') and under(i['id'],club):
        print(' ', path(i['id'])[-60:], pos(i))
    if i['name']=='ParadeRoute': print('route attrs', {a:G.val(b) for a,b in i['attrs'].items()})
print('--- tables')
for i in G.inst[1:]:
    if 'ClubTable' in i['tags']:
        a={k:G.val(v) for k,v in i['attrs'].items()}
        sp=None
        stack=[i['id']]
        kids2={}
        print(' ', a.get('TableId'), a.get('TableType'), a.get('Capacity'), path(i['id'])[-70:])
