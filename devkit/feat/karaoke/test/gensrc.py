import os
T='/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/karaoke/test'
roots={'sh':'/home/user/-/src/ReplicatedStorage/GwangalliKaraokeShared','srv':'/home/user/-/src/ServerScriptService/GwangalliKaraokePlus','cli':'/home/user/-/src/StarterPlayer/StarterPlayerScripts/GwangalliKaraokePlus'}
out=['return {']
for k,d in roots.items():
    for f in sorted(os.listdir(d)):
        if f.endswith('.luau'):
            s=open(os.path.join(d,f),encoding='utf-8').read()
            eq='='*8
            while (']'+eq+']') in s: eq+='='
            out.append('["%s/%s"] = [%s[%s]%s],'%(k,f,eq,s,eq))
out.append('}')
open(T+'/srcs.luau','w',encoding='utf-8').write('\n'.join(out))
