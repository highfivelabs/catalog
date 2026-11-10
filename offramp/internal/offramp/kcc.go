// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package offramp

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"sigs.k8s.io/yaml"
)

// Schema is the part of an OpenAPI v3 schema the converter reads.
type Schema struct {
	Type                 string             `json:"type"`
	Properties           map[string]*Schema `json:"properties"`
	AdditionalProperties *Schema            `json:"additionalProperties"`
	Items                *Schema            `json:"items"`
	Required             []string           `json:"required"`
}

// IsRef says whether s is a Config Connector reference: an object with
// an `external` field.
func (s *Schema) IsRef() bool {
	if s == nil || s.Type != "object" || s.Properties == nil {
		return false
	}
	_, ok := s.Properties["external"]
	return ok
}

// CRD is one Config Connector kind at its storage version.
type CRD struct {
	Group, Version, Kind string
	// Spec is nil for a kind with no spec (ComputeSharedVPCHostProject).
	Spec *Schema
}

// APIVersion is group/version.
func (c *CRD) APIVersion() string { return c.Group + "/" + c.Version }

// SMRef is one resourceReferences entry of a service mapping.
type SMRef struct {
	Key           string   `json:"key"`
	TFField       string   `json:"tfField"`
	TargetField   string   `json:"targetField"`
	ValueTemplate string   `json:"valueTemplate"`
	GVK           GVK      `json:"gvk"`
	Types         []SMType `json:"types"`
}

// SMType is one kind a multi-kind reference may name.
type SMType struct {
	Key         string `json:"key"`
	TargetField string `json:"targetField"`
	GVK         GVK    `json:"gvk"`
}

// GVK names a kind.
type GVK struct {
	Group   string `json:"group"`
	Version string `json:"version"`
	Kind    string `json:"kind"`
}

// SMResource is one resource of a Config Connector service mapping: how a
// Terraform resource type maps to a kind. The converter reads the same
// files Config Connector does (config/servicemappings), so a Terraform-based
// kind is mapped as Config Connector itself maps it.
type SMResource struct {
	Name            string `json:"name"`
	Kind            string `json:"kind"`
	IDTemplate      string `json:"idTemplate"`
	MetadataMapping struct {
		Name   string `json:"name"`
		Labels string `json:"labels"`
	} `json:"metadataMapping"`
	ResourceID struct {
		TargetField   string `json:"targetField"`
		ValueTemplate string `json:"valueTemplate"`
	} `json:"resourceID"`
	ServerGeneratedIDField string   `json:"serverGeneratedIDField"`
	IgnoredFields          []string `json:"ignoredFields"`
	Directives             []string `json:"directives"`
	IAMConfig              struct {
		PolicyName       string `json:"policyName"`
		PolicyMemberName string `json:"policyMemberName"`
		ReferenceField   struct {
			Name string `json:"name"`
			Type string `json:"type"`
		} `json:"referenceField"`
	} `json:"iamConfig"`
	ResourceReferences []SMRef `json:"resourceReferences"`
	Containers         []struct {
		Type          string `json:"type"`
		TFField       string `json:"tfField"`
		ValueTemplate string `json:"valueTemplate"`
	} `json:"containers"`
	HierarchicalReferences []struct {
		Type string `json:"type"`
		Key  string `json:"key"`
	} `json:"hierarchicalReferences"`
	Locationality string `json:"locationality"`
}

// KCC is what the converter knows of one Config Connector release: its
// kinds' schemas and its service mappings.
type KCC struct {
	CRDs map[string]*CRD // by kind
	// SM maps a Terraform resource type to its service mapping entry.
	SM map[string]*SMResource
	// IAMBase maps a Terraform IAM type (google_x_iam_member, _binding,
	// _policy) to the service mapping entry of the resource it is on.
	IAMBase map[string]*SMResource
}

// LoadKCC reads config/crds/resources and config/servicemappings under dir,
// a Config Connector checkout (or a copy of those two directories).
func LoadKCC(dir string) (*KCC, error) {
	k := &KCC{CRDs: map[string]*CRD{}, SM: map[string]*SMResource{}, IAMBase: map[string]*SMResource{}}
	crdFiles, err := filepath.Glob(filepath.Join(dir, "config", "crds", "resources", "*.yaml"))
	if err != nil {
		return nil, err
	}
	if len(crdFiles) == 0 {
		return nil, fmt.Errorf("no CRDs under %s/config/crds/resources", dir)
	}
	for _, f := range crdFiles {
		c, err := loadCRD(f)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", f, err)
		}
		if c != nil {
			k.CRDs[c.Kind] = c
		}
	}
	smFiles, err := filepath.Glob(filepath.Join(dir, "config", "servicemappings", "*.yaml"))
	if err != nil {
		return nil, err
	}
	for _, f := range smFiles {
		b, err := os.ReadFile(f)
		if err != nil {
			return nil, err
		}
		var doc struct {
			Spec struct {
				Resources []*SMResource `json:"resources"`
			} `json:"spec"`
		}
		if err := yaml.Unmarshal(b, &doc); err != nil {
			return nil, fmt.Errorf("%s: %w", f, err)
		}
		for _, r := range doc.Spec.Resources {
			// Several Terraform types may map to one kind and one type to
			// several kinds (Config Connector's multiplexed kinds); the
			// first entry wins, as for Config Connector's own export.
			if _, seen := k.SM[r.Name]; !seen {
				k.SM[r.Name] = r
			}
			if p := r.IAMConfig.PolicyMemberName; p != "" {
				base := strings.TrimSuffix(p, "_member")
				for _, t := range []string{p, base + "_binding", r.IAMConfig.PolicyName} {
					if t != "" {
						if _, seen := k.IAMBase[t]; !seen {
							k.IAMBase[t] = r
						}
					}
				}
			}
		}
	}
	return k, nil
}

func loadCRD(path string) (*CRD, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	j, err := yaml.YAMLToJSON(b)
	if err != nil {
		return nil, err
	}
	var doc struct {
		Kind string `json:"kind"`
		Spec struct {
			Group string `json:"group"`
			Names struct {
				Kind string `json:"kind"`
			} `json:"names"`
			Versions []struct {
				Name    string `json:"name"`
				Storage bool   `json:"storage"`
				Schema  struct {
					OpenAPIV3Schema *Schema `json:"openAPIV3Schema"`
				} `json:"schema"`
			} `json:"versions"`
		} `json:"spec"`
	}
	if err := json.Unmarshal(j, &doc); err != nil {
		return nil, err
	}
	if doc.Kind != "CustomResourceDefinition" {
		return nil, nil
	}
	for _, v := range doc.Spec.Versions {
		if !v.Storage {
			continue
		}
		c := &CRD{Group: doc.Spec.Group, Version: v.Name, Kind: doc.Spec.Names.Kind}
		if s := v.Schema.OpenAPIV3Schema; s != nil && s.Properties != nil {
			c.Spec = s.Properties["spec"]
		}
		return c, nil
	}
	return nil, fmt.Errorf("no storage version")
}

// Kinds lists the loaded kinds, sorted.
func (k *KCC) Kinds() []string {
	out := make([]string, 0, len(k.CRDs))
	for n := range k.CRDs {
		out = append(out, n)
	}
	sort.Strings(out)
	return out
}

// GuessKind finds the kind of a Terraform type that has no service mapping
// entry, as Config Connector names the kinds it generates from Terraform
// (v1alpha1): google_compute_network_firewall_policy_rule is
// ComputeNetworkFirewallPolicyRule.
func (k *KCC) GuessKind(tfType string) *CRD {
	name := strings.TrimPrefix(tfType, "google_")
	parts := strings.Split(name, "_")
	var b strings.Builder
	for _, p := range parts {
		if p == "" {
			continue
		}
		b.WriteString(strings.ToUpper(p[:1]) + p[1:])
	}
	if c, ok := k.CRDs[b.String()]; ok {
		return c
	}
	// Config Connector capitalises some acronyms (ComputeSharedVPCHostProject).
	for kind, c := range k.CRDs {
		if strings.EqualFold(kind, b.String()) {
			return c
		}
	}
	return nil
}
