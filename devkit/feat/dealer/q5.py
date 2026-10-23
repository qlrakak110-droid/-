import sys
sys.path.insert(0, '/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/tools')
from gwpb import GWPB
G = GWPB('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/v7place/place.bin')
for i in G.inst[1:]:
    if i['name'] == '광안 오토 정비소 & 중고차' and i['cls']=='Model':
        print(i['id'], list(i['props'].keys()), i.get('attrs'), i.get('tags'))
        for k in i['props']:
            try: print(' ', k, G.prop(i,k))
            except Exception as e: print(' ', k, 'ERR', e)
