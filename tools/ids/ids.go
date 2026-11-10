// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

// Package ids checks the catalog's id convention (docs/design.md,
// "Outputs"): every object a chart renders carries an hfl.dev/id
// annotation, and no two objects of one render share an id.
//
// Bundt binds each rendered object as resources.<id> for a Package's
// outputs. An object without the annotation takes a default id from its
// kind, which only works for the only object of its kind; two objects of
// one kind without distinct ids are a blocking finding on Bundt's plan
// (Bundt's drafts/cel, answers 1 and 2). The catalog's rule is stricter, so
// a chart never leans on the default: every object has an explicit id, and
// ids are distinct across the whole render, whatever the kinds, since
// resources is one map. Objects made in a loop take the loop's key into
// the id (subnet:<region>/<name>, route:<key>, iam-additive-<key>).
//
// The check renders every test case of a chart (tests/*.values.yaml), so
// a case with several items of one loop proves the loop's ids differ.
package ids

import (
	"bytes"
	"fmt"
	"io"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"
)

// Annotation is the annotation that holds an object's id.
const Annotation = "hfl.dev/id"

type object struct {
	Kind     string `yaml:"kind"`
	Metadata struct {
		Name        string            `yaml:"name"`
		Annotations map[string]string `yaml:"annotations"`
	} `yaml:"metadata"`
}

// Check renders each test case of the chart in chartDir and returns the
// problems found.
func Check(chartDir string) ([]string, error) {
	chart := filepath.Base(chartDir)
	cases, _ := filepath.Glob(filepath.Join(chartDir, "tests", "*.values.yaml"))
	if len(cases) == 0 {
		return nil, fmt.Errorf("%s has no tests/*.values.yaml", chart)
	}
	var problems []string
	checked := 0
	for _, values := range cases {
		name := strings.TrimSuffix(filepath.Base(values), ".values.yaml")
		var out, errb bytes.Buffer
		cmd := exec.Command("helm", "template", name, chartDir, "--namespace", "test", "-f", values)
		cmd.Stdout, cmd.Stderr = &out, &errb
		if err := cmd.Run(); err != nil {
			return nil, fmt.Errorf("%s/%s: %s", chart, name, strings.TrimSpace(errb.String()))
		}
		objs, err := decode(out.Bytes())
		if err != nil {
			return nil, fmt.Errorf("%s/%s: %w", chart, name, err)
		}
		problems = append(problems, Objects(chart+"/"+name, objs)...)
		checked += len(objs)
	}
	if checked == 0 {
		problems = append(problems, chart+": no object was checked: the test cases render nothing")
	}
	return problems, nil
}

// Objects checks one render's objects: each has an id, and no id is used
// twice. where names the render in the messages.
func Objects(where string, objs []object) []string {
	var problems []string
	byID := map[string][]string{}
	for _, o := range objs {
		id := o.Metadata.Annotations[Annotation]
		ref := o.Kind + " " + o.Metadata.Name
		if id == "" {
			problems = append(problems, fmt.Sprintf("%s: %s has no %s annotation: give every object an id (kcc.metadata's id)", where, ref, Annotation))
			continue
		}
		byID[id] = append(byID[id], ref)
	}
	ids := make([]string, 0, len(byID))
	for id := range byID {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	for _, id := range ids {
		if refs := byID[id]; len(refs) > 1 {
			problems = append(problems, fmt.Sprintf("%s: %s %q is on %d objects (%s): Bundt's plan blocks two objects of one kind with one id, and resources.<id> holds one object; put the loop's key in the id", where, Annotation, id, len(refs), strings.Join(refs, ", ")))
		}
	}
	return problems
}

func decode(rendered []byte) ([]object, error) {
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
