package main

import (
	"fmt"
	"io"
	"maps"
	"slices"
	"strings"
)

// Plan is the set of changes that would bring the controller in line with
// the declarations. Building it never calls the API.
type Plan struct {
	Lists    []Change
	Policies []Change
	Orders   []OrderChange
	MDNSMode *[2]string // {actual, desired}
	// MDNSNetworks is set when the mDNS network list differs. It is read-only
	// through the API (CONTEXT.md Q31), so it is reported, never applied.
	MDNSNetworks *[2][]string
}

// Change creates (ID == "") or updates one object.
type Change struct {
	Label  string
	ID     string
	Body   obj
	Before obj // live object, for the backup; nil on create
	Paths  []string
}

type OrderChange struct {
	Label   string
	Src     string
	Dst     string
	Current Ordering
	Desired Ordering
	names   map[string]string // policy ID -> display name
}

// Applicable reports whether the plan has changes the API can make; the mDNS
// network list is the one change left to the UI.
func (p *Plan) Applicable() bool {
	return len(p.Lists) > 0 || len(p.Policies) > 0 || len(p.Orders) > 0 || p.MDNSMode != nil
}

func (p *Plan) Empty() bool {
	return !p.Applicable() && p.MDNSNetworks == nil
}

// newPrefix marks the stand-in ID of an object the plan would create, so later
// steps (policy resolution, ordering) can be planned before it exists.
const newPrefix = "new:"

func buildPlan(d *Declarations, s *State) (*Plan, error) {
	p := &Plan{}
	names := Names{Zones: s.Names.Zones, Networks: s.Names.Networks, Lists: maps.Clone(s.Names.Lists)}

	live := map[string]obj{}
	for _, l := range s.Lists {
		name, _ := l["name"].(string)
		live[name] = l
	}
	for _, want := range d.Lists {
		name, _ := want["name"].(string)
		body := listFields(want)
		label := fmt.Sprintf("traffic matching list %q", name)
		got, ok := live[name]
		if !ok {
			names.Lists[name] = newPrefix + name
			p.Lists = append(p.Lists, Change{Label: label, Body: body})
			continue
		}
		if paths := diffPaths(listFields(got), body); len(paths) > 0 {
			id, _ := got["id"].(string)
			p.Lists = append(p.Lists, Change{Label: label, ID: id, Body: body, Before: got, Paths: paths})
		}
	}

	zoneName := invert(s.Names.Zones)
	livePol := map[string]obj{}
	display := map[string]string{}
	for _, lp := range s.Policies {
		k := livePolicyKey(lp, zoneName)
		if _, dup := livePol[k]; dup {
			return nil, fmt.Errorf("controller has more than one policy %s", k)
		}
		livePol[k] = lp
		id, _ := lp["id"].(string)
		name, _ := lp["name"].(string)
		display[id] = name
	}

	type pair struct{ src, dst string }
	var pairs []pair
	declared := map[pair][]string{}
	for _, want := range d.Policies {
		name, _ := want["name"].(string)
		key := policyKey(name, sideField(want, "source", "zone"), sideField(want, "destination", "zone"))
		body, err := resolvePolicy(want, names)
		if err != nil {
			return nil, fmt.Errorf("policy %s: %w", key, err)
		}
		pr := pair{sideField(body, "source", "zoneId"), sideField(body, "destination", "zoneId")}
		if _, seen := declared[pr]; !seen {
			pairs = append(pairs, pr)
		}
		id := newPrefix + key
		label := "policy " + key
		if got, ok := livePol[key]; ok {
			id, _ = got["id"].(string)
			if paths := diffPaths(projectPolicy(got), projectPolicy(body)); len(paths) > 0 {
				p.Policies = append(p.Policies, Change{Label: label, ID: id, Body: body, Before: got, Paths: paths})
			}
		} else {
			p.Policies = append(p.Policies, Change{Label: label, Body: body})
		}
		display[id] = name
		declared[pr] = append(declared[pr], id)
	}

	for _, pr := range pairs {
		cur := s.Orders[[2]string{pr.src, pr.dst}]
		want := desiredOrder(cur, declared[pr])
		if !slices.Equal(cur.Before, want.Before) || !slices.Equal(cur.After, want.After) {
			p.Orders = append(p.Orders, OrderChange{
				Label: fmt.Sprintf("order %s -> %s", zoneName[pr.src], zoneName[pr.dst]),
				Src:   pr.src, Dst: pr.dst, Current: cur, Desired: want, names: display,
			})
		}
	}

	if mode, _ := s.MDNS["mode"].(string); mode != d.MDNS.Mode {
		p.MDNSMode = &[2]string{mode, d.MDNS.Mode}
	}
	netName := invert(s.ClassicNetworks)
	var have []string
	if ids, ok := s.MDNS["enabled_for_network_ids"].([]any); ok {
		for _, id := range ids {
			sid, _ := id.(string)
			n, ok := netName[sid]
			if !ok {
				n = sid
			}
			have = append(have, n)
		}
	}
	for _, n := range d.MDNS.Networks {
		if _, ok := s.ClassicNetworks[n]; !ok {
			return nil, fmt.Errorf("mdns.json: unknown network %q", n)
		}
	}
	want := slices.Clone(d.MDNS.Networks)
	slices.Sort(have)
	slices.Sort(want)
	if !slices.Equal(have, want) {
		p.MDNSNetworks = &[2][]string{have, want}
	}
	return p, nil
}

// desiredOrder puts the declared policies first, in declaration order, ahead
// of every system-defined policy. Undeclared user policies keep their current
// relative order behind them (CONTEXT.md Q28).
func desiredOrder(cur Ordering, declared []string) Ordering {
	isDeclared := map[string]bool{}
	for _, id := range declared {
		isDeclared[id] = true
	}
	out := Ordering{Before: slices.Clone(declared), After: []string{}}
	for _, id := range cur.Before {
		if !isDeclared[id] {
			out.Before = append(out.Before, id)
		}
	}
	for _, id := range cur.After {
		if !isDeclared[id] {
			out.After = append(out.After, id)
		}
	}
	return out
}

func livePolicyKey(p obj, zoneName map[string]string) string {
	name, _ := p["name"].(string)
	return policyKey(name, zoneName[sideField(p, "source", "zoneId")], zoneName[sideField(p, "destination", "zoneId")])
}

func invert(m map[string]string) map[string]string {
	out := make(map[string]string, len(m))
	for k, v := range m {
		out[v] = k
	}
	return out
}

func (p *Plan) Print(w io.Writer) {
	if p.Empty() {
		fmt.Fprintln(w, "No changes. The controller matches unifi/controller/.")
		return
	}
	for _, c := range append(slices.Clone(p.Lists), p.Policies...) {
		if c.ID == "" {
			fmt.Fprintf(w, "+ create %s\n", c.Label)
		} else {
			fmt.Fprintf(w, "~ update %s: %s\n", c.Label, strings.Join(c.Paths, ", "))
		}
	}
	for _, o := range p.Orders {
		fmt.Fprintf(w, "~ %s\n    current: %s\n    desired: %s\n", o.Label, o.render(o.Current.Before), o.render(o.Desired.Before))
	}
	if p.MDNSMode != nil {
		fmt.Fprintf(w, "~ update mdns mode: %q -> %q\n", p.MDNSMode[0], p.MDNSMode[1])
	}
	if p.MDNSNetworks != nil {
		fmt.Fprintf(w, "! manual mdns networks: %v -> %v\n", p.MDNSNetworks[0], p.MDNSNetworks[1])
		fmt.Fprintln(w, "    The API ignores this field. In the UI: Settings -> Networks -> Global Network Settings ->")
		fmt.Fprintln(w, "    Multicast DNS, set the networks above, keep services on \"All\", save, then re-run plan.")
	}
}

func (o OrderChange) render(ids []string) string {
	out := make([]string, len(ids))
	for i, id := range ids {
		if n, ok := o.names[id]; ok {
			out[i] = fmt.Sprintf("%q", n)
		} else {
			out[i] = id
		}
	}
	return "[" + strings.Join(out, ", ") + "]"
}
