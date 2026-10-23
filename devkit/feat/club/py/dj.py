exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/club/py/south.py').read().split("rows=[]")[0])
import sys
name=sys.argv[1]
root=[c for c in walk(club) if G.inst[c]['name']==name][0]
for x in walk(root):
    i=G.inst[x]
    bb=aabb(i) if i['cls'] in ('Part','MeshPart','WedgePart','UnionOperation','TrussPart','CornerWedgePart') else None
    extra=''
    if i['cls'] in ('Part','MeshPart'):
        m=pv(i,'Material'); col=pv(i,'Color3uint8') or pv(i,'Color')
        extra=str(col)
    print(i['cls'], path(x)[len(path(root)):][-70:], [round(v,1) for v in bb[0]]+[round(v,1) for v in bb[1]] if bb else '', extra, i['tags'] or '', {a:G.val(b) for a,b in i['attrs'].items()} or '')
