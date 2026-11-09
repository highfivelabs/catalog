#!/usr/bin/env python3
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
"""Writes docs/terraform/<repo>/terraform.csv and terraform-resources.csv for each
extensions repository, and docs/terraform/summary.csv. usage: repo-files.py DIR"""
import csv, os, sys
from collections import defaultdict

here = os.path.dirname(os.path.abspath(__file__)) + "/../.."
data = here + "/docs/terraform/data"
sources = {
    "config-connector-extensions": [("google", "gcp-google"), ("google-beta", "gcp-google-beta")],
    "ack-extensions": [("aws", "aws")],
    "aso-extensions": [("azurerm", "azure-azurerm")],
}
CATS = ["platform-foundation", "security-adjacent", "application", "other"]


def pct(a, b):
    return f"{100.0 * a / b:.1f}" if b else "0.0"


def agg(rows):
    a = defaultdict(int)
    for r in rows:
        t = int(r["attributes_total"])
        a["resources"] += 1
        a["attrs"] += t
        has_tf = bool(r["tf_resources"])
        has_oo = bool(r["official_kinds"] or r["ours_kinds"])
        a["res_tf"] += has_tf
        a["res_tf_beyond"] += has_tf and not has_oo
        a["res_official"] += bool(r["official_kinds"])
        a["official"] += int(r["attributes_official"])
        a["ours"] += int(r["attributes_ours_beyond"])
        a["tf1"] += int(r["attributes_tf_l1"])
        a["tf2"] += int(r["attributes_tf_l2"])
        a["official_and_tf"] += int(r["official_and_tf_l2"])
        a["ours_and_tf"] += int(r["ours_and_tf_l2"])
        a["tf_only"] += int(r["tf_gain_l2"])
        a["tf_resource_attrs"] += t if has_tf else 0
    a["oo_without_tf"] = a["official"] + a["ours"] - a["official_and_tf"] - a["ours_and_tf"]
    a["union"] = a["official"] + a["ours"] + a["tf_only"]
    return a


def line(a):
    n = a["attrs"]
    return [a["resources"], a["res_tf"], a["res_tf_beyond"], n, a["tf1"], a["tf2"], pct(a["tf1"], n), pct(a["tf2"], n),
            a["official_and_tf"], a["ours_and_tf"], a["tf_only"], a["oo_without_tf"], pct(a["union"], n),
            pct(a["tf2"], a["tf_resource_attrs"])]


HDR = ["resources_total", "resources_terraform", "resources_terraform_beyond_official_and_ours",
       "attributes_total", "attributes_terraform_l1", "attributes_terraform_l2", "pct_terraform_l1", "pct_terraform_l2",
       "attributes_official_and_terraform", "attributes_ours_and_terraform", "attributes_terraform_only",
       "attributes_official_or_ours_without_terraform", "pct_official_ours_terraform_union",
       "pct_terraform_within_mapped_resources"]

summary = []
for repo, provs in sources.items():
    d = f"{here}/docs/terraform/{repo}"
    os.makedirs(d, exist_ok=True)
    with open(f"{d}/terraform.csv", "w", newline="") as fh, open(f"{d}/terraform-resources.csv", "w", newline="") as fr:
        w, wr = csv.writer(fh), csv.writer(fr)
        w.writerow(["service", "provider", "category"] + HDR)
        wr.writerow(["service", "resource", "provider", "category", "attributes_total", "terraform_resources",
                     "attributes_terraform_l1", "attributes_terraform_l2", "attributes_official_and_terraform",
                     "attributes_ours_and_terraform", "attributes_terraform_only"])
        for prov, tag in provs:
            rows = list(csv.DictReader(open(f"{data}/{tag}.api-resources.csv")))
            by = defaultdict(list)
            for r in rows:
                by[(r["service"], r["category"])].append(r)
                wr.writerow([r["service"], r["resource"], prov, r["category"], r["attributes_total"], r["tf_resources"],
                             r["attributes_tf_l1"], r["attributes_tf_l2"], r["official_and_tf_l2"], r["ours_and_tf_l2"], r["tf_gain_l2"]])
            for (svc, cat), rs in sorted(by.items()):
                w.writerow([svc, prov, cat] + line(agg(rs)))
            for scope in ["all"] + CATS:
                rs = rows if scope == "all" else [r for r in rows if r["category"] == scope]
                a = agg(rs)
                n = a["attrs"]
                summary.append([repo, prov, scope, a["resources"], a["res_official"], a["res_tf"], pct(a["res_tf"], a["resources"]),
                                n, pct(a["official"], n), pct(a["ours"], n), a["tf1"], a["tf2"], pct(a["tf1"], n), pct(a["tf2"], n),
                                pct(a["tf2"], a["tf_resource_attrs"]), a["tf_only"], pct(a["tf_only"], n), pct(a["union"], n),
                                a["oo_without_tf"], pct(a["oo_without_tf"], n)])
with open(f"{here}/docs/terraform/summary.csv", "w", newline="") as fh:
    w = csv.writer(fh)
    w.writerow(["repo", "provider", "scope", "resources_total", "resources_official", "resources_terraform", "pct_resources_terraform",
                "attributes_total", "pct_attributes_official", "pct_attributes_ours_beyond", "attributes_terraform_l1",
                "attributes_terraform_l2", "pct_terraform_l1", "pct_terraform_l2", "pct_terraform_within_mapped_resources",
                "attributes_terraform_only", "pct_terraform_only", "pct_union", "attributes_official_or_ours_without_terraform",
                "pct_official_or_ours_without_terraform"])
    w.writerows(summary)
print("wrote", len(summary), "summary rows")
