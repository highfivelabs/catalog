// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

// Command offramp turns a Terraform state, or a scan of what is in Google
// Cloud, into Config Connector objects that adopt the resources as they
// are, and into the Bundt documents that hold them. See offramp/README.md.
//
//	offramp state  --kcc DIR --state terraform.tfstate --out DIR [bundt flags]
//	offramp krm    --krm DIR|FILE --out DIR [bundt flags]
//	offramp names  --assets assets.json
//	offramp compare A.yaml B.yaml
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/highfivelabs/catalog/offramp/internal/offramp"
)

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	var err error
	switch os.Args[1] {
	case "state":
		err = cmdState(os.Args[2:])
	case "krm":
		err = cmdKRM(os.Args[2:])
	case "names":
		err = cmdNames(os.Args[2:])
	case "synth":
		err = cmdSynth(os.Args[2:])
	case "compare":
		var n int
		n, err = cmdCompare(os.Args[2:])
		if err == nil && n > 0 {
			os.Exit(1)
		}
	default:
		usage()
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "offramp:", err)
		os.Exit(2)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, `usage:
  offramp state   --kcc DIR --state FILE --out DIR [--root DIR --tfvars FILE --catalog DIR --modules-json FILE] [--name N --team T --env E --target T --namespace NS --version V --kcc-version V]
  offramp krm     --krm DIR|FILE --out DIR [same Bundt flags]
  offramp synth   --root DIR --tfvars FILE --out STATE [--terraform BIN --project P]
                     (a synthetic state: Terraform plans the root module offline, repeatedly)
  offramp names   --assets FILE      (full resource names for config-connector export)
  offramp compare A.yaml B.yaml      (exit 1 when they differ)`)
	os.Exit(2)
}

type bundtFlags struct {
	opt     offramp.BundtOptions
	out     string
	abandon bool
}

func (b *bundtFlags) register(fs *flag.FlagSet) {
	fs.StringVar(&b.out, "out", "", "output directory")
	fs.StringVar(&b.opt.Name, "name", "", "the Template's, Stack's and Instance's name (default: the state file's directory)")
	fs.StringVar(&b.opt.Team, "team", "platform", "the Team that owns the Stack and the Environment")
	fs.StringVar(&b.opt.Env, "env", "imported", "the Environment")
	fs.StringVar(&b.opt.Target, "target", "infra", "the Environment's Target, the cluster running Config Connector")
	fs.StringVar(&b.opt.Namespace, "namespace", "", "the Environment's namespace (default: <team>-<env>)")
	fs.StringVar(&b.opt.Version, "version", "0.1.0", "the Packages' and the Template's version")
	fs.StringVar(&b.opt.KCCVersion, "kcc-version", "1.160.0", "the Config Connector version the Environment pins")
	fs.BoolVar(&b.abandon, "abandon", true, "write deletion-policy abandon on every object")
}

func (b *bundtFlags) finish(defaultName string) error {
	if b.out == "" {
		return fmt.Errorf("--out is required")
	}
	if b.opt.Name == "" {
		b.opt.Name = defaultName
	}
	b.opt.Name = strings.Trim(strings.ToLower(b.opt.Name), "-")
	if b.opt.Namespace == "" {
		b.opt.Namespace = b.opt.Team + "-" + b.opt.Env
	}
	return nil
}

func (b *bundtFlags) convOpt() offramp.Options {
	if b.abandon {
		return offramp.Options{DeletionPolicy: "abandon"}
	}
	return offramp.Options{DeletionPolicy: "delete"}
}

func cmdState(args []string) error {
	fs := flag.NewFlagSet("state", flag.ExitOnError)
	var kccDir, statePath, root, catalog, modulesJSON string
	var tfvars multiFlag
	fs.StringVar(&kccDir, "kcc", "", "a Config Connector checkout (config/crds/resources and config/servicemappings)")
	fs.StringVar(&statePath, "state", "", "a Terraform state, format 4 (terraform state pull)")
	fs.StringVar(&root, "root", "", "the root module's directory: its module calls graduate to Instances of the catalog's charts where one ports the module and its render matches the state")
	fs.Var(&tfvars, "tfvars", "a tfvars file with the root module's variables (repeatable)")
	fs.StringVar(&catalog, "catalog", "", "the catalog repository's root (default: the directory above offramp/, found from the working directory)")
	fs.StringVar(&modulesJSON, "modules-json", "", "terraform init's .terraform/modules/modules.json (default: under --root when there)")
	var b bundtFlags
	b.register(fs)
	fs.Parse(args)
	if kccDir == "" || statePath == "" {
		return fmt.Errorf("--kcc and --state are required")
	}
	abs, _ := filepath.Abs(statePath)
	if err := b.finish(filepath.Base(filepath.Dir(abs))); err != nil {
		return err
	}
	k, err := offramp.LoadKCC(kccDir)
	if err != nil {
		return err
	}
	st, err := offramp.ReadState(statePath)
	if err != nil {
		return err
	}
	res := offramp.ConvertState(st, k, b.convOpt())
	if root != "" {
		if catalog == "" {
			catalog = findCatalog()
		}
		g, err := offramp.Graduate(res, st, offramp.GraduateOptions{Catalog: catalog, Root: root, Tfvars: tfvars, ModulesJSON: modulesJSON, Namespace: b.opt.Namespace})
		if err != nil {
			return err
		}
		b.opt.Graduation = g
	}
	bundle := offramp.Group(res.Objects, b.opt)
	hdr := fmt.Sprintf("From the Terraform state `%s` (Terraform %s), with Config Connector's kinds from `%s`.", statePath, st.TerraformVersion, kccDir)
	if err := offramp.Write(b.out, res, bundle, hdr); err != nil {
		return err
	}
	return summarize(res, bundle)
}

func cmdKRM(args []string) error {
	fs := flag.NewFlagSet("krm", flag.ExitOnError)
	var in string
	fs.StringVar(&in, "krm", "", "Config Connector YAML: config-connector export's or bulk-export's output")
	var b bundtFlags
	b.register(fs)
	fs.Parse(args)
	if in == "" {
		return fmt.Errorf("--krm is required")
	}
	if err := b.finish("scanned"); err != nil {
		return err
	}
	docs, err := offramp.ReadKRM(in)
	if err != nil {
		return err
	}
	res := offramp.ConvertKRM(docs, b.convOpt())
	bundle := offramp.Group(res.Objects, b.opt)
	if err := offramp.Write(b.out, res, bundle, fmt.Sprintf("From Config Connector's export of a scan, `%s`.", in)); err != nil {
		return err
	}
	return summarize(res, bundle)
}

type multiFlag []string

func (m *multiFlag) String() string     { return strings.Join(*m, ",") }
func (m *multiFlag) Set(v string) error { *m = append(*m, v); return nil }

// findCatalog walks up from the working directory to the catalog's root
// (the directory holding upstream/modules.yaml).
func findCatalog() string {
	d, _ := os.Getwd()
	for {
		if _, err := os.Stat(filepath.Join(d, "upstream", "modules.yaml")); err == nil {
			return d
		}
		p := filepath.Dir(d)
		if p == d {
			return "."
		}
		d = p
	}
}

func summarize(res *offramp.Result, b *offramp.Bundle) error {
	counts := map[string]int{}
	for _, f := range res.Findings {
		counts[f.Class]++
	}
	fmt.Printf("%d objects, %d components", len(res.Objects), len(b.Components))
	if b.Graduation != nil {
		grad := 0
		for _, c := range b.Components {
			if c.Graduated != nil {
				grad++
			}
		}
		fmt.Printf(" (%d graduated to catalog charts)", grad)
	}
	for _, c := range []string{"refused", "gap", "in-cluster", "terraform-only", "note"} {
		if counts[c] > 0 {
			fmt.Printf(", %d %s", counts[c], c)
		}
	}
	fmt.Println()
	return nil
}

func cmdNames(args []string) error {
	fs := flag.NewFlagSet("names", flag.ExitOnError)
	var assets string
	fs.StringVar(&assets, "assets", "", "a JSON array of Cloud Asset Inventory assets")
	fs.Parse(args)
	as, err := offramp.ReadAssets(assets)
	if err != nil {
		return err
	}
	names, skipped := offramp.ExportNames(as)
	for _, n := range names {
		fmt.Println(n)
	}
	for _, s := range skipped {
		fmt.Fprintf(os.Stderr, "skipped %s (%s): %s\n", s.Source, s.Type, s.Reason)
	}
	return nil
}

func cmdCompare(args []string) (int, error) {
	if len(args) != 2 {
		return 0, fmt.Errorf("compare takes two files")
	}
	a, err := offramp.ReadKRM(args[0])
	if err != nil {
		return 0, err
	}
	b, err := offramp.ReadKRM(args[1])
	if err != nil {
		return 0, err
	}
	diffs := offramp.Compare(a, b)
	for _, d := range diffs {
		fmt.Println(d)
	}
	if len(diffs) == 0 {
		fmt.Println("no differences")
	}
	return len(diffs), nil
}

func cmdSynth(args []string) error {
	fs := flag.NewFlagSet("synth", flag.ExitOnError)
	var opt offramp.SynthOptions
	var tfvars multiFlag
	var out string
	fs.StringVar(&opt.Root, "root", "", "the root module's directory")
	fs.Var(&tfvars, "tfvars", "a tfvars file (repeatable)")
	fs.StringVar(&opt.Terraform, "terraform", "terraform", "the terraform binary (1.12 or later for fabric's modules)")
	fs.StringVar(&opt.Project, "project", "", "the provider's default project, for resources whose project the plan leaves unknown")
	fs.StringVar(&out, "out", "", "where to write the synthetic state")
	fs.StringVar(&opt.Work, "work", "", "a scratch directory to plan in (default: a new temporary one)")
	fs.Parse(args)
	if opt.Root == "" || out == "" {
		return fmt.Errorf("--root and --out are required")
	}
	opt.Tfvars = tfvars
	opt.Log = func(s string) { fmt.Fprintln(os.Stderr, "synth:", s) }
	st, b, err := offramp.Synthesize(opt)
	if err != nil {
		return err
	}
	if err := os.WriteFile(out, b, 0o644); err != nil {
		return err
	}
	n := 0
	for _, r := range st.Resources {
		n += len(r.Instances)
	}
	fmt.Printf("synthetic state: %d resource instances\n", n)
	return nil
}
