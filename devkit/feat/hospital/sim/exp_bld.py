import sys, os
BP='/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bprev'
sys.path.insert(0, BP)
import export as E
from place import load
G = load()
iid = 306912  # 광안 메디컬 의원 (건물)
fx = dict(chain=[dict(cls='DataModel',name='DataModel',id=1),dict(cls='Workspace',name='Workspace',id=2),dict(cls='Model',name='Gwangalli',id=5),dict(cls='Model',name='hospital',id=304540)], tree=E.fixture(G, iid))
open(sys.argv[1],'w').write('return function(Vector3, Color3, CFrame)\nreturn ' + E.lua(fx) + '\nend\n')
print('ok')
