// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package watch

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func write(t *testing.T, dir, name, body string) {
	t.Helper()
	p := filepath.Join(dir, name)
	os.MkdirAll(filepath.Dir(p), 0o755)
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestCompare(t *testing.T) {
	oldD, newD := t.TempDir(), t.TempDir()
	write(t, oldD, "variables.tf", `
variable "name" { type = string }
variable "gone" { default = 1 }
variable "mode" {
  type    = string
  default = "a"
}
variable "cfg" {
  type = object({ a = string })
}
variable "same" { default = [] }
`)
	write(t, newD, "variables.tf", `
variable "name" { type = string }
variable "mode" {
  type    = string
  default = "b"
}
variable "cfg" {
  type = object({ a = string, b = optional(string) })
}
variable "same" { default = [] }
variable "added" { type = bool }
variable "added_optional" {
  type    = number
  default = 1
}
`)
	write(t, oldD, "outputs.tf", `output "id" { value = 1 }
output "old" { value = 1 }
`)
	write(t, newD, "outputs.tf", `output "id" { value = 1 }
output "fresh" { value = 1 }
`)
	write(t, oldD, "main.tf", `resource "google_a" "a" {}
`)
	write(t, newD, "main.tf", `resource "google_a" "a" {}
resource "google_b" "b" {}
`)
	d, err := Compare(oldD, newD)
	if err != nil {
		t.Fatal(err)
	}
	if got := strings.Join(d.VariablesAdded, "|"); got != "added (bool, required)|added_optional (number, optional)" {
		t.Errorf("added: %s", got)
	}
	if got := strings.Join(d.VariablesRemoved, "|"); got != "gone" {
		t.Errorf("removed: %s", got)
	}
	changed := map[string]string{}
	for _, c := range d.VariablesChanged {
		changed[c.Name] = c.What
	}
	if len(changed) != 2 || !strings.Contains(changed["mode"], `default "a" -> "b"`) || !strings.Contains(changed["cfg"], "type object({a}) -> object({a, b})") {
		t.Errorf("changed: %v", changed)
	}
	if strings.Join(d.OutputsAdded, ",") != "fresh" || strings.Join(d.OutputsRemoved, ",") != "old" {
		t.Errorf("outputs: %+v", d)
	}
	if strings.Join(d.ResourceTypesAdded, ",") != "google_b" {
		t.Errorf("resource types: %+v", d)
	}
	if strings.Join(d.FilesChanged, ",") != "main.tf,outputs.tf,variables.tf" {
		t.Errorf("files: %v", d.FilesChanged)
	}
	if d.Empty() || d.InterfaceEmpty() {
		t.Error("not empty")
	}

	same, _ := Compare(oldD, oldD)
	if !same.Empty() {
		t.Errorf("identical releases: %+v", same)
	}
}

func TestRenderTruncatesIssue(t *testing.T) {
	r := &Report{Date: "2026-11-09", Checked: 300, UpToDate: 100}
	for i := 0; i < 200; i++ {
		e := Entry{ID: "gcp/m", Pinned: "v1.0.0", Latest: "v2.0.0", ReleasesBehind: 1, CompareURL: "c", ReleaseNotes: "n", ModuleURL: "u"}
		e.Diff.VariablesAdded = []string{strings.Repeat("v", 80) + " (string, optional)"}
		r.Behind = append(r.Behind, e)
	}
	body := r.IssueBody(20000)
	if len(body) > 20000 {
		t.Fatalf("issue body is %d bytes, limit 20000", len(body))
	}
	if !strings.Contains(body, "200 with a newer release") || !strings.Contains(body, "Cut to fit") {
		t.Fatalf("body:\n%s", body[:500])
	}
	if _, err := r.JSON(); err != nil {
		t.Fatal(err)
	}
}
