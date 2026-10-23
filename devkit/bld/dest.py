exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
for i in G.inst[1:]:
    if 'Destination' in i['tags'] or i['name'].startswith('Destination'):
        a={k:G.val(v) for k,v in i['attrs'].items()}
        cf=G.prop(i,'CFrame')
        if cf:
            print('%-60s (%.1f,%.1f,%.1f) %s' % (path(i['id']).replace('DataModel/Workspace/Gwangalli/','')[-60:], cf[1],cf[2],cf[3], a.get('DisplayName','')))
