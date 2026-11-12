// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package offramp

import (
	"encoding/json"
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// Annotations the converter writes on every Config Connector object.
const (
	AnnDeletionPolicy = "cnrm.cloud.google.com/deletion-policy"
	AnnStateIntoSpec  = "cnrm.cloud.google.com/state-into-spec"
	AnnID             = "hfl.dev/id"
	// AnnAddress names where an object came from: a Terraform address, or
	// the asset's full resource name. A draft name (the design's
	// "Output shape").
	AnnAddress = "offramp.hfl.dev/source"
)

// Object is one Config Connector object made from one cloud resource.
type Object struct {
	// Source is the Terraform address or the asset name it came from.
	Source string
	// Call is the root module call it belongs to ("" for the root
	// module), or for a scan the group the converter put it in.
	Call   string
	TFType string
	Kind   string
	Obj    map[string]any
	// Deps are the Terraform addresses (without keys) it depends on.
	Deps []string
	// Labelled says that Config Connector writes this kind's cloud labels
	// from metadata.labels (and adds managed-by-cnrm), so adopting it
	// updates the resource unless that label is already there.
	Labelled bool
}

// Name is the object's metadata.name.
func (o *Object) Name() string { return str(dig(o.Obj, "metadata", "name")) }

// Finding is something the converter did not carry, or carried with a
// caveat.
type Finding struct {
	Source string `json:"source"`
	Type   string `json:"type"`
	// Class is one of: gap (a cloud resource with no Config Connector
	// kind), refused (a kind Bundt will not use), terraform-only (no
	// cloud resource: random_*, null_resource, time_sleep, data sources),
	// in-cluster (a Kubernetes object, not a cloud resource), note.
	Class  string `json:"class"`
	Reason string `json:"reason"`
}

// Result is a conversion's output.
type Result struct {
	Objects  []*Object
	Findings []Finding
}

// Options steer a conversion.
type Options struct {
	// DeletionPolicy is written on every object: abandon (the default for
	// an import) or delete.
	DeletionPolicy string
}

var terraformOnly = map[string]bool{
	"random": true, "null": true, "time": true, "local": true, "tls": true,
	"external": true, "terraform": true, "archive": true, "http": true,
}

// ConvertState converts a state's managed google resources to Config
// Connector objects.
func ConvertState(st *State, k *KCC, opt Options) *Result {
	res := &Result{}
	for _, r := range st.Instances() {
		prov := ProviderName(r.Provider)
		switch {
		case r.Mode == "data":
			res.Findings = append(res.Findings, Finding{r.Address, r.Type, "terraform-only", "a data source reads; there is nothing to adopt"})
			continue
		case terraformOnly[prov] || r.Type == "terraform_data":
			res.Findings = append(res.Findings, Finding{r.Address, r.Type, "terraform-only", "no cloud resource (" + prov + ")"})
			continue
		case prov == "kubernetes" || prov == "helm" || prov == "kubectl":
			res.Findings = append(res.Findings, Finding{r.Address, r.Type, "in-cluster", "a Kubernetes object, not a cloud resource: carry it as a plain manifest in the component that owns the cluster's contents, or leave it to the app"})
			continue
		case prov != "google" && prov != "google-beta":
			res.Findings = append(res.Findings, Finding{r.Address, r.Type, "gap", "provider " + prov + " is not converted"})
			continue
		}
		objs, f := convertResource(r, k)
		res.Findings = append(res.Findings, f...)
		for _, o := range objs {
			finish(o, opt)
			res.Objects = append(res.Objects, o)
		}
	}
	uniqueNames(res.Objects)
	return res
}

func convertResource(r *TFResource, k *KCC) ([]*Object, []Finding) {
	t := r.Type
	switch {
	case strings.HasSuffix(t, "_iam_policy"):
		return nil, []Finding{{r.Address, t, "refused", "an authoritative policy for the whole resource: Bundt never applies IAMPolicy (it would remove every grant made elsewhere). Convert it to members (IAMPolicyMember) or per-role bindings (IAMPartialPolicy), or leave it with Terraform"}}
	case strings.HasSuffix(t, "_iam_audit_config"):
		return nil, []Finding{{r.Address, t, "gap", "IAMAuditConfig is not converted yet"}}
	case strings.HasSuffix(t, "_iam_member"), strings.HasSuffix(t, "_iam_binding"):
		o, f := convertIAM(r, k)
		if o == nil {
			return nil, f
		}
		return []*Object{o}, f
	}
	if h, ok := special[t]; ok {
		return h(r, k)
	}
	sm := k.SM[t]
	var crd *CRD
	if sm != nil {
		crd = k.CRDs[sm.Kind]
	} else {
		crd = k.GuessKind(t)
	}
	if crd == nil {
		return nil, []Finding{{r.Address, t, "gap", "no Config Connector kind: keep it in Terraform, or close the gap in config-connector-extensions"}}
	}
	o, f := generic(r, k, sm, crd)
	return []*Object{o}, f
}

// generic maps a Terraform resource to its kind the way Config Connector's
// Terraform-based controllers do: the service mapping says which
// attributes are references, the resource ID, the container annotations
// and the directives; every other attribute is the spec field of the same
// name in lower camel case, when the kind has one.
func generic(r *TFResource, k *KCC, sm *SMResource, crd *CRD) (*Object, []Finding) {
	var findings []Finding
	attrs := r.Attrs
	used := map[string]bool{"id": true}
	spec := map[string]any{}
	ann := map[string]string{}
	var labels map[string]string
	var specProps map[string]*Schema
	if crd.Spec != nil {
		specProps = crd.Spec.Properties
	}
	nameBase := ""
	if sm != nil {
		if f := sm.ResourceID.TargetField; f != "" {
			if v := str(attrs[f]); v != "" {
				spec["resourceID"] = untemplate(sm.ResourceID.ValueTemplate, v)
			}
			used[f] = true
		}
		if f := sm.MetadataMapping.Name; f != "" {
			nameBase = str(attrs[f])
			used[f] = true
		}
		for _, ref := range sm.ResourceReferences {
			if ref.TFField == "" || strings.Contains(ref.TFField, ".") {
				continue
			}
			used[ref.TFField] = true
			v := attrs[ref.TFField]
			if empty(v) {
				continue
			}
			key := ref.Key
			if key == "" {
				key = pickType(ref.Types, v)
			}
			if key == "" || specProps[key] == nil {
				continue
			}
			spec[key] = refValue(v, specProps[key])
		}
		for _, c := range sm.Containers {
			used[c.TFField] = true
			v := str(attrs[c.TFField])
			if v == "" {
				continue
			}
			key := ""
			for _, h := range sm.HierarchicalReferences {
				if h.Type == c.Type {
					key = h.Key
				}
			}
			if key != "" && specProps[key] != nil {
				if _, set := spec[key]; !set {
					spec[key] = map[string]any{"external": v}
				}
				continue
			}
			ann["cnrm.cloud.google.com/"+c.Type+"-id"] = strings.TrimPrefix(strings.TrimPrefix(strings.TrimPrefix(v, "projects/"), "folders/"), "organizations/")
		}
		for _, d := range sm.Directives {
			used[d] = true
			if v, ok := attrs[d]; ok && v != nil {
				ann["cnrm.cloud.google.com/"+strings.ReplaceAll(d, "_", "-")] = scalarString(v)
			}
		}
		for _, f := range sm.IgnoredFields {
			used[f] = true
		}
		if l := sm.MetadataMapping.Labels; l != "" {
			labels = labelsOf(attrs, l)
			used[l] = true
		}
	} else {
		// A kind Config Connector generates from Terraform (v1alpha1) has
		// no service mapping in the repository: the name is the resource
		// ID and the project a reference or an annotation.
		if v := str(attrs["name"]); v != "" && specProps["resourceID"] != nil {
			spec["resourceID"] = v
		}
		nameBase = str(attrs["name"])
		used["name"] = true
		if p := str(attrs["project"]); p != "" {
			if specProps["projectRef"] != nil {
				spec["projectRef"] = map[string]any{"external": p}
			} else {
				ann["cnrm.cloud.google.com/project-id"] = p
			}
			used["project"] = true
		}
	}
	for _, l := range []string{"labels", "effective_labels", "terraform_labels"} {
		if _, ok := attrs[l]; ok && labels == nil && specProps["labels"] == nil {
			// The kind has no labels in the service mapping; Terraform's
			// computed label maps are not fields of the kind.
			used[l] = true
		}
	}
	used["effective_labels"], used["terraform_labels"] = true, true
	// Location: kinds with a location field take Terraform's region or zone.
	if specProps["location"] != nil && empty(attrs["location"]) {
		for _, f := range []string{"region", "zone"} {
			if v := str(attrs[f]); v != "" {
				spec["location"] = v
				used[f] = true
				break
			}
		}
	}
	nested := nestedRefs(sm)
	keys := sortedKeys(attrs)
	for _, a := range keys {
		if used[a] {
			continue
		}
		if r.Sensitive[a] {
			if !empty(attrs[a]) {
				findings = append(findings, Finding{r.Address, r.Type, "note", "the sensitive attribute " + a + " is not written into the object: give it as a reference to a Secret (or to Secret Manager) by hand"})
			}
			continue
		}
		v := attrs[a]
		if empty(v) {
			continue
		}
		key, s := specField(specProps, a)
		if s == nil {
			continue
		}
		if _, set := spec[key]; set {
			continue
		}
		cv, ok := convertValue(v, s, a, nested)
		if ok {
			spec[key] = cv
		}
	}
	if nameBase == "" {
		nameBase = str(spec["resourceID"])
	}
	if nameBase == "" {
		nameBase = r.Name
	}
	obj := map[string]any{
		"apiVersion": crd.APIVersion(),
		"kind":       crd.Kind,
		"metadata":   map[string]any{"name": sanitize(nameBase)},
	}
	if len(ann) > 0 {
		obj["metadata"].(map[string]any)["annotations"] = toAny(ann)
	}
	if len(labels) > 0 {
		obj["metadata"].(map[string]any)["labels"] = toAny(labels)
	}
	if crd.Spec != nil {
		obj["spec"] = spec
	}
	for _, req := range requiredOf(crd) {
		if _, ok := spec[req]; !ok {
			findings = append(findings, Finding{r.Address, r.Type, "note", fmt.Sprintf("%s's required field spec.%s has no value from the state", crd.Kind, req)})
		}
	}
	return &Object{Source: r.Address, Call: r.Call, TFType: r.Type, Kind: crd.Kind, Obj: obj, Deps: r.Deps, Labelled: sm != nil && sm.MetadataMapping.Labels != ""}, findings
}

func requiredOf(c *CRD) []string {
	if c.Spec == nil {
		return nil
	}
	return c.Spec.Required
}

// specField finds the spec field a Terraform attribute fills: the field of
// the same name in lower camel case, or, for a reference the service
// mapping does not list, the field named <name>Ref, or <singular>Refs for a
// list.
func specField(props map[string]*Schema, attr string) (string, *Schema) {
	c := camel(attr)
	if s := props[c]; s != nil {
		return c, s
	}
	if s := props[c+"Ref"]; s != nil && s.IsRef() {
		return c + "Ref", s
	}
	if strings.HasSuffix(c, "s") {
		if s := props[strings.TrimSuffix(c, "s")+"Refs"]; s != nil && s.Type == "array" {
			return strings.TrimSuffix(c, "s") + "Refs", s
		}
	}
	// Initialisms: Config Connector writes src_ip_ranges as srcIPRanges in
	// some kinds (ComputeFirewallPolicyRule).
	for k, s := range props {
		if strings.EqualFold(k, c) {
			return k, s
		}
	}
	return "", nil
}

// nestedRefs gives the service mapping's references inside nested
// blocks, by their Terraform path (secondary_ip_range.reserved_internal_range).
func nestedRefs(sm *SMResource) map[string]string {
	out := map[string]string{}
	if sm == nil {
		return out
	}
	for _, r := range sm.ResourceReferences {
		if strings.Contains(r.TFField, ".") && r.Key != "" {
			out[r.TFField] = r.Key
		}
	}
	return out
}

// convertValue converts a Terraform value to the shape the schema s has.
// path is the Terraform path, for nested references.
func convertValue(v any, s *Schema, path string, nested map[string]string) (any, bool) {
	if empty(v) || s == nil {
		return nil, false
	}
	switch s.Type {
	case "object":
		if s.IsRef() {
			return refValue(v, s), true
		}
		switch t := v.(type) {
		case []any:
			// A nested block with at most one element is a list in
			// Terraform and an object in Config Connector.
			if len(t) == 0 {
				return nil, false
			}
			m, ok := t[0].(map[string]any)
			if !ok {
				return nil, false
			}
			if cv, ok := convertObject(m, s, path, nested); ok {
				return cv, true
			}
			// The block is there with nothing set inside: its presence is
			// the setting (a secret's replication { auto {} }), so it stays,
			// empty.
			return map[string]any{}, true
		case map[string]any:
			if s.Properties == nil {
				return convertMap(t, s)
			}
			return convertObject(t, s, path, nested)
		case string:
			// A JSON document in a string (an organization policy's
			// parameters) is an object in Config Connector.
			var m map[string]any
			if json.Unmarshal([]byte(t), &m) == nil && len(m) > 0 {
				return m, true
			}
		}
		return nil, false
	case "array":
		list, ok := v.([]any)
		if !ok {
			return nil, false
		}
		var out []any
		for _, it := range list {
			if s.Items != nil && s.Items.IsRef() {
				if x := str(it); x != "" {
					out = append(out, map[string]any{"external": x})
				}
				continue
			}
			if cv, ok := convertValue(it, s.Items, path, nested); ok {
				out = append(out, cv)
			}
		}
		if len(out) == 0 {
			return nil, false
		}
		return out, true
	case "boolean":
		switch t := v.(type) {
		case bool:
			return t, true
		case string:
			b, err := strconv.ParseBool(strings.ToLower(t))
			if err == nil {
				return b, true
			}
		}
		return nil, false
	case "integer":
		switch t := v.(type) {
		case float64:
			if t == 0 {
				return nil, false
			}
			return int64(t), true
		case string:
			n, err := strconv.ParseInt(t, 10, 64)
			if err == nil && n != 0 {
				return n, true
			}
		}
		return nil, false
	case "number":
		switch t := v.(type) {
		case float64:
			if t == 0 {
				return nil, false
			}
			return t, true
		case string:
			n, err := strconv.ParseFloat(t, 64)
			if err == nil && n != 0 {
				return n, true
			}
		}
		return nil, false
	case "string":
		x := scalarString(v)
		if x == "" {
			return nil, false
		}
		return x, true
	default:
		// x-kubernetes-preserve-unknown-fields and the like: as is.
		return v, true
	}
}

func convertObject(m map[string]any, s *Schema, path string, nested map[string]string) (any, bool) {
	out := map[string]any{}
	for _, a := range sortedKeys(m) {
		v := m[a]
		if empty(v) {
			continue
		}
		p := path + "." + a
		if key, ok := nested[p]; ok && s.Properties[key] != nil {
			out[key] = refValue(v, s.Properties[key])
			continue
		}
		key, sub := specField(s.Properties, a)
		if sub == nil {
			continue
		}
		if cv, ok := convertValue(v, sub, p, nested); ok {
			out[key] = cv
		}
	}
	if len(out) == 0 {
		return nil, false
	}
	return out, true
}

func convertMap(m map[string]any, s *Schema) (any, bool) {
	out := map[string]any{}
	for k, v := range m {
		if s.AdditionalProperties != nil {
			if cv, ok := convertValue(v, s.AdditionalProperties, k, nil); ok {
				out[k] = cv
			}
			continue
		}
		out[k] = v
	}
	if len(out) == 0 {
		return nil, false
	}
	return out, true
}

// refValue makes a reference to something outside the converted set: the
// value Terraform holds, verbatim (a self link, an ID, an email). That is
// what Terraform sent the API and what Config Connector passes to the same
// Terraform field, so it never differs from the live value.
func refValue(v any, s *Schema) any {
	if list, ok := v.([]any); ok {
		if s != nil && s.Type == "array" {
			var out []any
			for _, it := range list {
				out = append(out, map[string]any{"external": str(it)})
			}
			return out
		}
		if len(list) > 0 {
			return map[string]any{"external": str(list[0])}
		}
	}
	if s != nil && s.Type == "array" {
		return []any{map[string]any{"external": str(v)}}
	}
	return map[string]any{"external": str(v)}
}

func pickType(types []SMType, v any) string {
	val := strings.ToLower(str(v))
	for _, t := range types {
		noun := strings.ToLower(strings.TrimPrefix(t.GVK.Kind, "Compute"))
		if noun != "" && strings.Contains(strings.ReplaceAll(val, "-", ""), noun) {
			return t.Key
		}
	}
	if len(types) > 0 {
		return types[0].Key
	}
	return ""
}

// untemplate inverts a valueTemplate such as folders/{{value}}.
func untemplate(tmpl, v string) string {
	if tmpl == "" {
		return v
	}
	i := strings.Index(tmpl, "{{value}}")
	if i < 0 {
		return v
	}
	return strings.TrimSuffix(strings.TrimPrefix(v, tmpl[:i]), tmpl[i+len("{{value}}"):])
}

func labelsOf(attrs map[string]any, field string) map[string]string {
	// Terraform 5+ keeps the labels it was given in `labels` and every
	// label on the resource in `effective_labels`. All of them go into
	// metadata.labels: Config Connector writes metadata.labels as the
	// resource's whole label set, so a label left out would be removed.
	src, _ := attrs["effective_labels"].(map[string]any)
	if len(src) == 0 {
		src, _ = attrs[field].(map[string]any)
	}
	if len(src) == 0 {
		return nil
	}
	out := map[string]string{}
	for k, v := range src {
		out[k] = str(v)
	}
	return out
}

// finish adds the annotations every imported object carries.
func finish(o *Object, opt Options) {
	md := o.Obj["metadata"].(map[string]any)
	ann, _ := md["annotations"].(map[string]any)
	if ann == nil {
		ann = map[string]any{}
	}
	dp := opt.DeletionPolicy
	if dp == "" {
		dp = "abandon"
	}
	ann[AnnDeletionPolicy] = dp
	ann[AnnStateIntoSpec] = "absent"
	ann[AnnAddress] = o.Source
	md["annotations"] = ann
}

// uniqueNames makes metadata.name unique per kind and gives every object an
// hfl.dev/id unique within its call (a Bundt component needs one per
// object when it renders two of a kind).
func uniqueNames(objs []*Object) {
	seen := map[string]int{}
	for _, o := range objs {
		md := o.Obj["metadata"].(map[string]any)
		n := str(md["name"])
		key := o.Kind + "/" + n
		seen[key]++
		if seen[key] > 1 {
			md["name"] = fitName(n, fmt.Sprintf("-%d", seen[key]))
		}
	}
	ids := map[string]int{}
	for _, o := range objs {
		md := o.Obj["metadata"].(map[string]any)
		id := sanitize(lowerFirst(o.Kind) + "-" + str(md["name"]))
		k := o.Call + "/" + id
		ids[k]++
		if ids[k] > 1 {
			id = fitName(id, fmt.Sprintf("-%d", ids[k]))
		}
		md["annotations"].(map[string]any)[AnnID] = id
	}
}

func lowerFirst(s string) string {
	if s == "" {
		return s
	}
	return strings.ToLower(s[:1]) + s[1:]
}

var nonName = regexp.MustCompile(`[^a-z0-9-]+`)

// sanitize makes an RFC 1123 label of at most 63 characters.
func sanitize(s string) string {
	s = strings.ToLower(s)
	s = nonName.ReplaceAllString(s, "-")
	s = strings.Trim(s, "-")
	for strings.Contains(s, "--") {
		s = strings.ReplaceAll(s, "--", "-")
	}
	if s == "" {
		s = "x"
	}
	if s[0] >= '0' && s[0] <= '9' {
		s = "n" + s
	}
	return fitName(s, "")
}

func fitName(s, suffix string) string {
	max := 63 - len(suffix)
	if len(s) > max {
		s = strings.TrimRight(s[:max], "-")
	}
	return s + suffix
}

// camel turns snake_case into lowerCamelCase as Config Connector does.
func camel(s string) string {
	parts := strings.Split(s, "_")
	for i := 1; i < len(parts); i++ {
		if parts[i] != "" {
			parts[i] = strings.ToUpper(parts[i][:1]) + parts[i][1:]
		}
	}
	return strings.Join(parts, "")
}

func empty(v any) bool {
	switch t := v.(type) {
	case nil:
		return true
	case string:
		return t == ""
	case []any:
		return len(t) == 0
	case map[string]any:
		return len(t) == 0
	}
	return false
}

func str(v any) string {
	switch t := v.(type) {
	case nil:
		return ""
	case string:
		return t
	default:
		return scalarString(v)
	}
}

func scalarString(v any) string {
	switch t := v.(type) {
	case string:
		return t
	case bool:
		return strconv.FormatBool(t)
	case float64:
		if t == float64(int64(t)) {
			return strconv.FormatInt(int64(t), 10)
		}
		return strconv.FormatFloat(t, 'f', -1, 64)
	case nil:
		return ""
	default:
		b, _ := json.Marshal(t)
		return string(b)
	}
}

func sortedKeys[V any](m map[string]V) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func toAny(m map[string]string) map[string]any {
	out := map[string]any{}
	for k, v := range m {
		out[k] = v
	}
	return out
}

func dig(m map[string]any, path ...string) any {
	var cur any = m
	for _, p := range path {
		mm, ok := cur.(map[string]any)
		if !ok {
			return nil
		}
		cur = mm[p]
	}
	return cur
}
