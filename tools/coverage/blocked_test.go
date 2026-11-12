// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package coverage

import (
	"strings"
	"testing"
)

func TestBlockedKinds(t *testing.T) {
	res := &Result{
		Rows: []Row{
			{Cloud: "gcp", Module: "a", Status: Blocked},
			{Cloud: "gcp", Module: "b", Status: Blocked},
			{Cloud: "gcp", Module: "c", Status: Blocked},
			{Cloud: "gcp", Module: "d", Status: NotStarted},
			{Cloud: "aws", Module: "a", Status: Blocked},
		},
		Types: []TypeRow{
			{Cloud: "gcp", Module: "a", Type: "google_x_route_policy", Class: "none"},
			{Cloud: "gcp", Module: "b", Type: "google_x_route_policy", Class: "none"},
			{Cloud: "gcp", Module: "b", Type: "google_y_iam_member", Class: "alpha", Kind: "YAccess/Y.spec.access"},
			{Cloud: "gcp", Module: "c", Type: "google_y_access", Class: "alpha", Kind: "YAccess"},
			{Cloud: "gcp", Module: "c", Type: "google_z", Class: "stable", Kind: "Z"},
			{Cloud: "gcp", Module: "d", Type: "google_w", Class: "alpha", Kind: "W"},
			{Cloud: "aws", Module: "a", Type: "aws_v", Class: "none"},
		},
	}
	order, n := blockedKinds(res)
	if n != 3 {
		t.Fatalf("blocked modules = %d, want 3", n)
	}
	var got []string
	for _, k := range order {
		got = append(got, k.Name+":"+strings.Join(k.Unblocks, "+"))
	}
	// XRoutePolicy unblocks a alone; YAccess (two types, one kind) then
	// unblocks b and c. W (not blocked) and AWS are not counted.
	if want := "XRoutePolicy:a YAccess:b+c"; strings.Join(got, " ") != want {
		t.Fatalf("order = %q, want %q", strings.Join(got, " "), want)
	}
	if !order[0].Proposed || order[1].Proposed {
		t.Fatalf("proposed = %v, %v", order[0].Proposed, order[1].Proposed)
	}
	page := string(blockedKindsPage(res))
	for _, s := range []string{"3 blocked modules lack 2 kinds", "| 1 | `XRoutePolicy` (proposed) | none | 1: `a` | 1 | 2 | 1 |", "| `c` | 1: `YAccess` |"} {
		if !strings.Contains(page, s) {
			t.Errorf("page lacks %q:\n%s", s, page)
		}
	}
}
