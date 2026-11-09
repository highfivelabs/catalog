#!/usr/bin/env python3
# Copyright 2026 High Five Labs
# SPDX-License-Identifier: Apache-2.0
"""Flatten `tofu providers schema -json` into CSVs.

usage: flatten.py schema.json OUTPREFIX

Writes OUTPREFIX.tf-resources.csv (provider, resource, attributes, writable,
required, deprecated, blocks, datasource_only=0) and
OUTPREFIX.attributes.csv.gz (provider, resource, path, type, required,
optional, computed, deprecated), one row per leaf. Paths use `[]` for
lists and sets and `{}` for maps, like docs/coverage of the three
extensions repositories. Only resources are read, not data sources.
"""
import csv
import gzip
import json
import sys

PRIM = {"string", "number", "bool", "dynamic"}


def short(t):
    if isinstance(t, str):
        return t
    if isinstance(t, list) and t and t[0] in ("list", "set", "map"):
        return t[0] + "(" + short(t[1]) + ")"
    if isinstance(t, list) and t and t[0] == "object":
        return "object"
    return "other"


def walk_type(t, path, flags, out):
    """Leaves of a cty type (an attribute declared with a type, not blocks)."""
    if isinstance(t, str):
        out.append((path, t) + flags)
        return
    kind = t[0]
    if kind in ("list", "set", "map"):
        mark = "{}" if kind == "map" else "[]"
        el = t[1]
        if isinstance(el, list) and el and el[0] == "object":
            walk_object(el[1], path + mark, flags, out)
        elif isinstance(el, list) and el and el[0] in ("list", "set", "map"):
            walk_type(el, path + mark, flags, out)
        else:
            out.append((path + mark, short(el)) + flags)
    elif kind == "object":
        walk_object(t[1], path, flags, out)
    else:
        out.append((path, "other") + flags)


def walk_object(fields, path, flags, out):
    if not fields:
        out.append((path, "object") + flags)
        return
    for k, v in sorted(fields.items()):
        walk_type(v, path + "." + k if path else k, flags, out)


def walk_block(block, prefix, out):
    for name, a in sorted((block.get("attributes") or {}).items()):
        path = prefix + name
        flags = (
            bool(a.get("required")),
            bool(a.get("optional")),
            bool(a.get("computed")),
            bool(a.get("deprecated")),
        )
        if "nested_type" in a:
            nt = a["nested_type"]
            mode = nt.get("nesting_mode", "single")
            mark = {"list": "[]", "set": "[]", "map": "{}"}.get(mode, "")
            walk_block(nt, path + mark + ".", out)
        else:
            walk_type(a["type"], path, flags, out)
    for name, b in sorted((block.get("block_types") or {}).items()):
        mode = b.get("nesting_mode", "single")
        mark = {"list": "[]", "set": "[]", "map": "{}"}.get(mode, "")
        sub = b["block"]
        n0 = len(out)
        walk_block(sub, prefix + name + mark + ".", out)
        if len(out) == n0:  # an empty block is still a setting
            out.append((prefix + name + mark, "block", False, True, False,
                        bool(b.get("block", {}).get("deprecated"))))


def main():
    schema_file, outprefix = sys.argv[1], sys.argv[2]
    schema = json.load(open(schema_file))
    res_rows = []
    with gzip.open(outprefix + ".attributes.csv.gz", "wt", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["provider", "resource", "path", "type", "required",
                    "optional", "computed", "deprecated"])
        for pname, p in sorted(schema["provider_schemas"].items()):
            pshort = pname.rsplit("/", 1)[-1]
            for rname, r in sorted((p.get("resource_schemas") or {}).items()):
                leaves = []
                walk_block(r["block"], "", leaves)
                nreq = nwrite = ndep = 0
                for path, typ, req, opt, comp, dep in leaves:
                    w.writerow([pshort, rname, path, typ, int(req), int(opt),
                                int(comp), int(dep)])
                    if req or opt:
                        nwrite += 1
                    if req:
                        nreq += 1
                    if dep:
                        ndep += 1
                res_rows.append([pshort, rname, len(leaves), nwrite, nreq,
                                 ndep, len(r["block"].get("block_types") or {})])
    with open(outprefix + ".tf-resources.csv", "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["provider", "resource", "attributes", "writable",
                    "required", "deprecated", "blocks"])
        w.writerows(res_rows)
    print(outprefix, len(res_rows), "resources")


main()
