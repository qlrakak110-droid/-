import re,os
d='/home/user/-/src/ServerScriptService/GwangalliShopCrew/'
used=set()
pats=[r'say\(crew, [\w\.]+, "(\w+)"', r'lineT\(T, "(\w+)"', r'close\(p, T, "(\w+)"', r'dinerSay\(crew, [^"]*?"(\w+)"', r'"(greet[A-Z]\w*)"']
for f in os.listdir(d):
    if not f.endswith('.luau'): continue
    s=open(d+f,encoding='utf-8').read()
    for p in pats:
        for m in re.finditer(p,s):
            for g in m.groups():
                if g: used.add(g)
# conditional key choices like: if count > 1 then "orderAckMany" else "orderAck"
for f in os.listdir(d):
    if not f.endswith('.luau'): continue
    s=open(d+f,encoding='utf-8').read()
    for m in re.finditer(r'(?:Crew\.say\(crew, [\w\.]+, |lineT\(T, |close\(p, T, )(if [^,]*?)(?:,|\))', s):
        for k in re.findall(r'"(\w+)"', m.group(1)): used.add(k)
    for m in re.finditer(r'local key = (if [^\n]*)', s):
        for k in re.findall(r'"(\w+)"', m.group(1)): used.add(k)
    for m in re.finditer(r'\{ "(small\w+)"', s):
        used.add(m.group(1))
open('usedkeys.luau','w').write('return {'+','.join('"%s"'%k for k in sorted(used))+'}')
print(len(used))
