// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package offramp

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

// State is a Terraform state file, format version 4 (`terraform state
// pull`, or the file a backend keeps). Only what the converter reads.
type State struct {
	Version          int             `json:"version"`
	TerraformVersion string          `json:"terraform_version"`
	Resources        []StateResource `json:"resources"`
}

// StateResource is one resource block of a state, with its instances.
type StateResource struct {
	Module    string          `json:"module"`
	Mode      string          `json:"mode"`
	Type      string          `json:"type"`
	Name      string          `json:"name"`
	Provider  string          `json:"provider"`
	Instances []StateInstance `json:"instances"`
}

// StateInstance is one instance (count or for_each) of a resource.
type StateInstance struct {
	IndexKey     any            `json:"index_key"`
	Status       string         `json:"status"`
	Attributes   map[string]any `json:"attributes"`
	Dependencies []string       `json:"dependencies"`
	// SensitiveAttributes are the paths Terraform marks sensitive, each a
	// list of steps ({"type": "get_attr", "value": "password"}).
	SensitiveAttributes []any `json:"sensitive_attributes"`
}

// ReadState reads and checks a state file.
func ReadState(path string) (*State, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var s State
	if err := json.Unmarshal(b, &s); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	if s.Version != 4 {
		return nil, fmt.Errorf("%s: state format version %d; the converter reads version 4 (`terraform state pull`)", path, s.Version)
	}
	return &s, nil
}

// TFResource is one instance of a managed resource, as the converter
// handles it.
type TFResource struct {
	// Address is the instance's full address,
	// module.vpc.module.subnets.google_compute_subnetwork.subnetwork["us-central1/a"].
	Address string
	// Module is the module path (module.vpc.module.subnets), empty at the root.
	Module string
	// Call is the root module's call this instance belongs to (vpc), empty
	// for a resource declared in the root module itself.
	Call     string
	Type     string
	Name     string
	Provider string
	Mode     string
	Attrs    map[string]any
	// Deps are the addresses (without instance keys) this instance
	// depends on, as Terraform recorded them.
	Deps []string
	// Sensitive are the top-level attributes Terraform marks sensitive.
	Sensitive map[string]bool
}

// Instances flattens a state into resource instances, data sources
// included (Mode "data"), in the state's order.
func (s *State) Instances() []*TFResource {
	var out []*TFResource
	for _, r := range s.Resources {
		for _, in := range r.Instances {
			// A tainted instance is still the live resource, so it is
			// converted like any other.
			base := r.Type + "." + r.Name
			if r.Mode == "data" {
				base = "data." + base
			}
			if r.Module != "" {
				base = r.Module + "." + base
			}
			out = append(out, &TFResource{
				Address:   base + indexSuffix(in.IndexKey),
				Module:    r.Module,
				Call:      rootCall(r.Module),
				Type:      r.Type,
				Name:      r.Name,
				Provider:  r.Provider,
				Mode:      r.Mode,
				Attrs:     in.Attributes,
				Deps:      in.Dependencies,
				Sensitive: sensitiveTop(in.SensitiveAttributes),
			})
		}
	}
	return out
}

func indexSuffix(k any) string {
	switch v := k.(type) {
	case nil:
		return ""
	case string:
		b, _ := json.Marshal(v)
		return "[" + string(b) + "]"
	case float64:
		return fmt.Sprintf("[%d]", int64(v))
	default:
		return fmt.Sprintf("[%v]", v)
	}
}

// rootCall gives the first module call of a module path:
// module.vpc.module.subnets is vpc; module.x["a"] is x.
func rootCall(module string) string {
	if module == "" {
		return ""
	}
	rest := strings.TrimPrefix(module, "module.")
	end := len(rest)
	for i, c := range rest {
		if c == '.' || c == '[' {
			end = i
			break
		}
	}
	return rest[:end]
}

// ProviderName gives the short provider name of a state's provider
// string: provider["registry.terraform.io/hashicorp/google-beta"] is
// google-beta.
func ProviderName(p string) string {
	p = strings.TrimSuffix(strings.TrimPrefix(p, `provider["`), `"]`)
	if i := strings.LastIndex(p, "/"); i >= 0 {
		p = p[i+1:]
	}
	if i := strings.Index(p, "."); i >= 0 { // an alias
		p = p[:i]
	}
	return p
}

// sensitiveTop gives the first attribute of each sensitive path.
func sensitiveTop(paths []any) map[string]bool {
	out := map[string]bool{}
	for _, p := range paths {
		steps, ok := p.([]any)
		if !ok || len(steps) == 0 {
			continue
		}
		if m, ok := steps[0].(map[string]any); ok && m["type"] == "get_attr" {
			if v, ok := m["value"].(string); ok {
				out[v] = true
			}
		}
	}
	return out
}
