exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
import sys
target=sys.argv[1]
ids=[i['id'] for i in G.inst[1:] if path(i['id']).endswith(target)]
sid=ids[0]
def walk(iid, d, rel):
    i=G.inst[iid]
    cf=G.prop(i,'CFrame'); sz=G.prop(i,'Size')
    s=''
    if cf and sz and sz[0]=='V3':
        s=' @(%.2f,%.2f,%.2f) sz(%.2f,%.2f,%.2f)'%(cf[1]-rel[0],cf[2]-rel[1],cf[3]-rel[2],sz[1],sz[2],sz[3])
        m=G.prop(i,'Material'); c=G.prop(i,'Color'); t=G.prop(i,'Transparency')
        s+=' m=%s c=%s t=%s'%(m, c, t)
        r=cf[4]; 
        if abs(r[0]-1)>1e-3 or abs(r[4]-1)>1e-3: s+=' rot=%s'%[round(x,2) for x in r]
    a={k:G.val(v) for k,v in i['attrs'].items()}
    print('  '*d+'%s [%s]%s%s'%(i['name'],i['cls'],s,(' '+str(a)) if a else ''))
    for c in kids.get(iid,[]): walk(c,d+1,rel)
fl=[c for c in kids[sid] if G.inst[c]['name']=='ShopFloor'][0]
fcf=G.prop(G.inst[fl],'CFrame')
rel=(fcf[1],fcf[2],fcf[3])
print(path(sid),'floor',rel)
walk(sid,0,rel)
