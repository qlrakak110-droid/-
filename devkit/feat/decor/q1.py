exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
for i in G.inst[1:]:
    if i['cls'] in ('Script','LocalScript'):
        p=path(i['id'])
        d=G.prop(i,'Disabled'); e=G.prop(i,'Enabled')
        print(i['cls'], p, 'Disabled=',d, 'Enabled=',e)
