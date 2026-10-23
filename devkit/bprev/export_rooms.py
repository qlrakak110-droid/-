# export_rooms.py [group ...]: export every venue room of tools/venues/rooms.json as fixtures <group>_<room> (+ _room.luau spec)
import sys, os, json, argparse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import export as E
from place import load
d = json.load(open('/home/user/-/tools/venues/rooms.json', encoding='utf-8'))
only = set(sys.argv[1:])
G = load()
for v in d['venues']:
    if only and v['group'] not in only:
        continue
    for r in v['rooms']:
        key = '%s_%s' % (v['group'], r['room'])
        a = argparse.Namespace(key=key, path='/%s/%s' % (v['group'], v['name']), id=None, margin=6)
        try:
            E.one(G, a)
        except SystemExit as e:
            print(key, e); continue
        open(E.SP + '/bprev/fx/%s_room.luau' % key, 'w', encoding='utf-8').write('return function(Vector3, CFrame)\nreturn { venue = %s, room = %s }\nend\n' % (json.dumps(v['name'], ensure_ascii=False), json.dumps(r['room'])))
