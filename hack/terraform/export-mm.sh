#!/usr/bin/env bash
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
#
# Reads Magic Modules' mmv1 resource definitions (the YAML the Google Terraform
# providers are largely generated from) into CSVs. Run on an offload VM:
#
#   ../offload/offload run --machine e2-standard-4 -- hack/terraform/export-mm.sh
#
# Writes offload-artifacts/terraform/: gcp.mm-resources.csv (one row per
# resource definition), gcp.mm-properties.csv (counts of the keys used on
# properties), gcp.mm-handwritten-files.txt, mm-commit.txt.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
out=$root/offload-artifacts/terraform
mkdir -p "$out"
work=$(mktemp -d)
git clone -q --depth 1 https://github.com/GoogleCloudPlatform/magic-modules.git "$work/mm"
git -C "$work/mm" log -1 --format='%H %cI' | tee "$out/mm-commit.txt"
python3 -m venv "$work/venv" && "$work/venv/bin/pip" -q install pyyaml
( cd "$work/mm" && find mmv1/third_party/terraform/services -name 'resource_*.go*' ! -name '*_test.go*' | sort ) > "$out/gcp.mm-handwritten-files.txt"
wc -l "$out/gcp.mm-handwritten-files.txt"
"$work/venv/bin/python" - "$work/mm/mmv1/products" "$out" <<'PY'
import csv, os, re, sys, collections, yaml
prods, out = sys.argv[1], sys.argv[2]

def snake(s):
    s = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1_\2", s)
    s = re.sub(r"([a-z\d])([A-Z])", r"\1_\2", s)
    return s.replace("-", "_").lower()

keycount = collections.Counter()
nprops = collections.Counter()
rows, failed = [], []

def walk(props, st):
    for p in props or []:
        if not isinstance(p, dict):
            continue
        st["props"] += 1
        for k, v in p.items():
            keycount[k] += 1
        if p.get("immutable"): st["immutable"] += 1
        if p.get("output"): st["output"] += 1
        if p.get("required"): st["required"] += 1
        if p.get("default_from_api"): st["default_from_api"] += 1
        if p.get("min_version") == "beta": st["beta"] += 1
        if p.get("deprecation_message"): st["deprecated"] += 1
        walk(p.get("properties"), st)
        it = p.get("item_type")
        if isinstance(it, dict):
            walk(it.get("properties"), st)
        vt = p.get("value_type")
        if isinstance(vt, dict):
            walk(vt.get("properties"), st)

for pdir in sorted(os.listdir(prods)):
    d = os.path.join(prods, pdir)
    pf = os.path.join(d, "product.yaml")
    if not os.path.isfile(pf):
        continue
    try:
        prod = yaml.safe_load(open(pf))
    except Exception as e:
        failed.append((pf, str(e))); continue
    versions = {v["name"]: v.get("base_url", "") for v in prod.get("versions", [])}
    base = versions.get("ga") or versions.get("beta") or ""
    host = re.sub(r"^https?://([^/]+)/.*$", r"\1", base) if base else ""
    pname = prod.get("legacy_name") or snake(prod["name"])
    for f in sorted(os.listdir(d)):
        if f == "product.yaml" or not f.endswith(".yaml"):
            continue
        try:
            r = yaml.safe_load(open(os.path.join(d, f)))
        except Exception as e:
            failed.append((os.path.join(d, f), str(e))); continue
        if not isinstance(r, dict) or "name" not in r:
            continue
        st = collections.Counter()
        walk(r.get("properties"), st)
        walk(r.get("parameters"), st)
        iam = r.get("iam_policy")
        a = r.get("async") or {}
        tf = r.get("legacy_name") or f"google_{pname}_{snake(r['name'])}"
        burl = r.get("base_url", "")
        static = [s for s in burl.split("/") if s and not s.startswith("{{")]
        rows.append({
            "product": pdir, "file": f, "name": r["name"], "tf_name_derived": tf,
            "host": host, "base_url": burl, "collection": static[-1] if static else "",
            "min_version": r.get("min_version", "ga"), "exclude": int(bool(r.get("exclude"))),
            "readonly": int(bool(r.get("readonly"))), "create_verb": r.get("create_verb", "POST"),
            "update_verb": r.get("update_verb", ""), "update_mask": int(bool(r.get("update_mask"))),
            "immutable_resource": int(bool(r.get("immutable"))),
            "async_type": a.get("type", ""), "async_actions": " ".join(a.get("actions", []) or []),
            "has_iam_policy": int(bool(iam)) if not (isinstance(iam, dict) and iam.get("exclude")) else 0,
            "iam_min_version": (iam or {}).get("min_version", "") if isinstance(iam, dict) else "",
            "properties": st["props"], "immutable": st["immutable"], "output": st["output"],
            "required": st["required"], "default_from_api": st["default_from_api"],
            "beta_properties": st["beta"], "deprecated_properties": st["deprecated"],
            "custom_code": int(bool(r.get("custom_code"))), "custom_diff": int(bool(r.get("custom_diff"))),
            "samples": len(r.get("samples", []) or r.get("examples", []) or []),
        })
with open(os.path.join(out, "gcp.mm-resources.csv"), "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows[0]))
    w.writeheader(); w.writerows(rows)
with open(os.path.join(out, "gcp.mm-properties.csv"), "w", newline="") as fh:
    w = csv.writer(fh); w.writerow(["property_key", "count"])
    w.writerows(keycount.most_common())
print(len(rows), "resource definitions;", len(failed), "unparsed")
for f, e in failed[:10]:
    print("unparsed:", f, e[:100])
PY
ls -l "$out"
