import sys, json
sys.path.insert(0,'/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/tools')
from gwpb import GWPB
G=GWPB('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/v7place/place.bin')
kids={}
for i in G.inst[1:]: kids.setdefault(i['parent'],[]).append(i['id'])
def path(iid):
    out=[]
    while iid: out.append(G.inst[iid]['name']); iid=G.inst[iid]['parent']
    return '/'.join(reversed(out))
def desc(iid):
    st=[iid]; out=[]
    while st:
        x=st.pop(); out.append(x); st.extend(kids.get(x,[]))
    return out
def fmt(i):
    cf=G.prop(i,'CFrame'); sz=G.prop(i,'Size')
    s=''
    if cf and cf[0]=='CF':
        m=cf[4]
        s+=' @(%.2f,%.2f,%.2f) look(%.2f,%.2f,%.2f)'%(cf[1],cf[2],cf[3],-m[2],-m[5],-m[8])
    if sz and sz[0]=='V3': s+=' sz(%.2f,%.2f,%.2f)'%(sz[1],sz[2],sz[3])
    a={k:G.val(v) for k,v in i['attrs'].items()}
    return '%s [%s]%s%s%s'%(i['name'],i['cls'],s,(' '+str(a)) if a else '',(' tags='+','.join(i['tags'])) if i['tags'] else '')
mode=sys.argv[1]
if mode=='find':
    pat=sys.argv[2]
    for i in G.inst[1:]:
        p=path(i['id'])
        if pat in p: print(p, '|', fmt(i))
elif mode=='sub':
    pat=sys.argv[2]; props=sys.argv[3].split(',') if len(sys.argv)>3 else []
    ids=[i['id'] for i in G.inst[1:] if path(i['id']).endswith(pat)]
    for r in ids[:1]:
        base=path(r)
        for x in desc(r):
            i=G.inst[x]
            extra=''
            for pn in props:
                v=G.prop(i,pn)
                if v is not None: extra+=' %s=%r'%(pn,v)
            print(path(x)[len(base):] or '/', '|', fmt(i)+extra)
