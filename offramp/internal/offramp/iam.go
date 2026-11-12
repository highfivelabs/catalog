// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package offramp

import (
	"crypto/sha256"
	"encoding/hex"
	"regexp"
	"strings"
)

// iamBindingAPIVersion is IAMBinding's group and version
// (config-connector-extensions; the catalog's
// crds/config-connector-extensions/iam.gcp.hfl.dev_iambindings.yaml).
const iamBindingAPIVersion = "iam.gcp.hfl.dev/v1beta1"

// iamBindingKinds are the resource kinds IAMBinding takes
// (config-connector-extensions pkg/iampolicy/registry.go), the same list as
// the catalog's lib/_kcc.tpl, kcc.iam.
var iamBindingKinds = map[string]bool{
	"Project": true, "Folder": true, "Organization": true, "IAMServiceAccount": true,
	"StorageBucket": true, "SecretManagerSecret": true, "ArtifactRegistryRepository": true,
	"RunService": true, "PubSubTopic": true, "PubSubSubscription": true,
	"KMSKeyRing": true, "KMSCryptoKey": true,
}

// convertIAM converts google_<x>_iam_member to an IAMPolicyMember and
// google_<x>_iam_binding (authoritative for one role, and its condition) to
// one IAMBinding (config-connector-extensions), exact as Terraform's, as
// the catalog's charts render it (docs/design.md, "IAM"). On a resource
// IAMBinding does not take (a subnet) the binding becomes an
// IAMPartialPolicy with one binding, as the charts fall back to, the
// closest kind that does not own the whole policy.
func convertIAM(r *TFResource, k *KCC) (*Object, []Finding) {
	base := k.IAMBase[r.Type]
	if base == nil {
		return nil, []Finding{{r.Address, r.Type, "gap", "IAM on a resource Config Connector's IAM kinds cannot reference"}}
	}
	baseCRD := k.CRDs[base.Kind]
	if baseCRD == nil {
		return nil, []Finding{{r.Address, r.Type, "gap", "the resource's kind " + base.Kind + " is not loaded"}}
	}
	ref := str(r.Attrs[base.IAMConfig.ReferenceField.Name])
	if ref != "" && !strings.Contains(ref, "/") && base.IDTemplate != "" {
		ref = expandID(base.IDTemplate, r.Attrs, ref)
	}
	resourceRef := map[string]any{"apiVersion": baseCRD.APIVersion(), "kind": base.Kind, "external": ref}
	role := str(r.Attrs["role"])
	cond := condition(r.Attrs["condition"])
	var findings []Finding
	member := strings.HasSuffix(r.Type, "_iam_member")
	exact := !member && iamBindingKinds[base.Kind]
	kind := "IAMPartialPolicy"
	switch {
	case member:
		kind = "IAMPolicyMember"
	case exact:
		kind = "IAMBinding"
	}
	apiVersion := iamBindingAPIVersion
	if !exact {
		crd := k.CRDs[kind]
		if crd == nil {
			return nil, []Finding{{r.Address, r.Type, "gap", "no " + kind + " kind loaded"}}
		}
		apiVersion = crd.APIVersion()
	}
	spec := map[string]any{"resourceRef": resourceRef}
	var who string
	if member {
		who = str(r.Attrs["member"])
		spec["member"] = who
		spec["role"] = role
		if cond != nil {
			spec["condition"] = cond
		}
	} else if exact {
		raw, _ := r.Attrs["members"].([]any)
		if len(raw) == 0 {
			return nil, []Finding{{r.Address, r.Type, "refused", "an authoritative binding with no members empties the role; an IAMBinding needs at least one member"}}
		}
		var members []any
		for _, m := range raw {
			members = append(members, str(m))
			who += str(m) + ","
		}
		spec["role"] = role
		spec["members"] = members
		if cond != nil {
			spec["condition"] = cond
		}
	} else {
		var members []any
		raw, _ := r.Attrs["members"].([]any)
		for _, m := range raw {
			members = append(members, map[string]any{"member": str(m)})
			who += str(m) + ","
		}
		b := map[string]any{"role": role, "members": members}
		if cond != nil {
			b["condition"] = cond
		}
		spec["bindings"] = []any{b}
		findings = append(findings, Finding{r.Address, r.Type, "note", "an authoritative binding on a " + base.Kind + ", which IAMBinding does not take, becomes IAMPartialPolicy: the listed members are kept, and members added outside it are no longer removed"})
	}
	name := sanitize(lastSegment(ref) + "-" + lastSegment(role) + "-" + shortHash(who+str(cond)))
	obj := map[string]any{
		"apiVersion": apiVersion,
		"kind":       kind,
		"metadata":   map[string]any{"name": name},
		"spec":       spec,
	}
	return &Object{Source: r.Address, Call: r.Call, TFType: r.Type, Kind: kind, Obj: obj, Deps: r.Deps}, findings
}

func condition(v any) map[string]any {
	list, ok := v.([]any)
	if !ok || len(list) == 0 {
		return nil
	}
	m, ok := list[0].(map[string]any)
	if !ok {
		return nil
	}
	out := map[string]any{}
	for _, f := range []string{"title", "description", "expression"} {
		if s := str(m[f]); s != "" {
			out[f] = s
		}
	}
	if len(out) == 0 {
		return nil
	}
	return out
}

var templateVar = regexp.MustCompile(`\{\{(\w+)\??\}\}`)

// expandID fills a service mapping's idTemplate from the attributes, the
// bare name standing for {{name}}.
func expandID(tmpl string, attrs map[string]any, name string) string {
	if i := strings.Index(tmpl, "["); i >= 0 { // alternatives: keep the first
		tmpl = tmpl[:i]
	}
	missing := false
	out := templateVar.ReplaceAllStringFunc(tmpl, func(m string) string {
		v := templateVar.FindStringSubmatch(m)[1]
		if v == "name" {
			return name
		}
		s := str(attrs[v])
		if s == "" {
			missing = true
		}
		return s
	})
	if missing {
		return name
	}
	return out
}

func lastSegment(s string) string {
	if i := strings.LastIndex(s, "/"); i >= 0 {
		return s[i+1:]
	}
	return s
}

func shortHash(s string) string {
	h := sha256.Sum256([]byte(s))
	return hex.EncodeToString(h[:])[:6]
}
