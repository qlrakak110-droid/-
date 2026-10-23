import sys, json, re
s = open(sys.argv[1], encoding='utf-8').read().split('\n')[1]
arr = json.loads(s[len('const MODELS='):].rstrip(';'))
for M in arr:
    print('==', M['model'], M['label'], 'wheelbase', M['wheelbase'], 'npieces', len(M['pieces']), 'keys', [k for k in M if k not in ('pieces','data')])
    roles = {}
    for p in M['pieces']:
        roles.setdefault(p['r'], []).append(p)
    for r, ps in sorted(roles.items()):
        print('  ', r, len(ps), ' '.join(f"{p['n']}(m{p['m']},{p['g']},v{p['v']})" for p in ps)[:600])
    print('  wheels', M.get('wheels'))
    for k in M:
        if k not in ('pieces','data','wheels'): print('  ', k, json.dumps(M[k])[:300])
