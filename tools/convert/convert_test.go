// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package convert

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func repo(t *testing.T) *Repo {
	t.Helper()
	r, err := OpenRepo(filepath.Join("..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	return r
}

func write(t *testing.T, name, body string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func messages(res *Result) string {
	var b strings.Builder
	for _, m := range res.Messages {
		b.WriteString(m.String() + "\n")
	}
	return b.String()
}

const src = `"github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/`

func TestSchemaViolationIsReported(t *testing.T) {
	f := write(t, "main.tf", `module "b" {
  source        = `+src+`gcs?ref=v60.0.0"
  name          = "b"
  location      = "EU"
  storage_class = 5
}`)
	res, err := Convert(f, Options{Repo: repo(t)})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(messages(res), "invalid: module.b.storage_class") {
		t.Fatalf("want a schema message for storage_class, got:\n%s", messages(res))
	}
}

func TestMapKeyHoldingAModuleOutputCannotBeCarried(t *testing.T) {
	f := write(t, "main.tf", `module "sa" {
  source = `+src+`iam-service-account?ref=v60.0.0"
  name   = "sa-one"
}
module "b" {
  source   = `+src+`gcs?ref=v60.0.0"
  name     = "b"
  location = "EU"
  iam_by_principals = {
    (module.sa.iam_email) = ["roles/storage.objectViewer"]
  }
}`)
	res, err := Convert(f, Options{Repo: repo(t)})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(messages(res), "module.b.iam_by_principals: cannot carry the value: a map key holds a module output") {
		t.Fatalf("got:\n%s", messages(res))
	}
}

func TestUnknownOutputNamesWhatTheChartProvides(t *testing.T) {
	f := write(t, "main.tf", `module "sa" {
  source = `+src+`iam-service-account?ref=v60.0.0"
  name   = "sa-one"
}
module "b" {
  source      = `+src+`gcs?ref=v60.0.0"
  name        = "b"
  location    = "EU"
  prefix      = module.sa.service_account
}`)
	res, _ := Convert(f, Options{Repo: repo(t)})
	if !strings.Contains(messages(res), "module.sa.service_account: the iam-service-account chart provides the outputs email, iam_email") {
		t.Fatalf("got:\n%s", messages(res))
	}
}

func TestDependsOnAndLocalsAndVars(t *testing.T) {
	f := write(t, "main.tf", `variable "env" { default = "dev" }
locals {
  suffix = "-${var.env}"
}
module "a" {
  source = `+src+`iam-service-account?ref=v60.0.0"
  name   = "a${local.suffix}"
}
module "b" {
  source     = `+src+`gcs?ref=v60.0.0"
  name       = "b"
  location   = "EU"
  depends_on = [module.a]
}`)
	res, err := Convert(f, Options{Repo: repo(t)})
	if err != nil {
		t.Fatal(err)
	}
	a, b := res.Components[0], res.Components[1]
	if len(a.Values) != 1 || a.Values[0].Key != "name" || a.Values[0].Value != "a-dev" {
		t.Fatalf("a depends on a variable through a local, so its name is the Instance's value: %+v", a)
	}
	if len(b.DependsOn) != 1 || b.DependsOn[0] != "a" || !strings.Contains(res.Documents, "dependsOn:\n        - a") {
		t.Fatalf("depends_on: %+v\n%s", b, res.Documents)
	}
}

func TestTfvarsForAChart(t *testing.T) {
	f := write(t, "prod.tfvars", `name     = "b"
location = "EU"
rpo      = "ASYNC_TURBO"
nope     = 1
labels   = { team = "x" }
`)
	res, err := ConvertTfvars(f, "gcs", Options{Repo: repo(t)})
	if err != nil {
		t.Fatal(err)
	}
	m := messages(res)
	if !strings.Contains(m, "gap: rpo: refused by the chart (gap)") || !strings.Contains(m, "gap: nope: nope is not a variable of the gcs chart") {
		t.Fatalf("got:\n%s", m)
	}
	if !strings.Contains(res.Documents, "labels:\n  team: x") || strings.Contains(res.Documents, "rpo") {
		t.Fatalf("values:\n%s", res.Documents)
	}
}

func TestSourceWithoutAChart(t *testing.T) {
	f := write(t, "main.tf", `module "v" {
  source = "terraform-aws-modules/vpc/aws"
}
module "k" {
  source = "./modules/kms"
}`)
	res, err := Convert(f, Options{Repo: repo(t)})
	if err == nil {
		t.Fatal("nothing converts, so Convert should fail")
	}
	m := messages(res)
	if !strings.Contains(m, "aws/vpc") || !strings.Contains(m, "gcp/kms") || !strings.Contains(m, "has no chart yet") {
		t.Fatalf("got:\n%s", m)
	}
}

func TestTerraformPrefixStaysPrefixAndNamePrefixIsAdded(t *testing.T) {
	f := write(t, "main.tf", `module "b" {
  source   = `+src+`gcs?ref=v60.0.0"
  prefix   = "test"
  name     = "b"
  location = "EU"
}`)
	res, err := Convert(f, Options{Repo: repo(t), NamePrefix: "${instance.name}"})
	if err != nil {
		t.Fatal(err)
	}
	in := res.Components[0].Inputs
	if in[0].Key != "namePrefix" || in[0].Value != "${instance.name}" {
		t.Fatalf("namePrefix is added first: %+v", in)
	}
	var prefix any
	for _, p := range in {
		if p.Key == "prefix" {
			prefix = p.Value
		}
	}
	if prefix != "test" {
		t.Fatalf("the Terraform prefix must stay prefix: %+v", in)
	}
	for _, m := range res.Messages {
		if m.Level != Note {
			t.Errorf("a context expression in namePrefix must pass the schema: %s", m)
		}
	}
	// A module block that sets namePrefix itself keeps its own.
	f = write(t, "main.tf", `module "b" {
  source     = `+src+`gcs?ref=v60.0.0"
  name       = "b"
  location   = "EU"
  namePrefix = "mine"
}`)
	res, _ = Convert(f, Options{Repo: repo(t), NamePrefix: "${instance.name}"})
	if !strings.Contains(messages(res), "sets namePrefix itself") {
		t.Fatalf("got:\n%s", messages(res))
	}
}
