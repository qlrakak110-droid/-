import sys, pickle, os
sys.path.insert(0, '/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/tools')
from gwpb import GWPB
G = GWPB('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/v7place/place.bin')
kids = {}
for i in G.inst[1:]:
    kids.setdefault(i['parent'], []).append(i['id'])
def path(iid):
    out=[]
    while iid:
        out.append(G.inst[iid]['name']); iid=G.inst[iid]['parent']
    return '/'.join(reversed(out))
