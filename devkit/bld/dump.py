exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
import os
base='/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/src'
os.makedirs(base, exist_ok=True)
lst=[]
for i in G.inst[1:]:
    if i['cls'] in ('Script','LocalScript','ModuleScript'):
        p=path(i['id']).replace('DataModel/','')
        src=G.val(i['props']['Source'][1]) if 'Source' in i['props'] else ''
        if not isinstance(src,str): src=str(src)
        fp=os.path.join(base, p + ('.' + i['cls'] + '.luau'))
        os.makedirs(os.path.dirname(fp), exist_ok=True)
        open(fp,'w').write(src)
        lst.append((i['cls'], p, len(src.splitlines())))
for x in lst: print(*x)
