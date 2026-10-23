exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
for iid in (304540, 304541, 306912):
    i=G.inst[iid]; print(path(iid), {k:G.val(v) for k,v in i['attrs'].items()}, i['tags'])
def show(iid,d,maxd):
    for c in kids.get(iid,[]):
        ci=G.inst[c]
        a={k:G.val(v) for k,v in ci['attrs'].items()}
        cf=G.prop(ci,'CFrame'); sz=G.prop(ci,'Size')
        s=''
        if cf and sz and sz[0]=='V3': s=' @(%.2f,%.2f,%.2f) sz(%.2f,%.2f,%.2f)'%(cf[1],cf[2],cf[3],sz[1],sz[2],sz[3])
        print('  '*d+'%s [%s]%s %s %s'%(ci['name'],ci['cls'],s,a if a else '', ci['tags'] if ci['tags'] else ''))
        if d<maxd: show(c,d+1,maxd)
show(306912,1,2)
# 2F children names only (parts)
from collections import Counter
for c in kids[304541]:
    if G.inst[c]['name'] in ('1F','2F'):
        print(G.inst[c]['name'], {k:G.val(v) for k,v in G.inst[c]['attrs'].items()}, Counter(G.inst[x]['name'] for x in kids[c] if G.inst[x]['cls']!='Model'))
