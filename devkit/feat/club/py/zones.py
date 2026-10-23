exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/club/py/impl1.py').read().split("for c in kids[main]:")[0])
n=0
for i in G.inst[1:]:
    if 'ClubZone' in i['tags'] or i['name'].startswith('Zone_'):
        a={k:G.val(v) for k,v in i['attrs'].items()}
        print(i['cls'], path(i['id'])[-70:], a, pos(i), size(i), list(i['tags']))
        n+=1
        if n>14: break
for i in G.inst[1:]:
    if 'ClubRuntime' in i['tags']:
        print('RUNTIME', path(i['id'])[-60:], {k:G.val(v) for k,v in list(i['attrs'].items())[:8]})
