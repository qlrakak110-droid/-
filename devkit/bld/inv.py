exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
import re, json, math
from collections import Counter, defaultdict
src=open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/v7all/gen/addons/zip/ReplicatedStorage/GwangalliBuildingsShared/StreetShops.luau',encoding='utf-8').read()
def block(name):
    i=src.index('SS.%s = {'%name); j=src.index('\n}\n',i); return src[i:j]
rules=re.findall(r'\{ "([^"]+)", "(\w+)", "(\w+)"( , exact = true| ?, exact = true)? \}', block('RULES'))
rules=[(a,b,c,bool(e)) for a,b,c,e in re.findall(r'\{ "([^"]+)", "(\w+)", "(\w+)"(, exact = true)? \}', block('RULES'))]
crules=re.findall(r'\{ "([^"]+)", "(\w+)", "(\w+)" \}', block('CONTENT_RULES'))
def classify(n):
    for k,t,m,ex in rules:
        if ex:
            if n.strip()==k: return t,m
        elif k in n: return t,m
def child(iid,nm):
    for c in kids.get(iid,[]):
        if G.inst[c]['name']==nm: return c
def desc(iid):
    out=[];st=[iid]
    while st:
        x=st.pop()
        for c in kids.get(x,[]): out.append(c); st.append(c)
    return out
PARTS=('Part','WedgePart','Seat','CornerWedgePart','TrussPart','MeshPart','VehicleSeat')
inv=defaultdict(Counter); shops=[]
for i in G.inst[1:]:
    if i['cls']=='Model' and child(i['id'],'ShopFloor') and child(i['id'],'Interior'):
        d=desc(i['id']); names=Counter(G.inst[x]['name'] for x in d if G.inst[x]['cls'] in PARTS)
        cands=[i['name']]+[G.inst[x]['name'][5:] for x in d if G.inst[x]['name'].startswith('Sign_')]
        t=None
        for n in cands:
            t=classify(n)
            if t: break
        if not t:
            for k,tt,m in crules:
                if any(nm.startswith(k) for nm in names): t=(tt,m); break
        t=t or ('none','none')
        a={k:G.val(v) for k,v in i['attrs'].items()}
        shops.append(dict(name=i['name'],type=t[0],menu=t[1],attrs=a,n=sum(names.values())))
        for k,v in names.items(): inv[t[0]][k]+=v
tc=Counter(s['type'] for s in shops)
print(tc.most_common())
json.dump(dict(shops=shops,inv={k:dict(v) for k,v in inv.items()}),open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/inv.json','w'),ensure_ascii=False,indent=0)
for t,c in inv.items():
    print('==',t,tc[t]); print(', '.join('%s:%d'%(k,v) for k,v in c.most_common(70)))
