// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package upstream

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const sha = "f706bc3b6166787df01402f73a96f1de57097477"

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

func fixture(t *testing.T, mutate func(modules, chartUp, chartYaml *string)) (string, []string) {
	t.Helper()
	modules := `schema: 1
modules:
  - id: gcp/gcs
    cloud: gcp
    module: gcs
    rank: 1
    repo: https://github.com/GoogleCloudPlatform/cloud-foundation-fabric
    path: modules/gcs
    tag_pattern: "v*"
    version: v60.0.0
    commit: ` + sha + `
    license: Apache-2.0
    copyright: Google LLC
    registry_url: null
    url: https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/gcs
    chart: charts/gcp/gcs
excluded: []
`
	chartUp := `module: gcp/gcs
repo: https://github.com/GoogleCloudPlatform/cloud-foundation-fabric
path: modules/gcs
version: v60.0.0
commit: ` + sha + `
license: Apache-2.0
copyright: Google LLC
module_url: https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/tree/v60.0.0/modules/gcs
registry_url: null
synced: 2026-11-09
`
	chartYaml := `apiVersion: v2
name: gcs
annotations:
  hfl.dev/source: cloud-foundation-fabric/modules/gcs
  hfl.dev/source-version: v60.0.0
  hfl.dev/source-commit: ` + sha + `
`
	if mutate != nil {
		mutate(&modules, &chartUp, &chartYaml)
	}
	root := t.TempDir()
	write(t, root, "upstream/modules.yaml", modules)
	write(t, root, "charts/gcp/gcs/upstream.yaml", chartUp)
	write(t, root, "charts/gcp/gcs/Chart.yaml", chartYaml)
	p, err := CheckAll(root, nil)
	if err != nil {
		return root, []string{err.Error()}
	}
	return root, p
}

func TestCheckClean(t *testing.T) {
	if _, p := fixture(t, nil); len(p) != 0 {
		t.Fatalf("want no problems, got %v", p)
	}
}

func TestCheckCatchesDrift(t *testing.T) {
	cases := []struct {
		name   string
		mutate func(m, u, c *string)
		want   string
	}{
		{"chart pin differs", func(m, u, c *string) { *u = strings.Replace(*u, "version: v60.0.0", "version: v61.0.0", 1) }, "upstream.yaml version"},
		{"Chart.yaml differs", func(m, u, c *string) { *c = strings.ReplaceAll(*c, "v60.0.0", "v59.0.0") }, "hfl.dev/source-version"},
		{"chart not claimed", func(m, u, c *string) { *m = strings.Replace(*m, "chart: charts/gcp/gcs", "chart: null", 1) }, "not this chart"},
		{"unknown module", func(m, u, c *string) { *u = strings.Replace(*u, "module: gcp/gcs", "module: gcp/nope", 1) }, "does not list"},
		{"tag outside pattern", func(m, u, c *string) { *m = strings.Replace(*m, "version: v60.0.0", "version: 60.0.0", 1) }, "tag_pattern"},
		{"bad sha", func(m, u, c *string) { *m = strings.Replace(*m, "commit: "+sha, "commit: abc", 1) }, "40-digit"},
		{"unknown field", func(m, u, c *string) { *u += "extra: 1\n" }, "field extra not found"},
		{"bad date", func(m, u, c *string) { *u = strings.Replace(*u, "2026-11-09", "yesterday", 1) }, "not a date"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, p := fixture(t, c.mutate)
			if !strings.Contains(strings.Join(p, "\n"), c.want) {
				t.Fatalf("want a problem containing %q, got %v", c.want, p)
			}
		})
	}
}

func TestBump(t *testing.T) {
	root, p := fixture(t, nil)
	if len(p) != 0 {
		t.Fatal(p)
	}
	newSHA := strings.Repeat("a", 40)
	if _, err := Bump(root, "gcp/gcs", "v59.0.0", newSHA, "2026-12-01", false); err == nil || !strings.Contains(err.Error(), "older") {
		t.Fatalf("a downgrade should be refused, got %v", err)
	}
	if _, err := Bump(root, "gcp/gcs", "60.1.0", newSHA, "2026-12-01", false); err == nil || !strings.Contains(err.Error(), "tag pattern") {
		t.Fatalf("a tag outside the pattern should be refused, got %v", err)
	}
	changed, err := Bump(root, "gcp/gcs", "v61.0.0", newSHA, "2026-12-01", false)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Join(changed, ",") != "upstream/modules.yaml,charts/gcp/gcs/upstream.yaml,charts/gcp/gcs/Chart.yaml" {
		t.Fatalf("changed %v", changed)
	}
	data, _ := os.ReadFile(filepath.Join(root, "upstream/modules.yaml"))
	for _, want := range []string{"version: v61.0.0", "commit: " + newSHA, "tree/v61.0.0/modules/gcs"} {
		if !strings.Contains(string(data), want) {
			t.Errorf("modules.yaml lacks %q:\n%s", want, data)
		}
	}
	cu, _ := os.ReadFile(filepath.Join(root, "charts/gcp/gcs/upstream.yaml"))
	if !strings.Contains(string(cu), "synced: 2026-12-01") {
		t.Errorf("upstream.yaml:\n%s", cu)
	}
	if p, _ := CheckAll(root, nil); len(p) != 0 {
		t.Fatalf("after the bump: %v", p)
	}
	if _, err := Bump(root, "gcp/gcs", "v61.0.0", newSHA, "2026-12-01", false); err == nil || !strings.Contains(err.Error(), "already") {
		t.Fatalf("bumping to the pinned tag should say so, got %v", err)
	}
}

func TestResolveID(t *testing.T) {
	f := &File{Modules: []Module{{ID: "gcp/kms", Module: "kms"}, {ID: "aws/kms", Module: "kms"}, {ID: "gcp/gcs", Module: "gcs"}}}
	if id, err := f.ResolveID("gcs"); err != nil || id != "gcp/gcs" {
		t.Fatal(id, err)
	}
	if _, err := f.ResolveID("kms"); err == nil || !strings.Contains(err.Error(), "ambiguous") {
		t.Fatal(err)
	}
	if id, _ := f.ResolveID("aws/kms"); id != "aws/kms" {
		t.Fatal(id)
	}
	if _, err := f.ResolveID("nope"); err == nil {
		t.Fatal("want an error")
	}
}
