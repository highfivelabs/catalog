// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package coverage

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func write(t *testing.T, root, rel, body string) {
	t.Helper()
	p := filepath.Join(root, rel)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

const sha = "f706bc3b6166787df01402f73a96f1de57097477"

func entry(id, module string, rank int, chart string) string {
	return `  - id: ` + id + `
    cloud: gcp
    module: ` + module + `
    rank: ` + string(rune('0'+rank)) + `
    repo: https://github.com/example/fabric
    path: modules/` + module + `
    tag_pattern: "v*"
    version: v1.0.0
    commit: ` + sha + `
    license: Apache-2.0
    copyright: Example
    registry_url: null
    url: https://github.com/example/fabric/tree/v1.0.0/modules/` + module + `
    chart: ` + chart + `
`
}

// fixture builds a repository with a cached "download" of module sources.
func fixture(t *testing.T) Options {
	root := t.TempDir()
	cache := filepath.Join(root, ".cache", "upstream")
	write(t, root, "upstream/modules.yaml", "schema: 1\nmodules:\n"+
		entry("gcp/a", "a", 1, "charts/gcp/a")+entry("gcp/b", "b", 2, "null")+entry("gcp/c", "c", 3, "null")+"excluded: []\n")
	write(t, root, "docs/coverage/gcp-resource-kinds.csv", `module,resource_type,count,class,kind
a,google_a,1,stable,A
b,google_b,1,stable,B
b,google_b2,1,alpha,B2
c,google_c,1,stable,C
`)
	src := filepath.Join(cache, "example", "fabric", "v1.0.0")
	write(t, src, ".fetched", "modules/a\nmodules/b\nmodules/c")
	write(t, src, "modules/a/variables.tf", `variable "x" { type = string }
variable "y" {
  type    = object({ p = string, q = optional(number) })
  default = null
}
variable "z" { default = 1 }
variable "w" { default = 1 }
`)
	write(t, src, "modules/a/outputs.tf", `output "id" { value = 1 }
output "obj" { value = 2 }
`)
	write(t, src, "modules/b/variables.tf", `variable "x" {}`)
	write(t, src, "modules/c/variables.tf", `variable "x" {}`)
	write(t, root, "charts/gcp/a/values.yaml", "names: {}\nnamePrefix: ''\nlabels: {}\ntags: {}\nx: ''\ny: null\nz: 1\n")
	write(t, root, "charts/gcp/a/package.yaml", "spec:\n  outputs:\n    id: inputs.x\n")
	write(t, root, "charts/gcp/a/upstream.yaml", `module: gcp/a
repo: https://github.com/example/fabric
path: modules/a
version: v1.0.0
commit: `+sha+`
license: Apache-2.0
copyright: Example
module_url: https://github.com/example/fabric/tree/v1.0.0/modules/a
registry_url: null
synced: 2026-11-09
refused:
  - variable: z
    kind: gap
    reason: no kind
  - variable: y
    kind: alpha
    reason: needs allow_alpha
    partial: true
`)
	return Options{Root: root, CacheDir: cache, Offline: true}
}

func TestBuild(t *testing.T) {
	res, err := Build(fixture(t))
	if err != nil {
		t.Fatal(err)
	}
	byName := map[string]Row{}
	for _, r := range res.Rows {
		byName[r.Module] = r
	}
	a := byName["a"]
	// x covered; y accepted in part (counts); z refused; w is not in the chart's values.
	if a.VarsTotal != 4 || a.VarsCovered != 2 || a.VarsPartial != 1 || a.Status != Partial {
		t.Fatalf("a: %+v", a)
	}
	if a.OutsTotal != 2 || a.OutsCovered != 1 {
		t.Fatalf("a outputs: %+v", a)
	}
	if a.TypesTotal != 1 || a.TypesStable != 1 || a.TypesMissing != 0 {
		t.Fatalf("a types: %+v", a)
	}
	if b := byName["b"]; b.Status != Blocked || b.TypesMissing != 1 || !strings.Contains(b.Notes, "1 alpha") {
		t.Fatalf("b: %+v", b)
	}
	if c := byName["c"]; c.Status != NotStarted || c.VarsCovered != 0 {
		t.Fatalf("c: %+v", c)
	}
	for _, v := range res.Vars {
		if v.Module == "a" && v.Variable == "w" && (v.Covered != "no" || v.GapKind != "not-ported") {
			t.Fatalf("w: %+v", v)
		}
		if v.Module == "a" && v.Variable == "y" && (v.Covered != "partial" || v.GapKind != "alpha" || v.Type != "object({p, q})") {
			t.Fatalf("y: %+v", v)
		}
	}
}

func TestBuildRejectsAMadeUpRefusal(t *testing.T) {
	o := fixture(t)
	p := filepath.Join(o.Root, "charts/gcp/a/upstream.yaml")
	data, _ := os.ReadFile(p)
	write(t, o.Root, "charts/gcp/a/upstream.yaml", string(data)+"  - variable: nope\n    kind: gap\n    reason: r\n")
	if _, err := Build(o); err == nil || !strings.Contains(err.Error(), `"nope"`) {
		t.Fatalf("want an error naming nope, got %v", err)
	}
}

func TestWriteCheck(t *testing.T) {
	o := fixture(t)
	write(t, o.Root, "README.md", "# x\n"+StartMarker+"\nold\n"+EndMarker+"\ntail\n")
	res, err := Build(o)
	if err != nil {
		t.Fatal(err)
	}
	files, _ := Files(res)
	if err := Write(o.Root, files, Readme(res), true); err == nil || !strings.Contains(err.Error(), "README.md") {
		t.Fatalf("check on stale outputs should fail naming the README, got %v", err)
	}
	if err := Write(o.Root, files, Readme(res), false); err != nil {
		t.Fatal(err)
	}
	if err := Write(o.Root, files, Readme(res), true); err != nil {
		t.Fatalf("check right after a write: %v", err)
	}
	// A stale bar is found, and a changed CSV is found.
	write(t, o.Root, "docs/coverage/bars/gcp-gone.svg", "<svg/>")
	write(t, o.Root, "docs/coverage/variables.csv", "changed")
	err = Write(o.Root, files, Readme(res), true)
	if err == nil || !strings.Contains(err.Error(), "gcp-gone.svg (stale)") || !strings.Contains(err.Error(), "variables.csv") {
		t.Fatalf("want stale bar and variables.csv, got %v", err)
	}
	readme, _ := os.ReadFile(filepath.Join(o.Root, "README.md"))
	if !strings.HasPrefix(string(readme), "# x\n") || !strings.HasSuffix(string(readme), EndMarker+"\ntail\n") {
		t.Fatalf("README outside the markers changed:\n%s", readme)
	}
}
