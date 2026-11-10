// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

// Package nameprefix checks the catalog's namePrefix convention
// (docs/design.md, "Names, labels and tags"): rendered with a namePrefix, every object
// whose cloud-side name can collide with another Instance's carries it, and
// rendered without one, nothing changes.
//
// The check walks every object a chart renders for each of its test cases.
// An object passes when its kind is listed as exempt in the chart's
// tests/name-prefix.yaml (with a reason: it has no name of its own, or the
// cloud fixes the name) or when its spec.resourceID, the cloud-side name,
// contains the prefix. So a resource added to a chart without the helper
// fails here until its author either prefixes it or says why not. A name a
// test case sets in full under names (docs/design.md, "Names, labels and
// tags") takes no prefix, so an object whose cloud name contains one of the
// case's names values passes too.
package nameprefix

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"
)

// Prefix is the namePrefix the check renders with. It is distinctive, so a
// name that merely happens to contain it is unlikely.
const Prefix = "zz9"

type exemptFile struct {
	Exempt map[string]string `yaml:"exempt"`
}

type object struct {
	APIVersion string `yaml:"apiVersion"`
	Kind       string `yaml:"kind"`
	Metadata   struct {
		Name string `yaml:"name"`
	} `yaml:"metadata"`
	Spec struct {
		ResourceID string `yaml:"resourceID"`
	} `yaml:"spec"`
}

func render(chartDir, release, values string, set ...string) ([]byte, error) {
	args := []string{"template", release, chartDir, "--namespace", "test", "-f", values}
	for _, s := range set {
		args = append(args, "--set", s)
	}
	var out, errb bytes.Buffer
	cmd := exec.Command("helm", args...)
	cmd.Stdout, cmd.Stderr = &out, &errb
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("%s", strings.TrimSpace(errb.String()))
	}
	return out.Bytes(), nil
}

// fullNames returns the values a test case sets under names: cloud names in
// full, which take no namePrefix.
func fullNames(values string) ([]string, error) {
	data, err := os.ReadFile(values)
	if err != nil {
		return nil, err
	}
	var v struct {
		Names map[string]string `yaml:"names"`
	}
	if err := yaml.Unmarshal(data, &v); err != nil {
		return nil, fmt.Errorf("%s: %w", values, err)
	}
	var out []string
	for _, n := range v.Names {
		if n != "" {
			out = append(out, n)
		}
	}
	return out, nil
}

func objects(rendered []byte) ([]object, error) {
	var objs []object
	dec := yaml.NewDecoder(bytes.NewReader(rendered))
	for {
		var o object
		if err := dec.Decode(&o); err != nil {
			if err == io.EOF {
				return objs, nil
			}
			return nil, err
		}
		if o.Kind != "" {
			objs = append(objs, o)
		}
	}
}

// Check runs the convention's checks on one chart and returns the problems.
func Check(chartDir string) ([]string, error) {
	chart := filepath.Base(chartDir)
	var problems []string
	bad := func(format string, a ...any) { problems = append(problems, chart+": "+fmt.Sprintf(format, a...)) }

	data, err := os.ReadFile(filepath.Join(chartDir, "tests", "name-prefix.yaml"))
	if err != nil {
		return nil, fmt.Errorf("%s needs tests/name-prefix.yaml (kinds exempt from the namePrefix, each with a reason): %w", chart, err)
	}
	var ex exemptFile
	if err := yaml.Unmarshal(data, &ex); err != nil {
		return nil, err
	}
	for k, why := range ex.Exempt {
		if strings.TrimSpace(why) == "" {
			bad("name-prefix.yaml exempts %s without a reason", k)
		}
	}
	cases, _ := filepath.Glob(filepath.Join(chartDir, "tests", "*.values.yaml"))
	if len(cases) == 0 {
		return nil, fmt.Errorf("%s has no tests/*.values.yaml", chart)
	}
	prefixed := 0
	for _, values := range cases {
		name := strings.TrimSuffix(filepath.Base(values), ".values.yaml")
		plain, err := render(chartDir, name, values)
		if err != nil {
			return nil, fmt.Errorf("%s/%s: %w", chart, name, err)
		}
		empty, err := render(chartDir, name, values, "namePrefix=")
		if err != nil {
			return nil, fmt.Errorf("%s/%s with namePrefix empty: %w", chart, name, err)
		}
		if !bytes.Equal(plain, empty) {
			bad("%s: an empty namePrefix changes the render", name)
		}
		with, err := render(chartDir, name, values, "namePrefix="+Prefix)
		if err != nil {
			bad("%s: does not render with namePrefix=%s: %v", name, Prefix, err)
			continue
		}
		objs, err := objects(with)
		if err != nil {
			return nil, err
		}
		full, err := fullNames(values)
		if err != nil {
			return nil, err
		}
		setInFull := func(id string) bool {
			for _, n := range full {
				if strings.Contains(id, n) {
					return true
				}
			}
			return false
		}
		for _, o := range objs {
			if !strings.HasPrefix(o.Metadata.Name, name+"-") && o.Metadata.Name != name {
				bad("%s: %s %q: the Kubernetes name does not start with the release name, so two Instances in one namespace could collide", name, o.Kind, o.Metadata.Name)
			}
			if _, ok := ex.Exempt[o.Kind]; ok {
				continue
			}
			prefixed++
			switch {
			case o.Spec.ResourceID == "":
				bad("%s: %s %q has no spec.resourceID, so its cloud name cannot carry the namePrefix: give it one built with kcc.cloudName, or list %s in tests/name-prefix.yaml with the reason", name, o.Kind, o.Metadata.Name, o.Kind)
			case !strings.Contains(o.Spec.ResourceID, Prefix+"-") && !setInFull(o.Spec.ResourceID):
				bad("%s: %s %q has cloud name %q without the namePrefix: build it with kcc.cloudName, or list %s in tests/name-prefix.yaml with the reason", name, o.Kind, o.Metadata.Name, o.Spec.ResourceID, o.Kind)
			}
		}
		// The same render without the prefix has none of it.
		if bytes.Contains(plain, []byte(Prefix+"-")) {
			bad("%s: the render without a namePrefix contains %q", name, Prefix+"-")
		}
	}
	if prefixed == 0 {
		bad("no object was checked: every kind is exempt, or the test cases render nothing")
	}
	return problems, nil
}
