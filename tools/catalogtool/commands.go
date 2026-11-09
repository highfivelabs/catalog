// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/highfivelabs/catalog/tools/upstream"
)

// commands are the subcommands that take their own arguments; the older
// ones (schemas, check, outputs) are dispatched in main.
var commands = map[string]func(args []string) error{
	"upstream": upstreamCmd,
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
