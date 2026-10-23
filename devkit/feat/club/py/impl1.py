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
print('club', path(club))
main=[c for c in kids[club] if G.inst[c]['name']=='MainRoom'][0]
def bbox(root):
    st=[root]; mn=[1e9]*3; mx=[-1e9]*3; n=0
    while st:
        x=st.pop()
        for c in kids.get(x,[]): st.append(c)
        i=G.inst[x]
        p=pos(i); s=size(i)
        if p and s:
            n+=1
            for k in range(3):
                mn[k]=min(mn[k],p[k]-s[k]/2); mx[k]=max(mx[k],p[k]+s[k]/2)
    return n,[round(v,1) for v in mn],[round(v,1) for v in mx]
for c in kids[main]:
    i=G.inst[c]
    print(i['cls'], i['name'], bbox(c))
print('--- top club children')
for c in kids[club]:
    i=G.inst[c]; print(i['cls'], i['name'], len(kids.get(c,[])))
# particle textures
tex={}
for i in G.inst[1:]:
    if i['cls']=='ParticleEmitter' and under(i['id'],club) if False else i['cls']=='ParticleEmitter':
        t=pv(i,'Texture')
        par=G.inst[i['parent']]
        tex.setdefault(str(t),[]).append(par['name']+'/'+i['name']+str(list(par['tags'])))
for t,v in tex.items(): print('TEX',t,len(v),v[:4])
