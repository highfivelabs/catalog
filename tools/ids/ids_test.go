// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package ids

import (
	"strings"
	"testing"
)

func obj(kind, name, id string) object {
	var o object
	o.Kind, o.Metadata.Name = kind, name
	if id != "" {
		o.Metadata.Annotations = map[string]string{Annotation: id}
	}
	return o
}

func TestObjects(t *testing.T) {
	for _, tc := range []struct {
		name string
		objs []object
		want []string
	}{
		{"distinct", []object{obj("StorageBucket", "a", "bucket-0"), obj("StorageBucket", "b", "bucket-1")}, nil},
		{"missing", []object{obj("StorageBucket", "a", "")}, []string{"has no hfl.dev/id"}},
		{"same kind, one id", []object{obj("StorageBucket", "a", "bucket"), obj("StorageBucket", "b", "bucket")}, []string{`"bucket" is on 2 objects`}},
		{"other kinds, one id", []object{obj("StorageBucket", "a", "x"), obj("PubSubTopic", "b", "x")}, []string{`"x" is on 2 objects`}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := Objects("c/case", tc.objs)
			if len(got) != len(tc.want) {
				t.Fatalf("got %q, want %d problems", got, len(tc.want))
			}
			for i, w := range tc.want {
				if !strings.Contains(got[i], w) {
					t.Errorf("problem %d: %q does not say %q", i, got[i], w)
				}
			}
		})
	}
}
