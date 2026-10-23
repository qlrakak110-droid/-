exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/club/py/impl1.py').read().split("for c in kids[main]:")[0])
for i in G.inst[1:]:
    if 'ClubTable' in i['tags']:
        a={k:G.val(v) for k,v in i['attrs'].items()}
        if a.get('TableId') not in ('G2','B3','T1','S2','D1'): continue
        print('==', a, i['cls'], path(i['id'])[-60:])
        st=[i['id']]
        while st:
            x=st.pop()
            for c in kids.get(x,[]): st.append(c)
            j=G.inst[x]
            if j['cls'] in ('Part','MeshPart','Seat','UnionOperation','WedgePart'):
                print('   ', j['cls'], j['name'], pos(j), size(j))
