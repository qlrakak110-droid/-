import os, re, sys
base='/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/eff'
res={}
for dp,dn,fn in os.walk(base):
    for f in fn:
        p=os.path.join(dp,f); rel=os.path.relpath(p,base)
        L=open(p,encoding='utf-8',errors='replace').read().split('\n')
        for i,l in enumerate(L):
            m=re.search(r'(\w+)\.Parent\s*=\s*(workspace|Workspace)\b\s*$', l.strip())
            if m:
                v=m.group(1)
                for j in range(max(0,i-12), i):
                    m2=re.search(re.escape(v)+r'\.Name\s*=\s*(".*?"|[\w\.]+)', L[j])
                    if m2:
                        res.setdefault(m2.group(1),set()).add(rel); break
                else:
                    res.setdefault('?'+v,set()).add(rel)
            for m3 in re.finditer(r'(?:Kit\.folder|folderIn|ensureFolder)\((?:workspace|Workspace),\s*("[^"]+"|[\w\.]+)', l):
                res.setdefault(m3.group(1),set()).add(rel)
            for m4 in re.finditer(r'(?:workspace|Workspace):FindFirstChild\("([A-Za-z_]+)"\)\s*or', l):
                res.setdefault('"'+m4.group(1)+'"(find-or)',set()).add(rel)
for k in sorted(res):
    print(k, '<-', ', '.join(sorted(res[k]))[:300])
