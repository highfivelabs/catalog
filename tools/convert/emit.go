// Copyright 2026 High Five Labs
// SPDX-License-Identifier: Apache-2.0

package convert

import (
	"bytes"
	"sort"

	"gopkg.in/yaml.v3"
)

func scalar(v any) *yaml.Node {
	n := &yaml.Node{}
	if err := n.Encode(v); err != nil {
		panic(err)
	}
	return n
}

func str(s string) *yaml.Node { return &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!str", Value: s} }

func quoted(s string) *yaml.Node {
	return &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!str", Value: s, Style: yaml.DoubleQuotedStyle}
}

func mapping(kv ...*yaml.Node) *yaml.Node {
	return &yaml.Node{Kind: yaml.MappingNode, Tag: "!!map", Content: kv}
}

func toNode(v any) *yaml.Node {
	switch x := v.(type) {
	case Ordered:
		return orderedNode(x)
	case map[string]any:
		keys := make([]string, 0, len(x))
		for k := range x {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		n := mapping()
		for _, k := range keys {
			n.Content = append(n.Content, scalarKey(k), toNode(x[k]))
		}
		return n
	case []any:
		n := &yaml.Node{Kind: yaml.SequenceNode, Tag: "!!seq"}
		for _, e := range x {
			n.Content = append(n.Content, toNode(e))
		}
		return n
	case string:
		// A string holding an expression stays a plain-looking string where YAML allows; ${ is fine plain
		// only when it does not start with a special character, so let the encoder decide.
		return scalar(x)
	}
	return scalar(v)
}

func scalarKey(k string) *yaml.Node { return scalar(k) }

func orderedNode(o Ordered) *yaml.Node {
	n := mapping()
	for _, p := range o {
		n.Content = append(n.Content, scalarKey(p.Key), toNode(p.Value))
	}
	return n
}

func seqOf(items ...*yaml.Node) *yaml.Node {
	return &yaml.Node{Kind: yaml.SequenceNode, Tag: "!!seq", Content: items}
}

// render writes the Template, the Stack and the Instance.
func render(res *Result, o Options) string {
	var docs []*yaml.Node

	var comps []*yaml.Node
	for _, c := range res.Components {
		cn := mapping(
			str("name"), str(c.Name),
			str("package"), mapping(str("name"), str(c.Chart.Package), str("version"), quoted(c.Chart.Version)),
		)
		if len(c.DependsOn) > 0 {
			var d []*yaml.Node
			for _, x := range c.DependsOn {
				d = append(d, str(x))
			}
			cn.Content = append(cn.Content, str("dependsOn"), seqOf(d...))
		}
		if len(c.Inputs) > 0 {
			cn.Content = append(cn.Content, str("inputs"), orderedNode(c.Inputs))
		}
		comps = append(comps, cn)
	}
	template := mapping(
		str("apiVersion"), str("hfl.dev/v1"),
		str("kind"), str("Template"),
		str("metadata"), mapping(str("name"), str(res.TemplateName)),
		str("spec"), mapping(str("version"), quoted(o.TemplateVersion), str("components"), seqOf(comps...)),
	)
	docs = append(docs, template)

	stack := mapping(
		str("apiVersion"), str("hfl.dev/v1"),
		str("kind"), str("Stack"),
		str("metadata"), mapping(str("name"), str(res.TemplateName), str("scope"), str(o.Team)),
		str("spec"), mapping(str("template"), str(res.TemplateName)),
	)
	docs = append(docs, stack)

	spec := mapping(str("stack"), str(res.TemplateName), str("version"), quoted(o.TemplateVersion))
	vals := mapping()
	for _, c := range res.Components {
		if len(c.Values) > 0 {
			vals.Content = append(vals.Content, str(c.Name), mapping(str("values"), orderedNode(c.Values)))
		}
	}
	if len(vals.Content) > 0 {
		spec.Content = append(spec.Content, str("components"), vals)
	}
	instance := mapping(
		str("apiVersion"), str("hfl.dev/v1"),
		str("kind"), str("Instance"),
		str("metadata"), mapping(str("name"), str(res.TemplateName+"-"+o.Env), str("scope"), str(o.Team+"/"+o.Env)),
		str("spec"), spec,
	)
	docs = append(docs, instance)

	var b bytes.Buffer
	for i, d := range docs {
		if i > 0 {
			b.WriteString("---\n")
		}
		enc := yaml.NewEncoder(&b)
		enc.SetIndent(2)
		if err := enc.Encode(d); err != nil {
			panic(err)
		}
		enc.Close()
	}
	return b.String()
}
