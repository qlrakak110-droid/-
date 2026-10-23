exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
for i in G.inst[1:]:
    if i['cls']=='ProximityPrompt':
        print(i['name'], {k:G.val(v[1]) for k,v in i['props'].items()})
        break
