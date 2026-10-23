exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
import sys
target=sys.argv[1]; maxd=int(sys.argv[2]) if len(sys.argv)>2 else 3
ids=[i['id'] for i in G.inst[1:] if path(i['id']).endswith(target)]
def show(iid, d):
    i=G.inst[iid]
    cf=G.prop(i,'CFrame'); sz=G.prop(i,'Size')
    s=''
    if cf and sz and sz[0]=='V3': s=' @(%.1f,%.1f,%.1f) sz(%.1f,%.1f,%.1f)'%(cf[1],cf[2],cf[3],sz[1],sz[2],sz[3])
    a={k:G.val(v) for k,v in i['attrs'].items()}
    nk=len(kids.get(iid,[]))
    print('  '*d + '%s [%s]%s%s%s%s'%(i['name'], i['cls'], s, (' kids=%d'%nk) if nk else '', (' '+str(a)) if a else '', (' tags='+','.join(i['tags'])) if i['tags'] else ''))
    if d<maxd:
        from collections import Counter
        ch=kids.get(iid,[])
        if len(ch)>40:
            c=Counter((G.inst[x]['name'],G.inst[x]['cls']) for x in ch)
            for (n,cl),k in c.most_common(40): print('  '*(d+1)+'%s [%s] x%d'%(n,cl,k))
        else:
            for c in ch: show(c, d+1)
for iid in ids[:1]:
    print(path(iid)); show(iid,0)
