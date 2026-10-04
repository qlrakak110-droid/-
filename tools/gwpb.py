# GWPB v1 reader/writer (structure-preserving)
import struct
FIX={0:0,1:0,2:0,3:8,4:4,7:12,8:8,10:12,11:3,14:16,15:8,21:20,22:1,23:1,24:24,28:1}
class Reader:
    def __init__(s,u8): s.u=u8; s.p=0
    def vi(s):
        u=s.u; b=u[s.p]; s.p+=1
        if b<128: return b
        v=b&127; mul=128
        while True:
            b=u[s.p]; s.p+=1
            if b<128: return v+b*mul
            v+=(b&127)*mul; mul*=128
    def skip(s):
        u=s.u; tag=u[s.p]; s.p+=1
        if tag in FIX: s.p+=FIX[tag]; return
        if tag in (5,6,18,25): s.vi()
        elif tag==9: s.p+= 49 if u[s.p+12]==0 else 13
        elif tag==12: s.p+=4; s.vi()
        elif tag==13: s.p+=4; s.vi(); s.p+=4; s.vi()
        elif tag==16: k=s.vi(); s.p+=k*12
        elif tag==17: k=s.vi(); s.p+=k*16
        elif tag==19: s.vi(); s.vi()
        elif tag in (20,26): s.vi(); s.vi(); s.vi()
        elif tag==27: s.vi(); s.vi()
        else: raise Exception('tag %d at %d'%(tag,s.p-1))
def enc_vi(v):
    out=bytearray()
    while v>=128: out.append((v&127)|128); v>>=7
    out.append(v); return bytes(out)
class Place:
    def __init__(s,data):
        s.data=data; r=Reader(data); r.p=8; s.r=r
        n=r.vi(); s.S=[]
        for i in range(n):
            l=r.vi(); s.S.append(data[r.p:r.p+l]); r.p+=l
        s.after_strings=r.p
        s.meta=r.vi()
        nrot=data[r.p]; r.p+=1+9*nrot
        npool=r.vi(); s.poolpos=[]
        for i in range(npool): s.poolpos.append(r.p); r.skip()
        ns=r.vi(); s.shapes=[None]
        for i in range(ns):
            k=r.vi(); s.shapes.append([r.vi() for _ in range(k)])
        s.inst_start=r.p
        ni=r.vi(); s.inst=[None]
        for i in range(1,ni+1):
            st=r.p
            cls=r.vi(); name=r.vi(); pd=r.vi(); shape=r.vi()
            props=[]
            if shape:
                for k in range(len(s.shapes[shape])):
                    ref=r.vi()
                    if ref==0: vp=r.p; r.skip(); props.append((0,vp,r.p))
                    else: props.append((ref,None,None))
            ex=r.p
            na=r.vi()
            attrs=[]
            for k in range(na): an=r.vi(); vp=r.p; r.skip(); attrs.append((an,vp,r.p))
            nt=r.vi(); tags=[r.vi() for _ in range(nt)]
            s.inst.append(dict(cls=cls,name=name,parent=i-pd if pd else 0,shape=shape,props=props,attrs=attrs,tags=tags,start=st,end=r.p))
        s.inst_end=r.p
        assert data[r.p:r.p+4]==b'END!', data[r.p:r.p+4]
    def s(self,i): return self.S[i].decode('utf-8','replace')
    def path(self,i):
        parts=[]
        while i:
            parts.append(self.s(self.inst[i]['name'])); i=self.inst[i]['parent']
        return '/'.join(reversed(parts))
    def prop(self,i,name):
        it=self.inst[i]
        if not it['shape']: return None
        names=[self.s(x) for x in self.shapes[it['shape']]]
        if name not in names: return None
        ref,vp,ve=it['props'][names.index(name)]
        if ref: vp=self.poolpos[ref-1]
        return vp
    def strval(self,vp):
        if vp is None or self.data[vp]!=6: return None
        r=Reader(self.data); r.p=vp+1; return r.vi()
