// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

// catalogtool holds the catalog's small offline tools:
//
//	catalogtool schemas CRD_DIR OUT_DIR
//	    Write a JSON schema per CRD version, for kubeconform, laid out as
//	    OUT_DIR/<group>/<kind>_<version>.json. Every object with declared
//	    properties is closed (additionalProperties: false), so a field name
//	    Config Connector does not have fails validation.
//
//	catalogtool check PACKAGE_YAML CHART_YAML
//	    Check a Package document against its chart: kind Package, engine
//	    helm, spec.version equal to the chart's version, and every output
//	    a CEL expression that compiles.
//
//	catalogtool outputs PACKAGE_YAML OBJECTS_JSON
//	    Evaluate a Package's spec.outputs, CEL as Bundt evaluates them
//	    (docs/design.md, "Outputs"), against live objects: OBJECTS_JSON is
//	    `kubectl get -o json` of a list. Each object whose annotation
//	    hfl.dev/id is set is bound as resources.<id>. Prints each output as
//	    JSON; exits 1 when any output fails to evaluate.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"

	"github.com/google/cel-go/cel"
	"github.com/google/cel-go/ext"
	"google.golang.org/protobuf/types/known/structpb"
	"sigs.k8s.io/yaml"
)

func main() {
	if len(os.Args) != 4 {
		fmt.Fprintln(os.Stderr, "usage: catalogtool schemas CRD_DIR OUT_DIR | check PACKAGE_YAML CHART_YAML | outputs PACKAGE_YAML OBJECTS_JSON")
		os.Exit(2)
	}
	var err error
	switch os.Args[1] {
	case "schemas":
		err = schemas(os.Args[2], os.Args[3])
	case "outputs":
		err = outputs(os.Args[2], os.Args[3])
	case "check":
		err = check(os.Args[2], os.Args[3])
	default:
		err = fmt.Errorf("unknown command %q", os.Args[1])
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "catalogtool:", err)
		os.Exit(1)
	}
}

type crd struct {
	Spec struct {
		Group string `json:"group"`
		Names struct {
			Kind string `json:"kind"`
		} `json:"names"`
		Versions []struct {
			Name   string `json:"name"`
			Schema struct {
				OpenAPIV3Schema map[string]any `json:"openAPIV3Schema"`
			} `json:"schema"`
		} `json:"versions"`
	} `json:"spec"`
}

func schemas(in, out string) error {
	files, err := filepath.Glob(filepath.Join(in, "*.yaml"))
	if err != nil {
		return err
	}
	n := 0
	for _, f := range files {
		b, err := os.ReadFile(f)
		if err != nil {
			return err
		}
		var c crd
		if err := yaml.Unmarshal(b, &c); err != nil {
			return fmt.Errorf("%s: %w", f, err)
		}
		if c.Spec.Names.Kind == "" {
			continue
		}
		for _, v := range c.Spec.Versions {
			s := v.Schema.OpenAPIV3Schema
			if s == nil {
				continue
			}
			closeObjects(s, true)
			dir := filepath.Join(out, c.Spec.Group)
			if err := os.MkdirAll(dir, 0o755); err != nil {
				return err
			}
			j, err := json.MarshalIndent(s, "", " ")
			if err != nil {
				return err
			}
			name := fmt.Sprintf("%s_%s.json", strings.ToLower(c.Spec.Names.Kind), v.Name)
			if err := os.WriteFile(filepath.Join(dir, name), j, 0o644); err != nil {
				return err
			}
			n++
		}
	}
	fmt.Printf("wrote %d schemas from %d CRDs\n", n, len(files))
	return nil
}

// closeObjects sets additionalProperties: false on every object schema
// that declares properties and allows nothing else, as the API server's
// structural pruning would drop unknown fields silently.
func closeObjects(s map[string]any, root bool) {
	props, hasProps := s["properties"].(map[string]any)
	_, preserve := s["x-kubernetes-preserve-unknown-fields"]
	if hasProps && !preserve {
		if _, set := s["additionalProperties"]; !set {
			s["additionalProperties"] = false
		}
	}
	if root && hasProps {
		// metadata is checked by the API server, not the CRD schema.
		props["metadata"] = map[string]any{"type": "object"}
	}
	for _, p := range props {
		if m, ok := p.(map[string]any); ok {
			closeObjects(m, false)
		}
	}
	if items, ok := s["items"].(map[string]any); ok {
		closeObjects(items, false)
	}
	if ap, ok := s["additionalProperties"].(map[string]any); ok {
		closeObjects(ap, false)
	}
}

type pkg struct {
	APIVersion string `json:"apiVersion"`
	Kind       string `json:"kind"`
	Metadata   struct {
		Name string `json:"name"`
	} `json:"metadata"`
	Spec struct {
		Version   string            `json:"version"`
		Engine    string            `json:"engine"`
		Providers []string          `json:"providers"`
		Outputs   map[string]string `json:"outputs"`
	} `json:"spec"`
}

func celEnv() (*cel.Env, error) {
	return cel.NewEnv(
		cel.Variable("resources", cel.MapType(cel.StringType, cel.DynType)),
		ext.Strings(), ext.Lists(), ext.Encoders(), ext.TwoVarComprehensions(),
	)
}

func check(pkgPath, chartPath string) error {
	b, err := os.ReadFile(pkgPath)
	if err != nil {
		return err
	}
	var p pkg
	if err := yaml.UnmarshalStrict(b, &p); err != nil {
		return fmt.Errorf("%s: %w", pkgPath, err)
	}
	cb, err := os.ReadFile(chartPath)
	if err != nil {
		return err
	}
	var chart struct {
		Version string `json:"version"`
	}
	if err := yaml.Unmarshal(cb, &chart); err != nil {
		return err
	}
	var problems []string
	if p.APIVersion != "hfl.dev/v1" || p.Kind != "Package" {
		problems = append(problems, "not an hfl.dev/v1 Package")
	}
	if p.Metadata.Name == "" {
		problems = append(problems, "no metadata.name")
	}
	if p.Spec.Engine != "helm" {
		problems = append(problems, fmt.Sprintf("engine %q, want helm", p.Spec.Engine))
	}
	if p.Spec.Version != chart.Version {
		problems = append(problems, fmt.Sprintf("spec.version %q, chart version %q", p.Spec.Version, chart.Version))
	}
	env, err := celEnv()
	if err != nil {
		return err
	}
	for n, expr := range p.Spec.Outputs {
		if _, iss := env.Compile(expr); iss.Err() != nil {
			problems = append(problems, fmt.Sprintf("output %s: %v", n, iss.Err()))
		}
	}
	if len(problems) > 0 {
		sort.Strings(problems)
		return fmt.Errorf("%s:\n  %s", pkgPath, strings.Join(problems, "\n  "))
	}
	return nil
}

func outputs(pkgPath, objectsPath string) error {
	b, err := os.ReadFile(pkgPath)
	if err != nil {
		return err
	}
	var p pkg
	if err := yaml.Unmarshal(b, &p); err != nil {
		return err
	}
	if p.Kind != "Package" {
		return fmt.Errorf("%s: kind %q, want Package", pkgPath, p.Kind)
	}
	ob, err := os.ReadFile(objectsPath)
	if err != nil {
		return err
	}
	var list struct {
		Items []map[string]any `json:"items"`
	}
	if err := json.Unmarshal(ob, &list); err != nil {
		return err
	}
	resources := map[string]any{}
	for _, o := range list.Items {
		md, _ := o["metadata"].(map[string]any)
		ann, _ := md["annotations"].(map[string]any)
		if id, ok := ann["hfl.dev/id"].(string); ok && id != "" {
			if _, dup := resources[id]; dup {
				return fmt.Errorf("two objects carry hfl.dev/id %q", id)
			}
			resources[id] = o
		}
	}
	env, err := celEnv()
	if err != nil {
		return err
	}
	names := make([]string, 0, len(p.Spec.Outputs))
	for n := range p.Spec.Outputs {
		names = append(names, n)
	}
	sort.Strings(names)
	failed := 0
	result := map[string]any{}
	for _, n := range names {
		ast, iss := env.Compile(p.Spec.Outputs[n])
		if iss.Err() != nil {
			fmt.Fprintf(os.Stderr, "output %s: %v\n", n, iss.Err())
			failed++
			continue
		}
		prg, err := env.Program(ast)
		if err != nil {
			fmt.Fprintf(os.Stderr, "output %s: %v\n", n, err)
			failed++
			continue
		}
		v, _, err := prg.Eval(map[string]any{"resources": resources})
		if err != nil {
			fmt.Fprintf(os.Stderr, "output %s: %v\n", n, err)
			failed++
			continue
		}
		native, err := v.ConvertToNative(reflect.TypeOf(&structpb.Value{}))
		if err != nil {
			fmt.Fprintf(os.Stderr, "output %s: %v\n", n, err)
			failed++
			continue
		}
		result[n] = native.(*structpb.Value).AsInterface()
	}
	j, _ := json.MarshalIndent(result, "", "  ")
	fmt.Println(string(j))
	if failed > 0 {
		return fmt.Errorf("%d of %d outputs failed", failed, len(names))
	}
	return nil
}
