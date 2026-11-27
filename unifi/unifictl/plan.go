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
	Zones          []Change
	Lists          []Change
	Policies       []Change
	DeletePolicies []Change
	Orders         []OrderChange
	MDNSMode       *[2]string // {actual, desired}
	// MDNSNetworks is set when the mDNS network list differs. It is read-only
	// through the API (CONTEXT.md Q31), so it is reported, never applied.
	MDNSNetworks   *[2][]string
	ClassicUpdates []ClassicUpdate
}

// Change creates (ID == "") or updates/deletes one object.
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

// ClassicUpdate PUTs a Classic API document (setting, networkconf, wlanconf, device).
type ClassicUpdate struct {
	Label  string
	Path   string
	Body   obj
	Before obj
	Paths  []string
}

// Applicable reports whether the plan has changes the API can make; the mDNS
// network list is the one change left to the UI.
func (p *Plan) Applicable() bool {
	return len(p.Zones) > 0 || len(p.Lists) > 0 || len(p.Policies) > 0 ||
		len(p.DeletePolicies) > 0 || len(p.Orders) > 0 || p.MDNSMode != nil || len(p.ClassicUpdates) > 0
}

func (p *Plan) Empty() bool {
	return !p.Applicable() && p.MDNSNetworks == nil
}

// newPrefix marks the stand-in ID of an object the plan would create, so later
// steps (policy resolution, ordering) can be planned before it exists.
const newPrefix = "new:"

func buildPlan(d *Declarations, s *State) (*Plan, error) {
	p := &Plan{}
	names := Names{
		Zones:    maps.Clone(s.Names.Zones),
		Networks: maps.Clone(s.Names.Networks),
		Lists:    maps.Clone(s.Names.Lists),
	}

	if err := planZones(d, s, &names, p); err != nil {
		return nil, err
	}

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

	zoneName := invert(names.Zones)
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

	deletedIDs := map[string]bool{}
	for _, ap := range d.AbsentPolicies {
		name, _ := ap["name"].(string)
		key := policyKey(name, sideField(ap, "source", "zone"), sideField(ap, "destination", "zone"))
		if got, ok := livePol[key]; ok {
			id, _ := got["id"].(string)
			deletedIDs[id] = true
			p.DeletePolicies = append(p.DeletePolicies, Change{Label: "policy " + key, ID: id, Before: got})
		}
	}

	for _, pr := range pairs {
		cur := s.Orders[[2]string{pr.src, pr.dst}]
		want := desiredOrder(cur, declared[pr], deletedIDs)
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

	if err := planSettings(d, s, p); err != nil {
		return nil, err
	}
	return p, nil
}

func planZones(d *Declarations, s *State, names *Names, p *Plan) error {
	if len(d.Zones) == 0 {
		return nil
	}
	liveZones := map[string]obj{}
	for _, z := range s.Zones {
		name, _ := z["name"].(string)
		liveZones[name] = z
	}
	for _, z := range d.Zones {
		netIDs := make([]any, 0, len(z.Networks))
		for _, netName := range z.Networks {
			id, ok := names.Networks[netName]
			if !ok {
				return fmt.Errorf("zone %q: unknown network %q", z.Name, netName)
			}
			netIDs = append(netIDs, id)
		}
		body := obj{"name": z.Name, "networkIds": netIDs}
		label := fmt.Sprintf("zone %q", z.Name)
		got, ok := liveZones[z.Name]
		if !ok {
			names.Zones[z.Name] = newPrefix + z.Name
			p.Zones = append(p.Zones, Change{Label: label, Body: body})
			continue
		}
		cur := obj{"name": got["name"], "networkIds": nonNilSlice(got["networkIds"])}
		if paths := diffPaths(cur, body); len(paths) > 0 {
			id, _ := got["id"].(string)
			p.Zones = append(p.Zones, Change{Label: label, ID: id, Body: body, Before: got, Paths: paths})
		}
	}
	return nil
}

func nonNilSlice(v any) []any {
	if s, ok := v.([]any); ok && s != nil {
		return s
	}
	return []any{}
}

func planSettings(d *Declarations, s *State, p *Plan) error {
	for _, key := range slices.Sorted(maps.Keys(d.Settings.Settings)) {
		live, ok := s.ClassicSettings[key]
		if !ok {
			return fmt.Errorf("settings.json: unknown setting %q", key)
		}
		desired, err := resolveSettingDecl(key, d.Settings.Settings[key], s)
		if err != nil {
			return fmt.Errorf("settings.json setting %q: %w", key, err)
		}
		if paths := diffSelectedKeys(live, desired); len(paths) > 0 {
			merged := deepCopy(live).(obj)
			for k, v := range desired {
				merged[k] = deepCopy(v)
			}
			p.ClassicUpdates = append(p.ClassicUpdates, ClassicUpdate{
				Label:  fmt.Sprintf("setting %q", key),
				Path:   "/rest/setting/" + key,
				Body:   merged,
				Before: live,
				Paths:  paths,
			})
		}
	}

	for _, name := range slices.Sorted(maps.Keys(d.Settings.Networks)) {
		live, ok := s.ClassicNetworksByName[name]
		if !ok {
			return fmt.Errorf("settings.json: unknown network %q", name)
		}
		desired := deepCopy(d.Settings.Networks[name]).(obj)
		if paths := diffSelectedKeys(live, desired); len(paths) > 0 {
			merged := deepCopy(live).(obj)
			for k, v := range desired {
				merged[k] = deepCopy(v)
			}
			id, _ := live["_id"].(string)
			p.ClassicUpdates = append(p.ClassicUpdates, ClassicUpdate{
				Label:  fmt.Sprintf("network %q", name),
				Path:   "/rest/networkconf/" + id,
				Body:   merged,
				Before: live,
				Paths:  paths,
			})
		}
	}

	for _, name := range slices.Sorted(maps.Keys(d.Settings.WLANs)) {
		live, ok := s.WLANs[name]
		if !ok {
			return fmt.Errorf("settings.json: unknown wlan %q", name)
		}
		desired := deepCopy(d.Settings.WLANs[name]).(obj)
		if paths := diffSelectedKeys(live, desired); len(paths) > 0 {
			merged := deepCopy(live).(obj)
			for k, v := range desired {
				merged[k] = deepCopy(v)
			}
			id, _ := live["_id"].(string)
			p.ClassicUpdates = append(p.ClassicUpdates, ClassicUpdate{
				Label:  fmt.Sprintf("wlan %q", name),
				Path:   "/rest/wlanconf/" + id,
				Body:   merged,
				Before: live,
				Paths:  paths,
			})
		}
	}

	for _, name := range slices.Sorted(maps.Keys(d.Settings.Devices)) {
		live, ok := s.Devices[name]
		if !ok {
			return fmt.Errorf("settings.json: unknown device %q", name)
		}
		payload, paths, err := buildDevicePayload(live, d.Settings.Devices[name])
		if err != nil {
			return fmt.Errorf("settings.json device %q: %w", name, err)
		}
		if len(payload) > 0 {
			id, _ := live["_id"].(string)
			p.ClassicUpdates = append(p.ClassicUpdates, ClassicUpdate{
				Label:  fmt.Sprintf("device %q", name),
				Path:   "/rest/device/" + id,
				Body:   payload,
				Before: live,
				Paths:  paths,
			})
		}
	}
	return nil
}

func resolveSettingDecl(key string, decl obj, s *State) (obj, error) {
	desired := deepCopy(decl).(obj)
	if key != "igmp_snooping" {
		return desired, nil
	}
	if err := resolveClassicNetList(desired, "networks", "network_ids", s.ClassicNetworks); err != nil {
		return nil, err
	}
	if err := resolveClassicNetList(desired, "fastleave_networks", "fastleave_for_network_ids", s.ClassicNetworks); err != nil {
		return nil, err
	}
	if err := resolveDeviceMAC(desired, "primary_querier_device", "primary_querier", s.Devices); err != nil {
		return nil, err
	}
	if err := resolveDeviceMAC(desired, "failover_querier_device", "failover_querier", s.Devices); err != nil {
		return nil, err
	}
	return desired, nil
}

func resolveClassicNetList(m obj, srcKey, dstKey string, nets map[string]string) error {
	raw, ok := m[srcKey]
	if !ok {
		return nil
	}
	list, ok := raw.([]any)
	if !ok {
		return fmt.Errorf("%s must be a list", srcKey)
	}
	ids := make([]any, 0, len(list))
	for _, x := range list {
		name, _ := x.(string)
		id, ok := nets[name]
		if !ok {
			return fmt.Errorf("unknown network %q", name)
		}
		ids = append(ids, id)
	}
	delete(m, srcKey)
	m[dstKey] = ids
	return nil
}

func resolveDeviceMAC(m obj, srcKey, dstKey string, devs map[string]obj) error {
	raw, ok := m[srcKey]
	if !ok {
		return nil
	}
	name, _ := raw.(string)
	dev, ok := devs[name]
	if !ok {
		return fmt.Errorf("unknown device %q", name)
	}
	mac, _ := dev["mac"].(string)
	if mac == "" {
		return fmt.Errorf("device %q has no mac", name)
	}
	delete(m, srcKey)
	m[dstKey] = mac
	return nil
}

func diffSelectedKeys(live, desired obj) []string {
	subset := obj{}
	for k := range desired {
		if v, ok := live[k]; ok {
			subset[k] = v
		}
	}
	return diffPaths(subset, desired)
}

func buildDevicePayload(live, decl obj) (obj, []string, error) {
	payload := obj{}
	var paths []string

	scalars := obj{}
	for k, v := range decl {
		if k == "config_network" || k == "port_overrides" || k == "radio_overrides" {
			continue
		}
		scalars[k] = v
	}
	if len(scalars) > 0 {
		for _, k := range diffSelectedKeys(live, scalars) {
			payload[k] = deepCopy(scalars[k])
			paths = append(paths, k)
		}
	}

	if cfgDecl, ok := decl["config_network"].(obj); ok {
		liveCfg, _ := live["config_network"].(obj)
		if liveCfg == nil {
			liveCfg = obj{}
		}
		if subPaths := diffSelectedKeys(liveCfg, cfgDecl); len(subPaths) > 0 {
			mergedCfg := deepCopy(liveCfg).(obj)
			for k, v := range cfgDecl {
				mergedCfg[k] = deepCopy(v)
			}
			payload["config_network"] = mergedCfg
			for _, sp := range subPaths {
				paths = append(paths, "config_network."+sp)
			}
		}
	}

	if portDecl, ok := decl["port_overrides"].([]any); ok {
		livePorts := nonNilSlice(live["port_overrides"])
		mergedPorts := deepCopy(livePorts).([]any)
		for _, rawOv := range portDecl {
			ov, ok := rawOv.(obj)
			if !ok {
				return nil, nil, fmt.Errorf("port_overrides entry must be an object")
			}
			idxEnc := encode(ov["port_idx"])
			matched := false
			for i, rawLP := range mergedPorts {
				lp, _ := rawLP.(obj)
				if encode(lp["port_idx"]) != idxEnc {
					continue
				}
				matched = true
				for k, v := range ov {
					if k == "unset" {
						continue
					}
					lp[k] = deepCopy(v)
				}
				if unset, ok := ov["unset"].([]any); ok {
					for _, u := range unset {
						if uk, _ := u.(string); uk != "" {
							delete(lp, uk)
						}
					}
				}
				mergedPorts[i] = lp
			}
			if !matched {
				return nil, nil, fmt.Errorf("port_overrides: port_idx %s not found", idxEnc)
			}
		}
		if encode(canonical(livePorts)) != encode(canonical(mergedPorts)) {
			payload["port_overrides"] = mergedPorts
			paths = append(paths, "port_overrides")
		}
	}

	if radioDecl, ok := decl["radio_overrides"].([]any); ok {
		liveRadios := nonNilSlice(live["radio_table"])
		mergedRadios := deepCopy(liveRadios).([]any)
		for _, rawOv := range radioDecl {
			ov, ok := rawOv.(obj)
			if !ok {
				return nil, nil, fmt.Errorf("radio_overrides entry must be an object")
			}
			band, _ := ov["radio"].(string)
			if band == "" {
				return nil, nil, fmt.Errorf("radio_overrides entry requires radio band")
			}
			matched := false
			for i, rawR := range mergedRadios {
				r, _ := rawR.(obj)
				if r["radio"] != band {
					continue
				}
				matched = true
				for k, v := range ov {
					if k == "radio" {
						continue
					}
					r[k] = deepCopy(v)
				}
				mergedRadios[i] = r
			}
			if !matched {
				return nil, nil, fmt.Errorf("radio_overrides: radio band %q not found", band)
			}
		}
		if encode(canonical(liveRadios)) != encode(canonical(mergedRadios)) {
			payload["radio_table"] = mergedRadios
			paths = append(paths, "radio_table")
		}
	}

	slices.Sort(paths)
	return payload, paths, nil
}

// desiredOrder puts the declared policies first, in declaration order, ahead
// of every system-defined policy. Undeclared user policies keep their current
// relative order behind them (CONTEXT.md Q28); deletedIDs are removed.
func desiredOrder(cur Ordering, declared []string, deletedIDs map[string]bool) Ordering {
	isDeclared := map[string]bool{}
	for _, id := range declared {
		isDeclared[id] = true
	}
	out := Ordering{Before: slices.Clone(declared), After: []string{}}
	for _, id := range cur.Before {
		if !isDeclared[id] && !deletedIDs[id] {
			out.Before = append(out.Before, id)
		}
	}
	for _, id := range cur.After {
		if !isDeclared[id] && !deletedIDs[id] {
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
	for _, c := range slices.Concat(p.Zones, p.Lists, p.Policies) {
		if c.ID == "" {
			fmt.Fprintf(w, "+ create %s\n", c.Label)
		} else {
			fmt.Fprintf(w, "~ update %s: %s\n", c.Label, strings.Join(c.Paths, ", "))
		}
	}
	for _, c := range p.DeletePolicies {
		fmt.Fprintf(w, "- delete %s\n", c.Label)
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
	for _, u := range p.ClassicUpdates {
		fmt.Fprintf(w, "~ update %s: %s\n", u.Label, strings.Join(u.Paths, ", "))
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
