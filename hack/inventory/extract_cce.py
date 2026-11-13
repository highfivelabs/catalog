# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
# Read config-connector-extensions' kinds at the pinned commit
# (UPSTREAM.md, "Gap kinds commit"): every CRD's kind, group and served
# versions; the Terraform type each discokind-generated kind ports
# (hack/discokind/kinds.yaml); and the resource kinds its IAMMember and
# IAMBinding take (pkg/iampolicy). classify.py maps Terraform types to
# them.
#   extract_cce.py CCE_DIR COMMIT OUT_JSON
import glob, json, re, sys
import yaml
cce, commit = sys.argv[1], sys.argv[2]
kinds = {}
for f in sorted(glob.glob(cce + "/config/crds/*.yaml")):
    d = yaml.safe_load(open(f))
    if not d or d.get("kind") != "CustomResourceDefinition":
        continue
    vers = [v["name"] for v in d["spec"]["versions"] if v.get("served", True)]
    kinds[d["spec"]["names"]["kind"]] = dict(group=d["spec"]["group"], versions=vers)
tf = {}
for k in yaml.safe_load(open(cce + "/hack/discokind/kinds.yaml")) or []:
    if k.get("terraform") and k["kind"] in kinds:
        for t in (k["terraform"] if isinstance(k["terraform"], list) else [k["terraform"]]):
            tf[t] = k["kind"]
iam = set()
for f in glob.glob(cce + "/pkg/iampolicy/*.go"):
    if f.endswith("_test.go"):
        continue
    src = open(f).read()
    iam.update(re.findall(r'\bKind:\s+"(\w+)"', src))
    iam.update(re.findall(r'\bmixin\("(\w+)"', src))
json.dump(dict(commit=commit, kinds=kinds, tf=tf, iam=sorted(iam)), open(sys.argv[3], "w"), indent=1, sort_keys=True)
print("config-connector-extensions", commit[:8], len(kinds), "kinds,", len(tf), "Terraform types,", len(iam), "IAM resource kinds")
