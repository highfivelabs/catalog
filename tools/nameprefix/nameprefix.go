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
//
// Two optional keys in tests/name-prefix.yaml cover charts whose cloud name
// is not spec.resourceID. nameFields maps a kind to the spec field that holds
// its cloud name, for resources the cloud names by number (a folder's
// spec.resourceID is the number Google assigns; its collision-prone name is
// spec.displayName). noCloudNames, with a reason, says the chart renders no
// object with a cloud name of its own (an IAM-only chart), so a chart that
// checks nothing is not reported.
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
	// NoCloudNames, with its reason, says the chart gives no cloud name at
	// all (every kind it renders is exempt: an organization policy is named
	// by its parent and its constraint), so a check that finds no object to
	// check is expected rather than a mistake.
	NoCloudNames string `yaml:"noCloudNames"`
	// NameFields names, per kind, the spec field that holds the cloud name
	// a namePrefix goes on when it is not spec.resourceID: a kind whose
	// resourceID the cloud assigns (a hierarchical firewall policy's number)
	// and whose caller-given name is another field (shortName).
	NameFields map[string]string `yaml:"nameFields"`
}

type object struct {
	APIVersion string `yaml:"apiVersion"`
	Kind       string `yaml:"kind"`
	Metadata   struct {
		Name string `yaml:"name"`
	} `yaml:"metadata"`
	Spec map[string]any `yaml:"spec"`
}

// cloudName is the object's cloud-side name: spec.resourceID, or the spec
// field name-prefix.yaml names for its kind.
func (o object) cloudName(fields map[string]string) (field, name string) {
	field = "resourceID"
	if f, ok := fields[o.Kind]; ok && f != "" {
		field = f
	}
	name, _ = o.Spec[field].(string)
	return field, name
}

// Sets returns the --set arguments that give a chart the namePrefix p: its
// own namePrefix, and the namePrefix of each chart it depends on (Chart.yaml
// dependencies, by alias or name), since Helm cannot pass a parent's value
// down to a subchart. A wrapper chart (charts/gcp/project-wrapper) checks
// that the two agree.
func Sets(chartDir, p string) ([]string, error) {
	data, err := os.ReadFile(filepath.Join(chartDir, "Chart.yaml"))
	if err != nil {
		return nil, err
	}
	var c struct {
		Dependencies []struct {
			Name  string `yaml:"name"`
			Alias string `yaml:"alias"`
		} `yaml:"dependencies"`
	}
	if err := yaml.Unmarshal(data, &c); err != nil {
		return nil, fmt.Errorf("%s/Chart.yaml: %w", chartDir, err)
	}
	out := []string{"namePrefix=" + p}
	for _, d := range c.Dependencies {
		key := d.Name
		if d.Alias != "" {
			key = d.Alias
		}
		out = append(out, key+".namePrefix="+p)
	}
	return out, nil
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
	// names is a map of names in full; a chart whose module has a names
	// variable of its own (a list) has none, and that is not one.
	var v struct {
		Names any `yaml:"names"`
	}
	if err := yaml.Unmarshal(data, &v); err != nil {
		return nil, fmt.Errorf("%s: %w", values, err)
	}
	m, _ := v.Names.(map[string]any)
	var out []string
	for _, raw := range m {
		if n, ok := raw.(string); ok && n != "" {
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
		emptySets, err := Sets(chartDir, "")
		if err != nil {
			return nil, err
		}
		empty, err := render(chartDir, name, values, emptySets...)
		if err != nil {
			return nil, fmt.Errorf("%s/%s with namePrefix empty: %w", chart, name, err)
		}
		if !bytes.Equal(plain, empty) {
			bad("%s: an empty namePrefix changes the render", name)
		}
		sets, err := Sets(chartDir, Prefix)
		if err != nil {
			return nil, err
		}
		with, err := render(chartDir, name, values, sets...)
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
			field, cloud := o.cloudName(ex.NameFields)
			switch {
			case cloud == "":
				bad("%s: %s %q has no spec.%s, so its cloud name cannot carry the namePrefix: give it one built with kcc.cloudName, or list %s in tests/name-prefix.yaml with the reason", name, o.Kind, o.Metadata.Name, field, o.Kind)
			case !strings.Contains(cloud, Prefix+"-") && !setInFull(cloud):
				bad("%s: %s %q has cloud name %q without the namePrefix: build it with kcc.cloudName, or list %s in tests/name-prefix.yaml with the reason", name, o.Kind, o.Metadata.Name, cloud, o.Kind)
			}
		}
		// The same render without the prefix has none of it.
		if bytes.Contains(plain, []byte(Prefix+"-")) {
			bad("%s: the render without a namePrefix contains %q", name, Prefix+"-")
		}
	}
	if prefixed == 0 && strings.TrimSpace(ex.NoCloudNames) == "" {
		bad("no object was checked: every kind is exempt, or the test cases render nothing (a chart that gives no cloud name at all says why in name-prefix.yaml's noCloudNames)")
	}
	if prefixed > 0 && strings.TrimSpace(ex.NoCloudNames) != "" {
		bad("name-prefix.yaml says noCloudNames, but %d objects have a cloud name to check", prefixed)
	}
	return problems, nil
}
