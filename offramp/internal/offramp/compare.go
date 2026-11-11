// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package offramp

import (
	"encoding/json"
	"fmt"
	"reflect"
	"sort"
	"strings"
)

// Identity is what names the cloud resource an object stands for: its kind
// and resource ID, and where it lives. Two objects with one identity adopt
// one resource.
func Identity(o map[string]any) string {
	kind := str(o["kind"])
	spec, _ := o["spec"].(map[string]any)
	switch kind {
	case "IAMPolicyMember":
		return fmt.Sprintf("%s %s %s %s", kind, normRef(dig(spec, "resourceRef", "external")), str(spec["role"]), str(spec["member"]))
	case "IAMPartialPolicy":
		return fmt.Sprintf("%s %s", kind, normRef(dig(spec, "resourceRef", "external")))
	}
	id := str(spec["resourceID"])
	if id == "" {
		id = str(dig(o, "metadata", "name"))
	}
	where := str(dig(o, "metadata", "annotations", "cnrm.cloud.google.com/project-id"))
	if where == "" {
		where = normRef(dig(spec, "projectRef", "external"))
	}
	for _, f := range []string{"region", "location", "zone"} {
		if s := str(spec[f]); s != "" {
			where += "/" + s
		}
	}
	return strings.TrimSpace(fmt.Sprintf("%s %s %s", kind, where, id))
}

// normRef turns a self link or a relative name into the relative name:
// https://www.googleapis.com/compute/v1/projects/p/global/networks/n is
// projects/p/global/networks/n.
func normRef(v any) string {
	s := str(v)
	for _, p := range []string{"https://www.googleapis.com/compute/v1/", "https://www.googleapis.com/compute/beta/", "https://compute.googleapis.com/compute/v1/"} {
		s = strings.TrimPrefix(s, p)
	}
	return strings.TrimPrefix(s, "projects/")
}

// Difference is one way two object sets disagree.
type Difference struct {
	Identity string
	Path     string
	A, B     any
}

func (d Difference) String() string {
	switch {
	case d.Path == "" && d.B == nil:
		return fmt.Sprintf("%s: only in the first", d.Identity)
	case d.Path == "" && d.A == nil:
		return fmt.Sprintf("%s: only in the second", d.Identity)
	}
	return fmt.Sprintf("%s: %s: %v != %v", d.Identity, d.Path, d.A, d.B)
}

// Compare matches two object sets by identity and lists their differences
// in spec (references compared by relative name).
func Compare(a, b []map[string]any) []Difference {
	ia, ib := index(a), index(b)
	var out []Difference
	for _, id := range sortedKeys(ia) {
		y, ok := ib[id]
		if !ok {
			out = append(out, Difference{Identity: id, A: true})
			continue
		}
		diffValue(id, "spec", ia[id]["spec"], y["spec"], &out)
	}
	for _, id := range sortedKeys(ib) {
		if _, ok := ia[id]; !ok {
			out = append(out, Difference{Identity: id, B: true})
		}
	}
	return out
}

// index keys objects by identity. An IAMPartialPolicy counts as one
// IAMPolicyMember per member and role, so a Terraform binding and an
// export's members of the same grants match.
func index(objs []map[string]any) map[string]map[string]any {
	out := map[string]map[string]any{}
	for _, o := range objs {
		if str(o["kind"]) != "IAMPartialPolicy" {
			out[Identity(o)] = o
			continue
		}
		ref := dig(o, "spec", "resourceRef")
		bs, _ := dig(o, "spec", "bindings").([]any)
		for _, b := range bs {
			bm, _ := b.(map[string]any)
			ms, _ := bm["members"].([]any)
			for _, m := range ms {
				spec := map[string]any{"resourceRef": ref, "role": bm["role"], "member": dig(m.(map[string]any), "member")}
				if c := bm["condition"]; c != nil {
					spec["condition"] = c
				}
				pm := map[string]any{"kind": "IAMPolicyMember", "spec": spec}
				out[Identity(pm)] = pm
			}
		}
	}
	return out
}

func diffValue(id, path string, a, b any, out *[]Difference) {
	am, aok := a.(map[string]any)
	bm, bok := b.(map[string]any)
	if aok && bok {
		if ext, ok := am["external"]; ok {
			if !refEqual(ext, bm["external"]) {
				*out = append(*out, Difference{id, path, ext, bm["external"]})
			}
			return
		}
		keys := map[string]bool{}
		for k := range am {
			keys[k] = true
		}
		for k := range bm {
			keys[k] = true
		}
		var ks []string
		for k := range keys {
			ks = append(ks, k)
		}
		sort.Strings(ks)
		for _, k := range ks {
			diffValue(id, path+"."+k, am[k], bm[k], out)
		}
		return
	}
	if zero(a) && zero(b) {
		// An exporter leaves out a false, a zero or an empty value that
		// the state writes: the same desired state.
		return
	}
	al, aok := a.([]any)
	bl, bok := b.([]any)
	if aok && bok && len(al) == len(bl) {
		// Terraform sets (a firewall's allow blocks) have no order.
		al, bl = sortedCopy(al), sortedCopy(bl)
		for i := range al {
			diffValue(id, fmt.Sprintf("%s[%d]", path, i), al[i], bl[i], out)
		}
		return
	}
	if !reflect.DeepEqual(normalizeScalar(a), normalizeScalar(b)) {
		*out = append(*out, Difference{id, path, a, b})
	}
}

func zero(v any) bool {
	switch t := v.(type) {
	case nil:
		return true
	case bool:
		return !t
	case string:
		return t == ""
	case float64:
		return t == 0
	case int64:
		return t == 0
	case int:
		return t == 0
	case []any:
		return len(t) == 0
	case map[string]any:
		return len(t) == 0
	}
	return false
}

func sortedCopy(l []any) []any {
	out := append([]any(nil), l...)
	key := func(v any) string { b, _ := json.Marshal(v); return string(b) }
	sort.SliceStable(out, func(i, j int) bool { return key(out[i]) < key(out[j]) })
	return out
}

func normalizeScalar(v any) any {
	switch t := v.(type) {
	case int:
		return float64(t)
	case int64:
		return float64(t)
	case float64:
		return t
	case string:
		return normRef(t)
	}
	return v
}

// refEqual compares two references by relative name; a bare name (what a
// configuration gives, and what a planned state holds) matches a path in
// the same scope that ends with it.
func refEqual(a, b any) bool {
	x, y := normRef(a), normRef(b)
	if x == y {
		return true
	}
	if !strings.Contains(x, "/") && x != "" {
		return lastSegment(y) == x
	}
	if !strings.Contains(y, "/") && y != "" {
		return lastSegment(x) == y
	}
	return false
}
