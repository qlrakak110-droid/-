import math
A=math.radians(-1.8747)
c,s=math.cos(A),math.sin(A)
O=(-515.0,6.9,300.0)
def W(x,y,z):  # local -> world ; X axis=(c,0,-s), Z axis=(s,0,c)
    return (O[0]+x*c+z*s, O[1]+y, O[2]-x*s+z*c)
def wbox(mn,mx):
    pts=[W(x,y,z) for x in (mn[0],mx[0]) for y in (mn[1],mx[1]) for z in (mn[2],mx[2])]
    return [min(p[i] for p in pts) for i in range(3)],[max(p[i] for p in pts) for i in range(3)]
K=[
 ('K01','restroom_block','facility_room',(-59.29,0,26.6),(-35.9,11.05,38.78)),
 ('K02','restroom_approach','facility',(-52.4,0,22.2),(-43.4,8.0,26.6)),
 ('K03','lift1_enclosure_landing','facility_room',(-36.4,0,31.0),(-27.8,11.05,38.78)),
 ('K04','hydrant_aed_niche','facility',(-36.0,0,27.6),(-34.6,8.0,31.0)),
 ('K05','staff_door_1F','opening',(-15.0,0,35.0),(-9.2,10.0,38.78)),
 ('K06','storage_door_1F','opening',(-25.0,0,35.0),(-19.2,10.0,38.78)),
 ('K07','fireexit_inside','opening',(54.5,0,26.2),(59.11,10.0,33.6)),
 ('K08','fireexit_outside','facility',(59.91,-0.4,25.6),(65.5,10.0,33.6)),
 ('K09','er_door_inside','opening',(53.5,0,9.0),(59.11,11.05,20.0)),
 ('K10','er_door_outside','facility',(59.91,-0.4,8.5),(68.5,12.6,20.5)),
 ('K11','east_wall_replacement','opening',(59.0,-0.4,-35.3),(60.1,13.0,39.6)),
 ('K12','glassdoor_consult','opening',(-26.6,0,-7.0),(-17.7,8.6,-5.4)),
 ('K13','glassdoor_treat','opening',(25.7,0,-2.9),(34.5,8.6,-1.6)),
 ('K14','consult_lamp_plate','facility',(-23.0,4.5,-5.82),(-14.7,10.0,-5.2)),
 ('K15','glassdoor_ward201','opening',(13.4,14.15,-10.9),(22.2,22.6,-9.6)),
 ('K16','glassdoor_ward202','opening',(-26.6,14.15,-10.9),(-17.7,22.6,-9.6)),
 ('K17','glassdoor_checkup','opening',(-36.6,14.15,-4.9),(-19.7,22.6,-3.6)),
 ('K18','lift2_enclosure_landing','facility_room',(-36.4,14.15,31.0),(-27.8,22.6,38.94)),
 ('K19','checkup_guide_board','facility',(-28.0,16.6,38.4),(-19.4,22.0,38.94)),
 ('K20','landing2F_passage','opening',(-8.1,14.15,-6.0),(-2.0,22.6,0.2)),
 ('K21','roofstair_door_2F','opening',(-8.09,14.15,34.5),(-3.3,22.6,38.94)),
 ('K22','roof_lift_penthouse','facility_room',(-36.6,25.2,30.5),(-27.6,35.2,38.87)),
]
print('| id | what | kind | local min | local max | WORLD min | WORLD max |')
print('|---|---|---|---|---|---|---|')
for k,n,kind,mn,mx in K:
    a,b=wbox(mn,mx)
    f=lambda v:'(%s)'%', '.join('%.2f'%x for x in v)
    print('| %s | %s | %s | %s | %s | %s | %s |'%(k,n,kind,f(mn),f(mx),f(a),f(b)))
print()
P=[('HF origin',(0,0,0)),('lift1 / lift2 spot',(-31.94,0.3,33.06)),('elevator door centre 1F',(-32.09,0,33.3)),('elevator door centre 2F',(-32.09,14.15,33.3)),('elevator door centre RF',(-32.09,25.2,33.3)),
('restroom W door centre',(-49.9,0,27.15)),('restroom M door centre',(-45.6,0,27.15)),('STAFF door centre',(-12.09,0,38.72)),('창고 door centre',(-22.09,0,38.72)),
('fire exit centre',(59.51,0,29.58)),('ER door centre',(59.51,0,14.5)),('2F passage centre',(-5.8,14.15,-4.12)),('2F roof-stair door',(-5.95,14.15,38.94)),('RoofDoor centre',(38.13,25.2,-2.17)),
('telescope',(-37.0,25.2,-34.0)),('P1 staff room door (inside)',(-12.1,-50,22.0)),('P2 storage door (inside)',(-22.1,-50,2.0)),('P3 stair bottom door',(-8.0,-50,-24.0)),('P3 stair top door',(-3.4,-38.95,-24.0))]
for n,p in P:
    w=W(*p); print('%-30s L(%.2f, %.2f, %.2f) -> W(%.2f, %.2f, %.2f)'%(n,p[0],p[1],p[2],w[0],w[1],w[2]))
for n,mn,mx in [('P1 staff lounge',(-24,-50,22),(-2,-41.4,36)),('P2 storage',(-30,-50,2),(-15,-41.4,14)),('P3 stairwell',(-10,-50,-24),(-1.4,-30.5,-7)),('portal zone (all, +shell)',(-31,-51,-25),(-1,-29.5,37))]:
    a,b=wbox(mn,mx); print('%-26s world %s .. %s'%(n,['%.1f'%x for x in a],['%.1f'%x for x in b]))
