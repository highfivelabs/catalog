// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package offramp

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"sigs.k8s.io/yaml"
)

// MarshalDocs writes YAML documents separated by ---.
func MarshalDocs(docs []map[string]any) ([]byte, error) {
	var buf bytes.Buffer
	for i, d := range docs {
		if i > 0 {
			buf.WriteString("---\n")
		}
		b, err := yaml.Marshal(d)
		if err != nil {
			return nil, err
		}
		buf.Write(b)
	}
	return buf.Bytes(), nil
}

// Write writes a conversion's output under dir:
//
//	krm/all.yaml                   every Config Connector object, for a plain kubectl apply
//	packages/<package>/manifests/  each component's objects, one file per object: the
//	                               files of its Package's manifests artifact
//	bundt/prereqs.yaml             the Team and the Target the record names
//	bundt/catalog.yaml             the Packages and the Template (one plan)
//	bundt/record.yaml              the Environment, the Stack and the Instance (a second plan)
//	report.md                      what became what, and what was not carried
func Write(dir string, res *Result, b *Bundle, header string) error {
	for _, d := range []string{"krm", "bundt", "packages"} {
		if err := os.MkdirAll(filepath.Join(dir, d), 0o755); err != nil {
			return err
		}
	}
	var all []map[string]any
	for _, o := range res.Objects {
		all = append(all, o.Obj)
	}
	if err := writeDocs(filepath.Join(dir, "krm", "all.yaml"), all); err != nil {
		return err
	}
	for _, c := range b.Components {
		md := filepath.Join(dir, "packages", c.Package, "manifests")
		if err := os.MkdirAll(md, 0o755); err != nil {
			return err
		}
		for i, o := range c.Objects {
			f := filepath.Join(md, fmt.Sprintf("%03d-%s-%s.yaml", i, strings.ToLower(o.Kind), o.Name()))
			if err := writeDocs(f, []map[string]any{o.Obj}); err != nil {
				return err
			}
		}
	}
	for name, docs := range map[string][]map[string]any{"prereqs.yaml": b.Prereqs, "catalog.yaml": b.Catalog, "record.yaml": b.Record} {
		if err := writeDocs(filepath.Join(dir, "bundt", name), docs); err != nil {
			return err
		}
	}
	return os.WriteFile(filepath.Join(dir, "report.md"), []byte(Report(res, b, header)), 0o644)
}

func writeDocs(path string, docs []map[string]any) error {
	b, err := MarshalDocs(docs)
	if err != nil {
		return err
	}
	return os.WriteFile(path, b, 0o644)
}

// Report says, for people, what became what.
func Report(res *Result, b *Bundle, header string) string {
	var s strings.Builder
	s.WriteString("# Offramp conversion\n\n")
	if header != "" {
		s.WriteString(header + "\n\n")
	}
	fmt.Fprintf(&s, "%d Config Connector objects in %d components; %d findings.\n\n", len(res.Objects), len(b.Components), len(res.Findings))
	s.WriteString("| Component | Package | Source | Kind | Name | Resource ID | Note |\n| --- | --- | --- | --- | --- | --- | --- |\n")
	for _, c := range b.Components {
		for _, o := range c.Objects {
			note := ""
			if o.Labelled {
				note = "labelled kind: Config Connector adds `managed-by-cnrm=true`, an update, unless the label is already there"
			}
			fmt.Fprintf(&s, "| %s | %s | `%s` | %s | %s | %s | %s |\n", c.Name, c.Package, o.Source, o.Kind, o.Name(), str(dig(o.Obj, "spec", "resourceID")), note)
		}
	}
	s.WriteString("\n## Components\n\n")
	for _, c := range b.Components {
		dep := "none"
		if len(c.DependsOn) > 0 {
			dep = strings.Join(c.DependsOn, ", ")
		}
		fmt.Fprintf(&s, "- `%s` (%d objects), after: %s\n", c.Name, len(c.Objects), dep)
	}
	for _, n := range b.Notes {
		fmt.Fprintf(&s, "- %s\n", n)
	}
	if len(res.Findings) > 0 {
		s.WriteString("\n## Findings\n\n| Class | Source | Type | Reason |\n| --- | --- | --- | --- |\n")
		fs := append([]Finding(nil), res.Findings...)
		sort.SliceStable(fs, func(i, j int) bool { return classRank(fs[i].Class) < classRank(fs[j].Class) })
		for _, f := range fs {
			fmt.Fprintf(&s, "| %s | `%s` | %s | %s |\n", f.Class, f.Source, f.Type, f.Reason)
		}
	}
	return s.String()
}

func classRank(c string) int {
	switch c {
	case "refused":
		return 0
	case "gap":
		return 1
	case "in-cluster":
		return 2
	case "note":
		return 3
	}
	return 4
}
