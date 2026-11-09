// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package coverage

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/highfivelabs/catalog/tools/upstream"
)

// samples are tried in turn as a refused variable's value; the first that
// gets past the chart's schema shows whether the chart refuses it.
var samples = []string{`{"a":"b"}`, `["a"]`, `"a"`, `true`, `1`, `[{}]`, `{"a":{}}`, `[{"a":"b"}]`, `{"a":{"subnet":"europe-west1/s"}}`}

// Verify renders each chart with every variable its upstream.yaml says is
// refused (wholly) set to a value, and checks that the render fails with
// the chart's "is not supported" message naming the variable (or, for a
// variable that needs allow_alpha, its "needs the alpha" message). So the
// coverage numbers cannot claim a refusal the chart does not make. A
// variable refused only in part cannot be checked this way and is counted
// in skipped.
func Verify(root string) (checked, skipped int, problems []string, err error) {
	if _, err := exec.LookPath("helm"); err != nil {
		return 0, 0, nil, fmt.Errorf("helm is not installed")
	}
	f, err := upstream.Load(filepath.Join(root, "upstream", "modules.yaml"))
	if err != nil {
		return 0, 0, nil, err
	}
	for _, m := range f.Modules {
		if m.Chart == "" {
			continue
		}
		cu, err := upstream.LoadChart(filepath.Join(root, m.Chart))
		if err != nil {
			return checked, skipped, problems, err
		}
		// The chart's first render case supplies the values it needs to get
		// as far as its refusals.
		base, _ := filepath.Glob(filepath.Join(root, m.Chart, "tests", "*.values.yaml"))
		if len(base) == 0 {
			return checked, skipped, problems, fmt.Errorf("%s has no tests/*.values.yaml", m.Chart)
		}
		// Prefer a case that does not already opt in to alpha kinds.
		for _, b := range base {
			if data, err := os.ReadFile(b); err == nil && !strings.Contains(string(data), "allow_alpha") {
				base = []string{b}
				break
			}
		}
		for _, r := range cu.Refused {
			if r.Partial && !r.NeedsAllowAlpha {
				skipped++
				continue
			}
			checked++
			want := ": " + r.Variable + " is not supported"
			if r.Partial {
				// Accepted only with allow_alpha: true.
				want = ": " + r.Variable + " needs the alpha"
			}
			ok, last := false, ""
			for _, s := range append(enumSamples(filepath.Join(root, m.Chart, "values.schema.json"), r.Variable), samples...) {
				cmd := exec.Command("helm", "template", "verify", filepath.Join(root, m.Chart), "--namespace", "test",
					"-f", base[0], "--set-json", r.Variable+"="+s)
				out, runErr := cmd.CombinedOutput()
				last = strings.TrimSpace(string(out))
				if runErr != nil && strings.Contains(last, want) {
					ok = true
					break
				}
			}
			if !ok {
				if len(last) > 200 {
					last = last[:200]
				}
				problems = append(problems, fmt.Sprintf("%s: upstream.yaml refuses %s, but no sample value makes the chart say %q (last output: %s)", m.Chart, r.Variable, want, last))
			}
		}
	}
	return checked, skipped, problems, nil
}

// enumSamples returns the values the chart's schema allows for a variable
// that is an enum, as JSON.
func enumSamples(schemaPath, variable string) []string {
	data, err := os.ReadFile(schemaPath)
	if err != nil {
		return nil
	}
	var sch struct {
		Properties map[string]struct {
			Enum []any `json:"enum"`
		} `json:"properties"`
	}
	if json.Unmarshal(data, &sch) != nil {
		return nil
	}
	var out []string
	for _, e := range sch.Properties[variable].Enum {
		if e == nil {
			continue
		}
		b, _ := json.Marshal(e)
		out = append(out, string(b))
	}
	return out
}
