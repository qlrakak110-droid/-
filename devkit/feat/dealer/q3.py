exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
gid=[x['id'] for x in G.inst[1:] if x['name']=='garage' and G.inst[x['parent']]['name']=='Gwangalli'][0]
st=[gid]; out=[]
while st:
    i=st.pop()
    for c in kids.get(i,[]):
        st.append(c)
        x=G.inst[c]
        if x['cls']=='ProximityPrompt':
            pr={k:G.prop(x,k) for k in ('ActionText','ObjectText','KeyboardKeyCode','MaxActivationDistance','HoldDuration','Enabled','RequiresLineOfSight','UIOffset','Exclusivity')}
            print(path(c)[len('DataModel/Workspace/Gwangalli/garage/'):], pr)
