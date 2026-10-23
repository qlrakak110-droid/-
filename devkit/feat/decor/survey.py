exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
import json, math
out={}
def cfof(i):
    cf=G.prop(i,'CFrame'); return cf
def desc(iid):
    for c in kids.get(iid,[]):
        yield c
        yield from desc(c)
tpl=[i for i in G.inst[1:] if path(i['id']).startswith('DataModel/ServerStorage/GwangalliHomes/HomeUnit_') and path(i['id']).count('/')==3]
for t in tpl:
    tid=t['id']; name=t['name']
    root=[c for c in kids[tid] if G.inst[c]['name']=='UnitRoot'][0]
    rcf=cfof(G.inst[root]); ro=(rcf[1],rcf[2],rcf[3]); rr=rcf[4]
    rec={'attrs':{k:str(G.val(v)) for k,v in t['attrs'].items()},'rootRot':[round(x,3) for x in rr],'floors':[],'walls':0,'lights':[],'slots':[],'interacts':[],'doors':[],'ceilY':None,'props':[], 'fixtures':[], 'rooms':{}}
    for d in desc(tid):
        i=G.inst[d]; a={k:G.val(v) for k,v in i['attrs'].items()}
        cf=cfof(i); sz=G.prop(i,'Size')
        loc=None
        if cf: loc=(round(cf[1]-ro[0],2),round(cf[2]-ro[1],2),round(cf[3]-ro[2],2))
        p=path(d)[len(path(tid))+1:]
        if i['cls'] in ('Part','MeshPart','WedgePart','UnionOperation','Seat') and sz:
            szv=(round(sz[1],2),round(sz[2],2),round(sz[3],2))
            if a.get('Surface')=='floor' or i['name'].startswith('Floor'):
                rec['floors'].append({'n':i['name'],'room':a.get('Room'),'pos':loc,'size':szv})
                r=a.get('Room') or i['name']
                x0,x1=loc[0]-szv[0]/2,loc[0]+szv[0]/2; z0,z1=loc[2]-szv[2]/2,loc[2]+szv[2]/2
                if r in rec['rooms']:
                    b=rec['rooms'][r]; rec['rooms'][r]=[min(b[0],x0),min(b[1],z0),max(b[2],x1),max(b[3],z1),max(b[4],loc[1]+szv[1]/2)]
                else: rec['rooms'][r]=[x0,z0,x1,z1,loc[1]+szv[1]/2]
            if a.get('Surface')=='wall': rec['walls']+=1
            if a.get('Surface')=='light': rec['lights'].append({'n':i['name'],'room':a.get('Room'),'pos':loc})
            if i['name']=='Ceiling' and p.startswith('Shell'):
                y=loc[1]-szv[1]/2; rec['ceilY']=y if rec['ceilY'] is None else min(rec['ceilY'],y)
            if 'HomeInteract' in i['tags']:
                rec['interacts'].append({'kind':a.get('Kind'),'label':a.get('Label'),'path':p,'pos':loc,'size':szv})
        if i['cls']=='Model' and 'FurnitureSlot' in i['tags']:
            base=[c for c in kids.get(d,[]) if G.inst[c]['name']=='SlotBase']
            bp=None
            if base:
                bcf=cfof(G.inst[base[0]]); bp=(round(bcf[1]-ro[0],2),round(bcf[2]-ro[1],2),round(bcf[3]-ro[2],2)); 
                look=(-bcf[4][2], -bcf[4][5], -bcf[4][8])
                yaw=round(math.degrees(math.atan2(-look[0],-look[2])))
            rec['slots'].append({'id':a.get('SlotId'),'cat':a.get('Category'),'def':a.get('DefaultItem'),'fp':str(a.get('Footprint')),'rot':a.get('Rotate'),'room':a.get('Room'),'pos':bp,'yaw':yaw if base else None})
        if i['cls']=='Model' and (i['name']=='Door' or i['name'].startswith('Door_')):
            rec['doors'].append(p)
        if i['cls']=='Model' and p.count('/')==1 and p.startswith('Props/'):
            rec['props'].append(i['name'])
        if i['cls']=='Model' and p.count('/')==1 and p.startswith('Fixtures/'):
            rec['fixtures'].append(i['name'])
    out[name]=rec
json.dump(out,open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/feat/decor/templates.json','w'),ensure_ascii=False,indent=1)
for n,r in out.items():
    print('=====',n,r['attrs'].get('Rooms'),'ceilY',r['ceilY'],'rootRot',r['rootRot'])
    for k,b in r['rooms'].items(): print('  room',k,[round(x,1) for x in b])
    print('  slots:',len(r['slots']),' interacts:',[(x['kind'],x['label']) for x in r['interacts']])
    print('  doors:',len(r['doors']),' props:',r['props'])
    print('  fixtures:',r['fixtures'])
    for s in r['slots']: print('   slot',s)
