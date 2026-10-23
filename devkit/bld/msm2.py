exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
from collections import Counter
c=Counter()
for i in G.inst[1:]:
    if i['cls']=='Model' and 'ModelStreamingMode' in i['props']:
        c[i['name']]+=1
print(c.most_common(30))
import json
e=json.load(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/v7all/gen/enums.json'))
print(type(e), list(e)[:5] if isinstance(e,dict) else e[:2])
for k in (e if isinstance(e,dict) else []):
    if 'ModelStreaming' in k: print(k, e[k])
