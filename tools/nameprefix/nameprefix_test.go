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

func TestNameFieldsAndNothingNamed(t *testing.T) {
	lib, _ := os.ReadFile(filepath.Join("..", "..", "lib", "_kcc.tpl"))
	// A kind whose cloud name is another spec field: resourceID is a number
	// the cloud assigns, displayName is the name.
	numbered := chart(t, "\"123\"\n  displayName: "+`{{ printf "%s%s" (include "kcc.namePrefix" .) .Values.name }}`, "  Other: because\n")
	os.WriteFile(filepath.Join(numbered, "templates", "_kcc.tpl"), lib, 0o644)
	if p, _ := Check(numbered); len(p) != 1 || !strings.Contains(p[0], `has cloud name "123"`) {
		t.Fatalf("without nameFields, resourceID is checked: %v", p)
	}
	os.WriteFile(filepath.Join(numbered, "tests", "name-prefix.yaml"), []byte("exempt: {}\nnameFields:\n  Thing: displayName\n"), 0o644)
	if p, err := Check(numbered); err != nil || len(p) != 0 {
		t.Fatalf("with nameFields, displayName is checked: %v %v", p, err)
	}
	// A module whose names variable is a list is not a map of names in full.
	os.WriteFile(filepath.Join(numbered, "tests", "basic.values.yaml"), []byte("name: x\nnames: [a, b]\n"), 0o644)
	if p, err := Check(numbered); err != nil || len(p) != 0 {
		t.Fatalf("a names list is not names in full: %v %v", p, err)
	}
	// A chart with nothing named says so.
	none := chart(t, `{{ .Values.name }}`, "  Thing: binds a member\nnoCloudNames: only IAM\n")
	if p, err := Check(none); err != nil || len(p) != 0 {
		t.Fatalf("noCloudNames allows a chart that checks nothing: %v %v", p, err)
	}
}

func TestCompactNames(t *testing.T) {
	lib, _ := os.ReadFile(filepath.Join("..", "..", "lib", "_kcc.tpl"))
	// A name that cannot hold a hyphen takes the prefix without one.
	compact := chart(t, `{{ printf "%s%s" (replace "-" "" (include "kcc.namePrefix" .)) .Values.name }}`, "  Other: because\ncompactNames:\n  Thing: lower-case letters and digits only\n")
	os.WriteFile(filepath.Join(compact, "templates", "_kcc.tpl"), lib, 0o644)
	if p, err := Check(compact); err != nil || len(p) != 0 {
		t.Fatalf("a compact prefixed name passes: %v %v", p, err)
	}
	// Listed as compact, a name without the prefix at its start still fails.
	bad := chart(t, `{{ .Values.name }}`, "  Other: because\ncompactNames:\n  Thing: lower-case letters and digits only\n")
	p, err := Check(bad)
	if err != nil || len(p) == 0 || !strings.Contains(p[0], "without the namePrefix at its start") {
		t.Fatalf("a compact name without the prefix fails: %v %v", p, err)
	}
	// Not listed, the same compact name fails: the hyphen is required.
	unlisted := chart(t, `{{ printf "%s%s" (replace "-" "" (include "kcc.namePrefix" .)) .Values.name }}`, "  Other: because\n")
	os.WriteFile(filepath.Join(unlisted, "templates", "_kcc.tpl"), lib, 0o644)
	if p, _ := Check(unlisted); len(p) == 0 || !strings.Contains(p[0], "without the namePrefix") {
		t.Fatalf("a compact name of a kind not listed fails: %v", p)
	}
	// A reason is needed.
	noReason := chart(t, `{{ .Values.name }}`, "  Other: because\ncompactNames:\n  Thing: \"\"\n")
	if p, _ := Check(noReason); len(p) == 0 || !strings.Contains(p[0], "under compactNames without a reason") {
		t.Fatalf("compactNames needs a reason: %v", p)
	}
}

func TestSets(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "Chart.yaml"), []byte("apiVersion: v2\nname: w\nversion: 0.1.0\ndependencies:\n  - name: project\n    version: 0.4.0\n  - name: project\n    alias: second\n"), 0o644)
	got, err := Sets(dir, "zz9")
	want := []string{"namePrefix=zz9", "project.namePrefix=zz9", "second.namePrefix=zz9"}
	if err != nil || strings.Join(got, " ") != strings.Join(want, " ") {
		t.Fatalf("a wrapper's dependencies get the namePrefix too: %v %v", got, err)
	}
	os.WriteFile(filepath.Join(dir, "Chart.yaml"), []byte("apiVersion: v2\nname: c\nversion: 0.1.0\n"), 0o644)
	if got, _ := Sets(dir, ""); strings.Join(got, " ") != "namePrefix=" {
		t.Fatalf("a chart without dependencies: %v", got)
	}
}
