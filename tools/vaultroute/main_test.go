// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package main

import (
	"net/url"
	"testing"
)

func TestRoute(t *testing.T) {
	keys, _ := url.Parse("https://fakearm.fake-cloud.svc")
	secrets, _ := url.Parse("https://fakevault.fake-cloud.svc")
	for path, want := range map[string]*url.URL{
		"/keys/catalog-key":                keys,
		"/keys/catalog-key/abc":            keys,
		"/keys/catalog-key/rotationpolicy": keys,
		"/deletedkeys/catalog-key":         keys,
		"/Keys/catalog-key":                keys,
		"/secrets/catalog-secret":          secrets,
		"/secrets/catalog-secret/":         secrets,
		"/deletedsecrets/catalog-secret":   secrets,
		"/certificates/app-tls/import":     secrets,
		"/keysmith":                        secrets,
		"/":                                secrets,
	} {
		if got := route(path, keys, secrets); got != want {
			t.Errorf("route(%q) = %s, want %s", path, got, want)
		}
	}
}
