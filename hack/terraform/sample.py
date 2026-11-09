#!/usr/bin/env python3
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
"""Draws a fixed random sample of the attributes counted as covered by Terraform
at level L2 but not L1, for checking by hand (docs/terraform-leverage.md,
"Method and error"). usage: sample.py CLOUD COVERAGE_DIR N [category]"""
import csv, random, sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
import analyze as A

cloud, covdir, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
cat = sys.argv[4] if len(sys.argv) > 4 else "platform-foundation"
res, tf = A.load(cloud, covdir, f"docs/terraform/data/{cloud}")
mp = {}
for r in csv.DictReader(open(f"docs/terraform/data/{cloud}.mapping.csv")):
    if r["api_resource"]:
        mp.setdefault((r["service"], r["api_resource"]), []).append(r["tf_resource"])
pool = []
for k, r in res.items():
    if r["category"] != cat or k not in mp:
        continue
    t1 = set(); t2 = {}
    for n_ in mp[k]:
        for a in tf[n_]["attrs"]:
            a1, a2 = A.keys(a, cloud)
            t1.add(a1); t2.setdefault(a2, []).append(n_ + ":" + a)
    for a, _ in r["attrs"]:
        a1, a2 = A.keys(a, cloud)
        if a1 not in t1 and a2 in t2:
            pool.append((k[1], a, t2[a2][:2]))
random.Random(7).shuffle(pool)
for x in pool[:n]:
    print(x)
print("pool", len(pool))
