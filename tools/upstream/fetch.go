// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package upstream

import (
	"archive/tar"
	"compress/gzip"
	"fmt"
	"io"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

// Everything in this file only reads from upstream: `git ls-remote` and
// GETs of public tarballs and files. Nothing is ever written to, commented
// on or opened in an upstream repository.

// UserAgent identifies the tools to GitHub.
const UserAgent = "highfivelabs-catalog-tools (read-only; https://github.com/highfivelabs/catalog)"

// Politeness is the pause before each request to GitHub.
var Politeness = 300 * time.Millisecond

var (
	mu       sync.Mutex
	lastCall time.Time
)

// polite spaces requests to one host Politeness apart.
// Polite waits until a request may be made.
func Polite() { polite() }

func polite() {
	mu.Lock()
	defer mu.Unlock()
	if d := time.Until(lastCall.Add(Politeness)); d > 0 {
		time.Sleep(d)
	}
	lastCall = time.Now()
}

// Get fetches a URL with a GET, retrying on 429 and 5xx (honouring
// Retry-After), at most Politeness apart from the last request.
func Get(url string) (io.ReadCloser, error) {
	var last error
	for attempt := 0; attempt < 4; attempt++ {
		polite()
		req, err := http.NewRequest(http.MethodGet, url, nil)
		if err != nil {
			return nil, err
		}
		req.Header.Set("User-Agent", UserAgent)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			last = err
			time.Sleep(time.Duration(attempt+1) * 2 * time.Second)
			continue
		}
		if resp.StatusCode == http.StatusOK {
			return resp.Body, nil
		}
		resp.Body.Close()
		last = fmt.Errorf("GET %s: %s", url, resp.Status)
		if resp.StatusCode == 429 || resp.StatusCode >= 500 {
			wait := time.Duration(attempt+1) * 5 * time.Second
			if ra := resp.Header.Get("Retry-After"); ra != "" {
				var s int
				if _, err := fmt.Sscanf(ra, "%d", &s); err == nil && s > 0 && s < 120 {
					wait = time.Duration(s) * time.Second
				}
			}
			time.Sleep(wait)
			continue
		}
		break
	}
	return nil, last
}

// Source is a cached checkout of a repository's Terraform files at a tag.
type Source struct {
	Slug string // owner/name
	Tag  string
	Dir  string // the extracted tree
}

// Dir returns where a module's files are, given the module's path.
func (s Source) ModuleDir(modPath string) string {
	return filepath.Join(s.Dir, filepath.FromSlash(modPath))
}

// Fetch downloads the repository's tarball at the tag (GET of
// codeload.github.com) and extracts its .tf files under paths into
// cacheDir/<owner>/<name>/<tag>, unless that is already done. A path of
// "." takes the whole tree except examples, tests and wrappers.
func Fetch(cacheDir, slug, tag string, paths []string) (Source, error) {
	paths = append([]string(nil), paths...)
	sort.Strings(paths)
	dir := filepath.Join(cacheDir, filepath.FromSlash(slug), tag)
	src := Source{Slug: slug, Tag: tag, Dir: dir}
	marker := filepath.Join(dir, ".fetched")
	if b, err := os.ReadFile(marker); err == nil {
		have := strings.Split(string(b), "\n")
		if covers(have, paths) {
			return src, nil
		}
		// Extract what was there too, so two callers do not undo each other.
		for _, h := range have {
			paths = appendUnique(paths, h)
		}
		sort.Strings(paths)
	}
	want := strings.Join(paths, "\n")
	if err := os.RemoveAll(dir); err != nil {
		return src, err
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return src, err
	}
	body, err := Get(fmt.Sprintf("https://codeload.github.com/%s/tar.gz/refs/tags/%s", slug, tag))
	if err != nil {
		return src, err
	}
	defer body.Close()
	if err := extract(body, dir, paths); err != nil {
		os.RemoveAll(dir)
		return src, fmt.Errorf("%s@%s: %w", slug, tag, err)
	}
	return src, os.WriteFile(marker, []byte(want), 0o644)
}

// covers reports whether an earlier extraction of have includes want.
func covers(have, want []string) bool {
	set := map[string]bool{}
	for _, h := range have {
		if h == "." {
			return true
		}
		set[h] = true
	}
	for _, w := range want {
		if !set[w] {
			return false
		}
	}
	return true
}

func wanted(rel string, paths []string) bool {
	if !strings.HasSuffix(rel, ".tf") {
		return false
	}
	for _, p := range paths {
		if p == "." || p == "" {
			for _, skip := range []string{"examples/", "example/", "tests/", "test/", "wrappers/", ".github/"} {
				if strings.HasPrefix(rel, skip) || strings.Contains(rel, "/"+skip) {
					return false
				}
			}
			return true
		}
		if strings.HasPrefix(rel, p+"/") {
			for _, skip := range []string{"/examples/", "/tests/", "/test/"} {
				if strings.Contains(rel[len(p):], skip) {
					return false
				}
			}
			return true
		}
	}
	return false
}

func extract(r io.Reader, dir string, paths []string) error {
	gz, err := gzip.NewReader(r)
	if err != nil {
		return err
	}
	defer gz.Close()
	tr := tar.NewReader(gz)
	for {
		h, err := tr.Next()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		if h.Typeflag != tar.TypeReg {
			continue
		}
		// Drop the archive's top directory (<repo>-<tag>/).
		i := strings.Index(h.Name, "/")
		if i < 0 {
			continue
		}
		rel := path.Clean(h.Name[i+1:])
		if !wanted(rel, paths) || strings.Contains(rel, "..") {
			continue
		}
		out := filepath.Join(dir, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(out), 0o755); err != nil {
			return err
		}
		f, err := os.Create(out)
		if err != nil {
			return err
		}
		if _, err := io.Copy(f, tr); err != nil {
			f.Close()
			return err
		}
		if err := f.Close(); err != nil {
			return err
		}
	}
}

func appendUnique(s []string, v string) []string {
	for _, x := range s {
		if x == v {
			return s
		}
	}
	return append(s, v)
}
