// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package convert

import (
	"fmt"
	"regexp"
	"strings"

	"github.com/hashicorp/hcl/v2"
	"github.com/zclconf/go-cty/cty"
	"github.com/zclconf/go-cty/cty/function"
)

// A module output is evaluated as a marker string, \x01module.<c>.<o>\x01,
// written out as ${components.<c>.outputs.<o>}. A function applied to an
// output becomes a CEL expression, \x02<cel>\x02, written as ${<cel>},
// where Bundt's CEL can say it; otherwise the argument cannot be carried.
var celMarker = regexp.MustCompile("\x02([^\x02]+)\x02")

// indexOnly reports whether the steps are one index by a literal string key.
func indexOnly(t hcl.Traversal) bool {
	if len(t) != 1 {
		return false
	}
	ix, ok := t[0].(hcl.TraverseIndex)
	return ok && ix.Key.Type() == cty.String
}

func hasMarker(v cty.Value) bool {
	if !v.IsKnown() || v.IsNull() {
		return false
	}
	t := v.Type()
	switch {
	case t == cty.String:
		return strings.ContainsAny(v.AsString(), "\x01\x02")
	case t.IsListType() || t.IsSetType() || t.IsTupleType() || t.IsMapType() || t.IsObjectType():
		for it := v.ElementIterator(); it.Next(); {
			_, e := it.Element()
			if hasMarker(e) {
				return true
			}
		}
	}
	return false
}

// celOf gives the CEL expression for a value that is exactly one marker.
func celOf(v cty.Value) (string, bool) {
	if v.Type() != cty.String {
		return "", false
	}
	s := v.AsString()
	if m := marker.FindStringSubmatch(s); m != nil && m[0] == s {
		return "components." + m[1] + ".outputs." + m[2], true
	}
	if m := celMarker.FindStringSubmatch(s); m != nil && m[0] == s {
		return "(" + m[1] + ")", true
	}
	return "", false
}

func celString(s string) string {
	return "'" + strings.ReplaceAll(strings.ReplaceAll(s, `\`, `\\`), "'", `\'`) + "'"
}

// passThrough are functions that keep a marker intact: they move strings
// around without looking inside them.
var passThrough = map[string]bool{
	"coalesce": true, "coalescelist": true, "compact": true, "concat": true, "distinct": true, "element": true,
	"flatten": true, "format": true, "formatlist": true, "join": true, "lookup": true, "merge": true,
	"reverse": true, "setunion": true, "slice": true, "tolist": true, "tomap": true, "toset": true,
	"tostring": true, "values": true, "zipmap": true,
}

// guardedFuncs are funcs for arguments that may read module outputs.
var guardedFuncs = func() map[string]function.Function {
	out := map[string]function.Function{}
	for name, f := range funcs {
		out[name] = guard(name, f)
	}
	return out
}()

func guard(name string, f function.Function) function.Function {
	if passThrough[name] {
		return f
	}
	spec := &function.Spec{
		Params:   f.Params(),
		VarParam: f.VarParam(),
		Type: func(args []cty.Value) (cty.Type, error) {
			for _, a := range args {
				if hasMarker(a) {
					return cty.String, nil
				}
			}
			return f.ReturnTypeForValues(args)
		},
		Impl: func(args []cty.Value, _ cty.Type) (cty.Value, error) {
			marked := false
			for _, a := range args {
				marked = marked || hasMarker(a)
			}
			if !marked {
				return f.Call(args)
			}
			x, whole := celOf(args[0])
			lit := func(i int) (string, bool) {
				if i >= len(args) || args[i].Type() != cty.String || hasMarker(args[i]) {
					return "", false
				}
				return args[i].AsString(), true
			}
			switch name {
			case "trimprefix":
				if p, ok := lit(1); ok && whole {
					return cty.StringVal(fmt.Sprintf("\x02%s.startsWith(%s) ? %s.substring(%d) : %s\x02", x, celString(p), x, len([]rune(p)), x)), nil
				}
			case "trimsuffix":
				if p, ok := lit(1); ok && whole {
					return cty.StringVal(fmt.Sprintf("\x02%s.endsWith(%s) ? %s.substring(0, %s.size() - %d) : %s\x02", x, celString(p), x, x, len([]rune(p)), x)), nil
				}
			case "replace":
				a, ok1 := lit(1)
				b, ok2 := lit(2)
				if ok1 && ok2 && whole && !strings.HasPrefix(a, "/") {
					return cty.StringVal(fmt.Sprintf("\x02%s.replace(%s, %s)\x02", x, celString(a), celString(b))), nil
				}
			case "lower", "upper":
				if whole {
					return cty.StringVal(fmt.Sprintf("\x02%s.%sAscii()\x02", x, name)), nil
				}
			}
			return cty.NilVal, fmt.Errorf("%s() of a module output cannot be written as a Bundt expression: write the value, or take it from another component's output as it is", name)
		},
	}
	return function.New(spec)
}
