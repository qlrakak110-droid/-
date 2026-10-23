exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
for c in kids[5]:
    ci=G.inst[c]
    if 'bridge' in ci['name'].lower() or '대교' in ci['name']:
        print(ci['name'], ci['cls'], {k:G.val(v) for k,v in ci['attrs'].items()}, ci['tags'], 'ModelStreamingMode=',G.prop(ci,'ModelStreamingMode'), 'LevelOfDetail=', G.prop(ci,'LevelOfDetail'), len(kids.get(c,[])))
        for cc in kids.get(c,[])[:8]:
            x=G.inst[cc]; print('   ', x['name'], x['cls'], G.prop(x,'ModelStreamingMode'), G.prop(x,'LevelOfDetail'))
print([G.inst[c]['name'] for c in kids[5]][:60])
