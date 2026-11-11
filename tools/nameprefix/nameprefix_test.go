// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package nameprefix

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func chart(t *testing.T, resourceID, exempt string) string {
	t.Helper()
	if _, err := exec.LookPath("helm"); err != nil {
		t.Skip("helm is not installed")
	}
	dir := filepath.Join(t.TempDir(), "demo")
	w := func(name, body string) {
		p := filepath.Join(dir, name)
		os.MkdirAll(filepath.Dir(p), 0o755)
		if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	w("Chart.yaml", "apiVersion: v2\nname: demo\nversion: 0.1.0\n")
	w("values.yaml", "namePrefix: \"\"\nname: x\n")
	w("templates/a.yaml", `apiVersion: example/v1
kind: Thing
metadata:
  name: {{ .Release.Name }}
spec:
  resourceID: `+resourceID+`
`)
	w("tests/basic.values.yaml", "name: x\n")
	w("tests/name-prefix.yaml", "exempt:\n"+exempt)
	return dir
}

func TestCheck(t *testing.T) {
	good := chart(t, `{{ printf "%s%s" (include "kcc.namePrefix" .) .Values.name }}`, "  Other: because\n")
	// kcc.namePrefix is defined by the library template.
	lib, _ := os.ReadFile(filepath.Join("..", "..", "lib", "_kcc.tpl"))
	os.WriteFile(filepath.Join(good, "templates", "_kcc.tpl"), lib, 0o644)
	if p, err := Check(good); err != nil || len(p) != 0 {
		t.Fatalf("a prefixed name passes: %v %v", p, err)
	}
	bad := chart(t, `{{ .Values.name }}`, "  Other: because\n")
	p, err := Check(bad)
	if err != nil || len(p) == 0 || !strings.Contains(p[0], `has cloud name "x" without the namePrefix`) {
		t.Fatalf("an unprefixed name fails: %v %v", p, err)
	}
	ok := chart(t, `{{ .Values.name }}`, "  Thing: fixed by the cloud\n")
	if p, _ := Check(ok); len(p) != 1 || !strings.Contains(p[0], "no object was checked") {
		t.Fatalf("an exempt kind passes, but a chart that checks nothing is reported: %v", p)
	}
	none := chart(t, `{{ .Values.name }}`, "  Thing: fixed by the cloud\nnoCloudNames: every kind is named by the cloud\n")
	if p, err := Check(none); err != nil || len(p) != 0 {
		t.Fatalf("a chart that says it gives no cloud name passes: %v %v", p, err)
	}
	short := chart(t, `{{ .Values.name }}
  shortName: {{ printf "%s%s" (include "kcc.namePrefix" .) .Values.name }}`, "  Other: because\nnameFields: {Thing: shortName}\n")
	os.WriteFile(filepath.Join(short, "templates", "_kcc.tpl"), lib, 0o644)
	if p, err := Check(short); err != nil || len(p) != 0 {
		t.Fatalf("a prefixed name in the field nameFields names passes: %v %v", p, err)
	}
	unshort := chart(t, `{{ printf "%s%s" (include "kcc.namePrefix" .) .Values.name }}
  shortName: {{ .Values.name }}`, "  Other: because\nnameFields: {Thing: shortName}\n")
	os.WriteFile(filepath.Join(unshort, "templates", "_kcc.tpl"), lib, 0o644)
	if p, _ := Check(unshort); len(p) != 1 || !strings.Contains(p[0], `has cloud name "x" without the namePrefix`) {
		t.Fatalf("nameFields moves the check to that field: %v", p)
	}
	wrong := chart(t, `{{ .Values.name }}`, "  Other: because\nnoCloudNames: wrongly claimed\n")
	if p, _ := Check(wrong); len(p) != 2 || !strings.Contains(p[1], "says noCloudNames, but 1 objects") {
		t.Fatalf("noCloudNames on a chart with a cloud name is reported: %v", p)
	}
}
