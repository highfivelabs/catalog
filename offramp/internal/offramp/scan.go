// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package offramp

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"sigs.k8s.io/yaml"
)

// Asset is one record of a Cloud Asset Inventory listing (`gcloud asset
// list --content-type=resource --format=json`, or offramp/hack/scan.sh's
// fallback, which writes the same fields from the services' own list
// calls).
type Asset struct {
	Name      string   `json:"name"`
	AssetType string   `json:"assetType"`
	Ancestors []string `json:"ancestors"`
	Resource  struct {
		Data   map[string]any `json:"data"`
		Parent string         `json:"parent"`
	} `json:"resource"`
	// Source says how the record was found: cloudasset, or the fallback's
	// service list call.
	Source string `json:"source"`
}

// ReadAssets reads a JSON array of assets.
func ReadAssets(path string) ([]Asset, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var out []Asset
	if err := json.Unmarshal(b, &out); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	return out, nil
}

// systemAsset says whether an asset is made by Google Cloud itself rather
// than by anyone's configuration, so it is not imported: a network's
// default routes, the default network's rules, Google-managed service
// accounts.
func systemAsset(a Asset) (bool, string) {
	d := a.Resource.Data
	name := str(d["name"])
	switch a.AssetType {
	case "compute.googleapis.com/Route":
		if strings.HasPrefix(name, "default-route-") || strings.HasPrefix(str(d["description"]), "Default ") {
			return true, "a route Google Cloud makes for every network or subnet"
		}
	case "iam.googleapis.com/ServiceAccount":
		email := str(d["email"])
		if strings.Contains(email, "gserviceaccount.com") && (strings.Contains(email, "@developer.") || strings.Contains(email, "@appspot.") || strings.Contains(email, "@cloudservices.")) {
			return true, "a default or Google-managed service account"
		}
	case "serviceusage.googleapis.com/Service":
		return false, ""
	}
	return false, ""
}

// ExportNames lists the full resource names `config-connector export`
// takes, one per line, leaving out what Google Cloud makes itself.
func ExportNames(assets []Asset) (names []string, skipped []Finding) {
	for _, a := range assets {
		if sys, why := systemAsset(a); sys {
			skipped = append(skipped, Finding{a.Name, a.AssetType, "terraform-only", why + "; not imported"})
			continue
		}
		names = append(names, a.Name)
	}
	return names, skipped
}

// ReadKRM reads every YAML document under dir (a file or a directory, as
// `config-connector export` or bulk-export writes them).
func ReadKRM(path string) ([]map[string]any, error) {
	var files []string
	st, err := os.Stat(path)
	if err != nil {
		return nil, err
	}
	if st.IsDir() {
		err := filepath.WalkDir(path, func(p string, d os.DirEntry, err error) error {
			if err == nil && !d.IsDir() && (strings.HasSuffix(p, ".yaml") || strings.HasSuffix(p, ".yml")) {
				files = append(files, p)
			}
			return err
		})
		if err != nil {
			return nil, err
		}
		sort.Strings(files)
	} else {
		files = []string{path}
	}
	var out []map[string]any
	for _, f := range files {
		b, err := os.ReadFile(f)
		if err != nil {
			return nil, err
		}
		for _, doc := range bytes.Split(b, []byte("\n---")) {
			doc = bytes.TrimSpace(bytes.TrimPrefix(bytes.TrimSpace(doc), []byte("---")))
			if len(doc) == 0 {
				continue
			}
			var m map[string]any
			if err := yaml.Unmarshal(doc, &m); err != nil {
				return nil, fmt.Errorf("%s: %w", f, err)
			}
			if m != nil && m["kind"] != nil {
				out = append(out, m)
			}
		}
	}
	return out, nil
}

// family groups a scanned object into a component when there is no
// Terraform module to say which one: the foundations a platform team owns
// by area. Telling the platform's part from an application's is the quiz's
// job (the design, "The boundary").
func family(kind string) string {
	switch {
	case kind == "Folder" || kind == "Project" || strings.HasPrefix(kind, "OrgPolicy") || kind == "ResourceManagerPolicy" || kind == "ResourceManagerLien" ||
		kind == "ComputeFirewallPolicy" || kind == "ComputeFirewallPolicyRule" || kind == "ComputeFirewallPolicyAssociation":
		return "hierarchy"
	case strings.HasPrefix(kind, "Compute") && (strings.Contains(kind, "Network") || strings.Contains(kind, "Subnetwork") || strings.Contains(kind, "Firewall") ||
		strings.Contains(kind, "Route") || strings.Contains(kind, "SharedVPC") || strings.Contains(kind, "Address")):
		return "network"
	case kind == "Service":
		return "services"
	case kind == "IAMServiceAccount":
		return "identity"
	case strings.HasPrefix(kind, "Container"):
		return "gke"
	}
	return "other"
}

// ConvertKRM prepares exported objects for an import: it drops status and
// what the exporter adds that is not desired state, adds the import's
// annotations, and puts IAM objects with the component of the resource
// they are on.
func ConvertKRM(docs []map[string]any, opt Options) *Result {
	res := &Result{}
	familyOf := map[string]string{} // kind/external -> family
	for _, d := range docs {
		delete(d, "status")
		md, _ := d["metadata"].(map[string]any)
		if md == nil {
			md = map[string]any{}
			d["metadata"] = md
		}
		for _, f := range []string{"creationTimestamp", "generation", "resourceVersion", "uid", "managedFields", "namespace"} {
			delete(md, f)
		}
		kind := str(d["kind"])
		o := &Object{Kind: kind, Obj: d, Source: str(dig(d, "metadata", "annotations", "cnrm.cloud.google.com/source"))}
		if o.Source == "" {
			o.Source = kind + "/" + str(md["name"])
		}
		if strings.HasPrefix(kind, "IAM") && kind != "IAMServiceAccount" {
			o.Call = "" // decided below
		} else {
			o.Call = family(kind)
			if id := str(dig(d, "spec", "resourceID")); id != "" {
				familyOf[kind+"/"+id] = o.Call
			}
		}
		res.Objects = append(res.Objects, o)
	}
	for _, o := range res.Objects {
		if o.Call != "" {
			continue
		}
		refKind := str(dig(o.Obj, "spec", "resourceRef", "kind"))
		ext := str(dig(o.Obj, "spec", "resourceRef", "external"))
		o.Call = familyOf[refKind+"/"+lastSegment(ext)]
		if o.Call == "" {
			o.Call = family(refKind)
		}
		if o.Call == "other" {
			o.Call = "iam"
		}
	}
	for _, o := range res.Objects {
		finish(o, opt)
	}
	uniqueNames(res.Objects)
	return res
}
