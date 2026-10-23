exec(open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/load.py').read())
from collections import defaultdict, Counter
import json
TAGS = ['GwShop','GwShopSpot','GwShopTable','GwShopPoint','GwShopClerk','ShopCounter','FurnitureSlot','HomeInteract','HomeEntrance','HomeEntranceCue','KaraokeRoom','PCStation','GwJobStation','VenueSpot','VenueStaff','VenueBoard','GymStation','SalonChair','ElevatorButton','HospitalBed','BowlingLane','ClubTable','ClubZone','ClubNPC','GarageTurntable','GarageDisplayCar','GaragePrompt','InteriorLight','AutoDoor','RoomDepth','RoomGlass','ZoneLOD','Destination','LEDScreen','ClubShowAnchor','ClubFloorTile']
by=defaultdict(list)
for i in G.inst[1:]:
    for t in i['tags']:
        if t in TAGS: by[t].append(i['id'])
out={}
for t in TAGS:
    ids=by[t]
    groups=Counter()
    samples=[]
    for iid in ids:
        p=path(iid).replace('DataModel/Workspace/Gwangalli/','')
        segs=p.split('/')
        groups['/'.join(segs[:2])]+=1
        if len(samples)<4:
            i=G.inst[iid]
            cf=G.prop(i,'CFrame')
            pos=None
            if cf: pos=[round(cf[1],1),round(cf[2],1),round(cf[3],1)]
            attrs={k:str(G.val(v))[:60] for k,v in i['attrs'].items()}
            samples.append({'path':p,'cls':i['cls'],'pos':pos,'attrs':attrs})
    out[t]={'count':len(ids),'groups':dict(groups.most_common(8)),'samples':samples}
    print(t, len(ids), dict(groups.most_common(6)))
    for s in samples[:3]: print('    ', s)
json.dump(out, open('/tmp/claude-0/-home-user--/70cfab65-8cfb-5029-bbdf-07c69ae89ee1/scratchpad/bld/tags_static.json','w'), ensure_ascii=False, indent=1)
