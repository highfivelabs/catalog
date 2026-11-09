// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package tfmod

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestParseDir(t *testing.T) {
	dir := t.TempDir()
	w := func(name, body string) {
		p := filepath.Join(dir, name)
		os.MkdirAll(filepath.Dir(p), 0o755)
		if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	w("variables.tf", `
variable "name" {
  description = "Bucket name."
  type        = string
}
variable "cors" {
  type = object({
    origin          = optional(list(string), [])
    method          = optional(list(string), ["GET"])
    max_age_seconds = optional(number)
  })
  default = null
}
variable "lifecycle_rules" {
  description = <<-EOT
    Rules, "quoted" and { braces }.
  EOT
  type = map(object({
    action    = object({ type = string })
    condition = optional(object({ age = optional(number) }), {})
  }))
  default  = {}
  nullable = false
}
variable "anything" {}
`)
	w("variables-iam.tf", `variable "iam" {
  type    = map(list(string))
  default = {}
}
`)
	w("main.tf", `
resource "google_storage_bucket" "bucket" {}
resource "google_storage_bucket_iam_binding" "authoritative" {}
resource "azapi_resource" "vnet" {
  type = "Microsoft.Network/virtualNetworks@2024-07-01"
}
resource "azapi_resource" "telemetry" {
  type = "Microsoft.Resources/deployments@2020-06-01"
}
resource "modtm_telemetry" "t" {}
data "google_project" "p" {}
`)
	w("outputs.tf", `output "id" { value = 1 }
output "url" {
  description = "The URL."
  value       = 2
}
`)
	w("modules/sub/main.tf", `resource "google_pubsub_topic" "t" {}
variable "ignored" {}
`)
	w("examples/e/main.tf", `resource "google_example" "e" {}`)

	m, err := ParseDir(dir, false)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, v := range m.Variables {
		names = append(names, v.Name)
	}
	if want := []string{"anything", "cors", "iam", "lifecycle_rules", "name"}; !reflect.DeepEqual(names, want) {
		t.Fatalf("variables %v, want %v", names, want)
	}
	if v := m.Var("name"); !v.Required || v.Type != "string" || v.Description != "Bucket name." {
		t.Fatalf("name: %+v", v)
	}
	if v := m.Var("cors"); v.Required || v.Type != "object({max_age_seconds, method, origin})" {
		t.Fatalf("cors: %+v", v)
	}
	if v := m.Var("lifecycle_rules"); v.Type != "map(object({action, condition}))" || v.Nullable || !reflect.DeepEqual(v.Attributes, []string{"action", "condition"}) {
		t.Fatalf("lifecycle_rules: %+v", v)
	}
	if v := m.Var("anything"); v.Type != "any" || !v.Required {
		t.Fatalf("anything: %+v", v)
	}
	if len(m.Outputs) != 2 || m.Outputs[1].Description != "The URL." {
		t.Fatalf("outputs %+v", m.Outputs)
	}
	if want := []string{"azapi_resource:Microsoft.Network/virtualNetworks", "google_storage_bucket", "google_storage_bucket_iam_binding"}; !reflect.DeepEqual(m.ResourceTypes, want) {
		t.Fatalf("resource types %v, want %v", m.ResourceTypes, want)
	}
	m, err = ParseDir(dir, true)
	if err != nil {
		t.Fatal(err)
	}
	if len(m.ResourceTypes) != 4 || len(m.Variables) != 5 {
		t.Fatalf("with submodules: types %v, variables %d (a submodule's variables are not the module's; examples are skipped)", m.ResourceTypes, len(m.Variables))
	}
}

func TestParseError(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "variables.tf"), []byte(`variable "x" { type = `), 0o644)
	if _, err := ParseDir(dir, false); err == nil {
		t.Fatal("want a parse error")
	}
}
