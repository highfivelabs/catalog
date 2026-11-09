// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/highfivelabs/catalog/tools/convert"
	"github.com/highfivelabs/catalog/tools/coverage"
	"github.com/highfivelabs/catalog/tools/nameprefix"
	"github.com/highfivelabs/catalog/tools/upstream"
	"github.com/highfivelabs/catalog/tools/watch"
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
	"nameprefix": func(args []string) error {
		var all []string
		for _, dir := range args {
			problems, err := nameprefix.Check(dir)
			if err != nil {
				return err
			}
			all = append(all, problems...)
		}
		if len(all) > 0 {
			return fmt.Errorf("namePrefix check failed:\n  %s", strings.Join(all, "\n  "))
		}
		fmt.Println("namePrefix: ok")
		return nil
	},
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
		return fmt.Errorf("usage: catalogtool upstream check [CHART_DIR...] | watch | bump MODULE TAG")
	}
	root, err := repoRoot()
	if err != nil {
		return err
	}
	switch args[0] {
	case "watch":
		return watchCmd(root, args[1:])
	case "bump":
		return bumpCmd(root, args[1:])
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
	usage := fmt.Errorf(`usage: catalogtool convert FILE.tf [--tfvars FILE]... [--name NAME] [--team TEAM] [--env ENV] [--name-prefix EXPR] [--plan [--render FILE]]
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
		case "--name-prefix":
			o.NamePrefix, err = next()
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

// watchCmd: catalogtool upstream watch [--out FILE] [--json FILE] [--issue FILE] [--only ID,ID] [--date D]
func watchCmd(root string, args []string) error {
	o := watch.Options{Root: root, CacheDir: filepath.Join(root, ".cache", "upstream"), Date: time.Now().UTC().Format("2006-01-02"),
		Progress: func(s string) { fmt.Fprintln(os.Stderr, "watch:", s) }}
	out := filepath.Join(root, "docs", "upstream-status.md")
	jsonOut := filepath.Join(root, "docs", "upstream-status.json")
	issue := ""
	for i := 0; i < len(args); i++ {
		arg := args[i]
		val := func() (string, error) {
			i++
			if i >= len(args) {
				return "", fmt.Errorf("%s needs a value", arg)
			}
			return args[i], nil
		}
		var err error
		var v string
		switch arg {
		case "--out":
			out, err = val()
		case "--json":
			jsonOut, err = val()
		case "--issue":
			issue, err = val()
		case "--date":
			o.Date, err = val()
		case "--only":
			if v, err = val(); err == nil {
				o.Only = strings.Split(v, ",")
			}
		default:
			return fmt.Errorf("usage: catalogtool upstream watch [--out FILE] [--json FILE] [--issue FILE] [--only ID,ID] [--date YYYY-MM-DD]")
		}
		if err != nil {
			return err
		}
	}
	rep, err := watch.Run(o)
	if err != nil {
		return err
	}
	if rep.Checked == 0 {
		return fmt.Errorf("no module could be checked: %s", strings.Join(rep.Unchecked, "; "))
	}
	for path, content := range map[string]func() ([]byte, error){
		out:     func() ([]byte, error) { return []byte(rep.Markdown()), nil },
		jsonOut: rep.JSON,
	} {
		if path == "" {
			continue
		}
		b, err := content()
		if err != nil {
			return err
		}
		if err := os.WriteFile(path, b, 0o644); err != nil {
			return err
		}
	}
	if issue != "" {
		if err := os.WriteFile(issue, []byte(rep.IssueBody(60000)), 0o644); err != nil {
			return err
		}
	}
	fmt.Printf("upstream watch: %d modules checked, %d up to date, %d behind, %d not checked\n", rep.Checked, rep.UpToDate, len(rep.Behind), len(rep.Unchecked))
	return nil
}

// bumpCmd: catalogtool upstream bump MODULE TAG [--allow-downgrade]
func bumpCmd(root string, args []string) error {
	var pos []string
	downgrade := false
	for _, a := range args {
		if a == "--allow-downgrade" {
			downgrade = true
		} else {
			pos = append(pos, a)
		}
	}
	if len(pos) != 2 {
		return fmt.Errorf("usage: catalogtool upstream bump MODULE TAG [--allow-downgrade]   (MODULE: gcp/gcs, or gcs when unambiguous)")
	}
	f, err := upstream.Load(filepath.Join(root, "upstream", "modules.yaml"))
	if err != nil {
		return err
	}
	id, err := f.ResolveID(pos[0])
	if err != nil {
		return err
	}
	m := f.Find(id)
	tags, err := upstream.ListTags(m.Repo, m.TagPattern)
	if err != nil {
		return err
	}
	var commit string
	for _, t := range tags {
		if t.Name == pos[1] {
			commit = t.Commit
		}
	}
	if commit == "" {
		return fmt.Errorf("%s has no release tag %q (git ls-remote --tags)", m.Repo, pos[1])
	}
	changed, err := upstream.Bump(root, id, pos[1], commit, time.Now().UTC().Format("2006-01-02"), downgrade)
	for _, c := range changed {
		fmt.Println("updated", c)
	}
	if err != nil {
		return err
	}
	fmt.Printf("%s pinned to %s (%s)\n", id, pos[1], commit)
	if m.Chart != "" {
		fmt.Printf("Reminder: this moves only the pin. The chart %s must already carry the module's changes between %s and %s; bump its version (Chart.yaml, package.yaml) if its behaviour changed (docs/design.md, \"Versioning\").\n", m.Chart, m.Version, pos[1])
	}
	return nil
}
