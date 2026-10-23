exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/club/py/impl1.py').read().split("for c in kids[main]:")[0])
from collections import Counter
# ClubLight kinds and positions
kinds={}
for i in G.inst[1:]:
    if 'ClubLight' in i['tags']:
        a={k:G.val(v) for k,v in i['attrs'].items()}
        kinds.setdefault(a.get('Kind'),[]).append((i['name'],pos(i),a.get('Room') or a.get('Zone')))
for k,v in kinds.items(): print('KIND',k,len(v),v[:3])
# parts in main room high band (truss)
c=Counter(); ex={}
st=[main]
while st:
    x=st.pop()
    for ch in kids.get(x,[]): st.append(ch)
    i=G.inst[x]; p=pos(i); s=size(i)
    if p and s and i['cls'] in ('Part','MeshPart','WedgePart','UnionOperation') and 26<p[1]<34:
        par=G.inst[i['parent']]['name']
        key=par+'/'+i['name']; c[key]+=1; ex.setdefault(key,[]).append((p,s))
for k,n in c.most_common(40): print(n,k,ex[k][0],ex[k][-1])
