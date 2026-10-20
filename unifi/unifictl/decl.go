package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
)

// obj is a generic JSON object. Declarations and API payloads are handled as
// untyped trees so filter variants this tool does not know about pass through.
type obj = map[string]any

// Declarations mirrors unifi/controller/*.json. Policies reference zones,
// networks and traffic matching lists by name; UUIDs never appear (CONTEXT.md Q27).
type Declarations struct {
	Policies []obj
	Lists    []obj
	MDNS     MDNSDecl
}

type MDNSDecl struct {
	Mode     string   `json:"mode"`
	Networks []string `json:"networks"`
}

// secretKey matches key names that only show up in objects carrying
// credentials. A declaration containing one is refused outright (CONTEXT.md Q30).
var secretKey = regexp.MustCompile(`(?i)(^x_|passphrase|password|psk|token|private_key|secret)`)

func loadDeclarations(dir string) (*Declarations, error) {
	d := &Declarations{}
	if err := readJSON(filepath.Join(dir, "firewall-policies.json"), &d.Policies); err != nil {
		return nil, err
	}
	if err := readJSON(filepath.Join(dir, "traffic-matching-lists.json"), &d.Lists); err != nil {
		return nil, err
	}
	if err := readJSON(filepath.Join(dir, "mdns.json"), &d.MDNS); err != nil {
		return nil, err
	}
	for _, p := range d.Policies {
		if err := checkSecrets(p, "firewall-policies.json"); err != nil {
			return nil, err
		}
	}
	for _, l := range d.Lists {
		if err := checkSecrets(l, "traffic-matching-lists.json"); err != nil {
			return nil, err
		}
	}
	return d, d.validate()
}

func readJSON(path string, v any) error {
	b, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	if err := json.Unmarshal(b, v); err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}
	return nil
}

func checkSecrets(v any, where string) error {
	switch t := v.(type) {
	case obj:
		for k, c := range t {
			if secretKey.MatchString(k) {
				return fmt.Errorf("%s: refusing secret-looking key %q", where, k)
			}
			if err := checkSecrets(c, where); err != nil {
				return err
			}
		}
	case []any:
		for _, c := range t {
			if err := checkSecrets(c, where); err != nil {
				return err
			}
		}
	}
	return nil
}

func (d *Declarations) validate() error {
	seen := map[string]bool{}
	for i, p := range d.Policies {
		name, _ := p["name"].(string)
		src, dst := sideZone(p, "source"), sideZone(p, "destination")
		if name == "" || src == "" || dst == "" {
			return fmt.Errorf("firewall-policies.json[%d]: name, source.zone and destination.zone are required", i)
		}
		k := policyKey(name, src, dst)
		if seen[k] {
			return fmt.Errorf("firewall-policies.json: duplicate policy %s", k)
		}
		seen[k] = true
	}
	lists := map[string]bool{}
	for i, l := range d.Lists {
		name, _ := l["name"].(string)
		if name == "" || lists[name] {
			return fmt.Errorf("traffic-matching-lists.json[%d]: missing or duplicate name %q", i, name)
		}
		lists[name] = true
	}
	if d.MDNS.Mode == "" {
		return fmt.Errorf("mdns.json: mode is required")
	}
	return nil
}

func sideZone(p obj, side string) string {
	s, _ := p[side].(obj)
	z, _ := s["zone"].(string)
	return z
}

// policyKey identifies a policy by (name, source zone, destination zone);
// names alone are not unique (four "Allow ICMPv6" policies exist).
func policyKey(name, src, dst string) string {
	return fmt.Sprintf("%q (%s -> %s)", name, src, dst)
}

// Names maps object names to IDs for one controller.
type Names struct {
	Zones    map[string]string
	Networks map[string]string
	Lists    map[string]string
}

// resolvePolicy turns a declared policy into an API request body: zone names
// become zoneId, "networks" becomes networkIds and "trafficMatchingList"
// becomes trafficMatchingListId. Unknown names are errors, never guesses.
func resolvePolicy(p obj, n Names) (obj, error) {
	out, err := resolveTree(deepCopy(p), n)
	if err != nil {
		return nil, err
	}
	body := out.(obj)
	for _, side := range []string{"source", "destination"} {
		s, _ := body[side].(obj)
		z, _ := s["zone"].(string)
		id, ok := n.Zones[z]
		if !ok {
			return nil, fmt.Errorf("%s: unknown zone %q", side, z)
		}
		delete(s, "zone")
		s["zoneId"] = id
	}
	return body, nil
}

func resolveTree(v any, n Names) (any, error) {
	switch t := v.(type) {
	case obj:
		for k, c := range t {
			r, err := resolveTree(c, n)
			if err != nil {
				return nil, err
			}
			t[k] = r
		}
		if nets, ok := t["networks"].([]any); ok {
			ids := make([]any, 0, len(nets))
			for _, x := range nets {
				name, _ := x.(string)
				id, ok := n.Networks[name]
				if !ok {
					return nil, fmt.Errorf("unknown network %q", name)
				}
				ids = append(ids, id)
			}
			delete(t, "networks")
			t["networkIds"] = ids
		}
		if l, ok := t["trafficMatchingList"].(string); ok {
			id, ok := n.Lists[l]
			if !ok {
				return nil, fmt.Errorf("unknown traffic matching list %q", l)
			}
			delete(t, "trafficMatchingList")
			t["trafficMatchingListId"] = id
		}
		return t, nil
	case []any:
		for i, c := range t {
			r, err := resolveTree(c, n)
			if err != nil {
				return nil, err
			}
			t[i] = r
		}
		return t, nil
	}
	return v, nil
}

// policyFields are the policy keys this tool owns. reportFlowEnabled, index
// and metadata are controller-owned and left alone.
var policyFields = []string{"name", "description", "enabled", "action", "source", "destination", "ipProtocolScope", "loggingEnabled"}

// projectPolicy keeps only the owned fields of an API policy, treating a
// missing description as "" so it compares equal to an omitted one.
func projectPolicy(p obj) obj {
	out := obj{}
	for _, k := range policyFields {
		if v, ok := p[k]; ok {
			out[k] = deepCopy(v)
		}
	}
	if _, ok := out["description"]; !ok {
		out["description"] = ""
	}
	return out
}

func listFields(l obj) obj {
	return obj{"name": l["name"], "type": l["type"], "items": deepCopy(l["items"])}
}

// canonical sorts every array by its JSON encoding. Every array in a policy or
// list is a set (ports, addresses, network IDs), so order carries no meaning
// and the API is free to reorder it.
func canonical(v any) any {
	switch t := v.(type) {
	case obj:
		out := obj{}
		for k, c := range t {
			out[k] = canonical(c)
		}
		return out
	case []any:
		out := make([]any, len(t))
		for i, c := range t {
			out[i] = canonical(c)
		}
		slices.SortFunc(out, func(a, b any) int { return strings.Compare(encode(a), encode(b)) })
		return out
	}
	return v
}

// diffPaths returns the dotted paths where a and b differ, after canonical().
func diffPaths(a, b any) []string {
	var out []string
	walkDiff(canonical(a), canonical(b), "", &out)
	return out
}

func walkDiff(a, b any, path string, out *[]string) {
	ao, aok := a.(obj)
	bo, bok := b.(obj)
	if aok && bok {
		keys := map[string]bool{}
		for k := range ao {
			keys[k] = true
		}
		for k := range bo {
			keys[k] = true
		}
		sorted := make([]string, 0, len(keys))
		for k := range keys {
			sorted = append(sorted, k)
		}
		slices.Sort(sorted)
		for _, k := range sorted {
			p := k
			if path != "" {
				p = path + "." + k
			}
			walkDiff(ao[k], bo[k], p, out)
		}
		return
	}
	if encode(a) != encode(b) {
		if path == "" {
			path = "(root)"
		}
		*out = append(*out, path)
	}
}

// encode and deepCopy only ever see trees produced by json.Unmarshal, which
// always re-encode; a failure means a programming error, so it panics.
func encode(v any) string {
	b, err := json.Marshal(v)
	if err != nil {
		panic(fmt.Sprintf("encode: %v", err))
	}
	return string(b)
}

func deepCopy(v any) any {
	var out any
	if err := json.Unmarshal([]byte(encode(v)), &out); err != nil {
		panic(fmt.Sprintf("deepCopy: %v", err))
	}
	return out
}
