# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
# Classify each module's resource types: a stable kind, an alpha kind, a
# gap kind of config-connector-extensions, a gap, or not Google Cloud.
#   classify.py DATA_JSON THIS_DIR OUT_JSON [CCE_JSON]
# With CCE_JSON (extract_cce.py), a type Config Connector has no kind for,
# or only an alpha one, is a config-connector-extensions kind ("hfl") when
# that repository has one at the pinned commit; the kind names its group
# and version, so a v1alpha1 one shows it needs allow_alpha.
import json,sys,re
sys.path.insert(0,sys.argv[2])
from manual import M,IAMT,NONGCP,CCE
d=json.load(open(sys.argv[1]))
K=d["kinds"]; TF=d["tfmap"]
X=json.load(open(sys.argv[4])) if len(sys.argv)>4 else dict(kinds={},tf={},iam=[])
XK=X["kinds"]
def pascal(t): return "".join(w.capitalize() for w in t.replace("google_","",1).split("_"))
XL={k.lower():k for k in XK}
def xkind(k): return f"{k} ({XK[k]['group']}/{XK[k]['versions'][-1]})"
def cce(r):
    """The config-connector-extensions kind for a Terraform type, or None."""
    m=re.match(r"google_(.+?)_iam_(member|binding)$",r)
    if m:
        r0="google_"+m.group(1)
        cands=[(M.get(r0) or "").replace("HFL:","").split(" (")[0]]+TF.get(r0,[])+[pascal(r0)]
        IL={k.lower():k for k in X["iam"]}
        target=next((IL[c.lower()] for c in cands if c.lower() in IL),None)
        if target:
            k="IAMMember" if m.group(2)=="member" else "IAMBinding"
            if k in XK: return f"{xkind(k)} on {target}"
        return None
    k=CCE.get(r) or X["tf"].get(r) or M.get(r) or pascal(r)
    if k and not k.startswith(("via:","HFL:")) and k.lower() in XL: return xkind(XL[k.lower()])
    return None
def beta(k): return any(v in ("v1beta1","v1") for v in K.get(k,{}).get("versions",[]))
def classify(r):
    if r.startswith(NONGCP): return ("na",None)
    m=re.match(r"google_(.+?)_iam_(member|binding|policy)$",r)
    if m:
        t=IAMT.get(m.group(1),"?"+m.group(1))
        kind="IAMPolicyMember" if m.group(2)=="member" else "IAMPartialPolicy"
        if t is None: return ("gap","IAM on "+m.group(1))
        if t.startswith("?"): return ("unknown",t)
        if t.startswith("via:"): return ("alpha",t[4:])
        return ("beta",f"{kind} -> {t}")
    if r in TF:
        k=TF[r][0]; return ("beta" if beta(k) else "alpha",k)
    if r in M:
        k=M[r]
        if k is None: return ("gap",r.replace("google_",""))
        if k.startswith("via:"): return ("beta",k[4:])
        if k.startswith("HFL:"): return ("hfl",k[4:])
        if k not in K: return ("unknown",k)
        return ("beta" if beta(k) else "alpha",k)
    return ("unknown",r)
out={}
gaps={}
for mod,v in d["mods"].items():
    rows=[]
    for r,n in sorted(v["resources"].items()):
        c,k=classify(r)
        if c in ("gap","alpha","unknown"):
            x=cce(r)
            if x: c,k="hfl",x
        rows.append(dict(tf=r,n=n,cls=c,kcc=k))
        if c in("gap","hfl"): gaps.setdefault((c,r),[]).append(mod)
    g=[x for x in rows if x["cls"]!="na"]
    cnt={c:sum(1 for x in g if x["cls"]==c) for c in("beta","alpha","gap","hfl","unknown")}
    out[mod]=dict(rows=rows,counts=cnt,**{k:v[k] for k in("tf_lines","variables","outputs","submodules","data")})
json.dump(dict(mods=out,gaps={f"{c}|{r}":m for (c,r),m in gaps.items()}),open(sys.argv[3],"w"),indent=1)
unk=[(m,x["tf"],x["kcc"]) for m,v in out.items() for x in v["rows"] if x["cls"]=="unknown"]
print("unknown",unk)
