# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
# Make the inventory tables of docs/gcp-inventory.md: run from a work
# directory holding cls.json, data.json and desc.txt (hack/inventory/run.sh).
import json,re,sys
c=json.load(open("cls.json")); d=json.load(open("data.json"))
desc={}
for l in open("desc.txt"):
    m,_,t=l.rstrip("\n").partition("|"); desc[m]=t
RANK=[
 # tier 1: landing-zone foundation (the builder's list first)
 "project","folder","organization","iam-service-account","net-vpc","net-vpc-firewall","net-cloudnat","dns","kms","gcs",
 "artifact-registry","secret-manager","cloudsql-instance","gke-cluster-standard","gke-cluster-autopilot","gke-nodepool",
 "pubsub","bigquery-dataset","cloud-run-v2",
 "billing-account","logging-bucket","net-firewall-policy","vpc-sc","project-factory","net-vpc-factory","net-vpc-peering",
 "net-address","net-vpn-ha","cloud-identity-group","dns-response-policy","certificate-manager","net-lb-app-ext",
 "net-lb-int","net-lb-ext","net-lb-app-int","compute-vm","compute-mig","service-directory","workflows",
 # tier 3
 "cloud-function-v2","alloydb","spanner-instance","bigtable-instance","firestore","managed-kafka","net-cloud-armor",
 "net-swp","net-lb-app-ext-regional","net-lb-app-int-cross-region","net-lb-proxy-int","net-lb-proxy-int-cross-region",
 "net-vpn-static","net-vpn-dynamic","net-vlan-attachment","net-ipsec-over-interconnect","ncc-spoke-ra","gke-hub",
 "binauthz","certificate-authority-service","backup-dr","cloud-deploy","cloud-build-v2-connection","secure-source-manager-instance",
 "source-repository","bigquery-connection","analytics-hub","biglake-catalog","dataform-repository","dataproc","datafusion",
 "dataplex","dataplex-datascan","dataplex-aspect-types","data-catalog-policy-tag","data-catalog-tag","data-catalog-tag-template",
 "api-gateway","apigee","endpoints","cloud-function-v1","workstation-cluster","gcve-private-cloud","looker-core",
 "ai-applications","geap-agent-gateway","geap-agent-runtime","geap-workbench","secops-rules","container-registry",
 "projects-data-source","cloud-config-container",
]
mods={m:v for m,v in c["mods"].items() if m!="__experimental_deprecated"}
assert set(RANK)==set(mods), (set(mods)-set(RANK), set(RANK)-set(mods))
COMPOSITE={"project-factory":"composes folder, project, iam-service-account, gcs, kms, pubsub, bigquery-dataset, logging-bucket, billing-account, data-catalog-policy-tag, dataplex-aspect-types",
           "net-vpc-factory":"composes net-vpc and net-vpc-firewall"}
NONE_PRIMARY={"looker-core","endpoints","container-registry"}
NA={"projects-data-source":"data sources only (a read, not a resource)","cloud-config-container":"generates cloud-init text; no resources"}
def size(v):
    l=v["tf_lines"]
    return "S" if l<400 else "M" if l<900 else "L" if l<2000 else "XL"
def coverage(m,v):
    if m in NA: return "n/a"
    if m in COMPOSITE: return "composite"
    ct=v["counts"]
    if m in NONE_PRIMARY: return "none"
    if ct["gap"]==0 and ct["hfl"]==0 and ct["alpha"]==0: return "full"
    if ct["gap"]==0 and ct["hfl"]==0: return "full, with alpha"
    return "partial"
# Each module's page at the pinned fabric tag, from upstream/modules.yaml.
import yaml
URL={x["module"]:x["url"] for x in yaml.safe_load(open(sys.argv[2]))["modules"] if x["cloud"]=="gcp"}
rows=[]; stats={}
for i,m in enumerate(RANK,1):
    v=mods[m]; cov=coverage(m,v); stats[cov]=stats.get(cov,0)+1
    rows.append((i,m,v,cov))
out=[]
out.append("| Rank | Module | Coverage | Size | Terraform lines | Variables | Resource types (beta / alpha / gap) |")
out.append("| ---: | --- | --- | --- | ---: | ---: | --- |")
for i,m,v,cov in rows:
    ct=v["counts"]; g=ct["gap"]+ct["hfl"]
    out.append(f"| {i} | [{m}](#{m}) | {cov} | {size(v)} | {v['tf_lines']} | {v['variables']} | {ct['beta']} / {ct['alpha']} / {g} |")
out.append("")
out.append("## Per module")
out.append("")
for i,m,v,cov in rows:
    out.append(f"### {m}")
    out.append("")
    dd=desc.get(m,"").strip()
    dd=re.sub(r"\[([^\]]+)\]\([^)]+\)",r"\1",dd)
    if dd and not dd.startswith("-"):
        out.append(f"{dd.rstrip('.').rstrip(':')}{'' if dd.endswith(':') else '.'}" if len(dd)<139 else dd+"…")
        out.append("")
    extra=[]
    if m in COMPOSITE: extra.append(COMPOSITE[m]+"; ported by porting those modules and composing them in a Bundt Template")
    if m in NA: extra.append(NA[m])
    if v["submodules"]: extra.append("submodules or factory data: "+", ".join(v["submodules"][:6])+(" …" if len(v["submodules"])>6 else ""))
    out.append(f"Rank {i}. Terraform module: [`modules/{m}`]({URL[m]}). Coverage: **{cov}**. Size: {size(v)} ({v['tf_lines']} lines of Terraform, {v['variables']} variables, {v['outputs']} outputs)."+(" "+"; ".join(extra)+"." if extra else ""))
    out.append("")
    if v["rows"]:
        out.append("| Terraform resource | Config Connector | |")
        out.append("| --- | --- | --- |")
        for r in v["rows"]:
            k=r["kcc"] or ""
            mark={"beta":"","alpha":"alpha only","gap":"**gap**","hfl":"gap kind (config-connector-extensions)","na":"not Google Cloud"}[r["cls"]]
            if r["cls"]=="gap": k="none"
            if r["cls"]=="na": k="n/a"
            out.append(f"| `{r['tf']}` | {k} | {mark} |")
        out.append("")
open(sys.argv[1],"w").write("\n".join(out)+"\n")
print(stats, len(rows))
