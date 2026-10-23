import json,collections
S='/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad'
d=json.load(open(S+'/bld/hg/dump.json'))['garage']
byid={x['id']:x for x in d}
kids=collections.defaultdict(list)
for x in d: kids[x.get('par')].append(x['id'])
def cnt(i):
    return 1+sum(cnt(c) for c in kids[i])
def parts(i):
    n=0
    for c in kids[i]:
        if byid[c]['cls'] in ('Part','MeshPart','WedgePart','UnionOperation','TrussPart','CornerWedgePart','Seat','VehicleSeat'): n+=1
        n+=parts(c)
    return n
root=d[0]
print(root['name'], root['cls'], root.get('attrs'), root.get('tags'))
def show(i,depth,maxd):
    x=byid[i]
    if depth>maxd: return
    if x['cls'] in ('Model','Folder') or x.get('tags') or x.get('attrs'):
        print('  '*depth, x['cls'], x['name'], 'n=%d'%cnt(i), 'p=%d'%parts(i), x.get('pos'), x.get('size'), x.get('tags') or '', x.get('attrs') or '')
    for c in kids[i]:
        if byid[c]['cls'] in ('Model','Folder') or byid[c].get('tags') or byid[c].get('attrs'):
            show(c,depth+1,maxd)
show(root['id'],0,3)
