// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"github.com/highfivelabs/catalog/tools/convert"
	"github.com/highfivelabs/catalog/tools/coverage"
	"github.com/highfivelabs/catalog/tools/upstream"
)

// coverageCmd: catalogtool coverage [--check] [--offline] [--cache DIR] | verify
func coverageCmd(args []string) error {
	root, err := repoRoot()
	if err != nil {
		return err
	}
	o := coverage.Options{Root: root, CacheDir: filepath.Join(root, ".cache", "upstream")}
	check := false
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "verify":
			checked, skipped, problems, err := coverage.Verify(root)
			if err != nil {
				return err
			}
			if len(problems) > 0 {
				return fmt.Errorf("coverage verify failed:\n  %s", strings.Join(problems, "\n  "))
			}
			fmt.Printf("coverage verify: %d refusals confirmed by rendering the charts, %d accepted-in-part not checked\n", checked, skipped)
			return nil
		case "--check":
			check = true
		case "--offline":
			o.Offline = true
		case "--cache":
			i++
			if i == len(args) {
				return fmt.Errorf("--cache needs a directory")
			}
			o.CacheDir = args[i]
		default:
			return fmt.Errorf("usage: catalogtool coverage [--check] [--offline] [--cache DIR]")
		}
	}
	res, err := coverage.Build(o)
	if err != nil {
		return err
	}
	files, err := coverage.Files(res)
	if err != nil {
		return err
	}
	if err := coverage.Write(root, files, coverage.Readme(res), check); err != nil {
		return err
	}
	if check {
		fmt.Println("coverage: up to date")
	} else {
		fmt.Println("coverage: wrote docs/coverage and the README section")
	}
	return nil
}

// commands are the subcommands that take their own arguments; the older
// ones (schemas, check, outputs) are dispatched in main.
var commands = map[string]func(args []string) error{
	"upstream": upstreamCmd,
	"coverage": coverageCmd,
	"convert":  convertCmd,
}

// repoRoot finds the repository root from the working directory: the
// nearest parent holding upstream/modules.yaml.
func repoRoot() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "upstream", "modules.yaml")); err == nil {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", fmt.Errorf("upstream/modules.yaml not found above %s", dir)
		}
		dir = parent
	}
}

func upstreamCmd(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("usage: catalogtool upstream check [CHART_DIR...]")
	}
	root, err := repoRoot()
	if err != nil {
		return err
	}
	switch args[0] {
	case "check":
		var only []string
		for _, a := range args[1:] {
			abs, err := filepath.Abs(a)
			if err != nil {
				return err
			}
			rel, err := filepath.Rel(root, abs)
			if err != nil {
				return err
			}
			only = append(only, filepath.ToSlash(rel))
		}
		problems, err := upstream.CheckAll(root, only)
		if err != nil {
			return err
		}
		if len(problems) > 0 {
			return fmt.Errorf("upstream check failed:\n  %s", strings.Join(problems, "\n  "))
		}
		fmt.Println("upstream: ok")
		return nil
	}
	return fmt.Errorf("unknown upstream command %q", args[0])
}

// convertCmd: catalogtool convert FILE.tf|FILE.tfvars [flags]
func convertCmd(args []string) error {
	usage := fmt.Errorf(`usage: catalogtool convert FILE.tf [--tfvars FILE]... [--name NAME] [--team TEAM] [--env ENV] [--plan [--render FILE]]
       catalogtool convert FILE.tfvars --chart NAME

FILE.tf holds module blocks (with any variable and locals blocks): the
output is a Template, a Stack and an Instance. FILE.tfvars with --chart is
converted to the values that chart takes.`)
	root, err := repoRoot()
	if err != nil {
		return err
	}
	repo, err := convert.OpenRepo(root)
	if err != nil {
		return err
	}
	o := convert.Options{Repo: repo}
	var file, chart string
	plan := false
	var renderPath string
	for i := 0; i < len(args); i++ {
		next := func() (string, error) {
			i++
			if i >= len(args) {
				return "", usage
			}
			return args[i], nil
		}
		var err error
		switch a := args[i]; a {
		case "--tfvars":
			var v string
			if v, err = next(); err == nil {
				o.Tfvars = append(o.Tfvars, v)
			}
		case "--name":
			o.Name, err = next()
		case "--team":
			o.Team, err = next()
		case "--env":
			o.Env, err = next()
		case "--chart":
			chart, err = next()
		case "--plan":
			plan = true
		case "--render":
			renderPath, err = next()
		default:
			if strings.HasPrefix(a, "-") || file != "" {
				return usage
			}
			file = a
		}
		if err != nil {
			return err
		}
	}
	if file == "" {
		return usage
	}
	var res *convert.Result
	if chart != "" {
		res, err = convert.ConvertTfvars(file, chart, o)
	} else {
		res, err = convert.Convert(file, o)
	}
	if res != nil {
		for _, m := range res.Messages {
			fmt.Fprintln(os.Stderr, m)
		}
	}
	if err != nil {
		return err
	}
	if plan {
		var rf *os.File
		var w io.Writer
		if renderPath != "" {
			if rf, err = os.Create(renderPath); err != nil {
				return err
			}
			defer rf.Close()
			w = rf
		}
		out, err := convert.Plan(repo, res, o, w)
		if err != nil {
			return err
		}
		fmt.Print(out)
	} else {
		fmt.Print(res.Documents)
	}
	if res.Gaps() {
		os.Exit(3)
	}
	return nil
}
