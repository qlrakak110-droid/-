exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/club/py/impl1.py').read().split("for c in kids[main]:")[0])
ppl=[c for c in kids[club] if G.inst[c]['name']=='People'][0]
for c in kids[ppl]:
    i=G.inst[c]
    a={k:G.val(v) for k,v in i['attrs'].items()}
    if a.get('Role') in ('dj','bartender','md') or i['name'].startswith(('DJ','MC','Bar')):
        hrp=[x for x in kids.get(c,[]) if G.inst[x]['name']=='HumanoidRootPart']
        print(i['name'], a, pos(G.inst[hrp[0]]) if hrp else None, list(i['tags']))
