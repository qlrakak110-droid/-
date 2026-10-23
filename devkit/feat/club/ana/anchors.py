exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
def pv(i,k):
    v=i['props'].get(k)
    return G.val(v[1]) if v else None
def fmt(x):
    try:
        if isinstance(x,(list,tuple)): return '('+','.join('%.2f'%float(a) for a in x[:12])+')'
    except Exception: pass
    return str(x)[:200]
want_tags={'ClubShowAnchor','ClubRuntime','ClubVenue','ClubDoor','ClubLaser','ClubZone'}
cnt={}
for i in G.inst[1:]:
    for t in i['tags']:
        cnt[t]=cnt.get(t,0)+1
print({k:v for k,v in cnt.items() if 'Club' in k})
for i in G.inst[1:]:
    tg=set(i['tags'])
    if tg & {'ClubShowAnchor','ClubRuntime','ClubVenue','ClubZone'}:
        print(i['cls'], path(i['id']), 'tags',i['tags'], 'CF',fmt(pv(i,'CFrame')), 'Size',fmt(pv(i,'size') or pv(i,'Size')), {k:G.val(v) for k,v in i['attrs'].items()})
