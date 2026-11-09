#!/usr/bin/env python3
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
"""Terraform provider coverage against the three coverage dashboards.

usage: analyze.py CLOUD COVERAGE_DIR TFDATA_PREFIX OUTDIR [--overrides FILE]

  CLOUD         gcp | aws | azure
  COVERAGE_DIR  docs/coverage of config-connector-extensions, ack-extensions
                or aso-extensions (resources.csv, attributes.csv, priority.csv)
  TFDATA_PREFIX docs/terraform/data/<cloud> (the flatten.py outputs)
  OUTDIR        where <cloud>.mapping.csv, <cloud>.api-resources.csv,
                <cloud>.services.csv and <cloud>.categories.csv are written

Method (docs/terraform-leverage.md, "Method and error"): a Terraform resource
is mapped to the API resources of the dashboard's denominator by name and by
attribute overlap; each API attribute is then counted as covered by Terraform
when a writable attribute of a mapped resource has the same name. Two
levels, because names differ: L1 compares the whole dotted path with
separators, case, plurals and `properties` removed; L2 also accepts a match
of the last two path segments. L1 is the floor and L2 the ceiling.
"""
import csv
import gzip
import re
import sys
from collections import defaultdict

csv.field_size_limit(10**8)

WRAPPERS = {"properties", "spec", "body"}


def sing(s):
    if len(s) > 4 and s.endswith("ies"):
        return s[:-3] + "y"
    if len(s) > 3 and s.endswith("ses"):
        return s[:-2]
    if len(s) > 3 and s.endswith("s") and not s.endswith("ss"):
        return s[:-1]
    return s


def segs(path):
    out = []
    for p in path.split("."):
        p = p.replace("[]", "").replace("{}", "")
        p = re.sub(r"[^A-Za-z0-9]", "", p).lower()
        if p and p not in WRAPPERS:
            out.append(sing(p))
    return out


def keys(path, cloud):
    """(L1 key, L2 key) of an attribute path."""
    s = segs(path)
    if cloud == "aws":
        # CloudFormation Tags[].Key/Value against Terraform's tags map
        if len(s) >= 2 and s[-2] == "tag" and s[-1] in ("key", "value"):
            s = s[:-2] + ["tag"]
    if not s:
        return "", ""
    return "".join(s), "".join(s[-2:])


def tokens(s):
    s = re.sub(r"([a-z0-9])([A-Z])", r"\1 \2", s)
    s = re.sub(r"[^A-Za-z0-9]+", " ", s)
    return [sing(t.lower()) for t in s.split() if t]


SKIP_TF_SUFFIX = re.compile(
    r"_(iam_binding|iam_member|iam_policy|iam_audit_config|iam_member_remove|iam_policy_binding"
    r"|role_assignment_.*)$")


def load(cloud, covdir, tfprefix, providers=None):
    # denominator
    res = {}
    for r in csv.DictReader(open(f"{covdir}/resources.csv")):
        key = (r["service"], r["resource"])
        res[key] = {
            "service": r["service"], "resource": r["resource"],
            "total": int(r["attributes_total"]),
            "official_kinds": r["official_kinds"], "ours_kinds": r["ours_kinds"],
            "attrs": [], "notes": r.get("notes", ""),
        }
    for a in csv.DictReader(open(f"{covdir}/attributes.csv")):
        k = (a["service"], a["resource"])
        if k in res:
            res[k]["attrs"].append((a["attribute"], a["covered_by"]))
    # categories
    prio = list(csv.DictReader(open(f"{covdir}/priority.csv")))
    svc_cat = {}
    res_cat = []
    for p in prio:
        if "/" in p["service"] and cloud == "gcp" or (cloud == "azure" and p["service"].count("/") >= 1):
            res_cat.append((p["service"], p["category"]))
        else:
            svc_cat[p["service"]] = p["category"]
    res_cat.sort(key=lambda x: -len(x[0]))
    for k, r in res.items():
        cat = None
        for pref, c in res_cat:
            pat = pref.rstrip("*")
            if r["resource"] == pref or (pref.endswith("*") and r["resource"].startswith(pat)):
                cat = c
                break
            if cloud == "azure" and r["resource"].lower().startswith(pref.lower()):
                cat = c
                break
        r["category"] = cat or svc_cat.get(r["service"], "other")
    # terraform
    tf = {}
    with gzip.open(tfprefix + ".attributes.csv.gz", "rt") as fh:
        for a in csv.DictReader(fh):
            if providers and a["provider"] not in providers:
                continue
            name = a["resource"]
            t = tf.setdefault(name, {"name": name, "providers": set(), "attrs": {}, "dep": set()})
            t["providers"].add(a["provider"])
            if a["required"] == "1" or a["optional"] == "1":
                t["attrs"][a["path"]] = a["deprecated"] == "1"
    return res, tf


def tf_tokens(name, cloud):
    n = re.sub(r"^(google|aws|azurerm|azapi)_", "", name)
    return tokens(n)


def api_tokens(r, cloud):
    svc = r["service"]
    name = r["resource"]
    if cloud == "gcp":
        name = name.split("/", 1)[-1]
        svc = svc.split(".")[0]
        svc = re.sub(r"^cloud", "", svc)
        name = name.replace(":", " ").replace("[]", "")
    elif cloud == "azure":
        svc = svc.replace("Microsoft.", "")
        name = name.split("/", 1)[-1].replace("/", " ")
    else:
        pass
    return set(tokens(svc)), set(tokens(name))


def svc_string(r, cloud):
    svc = r["service"]
    if cloud == "gcp":
        svc = re.sub(r"^cloud", "", svc.split(".")[0])
    elif cloud == "azure":
        svc = svc.replace("Microsoft.", "")
    return "".join(sing(re.sub(r"[^a-z0-9]", "", svc.lower())) for _ in [0])


# service names (of the denominators) whose Terraform prefix differs
GCP_ALIAS = {"aiplatform": "vertexai", "bigtableadmin": "bigtable", "sqladmin": "sql",
             "certificatemanager": "acm", "inspectorv2": "inspector2", "sso": "ssoadmin"}


def svc_prefix(seq, sstr):
    """True when the first tokens of the Terraform name, joined, spell the service
    (org_policy_policy against orgpolicy, gke_hub_fleet against gkehub)."""
    if not sstr:
        return False
    sstr = GCP_ALIAS.get(sstr, sstr)
    acc = ""
    for tk in seq:
        acc += tk
        if acc == sstr:
            return True
        if len(acc) >= len(sstr):
            break
    return False


def strip_service(seq, sstr, st):
    acc = ""
    for i, tk in enumerate(seq):
        acc += tk
        if acc == sstr:
            return seq[i + 1:]
        if len(acc) >= len(sstr):
            break
    return [tk for tk in seq if tk not in st]


def build_mapping(cloud, res, tf, overrides):
    # attribute key sets
    for r in res.values():
        r["k1"] = {keys(a, cloud)[0] for a, _ in r["attrs"]} - {""}
        r["k2"] = {keys(a, cloud)[1] for a, _ in r["attrs"]} - {""}
        r["st"], r["nt"] = api_tokens(r, cloud)
        r["sstr"] = "".join(sorted(r["st"], key=lambda x: 0)) if len(r["st"]) <= 1 else svc_string(r, cloud)
    for t in tf.values():
        t["k1"] = {keys(a, cloud)[0] for a in t["attrs"]} - {""}
        t["k2"] = {keys(a, cloud)[1] for a in t["attrs"]} - {""}
        t["seq"] = tf_tokens(t["name"], cloud)
        t["tok"] = set(t["seq"])
    # inverted index on name tokens
    idx = defaultdict(list)
    for k, r in res.items():
        for tk in r["st"] | r["nt"]:
            idx[tk].append(k)
    mapping = []  # (tf, api key, name score, attr containment, method)
    unmapped = []
    for name, t in sorted(tf.items()):
        if overrides.get(name) == ["-"]:
            unmapped.append((name, "override: no API resource"))
            continue
        if name in overrides:
            for ak in overrides[name]:
                cand = [k for k in res if k[1] == ak]
                for k in cand:
                    mapping.append((name, k, 1.0, 1.0, "override"))
            if any(m[0] == name for m in mapping):
                continue
        if SKIP_TF_SUFFIX.search(name):
            unmapped.append((name, "IAM add-on (policy/binding/member), not an API resource of the denominator"))
            continue
        cands = set()
        for tk in t["tok"]:
            cands.update(idx.get(tk, ()))
        scored = []
        for k in cands:
            r = res[k]
            if not r["attrs"]:
                continue
            api_all = r["st"] | r["nt"]
            # name score: Terraform name tokens against the resource's name tokens,
            # with the service tokens counting less
            inter_n = len(t["tok"] & r["nt"])
            inter_s = len((t["tok"] & r["st"]) - r["nt"])
            denom = len(t["tok"] | r["nt"]) or 1
            ns = (inter_n + 0.5 * inter_s) / max(denom, 1)
            if ns <= 0:
                continue
            # a Terraform name without the service prefix (google_service_account)
            exact = t["tok"] == r["nt"] or t["tok"] == (r["st"] | r["nt"]) or \
                (r["st"] and t["tok"] == (set(tokens(" ".join(sorted(r["st"])))) | r["nt"]))
            c1 = len(t["k1"] & r["k1"]) / max(len(r["k1"]), 1)
            c2 = len(t["k2"] & r["k2"]) / max(len(r["k2"]), 1)
            ao = max(c1, 0.8 * c2)
            # precision of the overlap the other way (many-field API resources)
            ap = len(t["k2"] & r["k2"]) / max(len(t["k2"]), 1)
            score = 0.6 * ns + 0.25 * ao + 0.15 * ap
            hit = bool(t["tok"] & r["st"]) or svc_prefix(t["seq"], r["sstr"])
            if hit and not exact:
                exact = set(strip_service(t["seq"], r["sstr"], r["st"])) == r["nt"]
            if exact:
                score += 0.4
            if not hit:
                score -= 0.15
            scored.append((score, ns, ao, exact, k, hit))
        if not scored:
            unmapped.append((name, "no API resource with a similar name"))
            continue
        scored.sort(key=lambda x: (-x[0], x[4]))
        best = scored[0]
        # accept: a clear name match, or a partial name match with attribute support
        ok = (best[3] and (best[5] or best[2] >= 0.25)) or \
            (best[5] and ((best[1] >= 0.5 and best[2] >= 0.2) or (best[1] >= 0.34 and best[2] >= 0.5))) or \
            (best[1] >= 0.6 and best[2] >= 0.3)
        if not ok:
            unmapped.append((name, f"best candidate {best[4][1]} too weak (name {best[1]:.2f}, attrs {best[2]:.2f})"))
            continue
        twins = {k for k, r in res.items() if r["service"] == best[4][0] and r["k1"] == res[best[4]]["k1"] and r["attrs"]}
        for sc, ns, ao, ex, k, _h in scored:
            if sc >= best[0] - 0.03 or k in twins:
                mapping.append((name, k, round(ns, 2), round(ao, 2), "exact-name" if ex else "name+attrs"))
    return mapping, unmapped


def sdk_overrides(res, tf, tfprefix, overrides):
    """azurerm resources whose source imports go-azure-sdk/resource-manager/<svc>/<ver>/<pkg>:
    the package is the lower-case last segment of the ARM type. Candidates are the
    denominator's resources with that tail; the best by attribute overlap wins (ties kept)."""
    try:
        rows = list(csv.DictReader(open(tfprefix + ".sdkmap.csv")))
    except FileNotFoundError:
        return overrides
    tails = defaultdict(list)
    for k, r in res.items():
        tails[k[1].rsplit("/", 1)[-1].lower()].append(k)
    out = dict(overrides)
    pk = defaultdict(set)
    for r in rows:
        pk[r["tf_resource"]].add((r["sdk_service"], r["sdk_package"]))
    for name, pairs in pk.items():
        if name in out or name not in tf:
            continue
        t = tf[name]
        t1 = {keys(a, "azure")[0] for a in t["attrs"]} - {""}
        t2 = {keys(a, "azure")[1] for a in t["attrs"]} - {""}
        cands = []
        for svc, pkg in pairs:
            for k in tails.get(pkg, []):
                r = res[k]
                if not r["attrs"]:
                    continue
                ns = k[0].lower().replace("microsoft.", "").replace(".", "")
                if not (svc in ns or ns in svc or svc[:5] == ns[:5]):
                    continue
                r1 = {keys(a, "azure")[0] for a, _ in r["attrs"]} - {""}
                r2 = {keys(a, "azure")[1] for a, _ in r["attrs"]} - {""}
                ov = max(len(t1 & r1), 0.8 * len(t2 & r2)) / max(len(r1), 1)
                cands.append((ov, k))
        if not cands:
            continue
        cands.sort(key=lambda x: (-x[0], x[1]))
        best = cands[0][0]
        out[name] = [k[1] for ov, k in cands if ov >= best - 0.03][:4]
    return out


def mm_overrides(res, tf, tfprefix, overrides):
    """Google: Magic Modules knows each generated resource's API host and collection
    (product.yaml versions[].base_url, the resource's base_url). The denominator's
    resources.csv notes carry the Discovery path (api=v1:projects.locations.instances).
    Same host and same last collection segment: the API resource. Best attribute
    overlap wins (ties kept)."""
    try:
        rows = list(csv.DictReader(open(tfprefix + ".mm-resources.csv")))
    except FileNotFoundError:
        return overrides
    by = defaultdict(list)
    for k, r in res.items():
        m = re.search(r"api=[^:;]*:([^;]+)", r["notes"])
        if m:
            by[(k[0], m.group(1).split(".")[-1].lower())].append(k)
    out = dict(overrides)
    for m in rows:
        name = m["tf_name_derived"]
        if m["exclude"] != "0" or name in out or name not in tf or not m["collection"]:
            continue
        host = re.sub(r"^\{\{[^}]*\}\}-", "", m["host"])
        cands = by.get((host, m["collection"].lower()), [])
        t = tf[name]
        t1 = {keys(a, "gcp")[0] for a in t["attrs"]} - {""}
        t2 = {keys(a, "gcp")[1] for a in t["attrs"]} - {""}
        sc = []
        for k in cands:
            r = res[k]
            if not r["attrs"]:
                continue
            r1 = {keys(a, "gcp")[0] for a, _ in r["attrs"]} - {""}
            r2 = {keys(a, "gcp")[1] for a, _ in r["attrs"]} - {""}
            ov = max(len(t1 & r1), 0.8 * len(t2 & r2)) / max(len(r1), 1)
            sc.append((ov, k))
        if not sc:
            continue
        sc.sort(key=lambda x: (-x[0], x[1]))
        if sc[0][0] < 0.15:  # same collection name but an unrelated resource
            continue
        out[name] = [k[1] for ov, k in sc if ov >= sc[0][0] - 0.03][:4]
    return out


def pct(a, b):
    return f"{100.0 * a / b:.1f}" if b else "0.0"


def main():
    args = sys.argv[1:]
    overrides = {}
    providers = None
    tag = ""
    if "--providers" in args:
        i = args.index("--providers")
        providers = set(args[i + 1].split(","))
        del args[i:i + 2]
    if "--tag" in args:
        i = args.index("--tag")
        tag = args[i + 1]
        del args[i:i + 2]
    if "--overrides" in args:
        i = args.index("--overrides")
        for r in csv.DictReader(open(args[i + 1])):
            if r["cloud"] != args[0]:
                continue
            overrides.setdefault(r["tf_resource"], []).extend(x for x in r["api_resource"].split(";") if x)
        del args[i:i + 2]
    cloud, covdir, tfprefix, outdir = args
    res, tf = load(cloud, covdir, tfprefix, providers)
    if cloud == "azure":
        overrides = sdk_overrides(res, tf, tfprefix, overrides)
    if cloud == "gcp":
        overrides = mm_overrides(res, tf, tfprefix, overrides)
    mapping, unmapped = build_mapping(cloud, res, tf, overrides)

    by_api = defaultdict(list)
    for name, k, ns, ao, method in mapping:
        by_api[k].append(name)
    with open(f"{outdir}/{cloud}{tag}.mapping.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["tf_resource", "service", "api_resource", "name_score", "attr_overlap", "method"])
        for name, k, ns, ao, m in sorted(mapping):
            w.writerow([name, k[0], k[1], ns, ao, m])
        for name, why in unmapped:
            w.writerow([name, "", "", "", "", why])

    rows = []
    for k, r in sorted(res.items()):
        tfs = by_api.get(k, [])
        k1 = set()
        k2 = set()
        for n in tfs:
            k1 |= tf[n]["k1"]
            k2 |= tf[n]["k2"]
        n1 = n2 = 0
        comb = defaultdict(int)  # (official/ours covered?, tf covered level)
        for a, cov in r["attrs"]:
            a1, a2 = keys(a, cloud)
            l1 = bool(tfs) and a1 in k1
            l2 = bool(tfs) and (l1 or a2 in k2)
            n1 += l1
            n2 += l2
            comb[(cov, l1, l2)] += 1
        r["tfs"] = tfs
        r["n1"], r["n2"] = n1, n2
        r["comb"] = comb
        rows.append(r)
    with open(f"{outdir}/{cloud}{tag}.api-resources.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["service", "resource", "category", "attributes_total", "official_kinds", "ours_kinds",
                    "attributes_official", "attributes_ours_beyond", "attributes_tf_l1", "attributes_tf_l2",
                    "tf_gain_l1", "tf_gain_l2", "official_and_tf_l2", "ours_and_tf_l2", "tf_resources"])
        for r in rows:
            off = sum(n for (c, _, _), n in r["comb"].items() if c in ("official", "both"))
            ours = sum(n for (c, _, _), n in r["comb"].items() if c == "ours")
            g1 = sum(n for (c, l1, _), n in r["comb"].items() if c == "none" and l1)
            g2 = sum(n for (c, _, l2), n in r["comb"].items() if c == "none" and l2)
            oc = sum(n for (c, _, l2), n in r["comb"].items() if c in ("official", "both") and l2)
            uc = sum(n for (c, _, l2), n in r["comb"].items() if c == "ours" and l2)
            w.writerow([r["service"], r["resource"], r["category"], r["total"], r["official_kinds"], r["ours_kinds"],
                        off, ours, r["n1"], r["n2"], g1, g2, oc, uc, ";".join(r["tfs"])])

    def roll(group):
        agg = defaultdict(lambda: defaultdict(int))
        for r in rows:
            g = group(r)
            a = agg[g]
            a["resources"] += 1
            a["attrs"] += r["total"]
            a["res_official"] += bool(r["official_kinds"])
            a["res_ours_only"] += bool(r["ours_kinds"]) and not r["official_kinds"]
            a["res_tf"] += bool(r["tfs"])
            a["res_tf_not_oo"] += bool(r["tfs"]) and not (r["official_kinds"] or r["ours_kinds"])
            a["res_oo_not_tf"] += bool(r["official_kinds"] or r["ours_kinds"]) and not r["tfs"]
            for (c, l1, l2), n in r["comb"].items():
                if c in ("official", "both"):
                    a["official"] += n
                if c == "ours":
                    a["ours"] += n
                if c == "none":
                    a["none"] += n
                a["tf1"] += n * l1
                a["tf2"] += n * l2
                if c == "none":
                    a["gain1"] += n * l1
                    a["gain2"] += n * l2
                if c in ("official", "both", "ours") and not l2:
                    a["oo_not_tf2"] += n
                if c in ("official", "both", "ours") and not l1:
                    a["oo_not_tf1"] += n
                if c in ("official", "both", "ours") and l2:
                    a["oo_and_tf2"] += n
                if c in ("official", "both", "ours") and l1:
                    a["oo_and_tf1"] += n
        return agg

    hdr = ["resources", "attributes", "resources_official", "resources_ours_only", "resources_tf",
           "resources_tf_without_official_or_ours", "resources_official_or_ours_without_tf",
           "attributes_official", "attributes_ours_beyond", "attributes_tf_l1", "attributes_tf_l2",
           "pct_official", "pct_ours_beyond", "pct_tf_l1", "pct_tf_l2",
           "tf_gain_over_official_and_ours_l1", "tf_gain_over_official_and_ours_l2",
           "pct_gain_l1", "pct_gain_l2", "official_or_ours_not_in_tf_l2",
           "pct_uncovered_by_all_l2"]

    def line(label, a):
        n = a["attrs"]
        return [label, a["resources"], n, a["res_official"], a["res_ours_only"], a["res_tf"],
                a["res_tf_not_oo"], a["res_oo_not_tf"],
                a["official"], a["ours"], a["tf1"], a["tf2"],
                pct(a["official"], n), pct(a["ours"], n), pct(a["tf1"], n), pct(a["tf2"], n),
                a["gain1"], a["gain2"], pct(a["gain1"], n), pct(a["gain2"], n),
                a["oo_not_tf2"], pct(a["none"] - a["gain2"], n)]

    for fname, group, label in (
        ("categories", lambda r: r["category"], "category"),
        ("services", lambda r: (r["category"], r["service"]), "category/service"),
    ):
        agg = roll(group)
        with open(f"{outdir}/{cloud}{tag}.{fname}.csv", "w", newline="") as fh:
            w = csv.writer(fh)
            w.writerow([label] + hdr)
            for g, a in sorted(agg.items(), key=lambda x: str(x[0])):
                w.writerow(line("/".join(g) if isinstance(g, tuple) else g, a))
    agg = roll(lambda r: "all")
    print(cloud, "mapped TF resources:", len({m[0] for m in mapping}), "of", len(tf),
          "| API resources with a TF resource:", sum(1 for r in rows if r["tfs"]), "of", len(rows))
    for g, a in sorted(roll(lambda r: r["category"]).items()):
        print(" ", line(g, a)[:1] + line(g, a)[1:3] + line(g, a)[12:20])


if __name__ == "__main__":
    main()
