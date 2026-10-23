import re, json, sys
items = []
cur = None
for line in open('catalog_dump.txt', encoding='utf-8'):
    line = line.rstrip('\n')
    if line.startswith('## '):
        m = re.match(r'## (\S+)\s+"([^"]+)"\s+cat=(\S+) kind=(\S+) wall=(\S+) flat=(\S+) mountY=(\S+) fixed=(\S+)\s+w=(\S+) d=(\S+) h=(\S+)\s+parts=(\d+)\s+colors=(.*?)\s+fixtureTag=(\S+)', line)
        cur = dict(id=m[1], name=m[2], cat=m[3], kind=m[4], wall=m[5], flat=m[6], mountY=float(m[7]), fixed=m[8], w=float(m[9]), d=float(m[10]), h=float(m[11]), n=int(m[12]), colors=m[13].split(' '), tag=m[14], parts=[])
        items.append(cur)
    elif line.startswith('    ') and cur:
        s = line.strip()
        name = s.split()[0]
        cls = s.split()[1]
        pos = re.search(r'pos\(([^)]*)\)', s)[1]
        size = re.search(r'size\(([^)]*)\)', s)[1]
        tr = float(re.search(r'tr=(\S+)', s)[1])
        mat = re.search(r'mat=(\S+)', s)[1]
        extra = re.search(r' \+(\S+)', s)
        tags = re.search(r'tags=(\S+)', s)
        attrs = re.search(r'attrs\{([^}]*)\}', s)
        rot = re.search(r'rot\(([^)]*)\)', s)
        coll = re.search(r'coll=(\S+)', s)[1]
        cur['parts'].append(dict(name=name, cls=cls, pos=pos, size=size, tr=tr, mat=mat, extra=extra[1] if extra else '', tags=tags[1] if tags else '', attrs=attrs[1] if attrs else '', rot=rot[1] if rot else '', coll=coll, primary='[PRIMARY]' in s, shape='Cylinder' if ' Cylinder ' in s else ('Ball' if ' Ball ' in s else '')))
out = []
for it in items:
    g = []
    for p in it['parts']:
        if p['primary']:
            continue
        y = [float(v) for v in p['pos'].split(',')]
        sz = [float(v) for v in p['size'].split(',')]
        if p['cls'] == 'Seat':
            g.append('Seat#%s c(%s) top=%.2f' % (p['attrs'].replace('Index=', ''), p['pos'], y[1] + sz[1] / 2 if not p['rot'] else y[1] + 0.15))
        elif p['name'] == 'LieSpot':
            g.append('LieSpot(%s)' % p['pos'])
        elif 'GwB_Screen' in p['tags'] or p['attrs'].find('ScreenKind') >= 0:
            g.append('Screen[%s] c(%s) s(%s)' % (p['attrs'], p['pos'], p['size']))
        elif 'GwB_Lamp' in p['tags']:
            g.append('Lamp %s c(%s) %s' % (p['name'], p['pos'], p['extra']))
        elif 'GwB_Spin' in p['tags']:
            g.append('Spin %s c(%s) [%s]' % (p['name'], p['pos'], p['attrs']))
        elif 'GwB_Water' in p['tags']:
            g.append('Water %s c(%s)' % (p['name'], p['pos']))
        elif 'Hinge' in p['attrs']:
            g.append('Door %s c(%s) s(%s) [%s]' % (p['name'], p['pos'], p['size'], p['attrs']))
        elif p['name'] == 'Hit' or (p['coll'] == 'true' and p['tr'] < 1):
            g.append('%s%s box c(%s) s(%s)' % ('Hit' if p['name'] == 'Hit' else 'Solid:' + p['name'], '', p['pos'], p['size']))
        elif p['name'] not in ('Part',) and p['name'] != 'Hit':
            g.append('%s c(%s)%s%s' % (p['name'], p['pos'], ' tr=%.2f' % p['tr'] if p['tr'] > 0 else '', (' ' + p['extra']) if p['extra'] else ''))
        elif p['extra']:
            g.append('Part c(%s) %s' % (p['pos'], p['extra']))
    vis = sum(1 for p in it['parts'] if p['tr'] < 1)
    snd = [p['extra'] for p in it['parts'] if p['primary'] and p['extra']]
    out.append(dict(id=it['id'], name=it['name'], cat=it['cat'], kind=it['kind'], tag=it['tag'], wall=it['wall'], mountY=it['mountY'], fixed=it['fixed'], w=it['w'], d=it['d'], h=it['h'], nparts=it['n'], visible=vis, colors=it['colors'], special=g, baseSound=snd))
json.dump(out, open('catalog_summary.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
for o in out:
    print('%-16s %-16s k=%-10s w%.1f d%.1f h%.1f my%.1f parts=%d vis=%d cw=%d %s' % (o['id'], o['name'], o['kind'], o['w'], o['d'], o['h'], o['mountY'], o['nparts'], o['visible'], len(o['colors']), ' | '.join(o['special'])[:600] + (' snd=' + ','.join(o['baseSound']) if o['baseSound'] else '')))
