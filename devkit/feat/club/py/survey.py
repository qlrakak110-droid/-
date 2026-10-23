exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
def pv(i,k):
    v=i['props'].get(k)
    return G.val(v[1]) if v else None
def cf(i):
    c=pv(i,'CFrame')
    return c if c and c[0]=='CF' else None
def size(i):
    s=pv(i,'size') or pv(i,'Size')
    if s and s[0]=='V3': return tuple(round(x,2) for x in s[1:4])
    return None
club=None
for i in G.inst[1:]:
    if i['name']=='CLUB OCEAN 광안': club=i['id']; print('club', path(club), i['cls'])
main=[c for c in kids[club] if G.inst[c]['name']=='MainRoom'][0]
print('MainRoom children:', sorted(set(G.inst[c]['name'] for c in kids[main])))
def walk(r):
    st=[r]
    while st:
        x=st.pop(); yield x; st.extend(kids.get(x,[]))
big=[]
for x in walk(main):
    i=G.inst[x]
    if i['cls'] in ('Part','MeshPart','WedgePart','UnionOperation'):
        s=size(i); c=cf(i)
        if s and c and max(s)>=30:
            big.append((path(x)[len(path(main)):], tuple(round(v,1) for v in c[1:4]), s, i['cls']))
for b in sorted(big)[:80]: print(b)
