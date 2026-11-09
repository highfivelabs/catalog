# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
# Read every fabric module (its resource types, variables, outputs) and
# every Config Connector CRD and service mapping into one JSON file.
#   extract.py FABRIC_DIR KCC_DIR OUT_JSON
import os,re,json,sys,glob
import yaml
root=sys.argv[1]
kcc=sys.argv[2]
out={}
# fabric modules
mods={}
for m in sorted(os.listdir(os.path.join(root,'modules'))):
    p=os.path.join(root,'modules',m)
    if not os.path.isdir(p): continue
    res={}; data=set(); lines=0; vars_=0; outs=0; submods=[]
    for dp,dn,fn in os.walk(p):
        for f in fn:
            if not f.endswith('.tf'): continue
            fp=os.path.join(dp,f); rel=os.path.relpath(fp,p)
            t=open(fp).read()
            lines+=t.count('\n')
            if os.path.dirname(rel) and os.path.dirname(rel) not in submods: submods.append(os.path.dirname(rel))
            for r,n in re.findall(r'^resource\s+"([a-z0-9_]+)"\s+"([^"]+)"',t,re.M):
                res.setdefault(r,0); res[r]+=1
            for r in re.findall(r'^data\s+"([a-z0-9_]+)"',t,re.M): data.add(r)
            if f=='variables.tf' or f.startswith('variables'):
                vars_+=len(re.findall(r'^variable\s+"',t,re.M))
            if f=='outputs.tf': outs+=len(re.findall(r'^output\s+"',t,re.M))
    yamls=len(glob.glob(p+'/**/*.yaml',recursive=True))+len(glob.glob(p+'/**/*.json',recursive=True))
    mods[m]=dict(resources=res,data=sorted(data),tf_lines=lines,variables=vars_,outputs=outs,submodules=submods,schema_files=yamls)
# kcc
kinds={}
for f in glob.glob(kcc+'/config/crds/resources/*.yaml'):
    d=yaml.safe_load(open(f))
    k=d['spec']['names']['kind']; g=d['spec']['group']
    lab=d['metadata'].get('labels',{})
    vers=[v['name'] for v in d['spec']['versions'] if v.get('served')]
    ctl='tf' if lab.get('cnrm.cloud.google.com/tf2crd')=='true' else 'dcl' if lab.get('cnrm.cloud.google.com/dcl2crd')=='true' else 'direct'
    kinds[k]=dict(group=g,versions=vers,stability=lab.get('cnrm.cloud.google.com/stability-level'),controller=ctl)
tfmap={}
for f in glob.glob(kcc+'/config/servicemappings/*.yaml'):
    d=yaml.safe_load(open(f))
    for rc in d['spec'].get('resources',[]):
        tfmap.setdefault(rc['name'],[]).append(rc['kind'])
json.dump(dict(mods=mods,kinds=kinds,tfmap=tfmap),open(sys.argv[3],'w'),indent=1,sort_keys=True)
print(len(mods),len(kinds),len(tfmap))
