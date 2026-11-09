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
