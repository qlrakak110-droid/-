exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
import json, math
shops=json.load(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/crew/py/shops_scan.json'))
dests=[]
for i in G.inst[1:]:
    if 'Destination' in (i.get('tags') or []):
        dn=i['attrs'].get('DisplayName'); dn=G.val(dn) if dn is not None else i['name']
        cf=G.prop(i,'CFrame')
        if cf: dests.append((dn,(cf[1],cf[2],cf[3])))
print('dests',len(dests))
want=['GS25 광안리점','스타벅스 광안리점','민락회타운','광안 포장마차','행복 돼지국밥','광안 PC방','광안 코인노래연습장','GS25 광안해변점 (켄트호텔 1F)','브롱스 광안리 (호메르스호텔 1F)','fondx 홍미당 (아쿠아펠리스 1F)','홈플러스 익스프레스 광안점']
for dn,p in dests:
    if dn in want:
        near=[(s['name'],round(math.hypot(s['floor'][0]-p[0],s['floor'][2]-p[2]),1)) for s in shops if math.hypot(s['floor'][0]-p[0],s['floor'][2]-p[2])<60]
        print(dn,[round(v,1) for v in p],near)
# GwJobStation tagged
js=[(path(i['id']),i['attrs']) for i in G.inst[1:] if 'GwJobStation' in (i.get('tags') or [])]
print('jobstations',len(js)); 
for j in js[:10]: print(j[0][-80:], {k:G.val(v) for k,v in j[1].items()})
# tags of interest counts
from collections import Counter
c=Counter()
for i in G.inst[1:]:
    for t in (i.get('tags') or []): c[t]+=1
print([ (t,n) for t,n in c.most_common() if any(k in t for k in ['Shop','Staff','Clerk','Seat','Venue','Job','Npc','NPC','Sit','Counter','Customer'])])
