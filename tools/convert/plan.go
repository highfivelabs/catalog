// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package convert

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

// Plan previews what Bundt's plan lists for the converted documents: one
// `create` for each document and live component, and under each live
// component the Config Connector objects its chart renders (the chart is
// rendered with `helm template`, with the component's inputs and the
// Instance's values laid over the chart's defaults, as Bundt does). A
// chart that refuses a value shows the refusal as a blocking finding, as
// Bundt shows it at plan time. The layout follows specs/record/plans.md
// (R2: one change per object); it is not captured from a running Bundt.
// renderTo, when set, receives the rendered objects.
func Plan(repo *Repo, res *Result, o Options, renderTo io.Writer) (string, error) {
	if _, err := exec.LookPath("helm"); err != nil {
		return "", fmt.Errorf("--plan renders the charts and needs helm")
	}
	if o.Team == "" {
		o.Team = "my-team"
	}
	if o.Env == "" {
		o.Env = "dev"
	}
	if o.TemplateVersion == "" {
		o.TemplateVersion = "1.0.0"
	}
	instance := res.TemplateName + "-" + o.Env
	var b strings.Builder
	fmt.Fprintf(&b, "Plan preview: the converted documents, with each chart rendered by helm template.\n")
	fmt.Fprintf(&b, "Layout after specs/record/plans.md R2 (one change per object); not captured from a running Bundt.\n\n")
	fmt.Fprintf(&b, "  create  Template   %s %s\n", res.TemplateName, o.TemplateVersion)
	fmt.Fprintf(&b, "  create  Stack      %s/%s  (Template %s)\n", o.Team, res.TemplateName, res.TemplateName)
	fmt.Fprintf(&b, "  create  Instance   %s/%s/%s  (Stack %s, Template version %s)\n", o.Team, o.Env, instance, res.TemplateName, o.TemplateVersion)

	var blocking []string
	for _, c := range res.Components {
		live := instance + "-" + c.Name
		fmt.Fprintf(&b, "  create  Component  %s  (%s %s)\n", live, c.Chart.Package, c.Chart.Version)
		var after []string
		after = append(after, c.DependsOn...)
		for _, p := range append(append(Ordered{}, c.Inputs...), c.Values...) {
			for _, dep := range expressionComponents(p.Value) {
				after = append(after, dep)
			}
		}
		if after = uniq(after); len(after) > 0 {
			fmt.Fprintf(&b, "            after %s\n", strings.Join(after, ", "))
		}
		objs, out, err := renderComponent(repo, c, live)
		if err != nil {
			blocking = append(blocking, fmt.Sprintf("%s: %s", live, err))
			fmt.Fprintf(&b, "            no objects: the render is refused (blocking finding below)\n")
			continue
		}
		if renderTo != nil {
			fmt.Fprintf(renderTo, "# component %s\n%s", live, out)
			if !strings.HasSuffix(out, "\n") {
				fmt.Fprintln(renderTo)
			}
		}
		for _, ob := range objs {
			cloud := ""
			if ob.ResourceID != "" && ob.ResourceID != ob.Name {
				cloud = "  (named " + ob.ResourceID + " in the cloud)"
			}
			fmt.Fprintf(&b, "            create  %-26s %s%s\n", ob.Kind, ob.Name, cloud)
		}
		fmt.Fprintf(&b, "            outputs once Ready: %s\n", strings.Join(c.Chart.Outputs, ", "))
	}
	b.WriteString("\n")
	if len(blocking) == 0 {
		b.WriteString("Findings: none. Approving the plan creates the documents and delivers the components.\n")
	} else {
		b.WriteString("Findings (blocking: ApprovePlan refuses this plan until they are fixed):\n")
		for _, f := range blocking {
			fmt.Fprintf(&b, "  - %s\n", f)
		}
	}
	return b.String(), nil
}

func uniq(s []string) []string {
	seen := map[string]bool{}
	var out []string
	for _, x := range s {
		if !seen[x] {
			seen[x] = true
			out = append(out, x)
		}
	}
	return out
}

// expressionComponents finds the components a value's ${components.X...} expressions name.
func expressionComponents(v any) []string {
	var out []string
	switch x := v.(type) {
	case string:
		rest := x
		for {
			i := strings.Index(rest, "${components.")
			if i < 0 {
				break
			}
			rest = rest[i+len("${components."):]
			if j := strings.Index(rest, "."); j > 0 {
				out = append(out, rest[:j])
			}
		}
	case []any:
		for _, e := range x {
			out = append(out, expressionComponents(e)...)
		}
	case map[string]any:
		for _, e := range x {
			out = append(out, expressionComponents(e)...)
		}
	}
	return out
}

type object struct{ APIVersion, Kind, Name, ResourceID string }

func renderComponent(repo *Repo, c *Component, live string) ([]object, string, error) {
	eff := map[string]any{}
	for _, p := range append(append(Ordered{}, c.Inputs...), c.Values...) {
		eff[p.Key] = p.Value
	}
	data, err := yaml.Marshal(eff)
	if err != nil {
		return nil, "", err
	}
	f, err := os.CreateTemp("", "convert-values-*.yaml")
	if err != nil {
		return nil, "", err
	}
	defer os.Remove(f.Name())
	f.Write(data)
	f.Close()
	cmd := exec.Command("helm", "template", live, filepath.Join(repo.Root, c.Chart.Dir), "--namespace", "test", "-f", f.Name())
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	if err := cmd.Run(); err != nil {
		msg := strings.TrimSpace(stderr.String())
		msg = strings.TrimPrefix(msg, "Error: ")
		// Helm wraps a template failure in its own frame; keep the chart's message.
		msg = strings.Join(strings.Fields(msg), " ")
		msg = strings.TrimSuffix(msg, " Use --debug flag to render out invalid YAML")
		if i := strings.Index(msg, "execution error at ("); i >= 0 {
			if j := strings.Index(msg[i:], "): "); j >= 0 {
				msg = msg[i+j+3:]
			}
		}
		msg = strings.Replace(msg, "values don't meet the specifications of the schema(s) in the following chart(s): ", "values.schema.json: ", 1)
		return nil, "", fmt.Errorf("%s", msg)
	}
	var objs []object
	dec := yaml.NewDecoder(bytes.NewReader(stdout.Bytes()))
	for {
		var d struct {
			APIVersion string `yaml:"apiVersion"`
			Kind       string `yaml:"kind"`
			Metadata   struct {
				Name string `yaml:"name"`
			} `yaml:"metadata"`
			Spec struct {
				ResourceID string `yaml:"resourceID"`
			} `yaml:"spec"`
		}
		if err := dec.Decode(&d); err != nil {
			if err == io.EOF {
				break
			}
			return nil, "", err
		}
		if d.Kind != "" {
			objs = append(objs, object{d.APIVersion, d.Kind, d.Metadata.Name, d.Spec.ResourceID})
		}
	}
	return objs, stdout.String(), nil
}
