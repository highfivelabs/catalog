// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package upstream

import (
	"fmt"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"strings"
)

// ResolveID turns "gcp/gcs" or a bare module name into the id of the one
// tracked module it names.
func (f *File) ResolveID(name string) (string, error) {
	if m := f.Find(name); m != nil {
		return m.ID, nil
	}
	var ids []string
	for _, m := range f.Modules {
		if m.Module == name {
			ids = append(ids, m.ID)
		}
	}
	switch len(ids) {
	case 0:
		return "", fmt.Errorf("no tracked module %q (ids look like gcp/gcs, aws/kms, azure/avm-res-network-virtualnetwork)", name)
	case 1:
		return ids[0], nil
	}
	return "", fmt.Errorf("%q is ambiguous: %s", name, strings.Join(ids, ", "))
}

// Bump records that the module's pin moved to tag (whose commit is given):
// the entry in upstream/modules.yaml, the chart's upstream.yaml and the
// chart's Chart.yaml annotations. It edits the text of those files, so
// comments and layout stay as they are. It does not port anything: the
// chart's changes are the person's, made before the pin is moved. It
// checks that the result is consistent (CheckAll) and returns what it
// changed.
func Bump(root, id, tag, commit, today string, allowDowngrade bool) ([]string, error) {
	f, err := Load(filepath.Join(root, "upstream", "modules.yaml"))
	if err != nil {
		return nil, err
	}
	m := f.Find(id)
	if m == nil {
		return nil, fmt.Errorf("no tracked module %q", id)
	}
	if ok, _ := path.Match(m.TagPattern, tag); !ok {
		return nil, fmt.Errorf("%s does not match %s's tag pattern %q", tag, id, m.TagPattern)
	}
	nv, ok := ParseSemver(tag)
	if !ok {
		return nil, fmt.Errorf("%s is not a release version (X.Y.Z)", tag)
	}
	ov, _ := ParseSemver(m.Version)
	if tag == m.Version {
		return nil, fmt.Errorf("%s is already pinned to %s", id, tag)
	}
	if Less(nv, ov) && !allowDowngrade {
		return nil, fmt.Errorf("%s is older than the pinned %s (use --allow-downgrade)", tag, m.Version)
	}
	if !shaRE.MatchString(commit) {
		return nil, fmt.Errorf("commit %q is not a 40-digit hex SHA", commit)
	}
	var changed []string
	edit := func(rel string, fn func(string) (string, error)) error {
		p := filepath.Join(root, rel)
		data, err := os.ReadFile(p)
		if err != nil {
			return err
		}
		out, err := fn(string(data))
		if err != nil {
			return fmt.Errorf("%s: %w", rel, err)
		}
		if out != string(data) {
			changed = append(changed, rel)
			return os.WriteFile(p, []byte(out), 0o644)
		}
		return nil
	}

	// upstream/modules.yaml: the lines of this entry's block.
	err = edit("upstream/modules.yaml", func(s string) (string, error) {
		lines := strings.Split(s, "\n")
		start := -1
		for i, l := range lines {
			if l == "  - id: "+id {
				start = i
				break
			}
		}
		if start < 0 {
			return "", fmt.Errorf("entry %s not found", id)
		}
		done := 0
		for i := start + 1; i < len(lines) && !strings.HasPrefix(lines[i], "  - id: ") && !strings.HasPrefix(lines[i], "excluded:") && !strings.HasPrefix(lines[i], "#"); i++ {
			switch {
			case strings.HasPrefix(lines[i], "    version: "):
				lines[i] = "    version: " + tag
				done++
			case strings.HasPrefix(lines[i], "    commit: "):
				lines[i] = "    commit: " + commit
				done++
			case strings.HasPrefix(lines[i], "    url: "):
				lines[i] = "    url: " + m.TreeURL(tag)
				done++
			}
		}
		if done != 3 {
			return "", fmt.Errorf("entry %s: expected version, commit and url lines", id)
		}
		return strings.Join(lines, "\n"), nil
	})
	if err != nil {
		return changed, err
	}

	if m.Chart != "" {
		err = edit(m.Chart+"/upstream.yaml", func(s string) (string, error) {
			s = replaceLine(s, "version: ", tag)
			s = replaceLine(s, "commit: ", commit)
			s = replaceLine(s, "module_url: ", m.TreeURL(tag))
			s = replaceLine(s, "synced: ", today)
			return s, nil
		})
		if err != nil {
			return changed, err
		}
		err = edit(m.Chart+"/Chart.yaml", func(s string) (string, error) {
			s = replaceLine(s, "  hfl.dev/source-version: ", tag)
			s = replaceLine(s, "  hfl.dev/source-commit: ", commit)
			// appVersion: "fabric-v60.0.0" and the sources URL at a commit.
			s = regexp.MustCompile(`(?m)^(appVersion: "[a-z-]*-?)`+regexp.QuoteMeta(m.Version)+`"`).ReplaceAllString(s, "${1}"+tag+`"`)
			s = strings.ReplaceAll(s, "/tree/"+m.Commit, "/tree/"+commit)
			return s, nil
		})
		if err != nil {
			return changed, err
		}
	}
	problems, err := CheckAll(root, nil)
	if err != nil {
		return changed, err
	}
	if len(problems) > 0 {
		return changed, fmt.Errorf("the bump left the pins inconsistent:\n  %s", strings.Join(problems, "\n  "))
	}
	return changed, nil
}

// replaceLine rewrites the first line that starts with prefix.
func replaceLine(s, prefix, value string) string {
	lines := strings.Split(s, "\n")
	for i, l := range lines {
		if strings.HasPrefix(l, prefix) {
			lines[i] = prefix + value
			break
		}
	}
	return strings.Join(lines, "\n")
}
