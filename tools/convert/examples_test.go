// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package convert

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Every directory under examples/ holds a Terraform module call (main.tf,
// with terraform.tfvars beside it), the Bundt documents that replace it
// (bundt.yaml) and what the converter says about it (messages.txt, absent
// when it says nothing). The test converts main.tf and compares.
// UPDATE=1 rewrites the expected files.
func TestExamples(t *testing.T) {
	root := filepath.Join("..", "..")
	repo, err := OpenRepo(root)
	if err != nil {
		t.Fatal(err)
	}
	dirs, _ := filepath.Glob(filepath.Join(root, "examples", "*", "main.tf"))
	if len(dirs) < 5 {
		t.Fatalf("want at least five examples, found %d", len(dirs))
	}
	for _, main := range dirs {
		dir := filepath.Dir(main)
		t.Run(filepath.Base(dir), func(t *testing.T) {
			o := Options{Repo: repo}
			if _, err := os.Stat(filepath.Join(dir, "terraform.tfvars")); err == nil {
				o.Tfvars = []string{filepath.Join(dir, "terraform.tfvars")}
			}
			applyArgs(t, dir, &o)
			res, err := Convert(main, o)
			if err != nil {
				t.Fatal(err)
			}
			var msgs strings.Builder
			for _, m := range res.Messages {
				fmt.Fprintln(&msgs, m)
			}
			compare(t, filepath.Join(dir, "bundt.yaml"), res.Documents)
			compare(t, filepath.Join(dir, "messages.txt"), msgs.String())
		})
	}
}

func compare(t *testing.T, path, got string) {
	t.Helper()
	if os.Getenv("UPDATE") != "" {
		if got == "" {
			os.Remove(path)
			return
		}
		if err := os.WriteFile(path, []byte(got), 0o644); err != nil {
			t.Fatal(err)
		}
		return
	}
	want, err := os.ReadFile(path)
	if err != nil && got != "" {
		t.Fatalf("%s is missing; got:\n%s", path, got)
	}
	if string(want) != got {
		t.Fatalf("%s differs (UPDATE=1 to accept).\nwant:\n%s\ngot:\n%s", path, want, got)
	}
}

// Every example that carries everything validates against its chart's schema
// (no "invalid" message), and only gaps/ has gaps.
func TestExamplesHaveNoSurpriseGaps(t *testing.T) {
	root := filepath.Join("..", "..")
	repo, _ := OpenRepo(root)
	dirs, _ := filepath.Glob(filepath.Join(root, "examples", "*", "main.tf"))
	for _, main := range dirs {
		dir := filepath.Dir(main)
		o := Options{Repo: repo}
		if _, err := os.Stat(filepath.Join(dir, "terraform.tfvars")); err == nil {
			o.Tfvars = []string{filepath.Join(dir, "terraform.tfvars")}
		}
		applyArgs(t, dir, &o)
		res, err := Convert(main, o)
		if err != nil {
			t.Fatal(err)
		}
		if filepath.Base(dir) == "gaps" {
			if !res.Gaps() {
				t.Errorf("gaps/ should have gaps")
			}
			continue
		}
		for _, m := range res.Messages {
			if m.Level != Note {
				t.Errorf("%s: %s", filepath.Base(dir), m)
			}
		}
	}
}

// applyArgs reads the example's convert.args (flags for catalogtool convert,
// one line) into the options; only --name-prefix, --env, --team and --name
// are understood.
func applyArgs(t *testing.T, dir string, o *Options) {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(dir, "convert.args"))
	if err != nil {
		return
	}
	f := strings.Fields(string(data))
	for i := 0; i < len(f); i += 2 {
		if i+1 >= len(f) {
			t.Fatalf("%s/convert.args: %s needs a value", dir, f[i])
		}
		switch f[i] {
		case "--name-prefix":
			o.NamePrefix = f[i+1]
		case "--env":
			o.Env = f[i+1]
		case "--team":
			o.Team = f[i+1]
		case "--name":
			o.Name = f[i+1]
		default:
			t.Fatalf("%s/convert.args: unknown flag %s", dir, f[i])
		}
	}
}
