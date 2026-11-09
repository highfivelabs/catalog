// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package upstream

import (
	"fmt"
	"os/exec"
	"path"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// Tag is a release tag of an upstream repository.
type Tag struct {
	Name   string
	Commit string // the commit the tag points at (peeled for annotated tags)
	Semver [3]int
}

var semverRE = regexp.MustCompile(`^v?(\d+)\.(\d+)\.(\d+)$`)

// ParseSemver reads vX.Y.Z or X.Y.Z; prereleases (v1.0.0-rc1) are not releases.
func ParseSemver(tag string) ([3]int, bool) {
	m := semverRE.FindStringSubmatch(tag)
	if m == nil {
		return [3]int{}, false
	}
	var v [3]int
	for i := 0; i < 3; i++ {
		v[i], _ = strconv.Atoi(m[i+1])
	}
	return v, true
}

// Less orders versions.
func Less(a, b [3]int) bool {
	for i := 0; i < 3; i++ {
		if a[i] != b[i] {
			return a[i] < b[i]
		}
	}
	return false
}

// ListTags reads a repository's release tags with `git ls-remote --tags`
// (a read; nothing is written anywhere), keeping the ones that match the
// glob and are plain X.Y.Z versions, oldest first.
func ListTags(repo, pattern string) ([]Tag, error) {
	polite()
	out, err := exec.Command("git", "ls-remote", "--tags", repo+".git").Output()
	if err != nil {
		msg := ""
		if ee, ok := err.(*exec.ExitError); ok {
			msg = strings.TrimSpace(string(ee.Stderr))
		}
		return nil, fmt.Errorf("git ls-remote --tags %s: %v %s", repo, err, msg)
	}
	byName := map[string]*Tag{}
	for _, line := range strings.Split(string(out), "\n") {
		f := strings.Fields(line)
		if len(f) != 2 || !strings.HasPrefix(f[1], "refs/tags/") {
			continue
		}
		name := strings.TrimPrefix(f[1], "refs/tags/")
		peeled := strings.HasSuffix(name, "^{}")
		name = strings.TrimSuffix(name, "^{}")
		if ok, _ := path.Match(pattern, name); !ok {
			continue
		}
		sv, ok := ParseSemver(name)
		if !ok {
			continue
		}
		t := byName[name]
		if t == nil {
			t = &Tag{Name: name, Semver: sv}
			byName[name] = t
		}
		if peeled || t.Commit == "" {
			t.Commit = f[0]
		}
	}
	var tags []Tag
	for _, t := range byName {
		tags = append(tags, *t)
	}
	sort.Slice(tags, func(i, j int) bool { return Less(tags[i].Semver, tags[j].Semver) })
	return tags, nil
}
