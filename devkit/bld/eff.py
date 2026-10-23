import json, os, shutil, re
S='/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad'
src=S+'/bld/src'; eff=S+'/bld/eff'
if os.path.exists(eff): shutil.rmtree(eff)
# copy place sources stripping class suffix
for dp,dn,fn in os.walk(src):
    for f in fn:
        m=re.match(r'(.*)\.(Script|LocalScript|ModuleScript)\.luau$', f)
        rel=os.path.relpath(os.path.join(dp,m.group(1)), src)
        out=os.path.join(eff, rel+'.luau')
        os.makedirs(os.path.dirname(out), exist_ok=True)
        shutil.copy(os.path.join(dp,f), out)
d=json.load(open(S+'/v7all/gen/addons.json'))
n=0
for a in d:
    s=a.get('src')
    if not s: continue
    rel='/'.join(p.split(':')[0] for p in a['path'])+'/'+a['name']
    out=os.path.join(eff, rel+'.luau')
    os.makedirs(os.path.dirname(out), exist_ok=True)
    shutil.copy(S+'/v7all/'+s, out); n+=1
print('overlaid', n)
